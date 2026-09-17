extends RefCounted

static func run(context: TestContext, parent: Node) -> void:
	var options := ArenaEffectRules.DEFAULT.duplicate()
	context.expect_true(ArenaEffectRules.valid(options), "default arena settings validate")
	context.expect_equal(ArenaEffectRules.enabled(options, &"twin_suns"), 0, "effects default off")
	options.mode = ArenaEffectRules.SIGNATURE
	context.expect_equal(ArenaEffectRules.enabled(options, &"twin_suns"), ArenaEffectRules.SOLAR, "Twin Suns enables only solar pulses")
	context.expect_equal(ArenaEffectRules.enabled(options, &"core_arena"), 0, "unsupported maps stay static")
	var invalid := options.duplicate()
	invalid.frequency = 99
	context.expect_true(not ArenaEffectRules.valid(invalid), "frequency rejects invalid remote values")
	invalid.frequency = 1.0
	context.expect_true(not ArenaEffectRules.valid(invalid), "settings reject wrong wire types")
	options.mode = ArenaEffectRules.CUSTOM
	options.mask = ArenaEffectRules.CARGO
	context.expect_equal(ArenaEffectRules.enabled(options, &"twin_suns"), 0, "custom masks cannot enable incompatible effects")
	options.mode = ArenaEffectRules.SIGNATURE
	var lobby := ServerLobby.new()
	lobby.admit(2, "Host")
	lobby.admit(3, "Guest")
	context.expect_true(not lobby.request_arena_effects(3, options).ok, "guests cannot change arena settings")
	context.expect_true(lobby.request_arena_effects(2, options).ok, "leader can change arena settings")
	options.strength = 2
	context.expect_equal(lobby.config.arena_effects.strength, 1, "lobby stores a detached settings copy")
	options.strength = 1
	lobby.match_active = true
	context.expect_true(not lobby.request_arena_effects(2, options).ok, "effects cannot change mid-match")

	var effects := ArenaEffectState.new()
	effects.reset(&"dead_freight", options)
	var rectangle := ArenaLayout.cover_rectangles(&"dead_freight")[0]
	var impact := rectangle.position + Vector2(-3, 50)
	context.expect_true(effects.damage_cover(impact, 4, 60), "projectiles damage authored cargo")
	context.expect_equal(effects.hidden_cover, 0, "damaged cover remains solid")
	effects.damage_cover(impact, 4, 60)
	context.expect_equal(effects.hidden_cover, 1, "destroyed cover opens one lane")
	context.expect_true(ArenaCollisionSystem.is_ship_position_clear(rectangle.get_center(), &"dead_freight", 0, effects.hidden_cover), "destroyed cover allows ship passage")
	context.expect_true(not ArenaCollisionSystem.is_ship_position_clear(rectangle.get_center(), &"dead_freight"), "dynamic state never mutates shared map geometry")
	var start := rectangle.get_center() - Vector2(300, 0)
	var finish := rectangle.get_center() + Vector2(300, 0)
	context.expect_true(ArenaCollisionSystem.has_clear_line_of_sight(start, finish, &"dead_freight", effects.hidden_cover), "destroyed cover opens projectile sightline")
	context.expect_true(not ArenaCollisionSystem.has_clear_line_of_sight(start, finish, &"dead_freight"), "static projectile cache remains isolated")
	context.expect_true(NpcObjectiveNavigation.segment_clear(start, finish, &"dead_freight", 20, effects.hidden_cover), "NPC routes use destroyed cover state")
	var payload := effects.snapshot()
	(payload.cargo_health as Dictionary)[0] = 999
	context.expect_equal(effects.cargo_health[0], 0.0, "network payload cannot mutate health")
	effects.reset(&"dead_freight", options)
	context.expect_equal(effects.hidden_cover, 0, "next heat restores cargo")
	effects.step(25, 30, {})
	context.expect_equal(effects.hidden_cover, 63, "overtime warning clears breakable cargo")

	effects.reset(&"switchyard", options)
	var door := ArenaLayout.cover_rectangles(&"switchyard")[0]
	var ship := CombatantState.create(2, CombatStats.create_base(), door.get_center())
	context.expect_equal(effects.hidden_cover, 51, "doors start open through countdown")
	effects.step(4, 60, {2: ship})
	context.expect_equal(effects.door_warning_mask, 17, "doors telegraph closing group")
	effects.step(6, 60, {2: ship})
	context.expect_true((effects.hidden_cover & 1) != 0, "occupied door waits rather than crushing ship")
	ship.position = Vector2(400, 400)
	effects.step(7, 60, {2: ship})
	context.expect_equal(effects.hidden_cover, 34, "clear doors close after warning")
	effects.step(25, 60, {2: ship})
	context.expect_equal(effects.hidden_cover, 17, "next cycle alternates barrier group")
	effects.step(55, 60, {2: ship})
	context.expect_equal(effects.hidden_cover, 51, "overtime opens every door")

	effects.reset(&"twin_suns", options)
	ship.position = Vector2(1500, 900)
	context.expect_true(effects.step(2, 60, {2: ship}).is_empty(), "opening grace prevents solar damage")
	context.expect_true(effects.step(4, 60, {2: ship}).is_empty() and effects.warning, "solar warning precedes damage")
	context.expect_equal(effects.step(7, 60, {2: ship}).size(), 1, "expanding pulse hits exposed ship")
	context.expect_true(effects.step(8, 60, {2: ship}).is_empty(), "pulse hits a life only once")
	effects.reset(&"twin_suns", options)
	ship.position = Vector2(2500, 900)
	context.expect_true(effects.step(9, 60, {2: ship}).is_empty(), "opposite reactor provides solar shelter")
	effects.reset(&"twin_suns", options)
	ship.position = Vector2(1500, 900)
	ship.aim_angle = PI
	ship.shield.active = true
	context.expect_true(effects.step(7, 60, {2: ship}).is_empty(), "shield facing source blocks solar pulse")
	ship.shield.active = false
	effects.reset(&"twin_suns", options)
	effects.step(6, 60, {})
	effects.protect_respawn(2)
	context.expect_true(effects.step(7, 60, {2: ship}).is_empty(), "respawn grace protects newly returned pilot")
	context.expect_true(effects.step(55, 60, {2: ship}).is_empty() and effects.pulse_radius < 0, "solar wave cancels at overtime warning")
	var world := AuthoritativeWorld.new()
	world.set_map_id(&"dead_freight")
	world.arena_effects.reset(world.map_id, options)
	world.arena_effects.damage_cover(impact, 4, 120)
	var pilot := world.add_peer(2)
	pilot.position = rectangle.get_center()
	var prediction := ClientPredictionBuffer.new()
	prediction.predicted_position = pilot.position
	prediction.hidden_cover = world.arena_effects.hidden_cover
	var frame := PlayerInputFrame.new(1, 1, Vector2.ZERO, 0)
	world.submit_input(2, frame)
	world.step(1.0 / 60.0)
	prediction.predict(frame, pilot.stats, 1.0 / 60.0, world.map_id)
	context.expect_equal(pilot.position, prediction.predicted_position, "prediction and authority agree inside destroyed terrain")
	var saved := world.arena_effects.snapshot()
	world.simulation_paused = true
	world.step(1.0)
	context.expect_equal(world.arena_effects.snapshot(), saved, "paused world preserves effect state")
	var arena := ArenaView.new()
	parent.add_child(arena)
	arena.set_map_id(&"dead_freight")
	arena.set_effect_state(world.arena_effects.snapshot())
	context.expect_equal(arena.hidden_cover, 1, "client applies authoritative terrain mask")
	context.expect_equal(arena.obstacle_root.get_child_count(), 5, "client removes destroyed collision body")
	arena.set_effect_state({})
	context.expect_equal(arena.obstacle_root.get_child_count(), 6, "client reset restores solid collision bodies")
	arena.free()
