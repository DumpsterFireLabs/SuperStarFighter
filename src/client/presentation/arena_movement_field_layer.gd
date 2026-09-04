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
		var field := resource as ArenaMovementFieldDefinition
		if field != null:
			_draw_annular_field(field)


func _draw_annular_field(field: ArenaMovementFieldDefinition) -> void:
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
