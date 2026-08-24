class_name CommandLineConfig
extends RefCounted


static func parse(arguments: PackedStringArray, dedicated_server_feature: bool = false) -> Dictionary:
	var result := {
		"ok": true,
		"exit_code": 0,
		"error": "",
		"mode": "server" if dedicated_server_feature else "client",
		"port": GameConstants.DEFAULT_PORT,
		"host": "127.0.0.1",
		"max_players": GameConstants.DEFAULT_MAX_PLAYERS,
		"rounds_to_win": GameConstants.DEFAULT_ROUNDS_TO_WIN,
		"auto_start": false,
		"bot_name": "",
		"force_test_failure": false,
		"test_protocol_version": GameConstants.PROTOCOL_VERSION,
		"has_test_protocol_override": false,
		"test_server_duration": 0,
		"test_fast_match": false,
		"test_match_seed": 0,
		"bot_passive": false,
		"bot_draft_timeout": false,
	}
	var explicit_modes: Array[String] = []

	for argument in arguments:
		if argument == "--server":
			explicit_modes.append("server")
		elif argument == "--run-tests":
			explicit_modes.append("tests")
		elif argument.begins_with("--bot-client="):
			explicit_modes.append("bot_client")
			result.bot_name = argument.trim_prefix("--bot-client=").strip_edges()
			if result.bot_name.is_empty():
				return _error("--bot-client requires a non-empty name.")
		elif argument.begins_with("--port="):
			var parsed_port := _parse_bounded_integer(
				argument.trim_prefix("--port="),
				GameConstants.MIN_PORT,
				GameConstants.MAX_PORT,
				"--port"
			)
			if not parsed_port.ok:
				return parsed_port
			result.port = parsed_port.value
		elif argument.begins_with("--host="):
			var parsed_host := argument.trim_prefix("--host=").strip_edges()
			if parsed_host.is_empty() or parsed_host.length() > 253 or parsed_host.contains(" "):
				return _error("--host requires a valid IP address or hostname.")
			result.host = parsed_host
		elif argument.begins_with("--max-players="):
			var parsed_players := _parse_bounded_integer(
				argument.trim_prefix("--max-players="),
				GameConstants.MIN_PLAYERS,
				GameConstants.MAX_PLAYERS,
				"--max-players"
			)
			if not parsed_players.ok:
				return parsed_players
			result.max_players = parsed_players.value
		elif argument.begins_with("--rounds-to-win="):
			var parsed_rounds := _parse_bounded_integer(
				argument.trim_prefix("--rounds-to-win="),
				GameConstants.MIN_ROUNDS_TO_WIN,
				GameConstants.MAX_ROUNDS_TO_WIN,
				"--rounds-to-win"
			)
			if not parsed_rounds.ok:
				return parsed_rounds
			result.rounds_to_win = parsed_rounds.value
		elif argument == "--auto-start":
			result.auto_start = true
		elif argument == "--force-test-failure":
			result.force_test_failure = true
		elif argument == "--test-fast-match":
			result.test_fast_match = true
		elif argument.begins_with("--test-match-seed="):
			var parsed_seed := _parse_bounded_integer(
				argument.trim_prefix("--test-match-seed="),
				1,
				2147483647,
				"--test-match-seed"
			)
			if not parsed_seed.ok:
				return parsed_seed
			result.test_match_seed = parsed_seed.value
		elif argument == "--bot-passive":
			result.bot_passive = true
		elif argument == "--bot-draft-timeout":
			result.bot_draft_timeout = true
		elif argument.begins_with("--test-protocol-version="):
			var parsed_protocol := _parse_bounded_integer(
				argument.trim_prefix("--test-protocol-version="),
				0,
				65535,
				"--test-protocol-version"
			)
			if not parsed_protocol.ok:
				return parsed_protocol
			result.test_protocol_version = parsed_protocol.value
			result.has_test_protocol_override = true
		elif argument.begins_with("--test-server-duration="):
			var parsed_duration := _parse_bounded_integer(
				argument.trim_prefix("--test-server-duration="),
				1,
				300,
				"--test-server-duration"
			)
			if not parsed_duration.ok:
				return parsed_duration
			result.test_server_duration = parsed_duration.value
		elif argument.begins_with("--"):
			return _error("Unknown Super Star Fighter option: %s" % argument)

	if explicit_modes.size() > 1:
		return _error("Choose only one startup mode: --server, --run-tests, or --bot-client.")
	if explicit_modes.size() == 1:
		result.mode = explicit_modes[0]
	if result.auto_start and result.mode != "server":
		return _error("--auto-start is only valid with --server.")
	if result.force_test_failure and result.mode != "tests":
		return _error("--force-test-failure is only valid with --run-tests.")
	if result.has_test_protocol_override and result.mode != "bot_client":
		return _error("--test-protocol-version is only valid with --bot-client.")
	if result.test_server_duration > 0 and result.mode != "server":
		return _error("--test-server-duration is only valid with --server.")
	if result.test_fast_match and result.mode != "server":
		return _error("--test-fast-match is only valid with --server.")
	if result.test_match_seed > 0 and result.mode != "server":
		return _error("--test-match-seed is only valid with --server.")
	if (result.bot_passive or result.bot_draft_timeout) and result.mode != "bot_client":
		return _error("Bot behavior options are only valid with --bot-client.")
	return result


static func _parse_bounded_integer(value_text: String, minimum: int, maximum: int, option: String) -> Dictionary:
	if not value_text.is_valid_int():
		return _error("%s must be an integer from %d through %d." % [option, minimum, maximum])
	var value := int(value_text)
	if value < minimum or value > maximum:
		return _error("%s must be from %d through %d." % [option, minimum, maximum])
	return {"ok": true, "value": value}


static func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"exit_code": 2,
		"error": message,
	}
