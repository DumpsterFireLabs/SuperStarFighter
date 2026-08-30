class_name AuthenticationAttemptLimiter
extends RefCounted

var maximum_failures: int
var window_seconds: float
var cooldown_seconds: float
var _states: Dictionary = {}


func _init(
	maximum: int = NetworkProtocol.AUTH_FAILURE_LIMIT,
	window: float = NetworkProtocol.AUTH_FAILURE_WINDOW_SECONDS,
	cooldown: float = NetworkProtocol.AUTH_COOLDOWN_SECONDS
) -> void:
	maximum_failures = maxi(maximum, 1)
	window_seconds = maxf(window, 1.0)
	cooldown_seconds = maxf(cooldown, 1.0)


func is_blocked(source: String, now_seconds: float) -> bool:
	var normalized := _normalize_source(source)
	if not _states.has(normalized):
		return false
	var state: Dictionary = _states[normalized]
	var blocked_until := float(state.get("blocked_until", 0.0))
	if blocked_until > now_seconds:
		return true
	if now_seconds - float(state.get("window_start", now_seconds)) >= window_seconds:
		_states.erase(normalized)
	return false


func register_failure(source: String, now_seconds: float) -> bool:
	_prune(now_seconds)
	var normalized := _normalize_source(source)
	if not _states.has(normalized) and _states.size() >= NetworkProtocol.AUTH_MAX_TRACKED_SOURCES:
		_remove_oldest_state()
	var state: Dictionary = _states.get(normalized, {
		"window_start": now_seconds,
		"failures": 0,
		"blocked_until": 0.0,
	})
	if now_seconds - float(state.window_start) >= window_seconds:
		state.window_start = now_seconds
		state.failures = 0
		state.blocked_until = 0.0
	state.failures = int(state.failures) + 1
	if int(state.failures) >= maximum_failures:
		state.blocked_until = now_seconds + cooldown_seconds
	_states[normalized] = state
	return float(state.blocked_until) > now_seconds


func clear() -> void:
	_states.clear()


func _prune(now_seconds: float) -> void:
	for source in _states.keys():
		var state := _states[source] as Dictionary
		if now_seconds >= float(state.get("blocked_until", 0.0)) and now_seconds - float(state.get("window_start", now_seconds)) >= window_seconds:
			_states.erase(source)


func _remove_oldest_state() -> void:
	var oldest_source: Variant = null
	var oldest_start := INF
	for source in _states.keys():
		var window_start := float((_states[source] as Dictionary).get("window_start", 0.0))
		if window_start < oldest_start:
			oldest_start = window_start
			oldest_source = source
	if oldest_source != null:
		_states.erase(oldest_source)


static func _normalize_source(source: String) -> String:
	var normalized := source.strip_edges().to_lower()
	return normalized if not normalized.is_empty() else "unknown"
