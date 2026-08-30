class_name OvertimeSystem
extends RefCounted


static func initial_radius(
	zone_center: Vector2 = GameConstants.ARENA_SIZE * 0.5
) -> float:
	var arena := ArenaLayout.arena_rect()
	return maxf(
		maxf(zone_center.distance_to(arena.position), zone_center.distance_to(Vector2(arena.end.x, arena.position.y))),
		maxf(zone_center.distance_to(Vector2(arena.position.x, arena.end.y)), zone_center.distance_to(arena.end))
	)


static func is_active(heat_elapsed: float) -> bool:
	return heat_elapsed >= GameConstants.OVERTIME_START_SECONDS


static func is_warning(heat_elapsed: float) -> bool:
	return heat_elapsed >= (
		GameConstants.OVERTIME_START_SECONDS - GameConstants.OVERTIME_WARNING_SECONDS
	) and not is_active(heat_elapsed)


static func radius_at(
	heat_elapsed: float,
	zone_center: Vector2 = GameConstants.ARENA_SIZE * 0.5,
	minimum_radius: float = GameConstants.OVERTIME_MINIMUM_RADIUS
) -> float:
	if not is_active(heat_elapsed):
		return initial_radius(zone_center)
	var shrink_progress := clampf(
		(heat_elapsed - GameConstants.OVERTIME_START_SECONDS) /
		GameConstants.OVERTIME_SHRINK_SECONDS,
		0.0,
		1.0
	)
	return lerpf(
		initial_radius(zone_center),
		minimum_radius,
		shrink_progress
	)


static func damage_rate_at(heat_elapsed: float) -> float:
	if not is_active(heat_elapsed):
		return 0.0
	var minimum_time := (
		GameConstants.OVERTIME_START_SECONDS + GameConstants.OVERTIME_SHRINK_SECONDS
	)
	var completed_steps := 0
	if heat_elapsed >= minimum_time:
		completed_steps = floori(
			(heat_elapsed - minimum_time) / GameConstants.OVERTIME_DAMAGE_STEP_SECONDS
		)
	return minf(
		GameConstants.OVERTIME_BASE_DAMAGE_PER_SECOND +
		completed_steps * GameConstants.OVERTIME_DAMAGE_STEP,
		GameConstants.OVERTIME_MAX_DAMAGE_PER_SECOND
	)


static func damage_for_position(
	position: Vector2,
	heat_elapsed: float,
	delta: float,
	zone_center: Vector2 = GameConstants.ARENA_SIZE * 0.5,
	minimum_radius: float = GameConstants.OVERTIME_MINIMUM_RADIUS
) -> float:
	if not is_active(heat_elapsed):
		return 0.0
	if position.distance_to(zone_center) <= radius_at(heat_elapsed, zone_center, minimum_radius):
		return 0.0
	return damage_rate_at(heat_elapsed) * maxf(delta, 0.0)
