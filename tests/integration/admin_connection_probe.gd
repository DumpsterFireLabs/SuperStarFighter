extends SceneTree

const AdminConnectionScript = preload("res://src/client/network/admin_connection.gd")

var connection: AdminConnection
var _step: String = ""


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var port := 0
	var secret_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--admin-port="):
			port = int(argument.trim_prefix("--admin-port="))
		elif argument.begins_with("--admin-password-file="):
			secret_path = argument.trim_prefix("--admin-password-file=")
	if port == 0 or secret_path.is_empty():
		_fail("Missing probe configuration.")
		return
	var file := FileAccess.open(secret_path, FileAccess.READ)
	if file == null:
		_fail("Could not read probe credential.")
		return
	var password := file.get_as_text().strip_edges()
	connection = AdminConnectionScript.new()
	root.add_child(connection)
	connection.authenticated.connect(_authenticated)
	connection.response_received.connect(_response)
	connection.connection_failed.connect(_fail)
	if connection.connect_local(port, password) != OK:
		_fail("Could not connect to the local admin service.")
		return
	create_timer(12.0).timeout.connect(func() -> void:
		if _step != "done":
			_fail("Admin probe timed out.")
	)


func _authenticated() -> void:
	_step = "status"
	if not connection.send_command({"command": "status"}):
		_fail("Could not request admin status.")


func _response(response: Dictionary) -> void:
	if _step == "invalid_kick":
		if bool(response.get("ok", false)):
			_fail("Malformed player ID was accepted.")
			return
		_step = "players"
		if not connection.send_command({"command": "players"}):
			_fail("Could not request players.")
		return
	if not bool(response.get("ok", false)):
		_fail("Admin command was rejected.")
		return
	if _step == "status":
		if not response.has("server_tick") or not response.has("lobby"):
			_fail("Status omitted expected fields.")
			return
		_step = "invalid_kick"
		if not connection.send_command({"command": "kick", "peer_id": []}):
			_fail("Could not send malformed-command probe.")
	elif _step == "players":
		if not response.get("players", null) is Array:
			_fail("Players response is malformed.")
			return
		_step = "unicode_setting"
		_send_fragmented_setting()
	elif _step == "unicode_setting":
		_step = "unicode_status"
		if not connection.send_command({"command": "status"}):
			_fail("Could not verify the Unicode setting.")
	elif _step == "unicode_status":
		if String(response.get("server_name", "")) != "Admin Å Test":
			_fail("A split UTF-8 command was not preserved.")
			return
		_step = "done"
		connection.disconnect_admin()
		print("ADMIN_CLIENT_PROBE=passed")
		quit(0)


func _send_fragmented_setting() -> void:
	var packet := (JSON.stringify({"command": "set", "setting": "server_name", "value": "Admin Å Test"}) + "\n").to_utf8_buffer()
	var split_index := packet.find(0xc3)
	if split_index < 0 or connection._peer.put_data(packet.slice(0, split_index + 1)) != OK:
		_fail("Could not start the split UTF-8 command.")
		return
	await create_timer(0.1).timeout
	if connection._peer.put_data(packet.slice(split_index + 1)) != OK:
		_fail("Could not finish the split UTF-8 command.")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
