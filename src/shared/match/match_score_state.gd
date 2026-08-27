class_name MatchScoreState
extends RefCounted

var _scores: Dictionary = {}


func register_player(peer_id: int, score: PlayerScoreState = null) -> PlayerScoreState:
	if _scores.has(peer_id):
		return _scores[peer_id] as PlayerScoreState
	var assigned_score := score if score != null else PlayerScoreState.new()
	_scores[peer_id] = assigned_score
	return assigned_score


func remove_player(peer_id: int) -> void:
	_scores.erase(peer_id)


func get_score(peer_id: int) -> PlayerScoreState:
	return _scores.get(peer_id) as PlayerScoreState


func award_heat(peer_id: int, rounds_to_win: int) -> Dictionary:
	var score := get_score(peer_id)
	if score == null:
		return {"ok": false, "round_winner": 0, "match_winner": 0}
	score.heat_wins += 1
	var round_winner := 0
	var match_winner := 0
	if score.heat_wins >= GameConstants.HEAT_WINS_TO_WIN_ROUND:
		round_winner = peer_id
		score.round_wins += 1
		clear_heat_wins()
		if score.round_wins >= rounds_to_win:
			match_winner = peer_id
	return {
		"ok": true,
		"round_winner": round_winner,
		"match_winner": match_winner,
	}


func award_forfeit(peer_id: int, rounds_to_win: int) -> void:
	var score := get_score(peer_id)
	if score != null:
		score.round_wins = maxi(score.round_wins, rounds_to_win)
	clear_heat_wins()


func award_kill(peer_id: int) -> bool:
	var score := get_score(peer_id)
	if score == null:
		return false
	score.kills += 1
	return true


func clear_heat_wins() -> void:
	for score in _scores.values():
		(score as PlayerScoreState).reset_heat_wins()


func reset_match() -> void:
	for score in _scores.values():
		(score as PlayerScoreState).reset_match()


func snapshot() -> Dictionary:
	var result: Dictionary = {}
	var peer_ids := _scores.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var score := get_score(peer_id)
		result[peer_id] = {
			"heat_wins": score.heat_wins,
			"round_wins": score.round_wins,
			"kills": score.kills,
		}
	return result
