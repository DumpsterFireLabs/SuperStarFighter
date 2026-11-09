class_name LobbySettings
extends RefCounted

## One descriptor per scalar lobby setting: its value type, coarse bounds and
## the ServerLobby request that applies it. The operator console, the admin
## panel's setting list and the command service all read this table, so a new
## scalar setting is added here once instead of in each of them.
##
## Bounds are a sanity check on untrusted input. ServerLobby still applies the
## context-dependent rules (current human count, team mode, and so on) and
## owns the player-facing error messages.

enum Kind { BOOL, INT, FLOAT }

const MAX_SETTING_ID_LENGTH: int = 64

const SCALAR := {
	&"rounds_to_win": {"kind": Kind.INT, "request": &"request_rounds_to_win", "min": GameConstants.MIN_ROUNDS_TO_WIN, "max": GameConstants.MAX_ROUNDS_TO_WIN},
	&"player_limit": {"kind": Kind.INT, "request": &"request_player_limit", "min": GameConstants.MIN_PLAYERS, "max": GameConstants.MAX_PLAYERS},
	&"npcs_enabled": {"kind": Kind.BOOL, "request": &"request_npcs_enabled"},
	&"npc_difficulty": {"kind": Kind.INT, "request": &"request_all_npc_difficulty", "min": NpcPilotController.Difficulty.PASSIVE, "max": NpcPilotController.Difficulty.INSANE},
	&"game_mode": {"kind": Kind.INT, "request": &"request_game_mode", "min": GameModeRules.Mode.DEATH_MATCH, "max": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG},
	&"team_count": {"kind": Kind.INT, "request": &"request_team_count", "min": GameModeRules.MIN_TEAM_COUNT, "max": GameModeRules.MAX_TEAM_COUNT},
	&"random_spawn_powerups": {"kind": Kind.BOOL, "request": &"request_random_spawn_powerups"},
	&"random_powerup_interval": {"kind": Kind.FLOAT, "request": &"request_random_powerup_interval", "min": 5.0, "max": 90.0},
	&"random_powerups_permanent": {"kind": Kind.BOOL, "request": &"request_random_powerups_permanent"},
	&"competitive_view": {"kind": Kind.BOOL, "request": &"request_competitive_view"},
	&"overtime_start": {"kind": Kind.FLOAT, "request": &"request_overtime_start", "min": 30.0, "max": 120.0},
}

## Settings an operator may change that belong to the server session rather
## than the lobby; NetworkBridge.operator_set_setting handles them itself.
const SESSION_SETTINGS: Array[StringName] = [&"server_name", &"auto_start"]


static func has(setting_id: StringName) -> bool:
	return SCALAR.has(setting_id)


## Every setting the operator console accepts, in display order.
static func operator_setting_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for setting_id: StringName in SCALAR:
		ids.append(setting_id)
	ids.append_array(SESSION_SETTINGS)
	return ids


static func kind_description(kind: int) -> String:
	match kind:
		Kind.BOOL:
			return "true or false"
		Kind.INT:
			return "an integer"
		_:
			return "a number"


## Converts an untrusted value to the setting's type. Integers arriving as
## whole floats (JSON has no integer type) are accepted. Returns
## {"ok": true, "value": typed value} or {"ok": false, "error": message}.
static func coerce(setting_id: StringName, value: Variant) -> Dictionary:
	if not SCALAR.has(setting_id):
		return {"ok": false, "error": "Unknown lobby setting: %s" % setting_id}
	var kind: int = SCALAR[setting_id].kind
	match kind:
		Kind.BOOL:
			if value is bool:
				return {"ok": true, "value": value}
		Kind.INT:
			if value is int or (value is float and is_finite(value) and is_equal_approx(value, roundf(value))):
				return {"ok": true, "value": int(value)}
		Kind.FLOAT:
			if (value is float and is_finite(value)) or value is int:
				return {"ok": true, "value": float(value)}
	return {"ok": false, "error": "%s requires %s." % [setting_id, kind_description(kind)]}


## True when a typed value lies within the descriptor's coarse bounds.
static func in_bounds(setting_id: StringName, value: Variant) -> bool:
	var descriptor: Dictionary = SCALAR[setting_id]
	if not descriptor.has("min"):
		return true
	return value >= descriptor.min and value <= descriptor.max


## Applies an already-typed value through its ServerLobby request function and
## returns that function's result dictionary.
static func apply(lobby: ServerLobby, sender_id: int, setting_id: StringName, value: Variant) -> Dictionary:
	return lobby.call(SCALAR[setting_id].request, sender_id, value)


## Validates an untrusted request_lobby_setting call before anything touches
## the lobby. Returns {"ok": true, "setting_id", "value"} with the value typed,
## or {"ok": false, "detail"} naming why it was refused for the traffic log.
static func validate_request(setting_id: Variant, value: Variant) -> Dictionary:
	if typeof(setting_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {"ok": false, "detail": "lobby_setting_id_type"}
	if String(setting_id).length() > MAX_SETTING_ID_LENGTH:
		return {"ok": false, "detail": "oversized_lobby_setting_id"}
	var id := StringName(setting_id)
	if not SCALAR.has(id):
		return {"ok": false, "detail": "unknown_lobby_setting"}
	if value is float and not is_finite(value):
		return {"ok": false, "detail": "non_finite_lobby_setting"}
	var typed := coerce(id, value)
	if not typed.ok:
		return {"ok": false, "detail": "lobby_setting_value_type"}
	if not in_bounds(id, typed.value):
		return {"ok": false, "detail": "lobby_setting_out_of_range"}
	return {"ok": true, "setting_id": id, "value": typed.value}
