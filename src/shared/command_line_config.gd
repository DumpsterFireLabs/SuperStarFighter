class_name CommandLineConfig
extends RefCounted


static func parse(arguments: PackedStringArray, dedicated_server_feature: bool = false) -> Dictionary:
	var result := {
		"ok": true,
		"exit_code": 0,
		"error": "",
		"mode": "server" if dedicated_server_feature else "client",
		"port": GameConstants.DEFAULT_PORT,
		"max_players": GameConstants.DEFAULT_MAX_PLAYERS,
		"rounds_to_win": GameConstants.DEFAULT_ROUNDS_TO_WIN,
		"auto_start": false,
		"bot_name": "",
		"force_test_failure": false,
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

