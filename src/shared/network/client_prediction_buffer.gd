class_name ClientPredictionBuffer
extends RefCounted

const MAX_BUFFERED_INPUTS: int = 240
const SMOOTHING_THRESHOLD_PIXELS: float = 128.0
const SMOOTHING_DURATION_SECONDS: float = 0.1

var buffered_inputs: Array[Dictionary] = []
var predicted_position: Vector2 = Vector2.ZERO
var predicted_velocity: Vector2 = Vector2.ZERO
var smoothing_offset: Vector2 = Vector2.ZERO
var smoothing_remaining: float = 0.0
var snap_count: int = 0
var last_reconciliation_error: float = 0.0
var simulated_combatant: CombatantState
var hidden_cover := 0
var last_actions: int = 0


func reset_to_snapshot(state: Dictionary, stats: CombatStats) -> void:
	buffered_inputs.clear()
	smoothing_offset = Vector2.ZERO
	smoothing_remaining = 0.0
	simulated_combatant = CombatantState.new()
	simulated_combatant.restore_prediction_state(state, stats)
	predicted_position = simulated_combatant.position
	predicted_velocity = simulated_combatant.velocity
	last_actions = 0


func push(frame: PlayerInputFrame, delta: float) -> void:
	buffered_inputs.append({"frame": frame, "delta": maxf(delta, 0.0)})
	while buffered_inputs.size() > MAX_BUFFERED_INPUTS:
		buffered_inputs.pop_front()


func predict(
	frame: PlayerInputFrame,
	stats: CombatStats,
	delta: float,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID,
	breakaway_active: bool = false
) -> void:
	_ensure_simulation(stats, breakaway_active)
	simulated_combatant.position = predicted_position
	simulated_combatant.velocity = predicted_velocity
	last_actions = _step_simulation(frame, stats, delta, map_id)
	predicted_position = simulated_combatant.position
	predicted_velocity = simulated_combatant.velocity
	push(frame, delta)


func reconcile(
	authoritative_position: Vector2,
	authoritative_velocity: Vector2,
	acknowledged_sequence: int,
	stats: CombatStats,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID,
	breakaway_active: bool = false,
	authoritative_state: Dictionary = {}
) -> Dictionary:
	var previous_prediction := predicted_position
	var previous_visual := predicted_position + smoothing_offset
	_prune_acknowledged(acknowledged_sequence)
	_ensure_simulation(stats, breakaway_active)
	if not authoritative_state.is_empty():
		simulated_combatant.restore_prediction_state(authoritative_state, stats)
	simulated_combatant.position = authoritative_position
	simulated_combatant.velocity = authoritative_velocity
	# Authority continues stepping a held sample while its acknowledgement is
	# unchanged. Those elapsed ticks are already in this snapshot. Keep their
	# frames pending for acknowledgement, but do not simulate that time twice.
	# The first input-age tick is the acknowledged frame itself, already pruned.
	var covered_seconds := maxf(int(authoritative_state.get("input_age_ticks", 0)) - 1, 0) / GameConstants.PHYSICS_TICKS_PER_SECOND
	for item in buffered_inputs:
		var frame := item.frame as PlayerInputFrame
		var delta := float(item.delta)
		var covered := minf(covered_seconds, delta)
		covered_seconds -= covered
		delta -= covered
		if delta <= 0.000001: continue
		_step_simulation(frame, stats, delta, map_id)
	last_reconciliation_error = previous_prediction.distance_to(simulated_combatant.position)
	predicted_position = simulated_combatant.position
	predicted_velocity = simulated_combatant.velocity
	var snapped := last_reconciliation_error > SMOOTHING_THRESHOLD_PIXELS
	if snapped:
		smoothing_offset = Vector2.ZERO
		smoothing_remaining = 0.0
		snap_count += 1
	else:
		# Preserve the displayed position when another correction arrives before
		# smoothing completes. Dropping the remaining offset creates a new jump.
		smoothing_offset = previous_visual - predicted_position
		smoothing_remaining = SMOOTHING_DURATION_SECONDS
	return {
		"snapped": snapped,
		"error": last_reconciliation_error,
		"position": predicted_position,
		"velocity": predicted_velocity,
	}


func visual_position(delta: float) -> Vector2:
	if smoothing_remaining <= 0.0:
		return predicted_position
	var previous_remaining := smoothing_remaining
	smoothing_remaining = maxf(smoothing_remaining - maxf(delta, 0.0), 0.0)
	var factor := smoothing_remaining / previous_remaining if previous_remaining > 0.0 else 0.0
	smoothing_offset *= factor
	return predicted_position + smoothing_offset


func _ensure_simulation(stats: CombatStats, breakaway_active: bool) -> void:
	if simulated_combatant == null:
		simulated_combatant = CombatantState.create(0, stats, predicted_position)
		simulated_combatant.velocity = predicted_velocity
		if breakaway_active:
			simulated_combatant.breakaway_remaining = GameConstants.BREAKAWAY_DURATION_SECONDS


func _step_simulation(
	frame: PlayerInputFrame,
	stats: CombatStats,
	delta: float,
	map_id: StringName
) -> int:
	simulated_combatant.stats = stats
	var actions := ArenaMovementSystem.step_input(simulated_combatant, frame, delta, map_id)
	var motion := ArenaCollisionSystem.move_ship(
		simulated_combatant.position, simulated_combatant.velocity, delta, map_id, hidden_cover
	)
	simulated_combatant.position = motion.position
	simulated_combatant.velocity = motion.velocity
	return actions


func _prune_acknowledged(acknowledged_sequence: int) -> void:
	var pending: Array[Dictionary] = []
	for item in buffered_inputs:
		var frame := item.frame as PlayerInputFrame
		if SequenceMath.is_newer(frame.sequence, acknowledged_sequence):
			pending.append(item)
	buffered_inputs = pending
