class_name SandboxArena
extends Node2D

var overtime_visible: bool = false
var overtime_radius: float = OvertimeSystem.initial_radius()


func _ready() -> void:
	_create_outer_walls()
	_create_central_obstacle()
	_create_cover_islands()
	queue_redraw()


func set_overtime(active: bool, radius: float) -> void:
	overtime_visible = active
	overtime_radius = radius
	queue_redraw()


func _draw() -> void:
	draw_rect(ArenaLayout.arena_rect(), Color("071024"), true)
	_draw_grid()
	draw_rect(ArenaLayout.arena_rect(), Color("36d7ff"), false, 8.0)
	var obstacle_fill := Color("18274a")
	var obstacle_line := Color("a35cff")
	var octagon := ArenaLayout.central_octagon()
	draw_colored_polygon(octagon, obstacle_fill)
	draw_polyline(octagon + PackedVector2Array([octagon[0]]), obstacle_line, 6.0)
	for rectangle in ArenaLayout.cover_rectangles():
		draw_rect(rectangle, obstacle_fill, true)
		draw_rect(rectangle, obstacle_line, false, 5.0)
	for anchor in ArenaLayout.spawn_anchors():
		draw_circle(anchor, 5.0, Color(0.2, 0.85, 1.0, 0.35))
	if overtime_visible:
		draw_circle(ArenaLayout.center(), overtime_radius, Color(1.0, 0.2, 0.42, 0.07))
		draw_arc(ArenaLayout.center(), overtime_radius, 0.0, TAU, 160, Color("ff315f"), 9.0)


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


func _create_central_obstacle() -> void:
	var body := StaticBody2D.new()
	body.name = "CentralOctagon"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionPolygon2D.new()
	collision.polygon = ArenaLayout.central_octagon()
	body.add_child(collision)
	add_child(body)


func _create_cover_islands() -> void:
	var index := 0
	for rectangle in ArenaLayout.cover_rectangles():
		_create_rectangle_body(rectangle.get_center(), rectangle.size, "Cover%d" % index)
		index += 1


func _create_rectangle_body(body_position: Vector2, size: Vector2, body_name: String = "Boundary") -> void:
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
	add_child(body)
