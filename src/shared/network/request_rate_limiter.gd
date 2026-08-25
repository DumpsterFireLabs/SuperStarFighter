class_name RequestRateLimiter
extends RefCounted

enum Decision {
	ACCEPT,
	DROP,
	DISCONNECT,
}

var maximum_per_second: int
var strike_windows_before_disconnect: int
var _states: Dictionary = {}


func _init(maximum: int = NetworkProtocol.MAX_CONTROL_REQUESTS_PER_SECOND, strike_windows: int = NetworkProtocol.TRAFFIC_STRIKES_BEFORE_DISCONNECT) -> void:
	maximum_per_second = maxi(maximum, 1)
	strike_windows_before_disconnect = maxi(strike_windows, 1)


func register(peer_id: int, now_seconds: float) -> Decision:
	var state: Dictionary = _states.get(peer_id, {
		"window_start": now_seconds,
		"count": 0,
		"strike_windows": 0,
		"window_struck": false,
	})
	if now_seconds - float(state.window_start) >= 1.0:
		if not bool(state.window_struck):
			state.strike_windows = maxi(int(state.strike_windows) - 1, 0)
		state.window_start = now_seconds
		state.count = 0
		state.window_struck = false
	state.count = int(state.count) + 1
	if int(state.count) > maximum_per_second:
		if not bool(state.window_struck):
			state.window_struck = true
			state.strike_windows = int(state.strike_windows) + 1
		_states[peer_id] = state
		if int(state.strike_windows) >= strike_windows_before_disconnect:
			return Decision.DISCONNECT
		return Decision.DROP
	_states[peer_id] = state
	return Decision.ACCEPT


func remove_peer(peer_id: int) -> void:
	_states.erase(peer_id)


func clear() -> void:
	_states.clear()
