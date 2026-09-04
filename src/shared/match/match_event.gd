class_name MatchEvent
extends RefCounted

var event_type: StringName
var server_tick: int
var _payload: Dictionary = {}
var _objective: ObjectiveState
var _action: StringName


func _init(type_value: StringName, tick: int, payload: Dictionary = {}) -> void:
	event_type = type_value
	server_tick = tick
	_payload = payload.duplicate(true)


static func objective_event(tick: int, state: ObjectiveState, action: StringName = &"") -> MatchEvent:
	var result := MatchEvent.new(&"OBJECTIVE_UPDATED" if action.is_empty() else &"OBJECTIVE_TRANSITION", tick)
	result._objective = state.snapshot()
	result._action = action
	return result


func to_dictionary() -> Dictionary:
	var payload := _payload.duplicate(true)
	if _objective != null:
		if not _action.is_empty():
			payload["action"] = _action
		payload["objective"] = _objective.to_dictionary()
	return {"event_type": event_type, "server_tick": server_tick, "payload": payload}
