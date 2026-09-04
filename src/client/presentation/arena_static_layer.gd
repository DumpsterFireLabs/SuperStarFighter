class_name ArenaStaticLayer
extends Node2D

# Cached canvas commands: objective pulses never invalidate static geometry.
var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var show_spawn_anchors: bool = false


func _draw() -> void:
	var palette := ArenaLayout.theme(map_id)
	draw_rect(ArenaLayout.arena_rect().grow(1600.0), Color("030716"), true)
	draw_rect(ArenaLayout.arena_rect(), palette.floor, true)
	_draw_stars()
	_draw_grid()
	draw_rect(ArenaLayout.arena_rect(), Color(palette.border, 0.65), false, 5.0)
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		draw_rect(rectangle, palette.obstacle, true)
		draw_rect(rectangle, Color(palette.line, 0.48), false, 3.0)
	for circle in ArenaLayout.circle_obstacles(map_id):
		draw_circle(circle.center, float(circle.radius), palette.obstacle)
		draw_arc(circle.center, float(circle.radius), 0.0, TAU, 64, Color(palette.line, 0.48), 3.0)
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
