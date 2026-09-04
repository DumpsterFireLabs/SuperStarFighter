extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_sweep_parity(context)
	_effect_pressure(context, parent)


static func _sweep_parity(context: TestContext) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 518621
	var world := AuthoritativeWorld.new()
	var ids: Array[int] = []
	for peer in range(1, 33):
		var pilot := world.add_peer(peer)
		pilot.position = Vector2(random.randf_range(50, 3150), random.randf_range(50, 1750))
		ids.append(peer)
	# Two equidistant hits and a ship whose collision circle crosses a cell edge.
	world.combatants[1].position = Vector2(200, 200)
	world.combatants[2].position = Vector2(200, 200)
	world.spatial_index.rebuild_ships(world.combatants, ids)
	var confirmed_hits := 0
	for radius in [3.0, 7.0, 70.0]:
		var mismatches := 0
		for sample in 240:
			var start := Vector2(random.randf_range(0, 3200), random.randf_range(0, 1800))
			var finish := Vector2(random.randf_range(0, 3200), random.randf_range(0, 1800))
			if sample == 0:
				start = Vector2(150, 190)
				finish = Vector2(220, 190)
			elif sample % 2 == 0:
				finish = start + Vector2(20, -15)
			var shot := ProjectileState.create(1, 99, 1, start, 0, CombatStats.create_base())
			shot.radius = radius
			var expected_id := 0
			var expected_fraction := INF
			for peer in ids:
				var fraction := world._segment_circle_hit_fraction(start, finish, world.combatants[peer].position, GameConstants.SHIP_COLLISION_RADIUS + radius)
				if fraction >= 0 and fraction < expected_fraction:
					expected_fraction = fraction
					expected_id = peer
			var actual: Variant = world._nearest_projectile_ship_hit(shot, start, finish, ids)
			if expected_id > 0:
				confirmed_hits += 1
			if (0 if actual == null else int(actual.peer_id)) != expected_id:
				mismatches += 1
			elif actual != null and absf(actual.fraction - expected_fraction) > 0.00001:
				mismatches += 1
		context.expect_equal(mismatches, 0, "expanded ship index matches exhaustive short/long sweeps, cell edges and ties at radius %.0f" % radius)
	context.expect_true(confirmed_hits > 100, "sweep equivalence fixture exercises real hits, not only empty cells")
	world.spatial_index.rebuild_ships({}, [])
	context.expect_true(world.spatial_index.query_ships_along_segment(Vector2.ZERO, Vector2(500, 500), 50).is_empty(), "rebuilding empty ship index removes prior candidates")


static func _effect_pressure(context: TestContext, parent: Node) -> void:
	var effects := CombatEffectsLayer.new()
	parent.add_child(effects)
	for index in 1000:
		effects.spawn_impact(Vector2(500, 500))
	context.expect_true(effects.effects.size() <= effects.DECORATIVE_EFFECT_LIMIT, "decorative contact flood leaves capacity for gameplay feedback")
	effects.spawn_damage(Vector2(600, 500), Vector2.RIGHT, true)
	for index in 200:
		effects.spawn_kinetic_vent(Vector2(500, 500))
		effects.spawn_elimination(Vector2(500, 500), Color.WHITE)
		effects.spawn_impact(Vector2(500, 500))
	var local_survives := false
	for effect in effects.effects:
		local_survives = local_survives or (effect.kind == &"damage" and effect.position == Vector2(600, 500))
	context.expect_true(local_survives, "local hull damage survives lower-priority effect pressure")
	context.expect_true(effects.effects.size() <= effects.MAX_ACTIVE_EFFECTS, "mixed burst memory is bounded")
	context.expect_true(effects.dropped_effect_count > 0, "suppressed decoration is measurable")
	effects.clear_effects()
	for index in 100:
		effects.spawn_mine_explosion(Vector2(500, 500))
	effects._process(1.0)
	context.expect_equal(effects.active_mine_effect_count, 0, "mine reservation is released after effects expire")
	context.expect_true(effects.effects.is_empty(), "effect flood drains fully after expiry")
	effects.visible_world_rect = Rect2(0, 0, 100, 100)
	effects.spawn_impact(Vector2(3000, 1700))
	context.expect_true(effects.effects.is_empty(), "distant decoration does not occupy the visible feedback budget")
	parent.remove_child(effects)
	effects.free()
