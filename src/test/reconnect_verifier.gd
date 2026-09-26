extends SceneTree

## Real TCP acceptance for reclaiming a held match seat after a dropped connection.
var server: NetworkBridge
var host: NetworkBridge
var guest: NetworkBridge
var intruder: NetworkBridge
var replacement: NetworkBridge
var intruder_rejection: StringName = &""
var host_state: Dictionary = {}
var verification_port: int = 17671


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
	intruder = _runtime("Intruder")
	replacement = _runtime("Replacement")
	intruder.client_rejected.connect(func(reason: StringName, _message: String) -> void: intruder_rejection = reason)
	host.client_match_event_received.connect(func(event: StringName, _tick: int, payload: Dictionary) -> void:
		if event == &"STATE_CHANGED":
			host_state = payload
	)
	if server.start_server({"port": verification_port, "max_players": 2, "lobby_password": "rejoin-test", "server_name": "Reconnect Verification", "test_fast_match": true}) != OK:
		_fail("server_start: %s" % server.last_error)
		return
	host.start_client("127.0.0.1", verification_port, "RejoinHost", GameConstants.PROTOCOL_VERSION, "rejoin-test")
	if not await _until(func() -> bool: return host.local_peer_id != 0):
		_fail("host_admission")
		return
	guest.start_client("127.0.0.1", verification_port, "RejoinGuest", GameConstants.PROTOCOL_VERSION, "rejoin-test")
	if not await _until(func() -> bool: return guest.local_peer_id != 0):
		_fail("guest_admission")
		return
	host.send_ready_state(true)
	guest.send_ready_state(true)
	if not await _until(func() -> bool: return server.lobby.all_humans_ready()):
		_fail("ready")
		return
	host.send_start_match()
	if not await _until(func() -> bool: return server.match_coordinator != null and server.match_coordinator.state() == MatchStateMachine.State.ACTIVE_HEAT):
		_fail("match_start")
		return
	var first_guest_id := guest.local_peer_id
	var cards := (server.match_coordinator.machine.players[first_guest_id] as PlayerMatchState).card_stacks.duplicate()
	if cards.is_empty():
		_fail("no_draft_cards")
		return
	guest.stop()
	if not await _until(func() -> bool: return server.world.simulation_paused and server.match_coordinator.can_reconnect(first_guest_id)):
		_fail("seat_not_held")
		return
	if server.match_coordinator.state() == MatchStateMachine.State.MATCH_RESULT:
		_fail("forfeit_not_held")
		return
	# The held seat stays taken: a newcomer cannot fill the full server meanwhile.
	intruder.start_client("127.0.0.1", verification_port, "Intruder", GameConstants.PROTOCOL_VERSION, "rejoin-test")
	if not await _until(func() -> bool: return intruder_rejection != &""):
		_fail("intruder_not_rejected")
		return
	if intruder_rejection != NetworkProtocol.REJECT_SERVER_FULL:
		_fail("intruder_rejected_for_%s" % intruder_rejection)
		return
	guest.start_client("127.0.0.1", verification_port, "SomeoneElse", GameConstants.PROTOCOL_VERSION, "rejoin-test")
	if not await _until(func() -> bool: return guest.local_peer_id != 0 and guest.local_peer_id != first_guest_id):
		_fail("guest_readmission")
		return
	var rejoined_id := guest.local_peer_id
	if not await _until(func() -> bool: return not server.world.simulation_paused):
		_fail("match_not_resumed")
		return
	var restored := server.match_coordinator.machine.players.get(rejoined_id) as PlayerMatchState
	if restored == null or not restored.participant or restored.card_stacks != cards or restored.display_name != "RejoinGuest":
		_fail("seat_not_restored")
		return
	if server.match_coordinator.machine.players.has(first_guest_id):
		_fail("previous_peer_retained")
		return
	if not await _until(func() -> bool: return rejoined_id in (host_state.get("participant_peer_ids", []) as Array)):
		_fail("host_not_informed")
		return
	# A stolen token without the lobby password cannot displace the live pilot.
	intruder_rejection = &""
	intruder.session._reconnect_tokens = guest.session._reconnect_tokens.duplicate()
	intruder.start_client("127.0.0.1", verification_port, "Intruder", GameConstants.PROTOCOL_VERSION, "wrong-password")
	if not await _until(func() -> bool: return intruder_rejection != &""):
		_fail("token_without_password_not_rejected")
		return
	if intruder_rejection != NetworkProtocol.REJECT_INVALID_PASSWORD or not server.lobby.players.has(rejoined_id):
		_fail("token_without_password_displaced_pilot")
		return
	# A rejoin that arrives before the server notices the old connection drop
	# takes the seat over from the stale peer instead of joining as a spectator.
	replacement.session._reconnect_tokens = guest.session._reconnect_tokens.duplicate()
	replacement.start_client("127.0.0.1", verification_port, "Replacement", GameConstants.PROTOCOL_VERSION, "rejoin-test")
	if not await _until(func() -> bool: return replacement.local_peer_id != 0):
		_fail("stale_peer_takeover_admission")
		return
	var takeover_id := replacement.local_peer_id
	var taken := server.match_coordinator.machine.players.get(takeover_id) as PlayerMatchState
	if taken == null or not taken.participant or taken.card_stacks != cards or server.match_coordinator.machine.players.has(rejoined_id):
		_fail("stale_peer_seat_not_taken_over")
		return
	if not await _until(func() -> bool: return not server.lobby.players.has(rejoined_id) and not server.world.simulation_paused):
		_fail("stale_peer_not_replaced")
		return
	# Closing the game (the bridge leaving the tree) gives the seat up at once:
	# no pause, immediate forfeit.
	replacement.get_parent().remove_child(replacement)
	if not await _until(func() -> bool: return server.match_coordinator == null or server.match_coordinator.state() == MatchStateMachine.State.MATCH_RESULT):
		_fail("deliberate_leave_held_seat")
		return
	if server.match_coordinator != null and server.match_coordinator.can_reconnect(takeover_id):
		_fail("deliberate_leave_reclaimable")
		return
	print("SSF_RECONNECT_OK previous=%d rejoined=%d takeover=%d cards=%d" % [first_guest_id, rejoined_id, takeover_id, cards.size()])
	_cleanup()
	quit(0)


func _until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func _cleanup() -> void:
	for bridge in [replacement, intruder, guest, host, server]:
		if bridge != null:
			bridge.stop()
	if replacement != null and not replacement.is_inside_tree():
		replacement.free()


func _fail(reason: String) -> void:
	printerr("SSF_RECONNECT_ERROR=%s" % reason)
	_cleanup()
	quit(1)
