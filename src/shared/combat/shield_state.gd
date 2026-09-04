class_name ShieldState
extends RefCounted

var energy: float = 0.0
var active: bool = false
var depletion_locked: bool = false
var time_since_activity: float = 0.0
var perfect_guard_window_remaining: float = 0.0
var perfect_guard_feedback_remaining: float = 0.0
var kinetic_vent_charge: float = 0.0
var kinetic_vent_release_pending: float = 0.0
var depletion_triggered: bool = false
# Fixed-size presentation accumulators. Only authority drains these; prediction
# cannot publish feedback. Resetting a life discards any undelivered old cues.
var _feedback_blocks: int = 0
var _feedback_breaks: int = 0


func drain_feedback() -> Vector2i:
	var result := Vector2i(_feedback_blocks, _feedback_breaks)
	_feedback_blocks = 0
	_feedback_breaks = 0
	return result


func reset(stats: CombatStats) -> void:
	energy = stats.shield_capacity
	active = false
	depletion_locked = false
	time_since_activity = stats.shield_regeneration_delay
	perfect_guard_window_remaining = 0.0
	perfect_guard_feedback_remaining = 0.0
	kinetic_vent_charge = 0.0
	kinetic_vent_release_pending = 0.0
	depletion_triggered = false
	_feedback_blocks = 0
	_feedback_breaks = 0


func step(held: bool, stats: CombatStats, delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	var was_active := active
	perfect_guard_window_remaining = maxf(perfect_guard_window_remaining - safe_delta, 0.0)
	perfect_guard_feedback_remaining = maxf(perfect_guard_feedback_remaining - safe_delta, 0.0)
	if not stats.kinetic_vent_enabled:
		kinetic_vent_charge = 0.0
		kinetic_vent_release_pending = 0.0
	var may_activate := held and not depletion_locked and energy > 0.0
	active = may_activate
	if active and not was_active:
		perfect_guard_window_remaining = GameConstants.PERFECT_GUARD_WINDOW_SECONDS
	if active:
		time_since_activity = 0.0
		energy = maxf(energy - stats.shield_continuous_drain * safe_delta, 0.0)
		if energy <= 0.0:
			_mark_depleted()
		else:
			return

	if was_active and not active:
		perfect_guard_window_remaining = 0.0
		if not held and not depletion_locked and stats.kinetic_vent_enabled and kinetic_vent_charge >= GameConstants.KINETIC_VENT_MINIMUM_CHARGE:
			kinetic_vent_release_pending = kinetic_vent_charge
		kinetic_vent_charge = 0.0

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
		stats.shield_depletion_threshold,
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
	var perfect_guard := perfect_guard_window_remaining > 0.0
	_consume_impact_energy(
		stats,
		GameConstants.PERFECT_GUARD_BLOCK_COST_FACTOR if perfect_guard else 1.0
	)
	if perfect_guard:
		perfect_guard_window_remaining = 0.0
		perfect_guard_feedback_remaining = GameConstants.PERFECT_GUARD_FEEDBACK_SECONDS
	return true


func try_absorb_contact(stats: CombatStats) -> bool:
	if not active:
		return false
	_consume_impact_energy(stats, 1.0)
	return true


func register_blocked_damage(damage: float, stats: CombatStats) -> void:
	if not stats.kinetic_vent_enabled or depletion_locked or damage <= 0.0:
		return
	kinetic_vent_charge = minf(
		kinetic_vent_charge + damage,
		GameConstants.KINETIC_VENT_MAXIMUM_CHARGE
	)


func consume_kinetic_vent_release() -> float:
	var charge := kinetic_vent_release_pending
	kinetic_vent_release_pending = 0.0
	return charge


func consume_depletion_trigger() -> bool:
	var triggered := depletion_triggered
	depletion_triggered = false
	return triggered


func is_perfect_guard_active() -> bool:
	return active and perfect_guard_window_remaining > 0.0


func has_perfect_guard_feedback() -> bool:
	return perfect_guard_feedback_remaining > 0.0


func _consume_impact_energy(stats: CombatStats, cost_factor: float) -> void:
	_feedback_blocks = mini(_feedback_blocks + 1, 65535)
	time_since_activity = 0.0
	energy = maxf(energy - stats.shield_block_cost * maxf(cost_factor, 0.0), 0.0)
	if energy <= 0.0:
		_mark_depleted()


func _mark_depleted() -> void:
	if not depletion_locked:
		depletion_triggered = true
		_feedback_breaks = mini(_feedback_breaks + 1, 65535)
	active = false
	depletion_locked = true
	perfect_guard_window_remaining = 0.0
	kinetic_vent_charge = 0.0
	kinetic_vent_release_pending = 0.0
