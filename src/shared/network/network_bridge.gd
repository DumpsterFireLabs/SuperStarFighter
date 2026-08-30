class_name NetworkBridge
extends Node

const ProjectileCorrectionAssemblerScript = preload("res://src/shared/network/projectile_correction_assembler.gd")

signal server_peer_admitted(peer_id: int, player: PlayerMatchState)
signal server_peer_departed(peer_id: int)
signal client_connected(peer_id: int)
signal client_lobby_updated(state: Dictionary)
signal client_match_event_received(event_type: StringName, server_tick: int, payload: Dictionary)
signal client_snapshot_received(decoded: Dictionary)
signal client_projectile_batch_received(decoded: Dictionary)
signal client_projectile_correction_received(decoded: Dictionary)
signal client_rejected(reason: StringName, message: String)
signal client_connection_lost(message: String)

enum Role {
	NONE,
	SERVER,
	CLIENT,
}

var role: Role = Role.NONE
var lobby: ServerLobby
var world: AuthoritativeWorld
var match_coordinator: AuthoritativeMatchCoordinator
var npc_controller := NpcPilotController.new()
var local_peer_id: int = 0
var latest_lobby_state: Dictionary = {}
var last_error: String = ""

var _configuration: Dictionary = {}
var _enet_peer: ENetMultiplayerPeer
var _lan_discovery: LanDiscoveryService
var _pending_handshakes := HandshakeRegistry.new()
var _pending_disconnects: Dictionary = {}
var _rate_limiter := InputRateLimiter.new()
var _control_rate_limiter := RequestRateLimiter.new()
var _malformed_control_strikes: Dictionary = {}
var _client_name: String = "Pilot"
var _client_protocol_version: int = GameConstants.PROTOCOL_VERSION
var _last_metrics_tick: int = 0
var _simulation_total_usec: int = 0
var _simulation_max_usec: int = 0
var _simulation_samples: int = 0
var _simulation_sample_usec: Array[int] = []
var _outbound_bytes: int = 0
var _metrics_window: int = 0
var _logged_overtime_key: String = ""
var _discovery_instance_id: String = ""
var _projectile_message_sequence: int = 0
var _projectile_correction_cursor: int = 0
var _projectile_correction_send_count: int = 0
var _projectile_correction_assembler := ProjectileCorrectionAssemblerScript.new()

const PARTIAL_PROJECTILE_CORRECTION_COUNT: int = 40


func start_server(configuration: Dictionary) -> Error:
	stop()
	role = Role.SERVER
	_configuration = configuration.duplicate(true)
	var match_config := MatchConfig.new()
	match_config.port = int(configuration.get("port", GameConstants.DEFAULT_PORT))
	if match_config.port == LanDiscoveryProtocol.DISCOVERY_PORT:
		last_error = "UDP port %d is reserved for LAN server discovery." % LanDiscoveryProtocol.DISCOVERY_PORT
		role = Role.NONE
		return ERR_INVALID_PARAMETER
	match_config.max_players = int(configuration.get("max_players", GameConstants.DEFAULT_MAX_PLAYERS))
	match_config.rounds_to_win = int(configuration.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN))
	if bool(configuration.get("test_fast_match", false)):
		match_config.draft_duration_seconds = 0.75
		match_config.countdown_duration_seconds = 0.25
		match_config.heat_result_duration_seconds = 0.25
		match_config.round_result_duration_seconds = 0.25
	lobby = ServerLobby.new(match_config)
	world = AuthoritativeWorld.new()
	match_coordinator = null
	_reset_metrics_window()
	_metrics_window = 0
	_logged_overtime_key = ""
	_discovery_instance_id = "%x-%x" % [Time.get_ticks_msec(), get_instance_id()]
	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_server(match_config.port, match_config.max_players + 1, NetworkProtocol.CHANNEL_COUNT)
	if error != OK:
		last_error = "Could not bind UDP port %d (error %d)." % [match_config.port, error]
		_log("error", "server_bind_failed", {"port": match_config.port, "error": error})
		role = Role.NONE
		return error
	multiplayer.multiplayer_peer = _enet_peer
	if not multiplayer.peer_connected.is_connected(_on_server_peer_connected):
		multiplayer.peer_connected.connect(_on_server_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_server_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_server_peer_disconnected)
	_lan_discovery = LanDiscoveryService.new()
	_lan_discovery.name = "LanDiscoveryResponder"
	add_child(_lan_discovery)
	var discovery_error := _lan_discovery.start_responder(_lan_discovery_payload)
	if discovery_error != OK:
		_log("warning", "lan_discovery_unavailable", {
			"port": LanDiscoveryProtocol.DISCOVERY_PORT,
			"error": discovery_error,
		})
	_log("info", "server_started", {
		"port": match_config.port,
		"max_players": match_config.max_players,
		"rounds_to_win": match_config.rounds_to_win,
	})
	return OK


func start_client(
	host: String,
	port: int,
	display_name: String,
	protocol_version: int = GameConstants.PROTOCOL_VERSION
) -> Error:
	stop()
	role = Role.CLIENT
	_client_name = display_name
	_client_protocol_version = protocol_version
	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_client(host, port, NetworkProtocol.CHANNEL_COUNT)
	if error != OK:
		last_error = "Could not connect to %s:%d (error %d)." % [host, port, error]
		role = Role.NONE
		return error
	multiplayer.multiplayer_peer = _enet_peer
	if not multiplayer.connected_to_server.is_connected(_on_client_transport_connected):
		multiplayer.connected_to_server.connect(_on_client_transport_connected)
	if not multiplayer.connection_failed.is_connected(_on_client_connection_failed):
		multiplayer.connection_failed.connect(_on_client_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_client_server_disconnected):
		multiplayer.server_disconnected.connect(_on_client_server_disconnected)
	return OK


func stop() -> void:
	# Mark teardown before closing ENet. Closing a live client can synchronously emit
	# server_disconnected; that callback must see NONE instead of recursively
	# entering the UI's disconnect path while this cleanup is still in progress.
	var stopped_role := role
	role = Role.NONE
	if stopped_role == Role.SERVER and _enet_peer != null:
		_log("info", "server_shutdown", {
			"connected_peers": lobby.human_count() if lobby != null else 0,
			"participant_records": lobby.players.size() if lobby != null else 0,
			"active_ships": world.combatants.size() if world != null else 0,
			"active_projectiles": world.projectile_registry.size() if world != null else 0,
			"pending_handshakes": _pending_handshakes.size(),
		})
	if _enet_peer != null:
		_enet_peer.close()
	_enet_peer = null
	if _lan_discovery != null:
		_lan_discovery.stop()
		_lan_discovery.queue_free()
		_lan_discovery = null
	if is_inside_tree() and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending_handshakes.clear()
	_pending_disconnects.clear()
	_rate_limiter.clear()
	_control_rate_limiter.clear()
	_malformed_control_strikes.clear()
	_projectile_message_sequence = 0
	_projectile_correction_cursor = 0
	_projectile_correction_send_count = 0
	_projectile_correction_assembler.clear()
	local_peer_id = 0
	latest_lobby_state.clear()
	match_coordinator = null
	npc_controller.clear()


func _lan_discovery_payload() -> Dictionary:
	return {
		"instance_id": _discovery_instance_id,
		"protocol_version": GameConstants.PROTOCOL_VERSION,
		"server_name": String(_configuration.get("server_name", "Super Star Fighter Server")),
		"game_port": int(_configuration.get("port", GameConstants.DEFAULT_PORT)),
		"human_count": lobby.human_count() if lobby != null else 0,
		"npc_count": lobby.npc_count() if lobby != null else 0,
		"player_limit": lobby.player_limit if lobby != null else int(_configuration.get("max_players", GameConstants.DEFAULT_MAX_PLAYERS)),
		"match_active": lobby.match_active if lobby != null else false,
	}


func flush_metrics() -> void:
	if role == Role.SERVER and _simulation_samples > 0 and lobby != null and lobby.match_active:
		_log_metrics()


func get_round_trip_time_ms() -> int:
	if role != Role.CLIENT or _enet_peer == null:
		return -1
	var server_peer := _enet_peer.get_peer(NetworkProtocol.SERVER_PEER_ID)
	if server_peer == null:
		return -1
	return int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func send_input(frame: PlayerInputFrame) -> void:
	if role != Role.CLIENT or local_peer_id == 0:
		return
	var packet := InputPacketCodec.encode(frame)
	submit_input.rpc_id(NetworkProtocol.SERVER_PEER_ID, packet)


func send_lobby_config(rounds_to_win: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_lobby_config.rpc_id(NetworkProtocol.SERVER_PEER_ID, rounds_to_win)


func send_player_limit(player_limit: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_player_limit.rpc_id(NetworkProtocol.SERVER_PEER_ID, player_limit)


func send_npcs_enabled(enabled: bool) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_npcs_enabled.rpc_id(NetworkProtocol.SERVER_PEER_ID, enabled)


func send_game_mode(mode: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_game_mode.rpc_id(NetworkProtocol.SERVER_PEER_ID, mode)


func send_team_count(team_count: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_team_count.rpc_id(NetworkProtocol.SERVER_PEER_ID, team_count)


func send_team_assignment(peer_id: int, team_selection: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_team_assignment.rpc_id(NetworkProtocol.SERVER_PEER_ID, peer_id, team_selection)


func send_random_spawn_powerups(enabled: bool) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_random_spawn_powerups.rpc_id(NetworkProtocol.SERVER_PEER_ID, enabled)


func send_player_color(random_color: bool, color: Color) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_player_color.rpc_id(NetworkProtocol.SERVER_PEER_ID, random_color, color.to_html(false))


func send_npc_difficulty(npc_peer_id: int, difficulty: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_npc_difficulty.rpc_id(NetworkProtocol.SERVER_PEER_ID, npc_peer_id, difficulty)


func send_all_npc_difficulty(difficulty: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_all_npc_difficulty.rpc_id(NetworkProtocol.SERVER_PEER_ID, difficulty)


func send_random_powerup_interval(seconds: float) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_random_powerup_interval.rpc_id(NetworkProtocol.SERVER_PEER_ID, seconds)


func send_random_powerups_permanent(permanent: bool) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_random_powerups_permanent.rpc_id(NetworkProtocol.SERVER_PEER_ID, permanent)


func send_overtime_start(seconds: float) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_overtime_start.rpc_id(NetworkProtocol.SERVER_PEER_ID, seconds)


func send_ready_state(ready: bool) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_ready_state.rpc_id(NetworkProtocol.SERVER_PEER_ID, ready)


func send_eject_player(peer_id: int) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_eject_player.rpc_id(NetworkProtocol.SERVER_PEER_ID, peer_id)


func send_start_match() -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_start_match.rpc_id(NetworkProtocol.SERVER_PEER_ID)


func send_return_to_lobby() -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_return_to_lobby.rpc_id(NetworkProtocol.SERVER_PEER_ID)


func send_extend_match() -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_extend_match.rpc_id(NetworkProtocol.SERVER_PEER_ID)


func send_card_selection(offer_token: String, card_id: StringName) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		select_card.rpc_id(NetworkProtocol.SERVER_PEER_ID, offer_token, String(card_id))


func send_test_input_packet(packet: PackedByteArray) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		submit_input.rpc_id(NetworkProtocol.SERVER_PEER_ID, packet)


func _physics_process(delta: float) -> void:
	if role != Role.SERVER or world == null:
		return
	var start_usec := Time.get_ticks_usec()
	_process_pending_connections()
	if match_coordinator != null and match_coordinator.controls_enabled():
		npc_controller.submit_inputs(
			world,
			lobby.npc_peer_ids_view(),
			lobby.npc_difficulties_view(),
			match_coordinator.npc_overtime_elapsed(),
			match_coordinator.npc_objective_state()
		)
	world.step(delta, match_coordinator != null and match_coordinator.controls_enabled())
	if match_coordinator != null:
		match_coordinator.step(delta)
		_drain_match_coordinator()
		_log_overtime_if_needed()
		if match_coordinator.is_finished():
			match_coordinator = null
			_broadcast_lobby_state()
	var tick := world.server_tick
	if tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PLAYER_SNAPSHOT_RATE) == 0:
		_send_player_snapshots()
	_send_projectile_batch()
	if tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PROJECTILE_CORRECTION_RATE) == 0:
		_send_projectile_correction()
	var duration_usec := Time.get_ticks_usec() - start_usec
	_simulation_total_usec += duration_usec
	_simulation_max_usec = maxi(_simulation_max_usec, duration_usec)
	_simulation_samples += 1
	_simulation_sample_usec.append(duration_usec)
	if tick - _last_metrics_tick >= GameConstants.PHYSICS_TICKS_PER_SECOND * 10:
		if lobby != null and lobby.match_active:
			_log_metrics()
		else:
			_reset_metrics_window()
		_last_metrics_tick = tick


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func client_hello(protocol_version: int, display_name: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _pending_handshakes.has(sender_id):
		_reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	var rejection := ConnectionAdmission.validate_hello(
		protocol_version,
		display_name,
		lobby.players.size() if lobby.match_active else lobby.human_count(),
		lobby.player_limit
	)
	if not rejection.is_empty():
		_reject_connection(sender_id, rejection)
		return
	var result := lobby.admit(sender_id, display_name)
	if not result.ok:
		_reject_connection(sender_id, result.reason)
		return
	_pending_handshakes.complete(sender_id)
	_remove_npc_entities(result.get("removed_npc_ids", []) as Array)
	var player := result.player as PlayerMatchState
	world.add_peer(sender_id)
	if match_coordinator != null:
		match_coordinator.add_late_spectator(player)
	server_welcome.rpc_id(sender_id, sender_id, lobby.serialize())
	if match_coordinator != null:
		match_event.rpc_id(
			sender_id,
			&"STATE_CHANGED",
			world.server_tick,
			match_coordinator.current_state_payload()
		)
	_outbound_bytes += 64
	_broadcast_lobby_state()
	server_peer_admitted.emit(sender_id, player)
	_log("info", "peer_joined", {"peer_id": sender_id, "display_name": player.display_name, "spectator": player.spectator})
	if bool(_configuration.get("auto_start", false)) and lobby.participant_count() >= GameConstants.MIN_PLAYERS and not lobby.match_active:
		for peer_id in lobby.human_peer_ids():
			lobby.request_ready(peer_id, true)
		var start_result := lobby.request_start(lobby.leader_id)
		if start_result.ok:
			_activate_added_npcs(start_result)
			_broadcast_lobby_state()
			_start_match_coordinator(lobby.leader_id)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_lobby_config(rounds_to_win: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "lobby_config"):
		return
	var result := lobby.request_rounds_to_win(sender_id, rounds_to_win)
	if result.ok:
		_broadcast_lobby_state()
	else:
		_send_request_rejected(sender_id, result.error)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_player_limit(player_limit: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "player_limit"):
		return
	var result := lobby.request_player_limit(sender_id, player_limit)
	if result.ok:
		_remove_npc_entities(result.get("removed_npc_ids", []) as Array)
		_activate_added_npcs(result)
		_broadcast_lobby_state()
	else:
		_send_request_rejected(sender_id, result.error)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_npcs_enabled(enabled: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "npcs_enabled"):
		return
	var result := lobby.request_npcs_enabled(sender_id, enabled)
	if result.ok:
		_remove_npc_entities(result.get("removed_npc_ids", []) as Array)
		_activate_added_npcs(result)
		_broadcast_lobby_state()
	else:
		_send_request_rejected(sender_id, result.error)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_game_mode(mode: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "game_mode"):
		return
	var result := lobby.request_game_mode(sender_id, mode)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_team_count(team_count: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "team_count"):
		return
	var result := lobby.request_team_count(sender_id, team_count)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_team_assignment(peer_id: int, team_selection: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "team_assignment"):
		return
	var result := lobby.request_team_assignment(sender_id, peer_id, team_selection)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_random_spawn_powerups(enabled: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "random_spawn_powerups"):
		return
	var result := lobby.request_random_spawn_powerups(sender_id, enabled)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_player_color(random_color: bool, color_value: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "player_color"):
		return
	if color_value.length() > 7:
		_reject_malformed_control(sender_id, "oversized_player_color")
		return
	var result := lobby.request_player_color(sender_id, random_color, color_value)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_npc_difficulty(npc_peer_id: int, difficulty: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "npc_difficulty"):
		return
	var result := lobby.request_npc_difficulty(sender_id, npc_peer_id, difficulty)
	if result.ok:
		if bool(result.get("changed", false)):
			_broadcast_lobby_state()
	else:
		_send_request_rejected(sender_id, result.error)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_all_npc_difficulty(difficulty: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "all_npc_difficulty"):
		return
	var result := lobby.request_all_npc_difficulty(sender_id, difficulty)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_random_powerup_interval(seconds: float) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "random_powerup_interval"):
		return
	var result := lobby.request_random_powerup_interval(sender_id, seconds)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_random_powerups_permanent(permanent: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "random_powerups_permanent"):
		return
	var result := lobby.request_random_powerups_permanent(sender_id, permanent)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_overtime_start(seconds: float) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "overtime_start"):
		return
	var result := lobby.request_overtime_start(sender_id, seconds)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_ready_state(ready: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "ready_state"):
		return
	var result := lobby.request_ready(sender_id, ready)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_eject_player(target_peer_id: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "eject_player"):
		return
	var result := lobby.request_eject(sender_id, target_peer_id)
	if not result.ok:
		_send_request_rejected(sender_id, result.error)
		return
	if world != null:
		world.remove_peer(target_peer_id)
	_rate_limiter.remove_peer(target_peer_id)
	_control_rate_limiter.remove_peer(target_peer_id)
	_malformed_control_strikes.erase(target_peer_id)
	_pending_handshakes.complete(target_peer_id)
	_activate_added_npcs(result)
	var reason := NetworkProtocol.REJECT_EJECTED
	connection_rejected.rpc_id(target_peer_id, reason, NetworkProtocol.rejection_message(reason))
	_pending_disconnects[target_peer_id] = _now_seconds() + 0.1
	_broadcast_lobby_state()
	server_peer_departed.emit(target_peer_id)
	_log("info", "peer_ejected", {"leader_id": sender_id, "peer_id": target_peer_id})


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_start_match() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "start_match"):
		return
	var result := lobby.request_start(sender_id)
	if result.ok:
		_activate_added_npcs(result)
		_broadcast_lobby_state()
		_start_match_coordinator(sender_id)
	else:
		_send_request_rejected(sender_id, result.error)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_return_to_lobby() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "return_to_lobby"):
		return
	if sender_id != lobby.leader_id:
		_send_request_rejected(sender_id, "Only the lobby leader may return the match to the lobby.")
		return
	if match_coordinator == null or not match_coordinator.return_to_lobby():
		_send_request_rejected(sender_id, "Return to lobby is only available from the final results screen.")
		return
	_drain_match_coordinator()
	if match_coordinator.is_finished():
		match_coordinator = null
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_extend_match() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "extend_match"):
		return
	if sender_id != lobby.leader_id:
		_send_request_rejected(sender_id, "Only the lobby leader may extend the match.")
		return
	if match_coordinator == null or not match_coordinator.extend_match():
		_send_request_rejected(sender_id, "Match extension is only available from final results with at least two competing participants.")
		return
	_drain_match_coordinator()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func select_card(offer_token: String, card_id: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "select_card"):
		return
	if offer_token.length() > NetworkProtocol.MAX_OFFER_TOKEN_LENGTH or card_id.length() > NetworkProtocol.MAX_CARD_ID_LENGTH:
		_reject_malformed_control(sender_id, "oversized_card_selection")
		return
	if match_coordinator == null:
		_send_request_rejected(sender_id, "Card selection is only accepted during the authoritative draft state.")
		return
	var result := match_coordinator.select_card(sender_id, offer_token, StringName(card_id))
	if result != DraftManager.SelectionResult.ACCEPTED:
		var result_name: String = String(DraftManager.SelectionResult.keys()[result])
		_send_request_rejected(sender_id, "Card selection rejected: %s." % result_name.to_lower())
		_log("warning", "card_selection_rejected", {
			"peer_id": sender_id,
			"selection_result": result_name,
			"card_id": card_id,
		})
	_drain_match_coordinator()


@rpc("any_peer", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_INPUT)
func submit_input(packet: PackedByteArray) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not lobby.players.has(sender_id):
		_reject_request(sender_id, "input_before_handshake")
		return
	var decoded := InputPacketCodec.decode(packet)
	var decision := _rate_limiter.register(sender_id, _now_seconds(), decoded.ok)
	if decision == InputRateLimiter.Decision.DISCONNECT:
		_log("warning", "traffic_peer_isolated", {"peer_id": sender_id, "traffic": "input", "detail": decoded.get("error", "rate_limit")})
		_reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	if decision != InputRateLimiter.Decision.ACCEPT or not decoded.ok:
		return
	world.submit_input(sender_id, decoded.frame)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func server_welcome(peer_id: int, lobby_state_value: Dictionary) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	local_peer_id = peer_id
	latest_lobby_state = lobby_state_value
	client_connected.emit(peer_id)
	client_lobby_updated.emit(lobby_state_value)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func connection_rejected(reason: StringName, display_message: String) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	last_error = display_message
	client_rejected.emit(reason, display_message)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func lobby_state(state: Dictionary) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var incoming_revision := int(state.get("revision", 0))
	var current_revision := int(latest_lobby_state.get("revision", 0))
	if not latest_lobby_state.is_empty() and not SequenceMath.is_newer(incoming_revision, current_revision):
		return
	latest_lobby_state = state
	client_lobby_updated.emit(state)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func draft_offer(offer_token: String, card_ids: Array[StringName], deadline_tick: int) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	client_match_event_received.emit(&"DRAFT_OFFER", deadline_tick, {"offer_token": offer_token, "card_ids": card_ids})


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func match_event(event_type: StringName, server_tick_value: int, payload: Dictionary) -> void:
	if role == Role.CLIENT and multiplayer.get_remote_sender_id() == NetworkProtocol.SERVER_PEER_ID:
		client_match_event_received.emit(event_type, server_tick_value, payload)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_OBJECTIVE)
func objective_snapshot(server_tick_value: int, payload: Dictionary) -> void:
	if role == Role.CLIENT and multiplayer.get_remote_sender_id() == NetworkProtocol.SERVER_PEER_ID:
		client_match_event_received.emit(&"OBJECTIVE_UPDATED", server_tick_value, payload)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_SNAPSHOT)
func world_snapshot(packet: PackedByteArray) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var decoded := PlayerSnapshotCodec.decode(packet)
	if decoded.ok:
		client_snapshot_received.emit(decoded)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_SNAPSHOT)
func projectile_batch(packet: PackedByteArray) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var decoded := ProjectilePacketCodec.decode_batch(packet)
	if decoded.ok and int(decoded.kind) == ProjectilePacketCodec.KIND_DELTA:
		client_projectile_batch_received.emit(decoded)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_SNAPSHOT)
func projectile_correction(packet: PackedByteArray) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var decoded := ProjectilePacketCodec.decode_correction(packet)
	if decoded.ok:
		_accept_projectile_correction_chunk(decoded)


func _on_server_peer_connected(peer_id: int) -> void:
	_pending_handshakes.begin(peer_id, _now_seconds())


func _on_server_peer_disconnected(peer_id: int) -> void:
	_pending_handshakes.complete(peer_id)
	_pending_disconnects.erase(peer_id)
	_rate_limiter.remove_peer(peer_id)
	_control_rate_limiter.remove_peer(peer_id)
	_malformed_control_strikes.erase(peer_id)
	if match_coordinator != null:
		match_coordinator.disconnect_peer(peer_id)
		_drain_match_coordinator()
	var departed := lobby.remove(peer_id) if lobby != null else null
	var replacement_npcs: Array[PlayerMatchState] = []
	if departed != null and match_coordinator == null:
		replacement_npcs = lobby.restore_npc_fill()
		_activate_added_npcs({"added_npcs": replacement_npcs})
	if world != null:
		world.remove_peer(peer_id)
	if departed != null:
		_broadcast_lobby_state()
		server_peer_departed.emit(peer_id)
		_log("info", "peer_left", {"peer_id": peer_id})


func _on_client_transport_connected() -> void:
	client_hello.rpc_id(NetworkProtocol.SERVER_PEER_ID, _client_protocol_version, _client_name)


func _on_client_connection_failed() -> void:
	if role != Role.CLIENT:
		return
	last_error = "Could not reach the server."
	client_connection_lost.emit(last_error)


func _on_client_server_disconnected() -> void:
	if role != Role.CLIENT:
		return
	var message := last_error if not last_error.is_empty() else NetworkProtocol.rejection_message(NetworkProtocol.REJECT_SERVER_CLOSED)
	local_peer_id = 0
	client_connection_lost.emit(message)


func _process_pending_connections() -> void:
	var now := _now_seconds()
	for peer_id in _pending_handshakes.expired(now):
		_reject_connection(peer_id, NetworkProtocol.REJECT_HANDSHAKE_TIMEOUT)
	for peer_value in _pending_disconnects.keys():
		var peer_id := int(peer_value)
		if now >= float(_pending_disconnects[peer_id]):
			_pending_disconnects.erase(peer_id)
			if _enet_peer != null:
				_enet_peer.disconnect_peer(peer_id)


func _reject_connection(peer_id: int, reason: StringName) -> void:
	var message := NetworkProtocol.rejection_message(reason)
	connection_rejected.rpc_id(peer_id, reason, message)
	_pending_handshakes.complete(peer_id)
	_pending_disconnects[peer_id] = _now_seconds() + 0.1
	_log("warning", "connection_rejected", {"peer_id": peer_id, "reason": String(reason)})


func _reject_request(peer_id: int, detail: String) -> void:
	_send_request_rejected(peer_id, "The request was rejected by server authority.")
	_log("warning", "request_rejected", {"peer_id": peer_id, "detail": detail})


func _accept_control_request(peer_id: int, request_name: String) -> bool:
	if lobby == null or not lobby.players.has(peer_id):
		_log("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": "request_before_handshake"})
		_reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	var decision := _control_rate_limiter.register(peer_id, _now_seconds())
	if decision == RequestRateLimiter.Decision.DISCONNECT:
		_log("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": "%s_rate_limit" % request_name})
		_reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	return decision == RequestRateLimiter.Decision.ACCEPT


func _reject_malformed_control(peer_id: int, detail: String) -> void:
	var strikes := int(_malformed_control_strikes.get(peer_id, 0)) + 1
	_malformed_control_strikes[peer_id] = strikes
	if strikes >= NetworkProtocol.TRAFFIC_STRIKES_BEFORE_DISCONNECT:
		_log("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": detail})
		_reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	_reject_request(peer_id, detail)


func _send_request_rejected(peer_id: int, message_text: String) -> void:
	match_event.rpc_id(peer_id, &"REQUEST_REJECTED", world.server_tick if world != null else 0, {"message": message_text})


func _broadcast_lobby_state() -> void:
	if lobby == null:
		return
	var state := lobby.serialize()
	lobby_state.rpc(state)
	_outbound_bytes += JSON.stringify(state).length() * maxi(lobby.human_count(), 1)


func _broadcast_match_event(event_type: StringName, payload: Dictionary) -> void:
	var tick := world.server_tick if world != null else 0
	match_event.rpc(event_type, tick, payload)
	_log("info", "match_event", {"event_type": String(event_type), "server_tick": tick})


func _start_match_coordinator(leader_id: int) -> void:
	var configured_seed := int(_configuration.get("test_match_seed", 0))
	var seed_value := configured_seed if configured_seed > 0 else int(Time.get_unix_time_from_system())
	var overtime_start := 2.0 if bool(_configuration.get("test_fast_match", false)) else lobby.config.overtime_start_seconds
	match_coordinator = AuthoritativeMatchCoordinator.new(lobby, world, seed_value, overtime_start)
	_logged_overtime_key = ""
	if not match_coordinator.start(world.server_tick):
		match_coordinator = null
		lobby.return_to_lobby()
		_broadcast_lobby_state()
		_send_request_rejected(leader_id, "The match coordinator could not start.")
		return
	_log("info", "match_seed", {"seed": seed_value, "participants": lobby.participant_count()})
	_broadcast_match_event(&"MATCH_START_ACCEPTED", {"leader_id": leader_id, "match_seed": seed_value})
	_drain_match_coordinator()


func _activate_added_npcs(start_result: Dictionary) -> void:
	for player_value in start_result.get("added_npcs", []):
		var player := player_value as PlayerMatchState
		world.add_peer(player.peer_id)
		if not lobby.match_active:
			world.set_spectator(player.peer_id)
		_log("info", "npc_added", {
			"peer_id": player.peer_id,
			"display_name": player.display_name,
			"difficulty": NpcPilotController.difficulty_name(player.npc_difficulty),
		})


func _remove_npc_entities(peer_ids: Array) -> void:
	for peer_value in peer_ids:
		var peer_id := int(peer_value)
		world.remove_peer(peer_id)
		npc_controller.remove_peer(peer_id)
		_log("info", "npc_removed", {"peer_id": peer_id})


func _drain_match_coordinator() -> void:
	if match_coordinator == null:
		return
	for event_value in match_coordinator.drain_events():
		var event := event_value as Dictionary
		var event_type := event.event_type as StringName
		var server_tick_value := int(event.server_tick)
		var payload := event.payload as Dictionary
		if event_type == &"OBJECTIVE_UPDATED":
			objective_snapshot.rpc(server_tick_value, payload)
		else:
			match_event.rpc(event_type, server_tick_value, payload)
		if event_type != &"OBJECTIVE_UPDATED":
			_log("info", "match_event", {
				"event_type": String(event_type),
				"server_tick": server_tick_value,
				"state": payload.get("state_name", ""),
				"round": payload.get("round_number", 0),
				"heat": payload.get("heat_number", 0),
				"winner": payload.get("match_winner", 0),
			})
	for offer_value in match_coordinator.drain_private_offers():
		var offer := offer_value as Dictionary
		var peer_id := int(offer.peer_id)
		var player := lobby.players.get(peer_id) as PlayerMatchState
		if player != null and not player.is_npc:
			draft_offer.rpc_id(
				peer_id,
				String(offer.offer_token),
				offer.card_ids as Array[StringName],
				int(offer.deadline_tick)
			)


func _send_player_snapshots() -> void:
	if lobby == null or lobby.players.is_empty():
		return
	var body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view())
	for peer_id in lobby.human_peer_ids_view():
		var packet := PlayerSnapshotCodec.assemble(world.server_tick, world.acknowledged_input(peer_id), body)
		world_snapshot.rpc_id(peer_id, packet)
		_outbound_bytes += packet.size()


func _send_projectile_batch() -> void:
	var batch := world.drain_projectile_batch()
	if (batch.spawned as Array).is_empty() and (batch.removed as Array).is_empty():
		return
	var sequence := _next_projectile_message_sequence()
	var packets := ProjectilePacketCodec.encode_batch_chunks(
		world.server_tick,
		sequence,
		batch.spawned as Array[ProjectileState],
		batch.removed as Array[int]
	)
	for packet in packets:
		projectile_batch.rpc(packet)
		_outbound_bytes += packet.size() * maxi(lobby.human_count(), 1)


func _send_projectile_correction() -> void:
	if lobby == null or lobby.players.is_empty():
		return
	var complete_snapshot := _projectile_correction_send_count % GameConstants.PROJECTILE_CORRECTION_RATE == 0
	var active: Array[ProjectileState] = []
	if complete_snapshot:
		active = world.active_projectiles()
	else:
		var window := world.projectile_registry.projectile_window(
			_projectile_correction_cursor,
			PARTIAL_PROJECTILE_CORRECTION_COUNT
		)
		active = window.projectiles as Array[ProjectileState]
		_projectile_correction_cursor = int(window.next_slot)
	_projectile_correction_send_count += 1
	var sequence := _next_projectile_message_sequence()
	var packets := ProjectilePacketCodec.encode_correction_chunks(
		world.server_tick,
		sequence,
		active,
		complete_snapshot
	)
	for packet in packets:
		projectile_correction.rpc(packet)
		_outbound_bytes += packet.size() * lobby.human_count()


func _next_projectile_message_sequence() -> int:
	_projectile_message_sequence = (_projectile_message_sequence + 1) & 0xffff
	return _projectile_message_sequence


func _accept_projectile_correction_chunk(decoded: Dictionary) -> void:
	var assembled := _projectile_correction_assembler.accept(decoded)
	if not assembled.is_empty():
		client_projectile_correction_received.emit(assembled)


func _log_metrics() -> void:
	var mean_usec := 0.0
	if _simulation_samples > 0:
		mean_usec = float(_simulation_total_usec) / _simulation_samples
	_metrics_window += 1
	_log("info", "simulation_metrics", {
		"window": _metrics_window,
		"server_tick": world.server_tick if world != null else 0,
		"connected_peers": lobby.human_count() if lobby != null else 0,
		"npc_pilots": lobby.npc_count() if lobby != null else 0,
		"participant_records": lobby.players.size() if lobby != null else 0,
		"active_ships": world.combatants.size() if world != null else 0,
		"active_projectiles": world.projectile_registry.size() if world != null else 0,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"mean_simulation_usec": mean_usec,
		"p95_simulation_usec": percentile_usec(_simulation_sample_usec, 0.95),
		"max_simulation_usec": _simulation_max_usec,
		"outbound_bytes": _outbound_bytes,
	})
	_reset_metrics_window()


func _reset_metrics_window() -> void:
	_simulation_total_usec = 0
	_simulation_max_usec = 0
	_simulation_samples = 0
	_simulation_sample_usec.clear()
	_outbound_bytes = 0


func _log_overtime_if_needed() -> void:
	if match_coordinator == null or match_coordinator.state() != MatchStateMachine.State.ACTIVE_HEAT:
		return
	var payload := match_coordinator.current_state_payload()
	var overtime_tick := int(payload.get("overtime_start_tick", -1))
	if overtime_tick < 0 or world.server_tick < overtime_tick:
		return
	var overtime_key := "%d:%d" % [int(payload.get("round_number", 0)), int(payload.get("heat_number", 0))]
	if overtime_key == _logged_overtime_key:
		return
	_logged_overtime_key = overtime_key
	_log("info", "overtime_started", {
		"server_tick": world.server_tick,
		"round": payload.get("round_number", 0),
		"heat": payload.get("heat_number", 0),
	})


func _log(level: String, event_name: String, fields: Dictionary = {}) -> void:
	var entry := {
		"timestamp": Time.get_datetime_string_from_system(true),
		"level": level,
		"event": event_name,
	}
	for key in fields:
		entry[key] = _bounded_log_value(fields[key])
	print(JSON.stringify(entry))


static func percentile_usec(samples: Array, percentile: float) -> int:
	if samples.is_empty():
		return 0
	var ordered := samples.duplicate()
	ordered.sort()
	var index := clampi(ceili(clampf(percentile, 0.0, 1.0) * ordered.size()) - 1, 0, ordered.size() - 1)
	return ordered[index]


static func _bounded_log_value(value: Variant, depth: int = 0) -> Variant:
	if depth >= 2:
		return "[bounded]"
	if value is String or value is StringName:
		var text := String(value)
		return text.left(NetworkProtocol.MAX_LOG_STRING_LENGTH)
	if value is Array:
		var bounded: Array = []
		var source := value as Array
		for index in mini(source.size(), NetworkProtocol.MAX_LOG_COLLECTION_LENGTH):
			bounded.append(_bounded_log_value(source[index], depth + 1))
		return bounded
	if value is Dictionary:
		var bounded_dictionary: Dictionary = {}
		var source_dictionary := value as Dictionary
		var keys := source_dictionary.keys()
		for index in mini(keys.size(), NetworkProtocol.MAX_LOG_COLLECTION_LENGTH):
			var key := String(keys[index]).left(NetworkProtocol.MAX_LOG_STRING_LENGTH)
			bounded_dictionary[key] = _bounded_log_value(source_dictionary[keys[index]], depth + 1)
		return bounded_dictionary
	return value


static func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
