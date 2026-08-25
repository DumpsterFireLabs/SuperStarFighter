class_name SplashLogo
extends Control

var elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var pulse := 1.0 + sin(elapsed * 4.0) * 0.035
	for ring_index in 4:
		var radius := (82.0 + ring_index * 26.0) * pulse
		var color := Color("42e8ff") if ring_index % 2 == 0 else Color("ff4fd8")
		draw_arc(center, radius, elapsed * (0.35 + ring_index * 0.08), TAU * (0.58 + ring_index * 0.07), 72, Color(color, 0.18 + ring_index * 0.08), 3.0)
	for ray_index in 16:
		var angle := TAU * ray_index / 16.0 - elapsed * 0.22
		var inner := center + Vector2.from_angle(angle) * 52.0
		var outer := center + Vector2.from_angle(angle) * (112.0 + 12.0 * sin(elapsed * 3.0 + ray_index))
		draw_line(inner, outer, Color("fff36a", 0.28), 2.0)
	var ship_points := PackedVector2Array([
		center + Vector2(58.0, 0.0), center + Vector2(-34.0, -31.0),
		center + Vector2(-18.0, 0.0), center + Vector2(-34.0, 31.0),
	])
	draw_colored_polygon(ship_points, Color("071024", 0.96))
	draw_polyline(PackedVector2Array([ship_points[0], ship_points[1], ship_points[2], ship_points[3], ship_points[0]]), Color("f4fbff"), 6.0, true)
	draw_line(center + Vector2(-28.0, -18.0), center + Vector2(-72.0, -18.0), Color("ff4fd8", 0.8), 8.0)
	draw_line(center + Vector2(-28.0, 18.0), center + Vector2(-72.0, 18.0), Color("42e8ff", 0.8), 8.0)
