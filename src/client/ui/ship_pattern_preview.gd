class_name ShipPatternPreview
extends Control

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")

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
	match ship_pattern:
		ShipAppearanceScript.ZEBRA:
			for stripe in [
				[Vector2(-25.0, -25.0), Vector2(-8.0, 18.0)],
				[Vector2(-6.0, -21.0), Vector2(7.0, 15.0)],
				[Vector2(14.0, -14.0), Vector2(24.0, 10.0)],
			]:
				draw_line(center + stripe[0], center + stripe[1], accent, 6.0, true)
		ShipAppearanceScript.LEOPARD:
			for spot in [Vector2(-22.0, -15.0), Vector2(-18.0, 14.0), Vector2(3.0, -9.0), Vector2(13.0, 12.0), Vector2(30.0, 0.0)]:
				draw_circle(center + spot, 5.5, accent)
				draw_circle(center + spot, 2.3, Color(ship_color.darkened(0.55), 0.95))
		ShipAppearanceScript.CHECKERBOARD:
			for column in 4:
				for row in 3:
					if (column + row) % 2 == 0:
						var tile_center := center + Vector2(-18.0 + column * 12.0, -12.0 + row * 12.0)
						draw_rect(Rect2(tile_center - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), accent, true)
		ShipAppearanceScript.RACING:
			draw_line(center + Vector2(-27.0, -7.0), center + Vector2(41.0, -7.0), accent, 5.0, true)
			draw_line(center + Vector2(-27.0, 7.0), center + Vector2(41.0, 7.0), accent, 5.0, true)
		ShipAppearanceScript.CHEVRON:
			for x in [-13.0, 8.0, 28.0]:
				draw_polyline(PackedVector2Array([center + Vector2(x - 8.0, -13.0), center + Vector2(x + 5.0, 0.0), center + Vector2(x - 8.0, 13.0)]), accent, 4.0, true)
