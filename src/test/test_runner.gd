extends Node

var _context := TestContext.new()


func _ready() -> void:
	_run_foundation_tests()
	CardStatTests.run(_context)
	DraftManagerTests.run(_context)
	MatchStateMachineTests.run(_context)
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	if configuration.get("force_test_failure", false):
		_context.expect_true(false, "forced failure proves the nonzero exit path")
	print("TEST_SUMMARY passed=%d failed=%d" % [_context.passed, _context.failed])
	print("SSF_MODE_READY=tests")
	get_tree().quit(0 if _context.failed == 0 else 1)


func _run_foundation_tests() -> void:
	_context.expect_equal(GameConstants.PROTOCOL_VERSION, 1, "protocol version is pinned")
	_context.expect_equal(GameConstants.PHYSICS_TICKS_PER_SECOND, 60, "physics tick rate is pinned")
	_context.expect_equal(GameConstants.DEFAULT_MAX_PLAYERS, 32, "default player capacity is pinned")
	_context.expect_equal(Engine.physics_ticks_per_second, 60, "project physics tick rate matches shared constants")

	var required_actions: Array[StringName] = [
		&"move_up",
		&"move_down",
		&"move_left",
		&"move_right",
		&"fire",
		&"shield",
		&"scoreboard",
		&"pause_overlay",
		&"draft_1",
		&"draft_2",
		&"draft_3",
		&"draft_4",
		&"draft_5",
	]
	for action in required_actions:
		_context.expect_true(InputMap.has_action(action), "input action %s exists" % action)

	var startup_scenes: Array[String] = [
		"res://scenes/client/client_main.tscn",
		"res://scenes/server/server_main.tscn",
		"res://scenes/test/bot_client_main.tscn",
		"res://scenes/test/test_runner.tscn",
	]
	for scene_path in startup_scenes:
		_context.expect_true(ResourceLoader.exists(scene_path), "startup scene %s exists" % scene_path)

	var server_config := CommandLineConfig.parse(
		PackedStringArray(["--server", "--port=7123", "--max-players=16", "--rounds-to-win=4"])
	)
	_context.expect_true(server_config.ok, "valid server arguments parse")
	_context.expect_equal(server_config.get("mode"), "server", "server mode is selected")
	_context.expect_equal(server_config.get("port"), 7123, "custom port parses")
	_context.expect_equal(server_config.get("max_players"), 16, "custom player limit parses")
	_context.expect_equal(server_config.get("rounds_to_win"), 4, "custom round target parses")

	var invalid_port := CommandLineConfig.parse(PackedStringArray(["--server", "--port=80"]))
	_context.expect_true(not invalid_port.ok, "privileged server port is rejected")
	_context.expect_equal(invalid_port.get("exit_code"), 2, "invalid arguments use exit code 2")

	var conflicting_modes := CommandLineConfig.parse(
		PackedStringArray(["--server", "--bot-client=Conflict"])
	)
	_context.expect_true(not conflicting_modes.ok, "conflicting startup modes are rejected")
