extends RefCounted

static func run(context: TestContext, parent: Node) -> void:
	_validate_solar_crucible(context)
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
	ship.position = door.get_center() - Vector2(0, door.size.y * 0.5 + GameConstants.SHIP_COLLISION_RADIUS)
	effects.step(8, 60, {2: ship})
	context.expect_equal(effects.hidden_cover, 34, "approaching a closed door does not reopen it")
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
	context.expect_true(effects.step(9.1, 60, {2: ship}).is_empty(), "expired grace does not apply a wave that already passed")
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
	_validate_combat(context, options)
	_validate_match_lifecycle(context, options)


static func _validate_combat(context: TestContext, options: Dictionary) -> void:
	for distance in [21.0, 150.0]:
		var world := AuthoritativeWorld.new()
		world.set_map_id(&"dead_freight")
		world.arena_effects.reset(world.map_id, options)
		var pilot := world.add_peer(2)
		pilot.position = Vector2(635 - distance, 550)
		pilot.stats.projectile_damage = 120
		pilot.aim_angle = 0
		world._spawn_shot(pilot)
		for tick in 30: world.step(1.0 / 60.0)
		context.expect_equal(world.arena_effects.hidden_cover, 1, "real shot destroys cargo at distance %s" % distance)
	var solar := AuthoritativeWorld.new()
	solar.set_map_id(&"twin_suns")
	solar.arena_effects.reset(solar.map_id, options)
	var victim := solar.add_peer(2)
	victim.position = Vector2(1500, 900)
	victim.health = 1
	solar.step_arena_effects(7, 60)
	context.expect_true(not victim.alive, "solar damage resolves through authoritative combat")
	var feedback := solar.drain_combat_feedback()
	context.expect_true(str(feedback).contains("solar_pulse"), "solar elimination retains explicit death attribution")
	context.expect_true(CombatFeedbackPresentation.death_text({"source": "solar_pulse"}, 2).contains("SOLAR PULSE"), "death explanation names the arena hazard")

static func _validate_match_lifecycle(context: TestContext, options: Dictionary) -> void:
	for selected_map in [&"twin_suns", &"dead_freight", &"switchyard", &"solar_crucible"]:
		for mode in range(5):
			var config := MatchConfig.new()
			config.arena_effects = options.duplicate()
			config.game_mode = mode
			config.draft_duration_seconds = 0.05
			config.countdown_duration_seconds = 0.05
			var lobby := ServerLobby.new(config)
			var world := AuthoritativeWorld.new()
			for peer in range(2, 34):
				lobby.admit(peer, "Pilot%d" % peer)
				world.add_peer(peer)
				lobby.request_ready(peer, true)
			lobby.request_start(2)
			var match_coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 42)
			match_coordinator._map_rotation = [selected_map]
			match_coordinator.start(0)
			for tick in 30:
				world.step(1.0 / 60.0, match_coordinator.controls_enabled())
				match_coordinator.step(1.0 / 60.0)
			context.expect_equal(match_coordinator.state(), MatchStateMachine.State.ACTIVE_HEAT, "effect match reaches combat on %s mode %d" % [selected_map, mode])
			context.expect_true(world.arena_effects.enabled != 0, "match initializes signature effect")
			for value in world.combatants.values():
				var pilot := value as CombatantState
				context.expect_true(ArenaCollisionSystem.is_ship_position_clear(pilot.position, selected_map, 0, world.arena_effects.hidden_cover), "all 32 effect-map spawns remain clear")
			world.server_tick = match_coordinator.machine.state_entered_tick + 7 * 60
			match_coordinator.step(1.0 / 60.0)
			context.expect_equal(match_coordinator.current_state_payload().arena_effect_state, world.arena_effects.snapshot(), "late spectator receives current terrain and pulse state")
			var before := world.arena_effects.snapshot()
			match_coordinator.request_pause(2, true)
			world.step(1)
			match_coordinator.step(1)
			context.expect_equal(before, world.arena_effects.snapshot(), "host pause freezes effect schedule")
			match_coordinator.request_pause(2, false)
			world.server_tick = match_coordinator.machine.state_entered_tick + 55 * 60
			match_coordinator.step(1.0 / 60.0)
			context.expect_true(world.arena_effects.safe, "every mode enters effect-safe overtime warning")


static func _validate_solar_crucible(context: TestContext) -> void:
	var effects := ArenaEffectState.new()
	effects.reset(&"solar_crucible", ArenaEffectRules.DEFAULT)
	context.expect_equal(effects.enabled, ArenaEffectRules.SOLAR, "Crucible hazards are intrinsic with optional effects off")
	var star := Vector2(1600, 900)
	var ship := CombatantState.create(2, CombatStats.create_base(), star + Vector2(150, 0))
	ship.shield.active = true
	ship.aim_angle = PI
	context.expect_empty(effects.step(2, 60, {2: ship}), "star contact respects opening grace")
	var hits := effects.step(3, 60, {2: ship})
	context.expect_true(hits.size() == 1 and hits[0].source == "star_contact" and hits[0].damage == 12.0, "star burns through active shields")
	context.expect_true(ship.velocity.x > 0.0, "contact nudges outward")
	context.expect_empty(effects.step(3.5, 60, {2: ship}), "contact damage has cooldown")
	context.expect_equal(effects.step(4.1, 60, {2: ship}).size(), 1, "remaining on star burns again after cooldown")
	effects.protect_respawn(2)
	context.expect_empty(effects.step(5.5, 60, {2: ship}), "respawn grace also blocks contact burns")
	effects.reset(&"solar_crucible", ArenaEffectRules.DEFAULT)
	ship.position = star + Vector2(600, 0)
	ship.shield.active = false
	context.expect_empty(effects.step(5.99, 60, {2: ship}), "three second warning deals no flare damage")
	context.expect_true(effects.warning, "flare warning is replicated")
	context.expect_empty(effects.step(6.5, 60, {2: ship}), "wave cannot hit before reaching ship")
	context.expect_equal(effects.step(7, 60, {2: ship}).size(), 1, "wave damages exposed ship when it arrives")
	context.expect_empty(effects.step(8, 60, {2: ship}), "wave damages each life once")
	effects.reset(&"solar_crucible", ArenaEffectRules.DEFAULT)
	ship.shield.reset(ship.stats)
	ship.shield.active = true
	context.expect_empty(effects.step(7, 60, {2: ship}), "inward shield blocks flare")
	effects.reset(&"solar_crucible", ArenaEffectRules.DEFAULT)
	ship.aim_angle = 0.0
	context.expect_equal(effects.step(7, 60, {2: ship}).size(), 1, "outward shield does not block flare")
	effects._flare_rng.seed = 42
	var intervals := {}
	for index in 8:
		var gap := effects._next_flare_start - effects._flare_start
		context.expect_true(gap >= 12.0 and gap <= 20.0, "random flare interval stays within recovery bounds")
		intervals[snappedf(gap, 0.001)] = true
		effects.step(effects._next_flare_start, 1000, {})
		context.expect_true(effects.warning, "each randomized flare starts with a warning")
	context.expect_true(intervals.size() > 1, "flare intervals vary")
	effects.reset(&"solar_crucible", ArenaEffectRules.DEFAULT)
	ship.position = star + Vector2(150, 0)
	context.expect_empty(effects.step(55, 60, {2: ship}), "overtime disables burns and flares")
	var sun_gravity := ArenaLayout.movement_fields(&"solar_crucible")[0]
	var hole_gravity := ArenaLayout.movement_fields(&"wormhole")[0]
	context.expect_approx(sun_gravity.gravity_acceleration, hole_gravity.gravity_acceleration * 0.25, "solar gravity is one quarter of black hole strength")
	context.expect_approx(sun_gravity.influence_at(star + Vector2(700, 0)), 0.0, "solar gravity stays localized")
	ship.velocity = Vector2.ZERO
	ship.shield.active = false
	ArenaMovementSystem.step_input(ship, PlayerInputFrame.new(1, 1, Vector2(0, -1), 0), 1.0 / 60.0, &"solar_crucible")
	context.expect_true(ship.velocity.x > 0.0, "normal thrust escapes surface gravity")
	var world := AuthoritativeWorld.new()
	world.set_map_id(&"solar_crucible")
	var victim := world.add_peer(2)
	victim.position = star + Vector2(150, 0)
	victim.health = 1
	world.step_arena_effects(4, 60)
	context.expect_true(not victim.alive, "contact burn resolves authoritative lethal damage")
	context.expect_true(str(world.drain_combat_feedback()).contains("star_contact"), "contact death names its hazard")
