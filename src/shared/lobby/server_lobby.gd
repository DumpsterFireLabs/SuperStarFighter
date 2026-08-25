class_name ServerLobby
extends RefCounted

var config: MatchConfig
var players: Dictionary = {}
var leader_id: int = 0
var revision: int = 0
var match_active: bool = false
var server_capacity: int = GameConstants.DEFAULT_MAX_PLAYERS
var player_limit: int = GameConstants.DEFAULT_MAX_PLAYERS
var npcs_enabled: bool = false
var _next_join_sequence: int = 1
var _next_npc_serial: int = 1

const NPC_PEER_ID_BASE: int = 1_800_000_000


func _init(match_config: MatchConfig = null) -> void:
	config = match_config.duplicate_config() if match_config != null else MatchConfig.new()
	server_capacity = config.max_players
	player_limit = config.max_players


func admit(peer_id: int, raw_name: String) -> Dictionary:
	if players.has(peer_id):
		return {"ok": false, "reason": NetworkProtocol.REJECT_MALFORMED_TRAFFIC}
	var trimmed := raw_name.strip_edges()
	if not is_valid_display_name(trimmed):
		return {"ok": false, "reason": NetworkProtocol.REJECT_INVALID_NAME}
	var removed_npc_ids: Array[int] = []
	if players.size() >= player_limit:
		if match_active or npc_count() == 0:
			return {"ok": false, "reason": NetworkProtocol.REJECT_SERVER_FULL}
		var waiting_npcs := npc_peer_ids()
		var replaced_npc_id: int = waiting_npcs.back()
		players.erase(replaced_npc_id)
		removed_npc_ids.append(replaced_npc_id)
	var unique_name := _make_unique_name(trimmed)
	var player := PlayerMatchState.new(peer_id, unique_name, _next_join_sequence)
	_next_join_sequence += 1
	player.participant = not match_active
	player.spectator = match_active
	players[peer_id] = player
	if leader_id == 0:
		leader_id = peer_id
	_revision_changed()
	return {"ok": true, "player": player, "removed_npc_ids": removed_npc_ids}


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
	if config.rounds_to_win == value:
		return {"ok": true}
	config.rounds_to_win = value
	_clear_human_ready()
	_revision_changed()
	return {"ok": true}


func request_player_limit(sender_id: int, value: int) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if value < GameConstants.MIN_PLAYERS or value > mini(server_capacity, GameConstants.MAX_PLAYERS):
		return {"ok": false, "error": "Player limit must be from 2 through %d." % mini(server_capacity, GameConstants.MAX_PLAYERS)}
	if value < human_count():
		return {"ok": false, "error": "Player limit cannot be lower than the connected human count."}
	if player_limit == value:
		return {"ok": true, "removed_npc_ids": []}
	player_limit = value
	var removed_npc_ids := _trim_npcs_to_limit()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "removed_npc_ids": removed_npc_ids}


func request_npcs_enabled(sender_id: int, enabled: bool) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if npcs_enabled == enabled:
		return {"ok": true, "removed_npc_ids": []}
	npcs_enabled = enabled
	var removed_npc_ids: Array[int] = []
	if not enabled:
		removed_npc_ids = remove_all_npcs()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "removed_npc_ids": removed_npc_ids}


func request_start(sender_id: int) -> Dictionary:
	if sender_id != leader_id:
		return {"ok": false, "error": "Only the lobby leader may start the match."}
	if match_active:
		return {"ok": false, "error": "A match is already active."}
	if not all_humans_ready():
		return {"ok": false, "error": "Every connected player must ready up before the match can start."}
	var added_npcs: Array[PlayerMatchState] = []
	if npcs_enabled:
		added_npcs = _fill_npc_seats()
	if participant_count() < GameConstants.MIN_PLAYERS:
		return {"ok": false, "error": "At least two participants are required; enable NPCs to force-start solo."}
	match_active = true
	_revision_changed()
	return {"ok": true, "added_npcs": added_npcs}


func request_ready(sender_id: int, ready: bool) -> Dictionary:
	if match_active:
		return {"ok": false, "error": "Ready state cannot change during a match."}
	var player := players.get(sender_id) as PlayerMatchState
	if player == null or player.is_npc:
		return {"ok": false, "error": "Only connected human players may change ready state."}
	if player.lobby_ready == ready:
		return {"ok": true, "changed": false}
	player.lobby_ready = ready
	_revision_changed()
	return {"ok": true, "changed": true}


func request_eject(sender_id: int, target_peer_id: int) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if target_peer_id == sender_id:
		return {"ok": false, "error": "The lobby leader cannot eject themselves."}
	var target := players.get(target_peer_id) as PlayerMatchState
	if target == null:
		return {"ok": false, "error": "That player is no longer in the lobby."}
	if target.is_npc:
		return {"ok": false, "error": "Disable NPC fill to remove server-owned NPCs."}
	var removed := remove(target_peer_id)
	return {"ok": true, "removed_player": removed}


func return_to_lobby() -> void:
	match_active = false
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		player.participant = true
		player.spectator = true
		player.lobby_ready = player.is_npc
		player.reset_match()
	_revision_changed()


func participant_count() -> int:
	var count := 0
	for player_value in players.values():
		if (player_value as PlayerMatchState).participant:
			count += 1
	return count


func human_count() -> int:
	var count := 0
	for player_value in players.values():
		if not (player_value as PlayerMatchState).is_npc:
			count += 1
	return count


func npc_count() -> int:
	var count := 0
	for player_value in players.values():
		if (player_value as PlayerMatchState).is_npc:
			count += 1
	return count


func ready_human_count() -> int:
	var count := 0
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if not player.is_npc and player.lobby_ready:
			count += 1
	return count


func all_humans_ready() -> bool:
	return human_count() > 0 and ready_human_count() == human_count()


func human_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if not player.is_npc:
			result.append(player.peer_id)
	result.sort()
	return result


func npc_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if player.is_npc:
			result.append(player.peer_id)
	result.sort()
	return result


func remove_all_npcs() -> Array[int]:
	var removed := npc_peer_ids()
	for peer_id in removed:
		players.erase(peer_id)
	return removed


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
			"is_npc": player.is_npc,
			"ready": player.lobby_ready,
		})
	return {
		"revision": revision,
		"leader_id": leader_id,
		"rounds_to_win": config.rounds_to_win,
		"max_players": player_limit,
		"player_limit": player_limit,
		"server_capacity": server_capacity,
		"npcs_enabled": npcs_enabled,
		"npc_count": npc_count(),
		"ready_human_count": ready_human_count(),
		"all_humans_ready": all_humans_ready(),
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
		if player.is_npc:
			continue
		if player.join_sequence < earliest_sequence:
			earliest_sequence = player.join_sequence
			earliest_id = player.peer_id
	return earliest_id


func _revision_changed() -> void:
	revision = SequenceMath.increment(revision)


func _settings_authority_error(sender_id: int) -> String:
	if sender_id != leader_id:
		return "Only the lobby leader may change match settings."
	if match_active:
		return "Match settings cannot change during a match."
	return ""


func _fill_npc_seats() -> Array[PlayerMatchState]:
	var added: Array[PlayerMatchState] = []
	while players.size() < player_limit:
		var peer_id := NPC_PEER_ID_BASE + _next_npc_serial
		while players.has(peer_id):
			_next_npc_serial += 1
			peer_id = NPC_PEER_ID_BASE + _next_npc_serial
		var npc := PlayerMatchState.new(peer_id, "NPC %02d" % _next_npc_serial, _next_join_sequence)
		_next_npc_serial += 1
		_next_join_sequence += 1
		npc.is_npc = true
		npc.participant = true
		npc.spectator = false
		npc.lobby_ready = true
		players[peer_id] = npc
		added.append(npc)
	return added


func _trim_npcs_to_limit() -> Array[int]:
	var npc_ids := npc_peer_ids()
	npc_ids.reverse()
	var removed: Array[int] = []
	while players.size() > player_limit and not npc_ids.is_empty():
		var peer_id: int = npc_ids.pop_front()
		players.erase(peer_id)
		removed.append(peer_id)
	return removed


func _clear_human_ready() -> void:
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if not player.is_npc:
			player.lobby_ready = false
