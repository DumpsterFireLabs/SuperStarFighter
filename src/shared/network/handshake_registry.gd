class_name HandshakeRegistry
extends RefCounted

var _deadlines: Dictionary = {}


func begin(peer_id: int, now_seconds: float) -> void:
	_deadlines[peer_id] = now_seconds + NetworkProtocol.HANDSHAKE_TIMEOUT_SECONDS


func has(peer_id: int) -> bool:
	return _deadlines.has(peer_id)


func complete(peer_id: int) -> bool:
	return _deadlines.erase(peer_id)


func expired(now_seconds: float) -> Array[int]:
	var result: Array[int] = []
	for peer_value in _deadlines.keys():
		var peer_id := int(peer_value)
		if now_seconds >= float(_deadlines[peer_id]):
			result.append(peer_id)
	result.sort()
	return result


func clear() -> void:
	_deadlines.clear()
