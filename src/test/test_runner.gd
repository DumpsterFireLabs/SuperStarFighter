extends Node

const AbilityDeliveryTests = preload("res://tests/unit/ability_delivery_tests.gd")

const InputProfileTestsScript = preload("res://tests/unit/input_profile_tests.gd")
const CombatCorrectnessTestsScript = preload("res://tests/unit/combat_correctness_tests.gd")
const GameplayGapTestsScript = preload("res://tests/unit/gameplay_gap_tests.gd")
const ReviewFollowupTestsScript = preload("res://tests/unit/review_followup_tests.gd")
const AbilityBudgetTestsScript = preload("res://tests/unit/ability_budget_tests.gd")
const CombatFeedbackTestsScript = preload("res://tests/unit/combat_feedback_tests.gd")
const BuildLabTestsScript = preload("res://tests/unit/build_lab_tests.gd")
const AccessibilityTestsScript = preload("res://tests/unit/accessibility_tests.gd")
const PerformanceReadabilityTestsScript = preload("res://tests/unit/performance_readability_tests.gd")
const CombatTutorialTestsScript = preload("res://tests/unit/combat_tutorial_tests.gd")
const CardIdentityTestsScript = preload("res://tests/unit/card_identity_tests.gd")
const MatchObservationTestsScript = preload("res://tests/unit/match_observation_tests.gd")
const NpcObjectiveTestsScript = preload("res://tests/unit/npc_objective_tests.gd")
const VisualAccessibilityTestsScript = preload("res://tests/unit/visual_accessibility_tests.gd")
const LobbyResultsTestsScript = preload("res://tests/unit/lobby_results_tests.gd")
const CompetitiveViewTests = preload("res://tests/unit/competitive_view_tests.gd")
const CollisionQueryOptimizationTests = preload("res://tests/unit/collision_query_optimization_tests.gd")
const ScreenControllerTests = preload("res://tests/unit/screen_controller_tests.gd")
const AudioMixTests = preload("res://tests/unit/audio_mix_tests.gd")
const MapResourceTests = preload("res://tests/unit/map_resource_tests.gd")
const StatMetadataTests = preload("res://tests/unit/stat_metadata_tests.gd")
const NetworkOwnershipTests = preload("res://tests/unit/network_ownership_tests.gd")
const ObjectiveContractTests = preload("res://tests/unit/objective_contract_tests.gd")
const NetworkViewOwnershipTests = preload("res://tests/unit/network_view_ownership_tests.gd")
const ArenaMovementFieldTests = preload("res://tests/unit/arena_movement_field_tests.gd")
var _context := TestContext.new()


func _ready() -> void:
	if "--r22-only" in OS.get_cmdline_user_args():
		ArenaMovementFieldTests.run(_context, self)
		print("R22_TEST_SUMMARY passed=%d failed=%d" % [_context.passed, _context.failed])
		get_tree().quit(0 if _context.failed == 0 else 1)
		return
	_run_foundation_tests()
	MapResourceTests.run(_context)
	AbilityDeliveryTests.run(_context)
	StatMetadataTests.run(_context)
	NetworkOwnershipTests.run(_context)
	ObjectiveContractTests.run(_context)
	NetworkViewOwnershipTests.run(_context, self)
	ArenaMovementFieldTests.run(_context, self)
	CompetitiveViewTests.run(_context, self)
	CollisionQueryOptimizationTests.run(_context)
	ScreenControllerTests.run(_context, self)
	AudioMixTests.run(_context, self)
	CardStatTests.run(_context)
	ClientDraftPresentationTests.run(_context, self)
	DraftManagerTests.run(_context)
	MatchStateMachineTests.run(_context)
	CombatSystemTests.run(_context)
	CombatCorrectnessTestsScript.run(_context)
	NetworkProtocolTests.run(_context)
	MatchCoordinatorTests.run(_context)
	MatchObservationTestsScript.run(_context)
	LobbyResultsTestsScript.run(_context, self)
	NpcObjectiveTestsScript.run(_context)
	VisualAccessibilityTestsScript.run(_context, self)
	GameplayGapTestsScript.run(_context, self)
	ReviewFollowupTestsScript.run(_context, self)
	AbilityBudgetTestsScript.run(_context, self)
	CombatFeedbackTestsScript.run(_context)
	BuildLabTestsScript.run(_context, self)
	AccessibilityTestsScript.run(_context, self)
	PerformanceReadabilityTestsScript.run(_context, self)
	CombatTutorialTestsScript.run(_context, self)
	CardIdentityTestsScript.run(_context, self)
	InputProfileTestsScript.run(_context)
	PresentationSystemTests.run(_context, self)
	await preload("res://tests/unit/graphical_language_tests.gd").run(_context, self)
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	if configuration.get("force_test_failure", false):
		_context.expect_true(false, "forced failure proves the nonzero exit path")
	print("TEST_SUMMARY passed=%d failed=%d" % [_context.passed, _context.failed])
	print("SSF_MODE_READY=tests")
	get_tree().quit(0 if _context.failed == 0 else 1)


func _run_foundation_tests() -> void:
	_context.expect_equal(GameConstants.GAME_VERSION, "0.1.0-beta.10", "game version is pinned to Beta 10")
	_context.expect_equal(ProjectSettings.get_setting("application/config/version"), GameConstants.GAME_VERSION, "project metadata matches the shared game version")
	_context.expect_equal(GameConstants.PROTOCOL_VERSION, 32, "protocol version is pinned")
	_context.expect_equal(GameConstants.PHYSICS_TICKS_PER_SECOND, 60, "physics tick rate is pinned")
	_context.expect_equal(GameConstants.DEFAULT_MAX_PLAYERS, 32, "default player capacity is pinned")
	_context.expect_equal(Engine.physics_ticks_per_second, 60, "project physics tick rate matches shared constants")

	var required_actions: Array[StringName] = [
		&"move_up",
		&"move_down",
		&"move_left",
		&"move_right",
		&"aim_up",
		&"aim_down",
		&"aim_left",
		&"aim_right",
		&"fire",
		&"shield",
		&"manual_reload",
		&"special",
		&"scoreboard",
		&"pause_overlay",
		&"diagnostics",
		&"spectator_previous",
		&"spectator_next",
		&"draft_1",
		&"draft_2",
		&"draft_3",
		&"draft_4",
		&"draft_5",
	]
	for action in required_actions:
		_context.expect_true(InputMap.has_action(action), "input action %s exists" % action)
	var tab_mapped := false
	for event in InputMap.action_get_events(&"scoreboard"):
		if event is InputEventKey and (event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB):
			tab_mapped = true
	_context.expect_true(tab_mapped, "scoreboard action uses Godot's special Tab keycode")

	var startup_scenes: Array[String] = [
		"res://scenes/client/client_main.tscn",
		"res://scenes/server/server_main.tscn",
		"res://scenes/test/bot_client_main.tscn",
		"res://scenes/test/test_runner.tscn",
	]
	for scene_path in startup_scenes:
		_context.expect_true(ResourceLoader.exists(scene_path), "startup scene %s exists" % scene_path)

	var server_config := CommandLineConfig.parse(
		PackedStringArray(["--server", "--host=localhost", "--port=7123", "--max-players=16", "--rounds-to-win=4", "--server-name=Foundation Arena", "--password=test-lobby"])
	)
	_context.expect_true(server_config.ok, "valid server arguments parse")
	_context.expect_equal(server_config.get("mode"), "server", "server mode is selected")
	_context.expect_equal(server_config.get("port"), 7123, "custom port parses")
	_context.expect_equal(server_config.get("max_players"), 16, "custom player limit parses")
	_context.expect_equal(server_config.get("rounds_to_win"), 4, "custom round target parses")
	_context.expect_equal(server_config.get("host"), "localhost", "custom network host parses")
	_context.expect_equal(server_config.get("server_name"), "Foundation Arena", "custom LAN server name parses")
	_context.expect_equal(server_config.get("lobby_password"), "test-lobby", "required lobby password parses")
	var prior_environment_password := OS.get_environment(CommandLineConfig.LOBBY_PASSWORD_ENVIRONMENT_VARIABLE)
	OS.set_environment(CommandLineConfig.LOBBY_PASSWORD_ENVIRONMENT_VARIABLE, "environment-lobby")
	var environment_config := CommandLineConfig.parse(PackedStringArray(["--server"]))
	_context.expect_true(environment_config.ok, "server accepts a lobby password from the protected process environment")
	_context.expect_equal(environment_config.get("lobby_password"), "environment-lobby", "environment lobby password reaches server configuration")
	OS.set_environment(CommandLineConfig.LOBBY_PASSWORD_ENVIRONMENT_VARIABLE, prior_environment_password)
	var prior_admin_password := OS.get_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE)
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, "operator-secret")
	var admin_config := CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--port=7123", "--admin-port=7124"]))
	_context.expect_true(admin_config.ok, "dedicated server accepts a distinct protected admin credential")
	_context.expect_equal(admin_config.get("admin_port"), 7124, "loopback admin port parses")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, "short")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--admin-port=7124"])).ok, "remote administration rejects weak short credentials")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, "operator-secret")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--port=7123", "--admin-port=7123"])).ok, "admin and gameplay ports cannot collide")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, "lobby-secret")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--admin-port=7124"])).ok, "admin and lobby credentials must differ")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, prior_admin_password)
	var match_test_config := CommandLineConfig.parse(PackedStringArray([
		"--server",
		"--test-fast-match",
		"--test-match-seed=4242",
		"--password=test-lobby",
	]))
	_context.expect_true(match_test_config.ok, "match-loop test server options parse")
	_context.expect_true(match_test_config.get("test_fast_match"), "fast match test mode is retained")
	_context.expect_equal(match_test_config.get("test_match_seed"), 4242, "deterministic match seed parses")
	var bot_config := CommandLineConfig.parse(PackedStringArray([
		"--bot-client=ProtocolProbe",
		"--host=127.0.0.1",
		"--test-protocol-version=999",
		"--bot-passive",
		"--bot-draft-timeout",
		"--bot-enable-npcs",
		"--bot-player-limit=4",
		"--bot-start-at=4",
		"--bot-randomized",
		"--password=test-lobby",
	]))
	_context.expect_true(bot_config.ok, "test bot protocol override parses")
	_context.expect_equal(bot_config.get("test_protocol_version"), 999, "test bot protocol override is retained")
	_context.expect_true(bot_config.get("bot_passive"), "passive bot behavior parses")
	_context.expect_true(bot_config.get("bot_draft_timeout"), "draft-timeout bot behavior parses")
	_context.expect_true(bot_config.get("bot_enable_npcs"), "NPC lobby bot behavior parses")
	_context.expect_equal(bot_config.get("bot_player_limit"), 4, "NPC lobby player limit parses")
	_context.expect_equal(bot_config.get("bot_start_at"), 4, "deferred soak start count parses")
	_context.expect_true(bot_config.get("bot_randomized"), "randomized soak behavior parses")
	var malicious_bot_config := CommandLineConfig.parse(PackedStringArray([
		"--bot-client=MalformedProbe",
		"--bot-malformed-input",
		"--password=test-lobby",
	]))
	_context.expect_true(malicious_bot_config.ok, "malformed-traffic test bot mode parses")
	var conflicting_traffic := CommandLineConfig.parse(PackedStringArray([
		"--bot-client=ConflictProbe",
		"--bot-malformed-input",
		"--bot-excessive-input",
		"--password=test-lobby",
	]))
	_context.expect_false(conflicting_traffic.ok, "malicious traffic modes are mutually exclusive")
	var soak_server_config := CommandLineConfig.parse(PackedStringArray([
		"--server",
		"--test-server-duration=600",
		"--password=test-lobby",
	]))
	_context.expect_true(soak_server_config.ok, "ten-minute soak duration parses")
	var invalid_protocol_override := CommandLineConfig.parse(PackedStringArray([
		"--server",
		"--test-protocol-version=999",
		"--password=test-lobby",
	]))
	_context.expect_false(invalid_protocol_override.ok, "protocol override is restricted to test bots")
	var invalid_host := CommandLineConfig.parse(PackedStringArray([
		"--bot-client=BadHost",
		"--host=not a host",
		"--password=test-lobby",
	]))
	_context.expect_false(invalid_host.ok, "hostnames containing spaces are rejected")

	var invalid_port := CommandLineConfig.parse(PackedStringArray(["--server", "--port=80"]))
	_context.expect_true(not invalid_port.ok, "privileged server port is rejected")
	_context.expect_equal(invalid_port.get("exit_code"), 2, "invalid arguments use exit code 2")
	var missing_password := CommandLineConfig.parse(PackedStringArray(["--server"]))
	_context.expect_false(missing_password.ok, "network hosts cannot start without a lobby password")

	var conflicting_modes := CommandLineConfig.parse(
		PackedStringArray(["--server", "--bot-client=Conflict"])
	)
	_context.expect_true(not conflicting_modes.ok, "conflicting startup modes are rejected")
