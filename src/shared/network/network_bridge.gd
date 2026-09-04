class_name NetworkBridge
extends Node

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const AuthenticationAttemptLimiterScript = preload("res://src/shared/network/authentication_attempt_limiter.gd")

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
var _authentication_attempt_limiter := AuthenticationAttemptLimiterScript.new()
var _connection_attempt_limiter := AuthenticationAttemptLimiterScript.new(
	NetworkProtocol.CONNECTION_ATTEMPT_LIMIT,
	NetworkProtocol.CONNECTION_ATTEMPT_WINDOW_SECONDS,
	NetworkProtocol.CONNECTION_ATTEMPT_COOLDOWN_SECONDS
)
var _peer_auth_sources: Dictionary = {}
var _blocked_sources: Dictionary = {}
var _ban_file_path: String = ""
var _malformed_control_strikes: Dictionary = {}
var _client_name: String = "Pilot"
var _client_protocol_version: int = GameConstants.PROTOCOL_VERSION
var _client_password: String = ""
var _last_metrics_tick: int = 0
var _simulation_total_usec: int = 0
var _simulation_max_usec: int = 0
var _simulation_samples: int = 0
var _simulation_sample_usec: Array[int] = []
var _simulation_over_budget_ticks: int = 0
var _outbound_bytes: int = 0
var _phase_totals_usec: Dictionary = {"simulation": 0, "coordination": 0, "replication": 0}
var _active_sample_usec: Array[int] = []
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
	var lobby_password := String(configuration.get("lobby_password", ""))
	if not NetworkProtocol.is_valid_lobby_password(lobby_password):
		last_error = "A lobby password containing 1–%d printable characters is required." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
		role = Role.NONE
		return ERR_INVALID_PARAMETER
	_configuration = configuration.duplicate(true)
	_configuration.erase("admin_password")
	_configuration.erase("admin_password_file")
	_configuration.erase("lobby_password_file")
	_ban_file_path = String(configuration.get("ban_file", "user://server-bans.json"))
	_load_blocked_sources()
	var match_config := MatchConfig.new()
	match_config.port = int(configuration.get("port", GameConstants.DEFAULT_PORT))
	if match_config.port == LanDiscoveryProtocol.DISCOVERY_PORT:
		last_error = "UDP port %d is reserved for LAN server discovery." % LanDiscoveryProtocol.DISCOVERY_PORT
		role = Role.NONE
		return ERR_INVALID_PARAMETER
	match_config.max_players = int(configuration.get("max_players", GameConstants.DEFAULT_MAX_PLAYERS))
	match_config.rounds_to_win = int(configuration.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN))
	match_config.competitive_view = bool(configuration.get("competitive_view", false))
	if bool(configuration.get("test_fast_match", false)):
		match_config.draft_duration_seconds = 0.75
		match_config.countdown_duration_seconds = 0.25
		match_config.heat_result_duration_seconds = 0.25
		match_config.round_result_duration_seconds = 0.25
	lobby = ServerLobby.new(match_config)
	world = AuthoritativeWorld.new()
	var preset_id := String(configuration.get("match_preset", ""))
	if not preset_id.is_empty():
		var preset_result := preload("res://src/shared/lobby/match_presets.gd").apply(lobby, ServerLobby.OPERATOR_AUTHORITY_ID, preset_id)
		if not bool(preset_result.ok):
			last_error = String(preset_result.error)
			role = Role.NONE
			return ERR_INVALID_PARAMETER
		_activate_added_npcs(preset_result)
	match_coordinator = null
	_reset_metrics_window()
	_metrics_window = 0
	_logged_overtime_key = ""
	_discovery_instance_id = "%x-%x" % [Time.get_ticks_msec(), get_instance_id()]
	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_server(
		match_config.port,
		match_config.max_players + NetworkProtocol.AUTH_RESERVED_PEERS,
		NetworkProtocol.CHANNEL_COUNT
	)
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
	protocol_version: int = GameConstants.PROTOCOL_VERSION,
	lobby_password: String = ""
) -> Error:
	stop()
	role = Role.CLIENT
	_client_name = display_name
	_client_protocol_version = protocol_version
	_client_password = lobby_password
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
	_authentication_attempt_limiter.clear()
	_connection_attempt_limiter.clear()
	_peer_auth_sources.clear()
	_blocked_sources.clear()
	_ban_file_path = ""
	_malformed_control_strikes.clear()
	_projectile_message_sequence = 0
	_projectile_correction_cursor = 0
	_projectile_correction_send_count = 0
	_projectile_correction_assembler.clear()
	_client_password = ""
	_configuration.clear()
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
		"password_required": true,
	}


func flush_metrics() -> void:
	if role == Role.SERVER and _simulation_samples > 0 and lobby != null and lobby.match_active:
		_log_metrics()


func get_round_trip_time_ms() -> int:
	return int(get_network_statistics().rtt_ms)


func get_network_statistics() -> Dictionary:
	var unavailable := {
		"rtt_ms": -1,
		"rtt_variance_ms": 0,
		"packet_loss_percent": 0.0,
		"packet_throttle_percent": 100.0,
	}
	if role != Role.CLIENT or _enet_peer == null:
		return unavailable
	var server_peer := _enet_peer.get_peer(NetworkProtocol.SERVER_PEER_ID)
	if server_peer == null:
		return unavailable
	return {
		"rtt_ms": int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)),
		"rtt_variance_ms": int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)),
		"packet_loss_percent": (
			float(server_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS))
			/ ENetPacketPeer.PACKET_LOSS_SCALE
			* 100.0
		),
		"packet_throttle_percent": (
			float(server_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
			/ ENetPacketPeer.PACKET_THROTTLE_SCALE
			* 100.0
		),
	}


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


func send_player_appearance(random_color: bool, color: Color, pattern: StringName) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_player_appearance.rpc_id(NetworkProtocol.SERVER_PEER_ID, random_color, color.to_html(false), String(pattern))


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


func send_competitive_view(enabled: bool) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_competitive_view.rpc_id(NetworkProtocol.SERVER_PEER_ID, enabled)


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


func send_match_preset(preset_id: String) -> void:
	if role == Role.CLIENT:
		request_match_preset.rpc_id(NetworkProtocol.SERVER_PEER_ID, preset_id)


func send_rematch() -> void:
	if role == Role.CLIENT:
		request_rematch.rpc_id(NetworkProtocol.SERVER_PEER_ID)


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
	var controls_enabled := match_coordinator != null and match_coordinator.controls_enabled()
	var npc_peer_ids := lobby.npc_peer_ids_view()
	if controls_enabled and not npc_peer_ids.is_empty():
		npc_controller.submit_inputs(
			world,
			npc_peer_ids,
			lobby.npc_difficulties_view(),
			match_coordinator.npc_overtime_elapsed(),
			match_coordinator.npc_objective_state()
		)
	world.step(delta, controls_enabled, not npc_peer_ids.is_empty())
	var simulation_done_usec := Time.get_ticks_usec()
	if match_coordinator != null:
		match_coordinator.step(delta)
		_drain_match_coordinator()
		_log_overtime_if_needed()
		if match_coordinator.is_finished():
			match_coordinator = null
			_broadcast_lobby_state()
	var coordination_done_usec := Time.get_ticks_usec()
	var tick := world.server_tick
	if lobby != null and lobby.match_active and tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PLAYER_SNAPSHOT_RATE) == 0:
		_send_player_snapshots()
	_send_projectile_batch()
	_send_mine_detonations()
	if lobby != null and lobby.match_active and tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PROJECTILE_CORRECTION_RATE) == 0:
		_send_projectile_correction()
	if tick % 3 == 0:
		_send_combat_feedback()
	var duration_usec := Time.get_ticks_usec() - start_usec
	_phase_totals_usec.simulation += simulation_done_usec - start_usec
	_phase_totals_usec.coordination += coordination_done_usec - simulation_done_usec
	_phase_totals_usec.replication += start_usec + duration_usec - coordination_done_usec
	if controls_enabled:
		_active_sample_usec.append(duration_usec)
	_simulation_total_usec += duration_usec
	_simulation_max_usec = maxi(_simulation_max_usec, duration_usec)
	_simulation_samples += 1
	_simulation_sample_usec.append(duration_usec)
	if duration_usec > int(1_000_000.0 / GameConstants.PHYSICS_TICKS_PER_SECOND):
		_simulation_over_budget_ticks += 1
	if tick - _last_metrics_tick >= GameConstants.PHYSICS_TICKS_PER_SECOND * 10:
		if lobby != null and lobby.match_active:
			_log_metrics()
		else:
			_reset_metrics_window()
		_last_metrics_tick = tick


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func client_hello(protocol_version: int, display_name: String, password_proof: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _pending_handshakes.has(sender_id):
		_reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	if display_name.length() > NetworkProtocol.MAX_LOG_STRING_LENGTH or not NetworkProtocol.is_valid_auth_proof(password_proof):
		_reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	var challenge := _pending_handshakes.challenge_for(sender_id)
	var expected_proof := NetworkProtocol.lobby_password_proof(
		challenge,
		String(_configuration.get("lobby_password", ""))
	)
	var rejection := ConnectionAdmission.validate_hello(
		protocol_version,
		display_name,
		lobby.players.size() if lobby.match_active else lobby.human_count(),
		lobby.player_limit,
		password_proof,
		expected_proof
	)
	if not rejection.is_empty():
		if rejection == NetworkProtocol.REJECT_INVALID_PASSWORD:
			_authentication_attempt_limiter.register_failure(
				String(_peer_auth_sources.get(sender_id, "peer:%d" % sender_id)),
				_now_seconds()
			)
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
	world.input_timeouts[sender_id] = GameConstants.INPUT_STALE_SECONDS
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
func request_player_appearance(random_color: bool, color_value: String, pattern_value: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "player_appearance"):
		return
	if color_value.length() > 7 or pattern_value.length() > 16:
		_reject_malformed_control(sender_id, "oversized_player_appearance")
		return
	var pattern := ShipAppearanceScript.normalized_pattern(pattern_value)
	var result := lobby.request_player_appearance(sender_id, random_color, color_value, pattern)
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
func request_competitive_view(enabled: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "competitive_view"):
		return
	var result := lobby.request_competitive_view(sender_id, enabled)
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
func request_match_preset(preset_id: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "match_preset"):
		return
	if preset_id.length() > 32:
		_reject_malformed_control(sender_id, "oversized_match_preset")
		return
	var result := preload("res://src/shared/lobby/match_presets.gd").apply(lobby, sender_id, preset_id)
	if not bool(result.ok):
		_send_request_rejected(sender_id, String(result.error))
		return
	_remove_npc_entities(result.get("removed_npc_ids", []) as Array)
	_activate_added_npcs(result)
	_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_rematch() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "rematch"):
		return
	var result := _prepare_fresh_rematch(sender_id)
	if not bool(result.ok):
		_send_request_rejected(sender_id, String(result.error))
		return
	_broadcast_lobby_state()
	_broadcast_match_event(&"MATCH_START_ACCEPTED", {"leader_id": sender_id, "fresh_rematch": true})
	_drain_match_coordinator()


func _prepare_fresh_rematch(sender_id: int) -> Dictionary:
	if lobby == null or sender_id != lobby.leader_id:
		return {"ok": false, "error": "Only the lobby leader may start a fresh rematch."}
	if match_coordinator == null or not match_coordinator.machine.can_extend_match():
		return {"ok": false, "error": "A fresh rematch needs final results and at least two competing participants."}
	# Build and validate the replacement before touching the finished match.
	var configured_seed := int(_configuration.get("test_match_seed", 0))
	var seed_value := configured_seed if configured_seed > 0 else _secure_match_seed()
	var replacement := AuthoritativeMatchCoordinator.new(lobby, world, seed_value, match_coordinator.overtime_start_seconds)
	if not replacement.start(world.server_tick):
		return {"ok": false, "error": "The current rules cannot start a rematch. Return to the lobby to adjust them."}
	for player_value in lobby.players.values():
		(player_value as PlayerMatchState).reset_match()
	world.reset_match_inventories()
	npc_controller.clear()
	match_coordinator = replacement
	_logged_overtime_key = ""
	return {"ok": true}


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
	if not _has_valid_authoritative_player_names(lobby_state_value, true):
		_reject_malformed_server_payload()
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
	if not _has_valid_authoritative_player_names(state, true):
		_reject_malformed_server_payload()
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
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	if not _has_valid_authoritative_player_names(payload, false):
		_reject_malformed_server_payload()
		return
	client_match_event_received.emit(event_type, server_tick_value, payload)


static func _has_valid_authoritative_player_names(payload: Dictionary, require_players: bool = false) -> bool:
	if not payload.has("players"):
		return not require_players
	var players_value: Variant = payload.get("players")
	if not players_value is Array:
		return false
	var player_values := players_value as Array
	if player_values.size() > NetworkProtocol.MAX_SNAPSHOT_PLAYERS:
		return false
	var accepted_names := PackedStringArray()
	for player_value in player_values:
		if not player_value is Dictionary:
			return false
		var player := player_value as Dictionary
		var display_name_value: Variant = player.get("display_name")
		if not display_name_value is String:
			return false
		var display_name := String(display_name_value)
		if not ServerLobby.is_valid_display_name(display_name):
			return false
		if ServerLobby._display_name_conflicts(display_name, accepted_names):
			return false
		accepted_names.append(display_name)
	return true


func _reject_malformed_server_payload() -> void:
	last_error = "The server sent malformed player identity data."
	stop()
	client_rejected.emit(NetworkProtocol.REJECT_MALFORMED_TRAFFIC, last_error)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_OBJECTIVE)
func objective_snapshot(server_tick_value: int, payload: Dictionary) -> void:
	if role == Role.CLIENT and multiplayer.get_remote_sender_id() == NetworkProtocol.SERVER_PEER_ID:
		client_match_event_received.emit(&"OBJECTIVE_UPDATED", server_tick_value, payload)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_PLAYER_SNAPSHOT)
func world_snapshot(packet: PackedByteArray) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var decoded := PlayerSnapshotCodec.decode(packet)
	if decoded.ok:
		client_snapshot_received.emit(decoded)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_PROJECTILE_DELTA)
func projectile_batch(packet: PackedByteArray) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var decoded := ProjectilePacketCodec.decode_batch(packet)
	if decoded.ok and int(decoded.kind) == ProjectilePacketCodec.KIND_DELTA:
		client_projectile_batch_received.emit(decoded)


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_PROJECTILE_CORRECTION)
func projectile_correction(packet: PackedByteArray) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var decoded := ProjectilePacketCodec.decode_correction(packet)
	if decoded.ok:
		_accept_projectile_correction_chunk(decoded)


func _on_server_peer_connected(peer_id: int) -> void:
	var source := _peer_auth_source(peer_id)
	_peer_auth_sources[peer_id] = source
	var now := _now_seconds()
	if _blocked_sources.has(_normalized_source(source)):
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_BLOCKED)
		return
	if (
		_connection_attempt_limiter.is_blocked(source, now) or
		_connection_attempt_limiter.register_failure(source, now)
	):
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	if _pending_auth_count_for_source(source, peer_id) >= NetworkProtocol.AUTH_MAX_PENDING_PER_SOURCE:
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	if _authentication_attempt_limiter.is_blocked(source, now):
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	var challenge := Crypto.new().generate_random_bytes(NetworkProtocol.AUTH_CHALLENGE_BYTES).hex_encode()
	_pending_handshakes.begin(peer_id, now, challenge)
	authentication_challenge.rpc_id(peer_id, challenge)


func _on_server_peer_disconnected(peer_id: int) -> void:
	_pending_handshakes.complete(peer_id)
	_peer_auth_sources.erase(peer_id)
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


func _peer_auth_source(peer_id: int) -> String:
	if _enet_peer == null:
		return "peer:%d" % peer_id
	var packet_peer := _enet_peer.get_peer(peer_id)
	if packet_peer == null:
		return "peer:%d" % peer_id
	var address := packet_peer.get_remote_address()
	return address if not address.is_empty() else "peer:%d" % peer_id


func _pending_auth_count_for_source(source: String, excluded_peer_id: int) -> int:
	var normalized := _normalized_source(source)
	var count := 0
	for peer_value in _peer_auth_sources.keys():
		var peer_id := int(peer_value)
		if peer_id != excluded_peer_id and _pending_handshakes.has(peer_id) and _normalized_source(String(_peer_auth_sources[peer_id])) == normalized:
			count += 1
	return count


func operator_status() -> Dictionary:
	var lobby_summary := lobby.serialize() if lobby != null else {}
	lobby_summary.erase("players")
	return {
		"ok": role == Role.SERVER,
		"server_name": String(_configuration.get("server_name", "")),
		"port": int(_configuration.get("port", 0)),
		"auto_start": bool(_configuration.get("auto_start", false)),
		"match_active": lobby.match_active if lobby != null else false,
		"server_tick": world.server_tick if world != null else 0,
		"human_count": lobby.human_count() if lobby != null else 0,
		"npc_count": lobby.npc_count() if lobby != null else 0,
		"active_projectiles": world.projectile_registry.size() if world != null else 0,
		"blocked_source_count": _blocked_sources.size(),
		"lobby": lobby_summary,
	}


func operator_players() -> Dictionary:
	var players: Array[Dictionary] = []
	var blocked_sources: Array = _blocked_sources.keys()
	blocked_sources.sort()
	var blocked_source_count := blocked_sources.size()
	if blocked_sources.size() > 256:
		blocked_sources = blocked_sources.slice(0, 256)
	if lobby != null:
		for peer_id in lobby.human_peer_ids():
			var player := lobby.players[peer_id] as PlayerMatchState
			players.append({
				"peer_id": peer_id,
				"display_name": player.display_name,
				"source": String(_peer_auth_sources.get(peer_id, "")),
				"ready": player.lobby_ready,
				"spectator": player.spectator,
			})
	return {
		"ok": role == Role.SERVER,
		"players": players,
		"blocked_sources": blocked_sources,
		"blocked_source_count": blocked_source_count,
		"blocked_sources_truncated": blocked_source_count > blocked_sources.size(),
	}


func operator_kick(peer_id: int, block_source: bool = false) -> Dictionary:
	if role != Role.SERVER or lobby == null:
		return {"ok": false, "error": "The server is not running."}
	var player := lobby.players.get(peer_id) as PlayerMatchState
	if player == null or player.is_npc:
		return {"ok": false, "error": "That human player is not connected."}
	var source := String(_peer_auth_sources.get(peer_id, ""))
	if block_source:
		var block_result := operator_block_source(source)
		if not block_result.ok:
			return block_result
	var reason := NetworkProtocol.REJECT_BLOCKED if block_source else NetworkProtocol.REJECT_KICKED
	connection_rejected.rpc_id(peer_id, reason, NetworkProtocol.rejection_message(reason))
	_pending_disconnects[peer_id] = _now_seconds() + 0.1
	_log("warning", "operator_peer_removed", {
		"peer_id": peer_id,
		"display_name": player.display_name,
		"blocked": block_source,
	})
	return {"ok": true, "peer_id": peer_id, "source": source, "blocked": block_source}


func operator_block_source(source: String) -> Dictionary:
	var normalized := _normalized_source(source)
	if not _is_valid_block_source(normalized):
		return {"ok": false, "error": "A bounded source address is required."}
	if not _blocked_sources.has(normalized) and _blocked_sources.size() >= NetworkProtocol.MAX_BLOCKED_SOURCES:
		return {"ok": false, "error": "The blocked-source limit has been reached."}
	_blocked_sources[normalized] = true
	var save_error := _save_blocked_sources()
	if not save_error.is_empty():
		_blocked_sources.erase(normalized)
		return {"ok": false, "error": save_error}
	return {"ok": true, "source": normalized}


func operator_unblock_source(source: String) -> Dictionary:
	var normalized := _normalized_source(source)
	if not _blocked_sources.erase(normalized):
		return {"ok": false, "error": "That source is not blocked."}
	var save_error := _save_blocked_sources()
	if not save_error.is_empty():
		_blocked_sources[normalized] = true
		return {"ok": false, "error": save_error}
	return {"ok": true, "source": normalized}


func operator_set_lobby_password(password: String) -> Dictionary:
	if not NetworkProtocol.is_valid_lobby_password(password):
		return {"ok": false, "error": "Lobby password must contain 1–%d printable characters." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH}
	_configuration.lobby_password = password
	_log("info", "operator_setting_changed", {"setting": "lobby_password"})
	return {"ok": true, "setting": "lobby_password"}


func operator_set_setting(setting: String, value: Variant) -> Dictionary:
	if role != Role.SERVER or lobby == null:
		return {"ok": false, "error": "The server is not running."}
	var result: Dictionary
	match setting:
		"rounds_to_win":
			if not _is_integer_setting_value(value):
				return _invalid_operator_setting_type(setting, "an integer")
			result = lobby.request_rounds_to_win(ServerLobby.OPERATOR_AUTHORITY_ID, int(value))
		"player_limit":
			if not _is_integer_setting_value(value):
				return _invalid_operator_setting_type(setting, "an integer")
			result = lobby.request_player_limit(ServerLobby.OPERATOR_AUTHORITY_ID, int(value))
		"npcs_enabled":
			if not value is bool:
				return _invalid_operator_setting_type(setting, "true or false")
			result = lobby.request_npcs_enabled(ServerLobby.OPERATOR_AUTHORITY_ID, bool(value))
		"npc_difficulty":
			if not _is_integer_setting_value(value):
				return _invalid_operator_setting_type(setting, "an integer")
			result = lobby.request_all_npc_difficulty(ServerLobby.OPERATOR_AUTHORITY_ID, int(value))
		"game_mode":
			if not _is_integer_setting_value(value):
				return _invalid_operator_setting_type(setting, "an integer")
			result = lobby.request_game_mode(ServerLobby.OPERATOR_AUTHORITY_ID, int(value))
		"team_count":
			if not _is_integer_setting_value(value):
				return _invalid_operator_setting_type(setting, "an integer")
			result = lobby.request_team_count(ServerLobby.OPERATOR_AUTHORITY_ID, int(value))
		"random_spawn_powerups":
			if not value is bool:
				return _invalid_operator_setting_type(setting, "true or false")
			result = lobby.request_random_spawn_powerups(ServerLobby.OPERATOR_AUTHORITY_ID, bool(value))
		"random_powerup_interval":
			if not value is float and not value is int:
				return _invalid_operator_setting_type(setting, "a number")
			result = lobby.request_random_powerup_interval(ServerLobby.OPERATOR_AUTHORITY_ID, float(value))
		"random_powerups_permanent":
			if not value is bool:
				return _invalid_operator_setting_type(setting, "true or false")
			result = lobby.request_random_powerups_permanent(ServerLobby.OPERATOR_AUTHORITY_ID, bool(value))
		"competitive_view":
			if not value is bool:
				return _invalid_operator_setting_type(setting, "true or false")
			result = lobby.request_competitive_view(ServerLobby.OPERATOR_AUTHORITY_ID, bool(value))
		"overtime_start":
			if not value is float and not value is int:
				return _invalid_operator_setting_type(setting, "a number")
			result = lobby.request_overtime_start(ServerLobby.OPERATOR_AUTHORITY_ID, float(value))
		"server_name":
			if not value is String:
				return _invalid_operator_setting_type(setting, "text")
			var server_name := String(value).strip_edges()
			if not LanDiscoveryProtocol.is_valid_server_name(server_name):
				return {"ok": false, "error": "Server name is outside the supported range."}
			_configuration.server_name = server_name
			result = {"ok": true, "changed": true}
		"auto_start":
			if not value is bool:
				return _invalid_operator_setting_type(setting, "true or false")
			_configuration.auto_start = bool(value)
			result = {"ok": true, "changed": true}
		_:
			return {"ok": false, "error": "Unknown or restart-only setting: %s" % setting}
	if not result.ok:
		return result
	_remove_npc_entities(result.get("removed_npc_ids", []) as Array)
	_activate_added_npcs(result)
	_broadcast_lobby_state()
	_log("info", "operator_setting_changed", {"setting": setting, "value": value})
	return {"ok": true, "setting": setting, "value": value}


static func _is_integer_setting_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and is_equal_approx(value, roundf(value)))


static func _invalid_operator_setting_type(setting: String, expected: String) -> Dictionary:
	return {"ok": false, "error": "%s requires %s." % [setting, expected]}


func _load_blocked_sources() -> void:
	_blocked_sources.clear()
	if _ban_file_path.is_empty() or not FileAccess.file_exists(_ban_file_path):
		return
	var file := FileAccess.open(_ban_file_path, FileAccess.READ)
	if file == null:
		_log("warning", "ban_file_read_failed", {"path": _ban_file_path})
		return
	if file.get_length() > NetworkProtocol.MAX_BAN_FILE_BYTES:
		_log("warning", "ban_file_too_large", {"path": _ban_file_path})
		return
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Array:
		_log("warning", "ban_file_invalid", {"path": _ban_file_path})
		return
	for value in decoded:
		if _blocked_sources.size() >= NetworkProtocol.MAX_BLOCKED_SOURCES:
			break
		var source := _normalized_source(String(value))
		if _is_valid_block_source(source):
			_blocked_sources[source] = true


func _save_blocked_sources() -> String:
	if _ban_file_path.is_empty():
		return "No ban-file path is configured."
	var target_path := ProjectSettings.globalize_path(_ban_file_path)
	var temporary_path := target_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return "Could not write the temporary ban file."
	var sources: Array = _blocked_sources.keys()
	sources.sort()
	file.store_string(JSON.stringify(sources, "  "))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return "Could not flush the temporary ban file."
	var replace_error := DirAccess.rename_absolute(temporary_path, target_path)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return "Could not atomically replace the ban file."
	return ""


static func _normalized_source(source: String) -> String:
	var normalized := source.strip_edges().to_lower()
	if normalized.begins_with("[") and normalized.ends_with("]"):
		normalized = normalized.substr(1, normalized.length() - 2)
	return normalized


static func _is_valid_block_source(source: String) -> bool:
	return not source.is_empty() and source.length() <= 64 and source.is_valid_ip_address()


func _on_client_transport_connected() -> void:
	# The server supplies a fresh challenge before the client sends credentials.
	pass


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func authentication_challenge(challenge: String) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	if not NetworkProtocol.is_valid_auth_challenge(challenge):
		last_error = NetworkProtocol.rejection_message(NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		stop()
		client_rejected.emit(NetworkProtocol.REJECT_MALFORMED_TRAFFIC, last_error)
		return
	var proof := NetworkProtocol.lobby_password_proof(challenge, _client_password)
	client_hello.rpc_id(NetworkProtocol.SERVER_PEER_ID, _client_protocol_version, _client_name, proof)
	_client_password = ""


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
	if _pending_handshakes.size() > 0:
		for peer_id in _pending_handshakes.expired(now):
			_reject_connection(peer_id, NetworkProtocol.REJECT_HANDSHAKE_TIMEOUT)
	if not _pending_disconnects.is_empty():
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
	var seed_value := configured_seed if configured_seed > 0 else _secure_match_seed()
	var overtime_start := 2.0 if bool(_configuration.get("test_fast_match", false)) else lobby.config.overtime_start_seconds
	world.reset_match_inventories()
	match_coordinator = AuthoritativeMatchCoordinator.new(lobby, world, seed_value, overtime_start)
	_logged_overtime_key = ""
	if not match_coordinator.start(world.server_tick):
		match_coordinator = null
		lobby.return_to_lobby()
		_broadcast_lobby_state()
		_send_request_rejected(leader_id, "The match coordinator could not start.")
		return
	_log("info", "match_randomness_initialized", {
		"source": "configured_test_seed" if configured_seed > 0 else "secure_random",
		"participants": lobby.participant_count(),
	})
	_broadcast_match_event(&"MATCH_START_ACCEPTED", {"leader_id": leader_id})
	_drain_match_coordinator()


static func _secure_match_seed() -> int:
	var random_bytes := Crypto.new().generate_random_bytes(8)
	if random_bytes.size() != 8:
		return maxi(int(Time.get_ticks_usec() & 0x7fff_ffff), 1)
	return maxi(int(random_bytes.decode_u64(0) & 0x7fff_ffff_ffff_ffff), 1)


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
		if event_type == &"STATE_CHANGED" and String(payload.get("state_name", "")) == "HEAT_RESULT":
			if not match_coordinator.observations.heats.is_empty():
				# Server-local study rows survive normal play without enlarging RPCs.
				var rows := MatchObservations.log_rows(match_coordinator.observations.heats.back())
				for index in rows.size():
					_log("info", "heat_observation" if index == 0 else "heat_player_observation", rows[index])
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
	var public_body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), 0)
	for peer_id in lobby.human_peer_ids_view():
		var combatant := world.combatants.get(peer_id) as CombatantState
		var body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), peer_id) if combatant != null and combatant.is_cloaked() else public_body
		var correction := combatant.prediction_state() if combatant != null else {}
		correction["active_ordnance"] = world.projectile_registry.count_for_owner(peer_id)
		correction["active_mines"] = world.projectile_registry.mine_count_for_owner(peer_id)
		correction["budget_evictions"] = world.projectile_registry.budget_evictions_for_owner(peer_id)
		var packet := PlayerSnapshotCodec.assemble(world.server_tick, world.acknowledged_input(peer_id), body, correction)
		world_snapshot.rpc_id(peer_id, packet)
		_outbound_bytes += packet.size()


func _send_combat_feedback() -> void:
	var feedback := world.drain_combat_feedback()
	if lobby == null:
		return
	for peer_id in lobby.human_peer_ids_view():
		if feedback.has(peer_id):
			var payload := feedback[peer_id] as Dictionary
			match_event.rpc_id(peer_id, &"COMBAT_FEEDBACK", world.server_tick, payload)
			_outbound_bytes += var_to_bytes(payload).size()


func _send_mine_detonations() -> void:
	var events := world.drain_mine_detonations()
	if lobby == null or lobby.human_count() == 0:
		return
	for start in range(0, events.size(), 8):
		var chunk := events.slice(start, start + 8)
		mine_detonations.rpc(world.server_tick, chunk)
		_outbound_bytes += var_to_bytes(chunk).size() * lobby.human_count()


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_PROJECTILE_DELTA)
func mine_detonations(server_tick_value: int, events: Array) -> void:
	if role == Role.CLIENT and events.size() <= 8:
		client_match_event_received.emit(&"MINE_DETONATIONS", server_tick_value, {"events": events})


func _send_projectile_batch() -> void:
	if not world.has_projectile_batch():
		return
	var batch := world.drain_projectile_batch()
	if lobby == null or lobby.human_count() == 0:
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
	_projectile_correction_send_count += 1
	if world.projectile_registry.size() == 0 and not complete_snapshot:
		return
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
		"p99_simulation_usec": percentile_usec(_simulation_sample_usec, 0.99),
		"active_samples": _active_sample_usec.size(),
		"active_p95_usec": percentile_usec(_active_sample_usec, 0.95),
		"active_p99_usec": percentile_usec(_active_sample_usec, 0.99),
		"mean_world_and_npc_usec": float(_phase_totals_usec.simulation) / maxi(_simulation_samples, 1),
		"mean_coordination_usec": float(_phase_totals_usec.coordination) / maxi(_simulation_samples, 1),
		"mean_replication_usec": float(_phase_totals_usec.replication) / maxi(_simulation_samples, 1),
		"projectile_budget_evictions": world.projectile_registry.budget_evictions if world != null else 0,
		"max_simulation_usec": _simulation_max_usec,
		"over_budget_ticks": _simulation_over_budget_ticks,
		"over_budget_percent": float(_simulation_over_budget_ticks) / maxi(_simulation_samples, 1) * 100.0,
		"outbound_bytes": _outbound_bytes,
	})
	_reset_metrics_window()


func _reset_metrics_window() -> void:
	_simulation_total_usec = 0
	_simulation_max_usec = 0
	_simulation_samples = 0
	_simulation_sample_usec.clear()
	_simulation_over_budget_ticks = 0
	_outbound_bytes = 0
	_phase_totals_usec = {"simulation": 0, "coordination": 0, "replication": 0}
	_active_sample_usec.clear()


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
			var key := str(keys[index]).left(NetworkProtocol.MAX_LOG_STRING_LENGTH)
			bounded_dictionary[key] = _bounded_log_value(source_dictionary[keys[index]], depth + 1)
		return bounded_dictionary
	return value


static func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
