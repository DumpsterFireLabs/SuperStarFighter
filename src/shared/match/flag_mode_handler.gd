class_name FlagModeHandler
extends RefCounted

var state := ObjectiveState.new()
var dropped_seconds: float = 0.0
var teams: Dictionary[int, int] = {}


func reset(position: Vector2) -> void:
	state.position = position
	state.flag_position = position
	state.flag_carrier_id = 0
	dropped_seconds = 0.0


func configure(mode: int, map_id: StringName, team_count: int, participants: Array[int], assignments: Dictionary, spawn_assignments: Dictionary) -> void:
	state.mode = mode
	teams.assign(assignments)
	state.capture_zones.clear()
	if not GameModeRules.uses_flag(mode):
		return
	if GameModeRules.is_team_mode(mode):
		for team_id in range(1, GameModeRules.team_count_for_mode(mode, team_count) + 1):
			state.capture_zones[team_id] = GameModeRules.capture_zone(mode, team_id, map_id)
	else:
		for peer_id in participants:
			state.capture_zones[peer_id] = spawn_assignments.get(peer_id, GameModeRules.capture_zone(mode, peer_id, map_id))


func step(delta: float, world: AuthoritativeWorld, alive_ids: Array[int], observations: MatchObservations) -> ObjectiveStepResult:
	var result := ObjectiveStepResult.new()
	if state.flag_carrier_id != 0:
		var carrier := world.combatants.get(state.flag_carrier_id) as CombatantState
		if carrier == null or not carrier.alive:
			if carrier != null:
				state.flag_position = carrier.position
			state.flag_carrier_id = 0
			dropped_seconds = 0.0
			result.transition(&"FLAG_DROPPED", state)
		else:
			observations.add_contribution(state.flag_carrier_id, "flag_carry_seconds", delta)
			carrier.cloak_remaining = 0.0
			state.flag_position = carrier.position
			var carrier_team: int = teams.get(state.flag_carrier_id, 0)
			var capture_zone_id := carrier_team if GameModeRules.is_team_mode(state.mode) else state.flag_carrier_id
			var capture_position: Vector2 = state.capture_zones.get(capture_zone_id, Vector2.ZERO)
			if carrier.position.distance_to(capture_position) <= GameModeRules.OBJECTIVE_ZONE_RADIUS:
				observations.add_contribution(state.flag_carrier_id, "flag_captures")
				if GameModeRules.is_team_mode(state.mode):
					result.winner_team_id = carrier_team
				else:
					result.winner_peer_id = state.flag_carrier_id
				return result
	if state.flag_carrier_id == 0:
		var pickup_id := 0
		var nearest_distance := INF
		for peer_id in alive_ids:
			var combatant := world.combatants.get(peer_id) as CombatantState
			if combatant == null:
				continue
			var distance := combatant.position.distance_to(state.flag_position)
			if distance <= GameModeRules.FLAG_PICKUP_RADIUS and distance < nearest_distance:
				pickup_id = peer_id
				nearest_distance = distance
		if pickup_id != 0:
			state.flag_carrier_id = pickup_id
			observations.add_contribution(pickup_id, "flag_pickups")
			(world.combatants[pickup_id] as CombatantState).cloak_remaining = 0.0
			state.flag_position = (world.combatants[pickup_id] as CombatantState).position
			dropped_seconds = 0.0
			result.transition(&"FLAG_PICKED_UP", state)
		else:
			dropped_seconds += maxf(delta, 0.0)
			if state.flag_position != state.position and dropped_seconds >= GameModeRules.FLAG_RESET_SECONDS:
				state.flag_position = state.position
				dropped_seconds = 0.0
				result.transition(&"FLAG_RESET", state)
	return result
