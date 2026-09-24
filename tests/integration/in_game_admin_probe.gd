extends SceneTree

const HostedSessionScript = preload("res://src/client/network/hosted_session.gd")
const ADMIN_SECRET := "in-game-admin-probe-2026"

var hosted: Node
var client: NetworkBridge
var _step: String = ""
var _challenge: String = ""
var _sequence: int = 0


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	hosted = HostedSessionScript.new()
	hosted.name = "HostedSession"
	root.add_child(hosted)
	var port := 19000 + int(Time.get_ticks_msec() % 10000)
	var error: Error = hosted.start({
		"port": port,
		"server_name": "Admin Probe",
		"lobby_password": "probe-lobby-secret",
		"admin_password": ADMIN_SECRET,
		"max_players": 4,
		"rounds_to_win": 3,
	})
	if error != OK:
		_fail("Could not start integration server.")
		return
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	client = NetworkBridge.new()
	client.name = "NetworkBridge"
	main.add_child(client)
	client.client_connected.connect(_connected)
	client.client_admin_response.connect(_response)
	client.client_connection_lost.connect(_fail)
	if client.start_client("127.0.0.1", port, "Admin Tester", GameConstants.PROTOCOL_VERSION, "probe-lobby-secret") != OK:
		_fail("Could not join integration server.")
		return
	create_timer(12.0).timeout.connect(func() -> void:
		if _step != "done":
			_fail("In-game admin probe timed out at %s." % _step)
	)


func _connected(_peer_id: int) -> void:
	_step = "unauthorized"
	client.send_admin_command({"command": "status"})


func _response(response: Dictionary) -> void:
	match _step:
		"unauthorized":
			if bool(response.get("ok", false)):
				_fail("Unauthenticated player ran an admin command.")
				return
			_step = "challenge"
			client.send_admin_challenge_request()
		"challenge":
			var challenge := String(response.get("challenge", ""))
			if String(response.get("event", "")) != "challenge" or not NetworkProtocol.is_valid_auth_challenge(challenge):
				_fail("Server did not issue a valid admin challenge.")
				return
			_challenge = challenge
			_step = "authentication"
			client.send_admin_proof(NetworkProtocol.admin_password_proof(challenge, ADMIN_SECRET))
		"authentication":
			if not bool(response.get("ok", false)) or String(response.get("event", "")) != "authenticated":
				_fail("Valid admin password did not authenticate.")
				return
			_step = "status"
			_admin_command({"command": "status"})
		"status":
			if not bool(response.get("ok", false)) or String(response.get("server_name", "")) != "Admin Probe":
				_fail("Authenticated status failed.")
				return
			_step = "setting"
			_admin_command({"command": "set", "setting": "rounds_to_win", "value": 4})
		"setting":
			if not bool(response.get("ok", false)) or hosted.server_bridge.lobby.config.rounds_to_win != 4:
				_fail("Authenticated setting did not reach server authority.")
				return
			_step = "idle_restart"
			_admin_command({"command": "restart_match"})
		"idle_restart":
			if bool(response.get("ok", false)):
				_fail("Idle match restart should be rejected.")
				return
			_step = "revoked"
			client.send_admin_revoke()
			client.send_admin_command({"command": "status"})
		"revoked":
			if bool(response.get("ok", false)):
				_fail("Locked player retained admin rights.")
				return
			_step = "done"
			print("IN_GAME_ADMIN_PROBE=passed")
			client.stop()
			hosted.stop()
			quit(0)
		_:
			_fail("Unexpected admin response.")


func _admin_command(request: Dictionary) -> void:
	_sequence += 1
	client.send_admin_command(request, _sequence, NetworkProtocol.admin_command_signature(_challenge, ADMIN_SECRET, _sequence, request))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
