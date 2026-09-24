class_name ServerLobby
extends RefCounted

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const MAX_DISPLAY_NAME_LENGTH: int = 16
const OPERATOR_AUTHORITY_ID: int = -2_147_483_648

static var _forbidden_display_name_regex := RegEx.create_from_string("[\\p{Cc}\\p{Cs}\\p{Co}\\p{Cn}\\p{Zl}\\p{Zp}]")
static var _format_character_regex := RegEx.create_from_string("\\p{Cf}")
static var _space_separator_regex := RegEx.create_from_string("\\p{Zs}")
static var _visible_display_character_regex := RegEx.create_from_string("[^\\p{M}\\p{Z}]")

var config: MatchConfig
var players: Dictionary = {}
var leader_id: int = 0
var revision: int = 0
var match_active: bool = false
var server_capacity: int = GameConstants.DEFAULT_MAX_PLAYERS
var player_limit: int = GameConstants.DEFAULT_MAX_PLAYERS
var npcs_enabled: bool = false
var default_npc_difficulty: int = NpcPilotController.Difficulty.NEUTRAL
var _next_join_sequence: int = 1
var _next_npc_serial: int = 1
var _cached_roster_revision: int = -1
var _cached_human_ids: Array[int] = []
var _cached_npc_ids: Array[int] = []
var _cached_npc_difficulties: Dictionary = {}

const NPC_PEER_ID_BASE: int = 1_800_000_000
const RANDOM_SHIP_COLORS: Array[String] = [
	"42e8ff", "ff4f78", "fff36a", "62ff9b", "d39cff", "ff9f43", "5cf6ff", "ff66d4",
	"8ba1ff", "72ffd5", "ff8fbc", "c5ff63", "ffc76a", "b58cff", "6ee7ff", "ff746a",
]


func _init(match_config: MatchConfig = null) -> void:
	config = match_config.duplicate_config() if match_config != null else MatchConfig.new()
	if config.game_mode == GameModeRules.Mode.KING_OF_THE_HILL:
		config.random_spawn_powerups = true
		config.random_powerups_permanent = false
	server_capacity = config.max_players
	player_limit = config.max_players


func admit(peer_id: int, raw_name: String) -> Dictionary:
	if players.has(peer_id):
		return {"ok": false, "reason": NetworkProtocol.REJECT_MALFORMED_TRAFFIC}
	var sanitized_name := sanitize_display_name(raw_name)
	if sanitized_name.is_empty():
		return {"ok": false, "reason": NetworkProtocol.REJECT_INVALID_NAME}
	var removed_npc_ids: Array[int] = []
	if players.size() >= player_limit:
		if match_active or npc_count() == 0:
			return {"ok": false, "reason": NetworkProtocol.REJECT_SERVER_FULL}
		var waiting_npcs := npc_peer_ids()
		var replaced_npc_id: int = waiting_npcs.back()
		players.erase(replaced_npc_id)
		removed_npc_ids.append(replaced_npc_id)
	var unique_name := _make_unique_name(sanitized_name)
	var player := PlayerMatchState.new(peer_id, unique_name, _next_join_sequence)
	player.ship_color = _random_ship_color(peer_id, player.join_sequence)
	_next_join_sequence += 1
	player.participant = not match_active
	player.spectator = match_active
	players[peer_id] = player
	_assign_teams()
	if leader_id == 0:
		leader_id = peer_id
	_revision_changed()
	return {"ok": true, "player": player, "removed_npc_ids": removed_npc_ids}


func remove(peer_id: int) -> PlayerMatchState:
	var removed := players.get(peer_id) as PlayerMatchState
	if removed == null:
		return null
	players.erase(peer_id)
	_assign_teams()
	if leader_id == peer_id:
		leader_id = _earliest_joined_peer()
	_revision_changed()
	return removed


func elect_leader(administrator_ids: Array[int] = []) -> bool:
	var selected_id := 0
	var earliest_sequence := 2_147_483_647
	for peer_id in administrator_ids:
		var player := players.get(peer_id) as PlayerMatchState
		if player != null and not player.is_npc and player.join_sequence < earliest_sequence:
			selected_id = peer_id
			earliest_sequence = player.join_sequence
	if selected_id == 0:
		selected_id = _earliest_joined_peer()
	if selected_id == leader_id:
		return false
	leader_id = selected_id
	_revision_changed()
	return true


func request_rounds_to_win(sender_id: int, value: int) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
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
	if config.game_mode == GameModeRules.Mode.TEAM_DEATH_MATCH and value < config.team_count:
		return {"ok": false, "error": "Player limit cannot be lower than the configured team count."}
	if player_limit == value:
		return {"ok": true, "removed_npc_ids": [], "added_npcs": []}
	player_limit = value
	var removed_npc_ids := _trim_npcs_to_limit()
	var added_npcs: Array[PlayerMatchState] = []
	if npcs_enabled:
		added_npcs = _fill_npc_seats()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "removed_npc_ids": removed_npc_ids, "added_npcs": added_npcs}


func request_npcs_enabled(sender_id: int, enabled: bool) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if npcs_enabled == enabled:
		return {"ok": true, "removed_npc_ids": [], "added_npcs": []}
	npcs_enabled = enabled
	var removed_npc_ids: Array[int] = []
	var added_npcs: Array[PlayerMatchState] = []
	if not enabled:
		removed_npc_ids = remove_all_npcs()
	else:
		added_npcs = _fill_npc_seats()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "removed_npc_ids": removed_npc_ids, "added_npcs": added_npcs}


func request_npc_difficulty(sender_id: int, npc_peer_id: int, difficulty: int) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	var npc := players.get(npc_peer_id) as PlayerMatchState
	if npc == null or not npc.is_npc:
		return {"ok": false, "error": "That NPC is no longer available in the lobby."}
	if not NpcPilotController.is_valid_difficulty(difficulty):
		return {"ok": false, "error": "NPC difficulty is outside the supported range."}
	if npc.npc_difficulty == difficulty:
		return {"ok": true, "changed": false}
	npc.npc_difficulty = difficulty
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_all_npc_difficulty(sender_id: int, difficulty: int) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if not NpcPilotController.is_valid_difficulty(difficulty):
		return {"ok": false, "error": "NPC difficulty is outside the supported range."}
	var changed := default_npc_difficulty != difficulty
	default_npc_difficulty = difficulty
	for peer_id in npc_peer_ids():
		var npc := players[peer_id] as PlayerMatchState
		if npc.npc_difficulty != difficulty:
			npc.npc_difficulty = difficulty
			changed = true
	if changed:
		_clear_human_ready()
		_revision_changed()
	return {"ok": true, "changed": changed}


func request_arena_effects(sender_id: int, settings: Dictionary) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty(): return {"ok": false, "error": authority_error}
	if not ArenaEffectRules.valid(settings): return {"ok": false, "error": "Invalid arena effect settings."}
	if config.arena_effects == settings: return {"ok": true, "changed": false}
	config.arena_effects = settings.duplicate()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_random_spawn_powerups(sender_id: int, enabled: bool) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if config.random_spawn_powerups == enabled:
		return {"ok": true, "changed": false}
	config.random_spawn_powerups = enabled
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_game_mode(sender_id: int, mode: int) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if not GameModeRules.is_valid_mode(mode):
		return {"ok": false, "error": "Game mode is outside the supported range."}
	if config.game_mode == mode:
		return {"ok": true, "changed": false}
	config.game_mode = mode
	if mode == GameModeRules.Mode.KING_OF_THE_HILL:
		config.random_spawn_powerups = true
		config.random_powerups_permanent = false
	if mode == GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG:
		config.team_count = GameModeRules.DEFAULT_TEAM_COUNT
	_reset_invalid_team_selections()
	_assign_teams()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_team_count(sender_id: int, team_count: int) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if config.game_mode != GameModeRules.Mode.TEAM_DEATH_MATCH:
		return {"ok": false, "error": "Team count is configurable only for Team Death Match."}
	if not GameModeRules.is_valid_team_count(team_count) or team_count > player_limit:
		return {"ok": false, "error": "Team count must be from %d through %d and cannot exceed the player limit." % [GameModeRules.MIN_TEAM_COUNT, GameModeRules.MAX_TEAM_COUNT]}
	if config.team_count == team_count:
		return {"ok": true, "changed": false}
	config.team_count = team_count
	_reset_invalid_team_selections()
	_assign_teams()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_team_assignment(sender_id: int, target_peer_id: int, team_selection: int) -> Dictionary:
	if match_active:
		return {"ok": false, "error": "Team assignments cannot change during a match."}
	if not GameModeRules.is_team_mode(config.game_mode):
		return {"ok": false, "error": "Team assignments are available only in team modes."}
	var sender := players.get(sender_id) as PlayerMatchState
	if sender == null or sender.is_npc or not sender.connected:
		return {"ok": false, "error": "Only connected human players may assign teams."}
	var target := players.get(target_peer_id) as PlayerMatchState
	if target == null or not target.connected or not target.participant:
		return {"ok": false, "error": "That participant is no longer available in the lobby."}
	if sender_id != leader_id and sender_id != target_peer_id and not target.is_npc:
		return {"ok": false, "error": "Only the lobby leader or that player may change this team."}
	var available_team_count := GameModeRules.team_count_for_mode(config.game_mode, config.team_count)
	if team_selection < 0 or team_selection > available_team_count:
		return {"ok": false, "error": "Team selection is outside the configured range."}
	if target.team_selection == team_selection:
		return {"ok": true, "changed": false}
	target.team_selection = team_selection
	_assign_teams()
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true, "team_id": target.team_id}


func request_random_powerup_interval(sender_id: int, seconds: float) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if not is_finite(seconds) or seconds < 5.0 or seconds > 90.0:
		return {"ok": false, "error": "Random powerup interval must be from 5 through 90 seconds."}
	if is_equal_approx(config.random_powerup_interval_seconds, seconds):
		return {"ok": true, "changed": false}
	config.random_powerup_interval_seconds = seconds
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_random_powerups_permanent(sender_id: int, permanent: bool) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if config.random_powerups_permanent == permanent:
		return {"ok": true, "changed": false}
	config.random_powerups_permanent = permanent
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_competitive_view(sender_id: int, enabled: bool) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if config.competitive_view == enabled:
		return {"ok": true, "changed": false}
	config.competitive_view = enabled
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_overtime_start(sender_id: int, seconds: float) -> Dictionary:
	var authority_error := _settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	if not is_finite(seconds) or seconds < 30.0 or seconds > 120.0:
		return {"ok": false, "error": "Overtime must begin from 30 through 120 seconds."}
	if is_equal_approx(config.overtime_start_seconds, seconds):
		return {"ok": true, "changed": false}
	config.overtime_start_seconds = seconds
	_clear_human_ready()
	_revision_changed()
	return {"ok": true, "changed": true}


func request_player_color(sender_id: int, random_color: bool, color_value: String) -> Dictionary:
	var player := players.get(sender_id) as PlayerMatchState
	var pattern: StringName = player.ship_pattern if player != null else ShipAppearanceScript.SOLID
	return request_player_appearance(sender_id, random_color, color_value, pattern)


func request_player_appearance(sender_id: int, random_color: bool, color_value: String, pattern_value: StringName) -> Dictionary:
	if match_active:
		return {"ok": false, "error": "Ship appearance cannot change during a match."}
	var player := players.get(sender_id) as PlayerMatchState
	if player == null or player.is_npc:
		return {"ok": false, "error": "Only connected human players may choose a ship appearance."}
	var chosen := _random_ship_color(sender_id, player.join_sequence + revision) if random_color else _normalized_ship_color(color_value)
	if chosen.is_empty():
		return {"ok": false, "error": "Ship colour must be a six-digit RGB value."}
	if not ShipAppearanceScript.is_valid_pattern(pattern_value):
		return {"ok": false, "error": "Ship pattern is not supported."}
	if player.ship_color == chosen and player.ship_pattern == pattern_value:
		return {"ok": true, "changed": false, "ship_color": chosen, "ship_pattern": pattern_value}
	player.ship_color = chosen
	player.ship_pattern = pattern_value
	player.lobby_ready = false
	_revision_changed()
	return {"ok": true, "changed": true, "ship_color": chosen, "ship_pattern": pattern_value}


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
		return {"ok": false, "error": "At least two participants are required; enable NPCs to start solo."}
	var team_error := team_setup_error()
	if not team_error.is_empty():
		return {"ok": false, "error": team_error}
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
	var added_npcs := restore_npc_fill()
	return {"ok": true, "removed_player": removed, "added_npcs": added_npcs}


func return_to_lobby() -> void:
	match_active = false
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		player.participant = true
		player.spectator = true
		player.lobby_ready = player.is_npc
		player.reset_match()
	_assign_teams()
	_revision_changed()


func participant_count() -> int:
	var count := 0
	for player_value in players.values():
		if (player_value as PlayerMatchState).participant:
			count += 1
	return count


func human_count() -> int:
	_ensure_roster_cache()
	return _cached_human_ids.size()


func npc_count() -> int:
	_ensure_roster_cache()
	return _cached_npc_ids.size()


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
	_ensure_roster_cache()
	return _cached_human_ids.duplicate()


func human_peer_ids_view() -> Array[int]:
	_ensure_roster_cache()
	return _cached_human_ids


func npc_peer_ids() -> Array[int]:
	_ensure_roster_cache()
	return _cached_npc_ids.duplicate()


func npc_peer_ids_view() -> Array[int]:
	_ensure_roster_cache()
	return _cached_npc_ids


func npc_difficulties() -> Dictionary:
	_ensure_roster_cache()
	return _cached_npc_difficulties.duplicate()


func npc_difficulties_view() -> Dictionary:
	_ensure_roster_cache()
	return _cached_npc_difficulties


func remove_all_npcs() -> Array[int]:
	var removed := npc_peer_ids()
	for peer_id in removed:
		players.erase(peer_id)
	_assign_teams()
	return removed


func restore_npc_fill() -> Array[PlayerMatchState]:
	if match_active or not npcs_enabled or human_count() == 0:
		return []
	var added := _fill_npc_seats()
	if not added.is_empty():
		_revision_changed()
	return added


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
			"npc_difficulty": player.npc_difficulty,
			"ship_color": player.ship_color,
			"ship_pattern": player.ship_pattern,
			"team_id": player.team_id,
			"team_selection": player.team_selection,
			"ready": player.lobby_ready,
		})
	var setup_error := team_setup_error()
	return {
		"revision": revision,
		"leader_id": leader_id,
		"rounds_to_win": config.rounds_to_win,
		"max_players": player_limit,
		"player_limit": player_limit,
		"server_capacity": server_capacity,
		"npcs_enabled": npcs_enabled,
		"default_npc_difficulty": default_npc_difficulty,
		"game_mode": config.game_mode,
		"game_mode_name": GameModeRules.mode_name(config.game_mode),
		"team_count": GameModeRules.team_count_for_mode(config.game_mode, config.team_count) if GameModeRules.is_team_mode(config.game_mode) else config.team_count,
		"team_setup_valid": setup_error.is_empty(),
		"team_setup_error": setup_error,
		"arena_effects": config.arena_effects.duplicate(),
		"random_spawn_powerups": config.random_spawn_powerups,
		"random_powerup_interval_seconds": config.random_powerup_interval_seconds,
		"random_powerups_permanent": config.random_powerups_permanent,
		"competitive_view": config.competitive_view,
		"overtime_start_seconds": config.overtime_start_seconds,
		"npc_count": npc_count(),
		"ready_human_count": ready_human_count(),
		"all_humans_ready": all_humans_ready(),
		"match_active": match_active,
		"players": serialized_players,
	}


static func is_valid_display_name(name_value: String) -> bool:
	return not name_value.is_empty() and sanitize_display_name(name_value) == name_value


static func sanitize_display_name(raw_name: String) -> String:
	var name_value := raw_name.strip_edges()
	if name_value.length() < 1 or name_value.length() > MAX_DISPLAY_NAME_LENGTH:
		return ""
	if _forbidden_display_name_regex.search(name_value) != null:
		return ""
	for match_value in _format_character_regex.search_all(name_value):
		var character_index := (match_value as RegExMatch).get_start()
		if name_value.unicode_at(character_index) != 0x200d or not _is_valid_emoji_joiner(name_value, character_index):
			return ""
	for match_value in _space_separator_regex.search_all(name_value):
		if name_value.unicode_at((match_value as RegExMatch).get_start()) != 0x20:
			return ""
	for index in name_value.length():
		var codepoint := name_value.unicode_at(index)
		if _is_variation_selector(codepoint) and not _has_emoji_base_before(name_value, index):
			return ""
	if _visible_display_character_regex.search(name_value) == null:
		return ""
	return name_value


func _make_unique_name(base_name: String) -> String:
	var used := PackedStringArray()
	for player_value in players.values():
		used.append((player_value as PlayerMatchState).display_name)
	if not _display_name_conflicts(base_name, used):
		return base_name
	var suffix := 2
	while true:
		var suffix_text := "#%d" % suffix
		var candidate := base_name.left(MAX_DISPLAY_NAME_LENGTH - suffix_text.length()) + suffix_text
		if not _display_name_conflicts(candidate, used):
			return candidate
		suffix += 1
	return ""


static func _display_name_conflicts(candidate: String, used_names: PackedStringArray) -> bool:
	for used_name in used_names:
		if candidate.nocasecmp_to(used_name) == 0:
			return true
	var text_server := TextServerManager.get_primary_interface()
	return (
		text_server != null and
		text_server.has_feature(TextServer.FEATURE_UNICODE_SECURITY) and
		text_server.is_confusable(candidate, used_names) >= 0
	)


static func _is_valid_emoji_joiner(name_value: String, joiner_index: int) -> bool:
	var previous_index := joiner_index - 1
	while previous_index >= 0 and _is_variation_selector(name_value.unicode_at(previous_index)):
		previous_index -= 1
	var next_index := joiner_index + 1
	while next_index < name_value.length() and _is_variation_selector(name_value.unicode_at(next_index)):
		next_index += 1
	return (
		previous_index >= 0 and
		next_index < name_value.length() and
		_is_emoji_codepoint(name_value.unicode_at(previous_index)) and
		_is_emoji_codepoint(name_value.unicode_at(next_index))
	)


static func _has_emoji_base_before(name_value: String, character_index: int) -> bool:
	var previous_index := character_index - 1
	while previous_index >= 0 and _is_variation_selector(name_value.unicode_at(previous_index)):
		previous_index -= 1
	return previous_index >= 0 and _is_emoji_codepoint(name_value.unicode_at(previous_index))


static func _is_emoji_codepoint(codepoint: int) -> bool:
	return (
		(codepoint >= 0x2300 and codepoint <= 0x23ff) or
		(codepoint >= 0x2600 and codepoint <= 0x27bf) or
		(codepoint >= 0x1f000 and codepoint <= 0x1faff)
	)


static func _is_variation_selector(codepoint: int) -> bool:
	return (
		(codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
		(codepoint >= 0xe0100 and codepoint <= 0xe01ef)
	)


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
	_cached_roster_revision = -1


func _ensure_roster_cache() -> void:
	if _cached_roster_revision == revision:
		return
	_cached_human_ids.clear()
	_cached_npc_ids.clear()
	_cached_npc_difficulties.clear()
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if player.is_npc:
			_cached_npc_ids.append(player.peer_id)
			_cached_npc_difficulties[player.peer_id] = player.npc_difficulty
		else:
			_cached_human_ids.append(player.peer_id)
	_cached_human_ids.sort()
	_cached_npc_ids.sort()
	_cached_roster_revision = revision


func _settings_authority_error(sender_id: int) -> String:
	if sender_id != leader_id and sender_id != OPERATOR_AUTHORITY_ID:
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
		npc.npc_difficulty = default_npc_difficulty
		npc.ship_color = _random_ship_color(peer_id, npc.join_sequence)
		npc.ship_pattern = _random_ship_pattern(peer_id, npc.join_sequence)
		npc.participant = true
		npc.spectator = false
		npc.lobby_ready = true
		players[peer_id] = npc
		added.append(npc)
	_assign_teams()
	return added


func _assign_teams() -> void:
	var ordered: Array = players.values()
	ordered.sort_custom(func(left: PlayerMatchState, right: PlayerMatchState) -> bool: return left.join_sequence < right.join_sequence)
	var team_count := GameModeRules.team_count_for_mode(config.game_mode, config.team_count)
	var team_counts: Dictionary = {}
	for team_id in range(1, team_count + 1):
		team_counts[team_id] = 0
	for player_value in ordered:
		var player := player_value as PlayerMatchState
		if not player.connected or not player.participant:
			player.team_id = 0
			continue
		if team_count == 0:
			player.team_id = 0
		elif player.team_selection > 0 and player.team_selection <= team_count:
			player.team_id = player.team_selection
			team_counts[player.team_id] = int(team_counts[player.team_id]) + 1
		else:
			player.team_id = 0
	if team_count == 0:
		return
	for player_value in ordered:
		var player := player_value as PlayerMatchState
		if not player.connected or not player.participant or player.team_id != 0:
			continue
		var selected_team := 1
		for team_id in range(2, team_count + 1):
			if int(team_counts[team_id]) < int(team_counts[selected_team]):
				selected_team = team_id
		player.team_id = selected_team
		team_counts[selected_team] = int(team_counts[selected_team]) + 1


func team_setup_error() -> String:
	var team_count := GameModeRules.team_count_for_mode(config.game_mode, config.team_count)
	if team_count == 0:
		return ""
	if participant_count() < team_count:
		return "At least %d participants are required for %d teams." % [team_count, team_count]
	var populated: Dictionary = {}
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if player.connected and player.participant and player.team_id > 0:
			populated[player.team_id] = true
	if populated.size() < team_count:
		return "Every configured team must contain at least one participant."
	return ""


func _reset_invalid_team_selections() -> void:
	var team_count := GameModeRules.team_count_for_mode(config.game_mode, config.team_count)
	for player_value in players.values():
		var player := player_value as PlayerMatchState
		if player.team_selection > team_count:
			player.team_selection = 0


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


func _random_ship_color(peer_id: int, salt: int) -> String:
	return RANDOM_SHIP_COLORS[posmod(peer_id * 31 + salt * 17, RANDOM_SHIP_COLORS.size())]


func _random_ship_pattern(peer_id: int, salt: int) -> StringName:
	return ShipAppearanceScript.PATTERNS[posmod(peer_id * 13 + salt * 7, ShipAppearanceScript.PATTERNS.size())]


static func _normalized_ship_color(value: String) -> String:
	var normalized := value.strip_edges().trim_prefix("#").to_lower()
	if normalized.length() != 6:
		return ""
	for character in normalized:
		if character not in "0123456789abcdef":
			return ""
	return normalized
