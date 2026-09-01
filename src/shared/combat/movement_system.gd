class_name MovementSystem
extends RefCounted


static func sanitize_input(input_direction: Vector2) -> Vector2:
	if not input_direction.is_finite():
		return Vector2.ZERO
	return input_direction.limit_length(1.0)


static func ship_relative_to_world(local_input: Vector2, aim_angle: float) -> Vector2:
	var movement := sanitize_input(local_input)
	var forward := Vector2.from_angle(normalize_aim_angle(aim_angle))
	var right := -forward.orthogonal()
	return sanitize_input(forward * -movement.y + right * movement.x)


static func world_to_ship_relative(world_input: Vector2, aim_angle: float) -> Vector2:
	var movement := sanitize_input(world_input)
	if movement.is_zero_approx():
		return Vector2.ZERO
	var forward := Vector2.from_angle(normalize_aim_angle(aim_angle))
	var right := -forward.orthogonal()
	return sanitize_input(Vector2(movement.dot(right), -movement.dot(forward)))


static func step_velocity(
	current_velocity: Vector2,
	input_direction: Vector2,
	stats: CombatStats,
	delta: float,
	shielding: bool = false,
	speed_multiplier: float = 1.0,
	acceleration_multiplier: float = 1.0,
	drag_multiplier: float = 1.0
) -> Vector2:
	var safe_delta := maxf(delta, 0.0)
	var movement := sanitize_input(input_direction)
	if movement.is_zero_approx():
		return current_velocity.move_toward(Vector2.ZERO, stats.drag * maxf(drag_multiplier, 0.0) * safe_delta)
	var acceleration := stats.acceleration * maxf(acceleration_multiplier, 0.0)
	if shielding:
		acceleration *= stats.shield_acceleration_factor
	return current_velocity.move_toward(
		movement * stats.max_speed * maxf(speed_multiplier, 0.0),
		acceleration * safe_delta
	)


static func normalize_aim_angle(angle: float, fallback: float = 0.0) -> float:
	if not is_finite(angle):
		return fposmod(fallback, TAU)
	return fposmod(angle, TAU)


static func spread_angles(
	center_angle: float,
	projectile_count: int,
	total_spread_degrees: float
) -> Array[float]:
	var count := maxi(projectile_count, 1)
	var result: Array[float] = []
	if count == 1:
		result.append(normalize_aim_angle(center_angle))
		return result
	var spread_radians := deg_to_rad(maxf(total_spread_degrees, 0.0))
	var step := spread_radians / float(count - 1)
	var start := center_angle - spread_radians * 0.5
	for index in count:
		result.append(normalize_aim_angle(start + step * index))
	return result
