class_name MatchConfig
extends RefCounted

var protocol_version: int = GameConstants.PROTOCOL_VERSION
var port: int = GameConstants.DEFAULT_PORT
var max_players: int = GameConstants.DEFAULT_MAX_PLAYERS
var rounds_to_win: int = GameConstants.DEFAULT_ROUNDS_TO_WIN
var draft_duration_seconds: float = GameConstants.DRAFT_DURATION_SECONDS
var countdown_duration_seconds: float = GameConstants.COUNTDOWN_DURATION_SECONDS
var heat_result_duration_seconds: float = GameConstants.HEAT_RESULT_DURATION_SECONDS
var round_result_duration_seconds: float = GameConstants.ROUND_RESULT_DURATION_SECONDS
var arena_effects: Dictionary = ArenaEffectRules.DEFAULT.duplicate()
var competitive_view: bool = false
var silly_mode: bool = false
var random_spawn_powerups: bool = false
var random_powerup_interval_seconds: float = 20.0
var random_powerups_permanent: bool = false
var overtime_start_seconds: float = GameConstants.OVERTIME_START_SECONDS
var game_mode: int = GameModeRules.Mode.DEATH_MATCH
var team_count: int = GameModeRules.DEFAULT_TEAM_COUNT


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ArenaEffectRules.valid(arena_effects):
		errors.append("Invalid arena effect settings.")
	if protocol_version != GameConstants.PROTOCOL_VERSION:
		errors.append("Protocol version must match the shared protocol version.")
	if port < GameConstants.MIN_PORT or port > GameConstants.MAX_PORT:
		errors.append("Port must be from %d through %d." % [GameConstants.MIN_PORT, GameConstants.MAX_PORT])
	if max_players < GameConstants.MIN_PLAYERS or max_players > GameConstants.MAX_PLAYERS:
		errors.append(
			"Maximum players must be from %d through %d." % [
				GameConstants.MIN_PLAYERS,
				GameConstants.MAX_PLAYERS,
			]
		)
	if rounds_to_win < GameConstants.MIN_ROUNDS_TO_WIN or rounds_to_win > GameConstants.MAX_ROUNDS_TO_WIN:
		errors.append(
			"Rounds to win must be from %d through %d." % [
				GameConstants.MIN_ROUNDS_TO_WIN,
				GameConstants.MAX_ROUNDS_TO_WIN,
			]
		)
	for duration in [
		draft_duration_seconds,
		countdown_duration_seconds,
		heat_result_duration_seconds,
		round_result_duration_seconds,
	]:
		if not is_finite(duration) or duration <= 0.0:
			errors.append("All state durations must be finite and greater than zero.")
			break
	if not is_finite(random_powerup_interval_seconds) or random_powerup_interval_seconds < 5.0 or random_powerup_interval_seconds > 90.0:
		errors.append("Random powerup interval must be from 5 through 90 seconds.")
	if not is_finite(overtime_start_seconds) or overtime_start_seconds < 30.0 or overtime_start_seconds > 120.0:
		errors.append("Overtime must begin from 30 through 120 seconds.")
	if not GameModeRules.is_valid_mode(game_mode):
		errors.append("Game mode is outside the supported range.")
	if not GameModeRules.is_valid_team_count(team_count) or team_count > max_players:
		errors.append("Team count must be from %d through %d and cannot exceed the player limit." % [GameModeRules.MIN_TEAM_COUNT, GameModeRules.MAX_TEAM_COUNT])
	return errors


func duration_to_ticks(duration_seconds: float) -> int:
	return ceili(duration_seconds * GameConstants.PHYSICS_TICKS_PER_SECOND)


func duplicate_config() -> MatchConfig:
	var copy := MatchConfig.new()
	copy.protocol_version = protocol_version
	copy.port = port
	copy.max_players = max_players
	copy.rounds_to_win = rounds_to_win
	copy.draft_duration_seconds = draft_duration_seconds
	copy.countdown_duration_seconds = countdown_duration_seconds
	copy.heat_result_duration_seconds = heat_result_duration_seconds
	copy.round_result_duration_seconds = round_result_duration_seconds
	copy.arena_effects = arena_effects.duplicate()
	copy.competitive_view = competitive_view
	copy.silly_mode = silly_mode
	copy.random_spawn_powerups = random_spawn_powerups
	copy.random_powerup_interval_seconds = random_powerup_interval_seconds
	copy.random_powerups_permanent = random_powerups_permanent
	copy.overtime_start_seconds = overtime_start_seconds
	copy.game_mode = game_mode
	copy.team_count = team_count
	return copy
