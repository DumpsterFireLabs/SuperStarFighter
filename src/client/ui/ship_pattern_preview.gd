class_name ShipPatternPreview
extends Control

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const ShipPatternGeometryScript = preload("res://src/client/presentation/ship_pattern_geometry.gd")
const PREVIEW_SCALE: Vector2 = Vector2(52.0 / 29.0, 30.0 / 17.0)

var ship_color: Color = Color("42e8ff")
var ship_pattern: StringName = ShipAppearanceScript.SOLID


func _ready() -> void:
	custom_minimum_size = Vector2(150.0, 84.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_appearance(color: Color, pattern: StringName) -> void:
	ship_color = Color(color.r, color.g, color.b, 1.0)
	ship_pattern = pattern if ShipAppearanceScript.is_valid_pattern(pattern) else ShipAppearanceScript.SOLID
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var points := PackedVector2Array([
		center + Vector2(52.0, 0.0),
		center + Vector2(-34.0, 30.0),
		center + Vector2(-20.0, 0.0),
		center + Vector2(-34.0, -30.0),
	])
	draw_colored_polygon(points, Color(ship_color.darkened(0.36), 0.96))
	_draw_pattern(center, ship_color.lightened(0.48))
	draw_polyline(points + PackedVector2Array([points[0]]), ship_color, 5.0, true)
	draw_circle(center, 7.0, Color.WHITE)


func _draw_pattern(center: Vector2, accent: Color) -> void:
	var pattern_shapes := ShipPatternGeometryScript.shapes(ship_pattern)
	_draw_pattern_polygons(pattern_shapes.accent, center, accent)
	_draw_pattern_polygons(pattern_shapes.detail, center, Color(ship_color.darkened(0.55), 0.95))


func _draw_pattern_polygons(polygons: Array, center: Vector2, color: Color) -> void:
	for polygon_value in polygons:
		var polygon := polygon_value as PackedVector2Array
		var transformed := PackedVector2Array()
		for point in polygon:
			transformed.append(center + point * PREVIEW_SCALE)
		draw_colored_polygon(transformed, color)
