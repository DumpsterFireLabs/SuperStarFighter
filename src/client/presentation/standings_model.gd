class_name StandingsModel
extends RefCounted


static func peer_ids(payload: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for peer_value in payload.get("participant_peer_ids", []):
		_append_unique_peer(result, int(peer_value))
	var scores := payload.get("scores", {}) as Dictionary
	for peer_value in scores.keys():
		_append_unique_peer(result, int(peer_value))
	_append_unique_peer(result, int(payload.get("match_winner", 0)))
	result.sort_custom(func(first: int, second: int) -> bool:
		var first_score := score(payload, first)
		var second_score := score(payload, second)
		var first_rounds := int(first_score.get("round_wins", 0))
		var second_rounds := int(second_score.get("round_wins", 0))
		if first_rounds != second_rounds:
			return first_rounds > second_rounds
		var first_heats := int(first_score.get("heat_wins", 0))
		var second_heats := int(second_score.get("heat_wins", 0))
		if first_heats != second_heats:
			return first_heats > second_heats
		if int(payload.get("game_mode", GameModeRules.Mode.DEATH_MATCH)) == GameModeRules.Mode.KING_OF_THE_HILL:
			var first_hill_score := objective_score(payload, first)
			var second_hill_score := objective_score(payload, second)
			if not is_equal_approx(first_hill_score, second_hill_score):
				return first_hill_score > second_hill_score
		return first < second
	)
	return result


static func score(payload: Dictionary, peer_id: int) -> Dictionary:
	var scores := payload.get("scores", {}) as Dictionary
	return scores.get(peer_id, scores.get(str(peer_id), {})) as Dictionary


static func build(payload: Dictionary, peer_id: int) -> Dictionary:
	var builds := payload.get("builds", {}) as Dictionary
	return builds.get(peer_id, builds.get(str(peer_id), {})) as Dictionary


static func objective_score(payload: Dictionary, peer_id: int) -> float:
	var objective := payload.get("objective", {}) as Dictionary
	var progress := objective.get("progress", {}) as Dictionary
	return float(progress.get(peer_id, progress.get(str(peer_id), 0.0)))


static func _append_unique_peer(peer_ids: Array[int], peer_id: int) -> void:
	if peer_id != 0 and peer_id not in peer_ids:
		peer_ids.append(peer_id)
