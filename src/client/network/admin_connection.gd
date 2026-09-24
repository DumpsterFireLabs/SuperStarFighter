class_name AdminConnection
extends Node

signal authenticated
signal response_received(response: Dictionary)
signal connection_failed(message: String)

var _peer := StreamPeerTCP.new()
var _state: String = "disconnected"
var _password: String = ""
var _buffer := PackedByteArray()
var _started_at: float = 0.0
var _last_activity: float = 0.0
var _pending: bool = false


func _ready() -> void:
	set_process(false)


func connect_local(port: int, password: String) -> Error:
	disconnect_admin()
	if port < 1024 or port > 65535 or not NetworkProtocol.is_valid_admin_password(password):
		return ERR_INVALID_PARAMETER
	_password = password
	_started_at = Time.get_ticks_msec() / 1000.0
	_last_activity = _started_at
	var error := _peer.connect_to_host("127.0.0.1", port)
	if error != OK:
		disconnect_admin()
		return error
	_state = "challenge"
	set_process(true)
	return OK


func disconnect_admin() -> void:
	set_process(false)
	_peer.disconnect_from_host()
	_state = "disconnected"
	_password = ""
	_buffer.clear()
	_pending = false


func is_authenticated() -> bool:
	return _state == "ready"


func send_command(request: Dictionary) -> bool:
	if _state != "ready" or _pending:
		return false
	if not _send(request):
		return false
	_pending = true
	return true


func _process(_delta: float) -> void:
	_peer.poll()
	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		_fail("Admin connection closed.")
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _state != "ready" and now - _started_at > NetworkProtocol.ADMIN_AUTH_TIMEOUT_SECONDS:
		_fail("Admin authentication timed out.")
		return
	if _pending and now - _last_activity > 10.0:
		_fail("Admin command timed out.")
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	if available + _buffer.size() > NetworkProtocol.ADMIN_MAX_RESPONSE_BYTES:
		_fail("Admin response is too large.")
		return
	var read_result := _peer.get_data(available)
	if int(read_result[0]) != OK:
		_fail("Could not read admin response.")
		return
	_buffer.append_array(read_result[1] as PackedByteArray)
	while true:
		var newline := _buffer.find(10)
		if newline < 0:
			break
		var line := _buffer.slice(0, newline).get_string_from_utf8()
		_buffer = _buffer.slice(newline + 1)
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			_fail("Invalid admin response.")
			return
		_handle_response(parsed as Dictionary)
		if _state == "disconnected":
			return


func _handle_response(response: Dictionary) -> void:
	match _state:
		"challenge":
			var challenge := String(response.get("challenge", ""))
			if String(response.get("event", "")) != "challenge" or not NetworkProtocol.is_valid_auth_challenge(challenge):
				_fail("Invalid admin challenge.")
				return
			var proof := NetworkProtocol.admin_password_proof(challenge, _password)
			_password = ""
			if not _send({"command": "authenticate", "proof": proof}):
				_fail("Could not send admin proof.")
				return
			_state = "authentication"
		"authentication":
			if not bool(response.get("ok", false)) or String(response.get("event", "")) != "authenticated":
				_fail("Admin authentication failed.")
				return
			_state = "ready"
			authenticated.emit()
		"ready":
			_pending = false
			response_received.emit(response)


func _send(request: Dictionary) -> bool:
	var encoded := (JSON.stringify(request) + "\n").to_utf8_buffer()
	if encoded.size() > NetworkProtocol.ADMIN_MAX_MESSAGE_BYTES:
		return false
	_last_activity = Time.get_ticks_msec() / 1000.0
	return _peer.put_data(encoded) == OK


func _fail(message: String) -> void:
	disconnect_admin()
	connection_failed.emit(message)
