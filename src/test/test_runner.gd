extends Node

const UNIT_TEST_DIRECTORY := "res://tests/unit"
const FOUNDATION_SUITE := "foundation"
const TREE := 1
const AWAIT := 2
## Every suite, in run order: [file name without .gd, flags, method]. TREE
## passes this node as the suite's parent; AWAIT waits for a suite that yields.
## Keep the order explicit; some suites depend on state left by earlier ones.
const SUITES: Array = [
	["arena_effect_tests", TREE],
	[FOUNDATION_SUITE, 0],
	["ship_collision_tests", 0],
	["objective_fairness_tests", 0],
	["preset_hazard_tests", TREE],
	["map_resource_tests", 0],
	["map_navigation_tests", 0],
	["update_checker_tests", 0],
	["ability_delivery_tests", TREE | AWAIT],
	["combat_request_tests", TREE],
	["movement_reconciliation_tests", 0],
	["stat_metadata_tests", 0],
	["network_ownership_tests", 0],
	["architecture_followup_tests", 0],
	["objective_contract_tests", 0],
	["network_view_ownership_tests", TREE],
	["client_match_state_tests", 0],
	["spectator_camera_tests", TREE],
	["arena_movement_field_tests", TREE],
	["competitive_view_tests", TREE],
	["collision_query_optimization_tests", 0],
	["screen_controller_tests", TREE],
	["draft_layout_tests", TREE | AWAIT],
	["audio_mix_tests", TREE],
	["card_stat_tests", 0],
	["client_draft_presentation_tests", TREE],
	["draft_manager_tests", 0],
	["match_state_machine_tests", 0],
	["combat_system_tests", 0],
	["projectile_trace_tests", 0],
	["combat_correctness_tests", 0],
	["escort_drone_tests", 0],
	["escort_drone_tests", TREE, &"run_network"],
	["network_protocol_tests", 0],
	["match_coordinator_tests", 0],
	["match_observation_tests", 0],
	["lobby_results_tests", TREE],
	["npc_objective_tests", 0],
	["visual_accessibility_tests", TREE],
	["gameplay_gap_tests", TREE],
	["review_followup_tests", TREE],
	["ability_budget_tests", TREE],
	["combat_feedback_tests", 0],
	["shield_timing_tests", TREE],
	["build_lab_tests", TREE],
	["accessibility_tests", TREE],
	["performance_readability_tests", TREE],
	["combat_tutorial_tests", TREE | AWAIT],
	["card_identity_tests", TREE],
	["presentation_followup_tests", TREE | AWAIT],
	["input_profile_tests", 0],
	["presentation_system_tests", TREE],
	["graphical_language_tests", TREE | AWAIT],
]
## Suites run by another suite rather than by this runner, keyed by file name.
const SUITES_RUN_BY_OTHER_SUITES := {
	"connection_preferences_tests.gd": "res://tests/unit/screen_controller_tests.gd",
	"connection_screen_tests.gd": "res://tests/unit/screen_controller_tests.gd",
}
var _context := TestContext.new()


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	var filter := String(configuration.get("test_filter", ""))
	if filter.is_empty():
		_run_registration_guard()
	else:
		print("TEST_FILTER %s" % filter)
	var timings: Array[String] = []
	var selected := 0
	for entry: Array in SUITES:
		var suite_name: String = entry[0]
		if not filter.is_empty() and not suite_name.contains(filter):
			continue
		selected += 1
		var method: StringName = entry[2] if entry.size() > 2 else &"run"
		var label := suite_name if method == &"run" else "%s.%s" % [suite_name, method]
		var passed_before := _context.passed
		var failed_before := _context.failed
		var started_msec := Time.get_ticks_msec()
		_context.begin_suite(label)
		if suite_name == FOUNDATION_SUITE:
			_run_foundation_tests()
		else:
			var suite: GDScript = load(UNIT_TEST_DIRECTORY.path_join(suite_name + ".gd"))
			var flags: int = entry[1]
			var arguments: Array = [_context, self] if flags & TREE else [_context]
			if flags & AWAIT:
				await suite.callv(method, arguments)
			else:
				suite.callv(method, arguments)
		timings.append("SUITE %s passed=%d failed=%d ms=%d" % [label, _context.passed - passed_before, _context.failed - failed_before, Time.get_ticks_msec() - started_msec])
	_context.begin_suite("")
	if selected == 0:
		_context.expect_true(false, "test filter %s matches at least one suite" % filter)
	if configuration.get("force_test_failure", false):
		_context.expect_true(false, "forced failure proves the nonzero exit path")
	for line in timings:
		print(line)
	_context.print_failure_recap()
	print("TEST_SUMMARY passed=%d failed=%d" % [_context.passed, _context.failed])
	print("SSF_MODE_READY=tests")
	get_tree().quit(0 if _context.failed == 0 else 1)


## Fails for any unit suite that nothing runs, so a new test file cannot pass
## CI by never executing. A suite runs when it is listed in SUITES, or when the
## suite named in SUITES_RUN_BY_OTHER_SUITES calls `preload("<path>").run`.
func _run_registration_guard() -> void:
	var listed := {}
	for entry: Array in SUITES:
		listed[String(entry[0]) + ".gd"] = true
	var suite_files := Array(DirAccess.get_files_at(UNIT_TEST_DIRECTORY)).filter(func(file_name: String) -> bool: return file_name.ends_with("_tests.gd"))
	_context.expect_true(suite_files.size() > 0, "registration guard finds unit suites under %s" % UNIT_TEST_DIRECTORY)
	for file_name: String in suite_files:
		if SUITES_RUN_BY_OTHER_SUITES.has(file_name):
			var invoker := String(SUITES_RUN_BY_OTHER_SUITES[file_name])
			var invoked := FileAccess.get_file_as_string(invoker).contains('preload("%s").run' % UNIT_TEST_DIRECTORY.path_join(file_name))
			_context.expect_true(invoked, "unit suite %s is run by %s" % [file_name, invoker])
		else:
			_context.expect_true(listed.has(file_name), "unit suite %s is listed in SUITES in src/test/test_runner.gd" % file_name)
	for file_name: String in listed:
		if file_name != FOUNDATION_SUITE + ".gd":
			_context.expect_true(suite_files.has(file_name), "SUITES entry %s exists under %s" % [file_name, UNIT_TEST_DIRECTORY])
	for file_name: String in SUITES_RUN_BY_OTHER_SUITES:
		_context.expect_true(suite_files.has(file_name), "suite %s listed as run by another suite still exists" % file_name)


func _run_foundation_tests() -> void:
	var release: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://release.json"))
	_context.expect_equal(GameConstants.GAME_VERSION, release.version, "game version matches the release manifest")
	_context.expect_equal(GameConstants.RELEASE_LABEL, "BETA " + str(release.version).get_slice("-beta.", 1), "release label is derived from the game version")
	_context.expect_equal(GameConstants.PROTOCOL_VERSION, int(release.protocol_version), "protocol version matches the release manifest")
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
	var in_game_admin_config := CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret"]))
	_context.expect_true(in_game_admin_config.ok and int(in_game_admin_config.admin_port) == 0, "in-game admin needs only the separate password, not a TCP admin port")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, "short")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--admin-port=7124"])).ok, "remote administration rejects weak short credentials")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret"])).ok, "in-game administration rejects weak short credentials")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, "operator-secret")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--port=7123", "--admin-port=7123"])).ok, "admin and gameplay ports cannot collide")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, "lobby-secret")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--admin-port=7124"])).ok, "admin and lobby credentials must differ")
	OS.set_environment(CommandLineConfig.ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, prior_admin_password)
	_context.expect_equal(CommandLineConfig.parse(PackedStringArray([])).get("window_mode_override"), "", "client keeps the saved display mode without an override")
	_context.expect_equal(CommandLineConfig.parse(PackedStringArray(["--windowed"])).get("window_mode_override"), "windowed", "--windowed overrides the client display mode")
	_context.expect_equal(CommandLineConfig.parse(PackedStringArray(["--fullscreen"])).get("window_mode_override"), "fullscreen", "--fullscreen overrides the client display mode")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--windowed", "--fullscreen"])).ok, "conflicting window overrides are rejected")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=test-lobby", "--fullscreen"])).ok, "window overrides are client-only")
	var match_test_config := CommandLineConfig.parse(PackedStringArray([
		"--server",
		"--test-fast-match",
		"--test-match-seed=4242",
		"--password=test-lobby",
	]))
	_context.expect_true(match_test_config.ok, "match-loop test server options parse")
	_context.expect_true(match_test_config.get("test_fast_match"), "fast match test mode is retained")
	_context.expect_equal(match_test_config.get("test_match_seed"), 4242, "deterministic match seed parses")
	var proxy_config := CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--bind=127.0.0.1", "--behind-proxy"]))
	_context.expect_true(proxy_config.ok and proxy_config.bind_address == "127.0.0.1" and proxy_config.behind_proxy, "tunnel server bind address and proxy mode parse")
	_context.expect_equal(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret"])).bind_address, "*", "servers listen on every interface by default")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--server", "--password=lobby-secret", "--bind=localhost"])).ok, "bind requires an IP address")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--behind-proxy"])).ok, "proxy mode is server-only")
	_context.expect_true(CommandLineConfig.parse(PackedStringArray(["--bot-client=Tunnel", "--password=test-lobby", "--host=wss://game.example.com"])).ok, "clients accept a wss:// host")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--bot-client=Tunnel", "--password=test-lobby", "--host=https://game.example.com"])).ok, "non-WebSocket URL schemes are rejected")
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

	var filtered_tests := CommandLineConfig.parse(PackedStringArray(["--run-tests", "--test-filter=input_profile"]))
	_context.expect_true(filtered_tests.ok and filtered_tests.test_filter == "input_profile", "test filter parses with --run-tests")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--test-filter=input_profile"])).ok, "test filter is only valid with --run-tests")
	_context.expect_false(CommandLineConfig.parse(PackedStringArray(["--run-tests", "--test-filter="])).ok, "empty test filter is rejected")

	var invalid_port := CommandLineConfig.parse(PackedStringArray(["--server", "--port=80"]))
	_context.expect_true(not invalid_port.ok, "privileged server port is rejected")
	_context.expect_equal(invalid_port.get("exit_code"), 2, "invalid arguments use exit code 2")
	var missing_password := CommandLineConfig.parse(PackedStringArray(["--server"]))
	_context.expect_false(missing_password.ok, "network hosts cannot start without a lobby password")

	var conflicting_modes := CommandLineConfig.parse(
		PackedStringArray(["--server", "--bot-client=Conflict"])
	)
	_context.expect_true(not conflicting_modes.ok, "conflicting startup modes are rejected")
