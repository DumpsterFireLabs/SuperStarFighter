class_name MatchStateMachine
extends RefCounted

enum State {
	LOBBY,
	DRAFT,
	COUNTDOWN,
	ACTIVE_HEAT,
	HEAT_RESULT,
	ROUND_RESULT,
	MATCH_RESULT,
}

var config: MatchConfig
var catalog: CardCatalog
var players: Dictionary = {}
var scores := MatchScoreState.new()
var team_scores := MatchScoreState.new()

var state: int = State.LOBBY
var state_entered_tick: int = 0
var state_deadline_tick: int = -1
var round_number: int = 0
var heat_number: int = 0
var last_heat_winner: int = 0
var last_round_winner: int = 0
var match_winner: int = 0
var last_heat_winner_team: int = 0
var last_round_winner_team: int = 0
var match_winner_team: int = 0
var team_heat_wins: Dictionary = {}
var team_round_wins: Dictionary = {}
var tied_heat: bool = false
var event_history: Array[Dictionary] = []

var _pending_round_winner: int = 0
var _pending_match_winner: int = 0
var _pending_round_winner_team: int = 0
var _pending_match_winner_team: int = 0


func _init(configuration: MatchConfig = null, card_catalog: CardCatalog = null) -> void:
	config = configuration.duplicate_config() if configuration != null else MatchConfig.new()
	catalog = card_catalog if card_catalog != null else CardCatalog.create_default()
	_ensure_team_score_entries()
	_refresh_team_score_views()


func add_player(peer_id: int, display_name: String, join_sequence: int) -> PlayerMatchState:
	if players.has(peer_id):
		return players[peer_id] as PlayerMatchState
	var player := PlayerMatchState.new(peer_id, display_name, join_sequence)
	player.participant = state == State.LOBBY
	player.spectator = true
	players[peer_id] = player
	player.score = scores.register_player(peer_id, player.score)
	return player


func start_match(at_tick: int) -> bool:
	if state != State.LOBBY or not config.validate().is_empty():
		return false
	var active_ids := participant_ids()
	if active_ids.size() < GameConstants.MIN_PLAYERS:
		return false
	for peer_id in active_ids:
		var player := players[peer_id] as PlayerMatchState
		player.reset_match()
		player.participant = true
	players = _sorted_player_dictionary(players)
	scores.reset_match()
	_ensure_team_score_entries()
	team_scores.reset_match()
	round_number = 1
	heat_number = 0
	last_heat_winner = 0
	last_round_winner = 0
	match_winner = 0
	last_heat_winner_team = 0
	last_round_winner_team = 0
	match_winner_team = 0
	_refresh_team_score_views()
	tied_heat = false
	_pending_round_winner = 0
	_pending_match_winner = 0
	_pending_round_winner_team = 0
	_pending_match_winner_team = 0
	event_history.clear()
	_transition(State.DRAFT, at_tick)
	return true


func draft_completed(at_tick: int) -> bool:
	if state != State.DRAFT:
		return false
	heat_number = 1
	_prepare_heat()
	_transition(State.COUNTDOWN, at_tick)
	return true


func is_draft_timed_out(at_tick: int) -> bool:
	return state == State.DRAFT and state_deadline_tick >= 0 and at_tick >= state_deadline_tick


func advance_time(at_tick: int) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	while state_deadline_tick >= 0 and at_tick >= state_deadline_tick:
		var transition_tick := state_deadline_tick
		match state:
			State.DRAFT:
				break
			State.COUNTDOWN:
				_transition(State.ACTIVE_HEAT, transition_tick)
			State.HEAT_RESULT:
				if _pending_match_winner != 0 or _pending_match_winner_team != 0:
					last_round_winner = _pending_round_winner
					last_round_winner_team = _pending_round_winner_team
					match_winner = _pending_match_winner
					match_winner_team = _pending_match_winner_team
					_transition(State.MATCH_RESULT, transition_tick)
				elif _pending_round_winner != 0 or _pending_round_winner_team != 0:
					last_round_winner = _pending_round_winner
					last_round_winner_team = _pending_round_winner_team
					_transition(State.ROUND_RESULT, transition_tick)
				else:
					heat_number += 1
					_prepare_heat()
					_transition(State.COUNTDOWN, transition_tick)
			State.ROUND_RESULT:
				round_number += 1
				heat_number = 0
				last_heat_winner = 0
				last_round_winner = 0
				last_heat_winner_team = 0
				last_round_winner_team = 0
				_pending_round_winner = 0
				_pending_round_winner_team = 0
				_transition(State.DRAFT, transition_tick)
			_:
				break
		transitions.append(event_history.back())
		if state == State.ACTIVE_HEAT or state == State.DRAFT or state == State.LOBBY:
			break
	return transitions


func finish_heat(winner_peer_id: int, at_tick: int) -> bool:
	if state != State.ACTIVE_HEAT:
		return false
	if winner_peer_id != 0:
		var winner := players.get(winner_peer_id) as PlayerMatchState
		if winner == null or not winner.connected or not winner.participant or not winner.alive:
			return false
	for player in players.values():
		var typed_player := player as PlayerMatchState
		if typed_player.participant and typed_player.peer_id != winner_peer_id:
			typed_player.eliminate()
	_resolve_heat(winner_peer_id, at_tick)
	return true


func finish_team_heat(winner_team_id: int, at_tick: int) -> bool:
	if state != State.ACTIVE_HEAT or not GameModeRules.is_team_mode(config.game_mode):
		return false
	if winner_team_id != 0 and not _team_has_living_participant(winner_team_id):
		return false
	for player in players.values():
		var typed_player := player as PlayerMatchState
		if typed_player.participant and typed_player.team_id != winner_team_id:
			typed_player.eliminate()
	_resolve_team_heat(winner_team_id, at_tick)
	return true


func eliminate_players(peer_ids: Array[int], at_tick: int) -> bool:
	if state != State.ACTIVE_HEAT:
		return false
	for peer_id in peer_ids:
		var player := players.get(peer_id) as PlayerMatchState
		if player != null and player.alive:
			player.eliminate()
	var survivors := alive_participant_ids()
	if config.game_mode == GameModeRules.Mode.DEATH_MATCH:
		if survivors.size() <= 1:
			_resolve_heat(survivors[0] if survivors.size() == 1 else 0, at_tick)
	elif config.game_mode == GameModeRules.Mode.TEAM_DEATH_MATCH:
		var living_teams := alive_team_ids()
		if living_teams.size() <= 1:
			_resolve_team_heat(living_teams[0] if living_teams.size() == 1 else 0, at_tick)
	elif survivors.is_empty():
		_resolve_heat(0, at_tick)
	return true


func disconnect_player(peer_id: int, at_tick: int) -> bool:
	var player := players.get(peer_id) as PlayerMatchState
	if player == null or not player.connected:
		return false
	player.connected = false
	player.participant = false
	player.eliminate()
	if state == State.LOBBY:
		players.erase(peer_id)
		scores.remove_player(peer_id)
		return true

	var remaining := participant_ids()
	if remaining.is_empty():
		_return_to_lobby(at_tick)
	elif GameModeRules.is_team_mode(config.game_mode) and _participant_team_ids().size() == 1:
		_award_team_forfeit(_participant_team_ids()[0], at_tick)
	elif remaining.size() == 1:
		_award_forfeit(remaining[0], at_tick)
	elif state == State.ACTIVE_HEAT:
		eliminate_players([], at_tick)
	return true


func participant_ids() -> Array[int]:
	var result: Array[int] = []
	for player in players.values():
		var typed_player := player as PlayerMatchState
		if typed_player.connected and typed_player.participant:
			result.append(typed_player.peer_id)
	result.sort()
	return result


func alive_participant_ids() -> Array[int]:
	var result: Array[int] = []
	for player in players.values():
		var typed_player := player as PlayerMatchState
		if typed_player.connected and typed_player.participant and typed_player.alive:
			result.append(typed_player.peer_id)
	result.sort()
	return result


func alive_team_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_id in alive_participant_ids():
		var team_id := (players[peer_id] as PlayerMatchState).team_id
		if team_id > 0 and team_id not in result:
			result.append(team_id)
	result.sort()
	return result


func state_name() -> String:
	return State.keys()[state]


func score_snapshot() -> Dictionary:
	var result := scores.snapshot()
	if not GameModeRules.is_team_mode(config.game_mode):
		return result
	for peer_id in participant_ids():
		var player := players[peer_id] as PlayerMatchState
		var team_score := team_scores.get_score(player.team_id)
		if team_score == null or not result.has(peer_id):
			continue
		var player_score := result[peer_id] as Dictionary
		player_score.heat_wins = team_score.heat_wins
		player_score.round_wins = team_score.round_wins
	return result


func return_to_lobby(at_tick: int) -> bool:
	if state != State.MATCH_RESULT:
		return false
	_return_to_lobby(at_tick)
	return true


func _resolve_heat(winner_peer_id: int, at_tick: int) -> void:
	last_heat_winner = winner_peer_id
	last_heat_winner_team = 0
	tied_heat = winner_peer_id == 0
	_pending_round_winner = 0
	_pending_match_winner = 0
	_pending_round_winner_team = 0
	_pending_match_winner_team = 0
	if winner_peer_id != 0:
		var result := scores.award_heat(winner_peer_id, config.rounds_to_win)
		_pending_round_winner = result.round_winner
		_pending_match_winner = result.match_winner
	_transition(State.HEAT_RESULT, at_tick)


func _resolve_team_heat(winner_team_id: int, at_tick: int) -> void:
	last_heat_winner_team = winner_team_id
	last_heat_winner = _team_representative(winner_team_id)
	tied_heat = winner_team_id == 0
	_pending_round_winner = 0
	_pending_match_winner = 0
	_pending_round_winner_team = 0
	_pending_match_winner_team = 0
	if winner_team_id != 0:
		var result := team_scores.award_heat(winner_team_id, config.rounds_to_win)
		_pending_round_winner_team = int(result.round_winner)
		_pending_match_winner_team = int(result.match_winner)
		if _pending_match_winner_team != 0:
			_pending_match_winner = _team_representative(_pending_match_winner_team)
		_pending_round_winner = _team_representative(_pending_round_winner_team)
	_refresh_team_score_views()
	_transition(State.HEAT_RESULT, at_tick)


func _prepare_heat() -> void:
	for player in players.values():
		var typed_player := player as PlayerMatchState
		if typed_player.connected and typed_player.participant:
			var stats := StatSystem.derive(typed_player.effective_card_stacks(), catalog)
			typed_player.reset_for_heat(stats)
		else:
			typed_player.eliminate()


func _award_forfeit(peer_id: int, at_tick: int) -> void:
	scores.award_forfeit(peer_id, config.rounds_to_win)
	match_winner = peer_id
	_pending_match_winner = peer_id
	_pending_round_winner = 0
	_transition(State.MATCH_RESULT, at_tick)


func _award_team_forfeit(team_id: int, at_tick: int) -> void:
	team_scores.award_forfeit(team_id, config.rounds_to_win)
	_refresh_team_score_views()
	match_winner_team = team_id
	match_winner = _team_representative(team_id)
	_pending_match_winner_team = team_id
	_pending_match_winner = match_winner
	_pending_round_winner = 0
	_pending_round_winner_team = 0
	_transition(State.MATCH_RESULT, at_tick)


func _return_to_lobby(at_tick: int) -> void:
	var disconnected_ids: Array[int] = []
	for player in players.values():
		var typed_player := player as PlayerMatchState
		if not typed_player.connected:
			disconnected_ids.append(typed_player.peer_id)
			continue
		typed_player.reset_match()
		typed_player.participant = true
	for peer_id in disconnected_ids:
		players.erase(peer_id)
		scores.remove_player(peer_id)
	scores.reset_match()
	team_scores.reset_match()
	round_number = 0
	heat_number = 0
	last_heat_winner = 0
	last_round_winner = 0
	match_winner = 0
	last_heat_winner_team = 0
	last_round_winner_team = 0
	match_winner_team = 0
	_refresh_team_score_views()
	tied_heat = false
	_pending_round_winner = 0
	_pending_match_winner = 0
	_pending_round_winner_team = 0
	_pending_match_winner_team = 0
	_transition(State.LOBBY, at_tick)


func _transition(next_state: int, at_tick: int) -> void:
	state = next_state
	state_entered_tick = at_tick
	var duration_seconds := _duration_for_state(next_state)
	state_deadline_tick = at_tick + config.duration_to_ticks(duration_seconds) if duration_seconds > 0.0 else -1
	event_history.append({
		"state": next_state,
		"state_name": State.keys()[next_state],
		"entered_tick": at_tick,
		"deadline_tick": state_deadline_tick,
		"round_number": round_number,
		"heat_number": heat_number,
		"scores": scores.snapshot(),
		"team_heat_wins": team_heat_wins.duplicate(true),
		"team_round_wins": team_round_wins.duplicate(true),
	})


func _duration_for_state(target_state: int) -> float:
	match target_state:
		State.DRAFT:
			return config.draft_duration_seconds
		State.COUNTDOWN:
			return config.countdown_duration_seconds
		State.HEAT_RESULT:
			return config.heat_result_duration_seconds
		State.ROUND_RESULT:
			return config.round_result_duration_seconds
		_:
			return 0.0


func _sorted_player_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var peer_ids := source.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		result[peer_id] = source[peer_id]
	return result


func _team_has_living_participant(team_id: int) -> bool:
	return team_id in alive_team_ids()


func _participant_team_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_id in participant_ids():
		var team_id := (players[peer_id] as PlayerMatchState).team_id
		if team_id > 0 and team_id not in result:
			result.append(team_id)
	result.sort()
	return result


func _team_representative(team_id: int) -> int:
	if team_id <= 0:
		return 0
	for peer_id in participant_ids():
		if (players[peer_id] as PlayerMatchState).team_id == team_id:
			return peer_id
	return 0


func _refresh_team_score_views() -> void:
	team_heat_wins = {}
	team_round_wins = {}
	var team_count := GameModeRules.team_count_for_mode(config.game_mode, config.team_count)
	for team_id in range(1, team_count + 1):
		var score := team_scores.get_score(team_id)
		team_heat_wins[team_id] = score.heat_wins if score != null else 0
		team_round_wins[team_id] = score.round_wins if score != null else 0


func _ensure_team_score_entries() -> void:
	var team_count := GameModeRules.team_count_for_mode(config.game_mode, config.team_count)
	for team_id in range(1, team_count + 1):
		team_scores.register_player(team_id)
