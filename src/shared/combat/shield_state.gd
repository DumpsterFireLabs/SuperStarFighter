class_name ShieldState
extends RefCounted

var energy: float = 0.0
var active: bool = false
var depletion_locked: bool = false
var time_since_activity: float = 0.0


func reset(stats: CombatStats) -> void:
	energy = stats.shield_capacity
	active = false
	depletion_locked = false
	time_since_activity = stats.shield_regeneration_delay


func step(held: bool, stats: CombatStats, delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	var may_activate := held and not depletion_locked and energy > 0.0
	active = may_activate
	if active:
		time_since_activity = 0.0
		energy = maxf(energy - stats.shield_continuous_drain * safe_delta, 0.0)
		if energy <= 0.0:
			active = false
			depletion_locked = true
		return

	var previous_inactivity := time_since_activity
	time_since_activity += safe_delta
	var regeneration_time := maxf(
		time_since_activity - stats.shield_regeneration_delay,
		0.0
	) - maxf(previous_inactivity - stats.shield_regeneration_delay, 0.0)
	if regeneration_time > 0.0:
		energy = minf(
			energy + stats.shield_regeneration * regeneration_time,
			stats.shield_capacity
		)
	if depletion_locked and energy >= minf(
		GameConstants.SHIELD_DEPLETION_THRESHOLD,
		stats.shield_capacity
	):
		depletion_locked = false


func can_block(
	aim_angle: float,
	impact_vector: Vector2,
	arc_degrees: float
) -> bool:
	if not active or impact_vector.is_zero_approx():
		return false
	var impact_angle := impact_vector.angle()
	var half_arc := deg_to_rad(arc_degrees) * 0.5
	return absf(angle_difference(aim_angle, impact_angle)) <= half_arc + 0.00001


func try_block(
	aim_angle: float,
	impact_vector: Vector2,
	stats: CombatStats
) -> bool:
	if not can_block(aim_angle, impact_vector, stats.shield_arc_degrees):
		return false
	time_since_activity = 0.0
	energy = maxf(energy - GameConstants.SHIELD_BLOCK_COST, 0.0)
	if energy <= 0.0:
		active = false
		depletion_locked = true
	return true
