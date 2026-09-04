class_name ObjectiveStepResult
extends RefCounted

# A handler reports a winner; only the coordinator may end the heat.
var winner_peer_id: int = 0
var winner_team_id: int = 0
var transitions: Array[ObjectiveTransition] = []


func transition(action: StringName, state: ObjectiveState) -> void:
	transitions.append(ObjectiveTransition.new(action, state))
