class_name ObjectiveTransition
extends RefCounted

var action: StringName
var objective: ObjectiveState


func _init(action_value: StringName, state: ObjectiveState) -> void:
	action = action_value
	# Capture intermediate state: drop and pickup may both occur in one tick.
	objective = state.snapshot()
