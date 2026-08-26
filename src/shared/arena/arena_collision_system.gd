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
