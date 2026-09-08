extends RefCounted


static func run(context: TestContext) -> void:
	_roles(context)
	_routes(context)
	_drafts(context)
	_draft_combat_effects(context)
	_beam_aim(context)
	_holding(context)


static func _roles(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	for peer_id in range(1, 7):
		world.add_peer(peer_id)
	world.set_team_assignments({1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 2})
	var controller := NpcPilotController.new()
	var objective := ObjectiveState.new()
	objective.active = true
	objective.mode = GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG
	objective.flag_position = Vector2(1600, 900)
	objective.capture_zones = {1: Vector2(300, 900), 2: Vector2(2900, 900)}
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
		var objective := ObjectiveState.new()
		objective.active = true
		objective.mode = GameModeRules.Mode.KING_OF_THE_HILL
		objective.position = destination
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



static func _draft_combat_effects(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	var player := PlayerMatchState.new(1, "NPC", 1)
	var players := {1: player}
	var hill := GameModeRules.Mode.KING_OF_THE_HILL
	var flag := GameModeRules.Mode.CAPTURE_THE_FLAG
	context.expect_equal(NpcDraftPolicy.choose_card(player, [&"tight_bore", &"efficient_field"], catalog, hill, players), &"efficient_field", "hill NPC values lower shield drain over a zero-spread dud")
	context.expect_equal(NpcDraftPolicy.choose_card(player, [&"tight_bore", &"shielded_drive"], catalog, flag, players), &"shielded_drive", "flag NPC recognizes shielded mobility and efficiency")
	# Isolate formerly ignored effects, including their downside directions.
	var base := CombatStats.create_base()
	for property in [&"shield_continuous_drain", &"shield_block_cost", &"shield_regeneration_delay", &"shield_depletion_threshold", &"shield_arc_degrees", &"shield_acceleration_factor"]:
		var improved := base.duplicate_stats()
		var worsened := base.duplicate_stats()
		var lower: bool = property in StatSystem.LOWER_IS_BETTER
		improved.set(property, float(base.get(property)) * (0.8 if lower else 1.2))
		worsened.set(property, float(base.get(property)) * (1.2 if lower else 0.8))
		for role in [&"runner", &"assault", &"defend", &"escort"]:
			context.expect_true(NpcDraftPolicy.utility(improved, role) > NpcDraftPolicy.utility(base, role), "%s role values beneficial %s" % [role, property])
			context.expect_true(NpcDraftPolicy.utility(worsened, role) < NpcDraftPolicy.utility(base, role), "%s role accounts for adverse %s" % [role, property])
	var speed := _draft_test_card(&"test_projectile_speed", {"projectile_speed": 1.5})
	var lifetime := _draft_test_card(&"test_projectile_lifetime", {"projectile_lifetime": 1.1})
	var arc := _draft_test_card(&"test_shield_arc", {"shield_arc_degrees": 1.2})
	var mild_loss := _draft_test_card(&"test_mild_loss", {"shield_continuous_drain": 1.1})
	var severe_loss := _draft_test_card(&"test_severe_loss", {"shield_continuous_drain": 2.0})
	for card in [speed, lifetime, arc, mild_loss, severe_loss]:
		context.expect_true(catalog.add_card(card), "draft policy fixture is a valid offered card")
	var choices: Array[StringName] = [speed.card_id, lifetime.card_id]
	context.expect_equal(NpcDraftPolicy.choose_card(player, choices, catalog, hill, players), speed.card_id, "projectile build values speed for both delivery and reach")
	player.card_stacks = {&"beam_emitter": 1}
	context.expect_equal(NpcDraftPolicy.choose_card(player, choices, catalog, hill, players), lifetime.card_id, "beam build selects actual lifetime benefit over overridden speed")
	var beam := StatSystem.derive(player.card_stacks, catalog)
	var fake_speed := beam.duplicate_stats()
	fake_speed.projectile_speed *= 1.5
	context.expect_approx(NpcDraftPolicy.utility(fake_speed, &"defend"), NpcDraftPolicy.utility(beam, &"defend"), "overridden beam speed receives no phantom utility")
	player.card_stacks = {&"omnidirectional_field": 1}
	context.expect_equal(NpcDraftPolicy.choose_card(player, [arc.card_id, &"efficient_field"], catalog, hill, players), &"efficient_field", "capped coverage does not beat a working drain reduction")
	player.card_stacks = {&"twin_shot": 2}
	context.expect_equal(NpcDraftPolicy.choose_card(player, [&"twin_shot", &"hollow_points"], catalog, hill, players), &"hollow_points", "NPC compares combined output when a pre-cap multishot repeat lowers damage")
	player.card_stacks.clear()
	context.expect_equal(NpcDraftPolicy.choose_card(player, [severe_loss.card_id, mild_loss.card_id], catalog, hill, players), mild_loss.card_id, "all-negative offers still resolve to the less harmful offered pick")
	context.expect_true(speed.card_id in catalog.eligible_ids({&"beam_emitter": 1}), "dead beam speed card remains eligible for offers")
	context.expect_true(&"damage_control" in catalog.eligible_ids({}), "repair prerequisite is not added to offer eligibility")
	context.expect_equal(NpcDraftPolicy.choose_card(player, [], catalog, hill, players), &"", "empty NPC offer remains empty")
	# Exercise the whole real card pool at ordinary and heavily capped builds.
	for id in CardCatalog.create_default().all_ids():
		for stacks in [1, 3, 20]:
			var stats := StatSystem.derive({id: stacks}, catalog)
			for role in [&"runner", &"assault", &"defend", &"escort"]:
				context.expect_true(is_finite(NpcDraftPolicy.utility(stats, role)), "%s x%d has finite utility for %s" % [id, stacks, role])


static func _draft_test_card(id: StringName, multipliers: Dictionary) -> CardDefinition:
	var card := CardDefinition.new()
	card.card_id = id
	card.display_name = String(id)
	card.description = "NPC evaluation fixture."
	card.multiplicative_modifiers = multipliers
	return card


static func _beam_aim(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	var beam := StatSystem.derive({&"beam_emitter": 1}, catalog)
	var accelerated := beam.duplicate_stats()
	accelerated.projectile_speed *= 2.0
	var base := CombatStats.create_base()
	var beam_angle := _moving_target_aim(beam)
	context.expect_approx(_moving_target_aim(accelerated), beam_angle, "ignored beam speed modifiers do not change NPC aim")
	context.expect_true(_moving_target_aim(base) > beam_angle, "slower projectiles need more lead than beams")
	var shot := ProjectileState.create(1, 2, 1, Vector2.ZERO, 0.0, beam)
	var profile := NpcPilotController.difficulty_profile(NpcPilotController.Difficulty.SKILLED)
	var expected := Vector2(600.0, 200.0 * 600.0 / shot.velocity.length() * float(profile.lead_factor)).angle()
	expected += sin(2.0 * 0.73) * deg_to_rad(float(profile.aim_error_degrees))
	context.expect_approx(beam_angle, expected, "NPC lead uses the speed of the actual created beam")


static func _moving_target_aim(stats: CombatStats) -> float:
	var world := AuthoritativeWorld.new()
	world.add_peer(2, stats).position = Vector2(400, 400)
	var target := world.add_peer(3)
	target.position = Vector2(1000, 400)
	target.velocity = Vector2(0, 200)
	var npc := NpcPilotController.new()
	npc.submit_inputs(world, [2], {2: NpcPilotController.Difficulty.SKILLED})
	return (world.latest_inputs[2] as PlayerInputFrame).aim_angle


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
	var objective := ObjectiveState.new()
	objective.active = true
	objective.mode = GameModeRules.Mode.KING_OF_THE_HILL
	objective.position = center
	objective.controller_id = 2
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
