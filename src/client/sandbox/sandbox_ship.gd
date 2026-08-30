class_name SandboxShip
extends CharacterBody2D

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const ShipPatternGeometryScript = preload("res://src/client/presentation/ship_pattern_geometry.gd")

var combatant: CombatantState
var ship_color: Color = Color("42e8ff")
var ship_pattern: StringName = ShipAppearanceScript.SOLID
var local_control: bool = false
var display_name: String = "Pilot"
var identity_pattern: int = 0
var damage_flash_remaining: float = 0.0
var shield_flash_remaining: float = 0.0
var elimination_pulse_remaining: float = 0.0
var thruster_particles: CPUParticles2D
var thruster_intensity: float = 0.0
var afterburner_bloom_remaining: float = 0.0


func setup(peer_id: int, stats: CombatStats, spawn_position: Vector2, color: Color, is_local: bool = false, pilot_name: String = "", pattern: StringName = ShipAppearanceScript.SOLID) -> void:
	combatant = CombatantState.create(peer_id, stats, spawn_position)
	ship_color = Color(color.r, color.g, color.b, 1.0)
	ship_pattern = pattern if ShipAppearanceScript.is_valid_pattern(pattern) else ShipAppearanceScript.SOLID
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
	_create_thruster_particles()
	queue_redraw()


func set_ship_color(color: Color) -> void:
	var opaque_color := Color(color.r, color.g, color.b, 1.0)
	if ship_color.is_equal_approx(opaque_color):
		return
	ship_color = opaque_color
	_update_thruster_color_ramp()
	queue_redraw()


func set_ship_appearance(color: Color, pattern: StringName) -> void:
	set_ship_color(color)
	set_ship_pattern(pattern)


func set_ship_pattern(pattern: StringName) -> void:
	var normalized := pattern if ShipAppearanceScript.is_valid_pattern(pattern) else ShipAppearanceScript.SOLID
	if ship_pattern == normalized:
		return
	ship_pattern = normalized
	queue_redraw()


func _process(delta: float) -> void:
	damage_flash_remaining = maxf(damage_flash_remaining - delta, 0.0)
	shield_flash_remaining = maxf(shield_flash_remaining - delta, 0.0)
	elimination_pulse_remaining = maxf(elimination_pulse_remaining - delta, 0.0)
	afterburner_bloom_remaining = maxf(afterburner_bloom_remaining - delta, 0.0)
	_update_thruster_particles()
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
	if thruster_particles != null:
		thruster_particles.emitting = false
	queue_redraw()


func flash_damage() -> void:
	damage_flash_remaining = 0.18
	queue_redraw()


func flash_shield_block() -> void:
	shield_flash_remaining = 0.2
	queue_redraw()


func flash_afterburner(duration: float = 0.18) -> void:
	afterburner_bloom_remaining = maxf(afterburner_bloom_remaining, duration)
	queue_redraw()


func reset_ship(stats: CombatStats, spawn_position: Vector2) -> void:
	combatant.reset_for_heat(stats, spawn_position)
	global_position = spawn_position
	damage_flash_remaining = 0.0
	shield_flash_remaining = 0.0
	elimination_pulse_remaining = 0.0
	afterburner_bloom_remaining = 0.0
	collision_layer = 2
	collision_mask = 3
	if thruster_particles != null:
		thruster_particles.restart()
	queue_redraw()


func _create_thruster_particles() -> void:
	thruster_particles = CPUParticles2D.new()
	thruster_particles.name = "ThrusterParticles"
	thruster_particles.amount = 10
	thruster_particles.lifetime = 0.42
	thruster_particles.randomness = 0.45
	thruster_particles.local_coords = false
	thruster_particles.direction = Vector2.LEFT
	thruster_particles.spread = 16.0
	thruster_particles.gravity = Vector2.ZERO
	thruster_particles.initial_velocity_min = 42.0
	thruster_particles.initial_velocity_max = 92.0
	thruster_particles.scale_amount_min = 1.4
	thruster_particles.scale_amount_max = 3.2
	_update_thruster_color_ramp()
	thruster_particles.z_index = -1
	thruster_particles.emitting = false
	add_child(thruster_particles)


func _update_thruster_color_ramp() -> void:
	if thruster_particles == null:
		return
	var color_fade := Gradient.new()
	color_fade.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	color_fade.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.82),
		Color(ship_color.lightened(0.18), 0.58),
		Color(ship_color, 0.0),
	])
	thruster_particles.color_ramp = color_fade


func _update_thruster_particles() -> void:
	if thruster_particles == null or combatant == null or not combatant.alive or combatant.is_cloaked():
		thruster_intensity = 0.0
		if thruster_particles != null:
			thruster_particles.emitting = false
		return
	var speed := combatant.velocity.length()
	thruster_intensity = clampf(speed / maxf(combatant.stats.max_speed, 1.0), 0.0, 1.0)
	if speed <= 12.0:
		thruster_particles.emitting = false
		return
	var travel_direction := combatant.velocity / speed
	var afterburning := afterburner_bloom_remaining > 0.0
	thruster_particles.position = -travel_direction * 18.0
	thruster_particles.rotation = travel_direction.angle()
	thruster_particles.amount = 36 if afterburning else 10
	thruster_particles.spread = 24.0 if afterburning else 16.0
	thruster_particles.initial_velocity_min = 110.0 if afterburning else 42.0
	thruster_particles.initial_velocity_max = 230.0 if afterburning else 92.0
	thruster_particles.scale_amount_min = 1.8 if afterburning else 1.4
	thruster_particles.scale_amount_max = 4.8 if afterburning else 3.2
	thruster_particles.speed_scale = (2.15 if afterburning else lerpf(0.7, 1.35, thruster_intensity))
	thruster_particles.emitting = true


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
	if combatant.is_cloaked():
		if not local_control:
			return
		var cloak_forward := Vector2.from_angle(combatant.aim_angle)
		var cloak_side := cloak_forward.orthogonal()
		var cloak_points := PackedVector2Array([
			cloak_forward * 29.0,
			-cloak_forward * 19.0 + cloak_side * 17.0,
			-cloak_forward * 11.0,
			-cloak_forward * 19.0 - cloak_side * 17.0,
		])
		draw_colored_polygon(cloak_points, Color(ship_color, 0.06))
		draw_polyline(cloak_points + PackedVector2Array([cloak_points[0]]), Color("73f7ff", 0.34), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(-52.0, -45.0), "CLOAKED", HORIZONTAL_ALIGNMENT_CENTER, 104.0, 14, Color("73f7ff", 0.62))
		return
	var forward := Vector2.from_angle(combatant.aim_angle)
	var side := forward.orthogonal()
	var points := PackedVector2Array([forward * 29.0, -forward * 19.0 + side * 17.0, -forward * 11.0, -forward * 19.0 - side * 17.0])
	draw_polyline(points + PackedVector2Array([points[0]]), Color(ship_color, 0.18), 12.0)
	draw_colored_polygon(points, Color(ship_color.darkened(0.45), 0.82))
	_draw_cosmetic_pattern(forward, side)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE if damage_flash_remaining > 0.0 else ship_color, 6.0 if local_control else 4.0)
	draw_circle(Vector2.ZERO, 6.0, Color("ffffff"))
	for mark in identity_pattern + 1:
		var offset := (float(mark) - identity_pattern * 0.5) * 8.0
		draw_line(-forward * 8.0 + side * offset, -forward * 16.0 + side * offset, Color.WHITE, 2.5)
	if local_control:
		var marker_center := -forward * 39.0
		draw_polyline(PackedVector2Array([marker_center - side * 9.0, marker_center + forward * 8.0, marker_center + side * 9.0]), Color("fff36a"), 4.0)
		_draw_ammo_indicator()
	if combatant.shield.active:
		var half_arc := deg_to_rad(combatant.stats.shield_arc_degrees) * 0.5
		draw_arc(Vector2.ZERO, 32.0, combatant.aim_angle - half_arc, combatant.aim_angle + half_arc, 32, Color("5cf6ff", 0.22), 14.0)
		draw_arc(Vector2.ZERO, 32.0, combatant.aim_angle - half_arc, combatant.aim_angle + half_arc, 32, Color.WHITE if shield_flash_remaining > 0.0 else Color("5cf6ff"), 7.0)
	var health_angle := TAU * combatant.health_fraction()
	draw_arc(Vector2.ZERO, 26.0, -PI * 0.5, -PI * 0.5 + health_angle, 24, Color("54ff8b"), 2.0)
	_draw_nameplate(Color("fff36a") if local_control else Color("e8f5ff"))


func _draw_cosmetic_pattern(forward: Vector2, side: Vector2) -> void:
	var accent := Color(ship_color.lightened(0.52), 0.92)
	var pattern_shapes := ShipPatternGeometryScript.shapes(ship_pattern)
	_draw_pattern_polygons(pattern_shapes.accent, forward, side, accent)
	_draw_pattern_polygons(pattern_shapes.detail, forward, side, Color(ship_color.darkened(0.6), 0.96))


func _ship_local(point: Vector2, forward: Vector2, side: Vector2) -> Vector2:
	return forward * point.x + side * point.y


func _draw_pattern_polygons(polygons: Array, forward: Vector2, side: Vector2, color: Color) -> void:
	for polygon_value in polygons:
		var polygon := polygon_value as PackedVector2Array
		var transformed := PackedVector2Array()
		for point in polygon:
			transformed.append(_ship_local(point, forward, side))
		draw_colored_polygon(transformed, color)


func _draw_nameplate(color: Color) -> void:
	var label := "◆ %s" % display_name if local_control else display_name
	draw_string(ThemeDB.fallback_font, Vector2(-70.0, -45.0), label, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16, color)


func _draw_ammo_indicator() -> void:
	var weapon := combatant.weapon
	var magazine_size := maxi(combatant.stats.magazine_size, 1)
	var fraction := clampf(float(weapon.ammunition) / float(magazine_size), 0.0, 1.0)
	var background := Rect2(-36.0, -78.0, 72.0, 8.0)
	draw_rect(background, Color("071024", 0.92), true)
	draw_rect(background, Color("fff36a", 0.75), false, 1.5)
	if fraction > 0.0:
		draw_rect(Rect2(background.position + Vector2(2.0, 2.0), Vector2((background.size.x - 4.0) * fraction, background.size.y - 4.0)), Color("ff9f43") if fraction <= 0.25 else Color("73f7ff"), true)
	var text := ammo_indicator_text()
	draw_string(ThemeDB.fallback_font, Vector2(-52.0, -83.0), text, HORIZONTAL_ALIGNMENT_CENTER, 104.0, 13, Color("fff36a") if weapon.reloading else Color("e8f5ff"))


func ammo_indicator_text() -> String:
	if combatant == null:
		return ""
	var weapon := combatant.weapon
	return "RELOAD %.1fs" % weapon.reload_remaining if weapon.reloading else "AMMO %d/%d" % [weapon.ammunition, maxi(combatant.stats.magazine_size, 1)]
