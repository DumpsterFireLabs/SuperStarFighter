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


## Gravity fields with a lethal event horizon.
static func event_horizons(map_id: StringName = DEFAULT_MAP_ID) -> Array[ArenaMovementField]:
	var horizons: Array[ArenaMovementField] = []
	for field in movement_fields(map_id):
		if field.event_horizon_radius > 0.0:
			horizons.append(field)
	return horizons


## Center of the event horizon a ship at this position touches, or Vector2.INF.
static func crushing_horizon(position: Vector2, map_id: StringName = DEFAULT_MAP_ID, tolerance: float = 0.0) -> Vector2:
	for field in movement_fields(map_id):
		if field.crushes(position, GameConstants.SHIP_COLLISION_RADIUS + tolerance):
			return field.center
	return Vector2.INF


## False when a point lies within margin of an event horizon. Respawns and
## objectives use this so nobody is placed where gravity will crush them.
static func is_clear_of_hazards(position: Vector2, margin: float, map_id: StringName = DEFAULT_MAP_ID) -> bool:
	for field in movement_fields(map_id):
		if field.event_horizon_radius > 0.0 and position.distance_to(field.center) < field.event_horizon_radius + margin:
			return false
	return true


static func intrinsic_effects(map_id: StringName = DEFAULT_MAP_ID) -> int:
	return Registry.intrinsic_effects(map_id)


static func contact_damage(map_id: StringName = DEFAULT_MAP_ID) -> float:
	return Registry.contact_damage(map_id)


static func pulse_interval_range(map_id: StringName = DEFAULT_MAP_ID) -> Vector2:
	return Registry.pulse_interval_range(map_id)


static func pulse_prompt(map_id: StringName = DEFAULT_MAP_ID) -> String:
	return Registry.pulse_prompt(map_id)


static func overtime_minimum_radius(map_id: StringName = DEFAULT_MAP_ID) -> float:
	var authored := Registry.overtime_minimum_radius(map_id)
	return authored if authored > 0.0 else GameConstants.OVERTIME_MINIMUM_RADIUS


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
