extends RefCounted

## One detached, read-only observation shared by world presentation and screens.
## Copies occur on network changes, never while rendering a frame or a UI row.
signal changed
var _payload: Dictionary = {}
var payload: Dictionary:
	get: return _payload
var _objective_tick: int = -1
var _objective_priority: int = 0


func _init() -> void:
	_payload.make_read_only()


func reset() -> void:
	_objective_tick = -1
	_objective_priority = 0
	_publish({})


func replace(value: Dictionary, server_tick: int = -1) -> void:
	var next := value.duplicate(true)
	if server_tick >= 0 and not _accept_objective_version(server_tick, 2):
		next["objective"] = payload.get("objective", {})
	_publish(next)


func update_fields(fields: Dictionary) -> void:
	# Existing subtrees are detached and recursively read-only. Only replacements
	# need copying/freezing; publishing a small field must not traverse all builds.
	var next := payload.duplicate()
	var detached := fields.duplicate(true)
	_freeze(detached)
	next.merge(detached, true)
	next.make_read_only()
	_payload = next
	changed.emit()


func apply_objective(objective: Dictionary, server_tick: int = -1, periodic: bool = false) -> bool:
	if server_tick >= 0 and not _accept_objective_version(server_tick, 1 if periodic else 0):
		return false
	update_fields({"objective": objective})
	return true


func _accept_objective_version(server_tick: int, priority: int) -> bool:
	if _objective_tick >= 0:
		if server_tick != _objective_tick and not SequenceMath.is_newer(server_tick, _objective_tick):
			return false
		if server_tick == _objective_tick and priority < _objective_priority:
			return false
	_objective_tick = server_tick
	_objective_priority = priority
	return true


func _publish(next: Dictionary) -> void:
	_freeze(next)
	_payload = next
	changed.emit()


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value:
			_freeze(item)
		value.make_read_only()
