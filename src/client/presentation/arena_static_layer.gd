class_name ArenaStaticLayer
extends Node2D

# Cached canvas commands: objective pulses never invalidate static geometry.
var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var show_spawn_anchors: bool = false
var hidden_cover := 0
var high_contrast: bool = false


func _draw() -> void:
	var palette := ArenaLayout.theme(map_id)
	draw_rect(ArenaLayout.arena_rect().grow(1600.0), Color("030716"), true)
	draw_rect(ArenaLayout.arena_rect(), palette.floor, true)
	_draw_stars()
	_draw_grid()
	draw_rect(ArenaLayout.arena_rect(), Color(palette.border, 0.65), false, 5.0)
	var landmark_index := 0
	for rectangle in ArenaCollisionSystem.cover_rectangles(map_id, hidden_cover):
		draw_rect(rectangle, palette.obstacle, true)
		_draw_rect_material(rectangle, palette, landmark_index)
		draw_rect(rectangle, Color(palette.line.lightened(0.3) if high_contrast else palette.line, 0.95 if high_contrast else 0.55), false, 4.0 if high_contrast else 3.0)
		landmark_index += 1
	for circle in ArenaLayout.circle_obstacles(map_id):
		draw_circle(circle.center, float(circle.radius), palette.obstacle)
		_draw_circle_material(circle.center, float(circle.radius), palette, landmark_index)
		draw_arc(circle.center, float(circle.radius), 0.0, TAU, 64, Color(palette.line.lightened(0.3) if high_contrast else palette.line, 0.95 if high_contrast else 0.55), 4.0 if high_contrast else 3.0)
		landmark_index += 1
	if show_spawn_anchors:
		for anchor in ArenaLayout.spawn_anchors(map_id):
			draw_circle(anchor, 5.0, Color(0.2, 0.85, 1.0, 0.35))
	draw_string(ThemeDB.fallback_font, Vector2(70.0, 92.0), ArenaLayout.display_name(map_id).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(palette.border, 0.34))


func _draw_stars() -> void:
	for index in 144:
		var x := -1600.0 + float(posmod(index * 977 + 131, int(GameConstants.ARENA_SIZE.x + 3200.0)))
		var y := -1600.0 + float(posmod(index * 577 + 83, int(GameConstants.ARENA_SIZE.y + 3200.0)))
		var radius := 1.0 + float(index % 3) * 0.55
		var color := Color("d7f5ff", 0.18 + float(index % 4) * 0.09)
		draw_circle(Vector2(x, y), radius, color)


func _draw_grid() -> void:
	var minor := Color(0.15, 0.35, 0.6, 0.09)
	var major := Color(0.2, 0.7, 0.9, 0.12)
	for x in range(0, int(GameConstants.ARENA_SIZE.x) + 1, 100):
		var color := major if x % 400 == 0 else minor
		draw_line(Vector2(x, 0.0), Vector2(x, GameConstants.ARENA_SIZE.y), color, 2.0)
	for y in range(0, int(GameConstants.ARENA_SIZE.y) + 1, 100):
		var color := major if y % 400 == 0 else minor
		draw_line(Vector2(0.0, y), Vector2(GameConstants.ARENA_SIZE.x, y), color, 2.0)


static func material_for_map(value: StringName) -> StringName:
	return ArenaLayout.material_family(value)


func _draw_rect_material(rectangle: Rect2, palette: Dictionary, index: int) -> void:
	var inset := rectangle.grow(-12.0)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		return
	var ink := Color(palette.line, 0.35 if high_contrast else 0.18)
	var material := material_for_map(map_id)
	match material:
		&"cargo":
			# Cargo ribs terminate inside the collider's continuous outer wall.
			for x in range(int(inset.position.x), int(inset.end.x), 42):
				draw_line(Vector2(x, inset.position.y), Vector2(x, inset.end.y), ink, 3.0)
			for corner in [inset.position, inset.end, Vector2(inset.position.x, inset.end.y), Vector2(inset.end.x, inset.position.y)]:
				draw_circle(corner, 4.0, ink)
		&"crystal":
			var center := inset.get_center()
			draw_colored_polygon(PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), center]), Color(palette.line, 0.08))
			draw_line(inset.position, center, ink, 2.0)
			draw_line(inset.end, center, ink, 2.0)
			draw_line(Vector2(inset.position.x, inset.end.y), center, ink, 2.0)
		&"thermal":
			for y in range(int(inset.position.y), int(inset.end.y), 26):
				draw_line(Vector2(inset.position.x, y), Vector2(inset.end.x, y), ink, 4.0)
		&"stone":
			var center := inset.get_center()
			draw_polyline(PackedVector2Array([inset.position, center + Vector2(-15, 10), center, inset.end]), ink, 2.0)
			draw_line(center, Vector2(inset.end.x, inset.position.y), ink, 2.0)
		_:
			draw_rect(inset, ink, false, 2.0)
			var center := inset.get_center()
			draw_line(Vector2(center.x, inset.position.y), Vector2(center.x, inset.end.y), ink, 2.0)
	_draw_landmark(inset.get_center(), index, palette)


func _draw_circle_material(center: Vector2, radius: float, palette: Dictionary, index: int) -> void:
	var ink := Color(palette.line, 0.35 if high_contrast else 0.18)
	var inner := maxf(radius - 18.0, 0.0)
	match material_for_map(map_id):
		&"crystal", &"stone":
			var facets := PackedVector2Array()
			for point_index in 7:
				facets.append(center + Vector2.from_angle(TAU * point_index / 6.0) * inner)
			draw_polyline(facets, ink, 2.0)
			for point_index in 3:
				draw_line(center, facets[point_index * 2], ink, 2.0)
		_:
			draw_arc(center, inner, 0.0, TAU, 48, ink, 3.0)
			draw_arc(center, inner * 0.7, 0.0, TAU, 48, ink, 2.0)
			for point_index in 8:
				var direction := Vector2.from_angle(TAU * point_index / 8.0)
				draw_line(center + direction * inner * 0.74, center + direction * inner * 0.94, ink, 4.0)
	_draw_landmark(center, index, palette)


func _draw_landmark(center: Vector2, index: int, palette: Dictionary) -> void:
	var label := "%s %02d" % [str(material_for_map(map_id)).to_upper(), index + 1]
	draw_string(ThemeDB.fallback_font, center + Vector2(-70, 7), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 18, Color(palette.line, 0.75 if high_contrast else 0.4))
