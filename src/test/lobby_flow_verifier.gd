extends SceneTree

## Real ENet acceptance for preset authority and same-rules fresh rematches.
var server: NetworkBridge
var host: NetworkBridge
var guest: NetworkBridge
var spectator: NetworkBridge
var spectator_state: Dictionary = {}
var guest_rejections: int = 0
var host_state: Dictionary = {}
var guest_state: Dictionary = {}
var verification_port: int = 17669


func _initialize() -> void:
	_run.call_deferred()


func _runtime(runtime_name: String) -> NetworkBridge:
	var branch := Node.new()
	branch.name = runtime_name
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var main := Node.new()
	main.name = "Main"
	branch.add_child(main)
	var bridge := NetworkBridge.new()
	bridge.name = "NetworkBridge"
	main.add_child(bridge)
	return bridge


func _run() -> void:
	server = _runtime("Server")
	host = _runtime("Host")
	guest = _runtime("Guest")
	spectator = _runtime("Spectator")
	spectator.client_match_event_received.connect(func(event: StringName, _tick: int, payload: Dictionary) -> void:
		if event == &"STATE_CHANGED":
			spectator_state = payload
	)
	host.client_match_event_received.connect(func(event: StringName, _tick: int, payload: Dictionary) -> void:
		if event == &"STATE_CHANGED":
			host_state = payload
	)
	guest.client_match_event_received.connect(func(event: StringName, _tick: int, payload: Dictionary) -> void:
		if event == &"REQUEST_REJECTED":
			guest_rejections += 1
		elif event == &"STATE_CHANGED":
			guest_state = payload
	)
	if server.start_server({"port": verification_port, "max_players": 32, "lobby_password": "flow-test", "server_name": "Lobby Flow Verification", "match_preset": "skirmish"}) != OK:
		_fail("server_start: %s" % server.last_error)
		return
	host.start_client("127.0.0.1", verification_port, "FlowHost", GameConstants.PROTOCOL_VERSION, "flow-test")
	if not await _until(func() -> bool: return host.local_peer_id != 0):
		_fail("host_admission")
		return
	guest.start_client("127.0.0.1", verification_port, "FlowGuest", GameConstants.PROTOCOL_VERSION, "flow-test")
	if not await _until(func() -> bool: return guest.local_peer_id != 0):
		_fail("guest_admission")
		return
	guest.send_match_preset("chaos")
	if not await _until(func() -> bool: return guest_rejections == 1):
		_fail("guest_preset_not_rejected")
		return
	if server.lobby.player_limit != 4:
		_fail("guest_preset_mutated_rules")
		return
	host.send_match_preset("team_objective")
	if not await _until(func() -> bool: return int(guest.latest_lobby_state.get("game_mode", -1)) == GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG and int(guest.latest_lobby_state.get("player_limit", 0)) == 8):
		_fail("host_preset_not_replicated")
		return
	# Keep free seats for the real late-spectator admission check.
	host.send_npcs_enabled(false)
	if not await _until(func() -> bool: return not bool(guest.latest_lobby_state.get("npcs_enabled", true))):
		_fail("npc_fill_not_disabled")
		return
	guest.send_competitive_view(true)
	if not await _until(func() -> bool: return guest_rejections == 2):
		_fail("guest_competitive_view_not_rejected")
		return
	host.send_competitive_view(true)
	if not await _until(func() -> bool: return bool(guest.latest_lobby_state.get("competitive_view", false)) and bool(host.latest_lobby_state.get("competitive_view", false))):
		_fail("competitive_view_not_replicated")
		return
	host.send_ready_state(true)
	guest.send_ready_state(true)
	if not await _until(func() -> bool: return server.lobby.all_humans_ready()):
		_fail("ready_not_replicated")
		return
	host.send_start_match()
	if not await _until(func() -> bool: return String(host_state.get("state_name", "")) == "DRAFT" and String(guest_state.get("state_name", "")) == "DRAFT"):
		_fail("draft_not_replicated")
		return
	if not bool(host_state.get("competitive_view", false)) or not bool(guest_state.get("competitive_view", false)):
		_fail("match_view_policy_missing")
		return
	host.send_competitive_view(false)
	await create_timer(0.1).timeout
	if not server.lobby.config.competitive_view:
		_fail("view_policy_changed_midmatch")
		return
	spectator.start_client("127.0.0.1", verification_port, "LateViewer", GameConstants.PROTOCOL_VERSION, "flow-test")
	if not await _until(func() -> bool: return spectator.local_peer_id != 0 and bool(spectator_state.get("competitive_view", false))):
		_fail("late_spectator_view_policy_missing")
		return
	if not server.lobby.players[spectator.local_peer_id].spectator:
		_fail("late_join_not_spectator")
		return
	# Results are a deterministic fixture; requests and their replication use
	# actual remote sender identities, RPC checksums and reliable ENet channels.
	var prior := server.match_coordinator
	prior.machine.state = MatchStateMachine.State.MATCH_RESULT
	prior.machine.state_deadline_tick = -1
	prior.machine.players[host.local_peer_id].card_stacks = {&"twin_shot": 3}
	prior.machine.players[host.local_peer_id].score.kills = 9
	server._broadcast_match_event(&"STATE_CHANGED", prior.current_state_payload())
	if not await _until(func() -> bool: return String(host_state.get("state_name", "")) == "MATCH_RESULT"):
		_fail("results_not_replicated")
		return
	guest.send_rematch()
	if not await _until(func() -> bool: return guest_rejections == 3):
		_fail("guest_rematch_not_rejected")
		return
	if server.match_coordinator != prior:
		_fail("guest_rematch_mutated_match")
		return
	var previous_team: int = prior.machine.players[host.local_peer_id].team_id
	host.send_rematch()
	if not await _until(func() -> bool: return server.match_coordinator != prior and String(host_state.get("state_name", "")) == "DRAFT" and String(guest_state.get("state_name", "")) == "DRAFT"):
		_fail("fresh_rematch_not_replicated")
		return
	var player: PlayerMatchState = server.match_coordinator.machine.players[host.local_peer_id]
	if not player.card_stacks.is_empty() or player.score.kills != 0 or player.team_id != previous_team or server.lobby.config.game_mode != GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG or server.lobby.player_limit != 8:
		_fail("fresh_rematch_reset_or_rules")
		return
	var builds: Dictionary = host_state.get("builds", {})
	if not (builds.get(host.local_peer_id, {}) as Dictionary).is_empty() or int(host_state.get("round_number", 0)) != 1 or not bool(host_state.get("competitive_view", false)) or not bool(guest_state.get("competitive_view", false)):
		_fail("client_fresh_build_or_round")
		return
	print("SSF_LOBBY_FLOW_OK=host_preset_guest_rejections_fresh_rematch protocol=%d" % GameConstants.PROTOCOL_VERSION)
	_cleanup()
	quit(0)


func _until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func _cleanup() -> void:
	for bridge in [spectator, guest, host, server]:
		if bridge != null:
			bridge.stop()


func _fail(reason: String) -> void:
	printerr("SSF_LOBBY_FLOW_ERROR=%s" % reason)
	_cleanup()
	quit(1)
