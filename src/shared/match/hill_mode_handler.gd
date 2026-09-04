class_name HillModeHandler
extends RefCounted

var state := ObjectiveState.new()


func _init() -> void:
	state.mode = GameModeRules.Mode.KING_OF_THE_HILL


func reset(position: Vector2, participant_ids: Array[int]) -> void:
	state.position = position
	state.controller_id = 0
	state.contested = false
	state.progress.clear()
	for peer_id in participant_ids:
		state.progress[peer_id] = 0.0


func step(delta: float, world: AuthoritativeWorld, alive_ids: Array[int], observations: MatchObservations) -> ObjectiveStepResult:
	var result := ObjectiveStepResult.new()
	var occupants: Array[int] = []
	for peer_id in alive_ids:
		var combatant := world.combatants.get(peer_id) as CombatantState
		if combatant != null and combatant.position.distance_to(state.position) <= GameModeRules.OBJECTIVE_ZONE_RADIUS:
			combatant.cloak_remaining = 0.0
			occupants.append(peer_id)
	state.contested = occupants.size() > 1
	if state.contested:
		for peer_id in occupants:
			observations.add_contribution(peer_id, "hill_contest_seconds", delta)
	if occupants.size() != 1:
		if state.controller_id != 0:
			state.controller_id = 0
			result.transition(&"HILL_CONTROL_LOST", state)
		return result
	var controller_id := occupants[0]
	observations.add_contribution(controller_id, "hill_control_seconds", delta)
	if controller_id != state.controller_id:
		state.controller_id = controller_id
		if not state.progress.has(controller_id):
			state.progress[controller_id] = 0.0
		result.transition(&"HILL_CONTROLLER_CHANGED", state)
	state.progress[controller_id] = state.progress.get(controller_id, 0.0) + maxf(delta, 0.0)
	if state.progress[controller_id] >= GameModeRules.HILL_HOLD_SECONDS:
		result.winner_peer_id = controller_id
	return result
