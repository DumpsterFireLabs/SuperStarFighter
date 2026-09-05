class_name CombatShipView
extends CharacterBody2D

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const ShipPatternGeometryScript = preload("res://src/client/presentation/ship_pattern_geometry.gd")
const BuildGeometry = preload("res://src/client/presentation/ship_build_geometry.gd")
const DEFAULT_SHIELD_COLOR: Color = Color("5cf6ff")
const AFTERBURNER_IGNITION_SECONDS: float = 0.12
const AFTERBURNER_ECHO_LIFETIME_SECONDS: float = 0.30
const AFTERBURNER_ECHO_INTERVAL_SECONDS: float = 0.045
const MAX_AFTERBURNER_ECHOES: int = 6

var combatant: CombatantState
var ship_color: Color = Color("42e8ff")
var shield_color: Color = DEFAULT_SHIELD_COLOR
var ship_pattern: StringName = ShipAppearanceScript.SOLID
var local_control: bool = false
var display_name: String = "Pilot"
var identity_pattern: int = 0
var damage_flash_remaining: float = 0.0
var reduced_flashes: bool = false
var high_contrast: bool = false
var shield_flash_remaining: float = 0.0
var elimination_pulse_remaining: float = 0.0
var thruster_particles: CPUParticles2D
var thruster_intensity: float = 0.0
var afterburner_bloom_remaining: float = 0.0
var afterburner_duration: float = 0.0
var afterburner_ignition_remaining: float = 0.0
var afterburner_echo_accumulator: float = 0.0
var afterburner_echoes: Array[Dictionary] = []
var thrust_input: Vector2 = Vector2.ZERO
var team_id: int = 0
var allied_to_local: bool = false
var has_local_team: bool = false
var movement_field_strength: float = 0.0
var show_combat_details: bool = true


func set_combat_focus(focus: Vector2, crowded: bool) -> void:
	var detailed := local_control or not crowded or global_position.distance_squared_to(focus) <= 360.0 * 360.0
	if detailed != show_combat_details:
		show_combat_details = detailed
		queue_redraw()


func set_team_identity(value: int, local_team: int) -> void:
	team_id = value
	has_local_team = local_team > 0
	allied_to_local = team_id > 0 and team_id == local_team
	queue_redraw()


func team_marker_text() -> String:
	if team_id <= 0:
		return ""
	var relation := "YOU" if local_control else ("ALLY" if allied_to_local else "ENEMY")
	return "T%d %s" % [team_id, relation] if has_local_team else "TEAM %d" % team_id


func setup(peer_id: int, stats: CombatStats, spawn_position: Vector2, color: Color, is_local: bool = false, pilot_name: String = "", pattern: StringName = ShipAppearanceScript.SOLID) -> void:
	combatant = CombatantState.create(peer_id, stats, spawn_position)
	ship_color = Color(color.r, color.g, color.b, 1.0)
	ship_pattern = pattern if ShipAppearanceScript.is_valid_pattern(pattern) else ShipAppearanceScript.SOLID
	local_control = is_local
	display_name = pilot_name if not pilot_name.is_empty() else "Pilot %d" % peer_id
	identity_pattern = posmod(peer_id, 3)
	global_position = spawn_position
	z_index = 4 if is_local else 3
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


func set_shield_build(build: Dictionary, catalog: CardCatalog) -> void:
	var highest_shield_card: CardDefinition
	for card_value in build:
		if int(build[card_value]) <= 0:
			continue
		var card := catalog.get_card(StringName(card_value))
		if card == null or card.category != CardDefinition.Category.SHIELD:
			continue
		if highest_shield_card == null or card.rarity > highest_shield_card.rarity:
			highest_shield_card = card
	shield_color = highest_shield_card.rarity_color() if highest_shield_card != null else DEFAULT_SHIELD_COLOR
	queue_redraw()


func _process(delta: float) -> void:
	damage_flash_remaining = maxf(damage_flash_remaining - delta, 0.0)
	shield_flash_remaining = maxf(shield_flash_remaining - delta, 0.0)
	elimination_pulse_remaining = maxf(elimination_pulse_remaining - delta, 0.0)
	afterburner_bloom_remaining = maxf(afterburner_bloom_remaining - delta, 0.0)
	afterburner_ignition_remaining = maxf(afterburner_ignition_remaining - delta, 0.0)
	_update_afterburner_echoes(delta)
	_update_thruster_particles()
	if (
		damage_flash_remaining > 0.0
		or shield_flash_remaining > 0.0
		or elimination_pulse_remaining > 0.0
		or afterburner_bloom_remaining > 0.0
		or afterburner_ignition_remaining > 0.0
		or not afterburner_echoes.is_empty()
		or not thrust_input.is_zero_approx()
		or movement_field_strength > 0.0
		or combatant != null and (combatant.breakaway_remaining > 0.0 or combatant.shield.is_perfect_guard_active() or combatant.shield.has_perfect_guard_feedback())
	):
		queue_redraw()


func simulate(input_direction: Vector2, aim_angle: float, shield_held: bool, delta: float) -> void:
	combatant.step(input_direction, aim_angle, shield_held, delta)
	velocity = combatant.velocity
	move_and_slide()
	combatant.velocity = velocity
	combatant.position = global_position
	queue_redraw()


func set_thrust_input(ship_relative_input: Vector2) -> void:
	var normalized := MovementSystem.sanitize_input(ship_relative_input)
	if thrust_input.is_equal_approx(normalized):
		return
	thrust_input = normalized
	queue_redraw()


func set_movement_field_strength(value: float) -> void:
	var normalized := clampf(value, 0.0, 1.0)
	if is_equal_approx(movement_field_strength, normalized):
		return
	movement_field_strength = normalized
	queue_redraw()


func set_eliminated() -> void:
	collision_layer = 0
	collision_mask = 0
	elimination_pulse_remaining = 0.65
	thrust_input = Vector2.ZERO
	afterburner_bloom_remaining = 0.0
	afterburner_ignition_remaining = 0.0
	afterburner_echoes.clear()
	if thruster_particles != null:
		thruster_particles.emitting = false
	movement_field_strength = 0.0
	queue_redraw()


func flash_damage() -> void:
	damage_flash_remaining = 0.18
	queue_redraw()


func flash_shield_block() -> void:
	shield_flash_remaining = 0.2
	queue_redraw()


func flash_afterburner(duration: float = 0.18) -> void:
	var safe_duration := maxf(duration, 0.0)
	var newly_active := afterburner_bloom_remaining <= 0.0
	afterburner_bloom_remaining = maxf(afterburner_bloom_remaining, safe_duration)
	if newly_active:
		afterburner_duration = safe_duration
		afterburner_ignition_remaining = AFTERBURNER_IGNITION_SECONDS
		afterburner_echo_accumulator = AFTERBURNER_ECHO_INTERVAL_SECONDS
	else:
		afterburner_duration = maxf(afterburner_duration, safe_duration)
	queue_redraw()


func sustain_afterburner(duration: float = 0.14) -> void:
	var safe_duration := maxf(duration, 0.0)
	afterburner_bloom_remaining = maxf(afterburner_bloom_remaining, safe_duration)
	afterburner_duration = maxf(afterburner_duration, safe_duration)
	queue_redraw()


func reset_ship(stats: CombatStats, spawn_position: Vector2) -> void:
	combatant.reset_for_heat(stats, spawn_position)
	global_position = spawn_position
	damage_flash_remaining = 0.0
	shield_flash_remaining = 0.0
	elimination_pulse_remaining = 0.0
	afterburner_bloom_remaining = 0.0
	afterburner_duration = 0.0
	afterburner_ignition_remaining = 0.0
	afterburner_echo_accumulator = 0.0
	afterburner_echoes.clear()
	thrust_input = Vector2.ZERO
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
	var breaking_away := combatant.breakaway_remaining > 0.0
	thruster_particles.position = -travel_direction * 18.0
	thruster_particles.rotation = travel_direction.angle()
	thruster_particles.amount = 18 if afterburning else (15 if breaking_away else 10)
	thruster_particles.spread = 10.0 if afterburning else (21.0 if breaking_away else 16.0)
	thruster_particles.initial_velocity_min = 86.0 if afterburning else (76.0 if breaking_away else 42.0)
	thruster_particles.initial_velocity_max = 168.0 if afterburning else (150.0 if breaking_away else 92.0)
	thruster_particles.scale_amount_min = 1.5 if afterburning else (1.7 if breaking_away else 1.4)
	thruster_particles.scale_amount_max = 3.8 if afterburning else (4.2 if breaking_away else 3.2)
	thruster_particles.speed_scale = (1.75 if afterburning else (1.65 if breaking_away else lerpf(0.7, 1.35, thruster_intensity)))
	thruster_particles.emitting = true


func _update_afterburner_echoes(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	for echo in afterburner_echoes:
		echo["age"] = float(echo.get("age", 0.0)) + safe_delta
	while not afterburner_echoes.is_empty() and float(afterburner_echoes[0].get("age", 0.0)) >= AFTERBURNER_ECHO_LIFETIME_SECONDS:
		afterburner_echoes.pop_front()
	if afterburner_bloom_remaining <= 0.0 or combatant == null or not combatant.alive or combatant.is_cloaked():
		return
	afterburner_echo_accumulator += safe_delta
	while afterburner_echo_accumulator >= AFTERBURNER_ECHO_INTERVAL_SECONDS:
		afterburner_echo_accumulator -= AFTERBURNER_ECHO_INTERVAL_SECONDS
		afterburner_echoes.append({
			"position": global_position,
			"aim_angle": combatant.aim_angle,
			"age": 0.0,
		})
		while afterburner_echoes.size() > MAX_AFTERBURNER_ECHOES:
			afterburner_echoes.pop_front()


func _draw() -> void:
	if combatant == null:
		return
	if not combatant.alive:
		var pulse_radius := 24.0 + elimination_pulse_remaining * 48.0
		if not reduced_flashes:
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
	if high_contrast:
		draw_circle(Vector2.ZERO, 30.0, Color("02040d"))
	_draw_team_marker()
	_draw_movement_field_wake()
	_draw_afterburner_echoes()
	_draw_maneuvering_jets(forward, side)
	_draw_afterburner_plume(forward, side)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(ship_color, 0.18), 12.0)
	draw_colored_polygon(points, Color(ship_color.darkened(0.45), 0.82))
	_draw_cosmetic_pattern(forward, side)
	if show_combat_details:
		_draw_build_modules(forward, side)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE if damage_flash_remaining > 0.0 and not reduced_flashes else (ship_color.lightened(0.55) if high_contrast else ship_color), 6.0 if local_control else 4.0)
	draw_circle(Vector2.ZERO, 6.0, Color("ffffff"))
	for mark in identity_pattern + 1:
		var offset := (float(mark) - identity_pattern * 0.5) * 8.0
		draw_line(-forward * 8.0 + side * offset, -forward * 16.0 + side * offset, Color.WHITE, 2.5)
	if local_control:
		var marker_center := -side * 39.0 if afterburner_bloom_remaining > 0.0 else -forward * 39.0
		draw_polyline(PackedVector2Array([marker_center - side * 9.0, marker_center + forward * 8.0, marker_center + side * 9.0]), Color("fff36a"), 4.0)
		_draw_ammo_indicator()
	if combatant.shield.active:
		var half_arc := deg_to_rad(combatant.stats.shield_arc_degrees) * 0.5
		var perfect_guard := combatant.shield.is_perfect_guard_active() or combatant.shield.has_perfect_guard_feedback()
		# Rarity belongs to the outer shield. A separate inner timing cue avoids
		# making every Perfect Guard window look like a Legendary upgrade.
		if combatant.stats.rebound_shield_enabled:
			draw_arc(Vector2.ZERO, GameConstants.REBOUND_SHIELD_RADIUS, 0.0, TAU, 40, Color(shield_color, 0.45), 2.0)
		draw_arc(Vector2.ZERO, 32.0, combatant.aim_angle - half_arc, combatant.aim_angle + half_arc, 32, Color(shield_color, 0.22), 14.0)
		draw_arc(Vector2.ZERO, 32.0, combatant.aim_angle - half_arc, combatant.aim_angle + half_arc, 32, Color.WHITE if shield_flash_remaining > 0.0 and not reduced_flashes else shield_color, 7.0)
		if perfect_guard:
			var guard_half_arc := minf(half_arc, PI / 6.0)
			draw_arc(Vector2.ZERO, 22.0, combatant.aim_angle - guard_half_arc, combatant.aim_angle + guard_half_arc, 12, Color.WHITE, 2.0)
	if combatant.breakaway_remaining > 0.0:
		var breakaway_alpha := clampf(combatant.breakaway_remaining / GameConstants.BREAKAWAY_DURATION_SECONDS, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 32, Color("ff9f43", breakaway_alpha * 0.75), 3.0)
	var health_angle := TAU * combatant.health_fraction()
	draw_arc(Vector2.ZERO, 26.0, -PI * 0.5, -PI * 0.5 + health_angle, 24, Color("54ff8b"), 2.0)
	_draw_nameplate(Color("fff36a") if local_control else Color("e8f5ff"))


func _draw_movement_field_wake() -> void:
	if movement_field_strength <= 0.0 or combatant.velocity.is_zero_approx():
		return
	var direction := combatant.velocity.normalized()
	var side := direction.orthogonal()
	var color := Color("77f8ff", 0.38 + movement_field_strength * 0.42)
	var origin := -direction * 18.0
	for index in 3:
		var distance := 18.0 + float(index) * 13.0
		var half_width := 10.0 - float(index) * 2.0
		var center := origin - direction * distance
		draw_polyline(PackedVector2Array([
			center - direction * 7.0 + side * half_width,
			center + direction * 5.0,
			center - direction * 7.0 - side * half_width,
		]), color, 3.0 if high_contrast else 2.0, true)


func _draw_afterburner_echoes() -> void:
	for echo in afterburner_echoes:
		var progress := clampf(float(echo.get("age", 0.0)) / AFTERBURNER_ECHO_LIFETIME_SECONDS, 0.0, 1.0)
		var echo_forward := Vector2.from_angle(float(echo.get("aim_angle", 0.0)))
		var echo_side := echo_forward.orthogonal()
		var origin := to_local(echo.get("position", global_position) as Vector2)
		var echo_points := PackedVector2Array([
			origin + echo_forward * 29.0,
			origin - echo_forward * 19.0 + echo_side * 17.0,
			origin - echo_forward * 11.0,
			origin - echo_forward * 19.0 - echo_side * 17.0,
		])
		var alpha := pow(1.0 - progress, 1.7) * 0.34
		draw_colored_polygon(echo_points, Color(ship_color, alpha * 0.16))
		draw_polyline(echo_points + PackedVector2Array([echo_points[0]]), Color(ship_color.lightened(0.42), alpha), lerpf(3.0, 1.0, progress))


func _draw_maneuvering_jets(forward: Vector2, side: Vector2) -> void:
	if thrust_input.is_zero_approx():
		return
	var forward_thrust := maxf(-thrust_input.y, 0.0)
	var reverse_thrust := maxf(thrust_input.y, 0.0)
	var lateral_thrust := thrust_input.x
	if forward_thrust > 0.02 and afterburner_bloom_remaining <= 0.0:
		_draw_jet(-forward * 17.0 + side * 9.0, -forward, forward_thrust, 23.0, 4.5)
		_draw_jet(-forward * 17.0 - side * 9.0, -forward, forward_thrust, 23.0, 4.5)
	if reverse_thrust > 0.02:
		_draw_jet(forward * 15.0 + side * 10.0, forward, reverse_thrust, 16.0, 3.4)
		_draw_jet(forward * 15.0 - side * 10.0, forward, reverse_thrust, 16.0, 3.4)
	if absf(lateral_thrust) > 0.02:
		var lateral_sign := signf(lateral_thrust)
		var exhaust_direction := side * lateral_sign
		var nozzle_side := side * lateral_sign * 14.0
		_draw_jet(nozzle_side + forward * 8.0, exhaust_direction, absf(lateral_thrust), 14.0, 3.0)
		_draw_jet(nozzle_side - forward * 9.0, exhaust_direction, absf(lateral_thrust), 14.0, 3.0)


func _draw_jet(nozzle: Vector2, exhaust_direction: Vector2, intensity: float, maximum_length: float, half_width: float) -> void:
	var strength := clampf(intensity, 0.0, 1.0)
	var direction := exhaust_direction.normalized()
	var cross := direction.orthogonal()
	var pulse := 0.86 if reduced_flashes else 0.86 + sin(Time.get_ticks_msec() * 0.024 + float(combatant.peer_id)) * 0.14
	var length := maximum_length * strength * pulse
	var width := half_width * (0.55 + strength * 0.45)
	var tip := nozzle + direction * length
	draw_colored_polygon(PackedVector2Array([
		nozzle - cross * width,
		nozzle + cross * width,
		tip + cross * width * 0.12,
		tip - cross * width * 0.12,
	]), Color(ship_color.lightened(0.30), 0.26 + strength * 0.34))
	draw_line(nozzle, nozzle + direction * length * 0.72, Color(1.0, 1.0, 1.0, 0.48 + strength * 0.34), maxf(width * 0.55, 1.0), true)


func _draw_afterburner_plume(forward: Vector2, side: Vector2) -> void:
	if afterburner_bloom_remaining <= 0.0:
		return
	if reduced_flashes:
		draw_line(-forward * 18.0, -forward * 86.0, Color(ship_color, 0.42), 7.0, true)
		return
	var elapsed := maxf(afterburner_duration - afterburner_bloom_remaining, 0.0)
	var ignition_mix := clampf(elapsed / 0.055, 0.0, 1.0)
	var shutdown_mix := clampf(afterburner_bloom_remaining / 0.09, 0.0, 1.0)
	var strength := minf(ignition_mix, shutdown_mix)
	var flicker := 0.90 + sin(elapsed * 58.0 + float(combatant.peer_id) * 1.7) * 0.10
	var plume_length := (78.0 + 22.0 * flicker) * strength
	var nozzle := -forward * 18.0
	var tail := nozzle - forward * plume_length
	var outer_width := (11.0 + 2.0 * flicker) * strength
	var middle_width := outer_width * 0.58
	var outer_color := Color(ship_color.lightened(0.18), 0.24 + strength * 0.34)
	var middle_color := Color(ship_color.lightened(0.58), 0.42 + strength * 0.40)
	draw_line(nozzle, tail + forward * plume_length * 0.08, Color(ship_color, 0.08 * strength), maxf(outer_width * 2.8, 1.0), true)
	draw_line(nozzle, tail + forward * plume_length * 0.16, Color(ship_color.lightened(0.32), 0.14 * strength), maxf(outer_width * 1.75, 1.0), true)
	draw_colored_polygon(PackedVector2Array([
		nozzle + side * outer_width,
		nozzle - side * outer_width,
		tail - side * outer_width * 0.10,
		tail + side * outer_width * 0.10,
	]), outer_color)
	draw_colored_polygon(PackedVector2Array([
		nozzle + side * middle_width,
		nozzle - side * middle_width,
		tail + forward * plume_length * 0.15 - side * middle_width * 0.08,
		tail + forward * plume_length * 0.15 + side * middle_width * 0.08,
	]), middle_color)
	draw_circle(nozzle, outer_width * 1.22, Color(ship_color.lightened(0.42), 0.24 * strength))
	draw_circle(nozzle, middle_width * 0.62, Color(1.0, 1.0, 1.0, 0.72 * strength))
	draw_line(nozzle, tail + forward * plume_length * 0.34, Color(1.0, 1.0, 1.0, 0.92 * strength), maxf(3.0 * strength, 1.0), true)
	for diamond_index in 2:
		var center := nozzle - forward * plume_length * (0.32 + diamond_index * 0.29)
		var half_length := plume_length * 0.08
		var half_height := middle_width * (0.62 - diamond_index * 0.12)
		draw_colored_polygon(PackedVector2Array([
			center + forward * half_length,
			center + side * half_height,
			center - forward * half_length,
			center - side * half_height,
		]), Color(1.0, 1.0, 1.0, 0.36 * strength))
	if afterburner_ignition_remaining > 0.0:
		var ring_progress := 1.0 - afterburner_ignition_remaining / AFTERBURNER_IGNITION_SECONDS
		var ring_radius := lerpf(7.0, 34.0, ring_progress)
		draw_arc(nozzle, ring_radius, 0.0, TAU, 28, Color(ship_color.lightened(0.55), (1.0 - ring_progress) * 0.78), lerpf(5.0, 1.0, ring_progress), true)


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


func _draw_team_marker() -> void:
	if team_id <= 0:
		return
	var color := GameModeRules.team_color(team_id)
	if allied_to_local or not has_local_team:
		draw_arc(Vector2.ZERO, 43.0, 0.0, TAU, 40, Color(color, 0.9), 2.5, true)
	else:
		draw_polyline(PackedVector2Array([Vector2(0, -43), Vector2(43, 0), Vector2(0, 43), Vector2(-43, 0), Vector2(0, -43)]), color, 2.5, true)
	if not show_combat_details:
		return
	draw_rect(Rect2(-49, 49, 98, 22), Color("071024"))
	draw_rect(Rect2(-49, 49, 98, 22), color, false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-47, 65), team_marker_text(), HORIZONTAL_ALIGNMENT_CENTER, 94.0, 14, color.lightened(0.25))


func _draw_nameplate(color: Color) -> void:
	if not show_combat_details:
		return
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


func _draw_build_modules(forward: Vector2, side: Vector2) -> void:
	for family in BuildGeometry.families(combatant.stats):
		for polygon in BuildGeometry.polygons(family):
			var transformed := PackedVector2Array()
			for point in polygon:
				transformed.append(forward * point.x + side * point.y)
			draw_colored_polygon(transformed, Color("071024"))
			draw_polyline(transformed + PackedVector2Array([transformed[0]]), ship_color.lightened(0.3), 1.5, true)
