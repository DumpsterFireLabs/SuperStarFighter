class_name InputRateLimiter
extends RefCounted

enum Decision {
	ACCEPT,
	DROP,
	DISCONNECT,
}

var _states: Dictionary = {}


func register(peer_id: int, now_seconds: float, packet_valid: bool = true) -> Decision:
	var state: Dictionary = _states.get(peer_id, {
		"window_start": now_seconds,
		"count": 0,
		"strike_windows": 0,
		"window_struck": false,
		"malformed_strikes": 0,
	})
	if now_seconds - float(state.window_start) >= 1.0:
		if not bool(state.window_struck):
			state.strike_windows = maxi(int(state.strike_windows) - 1, 0)
		state.window_start = now_seconds
		state.count = 0
		state.window_struck = false
	if not packet_valid:
		state.malformed_strikes = int(state.malformed_strikes) + 1
		_states[peer_id] = state
		if int(state.malformed_strikes) >= NetworkProtocol.TRAFFIC_STRIKES_BEFORE_DISCONNECT:
			return Decision.DISCONNECT
		return Decision.DROP
	state.count = int(state.count) + 1
	if int(state.count) > NetworkProtocol.MAX_INPUTS_PER_SECOND:
		if not bool(state.window_struck):
			state.window_struck = true
			state.strike_windows = int(state.strike_windows) + 1
		_states[peer_id] = state
		if int(state.strike_windows) >= NetworkProtocol.TRAFFIC_STRIKES_BEFORE_DISCONNECT:
			return Decision.DISCONNECT
		return Decision.DROP
	state.malformed_strikes = maxi(int(state.malformed_strikes) - 1, 0)
	_states[peer_id] = state
	return Decision.ACCEPT


func remove_peer(peer_id: int) -> void:
	_states.erase(peer_id)
