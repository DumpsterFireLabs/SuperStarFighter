class_name CardMechanicIcon
extends Control

var family: StringName = &"hull"
var accent: Color = DesignTokens.INTERACTIVE


func _init() -> void:
	custom_minimum_size = Vector2(32, 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	draw_set_transform(center, 0.0, Vector2.ONE * minf(size.x / 32.0, size.y / 28.0))
	match family:
		&"hull":
			_path([Vector2(0, -10), Vector2(10, -5), Vector2(7, 6), Vector2(0, 10), Vector2(-7, 6), Vector2(-10, -5), Vector2(0, -10)])
		&"shield", &"coverage", &"rebound", &"vent", &"escape", &"ram":
			draw_arc(Vector2.ZERO, 10, -PI * 0.85, PI * 0.85, 24, accent, 2, true)
			if family == &"coverage":
				draw_arc(Vector2.ZERO, 6, PI * 0.85, PI * 1.15, 8, accent, 2, true)
			elif family == &"vent":
				_path([Vector2(-6, 3), Vector2(0, -4), Vector2(6, 3)])
			elif family == &"rebound":
				_path([Vector2(-8, -5), Vector2(5, 0), Vector2(-8, 5)])
			elif family in [&"escape", &"ram"]:
				_arrow(Vector2(-7, 0), Vector2(6, 0))
			else:
				draw_line(Vector2(-3, -5), Vector2(-3, 5), accent, 2, true)
		&"repair":
			draw_line(Vector2(-9, 0), Vector2(9, 0), accent, 4, true)
			draw_line(Vector2(0, -9), Vector2(0, 9), accent, 4, true)
		&"mobility", &"boost":
			_path([Vector2(-9, 9), Vector2(0, -10), Vector2(9, 9), Vector2(0, 5), Vector2(-9, 9)])
			if family == &"boost":
				draw_line(Vector2(-2, 8), Vector2(-2, 13), accent, 2, true)
				draw_line(Vector2(2, 8), Vector2(2, 13), accent, 2, true)
		&"mine":
			draw_arc(Vector2.ZERO, 6, 0, TAU, 16, accent, 2, true)
			for index in 8:
				var direction := Vector2.RIGHT.rotated(index * TAU / 8.0)
				draw_line(direction * 7, direction * 11, accent, 2, true)
		&"missile":
			_path([Vector2(-9, 7), Vector2(3, -8), Vector2(10, -10), Vector2(8, -3), Vector2(-7, 9), Vector2(-9, 7)])
			draw_line(Vector2(-8, 1), Vector2(-12, 5), accent, 2, true)
		&"cloak":
			_path([Vector2(-12, 0), Vector2(-5, -6), Vector2(5, -6), Vector2(12, 0), Vector2(5, 6), Vector2(-5, 6), Vector2(-12, 0)])
			draw_line(Vector2(-10, 10), Vector2(10, -10), accent, 2, true)
		&"scatter":
			for y in [-8, 0, 8]:
				_arrow(Vector2(-10, 0), Vector2(10, y))
		&"pierce":
			draw_line(Vector2(1, -10), Vector2(1, 10), Color(accent, 0.5), 3, true)
			_arrow(Vector2(-12, 0), Vector2(12, 0))
		&"ricochet":
			_path([Vector2(-12, 8), Vector2(0, -8), Vector2(12, 8)])
			draw_line(Vector2(-6, -11), Vector2(6, -11), accent, 2, true)
		&"beam":
			draw_line(Vector2(-13, 0), Vector2(13, 0), accent, 3, true)
			draw_line(Vector2(-10, -5), Vector2(10, -5), Color(accent, 0.55), 1, true)
			draw_line(Vector2(-10, 5), Vector2(10, 5), Color(accent, 0.55), 1, true)
		&"cycling":
			draw_arc(Vector2.ZERO, 9, 0.0, PI * 1.65, 24, accent, 2, true)
			_path([Vector2(0, -11), Vector2(5, -8), Vector2(0, -5)])
		&"velocity":
			_arrow(Vector2(-7, 0), Vector2(12, 0))
			draw_line(Vector2(-13, -5), Vector2(-5, -5), accent, 2, true)
			draw_line(Vector2(-13, 5), Vector2(-5, 5), accent, 2, true)
		_:
			_path([Vector2(-11, 0), Vector2(-4, -3), Vector2(0, -10), Vector2(4, -3), Vector2(11, 0), Vector2(4, 3), Vector2(0, 10), Vector2(-4, 3), Vector2(-11, 0)])


func _path(points: PackedVector2Array) -> void:
	draw_polyline(points, accent, 2, true)


func _arrow(start: Vector2, finish: Vector2) -> void:
	draw_line(start, finish, accent, 2, true)
	var direction := (finish - start).normalized()
	_path([finish - direction.rotated(0.6) * 5, finish, finish - direction.rotated(-0.6) * 5])
