class_name MatchObservations
extends RefCounted

# Bounded, server-local observations. No input, position, or private build data is
# sent to opponents. A new coordinator starts a fresh observation lifetime.
const MAX_HEATS: int = 128
var heats: Array[Dictionary] = []
var contributions: Dictionary = {}
var draft_byes: Dictionary = {}
var permanent_pickups: Dictionary = {}
var all_pickups: Dictionary = {}
var _heat: Dictionary = {}
var _dead_since: Dictionary = {}
var _contact_serial: int = 0
var _draft_started: int = -1
var _draft_seconds: float = 0.0
var _previous_heat_end: int = -1
var _previous_round_end: int = -1


func add_contribution(peer_id: int, key: String, amount: float = 1.0) -> void:
	if peer_id == 0:
		return
	if not contributions.has(peer_id):
		contributions[peer_id] = {"hill_control_seconds": 0.0, "hill_contest_seconds": 0.0,
			"flag_carry_seconds": 0.0, "flag_pickups": 0, "flag_captures": 0, "carrier_stops": 0}
	if key.ends_with("seconds"):
		contributions[peer_id][key] = float(contributions[peer_id].get(key, 0.0)) + maxf(amount, 0.0)
	else:
		contributions[peer_id][key] = int(contributions[peer_id].get(key, 0)) + int(amount)


func record_bye(peer_id: int) -> void:
	draft_byes[peer_id] = int(draft_byes.get(peer_id, 0)) + 1


func record_pickup(peer_id: int, permanent: bool) -> void:
	all_pickups[peer_id] = int(all_pickups.get(peer_id, 0)) + 1
	if permanent:
		permanent_pickups[peer_id] = int(permanent_pickups.get(peer_id, 0)) + 1


func enter_state(state: int, tick: int, machine: MatchStateMachine, world: AuthoritativeWorld, map_id: StringName) -> void:
	if state == MatchStateMachine.State.DRAFT:
		_draft_started = tick
	elif state == MatchStateMachine.State.COUNTDOWN and _draft_started >= 0:
		_draft_seconds = _seconds(tick - _draft_started)
		_draft_started = -1
	elif state == MatchStateMachine.State.ACTIVE_HEAT:
		_contact_serial = world.combat_contact_serial
		_dead_since.clear()
		var builds: Dictionary = {}
		var eliminated: Dictionary = {}
		for peer_id in machine.participant_ids():
			builds[peer_id] = (machine.players[peer_id] as PlayerMatchState).effective_card_stacks().duplicate()
			eliminated[peer_id] = 0.0
		_heat = {"round": machine.round_number, "heat": machine.heat_number,
			"mode": GameModeRules.mode_name(machine.config.game_mode), "map": String(map_id),
			"players": builds.size(), "start_tick": tick, "first_contact_seconds": null,
			"draft_seconds": _draft_seconds if machine.heat_number == 1 else 0.0,
			"turnaround_seconds": _seconds(tick - _previous_heat_end) if _previous_heat_end >= 0 else null,
			"round_turnaround_seconds": _seconds(tick - _previous_round_end) if _previous_round_end >= 0 and machine.heat_number == 1 else null,
			"eliminated_seconds": eliminated, "starting_builds": builds,
			"draft_byes": draft_byes.duplicate(), "permanent_pickups_at_start": permanent_pickups.duplicate(),
			"pickups_at_start": all_pickups.duplicate()}
	elif state == MatchStateMachine.State.HEAT_RESULT and not _heat.is_empty():
		observe(tick, machine, world)
		for peer_id in _dead_since:
			_heat.eliminated_seconds[peer_id] += _seconds(tick - int(_dead_since[peer_id]))
		_heat["duration_seconds"] = _seconds(tick - int(_heat.start_tick))
		_heat["winner"] = machine.last_heat_winner
		_heat["winner_team"] = machine.last_heat_winner_team
		_heat["permanent_pickups_at_end"] = permanent_pickups.duplicate()
		_heat["pickups_at_end"] = all_pickups.duplicate()
		var ending_builds: Dictionary = {}
		for peer_id in _heat.starting_builds:
			if machine.players.has(peer_id):
				ending_builds[peer_id] = (machine.players[peer_id] as PlayerMatchState).effective_card_stacks().duplicate()
		_heat["ending_builds"] = ending_builds
		if heats.size() == MAX_HEATS:
			heats.pop_front()
		heats.append(_heat)
		_heat = {}
		_dead_since.clear()
		_previous_heat_end = tick
	elif state == MatchStateMachine.State.ROUND_RESULT:
		_previous_round_end = _previous_heat_end if _previous_heat_end >= 0 else tick


func observe(tick: int, machine: MatchStateMachine, world: AuthoritativeWorld) -> void:
	if _heat.is_empty():
		return
	if _heat.first_contact_seconds == null and world.combat_contact_serial != _contact_serial:
		_heat.first_contact_seconds = _seconds(tick - int(_heat.start_tick))
	for peer_id in _heat.eliminated_seconds:
		var combatant := world.combatants.get(peer_id) as CombatantState
		var player := machine.players.get(peer_id) as PlayerMatchState
		var dead := combatant == null or not combatant.alive or player == null or not player.connected
		if dead and not _dead_since.has(peer_id):
			_dead_since[peer_id] = tick
		elif not dead and _dead_since.has(peer_id):
			_heat.eliminated_seconds[peer_id] += _seconds(tick - int(_dead_since[peer_id]))
			_dead_since.erase(peer_id)


static func _seconds(ticks: int) -> float:
	return maxf(float(ticks) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0)


static func log_rows(heat: Dictionary) -> Array[Dictionary]:
	# One scalar summary plus at most 32 participant rows respects the existing
	# logger's depth/collection bounds. Large builds explicitly disclose truncation.
	var rows: Array[Dictionary] = []
	var summary := heat.duplicate()
	for key in heat:
		if heat[key] is Dictionary:
			summary.erase(key)
	rows.append(summary)
	var builds := heat.get("starting_builds", {}) as Dictionary
	for peer_id in builds:
		var starting: Dictionary = builds[peer_id]
		var ending: Dictionary = heat.get("ending_builds", {}).get(peer_id, {})
		rows.append({"round": heat.round, "heat": heat.heat, "peer_id": peer_id,
			"eliminated_seconds": heat.eliminated_seconds.get(peer_id, 0.0),
			"draft_byes": heat.draft_byes.get(peer_id, 0),
			"pickups_before": heat.pickups_at_start.get(peer_id, 0),
			"pickups_after": heat.pickups_at_end.get(peer_id, 0),
			"permanent_pickups_before": heat.permanent_pickups_at_start.get(peer_id, 0),
			"permanent_pickups_after": heat.permanent_pickups_at_end.get(peer_id, 0),
			"starting_build": starting, "ending_build": ending,
			"build_log_truncated": maxi(starting.size(), ending.size()) > NetworkProtocol.MAX_LOG_COLLECTION_LENGTH})
	return rows
