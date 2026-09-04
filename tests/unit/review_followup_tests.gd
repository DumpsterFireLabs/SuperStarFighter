extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_cloak_replication(context, parent)
	_objective_reveals(context)
	_automatic_drafts(context)
	_objective_presentation(context, parent)


static func _cloak_replication(context: TestContext, parent: Node) -> void:
	var world := AuthoritativeWorld.new()
	for peer in 32:
		world.add_peer(peer + 1)
	var hidden := world.combatants[2] as CombatantState
	hidden.cloak_remaining = 5.0
	hidden.position = Vector2(999, 777)
	hidden.velocity = Vector2(321, 123)
	world.set_team_assignments({1: 1, 2: 1})
	for recipient in [0, 1, 2, 3, 99]:
		var body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), recipient)
		var correction := hidden.prediction_state() if recipient == 2 else {}
		var packet := PlayerSnapshotCodec.assemble(10, 0, body, correction)
		var decoded := PlayerSnapshotCodec.decode(packet)
		var ids: Array[int] = []
		for state in decoded.states:
			ids.append(int(state.peer_id))
		context.expect_equal(ids.has(2), recipient == 2, "only owner receives cloaked state, including against allies and late spectators")
		context.expect_equal(ids.size(), 32 if recipient == 2 else 31, "visibility-filtered snapshot count matches serialized records")
		context.expect_true(packet.size() <= 1200, "private cloak snapshot stays inside transport budget")
	var client: Node = load("res://scenes/client/client_main.tscn").instantiate()
	parent.add_child(client)
	var view := client.network_world as NetworkWorldView
	view.local_peer_id = 1
	view.apply_match_state({"state_name": "ACTIVE_HEAT", "game_mode": 0})
	# First visible, then hidden, then revealed at a new location.
	hidden.cloak_remaining = 0.0
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.assemble(11, 0, PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), 1))))
	context.expect_true(view.ships.has(2), "visible opponent creates production ship")
	hidden.cloak_remaining = 5.0
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.assemble(12, 0, PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), 1))))
	context.expect_false(view.ships.has(2), "cloak omission removes ship from client targeting and markers")
	context.expect_false(view.presentation_states.has(2), "cloak omission discards prior feedback history")
	context.expect_false(2 in view._living_spectator_targets(), "spectator cannot follow cloaked pilot")
	hidden.cloak_remaining = 0.0
	hidden.position = Vector2(1400, 900)
	hidden.health = 50.0
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.assemble(13, 0, PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), 1))))
	context.expect_equal((view.ships[2] as CombatShipView).global_position, hidden.position, "reveal starts at fresh position without interpolation through hidden travel")
	context.expect_equal(float(view.presentation_states[2].health), 50.0, "reveal initializes feedback at current health")
	client.latest_match_payload = {"game_mode": GameModeRules.Mode.KING_OF_THE_HILL, "objective": {"mode": GameModeRules.Mode.KING_OF_THE_HILL, "controller_id": 0, "progress": {1: 5.0, 2: 5.0}}}
	context.expect_true(client._objective_status_text().contains("NEUTRAL"), "empty hill is not mislabeled contested")
	context.expect_true(client._objective_status_text().contains("TIED LEAD"), "equal accumulated hill leaders do not favor dictionary order")
	client.latest_match_payload.objective.contested = true
	context.expect_true(client._objective_status_text().contains("CONTESTED"), "HUD uses authoritative hill contest state")
	parent.remove_child(client)
	client.free()


static func _objective_reveals(context: TestContext) -> void:
	for mode in [GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG]:
		var fixture := MatchCoordinatorTests._objective_fixture(mode, 3, 1800 + mode)
		var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
		var world := fixture.world as AuthoritativeWorld
		var pilot := world.combatants[1] as CombatantState
		pilot.position = coordinator._objective_position
		pilot.cloak_remaining = 5.0
		coordinator._step_game_mode(1.0 / 60.0, world.server_tick)
		context.expect_false(pilot.is_cloaked(), "touching active objective explicitly reveals cloak in mode %d" % mode)
		if GameModeRules.uses_flag(mode):
			context.expect_equal(coordinator._flag_carrier_id, 1, "cloak reveal still permits normal flag pickup")
			pilot.cloak_remaining = 5.0
			coordinator._step_game_mode(1.0 / 60.0, world.server_tick + 1)
			context.expect_false(pilot.is_cloaked(), "carrying flag cannot resume secret movement")
		else:
			var rival := world.combatants[2] as CombatantState
			rival.position = coordinator._objective_position
			rival.cloak_remaining = 5.0
			coordinator._step_game_mode(1.0 / 60.0, world.server_tick + 1)
			context.expect_true(coordinator._objective_snapshot().contested, "multiple hill occupants are explicitly contested")
			context.expect_false(rival.is_cloaked(), "contesting hill also reveals cloak")
	# Existing homing counter remains deliberate, rather than changing silently.
	var world := AuthoritativeWorld.new()
	world.add_peer(1).position = Vector2(300, 300)
	var target := world.add_peer(2)
	target.position = Vector2(450, 300)
	target.cloak_remaining = 5.0
	context.expect_equal(world._acquire_missile_target(1, Vector2(300, 300), Vector2.RIGHT, 1000), 2, "missiles retain acquisition against cloaked pilots")


static func _automatic_drafts(context: TestContext) -> void:
	var full := CardCatalog.create_default()
	var catalog := CardCatalog.new()
	catalog.add_card(full.get_card(&"twin_shot"))
	catalog.add_card(full.get_card(&"reinforced_hull"))
	var build := {&"twin_shot": 5}
	context.expect_false(StatSystem.has_effective_benefit(build, full.get_card(&"twin_shot"), full), "sixth Twin Shot has no effective upside")
	context.expect_true(StatSystem.has_effective_benefit(build, full.get_card(&"reinforced_hull"), full), "uncapped hull remains an effective choice")
	context.expect_true(StatSystem.has_effective_benefit({}, full.get_card(&"cloak"), full), "new ability is an effective benefit")
	var pilot := PlayerMatchState.new(1, "Capped", 1)
	pilot.card_stacks = build.duplicate()
	var draft := DraftManager.new(catalog, 4)
	draft.start_draft({1: pilot}, 1)
	context.expect_true(&"twin_shot" in draft.get_offer(1).card_ids, "manual acquisition remains unlimited despite no upside")
	context.expect_equal(draft.automatic_card_ids(1), [&"reinforced_hull"], "NPC and timeout candidate set avoids drawback-only pick")
	draft.resolve_timeout()
	context.expect_equal(draft.get_offer(1).selected_card_id, &"reinforced_hull", "timeout applies useful offered card")
	var exhausted := CardCatalog.new()
	exhausted.add_card(full.get_card(&"twin_shot"))
	var fallback := DraftManager.new(exhausted, 4)
	fallback.start_draft({1: pilot}, 1)
	fallback.resolve_timeout()
	context.expect_equal(fallback.get_offer(1).selected_card_id, &"twin_shot", "all-capped draft still resolves without deadlock")
	var ids := catalog.all_ids()
	ids.clear()
	context.expect_equal(catalog.all_ids().size(), 2, "caller cannot mutate cached catalog ordering")
	catalog.add_card(full.get_card(&"cloak"))
	context.expect_equal(catalog.all_ids(), [&"cloak", &"reinforced_hull", &"twin_shot"], "catalog insertion invalidates sorted ID cache")


static func _objective_presentation(context: TestContext, parent: Node) -> void:
	var arena := ArenaView.new()
	parent.add_child(arena)
	arena.local_peer_id = 7
	arena.local_team_id = 2
	arena.set_objective({"active": true, "mode": GameModeRules.Mode.KING_OF_THE_HILL, "controller_id": 7, "progress": {"7": 10.0}, "target_seconds": 20.0})
	context.expect_true(arena.hill_status().label.contains("YOU"), "own hill control is explicit")
	context.expect_equal(arena.hill_status().progress, 0.5, "hill arc uses authoritative progress")
	arena.objective_state.controller_id = 8
	context.expect_true(arena.hill_status().label.contains("PILOT 8"), "opponent hill owner is identified")
	arena.objective_state.contested = true
	context.expect_true(arena.hill_status().label.contains("CONTESTED"), "contested hill differs from neutral")
	arena.set_objective({"active": true, "mode": GameModeRules.Mode.CAPTURE_THE_FLAG, "flag_carrier_id": 0, "flag_position": Vector2(2400, 900), "capture_zones": {"7": Vector2(200, 900), "8": Vector2(3000, 900)}})
	context.expect_equal(arena.base_label(7), "YOUR BASE", "solo base identifies ownership")
	context.expect_equal(arena.base_label(8), "PILOT 8 BASE", "other solo base identifies owner")
	arena.pilot_names[8] = "Rival"
	context.expect_equal(arena.base_label(8), "RIVAL BASE", "base uses public pilot identity instead of opaque transport ID")
	context.expect_equal(arena.navigation_targets().size(), 2, "flag navigation includes flag and own base")
	arena.objective_state.flag_carrier_id = 7
	context.expect_equal(arena.navigation_targets().size(), 1, "carrier gets only the useful return direction")
	context.expect_equal(arena.navigation_targets()[0].label, "RETURN FLAG", "carrier navigation explains next action")
	arena.objective_state.mode = GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG
	arena.objective_state.capture_zones = {2: Vector2(3000, 900)}
	context.expect_equal(arena.base_label(2), "YOUR TEAM BASE", "team base uses local authoritative team")
	arena.set_map_id(&"riftline")
	context.expect_equal(arena.static_layer.map_id, &"riftline", "static drawing updates with collision map")
	arena.show_spawn_anchors = true
	context.expect_true(arena.static_layer.show_spawn_anchors, "lab spawn overlay updates cached static drawing")
	arena.set_objective({})
	context.expect_empty(arena.navigation_targets(), "leaving objective mode clears navigation")
	parent.remove_child(arena)
	arena.free()
