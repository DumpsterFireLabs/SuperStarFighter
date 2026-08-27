class_name ArenaLayout
extends RefCounted

const DEFAULT_MAP_ID: StringName = &"core_arena"
const MAP_IDS: Array[StringName] = [
	&"core_arena", &"riftline", &"prism_array", &"twin_suns", &"dead_freight",
	&"longwave_array", &"broken_orbit", &"switchyard", &"solar_tide", &"relay_zero",
]
const MAP_NAMES := {
	&"core_arena": "Core Arena", &"riftline": "Riftline", &"prism_array": "Prism Array",
	&"twin_suns": "Twin Suns", &"dead_freight": "Dead Freight", &"longwave_array": "Longwave Array",
	&"broken_orbit": "Broken Orbit", &"switchyard": "Switchyard", &"solar_tide": "Solar Tide",
	&"relay_zero": "Relay Zero",
}
const CENTRAL_RADIUS: float = 180.0
const COVER_SIZE: Vector2 = Vector2(360.0, 130.0)
const SPAWN_CLEAR_RADIUS: float = 96.0
static var _cover_rectangle_cache: Dictionary = {}
static var _circle_obstacle_cache: Dictionary = {}


static func map_ids() -> Array[StringName]:
	return MAP_IDS.duplicate()


static func has_map(map_id: StringName) -> bool:
	return map_id in MAP_IDS


static func normalized_map_id(map_id: StringName) -> StringName:
	return map_id if has_map(map_id) else DEFAULT_MAP_ID


static func display_name(map_id: StringName = DEFAULT_MAP_ID) -> String:
	return String(MAP_NAMES.get(normalized_map_id(map_id), MAP_NAMES[DEFAULT_MAP_ID]))


static func arena_rect() -> Rect2:
	return Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)


static func center(_map_id: StringName = DEFAULT_MAP_ID) -> Vector2:
	return GameConstants.ARENA_SIZE * 0.5


static func central_radius(map_id: StringName = DEFAULT_MAP_ID) -> float:
	return CENTRAL_RADIUS if normalized_map_id(map_id) == DEFAULT_MAP_ID else 0.0


static func central_octagon(map_id: StringName = DEFAULT_MAP_ID) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := central_radius(map_id)
	if radius <= 0.0:
		return points
	for index in 8:
		points.append(center(map_id) + Vector2.from_angle(TAU * float(index) / 8.0 + PI / 8.0) * radius)
	return points


static func cover_rectangles(map_id: StringName = DEFAULT_MAP_ID) -> Array[Rect2]:
	var normalized := normalized_map_id(map_id)
	if _cover_rectangle_cache.has(normalized):
		return _cover_rectangle_cache[normalized] as Array[Rect2]
	var rectangles := _build_cover_rectangles(normalized)
	_cover_rectangle_cache[normalized] = rectangles
	return rectangles


static func _build_cover_rectangles(map_id: StringName) -> Array[Rect2]:
	match map_id:
		&"riftline":
			return [_rect(1600, 300, 150, 360), _rect(1600, 690, 150, 220), _rect(1600, 1110, 150, 220), _rect(1600, 1500, 150, 360)]
		&"prism_array":
			return [
				_rect(1080, 610, 330, 100), _rect(1320, 420, 100, 300), _rect(2120, 610, 330, 100), _rect(1880, 420, 100, 300),
				_rect(1080, 1190, 330, 100), _rect(1320, 1380, 100, 300), _rect(2120, 1190, 330, 100), _rect(1880, 1380, 100, 300),
			]
		&"dead_freight":
			return [
				_rect(850, 560, 430, 180), _rect(850, 1220, 430, 180), _rect(1600, 480, 460, 160),
				_rect(1600, 1320, 460, 160), _rect(2350, 560, 430, 180), _rect(2350, 1220, 430, 180),
			]
		&"longwave_array":
			return [
				_rect(720, 470, 90, 430), _rect(2480, 470, 90, 430), _rect(720, 1330, 90, 430),
				_rect(2480, 1330, 90, 430), _rect(1320, 900, 90, 400), _rect(1880, 900, 90, 400),
			]
		&"broken_orbit":
			return [
				_rect(1600, 430, 620, 90), _rect(1600, 1370, 620, 90), _rect(950, 900, 90, 430),
				_rect(2250, 900, 90, 430), _rect(1300, 720, 280, 80), _rect(1900, 1080, 280, 80),
			]
		&"switchyard":
			return [
				_rect(1050, 560, 420, 100), _rect(1050, 1240, 420, 100), _rect(1600, 690, 100, 360),
				_rect(1600, 1110, 100, 360), _rect(2150, 560, 420, 100), _rect(2150, 1240, 420, 100),
			]
		&"solar_tide":
			return [_rect(920, 520, 520, 90), _rect(2280, 520, 520, 90), _rect(920, 1280, 520, 90), _rect(2280, 1280, 520, 90)]
		&"relay_zero":
			return [
				_rect(780, 650, 280, 120), _rect(780, 1150, 280, 120), _rect(1250, 430, 120, 280), _rect(1250, 1370, 120, 280),
				_rect(1950, 430, 120, 280), _rect(1950, 1370, 120, 280), _rect(2420, 650, 280, 120), _rect(2420, 1150, 280, 120),
			]
		DEFAULT_MAP_ID:
			var result: Array[Rect2] = []
			for offset in [Vector2(-650, -350), Vector2(650, -350), Vector2(650, 350), Vector2(-650, 350)]:
				result.append(Rect2(center() + offset - COVER_SIZE * 0.5, COVER_SIZE))
			return result
		_:
			return []


static func circle_obstacles(map_id: StringName = DEFAULT_MAP_ID) -> Array[Dictionary]:
	var normalized := normalized_map_id(map_id)
	if _circle_obstacle_cache.has(normalized):
		return _circle_obstacle_cache[normalized] as Array[Dictionary]
	var circles := _build_circle_obstacles(normalized)
	_circle_obstacle_cache[normalized] = circles
	return circles


static func _build_circle_obstacles(map_id: StringName) -> Array[Dictionary]:
	match map_id:
		DEFAULT_MAP_ID:
			return [{"center": center(map_id), "radius": CENTRAL_RADIUS}]
		&"twin_suns":
			return [{"center": Vector2(1130, 900), "radius": 245.0}, {"center": Vector2(2070, 900), "radius": 245.0}]
		&"solar_tide":
			return [{"center": center(map_id), "radius": 135.0}]
		&"relay_zero":
			return [{"center": Vector2(1120, 900), "radius": 105.0}, {"center": Vector2(2080, 900), "radius": 105.0}]
		_:
			return []


static func spawn_anchors(map_id: StringName = DEFAULT_MAP_ID) -> Array[Vector2]:
	if normalized_map_id(map_id) == DEFAULT_MAP_ID:
		var core: Array[Vector2] = []
		for index in 12:
			core.append(center() + Vector2.from_angle(TAU * float(index) / 12.0) * 380.0)
		for index in 20:
			var angle := TAU * float(index) / 20.0
			core.append(center() + Vector2(cos(angle) * 1250.0, sin(angle) * 700.0))
		return core
	var result: Array[Vector2] = []
	for index in 8:
		var x := lerpf(400.0, 2800.0, float(index) / 7.0)
		result.append(Vector2(x, 140.0))
		result.append(Vector2(x, 1660.0))
	for index in 8:
		var y := lerpf(320.0, 1480.0, float(index) / 7.0)
		result.append(Vector2(180.0, y))
		result.append(Vector2(3020.0, y))
	return result


static func theme(map_id: StringName = DEFAULT_MAP_ID) -> Dictionary:
	match normalized_map_id(map_id):
		&"riftline": return {"floor": Color("130d1d"), "border": Color("ff9f43"), "obstacle": Color("36203e"), "line": Color("ff5f87")}
		&"prism_array": return {"floor": Color("080f24"), "border": Color("7afcff"), "obstacle": Color("202a54"), "line": Color("ff6ee7")}
		&"twin_suns": return {"floor": Color("160d12"), "border": Color("ffcc5c"), "obstacle": Color("44231d"), "line": Color("ff713f")}
		&"dead_freight": return {"floor": Color("0b1216"), "border": Color("a9d46e"), "obstacle": Color("29302b"), "line": Color("e0a84f")}
		&"longwave_array": return {"floor": Color("050f20"), "border": Color("56b8ff"), "obstacle": Color("152d4b"), "line": Color("8be9ff")}
		&"broken_orbit": return {"floor": Color("100b20"), "border": Color("bd7cff"), "obstacle": Color("2d2153"), "line": Color("e4a0ff")}
		&"switchyard": return {"floor": Color("101417"), "border": Color("ffe36e"), "obstacle": Color("303334"), "line": Color("ff9f43")}
		&"solar_tide": return {"floor": Color("130d24"), "border": Color("ff66d4"), "obstacle": Color("39204d"), "line": Color("66f5ff")}
		&"relay_zero": return {"floor": Color("07151a"), "border": Color("62ff9b"), "obstacle": Color("183d43"), "line": Color("42e8ff")}
		_: return {"floor": Color("071024"), "border": Color("36d7ff"), "obstacle": Color("18274a"), "line": Color("a35cff")}


static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen_names: Dictionary = {}
	for map_id in MAP_IDS:
		var map_name := display_name(map_id)
		if seen_names.has(map_name):
			errors.append("Map display name %s is duplicated." % map_name)
		seen_names[map_name] = true
		errors.append_array(validate_map(map_id))
	return errors


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


static func _rect(center_x: float, center_y: float, width: float, height: float) -> Rect2:
	var size := Vector2(width, height)
	return Rect2(Vector2(center_x, center_y) - size * 0.5, size)
