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


func push(frame: PlayerInputFrame, delta: float) -> void:
	buffered_inputs.append({"frame": frame, "delta": maxf(delta, 0.0)})
	while buffered_inputs.size() > MAX_BUFFERED_INPUTS:
		buffered_inputs.pop_front()


func predict(frame: PlayerInputFrame, stats: CombatStats, delta: float) -> void:
	var world_movement := MovementSystem.ship_relative_to_world(frame.movement, frame.aim_angle)
	predicted_velocity = MovementSystem.step_velocity(
		predicted_velocity,
		world_movement,
		stats,
		delta,
		frame.shielding
	)
	predicted_position += predicted_velocity * maxf(delta, 0.0)
	push(frame, delta)


func reconcile(
	authoritative_position: Vector2,
	authoritative_velocity: Vector2,
	acknowledged_sequence: int,
	stats: CombatStats
) -> Dictionary:
	var previous_prediction := predicted_position
	_prune_acknowledged(acknowledged_sequence)
	var replay_position := authoritative_position
	var replay_velocity := authoritative_velocity
	for item in buffered_inputs:
		var frame := item.frame as PlayerInputFrame
		var delta := float(item.delta)
		var world_movement := MovementSystem.ship_relative_to_world(frame.movement, frame.aim_angle)
		replay_velocity = MovementSystem.step_velocity(
			replay_velocity,
			world_movement,
			stats,
			delta,
			frame.shielding
		)
		replay_position += replay_velocity * delta
	last_reconciliation_error = previous_prediction.distance_to(replay_position)
	predicted_position = replay_position
	predicted_velocity = replay_velocity
	var snapped := last_reconciliation_error > SMOOTHING_THRESHOLD_PIXELS
	if snapped:
		smoothing_offset = Vector2.ZERO
		smoothing_remaining = 0.0
		snap_count += 1
	else:
		smoothing_offset = previous_prediction - replay_position
		smoothing_remaining = SMOOTHING_DURATION_SECONDS
	return {
		"snapped": snapped,
		"error": last_reconciliation_error,
		"position": replay_position,
		"velocity": replay_velocity,
	}


func visual_position(delta: float) -> Vector2:
	if smoothing_remaining <= 0.0:
		return predicted_position
	var previous_remaining := smoothing_remaining
	smoothing_remaining = maxf(smoothing_remaining - maxf(delta, 0.0), 0.0)
	var factor := smoothing_remaining / previous_remaining if previous_remaining > 0.0 else 0.0
	smoothing_offset *= factor
	return predicted_position + smoothing_offset


func _prune_acknowledged(acknowledged_sequence: int) -> void:
	var pending: Array[Dictionary] = []
	for item in buffered_inputs:
		var frame := item.frame as PlayerInputFrame
		if SequenceMath.is_newer(frame.sequence, acknowledged_sequence):
			pending.append(item)
	buffered_inputs = pending
