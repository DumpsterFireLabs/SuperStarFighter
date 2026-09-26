class_name CommandLineConfig
extends RefCounted

const LOBBY_PASSWORD_ENVIRONMENT_VARIABLE: String = "SSF_LOBBY_PASSWORD"
const ADMIN_PASSWORD_ENVIRONMENT_VARIABLE: String = "SSF_ADMIN_PASSWORD"


static func parse(arguments: PackedStringArray, dedicated_server_feature: bool = false) -> Dictionary:
	var result := {
		"ok": true,
		"exit_code": 0,
		"error": "",
		"mode": "server" if dedicated_server_feature else "client",
		"port": GameConstants.DEFAULT_PORT,
		"host": "127.0.0.1",
		"server_name": "Super Star Fighter Server",
		"lobby_password": "",
		"lobby_password_file": "",
		"admin_port": 0,
		"admin_password": "",
		"admin_password_file": "",
		"ban_file": "user://server-bans.json",
		"max_players": GameConstants.DEFAULT_MAX_PLAYERS,
		"rounds_to_win": GameConstants.DEFAULT_ROUNDS_TO_WIN,
		"auto_start": false,
		"bind_address": "*",
		"behind_proxy": false,
		"competitive_view": false,
		"window_mode_override": "",
		"bot_name": "",
		"force_test_failure": false,
		"test_protocol_version": GameConstants.PROTOCOL_VERSION,
		"has_test_protocol_override": false,
		"test_server_duration": 0,
		"test_fast_match": false,
		"test_match_seed": 0,
		"bot_passive": false,
		"bot_draft_timeout": false,
		"bot_enable_npcs": false,
		"bot_player_limit": 0,
		"bot_start_at": 0,
		"bot_randomized": false,
		"bot_malformed_input": false,
		"bot_excessive_input": false,
	}
	var explicit_modes: Array[String] = []
	var window_overrides: Array[String] = []

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
			if not NetworkProtocol.is_valid_server_address(parsed_host):
				return _error("--host requires a valid IP address or hostname (use --port for the port), or a ws:// / wss:// URL.")
			result.host = parsed_host
		elif argument.begins_with("--server-name="):
			var parsed_server_name := argument.trim_prefix("--server-name=").strip_edges()
			if not LanDiscoveryProtocol.is_valid_server_name(parsed_server_name):
				return _error("--server-name requires 1–%d printable characters." % LanDiscoveryProtocol.MAX_SERVER_NAME_LENGTH)
			result.server_name = parsed_server_name
		elif argument.begins_with("--password="):
			var parsed_password := argument.trim_prefix("--password=")
			if not NetworkProtocol.is_valid_lobby_password(parsed_password):
				return _error("--password requires 1–%d printable characters." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH)
			result.lobby_password = parsed_password
		elif argument.begins_with("--password-file="):
			var password_file := argument.trim_prefix("--password-file=").strip_edges()
			if password_file.is_empty():
				return _error("--password-file requires a readable file path.")
			result.lobby_password_file = password_file
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
		elif argument.begins_with("--admin-port="):
			var parsed_admin_port := _parse_bounded_integer(
				argument.trim_prefix("--admin-port="),
				GameConstants.MIN_PORT,
				GameConstants.MAX_PORT,
				"--admin-port"
			)
			if not parsed_admin_port.ok:
				return parsed_admin_port
			result.admin_port = parsed_admin_port.value
		elif argument.begins_with("--admin-password-file="):
			var admin_password_file := argument.trim_prefix("--admin-password-file=").strip_edges()
			if admin_password_file.is_empty():
				return _error("--admin-password-file requires a readable file path.")
			result.admin_password_file = admin_password_file
		elif argument.begins_with("--ban-file="):
			var ban_file := argument.trim_prefix("--ban-file=").strip_edges()
			if ban_file.is_empty():
				return _error("--ban-file requires a file path.")
			result.ban_file = ban_file
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
		elif argument == "--windowed":
			window_overrides.append("windowed")
		elif argument == "--fullscreen":
			window_overrides.append("fullscreen")
		elif argument == "--competitive-view":
			result.competitive_view = true
		elif argument == "--auto-start":
			result.auto_start = true
		elif argument.begins_with("--bind="):
			var parsed_bind := argument.trim_prefix("--bind=").strip_edges()
			if parsed_bind != "*" and not parsed_bind.is_valid_ip_address():
				return _error("--bind requires an IP address such as 127.0.0.1, or * for all interfaces.")
			result.bind_address = parsed_bind
		elif argument == "--behind-proxy":
			result.behind_proxy = true
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
		elif argument == "--bot-enable-npcs":
			result.bot_enable_npcs = true
		elif argument.begins_with("--bot-player-limit="):
			var parsed_bot_limit := _parse_bounded_integer(
				argument.trim_prefix("--bot-player-limit="),
				GameConstants.MIN_PLAYERS,
				GameConstants.MAX_PLAYERS,
				"--bot-player-limit"
			)
			if not parsed_bot_limit.ok:
				return parsed_bot_limit
			result.bot_player_limit = parsed_bot_limit.value
		elif argument.begins_with("--bot-start-at="):
			var parsed_start_count := _parse_bounded_integer(
				argument.trim_prefix("--bot-start-at="),
				GameConstants.MIN_PLAYERS,
				GameConstants.MAX_PLAYERS,
				"--bot-start-at"
			)
			if not parsed_start_count.ok:
				return parsed_start_count
			result.bot_start_at = parsed_start_count.value
		elif argument == "--bot-randomized":
			result.bot_randomized = true
		elif argument == "--bot-malformed-input":
			result.bot_malformed_input = true
		elif argument == "--bot-excessive-input":
			result.bot_excessive_input = true
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
				3600,
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
	if window_overrides.size() > 1:
		return _error("Choose only one window override: --windowed or --fullscreen.")
	if window_overrides.size() == 1:
		if result.mode != "client":
			return _error("--windowed and --fullscreen are only valid for the game client.")
		result.window_mode_override = window_overrides[0]
	if String(result.lobby_password).is_empty() and not String(result.lobby_password_file).is_empty():
		var loaded_password := _read_password_file(String(result.lobby_password_file))
		if not loaded_password.ok:
			return loaded_password
		result.lobby_password = loaded_password.value
	if String(result.lobby_password).is_empty():
		result.lobby_password = OS.get_environment(LOBBY_PASSWORD_ENVIRONMENT_VARIABLE)
	if String(result.admin_password).is_empty() and not String(result.admin_password_file).is_empty():
		var loaded_admin_password := _read_secret_file(String(result.admin_password_file), "--admin-password-file")
		if not loaded_admin_password.ok:
			return loaded_admin_password
		result.admin_password = loaded_admin_password.value
	if String(result.admin_password).is_empty():
		result.admin_password = OS.get_environment(ADMIN_PASSWORD_ENVIRONMENT_VARIABLE)
	if not String(result.lobby_password).is_empty() and not NetworkProtocol.is_valid_lobby_password(String(result.lobby_password)):
		return _error("The lobby password requires 1–%d printable characters." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH)
	if result.mode in ["server", "bot_client"] and String(result.lobby_password).is_empty():
		return _error("Set --password, --password-file, or %s when hosting or joining a network lobby." % LOBBY_PASSWORD_ENVIRONMENT_VARIABLE)
	if int(result.admin_port) > 0 and result.mode != "server":
		return _error("--admin-port is only valid with --server.")
	if int(result.admin_port) > 0 and int(result.admin_port) in [int(result.port), LanDiscoveryProtocol.DISCOVERY_PORT]:
		return _error("--admin-port must differ from the gameplay and LAN discovery ports.")
	if int(result.admin_port) > 0 and not NetworkProtocol.is_valid_admin_password(String(result.admin_password)):
		return _error("Set --admin-password-file or %s to %d–%d printable characters when remote administration is enabled." % [ADMIN_PASSWORD_ENVIRONMENT_VARIABLE, NetworkProtocol.MIN_ADMIN_PASSWORD_LENGTH, NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH])
	if result.mode == "server" and not String(result.admin_password).is_empty() and not NetworkProtocol.is_valid_admin_password(String(result.admin_password)):
		return _error("The in-game admin password requires %d–%d printable characters." % [NetworkProtocol.MIN_ADMIN_PASSWORD_LENGTH, NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH])
	if result.mode == "server" and not String(result.admin_password).is_empty() and String(result.admin_password) == String(result.lobby_password):
		return _error("The admin password must differ from the lobby password.")
	if result.auto_start and result.mode != "server":
		return _error("--auto-start is only valid with --server.")
	if (result.bind_address != "*" or result.behind_proxy) and result.mode != "server":
		return _error("--bind and --behind-proxy are only valid with --server.")
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
	if (result.bot_passive or result.bot_draft_timeout or result.bot_enable_npcs or result.bot_player_limit > 0 or result.bot_start_at > 0 or result.bot_randomized or result.bot_malformed_input or result.bot_excessive_input) and result.mode != "bot_client":
		return _error("Bot behavior options are only valid with --bot-client.")
	if result.bot_malformed_input and result.bot_excessive_input:
		return _error("Choose only one malicious bot traffic mode.")
	return result


static func _parse_bounded_integer(value_text: String, minimum: int, maximum: int, option: String) -> Dictionary:
	if not value_text.is_valid_int():
		return _error("%s must be an integer from %d through %d." % [option, minimum, maximum])
	var value := int(value_text)
	if value < minimum or value > maximum:
		return _error("%s must be from %d through %d." % [option, minimum, maximum])
	return {"ok": true, "value": value}


static func _read_password_file(path: String) -> Dictionary:
	return _read_secret_file(path, "--password-file")


static func _read_secret_file(path: String, option: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("%s could not read the requested file." % option)
	var value := file.get_as_text()
	while value.ends_with("\n") or value.ends_with("\r"):
		value = value.left(value.length() - 1)
	if not NetworkProtocol.is_valid_lobby_password(value):
		return _error("%s must contain 1–%d printable characters on one line." % [option, NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH])
	return {"ok": true, "value": value}


static func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"exit_code": 2,
		"error": message,
	}
