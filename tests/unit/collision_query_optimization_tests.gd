extends RefCounted


static func run(context: TestContext) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 140014
	var hit_count := 0
	for map_id in ArenaLayout.map_ids():
		for radius in [0.0, 3.0, 7.0, 70.0]:
			var mismatches := 0
			for sample in 120:
				var start := Vector2(random.randf_range(-10, 3210), random.randf_range(-10, 1810))
				var finish := Vector2(random.randf_range(-10, 3210), random.randf_range(-10, 1810))
				if sample % 2 == 0:
					finish = start + Vector2(random.randf_range(-35, 35), random.randf_range(-35, 35))
				var expected: Variant = _exhaustive_sweep(start, finish, radius, map_id)
				var actual: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(start, finish, radius, map_id)
				if expected != null:
					hit_count += 1
				if (actual == null) != (expected == null):
					mismatches += 1
				elif actual != null and (absf(float(actual.fraction) - float(expected.fraction)) > 0.00001 or not (actual.normal as Vector2).is_equal_approx(expected.normal)):
					mismatches += 1
			context.expect_equal(mismatches, 0, "cached obstacle occupancy matches exhaustive sweep on %s radius %.0f" % [map_id, radius])
	context.expect_true(hit_count > 500, "obstacle parity exercises real contacts as well as empty short sweeps")
	_ship_grid_reset(context)
	_retained_geometry(context)
	_cargo_opens_mid_tick(context)


static func _exhaustive_sweep(start: Vector2, finish: Vector2, radius: float, map_id: StringName) -> Variant:
	var normal := ArenaCollisionSystem.projectile_obstacle_normal(start, radius, map_id)
	if not normal.is_zero_approx():
		return {"fraction": 0.0, "normal": normal}
	var direction := finish - start
	var fraction := INF
	for axis in 2:
		var minimum := radius
		var maximum := GameConstants.ARENA_SIZE[axis] - radius
		var candidate := INF
		var candidate_normal := Vector2.ZERO
		if direction[axis] < 0.0 and finish[axis] <= minimum:
			candidate = (minimum - start[axis]) / direction[axis]
			candidate_normal[axis] = 1.0
		elif direction[axis] > 0.0 and finish[axis] >= maximum:
			candidate = (maximum - start[axis]) / direction[axis]
			candidate_normal[axis] = -1.0
		if candidate < fraction:
			fraction = candidate
			normal = candidate_normal
	# Deliberately test every obstacle: this oracle does not use occupancy cells.
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		var hit := ArenaCollisionSystem._segment_aabb_hit_vector(start, direction, rectangle.grow(radius))
		if hit.x < fraction:
			fraction = hit.x
			normal = Vector2(hit.y, hit.z)
	for circle in ArenaLayout.circle_obstacles(map_id):
		var hit := ArenaCollisionSystem._segment_circle_hit_vector(start, direction, circle.center, float(circle.radius) + radius)
		if hit.x < fraction:
			fraction = hit.x
			normal = Vector2(hit.y, hit.z)
	return null if not is_finite(fraction) else {"fraction": fraction, "normal": normal}


static func _ship_grid_reset(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	var pilot := world.add_peer(2)
	var ids: Array[int] = [2]
	pilot.position = Vector2(200, 200)
	world.spatial_index.rebuild_ships(world.combatants, ids)
	context.expect_equal(world.spatial_index.query_ships_along_segment(Vector2(175, 175), Vector2(190, 190), 27), ids, "dense ship cache retains expanded boundary candidates")
	pilot.position = Vector2(2200, 1200)
	world.spatial_index.rebuild_ships(world.combatants, ids)
	context.expect_empty(world.spatial_index.query_ships_along_segment(Vector2(175, 175), Vector2(190, 190), 27), "moving ship releases its previous dense cells")
	context.expect_equal(world.spatial_index.query_ships_along_segment(Vector2(2175, 1175), Vector2(2190, 1190), 27), ids, "moving ship populates new dense cells")
	pilot.alive = false
	world.spatial_index.rebuild_ships(world.combatants, ids)
	context.expect_empty(world.spatial_index.query_ships_along_segment(Vector2(2175, 1175), Vector2(2190, 1190), 27), "dead ship releases dense cached candidates")
	pilot.alive = true
	pilot.position = Vector2(-500, -500)
	world.spatial_index.rebuild_ships(world.combatants, ids)
	context.expect_equal(world.spatial_index.query_ships_along_segment(Vector2(-500, -500), Vector2(-490, -490), 27), ids, "out-of-arena ship queries retain sparse fallback semantics")


static func _retained_geometry(context: TestContext) -> void:
	var references := preload("res://src/shared/arena/projectile_geometry_references.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 18092026
	var mismatches := 0
	for map_id in ArenaLayout.map_ids():
		for mask in [0, 1, 51, 34, 0]:
			references.prepare(map_id, mask)
			for radius in [GameConstants.PROJECTILE_RADIUS, 7.0, GameConstants.MISSILE_RADIUS, 3.001, 3.004]:
				var geometry := references.for_radius(radius)
				for sample in 100:
					var start := Vector2(rng.randf_range(0, 3200), rng.randf_range(0, 1800))
					var finish := start + Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
					var expected: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(start, finish, radius, map_id, {}, mask)
					var actual: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(start, finish, radius, map_id, geometry, mask)
					if actual != expected: mismatches += 1
				var rectangles := geometry.rectangles as Array
				var authored := ArenaCollisionSystem.cover_rectangles(map_id, mask)
				if not authored.is_empty():
					context.expect_true(rectangles[0] == authored[0].grow(radius), "geometry retains actual radius without rounding aliases")
	context.expect_equal(mismatches, 0, "retained sweeps preserve exact hit fractions, positions and normals across map/cover/radius changes")
	references.reset()
	references.prepare(&"dead_freight", 0)
	context.expect_true(references.for_radius(7.0) == ArenaCollisionSystem.projectile_geometry(&"dead_freight", 7.0), "session reset restores closed cover geometry")


static func _cargo_opens_mid_tick(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	world.set_map_id(&"dead_freight")
	var options := ArenaEffectRules.DEFAULT.duplicate()
	options.mode = ArenaEffectRules.SIGNATURE
	world.arena_effects.reset(world.map_id, options)
	var rectangle := ArenaLayout.cover_rectangles(world.map_id)[0]
	var stats := CombatStats.create_base()
	stats.projectile_damage = 150.0
	stats.projectile_speed = 1200.0
	var start := Vector2(rectangle.position.x - 12.0, rectangle.get_center().y)
	for id in [1, 2]:
		world.projectile_registry.add(ProjectileState.create(id, 90, id, start, 0.0, stats))
	world.step(1.0 / 60.0, true, false)
	context.expect_true((world.arena_effects.hidden_cover & 1) != 0, "first projectile destroys cargo within the tick")
	context.expect_true(world.projectile_registry.get_projectile(1) == null, "destroying projectile resolves its impact")
	var second := world.projectile_registry.get_projectile(2)
	context.expect_true(second != null and second.position.x > rectangle.position.x, "next projectile passes through cargo destroyed earlier in the same tick")
