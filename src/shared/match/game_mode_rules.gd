class_name GameModeRules
extends RefCounted

enum Mode {
	DEATH_MATCH,
	TEAM_DEATH_MATCH,
	KING_OF_THE_HILL,
	CAPTURE_THE_FLAG,
	TEAM_CAPTURE_THE_FLAG,
}

const MODE_NAMES: Array[String] = [
	"Death Match",
	"Team Death Match",
	"King of the Hill",
	"Capture the Flag",
	"Team Capture the Flag",
]
const MODE_DESCRIPTIONS: Array[String] = [
	"Free-for-all combat. The last surviving pilot wins the heat.",
	"Two to eight configured teams fight with friendly fire disabled. Eliminate every opposing team to win the heat.",
	"Accumulate 20 seconds alone in the control point. Contested time pauses scoring; respawns take 5 seconds. At the time limit, highest control time wins; equal times draw.",
	"Take the neutral center flag back to your marked launch base. Respawns take 5 seconds. Bases remain inside overtime; no capture by the time limit means a draw.",
	"Two balanced teams carry a neutral center flag into their own base. Respawns take 5 seconds. Bases remain inside overtime; no capture by the time limit means a draw.",
]
const MIN_TEAM_COUNT: int = 2
const MAX_TEAM_COUNT: int = 8
const DEFAULT_TEAM_COUNT: int = 2
const TEAM_NAMES := {
	1: "CYAN TEAM",
	2: "MAGENTA TEAM",
	3: "GOLD TEAM",
	4: "GREEN TEAM",
	5: "VIOLET TEAM",
	6: "ORANGE TEAM",
	7: "BLUE TEAM",
	8: "RED TEAM",
}
const TEAM_COLORS := {
	1: Color("42e8ff"),
	2: Color("ff4fd8"),
	3: Color("ffe45c"),
	4: Color("62ff9b"),
	5: Color("b58cff"),
	6: Color("ff9f43"),
	7: Color("6f8cff"),
	8: Color("ff5d68"),
}
const HILL_HOLD_SECONDS: float = 20.0
const OBJECTIVE_ZONE_RADIUS: float = 125.0
const HILL_OVERTIME_MINIMUM_RADIUS: float = OBJECTIVE_ZONE_RADIUS + 50.0
const FLAG_PICKUP_RADIUS: float = 42.0
const FLAG_RESET_SECONDS: float = 8.0
const OBJECTIVE_RESPAWN_SECONDS: float = 5.0


static func is_valid_mode(mode: int) -> bool:
	return mode >= Mode.DEATH_MATCH and mode <= Mode.TEAM_CAPTURE_THE_FLAG


static func mode_name(mode: int) -> String:
	return MODE_NAMES[mode] if is_valid_mode(mode) else MODE_NAMES[Mode.DEATH_MATCH]


static func mode_description(mode: int) -> String:
	return MODE_DESCRIPTIONS[mode] if is_valid_mode(mode) else MODE_DESCRIPTIONS[Mode.DEATH_MATCH]


static func is_team_mode(mode: int) -> bool:
	return mode == Mode.TEAM_DEATH_MATCH or mode == Mode.TEAM_CAPTURE_THE_FLAG


static func is_valid_team_count(team_count: int) -> bool:
	return team_count >= MIN_TEAM_COUNT and team_count <= MAX_TEAM_COUNT


static func team_count_for_mode(mode: int, configured_count: int) -> int:
	if mode == Mode.TEAM_DEATH_MATCH:
		return clampi(configured_count, MIN_TEAM_COUNT, MAX_TEAM_COUNT)
	if mode == Mode.TEAM_CAPTURE_THE_FLAG:
		return DEFAULT_TEAM_COUNT
	return 0


static func uses_hill(mode: int) -> bool:
	return mode == Mode.KING_OF_THE_HILL


static func uses_flag(mode: int) -> bool:
	return mode == Mode.CAPTURE_THE_FLAG or mode == Mode.TEAM_CAPTURE_THE_FLAG


static func uses_objective(mode: int) -> bool:
	return uses_hill(mode) or uses_flag(mode)


static func uses_respawns(mode: int) -> bool:
	return uses_objective(mode)


static func team_name(team_id: int) -> String:
	return String(TEAM_NAMES.get(team_id, "NO TEAM"))


static func team_color(team_id: int) -> Color:
	return TEAM_COLORS.get(team_id, Color("aebbd4")) as Color


static func objective_spawn(map_id: StringName, round_number: int = 0) -> Vector2:
	var center := ArenaLayout.center(map_id)
	if round_number <= 0:
		return _nearest_clear_zone(center, map_id)
	# Hills rotate through distinct sectors each round instead of always occupying
	# the arena center. The map-aware clearance search keeps every variant legal.
	var sector := posmod(round_number - 1, 8)
	var radius := 330.0 + float(posmod(round_number - 1, 2)) * 110.0
	var desired := center + Vector2.from_angle(TAU * float(sector) / 8.0) * radius
	return _nearest_clear_zone(desired, map_id)


static func capture_zone(mode: int, team_id: int, map_id: StringName) -> Vector2:
	var center := ArenaLayout.center(map_id)
	var desired := Vector2(center.x, 170.0)
	if mode == Mode.TEAM_CAPTURE_THE_FLAG:
		desired = Vector2(190.0 if team_id == 1 else GameConstants.ARENA_SIZE.x - 190.0, center.y)
	return _nearest_clear_zone(desired, map_id)


static func _nearest_clear_zone(desired: Vector2, map_id: StringName) -> Vector2:
	var clearance_margin := OBJECTIVE_ZONE_RADIUS - GameConstants.SHIP_COLLISION_RADIUS
	if ArenaCollisionSystem.is_ship_position_clear(desired, map_id, clearance_margin):
		return desired
	for ring in range(1, 9):
		var distance := float(ring) * 90.0
		for sample in 24:
			var candidate := desired + Vector2.from_angle(TAU * float(sample) / 24.0) * distance
			if ArenaCollisionSystem.is_ship_position_clear(candidate, map_id, clearance_margin):
				return candidate
	for anchor in ArenaLayout.spawn_anchors(map_id):
		if ArenaCollisionSystem.is_ship_position_clear(anchor, map_id, clearance_margin):
			return anchor
	return desired
