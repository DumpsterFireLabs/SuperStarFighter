class_name ArenaCollisionSystem
extends RefCounted


static func move_ship(position: Vector2, velocity: Vector2, delta: float, map_id: StringName = ArenaLayout.DEFAULT_MAP_ID) -> Dictionary:
	var next_position := position + velocity * maxf(delta, 0.0)
	var next_velocity := velocity
	var radius := GameConstants.SHIP_COLLISION_RADIUS
	if next_position.x < radius or next_position.x > GameConstants.ARENA_SIZE.x - radius:
		next_position.x = clampf(next_position.x, radius, GameConstants.ARENA_SIZE.x - radius)
		next_velocity.x = 0.0
	if next_position.y < radius or next_position.y > GameConstants.ARENA_SIZE.y - radius:
		next_position.y = clampf(next_position.y, radius, GameConstants.ARENA_SIZE.y - radius)
		next_velocity.y = 0.0
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		var expanded := rectangle.grow(radius)
		if expanded.has_point(next_position):
			var distances := [
				absf(next_position.x - expanded.position.x),
				absf(expanded.end.x - next_position.x),
				absf(next_position.y - expanded.position.y),
				absf(expanded.end.y - next_position.y),
			]
			var nearest := distances.find(distances.min())
			match nearest:
				0:
					next_position.x = expanded.position.x
					next_velocity.x = minf(next_velocity.x, 0.0)
				1:
					next_position.x = expanded.end.x
					next_velocity.x = maxf(next_velocity.x, 0.0)
				2:
					next_position.y = expanded.position.y
					next_velocity.y = minf(next_velocity.y, 0.0)
				3:
					next_position.y = expanded.end.y
					next_velocity.y = maxf(next_velocity.y, 0.0)
	for circle in ArenaLayout.circle_obstacles(map_id):
		var circle_center := circle.center as Vector2
		var from_center := next_position - circle_center
		var circle_limit := float(circle.radius) + radius
		if from_center.length_squared() < circle_limit * circle_limit:
			var normal := from_center.normalized() if not from_center.is_zero_approx() else Vector2.RIGHT
			next_position = circle_center + normal * circle_limit
			var inward_speed := next_velocity.dot(-normal)
			if inward_speed > 0.0:
				next_velocity += normal * inward_speed
	return {"position": next_position, "velocity": next_velocity}


static func is_ship_position_clear(position: Vector2, map_id: StringName = ArenaLayout.DEFAULT_MAP_ID, margin: float = 0.0) -> bool:
	var radius := GameConstants.SHIP_COLLISION_RADIUS + maxf(margin, 0.0)
	if position.x < radius or position.x > GameConstants.ARENA_SIZE.x - radius:
		return false
	if position.y < radius or position.y > GameConstants.ARENA_SIZE.y - radius:
		return false
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		if rectangle.grow(radius).has_point(position):
			return false
	for circle in ArenaLayout.circle_obstacles(map_id):
		var minimum_distance := float(circle.radius) + radius
		if position.distance_squared_to(circle.center as Vector2) < minimum_distance * minimum_distance:
			return false
	return true


static func projectile_obstacle_normal(position: Vector2, radius: float, map_id: StringName = ArenaLayout.DEFAULT_MAP_ID) -> Vector2:
	if position.x <= radius:
		return Vector2.RIGHT
	if position.x >= GameConstants.ARENA_SIZE.x - radius:
		return Vector2.LEFT
	if position.y <= radius:
		return Vector2.DOWN
	if position.y >= GameConstants.ARENA_SIZE.y - radius:
		return Vector2.UP
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		var expanded := rectangle.grow(radius)
		if expanded.has_point(position):
			var local := position - expanded.get_center()
			var normalized := Vector2(local.x / expanded.size.x, local.y / expanded.size.y)
			var normal := Vector2(signf(local.x), 0.0) if absf(normalized.x) > absf(normalized.y) else Vector2(0.0, signf(local.y))
			return normal if not normal.is_zero_approx() else Vector2.UP
	for circle in ArenaLayout.circle_obstacles(map_id):
		var from_center := position - (circle.center as Vector2)
		if from_center.length() <= float(circle.radius) + radius:
			return from_center.normalized() if not from_center.is_zero_approx() else Vector2.RIGHT
	return Vector2.ZERO


static func projectile_obstacle_sweep(
	start: Vector2,
	end: Vector2,
	radius: float,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
) -> Dictionary:
	var start_normal := projectile_obstacle_normal(start, radius, map_id)
	if not start_normal.is_zero_approx():
		return {"hit": true, "fraction": 0.0, "position": start, "normal": start_normal}
	var direction := end - start
	if direction.is_zero_approx():
		return {"hit": false}
	var best_hit := {"hit": false, "fraction": INF, "position": end, "normal": Vector2.ZERO}
	var minimum := Vector2(radius, radius)
	var maximum := GameConstants.ARENA_SIZE - minimum
	if direction.x < 0.0 and end.x <= minimum.x:
		best_hit = _nearer_projectile_hit(best_hit, _sweep_candidate(start, direction, (minimum.x - start.x) / direction.x, Vector2.RIGHT))
	elif direction.x > 0.0 and end.x >= maximum.x:
		best_hit = _nearer_projectile_hit(best_hit, _sweep_candidate(start, direction, (maximum.x - start.x) / direction.x, Vector2.LEFT))
	if direction.y < 0.0 and end.y <= minimum.y:
		best_hit = _nearer_projectile_hit(best_hit, _sweep_candidate(start, direction, (minimum.y - start.y) / direction.y, Vector2.DOWN))
	elif direction.y > 0.0 and end.y >= maximum.y:
		best_hit = _nearer_projectile_hit(best_hit, _sweep_candidate(start, direction, (maximum.y - start.y) / direction.y, Vector2.UP))
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		best_hit = _nearer_projectile_hit(best_hit, _segment_aabb_hit(start, direction, rectangle.grow(radius)))
	for circle in ArenaLayout.circle_obstacles(map_id):
		best_hit = _nearer_projectile_hit(best_hit, _segment_circle_hit(
			start,
			direction,
			circle.center as Vector2,
			float(circle.radius) + radius
		))
	return best_hit if bool(best_hit.hit) else {"hit": false}


static func _segment_aabb_hit(start: Vector2, direction: Vector2, rectangle: Rect2) -> Dictionary:
	var entry_fraction := 0.0
	var exit_fraction := 1.0
	var entry_normal := Vector2.ZERO
	for axis in 2:
		var start_value := start[axis]
		var direction_value := direction[axis]
		var minimum := rectangle.position[axis]
		var maximum := rectangle.end[axis]
		if absf(direction_value) <= 0.000001:
			if start_value < minimum or start_value > maximum:
				return {"hit": false}
			continue
		var near_fraction := (minimum - start_value) / direction_value
		var far_fraction := (maximum - start_value) / direction_value
		if near_fraction > far_fraction:
			var swap := near_fraction
			near_fraction = far_fraction
			far_fraction = swap
		if near_fraction > entry_fraction:
			entry_fraction = near_fraction
			entry_normal = Vector2(-signf(direction_value), 0.0) if axis == 0 else Vector2(0.0, -signf(direction_value))
		exit_fraction = minf(exit_fraction, far_fraction)
		if entry_fraction > exit_fraction:
			return {"hit": false}
	if entry_normal.is_zero_approx() or entry_fraction < 0.0 or entry_fraction > 1.0:
		return {"hit": false}
	return _sweep_candidate(start, direction, entry_fraction, entry_normal)


static func _segment_circle_hit(start: Vector2, direction: Vector2, center: Vector2, radius: float) -> Dictionary:
	var offset := start - center
	var a := direction.length_squared()
	if a <= 0.000001:
		return {"hit": false}
	var b := 2.0 * offset.dot(direction)
	var c := offset.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return {"hit": false}
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	if fraction < 0.0 or fraction > 1.0:
		return {"hit": false}
	var position := start + direction * fraction
	var normal := (position - center).normalized()
	if normal.is_zero_approx():
		normal = -direction.normalized()
	return {"hit": true, "fraction": fraction, "position": position, "normal": normal}


static func _sweep_candidate(start: Vector2, direction: Vector2, fraction: float, normal: Vector2) -> Dictionary:
	if fraction < 0.0 or fraction > 1.0 or normal.is_zero_approx():
		return {"hit": false}
	return {"hit": true, "fraction": fraction, "position": start + direction * fraction, "normal": normal}


static func _nearer_projectile_hit(current: Dictionary, candidate: Dictionary) -> Dictionary:
	if not bool(candidate.get("hit", false)):
		return current
	if not bool(current.get("hit", false)) or float(candidate.fraction) < float(current.fraction):
		return candidate
	return current
