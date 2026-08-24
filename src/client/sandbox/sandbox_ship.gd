class_name SandboxShip
extends CharacterBody2D

var combatant: CombatantState
var ship_color: Color = Color("42e8ff")
var local_control: bool = false


func setup(peer_id: int, stats: CombatStats, spawn_position: Vector2, color: Color, is_local: bool = false) -> void:
	combatant = CombatantState.create(peer_id, stats, spawn_position)
	ship_color = color
	local_control = is_local
	global_position = spawn_position
	name = "Ship%d" % peer_id
	collision_layer = 2
	collision_mask = 3
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = GameConstants.SHIP_COLLISION_RADIUS
	collision.shape = circle
	add_child(collision)
	queue_redraw()


func simulate(input_direction: Vector2, aim_angle: float, shield_held: bool, delta: float) -> void:
	combatant.step(input_direction, aim_angle, shield_held, delta)
	velocity = combatant.velocity
	move_and_slide()
	combatant.velocity = velocity
	combatant.position = global_position
	queue_redraw()


func set_eliminated() -> void:
	collision_layer = 0
	collision_mask = 0
	queue_redraw()


func reset_ship(stats: CombatStats, spawn_position: Vector2) -> void:
	combatant.reset_for_heat(stats, spawn_position)
	global_position = spawn_position
	collision_layer = 2
	collision_mask = 3
	queue_redraw()


func _draw() -> void:
	if combatant == null:
		return
	if not combatant.alive:
		draw_circle(Vector2.ZERO, 24.0, Color(1.0, 0.2, 0.35, 0.18))
		draw_line(Vector2(-15.0, -15.0), Vector2(15.0, 15.0), Color("ff315f"), 5.0)
		draw_line(Vector2(-15.0, 15.0), Vector2(15.0, -15.0), Color("ff315f"), 5.0)
		return
	var forward := Vector2.from_angle(combatant.aim_angle)
	var side := forward.orthogonal()
	var points := PackedVector2Array([forward * 29.0, -forward * 19.0 + side * 17.0, -forward * 11.0, -forward * 19.0 - side * 17.0])
	draw_colored_polygon(points, Color(ship_color, 0.28))
	draw_polyline(points + PackedVector2Array([points[0]]), ship_color, 4.0)
	draw_circle(Vector2.ZERO, 6.0, Color("ffffff"))
	if local_control:
		var marker_center := -forward * 39.0
		draw_polyline(PackedVector2Array([marker_center - side * 9.0, marker_center + forward * 8.0, marker_center + side * 9.0]), Color("fff36a"), 4.0)
	if combatant.shield.active:
		var half_arc := deg_to_rad(combatant.stats.shield_arc_degrees) * 0.5
		draw_arc(Vector2.ZERO, 32.0, combatant.aim_angle - half_arc, combatant.aim_angle + half_arc, 32, Color("5cf6ff"), 7.0)
	var health_angle := TAU * combatant.health_fraction()
	draw_arc(Vector2.ZERO, 26.0, -PI * 0.5, -PI * 0.5 + health_angle, 24, Color("54ff8b"), 2.0)
