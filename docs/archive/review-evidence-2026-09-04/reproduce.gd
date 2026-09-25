extends SceneTree

# Independent review probes. No production state or files are changed.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var config := MatchConfig.new()
	config.game_mode = GameModeRules.Mode.CAPTURE_THE_FLAG
	config.draft_duration_seconds = 0.05
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for id in [2, 3]:
		lobby.admit(id, "Pilot%d" % id)
		lobby.request_ready(id, true)
		world.add_peer(id)
	lobby.request_start(2)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 12345)
	coordinator.start(0)
	for tick in 20:
		world.step(1.0 / 60.0, coordinator.controls_enabled())
		coordinator.step(1.0 / 60.0)
		if coordinator.state() == MatchStateMachine.State.COUNTDOWN:
			break
	for event in coordinator.drain_events():
		if event.event_type == &"STATE_CHANGED" and event.payload.state == MatchStateMachine.State.COUNTDOWN:
			print("REVIEW_COUNTDOWN announced=%s actual=%s" % [event.payload.objective.capture_zones, coordinator.current_state_payload().objective.capture_zones])
	var view := NetworkWorldView.new()
	var ship := CombatShipView.new()
	ship.combatant = CombatantState.create(2, CombatStats.create_base())
	var events: Array[StringName] = []
	view.presentation_event.connect(func(kind: StringName, _payload: Dictionary) -> void: events.append(kind))
	var previous := {"position": Vector2.ZERO, "health": 100.0, "shield": 26.0, "shielding": true, "alive": true}
	view.replicated_visuals._handle_snapshot_feedback(2, previous, ship)
	var current := previous.duplicate()
	current.shield = 24.0
	view.replicated_visuals._handle_snapshot_feedback(2, current, ship)
	print("REVIEW_FALSE_BREAK active=true energy=24 events=%s" % [events])
	events.clear()
	current.shield = 20.0
	view.replicated_visuals._handle_snapshot_feedback(2, current, ship)
	print("REVIEW_FALSE_BLOCK no_impacts=true energy_drop=4 events=%s" % [events])
	ship.free()
	view.free()
	var fields := ArenaLayout.movement_fields(&"solar_tide")
	var field := fields[0] as ArenaMovementFieldDefinition
	var original := field.maximum_speed_multiplier
	field.maximum_speed_multiplier = 1.99
	print("REVIEW_FIELD_MUTABLE subsequent_lookup=%s" % (ArenaLayout.movement_fields(&"solar_tide")[0] as ArenaMovementFieldDefinition).maximum_speed_multiplier)
	field.maximum_speed_multiplier = original
	coordinator.machine.state = MatchStateMachine.State.ACTIVE_HEAT
	print("REVIEW_TYPED_ZONE_BEGIN")
	print(NpcPilotController.new().objective_intent(world, world.combatants[2], coordinator.npc_objective_state()))
	print("REVIEW_TYPED_ZONE_END")
	print("REVIEW_PROBES_COMPLETE")
	quit()
