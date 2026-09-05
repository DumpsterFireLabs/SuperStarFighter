class_name RemoteInterpolator
extends RefCounted

const INTERPOLATION_DELAY_SECONDS: float = 0.1
const MAX_EXTRAPOLATION_SECONDS: float = 0.1
const MAX_SAMPLES_PER_PEER: int = 32

var _samples: Dictionary = {}
var _clock_offset_seconds: float = 0.0
var _clock_initialized: bool = false
var _last_clock_server_tick: int = -1


func add_sample(peer_id: int, receive_time: float, server_tick: int, state: Dictionary) -> void:
	var server_time := float(server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND
	_update_clock_offset(receive_time, server_time, server_tick)
	var peer_samples: Array = _samples.get(peer_id, [])
	# Only motion participates in interpolation. Copy these value types rather
	# than retaining every resource/correction field from each snapshot.
	peer_samples.append({"time": server_time, "state": {
		"position": state.position, "velocity": state.velocity, "aim_angle": state.aim_angle,
	}})
	while peer_samples.size() > MAX_SAMPLES_PER_PEER:
		peer_samples.pop_front()
	_samples[peer_id] = peer_samples


func sample(peer_id: int, now_seconds: float) -> Dictionary:
	var peer_samples: Array = _samples.get(peer_id, [])
	if peer_samples.is_empty():
		return {"ok": false}
	var estimated_server_time := now_seconds - _clock_offset_seconds if _clock_initialized else now_seconds
	var render_time := estimated_server_time - INTERPOLATION_DELAY_SECONDS
	var before: Dictionary = peer_samples[0]
	var after: Dictionary = peer_samples[peer_samples.size() - 1]
	for item_value in peer_samples:
		var item := item_value as Dictionary
		if float(item.time) <= render_time:
			before = item
		if float(item.time) >= render_time:
			after = item
			break
	var before_state := before.state as Dictionary
	var after_state := after.state as Dictionary
	if float(after.time) > float(before.time):
		var weight := clampf(
			(render_time - float(before.time)) / (float(after.time) - float(before.time)),
			0.0,
			1.0
		)
		return {
			"ok": true,
			"position": (before_state.position as Vector2).lerp(after_state.position as Vector2, weight),
			"velocity": (before_state.velocity as Vector2).lerp(after_state.velocity as Vector2, weight),
			"aim_angle": lerp_angle(float(before_state.aim_angle), float(after_state.aim_angle), weight),
			"extrapolated": false,
		}
	var latest := peer_samples[peer_samples.size() - 1] as Dictionary
	var latest_state := latest.state as Dictionary
	var extrapolation := clampf(render_time - float(latest.time), 0.0, MAX_EXTRAPOLATION_SECONDS)
	return {
		"ok": true,
		"position": (latest_state.position as Vector2) + (latest_state.velocity as Vector2) * extrapolation,
		"velocity": latest_state.velocity,
		"aim_angle": latest_state.aim_angle,
		"extrapolated": extrapolation > 0.0,
	}


func remove_peer(peer_id: int) -> void:
	_samples.erase(peer_id)


func clear() -> void:
	_samples.clear()
	_clock_offset_seconds = 0.0
	_clock_initialized = false
	_last_clock_server_tick = -1


func _update_clock_offset(receive_time: float, server_time: float, server_tick: int) -> void:
	if server_tick == _last_clock_server_tick:
		return
	_last_clock_server_tick = server_tick
	var observed_offset := receive_time - server_time
	if not _clock_initialized or observed_offset < _clock_offset_seconds:
		_clock_offset_seconds = observed_offset
		_clock_initialized = true
		return
	# Arrival spikes are queueing/jitter, not clock movement. Increase the
	# baseline slowly, while accepting a new lower-latency baseline immediately.
	_clock_offset_seconds = lerpf(_clock_offset_seconds, observed_offset, 0.02)
