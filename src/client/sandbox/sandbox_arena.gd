class_name SandboxArena
extends Node2D

var overtime_visible: bool = false
var overtime_radius: float = OvertimeSystem.initial_radius()
var show_spawn_anchors: bool = false
var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var obstacle_root: Node2D


func _ready() -> void:
	_create_outer_walls()
	_rebuild_map_collision()
	queue_redraw()


func set_map_id(value: StringName) -> void:
	var normalized := ArenaLayout.normalized_map_id(value)
	if normalized == map_id and obstacle_root != null:
		return
	map_id = normalized
	if is_inside_tree():
		_rebuild_map_collision()
	queue_redraw()


func set_overtime(active: bool, radius: float) -> void:
	overtime_visible = active
	overtime_radius = radius
	queue_redraw()


func _draw() -> void:
	var palette := ArenaLayout.theme(map_id)
	draw_rect(ArenaLayout.arena_rect().grow(1600.0), Color("030716"), true)
	draw_rect(ArenaLayout.arena_rect(), palette.floor, true)
	_draw_stars()
	_draw_grid()
	draw_rect(ArenaLayout.arena_rect(), palette.border, false, 8.0)
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		draw_rect(rectangle, palette.obstacle, true)
		draw_rect(rectangle, palette.line, false, 5.0)
	for circle in ArenaLayout.circle_obstacles(map_id):
		draw_circle(circle.center, float(circle.radius), palette.obstacle)
		draw_arc(circle.center, float(circle.radius), 0.0, TAU, 64, palette.line, 6.0)
	if show_spawn_anchors:
		for anchor in ArenaLayout.spawn_anchors(map_id):
			draw_circle(anchor, 5.0, Color(0.2, 0.85, 1.0, 0.35))
	draw_string(ThemeDB.fallback_font, Vector2(70.0, 92.0), ArenaLayout.display_name(map_id).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(palette.border, 0.34))
	if overtime_visible:
		var pulse := 0.72 + sin(Time.get_ticks_msec() * 0.008) * 0.2
		draw_circle(ArenaLayout.center(map_id), overtime_radius, Color(1.0, 0.2, 0.42, 0.1))
		draw_arc(ArenaLayout.center(map_id), overtime_radius, 0.0, TAU, 160, Color("ff315f", pulse * 0.2), 22.0)
		draw_arc(ArenaLayout.center(map_id), overtime_radius, 0.0, TAU, 160, Color("ff315f", pulse), 8.0)
		queue_redraw()


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


func _create_outer_walls() -> void:
	var thickness := 60.0
	_create_rectangle_body(Vector2(GameConstants.ARENA_SIZE.x * 0.5, -thickness * 0.5), Vector2(GameConstants.ARENA_SIZE.x + thickness * 2.0, thickness))
	_create_rectangle_body(Vector2(GameConstants.ARENA_SIZE.x * 0.5, GameConstants.ARENA_SIZE.y + thickness * 0.5), Vector2(GameConstants.ARENA_SIZE.x + thickness * 2.0, thickness))
	_create_rectangle_body(Vector2(-thickness * 0.5, GameConstants.ARENA_SIZE.y * 0.5), Vector2(thickness, GameConstants.ARENA_SIZE.y))
	_create_rectangle_body(Vector2(GameConstants.ARENA_SIZE.x + thickness * 0.5, GameConstants.ARENA_SIZE.y * 0.5), Vector2(thickness, GameConstants.ARENA_SIZE.y))


func _rebuild_map_collision() -> void:
	if obstacle_root != null:
		remove_child(obstacle_root)
		obstacle_root.free()
	obstacle_root = Node2D.new()
	obstacle_root.name = "MapObstacles"
	add_child(obstacle_root)
	var index := 0
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		_create_rectangle_body(rectangle.get_center(), rectangle.size, "Cover%d" % index, obstacle_root)
		index += 1
	index = 0
	for circle in ArenaLayout.circle_obstacles(map_id):
		_create_circle_body(circle.center, float(circle.radius), "Circle%d" % index)
		index += 1


func _create_rectangle_body(body_position: Vector2, size: Vector2, body_name: String = "Boundary", parent: Node = null) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = body_position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	(parent if parent != null else self).add_child(body)


func _create_circle_body(body_position: Vector2, radius: float, body_name: String) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = body_position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	body.add_child(collision)
	obstacle_root.add_child(body)
