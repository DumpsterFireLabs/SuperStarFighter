class_name NeonBackdrop
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color("05091b"), true)
	var drift := Time.get_ticks_msec() * 0.006
	for index in 80:
		var x := fposmod(index * 197.0 + drift * (1.0 + index % 3), maxf(size.x, 1.0))
		var y := fposmod(index * 113.0 + index * index * 3.0, maxf(size.y, 1.0))
		draw_circle(Vector2(x, y), 1.0 + index % 3, Color("bcecff", 0.14 + (index % 4) * 0.07))
	var horizon := size.y * 0.68
	for line in 13:
		var progress := float(line) / 12.0
		var y := lerpf(horizon, size.y, progress * progress)
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color("42e8ff", 0.06 + progress * 0.13), 2.0)
	for column in 17:
		var x := size.x * float(column) / 16.0
		draw_line(Vector2(size.x * 0.5, horizon), Vector2(x, size.y), Color("d39cff", 0.09), 2.0)
	draw_circle(Vector2(size.x * 0.18, size.y * 0.22), 150.0, Color("42e8ff", 0.025))
	draw_circle(Vector2(size.x * 0.82, size.y * 0.28), 210.0, Color("d39cff", 0.025))
