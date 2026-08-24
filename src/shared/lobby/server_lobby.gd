class_name ServerLobby
extends RefCounted

var config: MatchConfig
var players: Dictionary = {}
var leader_id: int = 0
var revision: int = 0
var match_active: bool = false
var _next_join_sequence: int = 1


func _init(match_config: MatchConfig = null) -> void:
	config = match_config.duplicate_config() if match_config != null else MatchConfig.new()


func admit(peer_id: int, raw_name: String) -> Dictionary:
	if players.has(peer_id):
		return {"ok": false, "reason": NetworkProtocol.REJECT_MALFORMED_TRAFFIC}
	if players.size() >= config.max_players:
		return {"ok": false, "reason": NetworkProtocol.REJECT_SERVER_FULL}
	var trimmed := raw_name.strip_edges()
	if not is_valid_display_name(trimmed):
		return {"ok": false, "reason": NetworkProtocol.REJECT_INVALID_NAME}
	var unique_name := _make_unique_name(trimmed)
	var player := PlayerMatchState.new(peer_id, unique_name, _next_join_sequence)
	_next_join_sequence += 1
	player.participant = not match_active
	player.spectator = match_active
	players[peer_id] = player
	if leader_id == 0:
		leader_id = peer_id
	_revision_changed()
	return {"ok": true, "player": player}


func remove(peer_id: int) -> PlayerMatchState:
	var removed := players.get(peer_id) as PlayerMatchState
	if removed == null:
		return null
	players.erase(peer_id)
	if leader_id == peer_id:
		leader_id = _earliest_joined_peer()
	_revision_changed()
	return removed


func request_rounds_to_win(sender_id: int, value: int) -> Dictionary:
	if sender_id != leader_id:
		return {"ok": false, "error": "Only the lobby leader may change match settings."}
	if match_active:
		return {"ok": false, "error": "Match settings cannot change during a match."}
	if value < GameConstants.MIN_ROUNDS_TO_WIN or value > GameConstants.MAX_ROUNDS_TO_WIN:
		return {"ok": false, "error": "Rounds to win is outside the supported range."}
	config.rounds_to_win = value
	_revision_changed()
	return {"ok": true}


func request_start(sender_id: int) -> Dictionary:
	if sender_id != leader_id:
		return {"ok": false, "error": "Only the lobby leader may start the match."}
	if match_active:
		return {"ok": false, "error": "A match is already active."}
	if participant_count() < GameConstants.MIN_PLAYERS:
		return {"ok": false, "error": "At least two participants are required."}
	match_active = true
	_revision_changed()
	return {"ok": true}


func return_to_lobby() -> void:
	match_active = false
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		player.participant = true
		player.spectator = true
		player.reset_match()
	_revision_changed()


func participant_count() -> int:
	var count := 0
	for player_value in players.values():
		if (player_value as PlayerMatchState).participant:
			count += 1
	return count


func serialize() -> Dictionary:
	var serialized_players: Array[Dictionary] = []
	var ordered := players.values()
	ordered.sort_custom(func(left: PlayerMatchState, right: PlayerMatchState) -> bool: return left.join_sequence < right.join_sequence)
	for player_value in ordered:
		var player := player_value as PlayerMatchState
		serialized_players.append({
			"peer_id": player.peer_id,
			"display_name": player.display_name,
			"join_sequence": player.join_sequence,
			"participant": player.participant,
			"spectator": player.spectator,
		})
	return {
		"revision": revision,
		"leader_id": leader_id,
		"rounds_to_win": config.rounds_to_win,
		"max_players": config.max_players,
		"match_active": match_active,
		"players": serialized_players,
	}


static func is_valid_display_name(name_value: String) -> bool:
	if name_value.length() < 1 or name_value.length() > 16:
		return false
	for index in name_value.length():
		var codepoint := name_value.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true


func _make_unique_name(base_name: String) -> String:
	var used: Dictionary = {}
	for player_value in players.values():
		used[(player_value as PlayerMatchState).display_name] = true
	if not used.has(base_name):
		return base_name
	var suffix := 2
	while used.has("%s#%d" % [base_name, suffix]):
		suffix += 1
	return "%s#%d" % [base_name, suffix]


func _earliest_joined_peer() -> int:
	var earliest_id := 0
	var earliest_sequence := 2_147_483_647
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if player.join_sequence < earliest_sequence:
			earliest_sequence = player.join_sequence
			earliest_id = player.peer_id
	return earliest_id


func _revision_changed() -> void:
	revision = SequenceMath.increment(revision)
