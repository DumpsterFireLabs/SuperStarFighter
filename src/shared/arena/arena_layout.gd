class_name ArenaLayout
extends RefCounted

const CENTRAL_RADIUS: float = 180.0
const COVER_SIZE: Vector2 = Vector2(360.0, 130.0)


static func arena_rect() -> Rect2:
	return Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)


static func center() -> Vector2:
	return GameConstants.ARENA_SIZE * 0.5


static func central_octagon() -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 8:
		points.append(
			center() + Vector2.from_angle(TAU * float(index) / 8.0 + PI / 8.0) * CENTRAL_RADIUS
		)
	return points


static func cover_rectangles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var offsets: Array[Vector2] = [
		Vector2(-650.0, -350.0),
		Vector2(650.0, -350.0),
		Vector2(650.0, 350.0),
		Vector2(-650.0, 350.0),
	]
	for offset in offsets:
		result.append(Rect2(center() + offset - COVER_SIZE * 0.5, COVER_SIZE))
	return result


static func spawn_anchors() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in 12:
		var angle := TAU * float(index) / 12.0
		result.append(center() + Vector2.from_angle(angle) * 380.0)
	for index in 20:
		var angle := TAU * float(index) / 20.0 + PI / 20.0
		result.append(center() + Vector2(cos(angle) * 1250.0, sin(angle) * 700.0))
	return result


static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var anchors := spawn_anchors()
	if anchors.size() != GameConstants.MAX_PLAYERS:
		errors.append("Arena must provide exactly 32 spawn anchors.")
	var safe_rect := arena_rect().grow(-GameConstants.SHIP_COLLISION_RADIUS)
	for index in anchors.size():
		var anchor := anchors[index]
		if not safe_rect.has_point(anchor):
			errors.append("Spawn anchor %d lies outside the safe arena bounds." % index)
		if _overlaps_obstacle(anchor, GameConstants.SHIP_COLLISION_RADIUS):
			errors.append("Spawn anchor %d overlaps an obstacle." % index)
		for other_index in range(index + 1, anchors.size()):
			if anchor.distance_to(anchors[other_index]) < 160.0 - 0.001:
				errors.append(
					"Spawn anchors %d and %d are less than 160 pixels apart." % [index, other_index]
				)
	return errors


static func _overlaps_obstacle(point: Vector2, radius: float) -> bool:
	if point.distance_to(center()) <= CENTRAL_RADIUS + radius:
		return true
	for rectangle in cover_rectangles():
		if rectangle.grow(radius).has_point(point):
			return true
	return false
