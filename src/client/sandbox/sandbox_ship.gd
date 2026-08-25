class_name SandboxShip
extends CharacterBody2D

var combatant: CombatantState
var ship_color: Color = Color("42e8ff")
var local_control: bool = false
var display_name: String = "Pilot"
var identity_pattern: int = 0
var damage_flash_remaining: float = 0.0
var shield_flash_remaining: float = 0.0
var elimination_pulse_remaining: float = 0.0


func setup(peer_id: int, stats: CombatStats, spawn_position: Vector2, color: Color, is_local: bool = false, pilot_name: String = "") -> void:
	combatant = CombatantState.create(peer_id, stats, spawn_position)
	ship_color = color
	local_control = is_local
	display_name = pilot_name if not pilot_name.is_empty() else "Pilot %d" % peer_id
	identity_pattern = posmod(peer_id, 3)
	global_position = spawn_position
	z_index = 3
	name = "Ship%d" % peer_id
	collision_layer = 2
	collision_mask = 3
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = GameConstants.SHIP_COLLISION_RADIUS
	collision.shape = circle
	add_child(collision)
	queue_redraw()


func _process(delta: float) -> void:
	damage_flash_remaining = maxf(damage_flash_remaining - delta, 0.0)
	shield_flash_remaining = maxf(shield_flash_remaining - delta, 0.0)
	elimination_pulse_remaining = maxf(elimination_pulse_remaining - delta, 0.0)
	if damage_flash_remaining > 0.0 or shield_flash_remaining > 0.0 or elimination_pulse_remaining > 0.0:
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
	elimination_pulse_remaining = 0.65
	queue_redraw()


func flash_damage() -> void:
	damage_flash_remaining = 0.18
	queue_redraw()


func flash_shield_block() -> void:
	shield_flash_remaining = 0.2
	queue_redraw()


func reset_ship(stats: CombatStats, spawn_position: Vector2) -> void:
	combatant.reset_for_heat(stats, spawn_position)
	global_position = spawn_position
	damage_flash_remaining = 0.0
	shield_flash_remaining = 0.0
	elimination_pulse_remaining = 0.0
	collision_layer = 2
	collision_mask = 3
	queue_redraw()


func _draw() -> void:
	if combatant == null:
		return
	if not combatant.alive:
		var pulse_radius := 24.0 + elimination_pulse_remaining * 48.0
		draw_circle(Vector2.ZERO, pulse_radius, Color(1.0, 0.2, 0.35, 0.1 + elimination_pulse_remaining * 0.14))
		draw_line(Vector2(-15.0, -15.0), Vector2(15.0, 15.0), Color("ff315f"), 5.0)
		draw_line(Vector2(-15.0, 15.0), Vector2(15.0, -15.0), Color("ff315f"), 5.0)
		_draw_nameplate(Color("ff7994"))
		return
	var forward := Vector2.from_angle(combatant.aim_angle)
	var side := forward.orthogonal()
	var points := PackedVector2Array([forward * 29.0, -forward * 19.0 + side * 17.0, -forward * 11.0, -forward * 19.0 - side * 17.0])
	draw_polyline(points + PackedVector2Array([points[0]]), Color(ship_color, 0.18), 12.0)
	draw_colored_polygon(points, Color(ship_color.darkened(0.45), 0.82))
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE if damage_flash_remaining > 0.0 else ship_color, 6.0 if local_control else 4.0)
	draw_circle(Vector2.ZERO, 6.0, Color("ffffff"))
	var exhaust_origin := -forward * 19.0
	draw_line(exhaust_origin + side * 7.0, exhaust_origin - forward * (12.0 + combatant.velocity.length() * 0.015), Color(ship_color, 0.7), 4.0)
	for mark in identity_pattern + 1:
		var offset := (float(mark) - identity_pattern * 0.5) * 8.0
		draw_line(-forward * 8.0 + side * offset, -forward * 16.0 + side * offset, Color.WHITE, 2.5)
	if local_control:
		var marker_center := -forward * 39.0
		draw_polyline(PackedVector2Array([marker_center - side * 9.0, marker_center + forward * 8.0, marker_center + side * 9.0]), Color("fff36a"), 4.0)
	if combatant.shield.active:
		var half_arc := deg_to_rad(combatant.stats.shield_arc_degrees) * 0.5
		draw_arc(Vector2.ZERO, 32.0, combatant.aim_angle - half_arc, combatant.aim_angle + half_arc, 32, Color("5cf6ff", 0.22), 14.0)
		draw_arc(Vector2.ZERO, 32.0, combatant.aim_angle - half_arc, combatant.aim_angle + half_arc, 32, Color.WHITE if shield_flash_remaining > 0.0 else Color("5cf6ff"), 7.0)
	var health_angle := TAU * combatant.health_fraction()
	draw_arc(Vector2.ZERO, 26.0, -PI * 0.5, -PI * 0.5 + health_angle, 24, Color("54ff8b"), 2.0)
	_draw_nameplate(Color("fff36a") if local_control else Color("e8f5ff"))


func _draw_nameplate(color: Color) -> void:
	var label := "◆ %s" % display_name if local_control else display_name
	draw_string(ThemeDB.fallback_font, Vector2(-70.0, -45.0), label, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16, color)
