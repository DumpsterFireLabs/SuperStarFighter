class_name NetworkBridge
extends Node

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")


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

var session: NetworkSessionOwner
var replication: NetworkReplicationScheduler

# Read-only session observations; mutations go to the owning service.
var role: Role:
	get:
		return session.role
var lobby: ServerLobby
var world: AuthoritativeWorld
var match_coordinator: AuthoritativeMatchCoordinator
var npc_controller := NpcPilotController.new()
var local_peer_id: int:
	get:
		return session.local_peer_id
var latest_lobby_state: Dictionary:
	get:
		return session.latest_lobby_state.duplicate(true)
var last_error: String:
	get:
		return session.last_error

var _last_metrics_tick: int = 0
var _simulation_total_usec: int = 0
var _simulation_max_usec: int = 0
var _simulation_samples: int = 0
var _simulation_sample_usec: Array[int] = []
var _simulation_over_budget_ticks: int = 0
var _phase_totals_usec: Dictionary = {"simulation": 0, "coordination": 0, "replication": 0}
var _active_sample_usec: Array[int] = []
var _metrics_window: int = 0
var _logged_overtime_key: String = ""


func _init() -> void:
	session = NetworkSessionOwner.new(self, _session_status)
	session.log_requested.connect(_log)
	session.challenge_requested.connect(func(peer_id: int, challenge: String) -> void: authentication_challenge.rpc_id(peer_id, challenge))
	session.rejection_requested.connect(func(peer_id: int, reason: StringName, message: String) -> void: connection_rejected.rpc_id(peer_id, reason, message))
	session.connection_lost.connect(func(message: String) -> void: client_connection_lost.emit(message))
	session.peer_departed.connect(_on_session_peer_departed)
	session.request_rejected.connect(_reject_request)
	session.stopped.connect(_on_session_stopped)
	replication = NetworkReplicationScheduler.new()
	replication.player_snapshot_ready.connect(func(peer_id: int, packet: PackedByteArray) -> void: world_snapshot.rpc_id(peer_id, packet))
	replication.projectile_batch_ready.connect(func(packet: PackedByteArray) -> void: projectile_batch.rpc(packet))
	replication.projectile_correction_ready.connect(func(packet: PackedByteArray) -> void: projectile_correction.rpc(packet))
	replication.combat_feedback_ready.connect(func(peer_id: int, tick: int, payload: Dictionary) -> void: match_event.rpc_id(peer_id, &"COMBAT_FEEDBACK", tick, payload))
	replication.mine_detonations_ready.connect(func(tick: int, events: Array) -> void: mine_detonations.rpc(tick, events))


func start_server(configuration: Dictionary) -> Error:
	stop()
	var match_config := MatchConfig.new()
	match_config.port = int(configuration.get("port", GameConstants.DEFAULT_PORT))
	if match_config.port == LanDiscoveryProtocol.DISCOVERY_PORT:
		session.set_error("UDP port %d is reserved for LAN server discovery." % LanDiscoveryProtocol.DISCOVERY_PORT)
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
			session.set_error(String(preset_result.error))
			return ERR_INVALID_PARAMETER
		_activate_added_npcs(preset_result)
	match_coordinator = null
	_reset_metrics_window()
	_metrics_window = 0
	_logged_overtime_key = ""
	return session.start_server(configuration, match_config)


func start_client(
	host: String,
	port: int,
	display_name: String,
	protocol_version: int = GameConstants.PROTOCOL_VERSION,
	lobby_password: String = ""
) -> Error:
	return session.start_client(host, port, display_name, protocol_version, lobby_password)


func stop() -> void:
	session.stop()


func flush_metrics() -> void:
	if role == Role.SERVER and _simulation_samples > 0 and lobby != null and lobby.match_active:
		_log_metrics()


func get_round_trip_time_ms() -> int:
	return int(get_network_statistics().rtt_ms)


func get_network_statistics() -> Dictionary:
	return session.get_network_statistics()


func send_input(frame: PlayerInputFrame) -> void:
	if role != Role.CLIENT or local_peer_id == 0:
		return
	var packet := InputPacketCodec.encode(frame)
	submit_input.rpc_id(NetworkProtocol.SERVER_PEER_ID, packet)


func send_action_input(frame: PlayerInputFrame) -> void:
	if role != Role.CLIENT or local_peer_id == 0:
		return
	action_input.rpc_id(NetworkProtocol.SERVER_PEER_ID, InputPacketCodec.encode(frame))


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
	session.process_pending_connections()
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
	replication.replicate_tick(tick, lobby, world)
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
	if session.validate_hello(sender_id, protocol_version, display_name, password_proof, lobby.players.size() if lobby.match_active else lobby.human_count(), lobby.player_limit):
		complete_admission(sender_id, display_name)


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
		session.reject_malformed_control(sender_id, "oversized_player_color")
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
		session.reject_malformed_control(sender_id, "oversized_player_appearance")
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
	session.forget_admission(target_peer_id)
	_activate_added_npcs(result)
	var reason := NetworkProtocol.REJECT_EJECTED
	connection_rejected.rpc_id(target_peer_id, reason, NetworkProtocol.rejection_message(reason))
	session.schedule_disconnect(target_peer_id)
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
		session.reject_malformed_control(sender_id, "oversized_match_preset")
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
	var configured_seed := int(session.configuration_value("test_match_seed", 0))
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
		session.reject_malformed_control(sender_id, "oversized_card_selection")
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
	_accept_input_packet(packet)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_INPUT)
func action_input(packet: PackedByteArray) -> void:
	_accept_input_packet(packet)


func _accept_input_packet(packet: PackedByteArray) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not lobby.players.has(sender_id):
		_reject_request(sender_id, "input_before_handshake")
		return
	var decoded := InputPacketCodec.decode(packet)
	if session.accept_input(sender_id, decoded):
		world.submit_input(sender_id, decoded.frame)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func server_welcome(peer_id: int, lobby_state_value: Dictionary) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	if not _has_valid_authoritative_player_names(lobby_state_value, true):
		_reject_malformed_server_payload()
		return
	session.accept_welcome(peer_id, lobby_state_value)
	client_connected.emit(peer_id)
	client_lobby_updated.emit(lobby_state_value)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func connection_rejected(reason: StringName, display_message: String) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	session.set_error(display_message)
	client_rejected.emit(reason, display_message)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func lobby_state(state: Dictionary) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	if not _has_valid_authoritative_player_names(state, true):
		_reject_malformed_server_payload()
		return
	if session.accept_lobby_state(state):
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
	session.set_error("The server sent malformed player identity data.")
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


func operator_status() -> Dictionary:
	var lobby_summary := lobby.serialize() if lobby != null else {}
	lobby_summary.erase("players")
	return {
		"ok": role == Role.SERVER,
		"server_name": String(session.configuration_value("server_name", "")),
		"port": int(session.configuration_value("port", 0)),
		"auto_start": bool(session.configuration_value("auto_start", false)),
		"match_active": lobby.match_active if lobby != null else false,
		"server_tick": world.server_tick if world != null else 0,
		"human_count": lobby.human_count() if lobby != null else 0,
		"npc_count": lobby.npc_count() if lobby != null else 0,
		"active_projectiles": world.projectile_registry.size() if world != null else 0,
		"blocked_source_count": session.blocked_sources().size(),
		"lobby": lobby_summary,
	}


func operator_players() -> Dictionary:
	var players: Array[Dictionary] = []
	var blocked_sources: Array = session.blocked_sources()
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
				"source": session.peer_source(peer_id),
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
	return session.operator_kick(peer_id, player.display_name, block_source)


func operator_block_source(source: String) -> Dictionary:
	return session.operator_block_source(source)


func operator_unblock_source(source: String) -> Dictionary:
	return session.operator_unblock_source(source)


func operator_set_lobby_password(password: String) -> Dictionary:
	return session.operator_set_lobby_password(password)


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
			session.set_server_name(server_name)
			result = {"ok": true, "changed": true}
		"auto_start":
			if not value is bool:
				return _invalid_operator_setting_type(setting, "true or false")
			session.set_auto_start(bool(value))
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


static func _normalized_source(source: String) -> String:
	return NetworkSessionOwner._normalized_source(source)


static func _is_valid_block_source(source: String) -> bool:
	return NetworkSessionOwner._is_valid_block_source(source)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func authentication_challenge(challenge: String) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	if not NetworkProtocol.is_valid_auth_challenge(challenge):
		session.set_error(NetworkProtocol.rejection_message(NetworkProtocol.REJECT_MALFORMED_TRAFFIC))
		stop()
		client_rejected.emit(NetworkProtocol.REJECT_MALFORMED_TRAFFIC, last_error)
		return
	var hello := session.take_client_hello(challenge)
	client_hello.rpc_id(NetworkProtocol.SERVER_PEER_ID, hello.protocol, hello.name, hello.proof)


func _reject_request(peer_id: int, detail: String) -> void:
	_send_request_rejected(peer_id, "The request was rejected by server authority.")
	_log("warning", "request_rejected", {"peer_id": peer_id, "detail": detail})


func _accept_control_request(peer_id: int, request_name: String) -> bool:
	return session.accept_control_request(peer_id, request_name, lobby != null and lobby.players.has(peer_id))


func _send_request_rejected(peer_id: int, message_text: String) -> void:
	match_event.rpc_id(peer_id, &"REQUEST_REJECTED", world.server_tick if world != null else 0, {"message": message_text})


func _broadcast_lobby_state() -> void:
	if lobby == null:
		return
	var state := lobby.serialize()
	lobby_state.rpc(state)
	replication.record_outbound_bytes(JSON.stringify(state).length() * maxi(lobby.human_count(), 1))


func _broadcast_match_event(event_type: StringName, payload: Dictionary) -> void:
	var tick := world.server_tick if world != null else 0
	match_event.rpc(event_type, tick, payload)
	_log("info", "match_event", {"event_type": String(event_type), "server_tick": tick})


func _start_match_coordinator(leader_id: int) -> void:
	var configured_seed := int(session.configuration_value("test_match_seed", 0))
	var seed_value := configured_seed if configured_seed > 0 else _secure_match_seed()
	var overtime_start := 2.0 if bool(session.configuration_value("test_fast_match", false)) else lobby.config.overtime_start_seconds
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


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_PROJECTILE_DELTA)
func mine_detonations(server_tick_value: int, events: Array) -> void:
	if role == Role.CLIENT and events.size() <= 8:
		client_match_event_received.emit(&"MINE_DETONATIONS", server_tick_value, {"events": events})


func _accept_projectile_correction_chunk(decoded: Dictionary) -> void:
	var assembled := replication.accept_projectile_correction_chunk(decoded)
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
		"outbound_bytes": replication.outbound_bytes(),
	})
	_reset_metrics_window()


func _reset_metrics_window() -> void:
	_simulation_total_usec = 0
	_simulation_max_usec = 0
	_simulation_samples = 0
	_simulation_sample_usec.clear()
	_simulation_over_budget_ticks = 0
	replication.reset_outbound_bytes()
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


func _on_session_peer_departed(peer_id: int) -> void:
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


func complete_admission(sender_id: int, display_name: String) -> void:
	var result := lobby.admit(sender_id, display_name)
	if not result.ok:
		session.reject_connection(sender_id, result.reason)
		return
	session.complete_handshake(sender_id)
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
	replication.record_outbound_bytes(64)
	_broadcast_lobby_state()
	server_peer_admitted.emit(sender_id, player)
	_log("info", "peer_joined", {"peer_id": sender_id, "display_name": player.display_name, "spectator": player.spectator})
	if bool(session.configuration_value("auto_start", false)) and lobby.participant_count() >= GameConstants.MIN_PLAYERS and not lobby.match_active:
		for peer_id in lobby.human_peer_ids():
			lobby.request_ready(peer_id, true)
		var start_result := lobby.request_start(lobby.leader_id)
		if start_result.ok:
			_activate_added_npcs(start_result)
			_broadcast_lobby_state()
			_start_match_coordinator(lobby.leader_id)


func _session_status() -> Dictionary:
	return {"human_count": lobby.human_count() if lobby != null else 0,
		"npc_count": lobby.npc_count() if lobby != null else 0,
		"player_limit": lobby.player_limit if lobby != null else GameConstants.DEFAULT_MAX_PLAYERS,
		"match_active": lobby.match_active if lobby != null else false,
		"participant_records": lobby.players.size() if lobby != null else 0,
		"active_ships": world.combatants.size() if world != null else 0,
		"active_projectiles": world.projectile_registry.size() if world != null else 0}


func _on_session_stopped() -> void:
	if replication != null:
		replication.clear()
	match_coordinator = null
	npc_controller.clear()
