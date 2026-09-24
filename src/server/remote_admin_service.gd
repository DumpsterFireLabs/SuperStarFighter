class_name RemoteAdminService
extends Node

const AuthenticationAttemptLimiterScript = preload("res://src/shared/network/authentication_attempt_limiter.gd")

signal shutdown_requested

var _server := TCPServer.new()
var _bridge: NetworkBridge
var _password: String = ""
var _clients: Dictionary = {}
var _next_client_id: int = 1
var _authentication_attempt_limiter := AuthenticationAttemptLimiterScript.new(
	NetworkProtocol.ADMIN_AUTH_FAILURE_LIMIT,
	NetworkProtocol.ADMIN_AUTH_FAILURE_WINDOW_SECONDS,
	NetworkProtocol.ADMIN_AUTH_COOLDOWN_SECONDS
)


func start(port: int, password: String, bridge: NetworkBridge) -> Error:
	stop()
	if port == 0:
		return OK
	if not NetworkProtocol.is_valid_admin_password(password) or bridge == null:
		return ERR_INVALID_PARAMETER
	var error := _server.listen(port, "127.0.0.1")
	if error != OK:
		return error
	_bridge = bridge
	_password = password
	set_process(true)
	_admin_log("admin_started", {"bind": "127.0.0.1", "port": port})
	return OK


func stop() -> void:
	set_process(false)
	for client_id in _clients.keys():
		_close_client(int(client_id))
	_clients.clear()
	_server.stop()
	_password = ""
	_bridge = null
	_authentication_attempt_limiter.clear()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			break
		if _clients.size() >= NetworkProtocol.ADMIN_MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		_accept_client(peer)
	for client_value in _clients.keys():
		_poll_client(int(client_value))


func _accept_client(peer: StreamPeerTCP) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _authentication_attempt_limiter.is_blocked("loopback-admin", now):
		_admin_log("admin_connection_rate_limited", {})
		peer.disconnect_from_host()
		return
	var client_id := _next_client_id
	_next_client_id += 1
	var challenge := Crypto.new().generate_random_bytes(NetworkProtocol.AUTH_CHALLENGE_BYTES).hex_encode()
	_clients[client_id] = {
		"peer": peer,
		"buffer": PackedByteArray(),
		"challenge": challenge,
		"authenticated": false,
		"auth_failures": 0,
		"connected_at": now,
		"last_activity": now,
		"window_start": now,
		"request_count": 0,
	}
	_send(client_id, {"event": "challenge", "challenge": challenge})


func _poll_client(client_id: int) -> void:
	if not _clients.has(client_id):
		return
	var state: Dictionary = _clients[client_id]
	var peer := state.peer as StreamPeerTCP
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_close_client(client_id)
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not bool(state.authenticated) and now - float(state.connected_at) >= NetworkProtocol.ADMIN_AUTH_TIMEOUT_SECONDS:
		_close_client(client_id)
		return
	if bool(state.authenticated) and now - float(state.last_activity) >= NetworkProtocol.ADMIN_IDLE_TIMEOUT_SECONDS:
		_admin_log("admin_idle_timeout", {"client_id": client_id})
		_close_client(client_id)
		return
	var available := peer.get_available_bytes()
	if available <= 0:
		return
	if available > NetworkProtocol.ADMIN_MAX_MESSAGE_BYTES:
		_close_client(client_id)
		return
	var read_result := peer.get_data(available)
	if int(read_result[0]) != OK:
		_close_client(client_id)
		return
	var buffer := state.buffer as PackedByteArray
	buffer.append_array(read_result[1] as PackedByteArray)
	if buffer.size() > NetworkProtocol.ADMIN_MAX_MESSAGE_BYTES:
		_close_client(client_id)
		return
	state.buffer = buffer
	_clients[client_id] = state
	while true:
		var newline := buffer.find(10)
		if newline < 0:
			break
		var line := buffer.slice(0, newline).get_string_from_utf8().strip_edges()
		buffer = buffer.slice(newline + 1)
		state.buffer = buffer
		_clients[client_id] = state
		if not line.is_empty():
			_handle_line(client_id, line)
			if not _clients.has(client_id):
				return


func _handle_line(client_id: int, line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if not parsed is Dictionary:
		_send(client_id, {"ok": false, "error": "Command must be one JSON object."})
		return
	var request := parsed as Dictionary
	var state: Dictionary = _clients[client_id]
	if not bool(state.authenticated):
		_authenticate(client_id, request)
		return
	var now := Time.get_ticks_msec() / 1000.0
	state.last_activity = now
	if now - float(state.window_start) >= 1.0:
		state.window_start = now
		state.request_count = 0
	state.request_count = int(state.request_count) + 1
	_clients[client_id] = state
	if int(state.request_count) > NetworkProtocol.ADMIN_MAX_REQUESTS_PER_SECOND:
		_close_client(client_id)
		return
	var response := _execute(request)
	if request.has("request_id"):
		response.request_id = request.request_id
	_send(client_id, response)
	if bool(response.get("shutdown", false)):
		call_deferred("_emit_shutdown")


func _authenticate(client_id: int, request: Dictionary) -> void:
	var state: Dictionary = _clients[client_id]
	var valid := String(request.get("command", "")) == "authenticate"
	var supplied := String(request.get("proof", ""))
	var expected := NetworkProtocol.admin_password_proof(String(state.challenge), _password)
	valid = valid and NetworkProtocol.is_valid_auth_proof(supplied)
	valid = valid and NetworkProtocol.constant_time_string_equal(supplied, expected)
	if valid:
		state.authenticated = true
		state.challenge = ""
		_clients[client_id] = state
		_send(client_id, {"ok": true, "event": "authenticated"})
		_admin_log("admin_authenticated", {"client_id": client_id})
		return
	state.auth_failures = int(state.auth_failures) + 1
	_clients[client_id] = state
	var rate_limited := _authentication_attempt_limiter.register_failure("loopback-admin", Time.get_ticks_msec() / 1000.0)
	_admin_log("admin_auth_failed", {"client_id": client_id, "failures": int(state.auth_failures)})
	_send(client_id, {"ok": false, "error": "Authentication failed."})
	if rate_limited or int(state.auth_failures) >= 3:
		_close_client(client_id)


func _execute(request: Dictionary) -> Dictionary:
	if not request.get("command", null) is String:
		return {"ok": false, "error": "A text command is required."}
	var command := String(request.command)
	var result: Dictionary
	match command:
		"status":
			result = _bridge.operator_status()
		"players":
			result = _bridge.operator_players()
		"kick":
			result = _bridge.operator_kick(int(request.peer_id), false) if _valid_peer_id(request.get("peer_id")) else {"ok": false, "error": "peer_id requires a positive integer."}
		"ban":
			result = _bridge.operator_kick(int(request.peer_id), true) if _valid_peer_id(request.get("peer_id")) else {"ok": false, "error": "peer_id requires a positive integer."}
		"block":
			result = _bridge.operator_block_source(String(request.source)) if request.get("source", null) is String else {"ok": false, "error": "source requires text."}
		"unblock":
			result = _bridge.operator_unblock_source(String(request.source)) if request.get("source", null) is String else {"ok": false, "error": "source requires text."}
		"set":
			result = _bridge.operator_set_setting(String(request.setting), request.get("value")) if request.get("setting", null) is String else {"ok": false, "error": "setting requires text."}
		"set_password":
			if not request.get("password", null) is String:
				result = {"ok": false, "error": "password requires text."}
			else:
				result = _bridge.operator_set_lobby_password(String(request.password))
		"restart_match":
			result = _bridge.operator_restart_match()
		"shutdown":
			result = {"ok": true, "shutdown": true}
		_:
			result = {"ok": false, "error": "Unknown admin command."}
	_admin_log("admin_command", {
		"command": command,
		"ok": bool(result.get("ok", false)),
		"peer_id": int(request.peer_id) if _valid_peer_id(request.get("peer_id")) else 0,
		"setting": String(request.setting) if request.get("setting", null) is String else "",
	})
	return result


static func _valid_peer_id(value: Variant) -> bool:
	return (value is int and value > 1 and value <= 2_147_483_647) or (value is float and is_finite(value) and value > 1.0 and value <= 2_147_483_647.0 and value == floor(value))


func _emit_shutdown() -> void:
	shutdown_requested.emit()


func _send(client_id: int, payload: Dictionary) -> void:
	if not _clients.has(client_id):
		return
	var peer := (_clients[client_id] as Dictionary).peer as StreamPeerTCP
	var encoded := (JSON.stringify(payload) + "\n").to_utf8_buffer()
	if encoded.size() > NetworkProtocol.ADMIN_MAX_RESPONSE_BYTES:
		_admin_log("admin_response_rejected", {"client_id": client_id, "bytes": encoded.size()})
		encoded = (JSON.stringify({"ok": false, "error": "Admin response exceeded the safety limit."}) + "\n").to_utf8_buffer()
	if peer.put_data(encoded) != OK:
		_close_client(client_id)


func _close_client(client_id: int) -> void:
	if not _clients.has(client_id):
		return
	var peer := (_clients[client_id] as Dictionary).peer as StreamPeerTCP
	peer.disconnect_from_host()
	_clients.erase(client_id)


static func _admin_log(event_name: String, fields: Dictionary) -> void:
	var payload := fields.duplicate(true)
	payload.event = event_name
	payload.timestamp = Time.get_datetime_string_from_system(true)
	print(JSON.stringify(payload))
