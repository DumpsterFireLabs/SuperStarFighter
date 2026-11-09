class_name ObjectiveTransition
extends RefCounted

## Objective transition actions, sent as the `action` of an
## OBJECTIVE_TRANSITION event payload.
const FLAG_DROPPED := &"FLAG_DROPPED"
const FLAG_PICKED_UP := &"FLAG_PICKED_UP"
const FLAG_RESET := &"FLAG_RESET"
const HILL_CONTROL_LOST := &"HILL_CONTROL_LOST"
const HILL_CONTROLLER_CHANGED := &"HILL_CONTROLLER_CHANGED"

var action: StringName
var objective: ObjectiveState


func _init(action_value: StringName, state: ObjectiveState) -> void:
	action = action_value
	# Capture intermediate state: drop and pickup may both occur in one tick.
	objective = state.snapshot()
