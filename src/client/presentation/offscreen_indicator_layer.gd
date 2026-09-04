class_name OffscreenIndicatorLayer
extends Control

var world_view: NetworkWorldView
var _redraw_accumulator: float = 0.0


func setup(view: NetworkWorldView) -> void:
	world_view = view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_redraw_accumulator += maxf(delta, 0.0)
	if _redraw_accumulator >= 0.05:
		_redraw_accumulator = fmod(_redraw_accumulator, 0.05)
		queue_redraw()


func _draw() -> void:
	if world_view == null or world_view.camera == null or not world_view.visible:
		return
	var viewport_size := size
	if viewport_size.is_zero_approx():
		viewport_size = get_viewport_rect().size
	var center := viewport_size * 0.5
	var margin := Vector2(54.0, 54.0)
	for peer_value in world_view.ships.keys():
		var peer_id := int(peer_value)
		if peer_id == world_view.local_peer_id:
			continue
		var ship := world_view.ships[peer_id] as CombatShipView
		if not ship.combatant.alive or ship.combatant.is_cloaked():
			continue
		var screen_position := center + (ship.global_position - world_view.camera.position) * world_view.camera.zoom
		if Rect2(Vector2.ZERO, viewport_size).grow(-36.0).has_point(screen_position):
			continue
		if world_view.camera.position.distance_to(ship.global_position) > 900.0:
			continue
		_draw_ship_indicator(screen_position, center, viewport_size, margin, ship.ship_color, ship.identity_pattern)
		if ship.team_id > 0:
			var point := _edge_point(screen_position, center, viewport_size, margin)
			var team_color := GameModeRules.team_color(ship.team_id)
			if ship.allied_to_local or not ship.has_local_team:
				draw_arc(point, 22.0, 0.0, TAU, 24, team_color, 3.0)
			else:
				draw_polyline(PackedVector2Array([point + Vector2(0, -25), point + Vector2(25, 0), point + Vector2(0, 25), point + Vector2(-25, 0), point + Vector2(0, -25)]), team_color, 3.0)
			draw_string(ThemeDB.fallback_font, point + Vector2(-42, 44), ship.team_marker_text(), HORIZONTAL_ALIGNMENT_CENTER, 84.0, 13, team_color)
	var incoming := world_view.nearest_incoming_offscreen_projectile()
	if incoming != null:
		var projectile_screen := center + (incoming.position - world_view.camera.position) * world_view.camera.zoom
		if not Rect2(Vector2.ZERO, viewport_size).grow(-36.0).has_point(projectile_screen):
			_draw_projectile_indicator(projectile_screen, center, viewport_size, margin)
	if world_view.arena != null:
		var previous_points: Array[Vector2] = []
		for target in world_view.arena.navigation_targets():
			var screen_position := center + ((target.position as Vector2) - world_view.camera.position) * world_view.camera.zoom
			if not Rect2(Vector2.ZERO, viewport_size).grow(-36.0).has_point(screen_position):
				previous_points.append(_draw_objective_indicator(target, screen_position, center, viewport_size, previous_points))


func _draw_objective_indicator(target: Dictionary, screen_position: Vector2, center: Vector2, viewport_size: Vector2, previous_points: Array[Vector2]) -> Vector2:
	# A separate inset keeps objectives apart from the outer ship/threat markers.
	var inset := Vector2(150, 115) if target.kind == "base" else Vector2(150, 190)
	var point := _edge_point(screen_position, center, viewport_size, inset)
	for previous in previous_points:
		if absf(point.y - previous.y) < 65.0 and absf(point.x - previous.x) < 285.0:
			point.y = previous.y + 80.0 if previous.y + 150.0 < viewport_size.y else previous.y - 80.0
	var color := target.color as Color
	var direction := (screen_position - center).normalized()
	draw_line(point, point + direction * 28.0, color, 3.0)
	if target.kind == "base":
		draw_rect(Rect2(point - Vector2(13, 13), Vector2(26, 26)), color, false, 3.0)
	elif target.kind == "flag":
		draw_polyline(PackedVector2Array([point + Vector2(0, -17), point + Vector2(14, 0), point + Vector2(0, 17), point + Vector2(-14, 0), point + Vector2(0, -17)]), color, 3.0)
	else:
		for segment in 4:
			draw_arc(point, 16, segment * PI / 2.0, segment * PI / 2.0 + PI / 3.0, 8, color, 3.0)
	var distance := world_view.camera.position.distance_to(target.position as Vector2)
	var caption := "%s · %d px" % [target.label, roundi(distance)]
	draw_rect(Rect2(point + Vector2(-142, 26), Vector2(284, 26)), Color("030716", 0.9))
	draw_string(ThemeDB.fallback_font, point + Vector2(-140, 46), caption, HORIZONTAL_ALIGNMENT_CENTER, 280, 18, color)
	return point


func _edge_point(screen_position: Vector2, center: Vector2, viewport_size: Vector2, margin: Vector2) -> Vector2:
	var direction := screen_position - center
	if direction.is_zero_approx():
		return center
	var scale_x := (viewport_size.x * 0.5 - margin.x) / absf(direction.x) if absf(direction.x) > 0.001 else INF
	var scale_y := (viewport_size.y * 0.5 - margin.y) / absf(direction.y) if absf(direction.y) > 0.001 else INF
	return center + direction * minf(scale_x, scale_y)


func _draw_ship_indicator(screen_position: Vector2, center: Vector2, viewport_size: Vector2, margin: Vector2, color: Color, pattern: int) -> void:
	var point := _edge_point(screen_position, center, viewport_size, margin)
	var direction := (screen_position - center).normalized()
	var side := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([point + direction * 16.0, point - direction * 12.0 + side * 11.0, point - direction * 12.0 - side * 11.0]), Color(color, 0.92))
	draw_polyline(PackedVector2Array([point + direction * 16.0, point - direction * 12.0 + side * 11.0, point - direction * 12.0 - side * 11.0, point + direction * 16.0]), Color.WHITE, 2.0)
	for mark in pattern + 1:
		draw_circle(point - direction * 20.0 + side * (float(mark) - pattern * 0.5) * 7.0, 2.5, Color.WHITE)


func _draw_projectile_indicator(screen_position: Vector2, center: Vector2, viewport_size: Vector2, margin: Vector2) -> void:
	var point := _edge_point(screen_position, center, viewport_size, margin + Vector2(22.0, 22.0))
	var direction := (screen_position - center).normalized()
	var side := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([point + direction * 12.0, point + side * 9.0, point - direction * 12.0, point - side * 9.0]), Color("fff36a"))
	draw_string(ThemeDB.fallback_font, point + Vector2(16.0, 6.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color("fff36a"))
