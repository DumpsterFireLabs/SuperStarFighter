extends Node

var _context := TestContext.new()


func _ready() -> void:
	_run_foundation_tests()
	CardStatTests.run(_context)
	ClientDraftPresentationTests.run(_context, self)
	DraftManagerTests.run(_context)
	MatchStateMachineTests.run(_context)
	CombatSystemTests.run(_context)
	NetworkProtocolTests.run(_context)
	MatchCoordinatorTests.run(_context)
	PresentationSystemTests.run(_context, self)
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	if configuration.get("force_test_failure", false):
		_context.expect_true(false, "forced failure proves the nonzero exit path")
	print("TEST_SUMMARY passed=%d failed=%d" % [_context.passed, _context.failed])
	print("SSF_MODE_READY=tests")
	get_tree().quit(0 if _context.failed == 0 else 1)


func _run_foundation_tests() -> void:
	_context.expect_equal(GameConstants.PROTOCOL_VERSION, 6, "protocol version is pinned")
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
		PackedStringArray(["--server", "--host=localhost", "--port=7123", "--max-players=16", "--rounds-to-win=4"])
	)
	_context.expect_true(server_config.ok, "valid server arguments parse")
	_context.expect_equal(server_config.get("mode"), "server", "server mode is selected")
	_context.expect_equal(server_config.get("port"), 7123, "custom port parses")
	_context.expect_equal(server_config.get("max_players"), 16, "custom player limit parses")
	_context.expect_equal(server_config.get("rounds_to_win"), 4, "custom round target parses")
	_context.expect_equal(server_config.get("host"), "localhost", "custom network host parses")
	var match_test_config := CommandLineConfig.parse(PackedStringArray([
		"--server",
		"--test-fast-match",
		"--test-match-seed=4242",
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
	]))
	_context.expect_true(malicious_bot_config.ok, "malformed-traffic test bot mode parses")
	var conflicting_traffic := CommandLineConfig.parse(PackedStringArray([
		"--bot-client=ConflictProbe",
		"--bot-malformed-input",
		"--bot-excessive-input",
	]))
	_context.expect_false(conflicting_traffic.ok, "malicious traffic modes are mutually exclusive")
	var soak_server_config := CommandLineConfig.parse(PackedStringArray([
		"--server",
		"--test-server-duration=600",
	]))
	_context.expect_true(soak_server_config.ok, "ten-minute soak duration parses")
	var invalid_protocol_override := CommandLineConfig.parse(PackedStringArray([
		"--server",
		"--test-protocol-version=999",
	]))
	_context.expect_false(invalid_protocol_override.ok, "protocol override is restricted to test bots")
	var invalid_host := CommandLineConfig.parse(PackedStringArray([
		"--bot-client=BadHost",
		"--host=not a host",
	]))
	_context.expect_false(invalid_host.ok, "hostnames containing spaces are rejected")

	var invalid_port := CommandLineConfig.parse(PackedStringArray(["--server", "--port=80"]))
	_context.expect_true(not invalid_port.ok, "privileged server port is rejected")
	_context.expect_equal(invalid_port.get("exit_code"), 2, "invalid arguments use exit code 2")

	var conflicting_modes := CommandLineConfig.parse(
		PackedStringArray(["--server", "--bot-client=Conflict"])
	)
	_context.expect_true(not conflicting_modes.ok, "conflicting startup modes are rejected")
