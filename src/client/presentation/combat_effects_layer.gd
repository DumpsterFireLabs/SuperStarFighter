class_name CombatEffectsLayer
extends Node2D

const MINE_EFFECT_DELAY: float = 0.1
const MINE_EFFECT_DURATION: float = 0.9
const MINE_SPARK_COUNT: int = 16
const MINE_SMOKE_COUNT: int = 6
const MAX_ACTIVE_MINE_EFFECTS: int = 24

var effects: Array[Dictionary] = []
var reduced_flashes: bool = false
var active_mine_effect_count: int = 0
var _mine_effect_sequence: int = 0


func _process(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		var effect := effects[index]
		effect.remaining = float(effect.remaining) - delta
		if float(effect.remaining) <= 0.0:
			if StringName(effect.kind) == &"mine":
				active_mine_effect_count = maxi(active_mine_effect_count - 1, 0)
			effects.remove_at(index)
	queue_redraw()


func spawn_impact(position: Vector2, color: Color = Color("f4fbff")) -> void:
	effects.append({"kind": &"impact", "position": position, "color": color, "remaining": 0.22, "duration": 0.22})


func spawn_elimination(position: Vector2, color: Color) -> void:
	effects.append({"kind": &"elimination", "position": position, "color": color, "remaining": 0.65, "duration": 0.65})


func spawn_damage(position: Vector2, direction: Vector2) -> void:
	effects.append({"kind": &"damage", "position": position, "direction": direction, "color": Color("ff4f78"), "remaining": 0.3, "duration": 0.3})


func spawn_mine_explosion(position: Vector2) -> void:
	if active_mine_effect_count >= MAX_ACTIVE_MINE_EFFECTS:
		return
	_mine_effect_sequence += 1
	var random := RandomNumberGenerator.new()
	random.seed = absi(
		roundi(position.x * 73856093.0)
		^ roundi(position.y * 19349663.0)
		^ _mine_effect_sequence * 83492791
	)
	var sparks: Array[Dictionary] = []
	for index in MINE_SPARK_COUNT:
		var angle := TAU * float(index) / float(MINE_SPARK_COUNT) + random.randf_range(-0.18, 0.18)
		sparks.append({
			"direction": Vector2.from_angle(angle),
			"speed": random.randf_range(150.0, 310.0),
			"length": random.randf_range(10.0, 26.0),
			"lifetime": random.randf_range(0.34, 0.68),
		})
	var smoke: Array[Dictionary] = []
	for index in MINE_SMOKE_COUNT:
		var angle := TAU * float(index) / float(MINE_SMOKE_COUNT) + random.randf_range(-0.42, 0.42)
		smoke.append({
			"direction": Vector2.from_angle(angle),
			"distance": random.randf_range(28.0, 62.0),
			"radius": random.randf_range(15.0, 28.0),
		})
	effects.append({
		"kind": &"mine",
		"position": position,
		"color": Color("ff9f43"),
		"remaining": MINE_EFFECT_DURATION,
		"duration": MINE_EFFECT_DURATION,
		"sparks": sparks,
		"smoke": smoke,
	})
	active_mine_effect_count += 1


func spawn_rebound(position: Vector2) -> void:
	effects.append({"kind": &"rebound", "position": position, "color": Color("ff4fd8"), "remaining": 0.3, "duration": 0.3})


func spawn_kinetic_vent(position: Vector2) -> void:
	effects.append({
		"kind": &"kinetic_vent",
		"position": position,
		"color": Color("73f7ff"),
		"remaining": GameConstants.KINETIC_VENT_FEEDBACK_SECONDS,
		"duration": GameConstants.KINETIC_VENT_FEEDBACK_SECONDS,
	})


func clear_effects() -> void:
	effects.clear()
	active_mine_effect_count = 0
	queue_redraw()


func _draw() -> void:
	for effect in effects:
		var progress := 1.0 - float(effect.remaining) / float(effect.duration)
		var alpha := 1.0 - progress
		var position := effect.position as Vector2
		var color := effect.color as Color
		if reduced_flashes:
			# Stable, subdued outlines preserve contact/location cues without bright
			# filled explosions, white cores, or expanding starburst streaks.
			var radius := GameConstants.MINE_BLAST_RADIUS if StringName(effect.kind) == &"mine" else 28.0
			draw_arc(position, radius, 0.0, TAU, 40, Color(color, alpha * 0.42), 2.0, true)
			continue
		match StringName(effect.kind):
			&"impact":
				draw_circle(position, lerpf(5.0, 24.0, progress), Color(color, alpha * 0.24))
				for ray in 6:
					var direction := Vector2.from_angle(TAU * ray / 6.0)
					draw_line(position + direction * 5.0, position + direction * lerpf(8.0, 34.0, progress), Color(color, alpha), 3.0)
			&"elimination":
				draw_circle(position, lerpf(18.0, 86.0, progress), Color(color, alpha * 0.12))
				draw_arc(position, lerpf(20.0, 96.0, progress), 0.0, TAU, 40, Color(color, alpha), 5.0)
				for ray in 10:
					var direction := Vector2.from_angle(TAU * ray / 10.0 + 0.2)
					draw_line(position + direction * 22.0, position + direction * lerpf(30.0, 110.0, progress), Color(color, alpha), 4.0)
			&"damage":
				var direction := (effect.direction as Vector2).normalized()
				var side := direction.orthogonal()
				var tip := position + direction * lerpf(36.0, 64.0, progress)
				draw_colored_polygon(PackedVector2Array([tip, tip - direction * 18.0 + side * 10.0, tip - direction * 18.0 - side * 10.0]), Color(color, alpha))
			&"mine":
				_draw_mine_explosion(effect, position)
			&"rebound":
				draw_circle(position, lerpf(12.0, 46.0, progress), Color(color, alpha * 0.2))
				draw_arc(position, lerpf(16.0, 52.0, progress), -PI * 0.7, PI * 0.7, 24, Color(color, alpha), 5.0)
				for ray in 5:
					var direction := Vector2.from_angle(PI + lerpf(-0.65, 0.65, ray / 4.0))
					draw_line(position, position + direction * lerpf(14.0, 54.0, progress), Color(color, alpha), 3.0)
			&"kinetic_vent":
				var radius := lerpf(28.0, GameConstants.KINETIC_VENT_RADIUS, _smooth_unit(progress))
				draw_circle(position, radius, Color(color, alpha * 0.055))
				draw_arc(position, radius, 0.0, TAU, 64, Color(color, alpha * 0.9), lerpf(7.0, 2.0, progress), true)


func _draw_mine_explosion(effect: Dictionary, position: Vector2) -> void:
	var elapsed := float(effect.duration) - float(effect.remaining)
	if elapsed < MINE_EFFECT_DELAY:
		var charge_progress := clampf(elapsed / MINE_EFFECT_DELAY, 0.0, 1.0)
		var charge_radius := lerpf(24.0, 5.0, _smooth_unit(charge_progress))
		draw_circle(position, charge_radius, Color("fff7c2", 0.12 + charge_progress * 0.34))
		draw_arc(position, charge_radius + 5.0, -PI * 0.85, PI * 0.85, 24, Color("ff9f43", 0.72), 2.5)
		return

	var age := elapsed - MINE_EFFECT_DELAY
	var life := MINE_EFFECT_DURATION - MINE_EFFECT_DELAY
	var progress := clampf(age / life, 0.0, 1.0)
	var smooth_progress := _smooth_unit(progress)
	var fade := 1.0 - smooth_progress

	# Smoke sits behind the hot core and drifts outward after the initial flash.
	var smoke_progress := _smooth_unit(clampf((age - 0.08) / maxf(life - 0.08, 0.001), 0.0, 1.0))
	for puff_value in effect.get("smoke", []):
		var puff := puff_value as Dictionary
		var direction := puff.direction as Vector2
		var center := position + direction * float(puff.distance) * smoke_progress + Vector2.UP * 13.0 * smoke_progress
		var radius := float(puff.radius) * lerpf(0.42, 1.35, smoke_progress)
		draw_circle(center, radius, Color("211827", (1.0 - smoke_progress) * 0.28))
		draw_circle(center - direction * radius * 0.18, radius * 0.62, Color("60323a", (1.0 - smoke_progress) * 0.14))

	var shock_progress := _smooth_unit(clampf(age / 0.52, 0.0, 1.0))
	var shock_radius := lerpf(16.0, GameConstants.MINE_BLAST_RADIUS, shock_progress)
	draw_circle(position, shock_radius, Color("ff6d43", fade * 0.075))
	draw_arc(position, shock_radius, 0.0, TAU, 64, Color("fff36a", fade * 0.92), lerpf(7.0, 1.5, shock_progress), true)
	if age > 0.055:
		var echo_progress := _smooth_unit(clampf((age - 0.055) / 0.58, 0.0, 1.0))
		draw_arc(
			position,
			lerpf(12.0, GameConstants.MINE_BLAST_RADIUS * 0.82, echo_progress),
			0.0,
			TAU,
			56,
			Color("ff784f", (1.0 - echo_progress) * 0.46),
			3.0,
			true
		)

	# Fast streaks sell the explosion without requiring a texture or particle node.
	for spark_value in effect.get("sparks", []):
		var spark := spark_value as Dictionary
		var spark_progress := clampf(age / float(spark.lifetime), 0.0, 1.0)
		if spark_progress >= 1.0:
			continue
		var direction := spark.direction as Vector2
		var distance := float(spark.speed) * age * (1.0 - spark_progress * 0.24)
		var head := position + direction * distance
		var trail_length := float(spark.length) * (1.0 - spark_progress * 0.55)
		var spark_color := Color("fffbd1").lerp(Color("ff5a36"), spark_progress)
		draw_line(head - direction * trail_length, head, Color(spark_color, (1.0 - spark_progress) * 0.92), lerpf(4.0, 1.2, spark_progress), true)

	var flash_progress := clampf(age / 0.14, 0.0, 1.0)
	var flash_fade := (1.0 - flash_progress) * (1.0 - flash_progress)
	draw_circle(position, lerpf(10.0, 58.0, _smooth_unit(flash_progress)), Color("ff7a3d", flash_fade * 0.68))
	draw_circle(position, lerpf(8.0, 29.0, flash_progress), Color("fffbd6", flash_fade * 0.96))
	if flash_progress < 0.72:
		for ray in 8:
			var direction := Vector2.from_angle(TAU * float(ray) / 8.0 + 0.19)
			draw_line(position + direction * 8.0, position + direction * lerpf(24.0, 74.0, flash_progress), Color("ffd35a", flash_fade), 4.0, true)


func _smooth_unit(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
