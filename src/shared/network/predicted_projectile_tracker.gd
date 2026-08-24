class_name PredictedProjectileTracker
extends RefCounted

const REJECT_FADE_SECONDS: float = 0.1

var _predicted: Dictionary = {}


func add(owner_id: int, shot_sequence: int, created_at: float) -> void:
	_predicted[_key(owner_id, shot_sequence)] = {
		"created_at": created_at,
		"rejected_at": -1.0,
	}


func reconcile(owner_id: int, shot_sequence: int) -> bool:
	return _predicted.erase(_key(owner_id, shot_sequence))


func reject(owner_id: int, shot_sequence: int, now_seconds: float) -> bool:
	var key := _key(owner_id, shot_sequence)
	if not _predicted.has(key):
		return false
	_predicted[key].rejected_at = now_seconds
	return true


func step(now_seconds: float) -> Array[String]:
	var removed: Array[String] = []
	for key_value in _predicted.keys():
		var key := String(key_value)
		var item := _predicted[key] as Dictionary
		if float(item.rejected_at) >= 0.0 and now_seconds - float(item.rejected_at) >= REJECT_FADE_SECONDS:
			_predicted.erase(key)
			removed.append(key)
	return removed


func size() -> int:
	return _predicted.size()


static func _key(owner_id: int, shot_sequence: int) -> String:
	return "%d:%d" % [owner_id, shot_sequence]
