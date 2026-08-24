class_name RemoteInterpolator
extends RefCounted

const INTERPOLATION_DELAY_SECONDS: float = 0.1
const MAX_EXTRAPOLATION_SECONDS: float = 0.1
const MAX_SAMPLES_PER_PEER: int = 32

var _samples: Dictionary = {}


func add_sample(peer_id: int, receive_time: float, state: Dictionary) -> void:
	var peer_samples: Array = _samples.get(peer_id, [])
	peer_samples.append({"time": receive_time, "state": state.duplicate(true)})
	while peer_samples.size() > MAX_SAMPLES_PER_PEER:
		peer_samples.pop_front()
	_samples[peer_id] = peer_samples


func sample(peer_id: int, now_seconds: float) -> Dictionary:
	var peer_samples: Array = _samples.get(peer_id, [])
	if peer_samples.is_empty():
		return {"ok": false}
	var render_time := now_seconds - INTERPOLATION_DELAY_SECONDS
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
	if before != after and float(after.time) > float(before.time):
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
