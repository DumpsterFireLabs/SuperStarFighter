class_name ArenaCollisionSystem
extends RefCounted
static var _projectile_geometry_cache: Dictionary = {}
static var _empty_obstacle_indices: Array[int] = []
const PROJECTILE_OBSTACLE_CELL_SIZE: float = 240.0


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
	var geometry := _projectile_geometry(map_id, radius)
	for rectangle in geometry.rectangles as Array:
		if rectangle.has_point(position):
			return _rectangle_normal(position, rectangle)
	for circle in geometry.circles as Array:
		var from_center := position - Vector2(circle.x, circle.y)
		if from_center.length_squared() <= circle.z * circle.z:
			return from_center.normalized() if not from_center.is_zero_approx() else Vector2.RIGHT
	return Vector2.ZERO


static func projectile_obstacle_sweep(
	start: Vector2,
	end: Vector2,
	radius: float,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
) -> Dictionary:
	var hit: Variant = projectile_obstacle_sweep_hit(start, end, radius, map_id)
	return hit as Dictionary if hit != null else {"hit": false}


static func has_clear_line_of_sight(
	start: Vector2,
	end: Vector2,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
) -> bool:
	return projectile_obstacle_sweep_hit(start, end, 0.0, map_id) == null


static func projectile_obstacle_sweep_hit(
	start: Vector2,
	end: Vector2,
	radius: float,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID,
	geometry_override: Dictionary = {}
) -> Variant:
	if start.x <= radius:
		return {"hit": true, "fraction": 0.0, "position": start, "normal": Vector2.RIGHT}
	if start.x >= GameConstants.ARENA_SIZE.x - radius:
		return {"hit": true, "fraction": 0.0, "position": start, "normal": Vector2.LEFT}
	if start.y <= radius:
		return {"hit": true, "fraction": 0.0, "position": start, "normal": Vector2.DOWN}
	if start.y >= GameConstants.ARENA_SIZE.y - radius:
		return {"hit": true, "fraction": 0.0, "position": start, "normal": Vector2.UP}
	var geometry := geometry_override if not geometry_override.is_empty() else _projectile_geometry(map_id, radius)
	var start_cell := _projectile_obstacle_cell(start)
	var end_cell := _projectile_obstacle_cell(end)
	# The common empty-cell path needs only one occupancy lookup. Defer typed
	# geometry extraction until a sweep can actually reach an obstacle.
	if (
		start_cell == end_cell
		and not (geometry.occupied_cells as Dictionary).has(start_cell)
		and end.x > radius and end.y > radius
		and end.x < GameConstants.ARENA_SIZE.x - radius
		and end.y < GameConstants.ARENA_SIZE.y - radius
	):
		return null
	var rectangles := geometry.rectangles as Array
	var circles := geometry.circles as Array
	var rectangle_cells := geometry.rectangle_cells as Dictionary
	var circle_cells := geometry.circle_cells as Dictionary
	for rectangle_index in rectangle_cells.get(start_cell, _empty_obstacle_indices) as Array:
		var rectangle := rectangles[int(rectangle_index)] as Rect2
		if rectangle.has_point(start):
			return {"hit": true, "fraction": 0.0, "position": start, "normal": _rectangle_normal(start, rectangle)}
	for circle_index in circle_cells.get(start_cell, _empty_obstacle_indices) as Array:
		var circle := circles[int(circle_index)] as Vector3
		var from_center := start - Vector2(circle.x, circle.y)
		if from_center.length_squared() <= circle.z * circle.z:
			var normal := from_center.normalized() if not from_center.is_zero_approx() else Vector2.RIGHT
			return {"hit": true, "fraction": 0.0, "position": start, "normal": normal}
	var direction := end - start
	if direction.is_zero_approx():
		return null
	var best_fraction := INF
	var best_normal := Vector2.ZERO
	var minimum := Vector2(radius, radius)
	var maximum := GameConstants.ARENA_SIZE - minimum
	if direction.x < 0.0 and end.x <= minimum.x:
		best_fraction = (minimum.x - start.x) / direction.x
		best_normal = Vector2.RIGHT
	elif direction.x > 0.0 and end.x >= maximum.x:
		best_fraction = (maximum.x - start.x) / direction.x
		best_normal = Vector2.LEFT
	if direction.y < 0.0 and end.y <= minimum.y:
		var candidate_fraction := (minimum.y - start.y) / direction.y
		if candidate_fraction < best_fraction:
			best_fraction = candidate_fraction
			best_normal = Vector2.DOWN
	elif direction.y > 0.0 and end.y >= maximum.y:
		var candidate_fraction := (maximum.y - start.y) / direction.y
		if candidate_fraction < best_fraction:
			best_fraction = candidate_fraction
			best_normal = Vector2.UP
	var segment_minimum := Vector2i(mini(start_cell.x, end_cell.x), mini(start_cell.y, end_cell.y))
	var segment_maximum := Vector2i(maxi(start_cell.x, end_cell.x), maxi(start_cell.y, end_cell.y))
	if (
		segment_minimum == segment_maximum and
		not rectangle_cells.has(segment_minimum) and
		not circle_cells.has(segment_minimum)
	):
		if best_normal.is_zero_approx():
			return null
		return {"hit": true, "fraction": best_fraction, "position": start + direction * best_fraction, "normal": best_normal}
	var tested_rectangles := 0
	var tested_circles := 0
	for cell_y in range(segment_minimum.y, segment_maximum.y + 1):
		for cell_x in range(segment_minimum.x, segment_maximum.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			for rectangle_index_value in rectangle_cells.get(cell, _empty_obstacle_indices) as Array:
				var rectangle_index := int(rectangle_index_value)
				var rectangle_bit := 1 << rectangle_index
				if tested_rectangles & rectangle_bit:
					continue
				tested_rectangles |= rectangle_bit
				var candidate := _segment_aabb_hit_vector(start, direction, rectangles[rectangle_index] as Rect2)
				if candidate.x < best_fraction:
					best_fraction = candidate.x
					best_normal = Vector2(candidate.y, candidate.z)
			for circle_index_value in circle_cells.get(cell, _empty_obstacle_indices) as Array:
				var circle_index := int(circle_index_value)
				var circle_bit := 1 << circle_index
				if tested_circles & circle_bit:
					continue
				tested_circles |= circle_bit
				var circle := circles[circle_index] as Vector3
				var candidate := _segment_circle_hit_vector(start, direction, Vector2(circle.x, circle.y), circle.z)
				if candidate.x < best_fraction:
					best_fraction = candidate.x
					best_normal = Vector2(candidate.y, candidate.z)
	if best_fraction < 0.0 or best_fraction > 1.0 or best_normal.is_zero_approx():
		return null
	return {
		"hit": true,
		"fraction": best_fraction,
		"position": start + direction * best_fraction,
		"normal": best_normal,
	}


static func _projectile_geometry(map_id: StringName, radius: float) -> Dictionary:
	var key := "%s:%d" % [ArenaLayout.normalized_map_id(map_id), roundi(radius * 100.0)]
	if _projectile_geometry_cache.has(key):
		return _projectile_geometry_cache[key] as Dictionary
	var rectangles: Array[Rect2] = []
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		rectangles.append(rectangle.grow(radius))
	var circles: Array[Vector3] = []
	for circle in ArenaLayout.circle_obstacles(map_id):
		var center := circle.center as Vector2
		circles.append(Vector3(center.x, center.y, float(circle.radius) + radius))
	var rectangle_cells: Dictionary = {}
	for rectangle_index in rectangles.size():
		_append_obstacle_to_cells(rectangle_cells, rectangles[rectangle_index], rectangle_index)
	var circle_cells: Dictionary = {}
	for circle_index in circles.size():
		var circle := circles[circle_index]
		var extent := Vector2.ONE * circle.z
		_append_obstacle_to_cells(circle_cells, Rect2(Vector2(circle.x, circle.y) - extent, extent * 2.0), circle_index)
	var occupied_cells := rectangle_cells.duplicate()
	occupied_cells.merge(circle_cells)
	var result := {
		"occupied_cells": occupied_cells,
		"rectangles": rectangles,
		"circles": circles,
		"rectangle_cells": rectangle_cells,
		"circle_cells": circle_cells,
	}
	_projectile_geometry_cache[key] = result
	return result


static func projectile_geometry(map_id: StringName, radius: float) -> Dictionary:
	return _projectile_geometry(map_id, radius)


static func _append_obstacle_to_cells(cells: Dictionary, bounds: Rect2, obstacle_index: int) -> void:
	var minimum := _projectile_obstacle_cell(bounds.position)
	var maximum := _projectile_obstacle_cell(bounds.end)
	for cell_y in range(minimum.y, maximum.y + 1):
		for cell_x in range(minimum.x, maximum.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			var indices: Array[int] = []
			if cells.has(cell):
				indices = cells[cell] as Array[int]
			else:
				cells[cell] = indices
			indices.append(obstacle_index)


static func _projectile_obstacle_cell(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / PROJECTILE_OBSTACLE_CELL_SIZE),
		floori(position.y / PROJECTILE_OBSTACLE_CELL_SIZE)
	)


static func _rectangle_normal(position: Vector2, rectangle: Rect2) -> Vector2:
	var local := position - rectangle.get_center()
	var normalized := Vector2(local.x / rectangle.size.x, local.y / rectangle.size.y)
	var normal := Vector2(signf(local.x), 0.0) if absf(normalized.x) > absf(normalized.y) else Vector2(0.0, signf(local.y))
	return normal if not normal.is_zero_approx() else Vector2.UP


static func _segment_aabb_hit_vector(start: Vector2, direction: Vector2, rectangle: Rect2) -> Vector3:
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
				return Vector3(INF, 0.0, 0.0)
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
			return Vector3(INF, 0.0, 0.0)
	if entry_normal.is_zero_approx() or entry_fraction < 0.0 or entry_fraction > 1.0:
		return Vector3(INF, 0.0, 0.0)
	return Vector3(entry_fraction, entry_normal.x, entry_normal.y)


static func _segment_circle_hit_vector(start: Vector2, direction: Vector2, center: Vector2, radius: float) -> Vector3:
	var offset := start - center
	var a := direction.length_squared()
	if a <= 0.000001:
		return Vector3(INF, 0.0, 0.0)
	var b := 2.0 * offset.dot(direction)
	var c := offset.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return Vector3(INF, 0.0, 0.0)
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	if fraction < 0.0 or fraction > 1.0:
		return Vector3(INF, 0.0, 0.0)
	var normal := (start + direction * fraction - center).normalized()
	if normal.is_zero_approx():
		normal = -direction.normalized()
	return Vector3(fraction, normal.x, normal.y)
