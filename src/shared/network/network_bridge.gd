class_name NetworkBridge
extends Node

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const CommandService = preload("res://src/shared/network/lobby_match_commands.gd")


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
signal client_admin_response(response: Dictionary)
signal operator_shutdown_requested

enum Role {
	NONE,
	SERVER,
	CLIENT,
}

var session: NetworkSessionOwner
var replication: NetworkReplicationScheduler
var commands: CommandService

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

const METRICS_INTERVAL_USEC: int = 10_000_000
var _metrics_started_usec: int = 0
var _server_started_usec: int = 0
var _last_physics_usec: int = 0
var _max_physics_gap_usec: int = 0
var _latest_metrics: Dictionary = {}
var _simulation_total_usec: int = 0
var _simulation_max_usec: int = 0
var _simulation_samples: int = 0
var _simulation_sample_usec: Array[int] = []
var _simulation_over_budget_ticks: int = 0
var _phase_totals_usec: Dictionary = {"simulation": 0, "coordination": 0, "replication": 0, "logging": 0}
var _max_logging_usec: int = 0
var _batch_tick_logs: bool = false
var _tick_log_lines: PackedStringArray = []
var log_output: Callable
var log_status: Callable
var _active_sample_usec: Array[int] = []
var _metrics_window: int = 0
var _logged_overtime_key: String = ""
var _admission_lobby_broadcast_pending: bool = false
var in_game_admin := InGameAdminAuthority.new()
var _ping_accumulator: float = 0.0
# Admitted human peer id -> private token that lets the player reclaim their seat.
var _reconnect_tokens: Dictionary = {}
# Token -> {"peer_id", "player", "coordinator"} for held match seats. The
# coordinator owns each seat's deadline.
var _reconnect_reservations: Dictionary = {}
# Stale peers whose departure _replace_stale_peer already handled; their socket
# closing later must not run it again.
var _replaced_peers: Dictionary = {}


func _init() -> void:
	commands = CommandService.new(self)
	session = NetworkSessionOwner.new(self, _session_status)
	session.log_requested.connect(_log)
	session.challenge_requested.connect(func(peer_id: int, challenge: String) -> void: _send_control_to_peer(peer_id, &"authentication_challenge", [challenge]))
	session.rejection_requested.connect(func(peer_id: int, reason: StringName, message: String) -> void: _send_control_to_peer(peer_id, &"connection_rejected", [reason, message]))
	session.connection_lost.connect(func(message: String) -> void: client_connection_lost.emit(message))
	session.peer_departed.connect(_on_session_peer_departed)
	session.request_rejected.connect(_reject_request)
	session.stopped.connect(_on_session_stopped)
	session.probe_requested.connect(func(peer_id: int, server_usec: int) -> void: transport_probe.rpc_id(peer_id, server_usec))
	replication = NetworkReplicationScheduler.new()
	replication.player_snapshot_ready.connect(func(peer_id: int, packet: PackedByteArray) -> void: world_snapshot.rpc_id(peer_id, packet))
	replication.projectile_batch_ready.connect(func(packet: PackedByteArray) -> void: _broadcast_to_admitted(&"projectile_batch", [packet]))
	# Periodic corrections are replaceable; a backlogged TCP peer receives the next one instead of queueing this one.
	replication.projectile_correction_ready.connect(func(packet: PackedByteArray) -> void: _broadcast_to_admitted(&"projectile_correction", [packet], replication.transport_congested_peers()))
	replication.projectile_recovery_ready.connect(func(peer_id: int, packet: PackedByteArray) -> void: projectile_recovery.rpc_id(peer_id, packet))
	replication.combat_feedback_ready.connect(func(peer_id: int, tick: int, payload: Dictionary) -> void: match_event.rpc_id(peer_id, &"COMBAT_FEEDBACK", tick, payload))
	replication.mine_detonations_ready.connect(func(tick: int, events: Array) -> void: _broadcast_to_admitted(&"mine_detonations", [tick, events]))


func start_server(configuration: Dictionary) -> Error:
	stop()
	var match_config := MatchConfig.new()
	match_config.port = int(configuration.get("port", GameConstants.DEFAULT_PORT))
	if match_config.port == LanDiscoveryProtocol.DISCOVERY_PORT:
		session.set_error("Port %d is reserved for LAN server discovery." % LanDiscoveryProtocol.DISCOVERY_PORT)
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
	_server_started_usec = Time.get_ticks_usec()
	_last_physics_usec = 0
	_latest_metrics.clear()
	_metrics_window = 0
	_logged_overtime_key = ""
	var error := session.start_server(configuration, match_config)
	if error == OK:
		in_game_admin.configure(String(configuration.get("admin_password", "")))
	return error


func start_client(
	host: String,
	port: int,
	display_name: String,
	protocol_version: int = GameConstants.PROTOCOL_VERSION,
	lobby_password: String = ""
) -> Error:
	return session.start_client(host, port, display_name, protocol_version, lobby_password)


## Tells the server this player is leaving on purpose, so their match seat is
## given up at once instead of being held for a reconnect, then disconnects.
## The socket stays open in the background until the server closes it. With
## wait_for_delivery (quitting the game) this blocks for at most a moment instead.
func leave_server(wait_for_delivery: bool = false) -> void:
	if role != Role.CLIENT or local_peer_id <= 0 or not is_inside_tree():
		stop()
		return
	player_leaving.rpc_id(NetworkProtocol.SERVER_PEER_ID)
	session.forget_reconnect_token()
	_flush_tick_logs()
	session.stop_after_delivery()
	in_game_admin.clear()
	if wait_for_delivery:
		var deadline := Time.get_ticks_msec() + NetworkProtocol.LEAVE_EXIT_WAIT_MSEC
		while session.poll_lingering_transport() and Time.get_ticks_msec() < deadline:
			OS.delay_msec(5)


## Quitting or closing the window tears the tree down children first, so the
## owner's _exit_tree runs after this node can no longer send RPCs. Leaving here
## still reaches the server and gives the match seat up at once.
func _exit_tree() -> void:
	if role == Role.CLIENT:
		leave_server(true)


func stop() -> void:
	_flush_tick_logs()
	session.stop()
	in_game_admin.clear()


func send_admin_challenge_request() -> void:
	if role == Role.CLIENT and local_peer_id > 0:
		request_admin_challenge.rpc_id(NetworkProtocol.SERVER_PEER_ID)


func send_admin_proof(proof: String) -> void:
	if role == Role.CLIENT and local_peer_id > 0 and NetworkProtocol.is_valid_auth_proof(proof):
		request_admin_authentication.rpc_id(NetworkProtocol.SERVER_PEER_ID, proof)


func send_admin_command(request: Dictionary, sequence: int = 0, signature: String = "") -> void:
	if role == Role.CLIENT and local_peer_id > 0 and var_to_bytes(request).size() <= NetworkProtocol.ADMIN_MAX_MESSAGE_BYTES:
		request_admin_action.rpc_id(NetworkProtocol.SERVER_PEER_ID, request, sequence, signature)


func send_admin_revoke() -> void:
	# Best effort during teardown: the transport may already be gone.
	var peer := multiplayer.multiplayer_peer
	var connected := peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if role == Role.CLIENT and local_peer_id > 0 and connected and multiplayer.get_unique_id() != NetworkProtocol.SERVER_PEER_ID:
		request_admin_revoke.rpc_id(NetworkProtocol.SERVER_PEER_ID)


func flush_metrics() -> void:
	if role == Role.SERVER and _simulation_samples > 0:
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


func send_arena_effects(settings: Dictionary) -> void:
	if role == Role.CLIENT:
		request_arena_effects.rpc_id(NetworkProtocol.SERVER_PEER_ID, settings)


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


func send_match_paused(paused: bool) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		request_match_paused.rpc_id(NetworkProtocol.SERVER_PEER_ID, paused)


func send_card_selection(offer_token: String, card_id: StringName) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		select_card.rpc_id(NetworkProtocol.SERVER_PEER_ID, offer_token, String(card_id))


func send_test_input_packet(packet: PackedByteArray) -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		submit_input.rpc_id(NetworkProtocol.SERVER_PEER_ID, packet)


func _physics_process(delta: float) -> void:
	session.poll_lingering_transport()
	if role == Role.CLIENT:
		_process_client_ping(delta)
		return
	if role != Role.SERVER or world == null:
		return
	var start_usec := Time.get_ticks_usec()
	_batch_tick_logs = true
	if _last_physics_usec > 0:
		_max_physics_gap_usec = maxi(_max_physics_gap_usec, start_usec - _last_physics_usec)
	_last_physics_usec = start_usec
	session.process_pending_connections()
	_expire_reconnect_reservations()
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
	world.step(delta, controls_enabled)
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
	replication.set_transport_congested_peers(session.congested_peers())
	replication.replicate_tick(tick, lobby, world)
	var replication_done_usec := Time.get_ticks_usec()
	# A heat result may produce a row for every player. Preserve all JSON lines
	# but perform only one synchronous release-log flush for this callback.
	_flush_tick_logs()
	var duration_usec := Time.get_ticks_usec() - start_usec
	_phase_totals_usec.simulation += simulation_done_usec - start_usec
	_phase_totals_usec.coordination += coordination_done_usec - simulation_done_usec
	_phase_totals_usec.replication += replication_done_usec - coordination_done_usec
	var logging_usec := start_usec + duration_usec - replication_done_usec
	_phase_totals_usec.logging += logging_usec
	_max_logging_usec = maxi(_max_logging_usec, logging_usec)
	if controls_enabled:
		_active_sample_usec.append(duration_usec)
	_simulation_total_usec += duration_usec
	_simulation_max_usec = maxi(_simulation_max_usec, duration_usec)
	_simulation_samples += 1
	_simulation_sample_usec.append(duration_usec)
	if duration_usec > int(1_000_000.0 / GameConstants.PHYSICS_TICKS_PER_SECOND):
		_simulation_over_budget_ticks += 1
	# Match time freezes during pause. Operational health must keep rotating in
	# idle/paused sessions, both to report liveness and to bound sample storage.
	if Time.get_ticks_usec() - _metrics_started_usec >= METRICS_INTERVAL_USEC:
		_log_metrics()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func client_hello(protocol_version: int, display_name: String, password_proof: String) -> void:
	if role != Role.SERVER:
		return
	_admit_hello(multiplayer.get_remote_sender_id(), protocol_version, display_name, password_proof, "")


# A separate RPC keeps client_hello's signature stable, so a client from another
# release still reaches the protocol-version check and sees why it was refused.
@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func rejoin_hello(protocol_version: int, display_name: String, password_proof: String, reconnect_token: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not NetworkProtocol.is_valid_reconnect_token(reconnect_token):
		session.reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	_admit_hello(sender_id, protocol_version, display_name, password_proof, reconnect_token)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func player_leaving() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if lobby == null or not lobby.players.has(sender_id):
		# Rejects pre-handshake traffic, which never holds a seat.
		_accept_control_request(sender_id, "player_leaving")
		return
	# Not rate limited: a throttled notice would otherwise turn a deliberate
	# leave into a held seat. The server closes the connection so the notice is
	# never lost to the client's close.
	session.schedule_disconnect(sender_id)


func _admit_hello(sender_id: int, protocol_version: int, display_name: String, password_proof: String, reconnect_token: String) -> void:
	var occupied := lobby.human_count()
	if lobby.match_active:
		# Held seats stay taken, so a newcomer cannot lock out a returning pilot.
		occupied = lobby.players.size() + _held_seat_count()
	# A returning pilot's own seat, held or still attached to their old
	# connection, is theirs to take.
	var stale_value: Variant = _reconnect_tokens.find_key(reconnect_token) if not reconnect_token.is_empty() else null
	if _reconnect_reservations.has(reconnect_token) or stale_value != null:
		occupied -= 1
	if not session.validate_hello(sender_id, protocol_version, display_name, password_proof, occupied, lobby.player_limit):
		return
	# Only after the password and version are proven may a rejoin displace a live peer.
	if stale_value != null:
		_replace_stale_peer(int(stale_value))
	complete_admission(sender_id, display_name, reconnect_token)


## A player can rejoin before the server notices their old connection drop (it
## waits out the idle timeout). The old peer then departs now, keeping its seat,
## so the rejoin claims that seat instead of arriving as a spectator.
func _replace_stale_peer(stale_peer_id: int) -> void:
	_log("info", "stale_peer_replaced", {"peer_id": stale_peer_id})
	_on_session_peer_departed(stale_peer_id, true)
	_replaced_peers[stale_peer_id] = true
	session.forget_admission(stale_peer_id)
	session.schedule_disconnect(stale_peer_id)


func _held_seat_count() -> int:
	var count := 0
	for reservation: Dictionary in _reconnect_reservations.values():
		if reservation.coordinator == match_coordinator:
			count += 1
	return count


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_admin_challenge() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "admin_challenge"):
		return
	var response := in_game_admin.begin(sender_id, session.peer_source(sender_id), _now_seconds())
	_send_control_to_peer(sender_id, &"admin_response", [response])


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_admin_authentication(proof: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "admin_authentication"):
		return
	var response := in_game_admin.authenticate(sender_id, session.peer_source(sender_id), proof, _now_seconds())
	_log("info" if bool(response.ok) else "warning", "in_game_admin_authentication", {"peer_id": sender_id, "ok": bool(response.ok)})
	_send_control_to_peer(sender_id, &"admin_response", [response])
	if bool(response.ok):
		_elect_lobby_leader()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_admin_action(request: Dictionary, sequence: int, signature: String) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "admin_action"):
		return
	if not in_game_admin.is_authorized(sender_id):
		_send_control_to_peer(sender_id, &"admin_response", [{"ok": false, "error": "Enter the admin password first."}])
		return
	if var_to_bytes(request).size() > NetworkProtocol.ADMIN_MAX_MESSAGE_BYTES:
		session.reject_malformed_control(sender_id, "oversized_admin_action")
		return
	if not in_game_admin.verify_command(sender_id, sequence, request, signature):
		_send_control_to_peer(sender_id, &"admin_response", [{"ok": false, "error": "Admin command signature or sequence was invalid."}])
		_log("warning", "in_game_admin_command_rejected", {"peer_id": sender_id})
		return
	var response := _execute_in_game_admin(request)
	_log("info", "in_game_admin_command", {"peer_id": sender_id, "command": String(request.get("command", "")), "ok": bool(response.get("ok", false))})
	_send_control_to_peer(sender_id, &"admin_response", [response])
	if bool(response.get("shutdown", false)):
		call_deferred("_emit_operator_shutdown")


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_admin_revoke() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if lobby != null and lobby.players.has(sender_id):
		in_game_admin.revoke(sender_id)
		_elect_lobby_leader()


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func admin_response(response: Dictionary) -> void:
	if role == Role.CLIENT and multiplayer.get_remote_sender_id() == NetworkProtocol.SERVER_PEER_ID:
		client_admin_response.emit(response)


func _execute_in_game_admin(request: Dictionary) -> Dictionary:
	if not request.get("command", null) is String:
		return {"ok": false, "error": "A text command is required."}
	match String(request.command):
		"status":
			return operator_status()
		"players":
			return operator_players()
		"kick", "ban":
			var peer_value: Variant = request.get("peer_id")
			if not _valid_admin_peer_id(peer_value):
				return {"ok": false, "error": "peer_id requires a positive integer."}
			return operator_kick(int(peer_value), String(request.command) == "ban")
		"block", "unblock":
			if not request.get("source", null) is String:
				return {"ok": false, "error": "source requires text."}
			return operator_block_source(String(request.source)) if String(request.command) == "block" else operator_unblock_source(String(request.source))
		"set":
			if not request.get("setting", null) is String:
				return {"ok": false, "error": "setting requires text."}
			return operator_set_setting(String(request.setting), request.get("value"))
		"restart_match":
			return operator_restart_match()
		"shutdown":
			return {"ok": true, "shutdown": true}
		_:
			return {"ok": false, "error": "Unknown admin command."}


func _emit_operator_shutdown() -> void:
	operator_shutdown_requested.emit()


static func _valid_admin_peer_id(value: Variant) -> bool:
	return (value is int and value > 1 and value <= 2_147_483_647) or (value is float and is_finite(value) and value > 1.0 and value <= 2_147_483_647.0 and value == floor(value))


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_lobby_config(rounds_to_win: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "lobby_config"):
		return
	commands.request_lobby_config(sender_id, rounds_to_win)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_player_limit(player_limit: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "player_limit"):
		return
	commands.request_player_limit(sender_id, player_limit)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_npcs_enabled(enabled: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "npcs_enabled"):
		return
	commands.request_npcs_enabled(sender_id, enabled)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_game_mode(mode: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "game_mode"):
		return
	commands.request_game_mode(sender_id, mode)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_team_count(team_count: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "team_count"):
		return
	commands.request_team_count(sender_id, team_count)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_team_assignment(peer_id: int, team_selection: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "team_assignment"):
		return
	commands.request_team_assignment(sender_id, peer_id, team_selection)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_arena_effects(settings: Dictionary) -> void:
	if role != Role.SERVER: return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "arena_effects"): return
	commands.request_arena_effects(sender_id, settings)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_random_spawn_powerups(enabled: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "random_spawn_powerups"):
		return
	commands.request_random_spawn_powerups(sender_id, enabled)


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
	commands.request_player_color(sender_id, random_color, color_value)


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
	commands.request_player_appearance(sender_id, random_color, color_value, pattern_value)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_npc_difficulty(npc_peer_id: int, difficulty: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "npc_difficulty"):
		return
	commands.request_npc_difficulty(sender_id, npc_peer_id, difficulty)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_all_npc_difficulty(difficulty: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "all_npc_difficulty"):
		return
	commands.request_all_npc_difficulty(sender_id, difficulty)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_random_powerup_interval(seconds: float) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "random_powerup_interval"):
		return
	commands.request_random_powerup_interval(sender_id, seconds)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_random_powerups_permanent(permanent: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "random_powerups_permanent"):
		return
	commands.request_random_powerups_permanent(sender_id, permanent)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_competitive_view(enabled: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "competitive_view"):
		return
	commands.request_competitive_view(sender_id, enabled)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_overtime_start(seconds: float) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "overtime_start"):
		return
	commands.request_overtime_start(sender_id, seconds)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_ready_state(ready: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "ready_state"):
		return
	commands.request_ready_state(sender_id, ready)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_eject_player(target_peer_id: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "eject_player"):
		return
	commands.request_eject_player(sender_id, target_peer_id)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_start_match() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "start_match"):
		return
	commands.request_start_match(sender_id)


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
	commands.request_match_preset(sender_id, preset_id)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_rematch() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "rematch"):
		return
	commands.request_rematch(sender_id)


func _prepare_fresh_rematch(sender_id: int) -> Dictionary:
	if not can_control_results(sender_id):
		return {"ok": false, "error": "Only the lobby leader or an authenticated admin may start a fresh rematch."}
	if match_coordinator == null or not match_coordinator.machine.can_extend_match():
		return {"ok": false, "error": "A fresh rematch needs final results and at least two competing participants."}
	# Build and validate the replacement before touching the finished match.
	var configured_seed := int(session.configuration_value("test_match_seed", 0))
	var seed_value := configured_seed if configured_seed > 0 else _secure_match_seed()
	var replacement := AuthoritativeMatchCoordinator.new(lobby, world, seed_value, match_coordinator.overtime_start_seconds)
	replacement.incremental_drafts = true
	if not replacement.start(world.server_tick):
		return {"ok": false, "error": "The current rules cannot start a rematch. Return to the lobby to adjust them."}
	for player_value in lobby.players.values():
		(player_value as PlayerMatchState).reset_match()
	world.reset_match_inventories()
	npc_controller.clear()
	match_coordinator = replacement
	_logged_overtime_key = ""
	return {"ok": true}


func can_control_results(peer_id: int) -> bool:
	return lobby != null and peer_id > 0 and lobby.players.has(peer_id) and (peer_id == lobby.leader_id or in_game_admin.is_authorized(peer_id))


func _elect_lobby_leader(broadcast: bool = true) -> void:
	if lobby == null:
		return
	var administrators: Array[int] = []
	for peer_id in lobby.human_peer_ids_view():
		if in_game_admin.is_authorized(peer_id):
			administrators.append(peer_id)
	if lobby.elect_leader(administrators) and broadcast:
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_return_to_lobby() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "return_to_lobby"):
		return
	commands.request_return_to_lobby(sender_id)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_extend_match() -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "extend_match"):
		return
	commands.request_extend_match(sender_id)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func request_match_paused(paused: bool) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _accept_control_request(sender_id, "match_paused"):
		return
	commands.request_match_paused(sender_id, paused)


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


func _process_client_ping(delta: float) -> void:
	if local_peer_id == 0:
		_ping_accumulator = 0.0
		return
	session.check_server_liveness()
	_ping_accumulator += delta
	if _ping_accumulator >= NetworkProtocol.TRANSPORT_PING_INTERVAL_SECONDS:
		_ping_accumulator = 0.0
		_send_ping()


func _send_ping() -> void:
	if role == Role.CLIENT and local_peer_id != 0:
		transport_ping.rpc_id(NetworkProtocol.SERVER_PEER_ID, Time.get_ticks_usec())


# TCP exposes no round-trip statistic, so clients echo a local timestamp.
@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func transport_ping(client_usec: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not session.accept_transport_message(sender_id):
		return
	session.note_peer_alive(sender_id)
	transport_pong.rpc_id(sender_id, client_usec)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func transport_pong(client_usec: int) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	session.note_server_alive()
	var elapsed_usec := Time.get_ticks_usec() - client_usec
	if elapsed_usec >= 0 and elapsed_usec < 60_000_000:
		session.record_round_trip(elapsed_usec / 1000.0)


# Server-originated probe: its round trip includes queueing in the server's
# outbound TCP stream, which the client's own ping cannot observe.
@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func transport_probe(server_usec: int) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	transport_probe_ack.rpc_id(NetworkProtocol.SERVER_PEER_ID, server_usec)


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func transport_probe_ack(server_usec: int) -> void:
	if role != Role.SERVER:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not session.accept_transport_message(sender_id):
		return
	session.note_peer_alive(sender_id)
	session.record_probe_ack(sender_id, server_usec)


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
	session.note_peer_alive(sender_id)
	var decoded := InputPacketCodec.decode(packet)
	if session.accept_input(sender_id, decoded):
		world.submit_input(sender_id, decoded.frame)


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_CONTROL)
func server_welcome(peer_id: int, lobby_state_value: Dictionary, reconnect_token: String) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	if not _has_valid_authoritative_player_names(lobby_state_value, true) or not NetworkProtocol.is_valid_reconnect_token(reconnect_token):
		_reject_malformed_server_payload()
		return
	session.accept_welcome(peer_id, lobby_state_value, reconnect_token)
	_send_ping()
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


@rpc("authority", "call_remote", "reliable", NetworkProtocol.CHANNEL_PROJECTILE_CORRECTION)
func projectile_recovery(packet: PackedByteArray) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != NetworkProtocol.SERVER_PEER_ID:
		return
	var decoded := ProjectilePacketCodec.decode_correction(packet)
	if decoded.ok and bool(decoded.get("complete_snapshot", false)):
		_accept_projectile_correction_chunk(decoded)

		projectile_recovery_ack.rpc_id(NetworkProtocol.SERVER_PEER_ID, int(decoded.server_tick), int(decoded.batch_sequence), int(decoded.chunk_index))


@rpc("any_peer", "call_remote", "reliable", NetworkProtocol.CHANNEL_PROJECTILE_CORRECTION)
func projectile_recovery_ack(tick: int, sequence: int, chunk: int) -> void:
	if role != Role.SERVER or lobby == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if lobby.human_peer_ids_view().has(sender):
		replication.acknowledge_recovery(sender, tick, sequence, chunk)


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
		"uptime_seconds": float(Time.get_ticks_usec() - _server_started_usec) / 1_000_000.0 if role == Role.SERVER else 0.0,
		"metrics": _latest_metrics.duplicate(true),
		"logging": log_status.call() if log_status.is_valid() else {},
		"metrics_age_seconds": float(Time.get_ticks_usec() - _metrics_started_usec) / 1_000_000.0 if not _latest_metrics.is_empty() else -1.0,
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


func operator_restart_match() -> Dictionary:
	if role != Role.SERVER or lobby == null or match_coordinator == null or not lobby.match_active:
		return {"ok": false, "error": "There is no active match to restart."}
	if lobby.participant_count() < GameConstants.MIN_PLAYERS:
		return {"ok": false, "error": "At least two participants are required."}
	var configured_seed := int(session.configuration_value("test_match_seed", 0))
	var seed_value := configured_seed if configured_seed > 0 else _secure_match_seed()
	var replacement := AuthoritativeMatchCoordinator.new(lobby, world, seed_value, lobby.config.overtime_start_seconds)
	replacement.incremental_drafts = true
	if not replacement.start(world.server_tick):
		return {"ok": false, "error": "The current rules cannot start a new match."}
	for player_value in lobby.players.values():
		(player_value as PlayerMatchState).reset_match()
	world.clear_projectiles()
	world.reset_match_inventories()
	world.simulation_paused = false
	npc_controller.clear()
	match_coordinator = replacement
	_logged_overtime_key = ""
	_broadcast_match_event(&"MATCH_START_ACCEPTED", {"leader_id": ServerLobby.OPERATOR_AUTHORITY_ID, "fresh_rematch": true})
	_drain_match_coordinator()
	_log("warning", "operator_match_restarted", {"participants": lobby.participant_count()})
	return {"ok": true, "message": "Match restarted from round one."}


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
	if String(hello.reconnect_token).is_empty():
		client_hello.rpc_id(NetworkProtocol.SERVER_PEER_ID, hello.protocol, hello.name, hello.proof)
	else:
		rejoin_hello.rpc_id(NetworkProtocol.SERVER_PEER_ID, hello.protocol, hello.name, hello.proof, hello.reconnect_token)


func _reject_request(peer_id: int, detail: String) -> void:
	_send_request_rejected(peer_id, "The request was rejected by server authority.")
	_log("warning", "request_rejected", {"peer_id": peer_id, "detail": detail})


func _accept_control_request(peer_id: int, request_name: String) -> bool:
	return session.accept_control_request(peer_id, request_name, lobby != null and lobby.players.has(peer_id))


func _send_request_rejected(peer_id: int, message_text: String) -> void:
	_send_control_to_peer(peer_id, &"match_event", [&"REQUEST_REJECTED", world.server_tick if world != null else 0, {"message": message_text}])


func _send_control_to_peer(peer_id: int, method: StringName, arguments: Array) -> void:
	replication.record_payload("control", var_to_bytes(arguments).size())
	callv(&"rpc_id", [peer_id, method] + arguments)


func _broadcast_to_admitted(method: StringName, arguments: Array, excluded: Dictionary = {}) -> void:
	if role != Role.SERVER or lobby == null: return
	var recipients: Array[int] = []
	for peer_id in lobby.human_peer_ids_view():
		if session.can_send_to(peer_id) and not excluded.has(peer_id): recipients.append(peer_id)
	if recipients.is_empty(): return
	if method in [&"lobby_state", &"match_event", &"objective_snapshot"]:
		replication.record_payload("control", var_to_bytes(arguments).size() * recipients.size())
	# Retain one serialization/fan-out in steady play. During admission or a
	# disconnect burst, exclude unauthenticated and already-closing transports.
	if recipients.size() == multiplayer.get_peers().size():
		callv(&"rpc", [method] + arguments)
	else:
		for peer_id in recipients: callv(&"rpc_id", [peer_id, method] + arguments)


func _schedule_admission_lobby_state() -> void:
	# Joining a crowded lobby previously queued a complete reliable roster for
	# every admission, including obsolete intermediate rosters. Coalesce only
	# these notifications; each welcome and all explicit lobby actions stay immediate.
	if not is_inside_tree():
		_broadcast_lobby_state()
		return
	if _admission_lobby_broadcast_pending:
		return
	_admission_lobby_broadcast_pending = true
	get_tree().create_timer(0.1).timeout.connect(_flush_admission_lobby_state, CONNECT_ONE_SHOT)


func _flush_admission_lobby_state() -> void:
	if _admission_lobby_broadcast_pending and role == Role.SERVER:
		_admission_lobby_broadcast_pending = false
		_broadcast_lobby_state()


func _broadcast_lobby_state() -> void:
	_admission_lobby_broadcast_pending = false
	if lobby == null:
		return
	var state := _serialized_lobby_state()
	_broadcast_to_admitted(&"lobby_state", [state])


func _serialized_lobby_state() -> Dictionary:
	var state := lobby.serialize()
	state["leader_is_admin"] = in_game_admin.is_authorized(lobby.leader_id)
	return state


func _broadcast_match_event(event_type: StringName, payload: Dictionary) -> void:
	var tick := world.server_tick if world != null else 0
	_broadcast_to_admitted(&"match_event", [event_type, tick, payload])
	_log("info", "match_event", {"event_type": String(event_type), "server_tick": tick})


func _start_match_coordinator(leader_id: int) -> void:
	var started_usec := Time.get_ticks_usec()
	var configured_seed := int(session.configuration_value("test_match_seed", 0))
	var seed_value := configured_seed if configured_seed > 0 else _secure_match_seed()
	var overtime_start := 2.0 if bool(session.configuration_value("test_fast_match", false)) else lobby.config.overtime_start_seconds
	world.reset_match_inventories()
	match_coordinator = AuthoritativeMatchCoordinator.new(lobby, world, seed_value, overtime_start)
	match_coordinator.incremental_drafts = true
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
	match_coordinator.record_phase_work(&"match_start_rpc", Time.get_ticks_usec() - started_usec)


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
			_broadcast_to_admitted(&"objective_snapshot", [server_tick_value, payload])
		else:
			_broadcast_to_admitted(&"match_event", [event_type, server_tick_value, payload])
		if event_type not in [&"OBJECTIVE_UPDATED", &"ARENA_EFFECTS_UPDATED"]:
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
			_send_control_to_peer(peer_id, &"draft_offer", [
				String(offer.offer_token), offer.card_ids as Array[StringName], int(offer.deadline_tick)
			])


@rpc("authority", "call_remote", "unreliable_ordered", NetworkProtocol.CHANNEL_PROJECTILE_DELTA)
func mine_detonations(server_tick_value: int, events: Array) -> void:
	if role == Role.CLIENT and events.size() <= 8:
		client_match_event_received.emit(&"MINE_DETONATIONS", server_tick_value, {"events": events})


func _accept_projectile_correction_chunk(decoded: Dictionary) -> void:
	var assembled := replication.accept_projectile_correction_chunk(decoded)
	if not assembled.is_empty():
		client_projectile_correction_received.emit(assembled)


func _log_metrics() -> void:
	var elapsed_seconds := maxf(float(Time.get_ticks_usec() - _metrics_started_usec) / 1_000_000.0, 0.000001)
	var logging_status: Dictionary = log_status.call() if log_status.is_valid() else {}
	var mean_usec := 0.0
	if _simulation_samples > 0:
		mean_usec = float(_simulation_total_usec) / _simulation_samples
	_metrics_window += 1
	_latest_metrics = {
		"window": _metrics_window,
		"phase_work": match_coordinator.phase_work_snapshot() if match_coordinator != null else {},
		"window_seconds": elapsed_seconds,
		"physics_samples": _simulation_samples,
		"physics_ticks_per_second": float(_simulation_samples) / elapsed_seconds,
		"max_physics_gap_usec": _max_physics_gap_usec,
		"match_active": lobby.match_active if lobby != null else false,
		"simulation_paused": world.simulation_paused if world != null else false,
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
		"mean_logging_usec": float(_phase_totals_usec.logging) / maxi(_simulation_samples, 1),
		"max_logging_usec": _max_logging_usec,
		"log_queued_batches": int(logging_status.get("queued_batches", 0)),
		"log_dropped_batches": int(logging_status.get("dropped_batches", 0)),
		"projectile_budget_evictions": world.projectile_registry.budget_evictions if world != null else 0,
		"max_simulation_usec": _simulation_max_usec,
		"over_budget_ticks": _simulation_over_budget_ticks,
		"over_budget_percent": float(_simulation_over_budget_ticks) / maxi(_simulation_samples, 1) * 100.0,
		"outbound_bytes": replication.outbound_bytes(),
		"outbound_payload": replication.payload_metrics(),
		"outbound_bytes_per_second": float(replication.outbound_bytes()) / elapsed_seconds,
	}
	_log("info", "simulation_metrics", _latest_metrics)
	_reset_metrics_window()


func _reset_metrics_window() -> void:
	_metrics_started_usec = Time.get_ticks_usec()
	_max_physics_gap_usec = 0
	_simulation_total_usec = 0
	_simulation_max_usec = 0
	_simulation_samples = 0
	_simulation_sample_usec.clear()
	_simulation_over_budget_ticks = 0
	replication.reset_outbound_bytes()
	_phase_totals_usec = {"simulation": 0, "coordination": 0, "replication": 0, "logging": 0}
	_max_logging_usec = 0
	_active_sample_usec.clear()


func _log_overtime_if_needed() -> void:
	if match_coordinator == null or match_coordinator.state() != MatchStateMachine.State.ACTIVE_HEAT:
		return
	var observation := match_coordinator.overtime_observation()
	var overtime_tick := observation.x
	if overtime_tick < 0 or world.server_tick < overtime_tick:
		return
	var overtime_key := "%d:%d" % [observation.y, observation.z]
	if overtime_key == _logged_overtime_key:
		return
	_logged_overtime_key = overtime_key
	_log("info", "overtime_started", {
		"server_tick": world.server_tick,
		"round": observation.y,
		"heat": observation.z,
	})


func _log(level: String, event_name: String, fields: Dictionary = {}) -> void:
	var entry := {
		"timestamp": Time.get_datetime_string_from_system(true),
		"level": level,
		"event": event_name,
	}
	for key in fields:
		entry[key] = _bounded_log_value(fields[key])
	var line := JSON.stringify(entry)
	if _batch_tick_logs:
		_tick_log_lines.append(line)
	else:
		_write_log_output(line)


func _flush_tick_logs() -> void:
	_batch_tick_logs = false
	if _tick_log_lines.is_empty():
		return
	_write_log_output("\n".join(_tick_log_lines))
	_tick_log_lines.clear()


func _write_log_output(text: String) -> void:
	if log_output.is_valid():
		log_output.call(text)
	else:
		print(text)


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


func _on_session_peer_departed(peer_id: int, keeps_seat: bool = true) -> void:
	if _replaced_peers.erase(peer_id):
		return
	in_game_admin.revoke(peer_id)
	var reconnect_token := String(_reconnect_tokens.get(peer_id, ""))
	_reconnect_tokens.erase(peer_id)
	if match_coordinator != null:
		var departing := lobby.players.get(peer_id) as PlayerMatchState if lobby != null else null
		if match_coordinator.disconnect_peer(peer_id, keeps_seat and not reconnect_token.is_empty()) and departing != null:
			_reconnect_reservations[reconnect_token] = {
				"peer_id": peer_id,
				"player": departing,
				"coordinator": match_coordinator,
			}
			_sync_reserved_names()
			_log("info", "reconnect_seat_held", {"peer_id": peer_id, "display_name": departing.display_name, "grace_seconds": GameConstants.RECONNECT_GRACE_SECONDS})
		_drain_match_coordinator()
	var departed := lobby.remove(peer_id) if lobby != null else null
	if departed != null:
		_elect_lobby_leader(false)
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


func complete_admission(sender_id: int, display_name: String, reconnect_token: String = "") -> void:
	var reservation := _take_reconnect_reservation(reconnect_token)
	var returning := reservation.get("player") as PlayerMatchState
	var result := lobby.admit(sender_id, display_name, returning)
	if not result.ok:
		if returning != null:
			_reconnect_reservations[reconnect_token] = reservation
			_sync_reserved_names()
		session.reject_connection(sender_id, result.reason)
		return
	session.complete_handshake(sender_id)
	_remove_npc_entities(result.get("removed_npc_ids", []) as Array)
	var player := result.player as PlayerMatchState
	world.add_peer(sender_id)
	world.input_timeouts[sender_id] = GameConstants.INPUT_STALE_SECONDS
	if returning != null and match_coordinator.reconnect_peer(int(reservation.peer_id), sender_id):
		_log("info", "peer_rejoined", {"peer_id": sender_id, "previous_peer_id": int(reservation.peer_id), "display_name": player.display_name})
	elif match_coordinator != null:
		# A seat that could not be restored leaves an ordinary late spectator.
		player.participant = false
		player.spectator = true
		match_coordinator.add_late_spectator(player)
	var issued_token := Crypto.new().generate_random_bytes(NetworkProtocol.RECONNECT_TOKEN_BYTES).hex_encode()
	_reconnect_tokens[sender_id] = issued_token
	_send_control_to_peer(sender_id, &"server_welcome", [sender_id, _serialized_lobby_state(), issued_token])
	if match_coordinator != null:
		_send_control_to_peer(sender_id, &"match_event", [
			&"STATE_CHANGED", world.server_tick, match_coordinator.current_state_payload()
		])
	_schedule_admission_lobby_state()
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


## Returns the held-seat reservation for a token, removing it, or {} when the
## token is unknown, expired, or belongs to a match that has since ended.
func _take_reconnect_reservation(reconnect_token: String) -> Dictionary:
	if reconnect_token.is_empty() or not _reconnect_reservations.has(reconnect_token):
		return {}
	var reservation := _reconnect_reservations[reconnect_token] as Dictionary
	_reconnect_reservations.erase(reconnect_token)
	_sync_reserved_names()
	if match_coordinator == null or reservation.coordinator != match_coordinator or not match_coordinator.can_reconnect(int(reservation.peer_id)):
		return {}
	return reservation


func _expire_reconnect_reservations() -> void:
	if match_coordinator != null:
		var expired := match_coordinator.expire_reconnects()
		if not expired.is_empty():
			_drain_match_coordinator()
			for peer_id in expired:
				_log("info", "reconnect_seat_released", {"peer_id": peer_id})
	if _reconnect_reservations.is_empty():
		return
	for reconnect_token in _reconnect_reservations.keys():
		var reservation := _reconnect_reservations[reconnect_token] as Dictionary
		if reservation.coordinator != match_coordinator or not match_coordinator.can_reconnect(int(reservation.peer_id)):
			_reconnect_reservations.erase(reconnect_token)
			_sync_reserved_names()


func _sync_reserved_names() -> void:
	if lobby == null:
		return
	var names := PackedStringArray()
	for reservation: Dictionary in _reconnect_reservations.values():
		names.append((reservation.player as PlayerMatchState).display_name)
	lobby.reserved_names = names


func _session_status() -> Dictionary:
	return {"human_count": lobby.human_count() if lobby != null else 0,
		"npc_count": lobby.npc_count() if lobby != null else 0,
		"player_limit": lobby.player_limit if lobby != null else GameConstants.DEFAULT_MAX_PLAYERS,
		"match_active": lobby.match_active if lobby != null else false,
		"participant_records": lobby.players.size() if lobby != null else 0,
		"active_ships": world.combatants.size() if world != null else 0,
		"active_projectiles": world.projectile_registry.size() if world != null else 0}


func _on_session_stopped() -> void:
	in_game_admin.clear()
	_reconnect_tokens.clear()
	_reconnect_reservations.clear()
	_replaced_peers.clear()
	_admission_lobby_broadcast_pending = false
	if replication != null:
		replication.clear()
	match_coordinator = null
	npc_controller.clear()
