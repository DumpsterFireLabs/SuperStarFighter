class_name ArenaMovementFieldLayer
extends Node2D

const ARROW_COUNT: int = 18
const REDRAW_INTERVAL_SECONDS: float = 1.0 / 30.0

var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var high_contrast: bool = false
var animation_time: float = 0.0
var redraw_remaining: float = 0.0


func set_map(value: StringName) -> void:
	map_id = ArenaLayout.normalized_map_id(value)
	set_process(not ArenaLayout.movement_fields(map_id).is_empty())
	queue_redraw()


func set_high_contrast(value: bool) -> void:
	high_contrast = value
	queue_redraw()


func _process(delta: float) -> void:
	animation_time += maxf(delta, 0.0)
	redraw_remaining -= maxf(delta, 0.0)
	if redraw_remaining <= 0.0:
		redraw_remaining = REDRAW_INTERVAL_SECONDS
		queue_redraw()


func _draw() -> void:
	for resource in ArenaLayout.movement_fields(map_id):
		var field := resource as ArenaMovementField
		if field != null:
			match field.visual_style:
				&"star": _draw_sun(field)
				&"black_hole": _draw_wormhole(field)
				_: _draw_annular_field(field)


func _draw_annular_field(field: ArenaMovementField) -> void:
	var palette := ArenaLayout.theme(map_id)
	var flow_color := Color("77f8ff") if high_contrast else Color(palette.line).lerp(Color("77f8ff"), 0.55)
	var segments := 96
	var orbit_radius := (field.inner_radius + field.outer_radius) * 0.5
	var band_width := field.outer_radius - field.inner_radius
	# A thick closed arc produces a reliable annulus without asking the polygon
	# triangulator to infer a hole in a self-touching contour.
	draw_arc(field.center, orbit_radius, 0.0, TAU, segments, Color(flow_color, 0.15 if high_contrast else 0.085), band_width, true)
	draw_arc(field.center, field.inner_radius, 0.0, TAU, segments, Color(flow_color, 0.88 if high_contrast else 0.42), 4.0 if high_contrast else 2.0, true)
	draw_arc(field.center, field.outer_radius, 0.0, TAU, segments, Color(flow_color, 0.88 if high_contrast else 0.42), 4.0 if high_contrast else 2.0, true)
	var direction_sign := 1.0 if field.clockwise else -1.0
	var phase := fmod(animation_time * 0.42 * direction_sign, TAU / float(ARROW_COUNT))
	for index in ARROW_COUNT:
		var angle := TAU * float(index) / float(ARROW_COUNT) + phase
		var arrow_center := field.center + Vector2.from_angle(angle) * orbit_radius
		var tangent := field.flow_direction_at(arrow_center)
		var side := tangent.orthogonal()
		var tip := arrow_center + tangent * 18.0
		var rear := arrow_center - tangent * 14.0
		draw_colored_polygon(PackedVector2Array([
			tip,
			rear + side * 9.0,
			rear - side * 9.0,
		]), Color(flow_color, 0.96 if high_contrast else 0.72))
		if not high_contrast:
			draw_circle(arrow_center - tangent * 28.0, 2.5, Color(flow_color, 0.34))
	var label_position := field.center + Vector2(-180.0, -field.outer_radius - 22.0)
	draw_string(
		ThemeDB.fallback_font,
		label_position,
		field.mechanic_prompt(),
		HORIZONTAL_ALIGNMENT_CENTER,
		360.0,
		22,
		Color(flow_color, 1.0 if high_contrast else 0.78)
	)


func _draw_sun(field: ArenaMovementField) -> void:
	var center := field.center
	# The star is the solid circle obstacle sharing the field's center.
	var radius := 130.0
	for circle in ArenaLayout.circle_obstacles(map_id):
		if (circle.center as Vector2).is_equal_approx(center):
			radius = float(circle.radius)
	for layer in range(8, 0, -1):
		draw_circle(center, radius + float(layer) * 8.0, Color(1.0, 0.35, 0.04, 0.025))
	draw_circle(center, radius, Color("ff8e24"))
	draw_circle(center, radius - 12.0, Color("ffd36a"))
	draw_circle(center, radius - 29.0, Color("fff2b5"))
	for index in 12:
		var angle := TAU * float(index) / 12.0 + animation_time * 0.08
		var direction := Vector2.from_angle(angle)
		var reach := 12.0 + 8.0 * sin(animation_time * 2.0 + float(index))
		draw_line(center + direction * radius, center + direction * (radius + reach), Color("ffb542"), 4.0, true)
	for ring in 3:
		var phase := fposmod(float(ring) / 3.0 - animation_time * 0.06, 1.0)
		draw_arc(center, lerpf(180.0, field.outer_radius, phase), 0.0, TAU, 96, Color(1.0, 0.65, 0.25, (1.0 - phase) * 0.12), 2.0, true)
	draw_string(ThemeDB.fallback_font, center + Vector2(-128, 210), "STAR CONTACT BURNS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffd36a"))


func _draw_wormhole(field: ArenaMovementField) -> void:
	var amber := Color("ff9b28")
	var gold := Color("fff1a3") if high_contrast else Color("ffdb73")
	var rim_radius := field.event_horizon_radius if field.event_horizon_radius > 0.0 else 108.0
	# Faint infalling rings reveal the pull without filling the combat area.
	for ring in 7:
		var phase := fposmod(float(ring) / 7.0 - animation_time * 0.075, 1.0)
		var radius := lerpf(rim_radius + 24.0, field.outer_radius, phase * phase)
		draw_arc(field.center, radius, 0.0, TAU, 128, Color(amber, (1.0 - phase) * 0.12), 2.0, true)
	# Layered translucent bands create a warm halo without a bloom dependency.
	for layer in range(12, 0, -1):
		var spread := float(layer)
		draw_arc(field.center, rim_radius + spread * 2.2, 0.0, TAU, 160,
			Color("ff6418", 0.018 + (12.0 - spread) * 0.002), spread * 8.0, true)
	for arm in 6:
		var points := PackedVector2Array()
		for step in 81:
			var t := float(step) / 80.0
			var angle := TAU * float(arm) / 6.0 + t * 3.8 + animation_time * 0.22
			points.append(field.center + Vector2.from_angle(angle) * lerpf(rim_radius + 9.0, 305.0, t * t))
		draw_polyline(points, Color(amber, 0.18), 2.0, true)
	# Uneven orbiting bands suggest hot matter circling the black silhouette.
	for band in 5:
		var radius := rim_radius + float(band) * 4.5
		var start := animation_time * (0.34 + float(band) * 0.06) + float(band) * 1.7
		draw_arc(field.center, radius, start, start + TAU * 0.78, 128,
			Color(amber.lerp(gold, 1.0 - float(band) / 5.0), 0.65 - float(band) * 0.09), 4.5, true)
	draw_circle(field.center, rim_radius - 3.0, Color("010103"))
	draw_arc(field.center, rim_radius, 0.0, TAU, 160, Color("ff841f"), 8.0, true)
	draw_arc(field.center, rim_radius - 1.0, 0.0, TAU, 160, gold, 3.0, true)
	var hotspot := animation_time * 0.38
	draw_arc(field.center, rim_radius, hotspot, hotspot + 1.4, 48, Color("fff4c4"), 4.0, true)
	draw_string(ThemeDB.fallback_font, field.center + Vector2(-280.0, -365.0),
		field.mechanic_prompt(), HORIZONTAL_ALIGNMENT_CENTER, 560.0, 22, gold)
