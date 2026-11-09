extends RefCounted

## The client's match-state reductions for individual events, without a scene.


static func run(context: TestContext) -> void:
	var state := preload("res://src/client/network/client_match_state.gd").new()
	state.replace({"alive_peer_ids": [2, 3, 4], "scores": {2: 0, 3: 0}})
	var changes := [0]
	state.changed.connect(func() -> void: changes[0] += 1)
	state.apply_elimination({"peer_ids": [3], "respawn_deadlines": {3: 900}, "scores": {2: 1, 3: 0}})
	context.expect_equal(state.payload.alive_peer_ids, [2, 4], "elimination removes the eliminated pilots from the alive list")
	context.expect_equal(state.payload.respawn_deadlines, {3: 900}, "elimination takes the respawn deadlines")
	context.expect_equal(state.payload.scores, {2: 1, 3: 0}, "elimination takes scores when the server sends them")
	context.expect_equal(changes[0], 1, "an elimination publishes one change")
	state.apply_elimination({"peer_ids": [4]})
	context.expect_equal(state.payload.alive_peer_ids, [2], "eliminations accumulate")
	context.expect_equal(state.payload.scores, {2: 1, 3: 0}, "an elimination without scores keeps the previous scores")
	state.apply_respawn({"alive_peer_ids": [2, 3], "respawn_deadlines": {}})
	context.expect_equal(state.payload.alive_peer_ids, [2, 3], "respawn replaces the alive list with the server's")
	context.expect_true((state.payload.respawn_deadlines as Dictionary).is_empty(), "respawn clears met deadlines")
	state.apply_pause({"paused": true, "awaiting_reconnect": ["Pilot3"]})
	context.expect_true(state.payload.paused and state.payload.awaiting_reconnect == ["Pilot3"], "pause records the pilots the match waits for")
	state.apply_pause({})
	context.expect_false(state.payload.paused, "a pause event without a flag resumes")
	context.expect_true(state.payload.is_read_only(), "published state stays read-only")
