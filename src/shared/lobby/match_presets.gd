extends RefCounted

## Deliberate starting points; advanced settings remain independently editable.
const COMPETITIVE_MAP_POOL: Array[StringName] = [
	&"core_arena", &"riftline", &"prism_array", &"twin_suns", &"dead_freight",
	&"longwave_array", &"broken_orbit", &"switchyard", &"relay_zero",
]

const PRESETS: Array[Dictionary] = [
	{"id": "competitive", "name": "Semi-competitive · 4 pilots", "description": "Two human teams, equal view and ally-only death cameras. Nine static maps; no NPCs, pickups, currents, gravity or arena hazards. Host-controlled pause; first to three round wins.", "arena_effect_mode": ArenaEffectRules.OFF, "players": 4, "mode": GameModeRules.Mode.TEAM_DEATH_MATCH, "rounds": 3, "powerups": false, "npcs": false},
	{"id": "duel", "name": "Duel · 2 pilots", "description": "A focused one-on-one death match. One NPC fills the opponent seat when playing solo. All maps; optional effects off, intrinsic map hazards active.", "arena_effect_mode": ArenaEffectRules.OFF, "players": 2, "mode": GameModeRules.Mode.DEATH_MATCH, "rounds": 3, "powerups": false},
	{"id": "skirmish", "name": "Skirmish · 4 pilots", "description": "A small free-for-all with room to learn. NPCs fill empty seats; first to three round wins. All maps; optional effects off, intrinsic map hazards active.", "arena_effect_mode": ArenaEffectRules.OFF, "players": 4, "mode": GameModeRules.Mode.DEATH_MATCH, "rounds": 3, "powerups": false},
	{"id": "team_objective", "name": "Team objective · 8 pilots", "description": "Two teams race a neutral flag back to their base. NPCs fill empty seats; temporary pickups add variety. All maps; optional effects off, intrinsic map hazards active.", "arena_effect_mode": ArenaEffectRules.OFF, "players": 8, "mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "rounds": 3, "powerups": true},
	{"id": "chaos", "name": "Chaos · 32 pilots", "description": "A full free-for-all with frequent temporary pickups and NPC fill. All maps, signature effects and intrinsic map hazards active. Expect a crowded arena.", "arena_effect_mode": ArenaEffectRules.SIGNATURE, "players": 32, "mode": GameModeRules.Mode.DEATH_MATCH, "rounds": 3, "powerups": true},
]


static func find(preset_id: String) -> Dictionary:
	for preset in PRESETS:
		if String(preset.id) == preset_id:
			return preset.duplicate(true)
	return {}


static func apply(lobby: ServerLobby, sender_id: int, preset_id: String) -> Dictionary:
	var authority_error := lobby._settings_authority_error(sender_id)
	if not authority_error.is_empty():
		return {"ok": false, "error": authority_error}
	var preset := find(preset_id)
	if preset.is_empty():
		return {"ok": false, "error": "Unknown match preset."}
	var pool := COMPETITIVE_MAP_POOL.duplicate() if preset_id == "competitive" else ArenaLayout.map_ids()
	if not MatchConfig.valid_map_pool(pool):
		return {"ok": false, "error": "This preset has an invalid map pool."}
	var seats := int(preset.players)
	if seats < lobby.human_count() or seats > lobby.server_capacity:
		return {"ok": false, "error": "This preset needs %d seats and cannot remove connected players. Choose a larger preset or adjust the player limit in Pilots." % seats}
	# Validate before changing anything. Switching mode first removes an old TDM
	# team-count constraint before a smaller preset trims only server-owned NPCs.
	lobby.request_map_pool(sender_id, pool)
	lobby.request_game_mode(sender_id, int(preset.mode))
	if preset_id == "competitive":
		lobby.request_team_count(sender_id, 2)
		lobby.request_competitive_view(sender_id, true)
	var resized := lobby.request_player_limit(sender_id, seats)
	var filled := lobby.request_npcs_enabled(sender_id, bool(preset.get("npcs", true)))
	lobby.request_rounds_to_win(sender_id, int(preset.rounds))
	lobby.request_all_npc_difficulty(sender_id, NpcPilotController.Difficulty.NEUTRAL)
	var effects := ArenaEffectRules.DEFAULT.duplicate()
	effects.mode = int(preset.arena_effect_mode)
	lobby.request_arena_effects(sender_id, effects)
	lobby.request_random_spawn_powerups(sender_id, bool(preset.powerups))
	lobby.request_random_powerup_interval(sender_id, 10.0 if preset_id == "chaos" else 20.0)
	lobby.request_random_powerups_permanent(sender_id, false)
	lobby.request_overtime_start(sender_id, GameConstants.OVERTIME_START_SECONDS)
	# Presets also restore automatic team balance; a previous manual assignment
	# must not leave the advertised two-team setup with an empty team.
	for player_value in lobby.players.values():
		(player_value as PlayerMatchState).team_selection = 0
	lobby._assign_teams()
	lobby._clear_human_ready()
	lobby._revision_changed()
	var added: Array = resized.get("added_npcs", [])
	added.append_array(filled.get("added_npcs", []))
	var removed: Array = resized.get("removed_npc_ids", [])
	removed.append_array(filled.get("removed_npc_ids", []))
	# Resizing may have briefly filled seats before this preset disabled NPCs.
	added = added.filter(func(player: PlayerMatchState) -> bool: return lobby.players.has(player.peer_id))
	return {"ok": true, "added_npcs": added, "removed_npc_ids": removed}
