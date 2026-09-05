class_name HandshakeRegistry
extends RefCounted

var _records: Dictionary = {}


func begin(peer_id: int, now_seconds: float, challenge: String = "") -> void:
	_records[peer_id] = {
		"deadline": now_seconds + NetworkProtocol.HANDSHAKE_TIMEOUT_SECONDS,
		"challenge": challenge,
	}


func has(peer_id: int) -> bool:
	return _records.has(peer_id)


func challenge_for(peer_id: int) -> String:
	var record := _records.get(peer_id, {}) as Dictionary
	return String(record.get("challenge", ""))


func complete(peer_id: int) -> bool:
	return _records.erase(peer_id)


func queued_peers() -> Array[int]:
	var result: Array[int] = []
	for peer_id in _records:
		if challenge_for(peer_id).is_empty(): result.append(peer_id)
	return result


func start_challenge(peer_id: int, challenge: String, now_seconds: float) -> bool:
	if not _records.has(peer_id) or not challenge_for(peer_id).is_empty(): return false
	if now_seconds >= float(_records[peer_id].deadline): return false
	_records[peer_id].challenge = challenge
	return true


func expired(now_seconds: float) -> Array[int]:
	var result: Array[int] = []
	for peer_value in _records.keys():
		var peer_id := int(peer_value)
		var record := _records[peer_id] as Dictionary
		if now_seconds >= float(record.get("deadline", 0.0)):
			result.append(peer_id)
	result.sort()
	return result


func clear() -> void:
	_records.clear()


func size() -> int:
	return _records.size()
