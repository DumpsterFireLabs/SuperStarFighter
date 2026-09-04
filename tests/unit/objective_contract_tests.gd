extends RefCounted


static func run(context: TestContext) -> void:
	_hill_transitions(context)
	_flag_transitions(context)
	_capture_ownership(context)
	_transport_boundary(context)


static func _hill_transitions(context: TestContext) -> void:
	var coordinator := _fixture(GameModeRules.Mode.KING_OF_THE_HILL)
	var first := coordinator.world.combatants[1] as CombatantState
	var second := coordinator.world.combatants[2] as CombatantState
	first.position = coordinator._objective_position
	second.position = first.position + Vector2(500, 0)
	first.cloak_remaining = 5.0
	coordinator._step_hill(2.0, 100)
	var changed: MatchEvent = coordinator._events[0]
	context.expect_equal(changed.event_type, &"OBJECTIVE_TRANSITION", "production objective queue uses typed events")
	var payload: Dictionary = changed.to_dictionary().payload
	context.expect_equal(payload.action, &"HILL_CONTROLLER_CHANGED", "sole occupant produces controller transition")
	context.expect_equal(payload.objective.progress[1], 0.0, "controller transition freezes progress before this tick scores")
	context.expect_equal(coordinator._hill.state.progress[1], 2.0, "typed live hill state receives scored time")
	context.expect_equal(first.cloak_remaining, 0.0, "handler reveals cloaked objective occupant")
	second.position = first.position
	coordinator._step_hill(1.0, 101)
	var contested: Dictionary = coordinator.drain_events()[1].payload
	context.expect_equal(contested.action, &"HILL_CONTROL_LOST", "contesting emits loss after controller change")
	context.expect_true(contested.objective.contested, "loss snapshot includes contested state")
	context.expect_equal(contested.objective.progress[1], 2.0, "contesting preserves accumulated hill time")
	context.expect_equal(coordinator.observations.contributions[2].hill_contest_seconds, 1.0, "handler credits each contester")
	second.position += Vector2(500, 0)
	coordinator._step_game_mode(18.0, 102)
	var events := coordinator.drain_events()
	context.expect_equal(events.size(), 2, "winning objective tick emits transition and heat result without periodic update")
	context.expect_equal(events[0].event_type, &"OBJECTIVE_TRANSITION", "winning controller change precedes state result")
	context.expect_equal(events[1].event_type, &"STATE_CHANGED", "coordinator alone emits heat result state")
	context.expect_equal(events[1].payload.last_heat_winner, 1, "coordinator resolves handler winner")
	context.expect_equal(events[1].payload.objective_contributions[1].hill_control_seconds, 20.0, "winning contribution is included in immediate result")
	context.expect_false(events[1].payload.objective.active, "result objective is inactive")
	coordinator._reset_objective_for_heat()
	context.expect_equal(coordinator._hill.state.progress, {1: 0.0, 2: 0.0}, "next heat resets all participant progress")
	context.expect_equal(coordinator._hill.state.controller_id, 0, "next heat resets hill controller")
	context.expect_false(coordinator._hill.state.contested, "next heat resets contested state")
	context.expect_equal(changed.to_dictionary().payload.objective.progress[1], 0.0, "queued snapshot survives later scoring and heat reset")


static func _flag_transitions(context: TestContext) -> void:
	var coordinator := _fixture(GameModeRules.Mode.CAPTURE_THE_FLAG)
	var first := coordinator.world.combatants[1] as CombatantState
	var second := coordinator.world.combatants[2] as CombatantState
	first.position = coordinator._objective_position
	second.position = first.position
	coordinator._step_flag(0.25, 200)
	context.expect_equal(coordinator._flag.state.flag_carrier_id, 1, "equidistant pickup retains participant-order tie breaking")
	coordinator.drain_events()
	first.alive = false
	first.position += Vector2(300, 0)
	second.position = first.position
	second.cloak_remaining = 5.0
	var alive_ids: Array[int] = [2]
	var outcome := coordinator._flag.step(0.25, coordinator.world, alive_ids, coordinator.observations)
	context.expect_equal(outcome.transitions.size(), 2, "carrier death can drop and transfer flag in same tick")
	context.expect_equal(outcome.transitions[0].action, &"FLAG_DROPPED", "drop is ordered before pickup")
	context.expect_equal(outcome.transitions[0].objective.flag_carrier_id, 0, "drop snapshot preserves empty carrier before transfer")
	context.expect_equal(outcome.transitions[1].action, &"FLAG_PICKED_UP", "pickup follows same-tick drop")
	context.expect_equal(outcome.transitions[1].objective.flag_carrier_id, 2, "pickup snapshot identifies new carrier")
	context.expect_equal(second.cloak_remaining, 0.0, "pickup reveals new carrier")
	second.alive = false
	var nobody: Array[int] = []
	coordinator._flag.step(0.0, coordinator.world, nobody, coordinator.observations)
	outcome = coordinator._flag.step(GameModeRules.FLAG_RESET_SECONDS - 0.01, coordinator.world, nobody, coordinator.observations)
	context.expect_empty(outcome.transitions, "dropped flag remains before exact reset deadline")
	outcome = coordinator._flag.step(0.01, coordinator.world, nobody, coordinator.observations)
	context.expect_equal(outcome.transitions[0].action, &"FLAG_RESET", "flag resets at exact elapsed deadline")
	context.expect_equal(coordinator._flag.state.flag_position, coordinator._objective_position, "reset returns flag to objective spawn")
	coordinator._reset_objective_for_heat()
	context.expect_equal(coordinator._flag.state.flag_carrier_id, 0, "heat reset removes flag carrier")
	context.expect_equal(coordinator._flag.dropped_seconds, 0.0, "heat reset removes drop timer")


static func _capture_ownership(context: TestContext) -> void:
	for mode in [GameModeRules.Mode.CAPTURE_THE_FLAG, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG]:
		var coordinator := _fixture(mode)
		var first := coordinator.world.combatants[1] as CombatantState
		var second := coordinator.world.combatants[2] as CombatantState
		first.position = coordinator._objective_position
		second.position = first.position + Vector2(500, 0)
		coordinator._step_flag(0.1, 300)
		coordinator.drain_events()
		var zone_id: int = coordinator._flag.teams[1] if GameModeRules.is_team_mode(mode) else 1
		first.position = coordinator._flag.state.capture_zones[zone_id]
		var outcome := coordinator._flag.step(0.5, coordinator.world, coordinator.machine.alive_participant_ids(), coordinator.observations)
		context.expect_equal(coordinator.state(), MatchStateMachine.State.ACTIVE_HEAT, "mode handler cannot transition match machine")
		context.expect_equal(outcome.winner_team_id if GameModeRules.is_team_mode(mode) else outcome.winner_peer_id, zone_id, "handler reports correctly scoped capture winner")
		coordinator._consume_objective_result(outcome, 301)
		var events := coordinator.drain_events()
		context.expect_equal(events.size(), 1, "coordinator captures a single winning state transition")
		context.expect_equal(events[0].payload.objective_contributions[1].flag_captures, 1, "capture credit precedes result payload")


static func _transport_boundary(context: TestContext) -> void:
	for mode in range(GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG + 1):
		var coordinator := _fixture(mode)
		var snapshot := coordinator._objective_snapshot()
		var keys: Array = ["active", "mode", "mode_name", "position", "zone_radius"]
		if GameModeRules.uses_hill(mode):
			keys.append_array(["controller_id", "contested", "progress", "target_seconds"])
		elif GameModeRules.uses_flag(mode):
			keys.append_array(["flag_position", "flag_carrier_id", "pickup_radius", "capture_zones"])
		keys.sort()
		var actual_keys: Array[String] = []
		for key in snapshot:
			actual_keys.append(String(key))
		actual_keys.sort()
		context.expect_equal(actual_keys, keys, "objective wire keys remain compatible for mode %d" % mode)
		context.expect_equal(bytes_to_var(var_to_bytes(snapshot)), snapshot, "objective payload serializes without RefCounted objects")
		var objective_event := MatchEvent.objective_event(42, coordinator._mode_state(), &"CONTRACT")
		var expected_envelope := {"event_type": &"OBJECTIVE_TRANSITION", "server_tick": 42,
			"payload": {"action": &"CONTRACT", "objective": snapshot}}
		context.expect_true(var_to_bytes(objective_event.to_dictionary()) == var_to_bytes(expected_envelope), "typed objective event retains legacy wire types and field ordering")
		if snapshot.has("progress"):
			context.expect_false((snapshot.progress as Dictionary).is_typed(), "wire progress uses plain dictionary")
			snapshot.progress[1] = 99.0
			context.expect_equal(coordinator._hill.state.progress[1], 0.0, "transport mutation cannot alter authoritative typed progress")
		if snapshot.has("capture_zones"):
			context.expect_false((snapshot.capture_zones as Dictionary).is_typed(), "wire zones use plain dictionary")
			var zone_id: int = coordinator._flag.state.capture_zones.keys()[0]
			var original := coordinator._flag.state.capture_zones[zone_id]
			snapshot.capture_zones[zone_id] = Vector2(-999, -999)
			context.expect_equal(coordinator._flag.state.capture_zones[zone_id], original, "transport mutation cannot alter capture zones")
	var supplied := {"ready_peer_ids": [1, 2]}
	var event := MatchEvent.new(&"DRAFT_READY", 42, supplied)
	supplied.ready_peer_ids.clear()
	var wire := event.to_dictionary()
	context.expect_equal(wire, {"event_type": &"DRAFT_READY", "server_tick": 42, "payload": {"ready_peer_ids": [1, 2]}}, "typed general event retains existing immutable wire envelope")
	wire.payload.ready_peer_ids.clear()
	context.expect_equal(event.to_dictionary().payload.ready_peer_ids, [1, 2], "drain serialization cannot mutate queued typed event")


static func _fixture(mode: int) -> AuthoritativeMatchCoordinator:
	var fixture := MatchCoordinatorTests._objective_fixture(mode, 2, 18021)
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	coordinator.drain_events()
	return coordinator
