extends RefCounted


static func run(context: TestContext) -> void:
	_roles(context)
	_routes(context)
	_drafts(context)
	_holding(context)


static func _roles(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	for peer_id in range(1, 7):
		world.add_peer(peer_id)
	world.set_team_assignments({1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 2})
	var controller := NpcPilotController.new()
	var objective := {"active": true, "mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "flag_position": Vector2(1600, 900), "flag_carrier_id": 0, "capture_zones": {1: Vector2(300, 900), 2: Vector2(2900, 900)}}
	context.expect_equal(controller.objective_intent(world, world.combatants[1], objective).role, &"retrieve", "lead NPC retrieves a loose flag")
	context.expect_equal(controller.objective_intent(world, world.combatants[3], objective).role, &"defend", "three-pilot team keeps a corridor defender")
	(world.combatants[1] as CombatantState).position = Vector2(1000, 900)
	objective.flag_carrier_id = 1
	context.expect_equal(controller.objective_intent(world, world.combatants[1], objective).role, &"runner", "carrier returns to its own scoring base")
	context.expect_equal(controller.objective_intent(world, world.combatants[2], objective).role, &"escort", "teammate escorts an allied carrier")
	context.expect_equal(controller.objective_intent(world, world.combatants[3], objective).role, &"defend", "defender clears the carrier return corridor")
	context.expect_equal(controller.objective_intent(world, world.combatants[4], objective).role, &"intercept", "opposing NPC intercepts the carrier")
	context.expect_equal(controller._objective_target(world, world.combatants[4], objective), world.combatants[1], "interception targets the public carrier ahead of unrelated duels")
	objective.active = false
	context.expect_empty(controller.objective_intent(world, world.combatants[2], objective), "inactive objective never retains a role")
	controller._objective_navigation._routes[2] = {"old": true}
	controller._objective_steering(world, world.combatants[2], objective)
	context.expect_empty(controller._objective_navigation._routes, "inactive objective discards stale navigation")
	controller._objective_navigation._routes[2] = {"old": true}
	controller.objective_roles[2] = &"retrieve"
	objective.active = true
	controller._objective_steering(world, world.combatants[2], objective)
	context.expect_false((controller._objective_navigation._routes.get(2, {}) as Dictionary).has("old"), "role change drops the previous objective route immediately")
	controller.objective_roles[2] = &"escort"
	controller.remove_peer(2)
	context.expect_empty(controller.objective_roles, "departing pilots release role state")


static func _routes(context: TestContext) -> void:
	for map_id in ArenaLayout.map_ids():
		var start := Vector2(400, 900)
		var destination := Vector2(2800, 900)
		var route := NpcObjectiveNavigation.plan_route(start, destination, map_id)
		context.expect_true(not route.is_empty(), "objective route exists across %s" % map_id)
		var previous := start
		for point in route:
			context.expect_true(NpcObjectiveNavigation.segment_clear(previous, point, map_id), "objective route segment clears ship-sized collision on %s" % map_id)
			previous = point
		var world := AuthoritativeWorld.new()
		world.set_map_id(map_id)
		var pilot := world.add_peer(1)
		pilot.position = start
		var controller := NpcPilotController.new()
		var peers: Array[int] = [1]
		var objective := {"active": true, "mode": GameModeRules.Mode.KING_OF_THE_HILL, "position": destination}
		for tick in 1800:
			controller.submit_inputs(world, peers, {1: NpcPilotController.Difficulty.NEUTRAL}, -1.0, objective)
			world.step(1.0 / 60.0)
		context.expect_true(pilot.position.distance_to(destination) < 120.0, "NPC physically reaches objective around cover on %s (distance %.1f)" % [map_id, pilot.position.distance_to(destination)])
	var navigation := NpcObjectiveNavigation.new()
	for peer_id in range(1, 9):
		navigation.steering(peer_id, Vector2(1000, 900), Vector2(2200, 900), &"core_arena", 10)
	context.expect_equal(navigation._plans_this_tick, NpcObjectiveNavigation.MAX_PLANS_PER_TICK, "objective route work is bounded during simultaneous decisions")
	navigation.clear()
	context.expect_empty(navigation._routes, "session reset releases cached pilot routes")


static func _drafts(context: TestContext) -> void:
	var catalog := CardCatalog.new()
	var speed := CardDefinition.new()
	speed.card_id = &"test_speed"
	speed.additive_modifiers = {&"max_speed": 120.0}
	var hull := CardDefinition.new()
	hull.card_id = &"test_hull"
	hull.additive_modifiers = {&"max_health": 20.0}
	speed.display_name = "Speed"
	speed.description = "Test speed"
	catalog.add_card(speed)
	hull.display_name = "Hull"
	hull.description = "Test hull"
	catalog.add_card(hull)
	var player := PlayerMatchState.new(1, "NPC", 1)
	var choices: Array[StringName] = [speed.card_id, hull.card_id]
	context.expect_equal(NpcDraftPolicy.choose_card(player, choices, catalog, GameModeRules.Mode.CAPTURE_THE_FLAG, {1: player}), speed.card_id, "flag runner drafts movement from an equal utility offer")
	context.expect_equal(NpcDraftPolicy.choose_card(player, choices, catalog, GameModeRules.Mode.KING_OF_THE_HILL, {1: player}), hull.card_id, "hill holder drafts survival from the same offer")
	player.card_stacks[speed.card_id] = 100
	context.expect_equal(NpcDraftPolicy.choose_card(player, choices, catalog, GameModeRules.Mode.CAPTURE_THE_FLAG, {1: player}), hull.card_id, "saturated mobility build chooses remaining effective survival instead")



static func _holding(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	world.set_map_id(&"prism_array")
	var center := Vector2(1600, 900)
	var pilot := world.add_peer(2)
	pilot.position = center
	var durable := CombatStats.create_base()
	durable.max_health = 100000.0
	var target := world.add_peer(3, durable)
	target.position = center + Vector2(600, 0)
	var controller := NpcPilotController.new()
	var objective := {"active": true, "mode": GameModeRules.Mode.KING_OF_THE_HILL, "position": center, "controller_id": 2}
	var ids: Array[int] = [2]
	var maximum_distance := 0.0
	for tick in 1200:
		controller.submit_inputs(world, ids, {2: NpcPilotController.Difficulty.SKILLED}, -1.0, objective)
		world.step(1.0 / 60.0)
		maximum_distance = maxf(maximum_distance, pilot.position.distance_to(center))
	context.expect_true(maximum_distance < GameModeRules.OBJECTIVE_ZONE_RADIUS, "arrived hill holder keeps control while firing at an outside enemy (max offset %.1f)" % maximum_distance)
	context.expect_true(world.combat_contact_serial > 0, "holding position still engages visible enemies")
	world = AuthoritativeWorld.new()
	world.set_map_id(&"prism_array")
	for peer_id in [2, 3]:
		var contestant := world.add_peer(peer_id, durable)
		contestant.position = center + Vector2(-20 if peer_id == 2 else 20, 0)
	controller = NpcPilotController.new()
	ids = [2, 3]
	objective.controller_id = 0
	for tick in 900:
		controller.submit_inputs(world, ids, {2: NpcPilotController.Difficulty.SKILLED, 3: NpcPilotController.Difficulty.SKILLED}, -1.0, objective)
		world.step(1.0 / 60.0)
	context.expect_true(world.combat_contact_serial > 0, "crowded hill contenders separate enough to resume combat")
