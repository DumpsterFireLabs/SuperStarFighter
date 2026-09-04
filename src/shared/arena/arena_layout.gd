class_name ArenaLayout
extends RefCounted

const Registry = preload("res://src/shared/arena/map_registry.gd")
const DEFAULT_MAP_ID: StringName = &"core_arena"
const CENTRAL_RADIUS: float = 180.0
const SPAWN_CLEAR_RADIUS: float = 96.0


static func map_ids() -> Array[StringName]:
	return Registry.ids()


static func has_map(map_id: StringName) -> bool:
	return Registry.has_map(map_id)


static func normalized_map_id(map_id: StringName) -> StringName:
	return Registry.normalized(map_id)


static func display_name(map_id: StringName = DEFAULT_MAP_ID) -> String:
	return Registry.display_name(map_id)


static func arena_rect() -> Rect2:
	return Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)


static func center(_map_id: StringName = DEFAULT_MAP_ID) -> Vector2:
	return GameConstants.ARENA_SIZE * 0.5


static func central_radius(map_id: StringName = DEFAULT_MAP_ID) -> float:
	return Registry.central_radius(map_id)


static func central_octagon(map_id: StringName = DEFAULT_MAP_ID) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := central_radius(map_id)
	if radius <= 0.0:
		return points
	for index in 8:
		points.append(center(map_id) + Vector2.from_angle(TAU * float(index) / 8.0 + PI / 8.0) * radius)
	return points


static func cover_rectangles(map_id: StringName = DEFAULT_MAP_ID) -> Array[Rect2]:
	return Registry.cover(map_id)


static func circle_obstacles(map_id: StringName = DEFAULT_MAP_ID) -> Array[Dictionary]:
	return Registry.circles(map_id)


static func spawn_anchors(map_id: StringName = DEFAULT_MAP_ID) -> Array[Vector2]:
	return Registry.spawns(map_id)


static func movement_fields(map_id: StringName = DEFAULT_MAP_ID) -> Array[ArenaMovementField]:
	return Registry.movement_fields(map_id)


static func mechanic_prompt(map_id: StringName = DEFAULT_MAP_ID) -> String:
	var fields := movement_fields(map_id)
	if fields.is_empty():
		return ""
	var field := fields[0] as ArenaMovementField
	return field.mechanic_prompt() if field != null else ""


static func theme(map_id: StringName = DEFAULT_MAP_ID) -> Dictionary:
	return Registry.palette(map_id)


static func material_family(map_id: StringName = DEFAULT_MAP_ID) -> StringName:
	return Registry.material_family(map_id)


static func validate() -> PackedStringArray:
	return Registry.validation_errors()


static func validate_map(map_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	if not has_map(map_id):
		return PackedStringArray(["Unknown map ID %s." % map_id])
	var anchors := spawn_anchors(map_id)
	if anchors.size() != GameConstants.MAX_PLAYERS:
		errors.append("Map %s must provide exactly 32 spawn anchors." % map_id)
	var safe_rect := arena_rect().grow(-SPAWN_CLEAR_RADIUS)
	for index in anchors.size():
		var anchor := anchors[index]
		if not safe_rect.has_point(anchor):
			errors.append("Map %s spawn anchor %d lies outside the safe arena bounds." % [map_id, index])
		if overlaps_obstacle(anchor, SPAWN_CLEAR_RADIUS, map_id):
			errors.append("Map %s spawn anchor %d overlaps an obstacle." % [map_id, index])
		for other_index in range(index + 1, anchors.size()):
			if anchor.distance_to(anchors[other_index]) < 160.0 - 0.001:
				errors.append("Map %s spawn anchors %d and %d are less than 160 pixels apart." % [map_id, index, other_index])
	return errors


static func overlaps_obstacle(point: Vector2, radius: float, map_id: StringName = DEFAULT_MAP_ID) -> bool:
	for rectangle in cover_rectangles(map_id):
		if rectangle.grow(radius).has_point(point):
			return true
	for circle in circle_obstacles(map_id):
		if point.distance_to(circle.center) <= float(circle.radius) + radius:
			return true
	return false
