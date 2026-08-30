class_name ShipPatternGeometry
extends RefCounted

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")

# Pattern shapes use the gameplay ship's local coordinate system. Every filled
# shape is intersected with the concave hull before either renderer receives it.
static var HULL: PackedVector2Array = PackedVector2Array([
	Vector2(29.0, 0.0),
	Vector2(-19.0, 17.0),
	Vector2(-11.0, 0.0),
	Vector2(-19.0, -17.0),
])
const CIRCLE_SEGMENTS: int = 16

static var _shape_cache: Dictionary = {}


static func shapes(pattern: StringName) -> Dictionary:
	var normalized := pattern if ShipAppearanceScript.is_valid_pattern(pattern) else ShipAppearanceScript.SOLID
	if _shape_cache.has(normalized):
		return _shape_cache[normalized]
	var result := {"accent": [], "detail": []}
	match normalized:
		ShipAppearanceScript.ZEBRA:
			for stripe in [
				[Vector2(-16.0, -13.0), Vector2(-7.0, 11.0)],
				[Vector2(-4.0, -12.0), Vector2(3.0, 9.0)],
				[Vector2(8.0, -8.0), Vector2(14.0, 6.0)],
			]:
				_append_clipped(result.accent, _line_polygon(stripe[0], stripe[1], 3.5))
		ShipAppearanceScript.LEOPARD:
			for center in [Vector2(-12.0, -8.0), Vector2(-11.0, 9.0), Vector2(1.0, -7.0), Vector2(5.0, 8.0), Vector2(17.0, 0.0)]:
				_append_clipped(result.accent, _circle_polygon(center, 3.4))
				_append_clipped(result.detail, _circle_polygon(center, 1.4))
		ShipAppearanceScript.CHECKERBOARD:
			for column in 4:
				for row in 3:
					if (column + row) % 2 == 0:
						var center := Vector2(-10.5 + column * 7.0, -7.0 + row * 7.0)
						_append_clipped(result.accent, _rectangle_polygon(center, Vector2(5.8, 5.8)))
		ShipAppearanceScript.RACING:
			_append_clipped(result.accent, _line_polygon(Vector2(-14.0, -4.0), Vector2(22.0, -4.0), 2.7))
			_append_clipped(result.accent, _line_polygon(Vector2(-14.0, 4.0), Vector2(22.0, 4.0), 2.7))
		ShipAppearanceScript.CHEVRON:
			for x in [-4.0, 8.0, 18.0]:
				var tail_top := Vector2(x - 5.0, -7.0)
				var tip := Vector2(x + 3.0, 0.0)
				var tail_bottom := Vector2(x - 5.0, 7.0)
				_append_clipped(result.accent, _line_polygon(tail_top, tip, 2.5))
				_append_clipped(result.accent, _line_polygon(tip, tail_bottom, 2.5))
	_shape_cache[normalized] = result
	return result


static func all_vertices_fit_hull(pattern: StringName) -> bool:
	var pattern_shapes := shapes(pattern)
	for group_name in ["accent", "detail"]:
		for polygon_value in pattern_shapes[group_name]:
			var polygon := polygon_value as PackedVector2Array
			for point in polygon:
				if not Geometry2D.is_point_in_polygon(point, HULL) and not _point_on_hull(point):
					return false
	return true


static func _append_clipped(destination: Array, polygon: PackedVector2Array) -> void:
	for clipped in Geometry2D.intersect_polygons(polygon, HULL):
		if clipped.size() >= 3:
			destination.append(clipped)


static func _line_polygon(start: Vector2, finish: Vector2, width: float) -> PackedVector2Array:
	var direction := finish - start
	if direction.is_zero_approx():
		return PackedVector2Array()
	var offset := direction.normalized().orthogonal() * width * 0.5
	return PackedVector2Array([start + offset, finish + offset, finish - offset, start - offset])


static func _rectangle_polygon(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half_size := size * 0.5
	return PackedVector2Array([
		center + Vector2(-half_size.x, -half_size.y),
		center + Vector2(half_size.x, -half_size.y),
		center + Vector2(half_size.x, half_size.y),
		center + Vector2(-half_size.x, half_size.y),
	])


static func _circle_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for index in CIRCLE_SEGMENTS:
		polygon.append(center + Vector2.from_angle(TAU * float(index) / float(CIRCLE_SEGMENTS)) * radius)
	return polygon


static func _point_on_hull(point: Vector2) -> bool:
	for index in HULL.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, HULL[index], HULL[(index + 1) % HULL.size()])
		if closest.distance_squared_to(point) <= 0.0001:
			return true
	return false
