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
	"Two balanced teams fight with friendly fire disabled. Eliminate the opposing team to win the heat.",
	"Hold the central control point uncontested for 20 seconds without dying.",
	"Take the neutral flag from the middle of the arena to the marked extraction zone.",
	"Two balanced teams contest a neutral center flag and carry it into their own team base.",
]
const TEAM_NAMES := {1: "CYAN TEAM", 2: "MAGENTA TEAM"}
const TEAM_COLORS := {1: Color("42e8ff"), 2: Color("ff4fd8")}
const HILL_HOLD_SECONDS: float = 20.0
const OBJECTIVE_ZONE_RADIUS: float = 125.0
const FLAG_PICKUP_RADIUS: float = 42.0
const FLAG_RESET_SECONDS: float = 8.0


static func is_valid_mode(mode: int) -> bool:
	return mode >= Mode.DEATH_MATCH and mode <= Mode.TEAM_CAPTURE_THE_FLAG


static func mode_name(mode: int) -> String:
	return MODE_NAMES[mode] if is_valid_mode(mode) else MODE_NAMES[Mode.DEATH_MATCH]


static func mode_description(mode: int) -> String:
	return MODE_DESCRIPTIONS[mode] if is_valid_mode(mode) else MODE_DESCRIPTIONS[Mode.DEATH_MATCH]


static func is_team_mode(mode: int) -> bool:
	return mode == Mode.TEAM_DEATH_MATCH or mode == Mode.TEAM_CAPTURE_THE_FLAG


static func uses_hill(mode: int) -> bool:
	return mode == Mode.KING_OF_THE_HILL


static func uses_flag(mode: int) -> bool:
	return mode == Mode.CAPTURE_THE_FLAG or mode == Mode.TEAM_CAPTURE_THE_FLAG


static func uses_objective(mode: int) -> bool:
	return uses_hill(mode) or uses_flag(mode)


static func team_name(team_id: int) -> String:
	return String(TEAM_NAMES.get(team_id, "NO TEAM"))


static func team_color(team_id: int) -> Color:
	return TEAM_COLORS.get(team_id, Color("aebbd4")) as Color


static func objective_spawn(map_id: StringName) -> Vector2:
	return _nearest_clear_zone(ArenaLayout.center(map_id), map_id)


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
