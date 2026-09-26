extends SceneTree

## Real TCP clients sharing one source address, as with an internet NAT.
var server: NetworkBridge
var clients: Array[NetworkBridge] = []
var rejections: Array[Dictionary] = []
var admissions: int = 0
var delay_ms: int = 150
var port: int = 17940


func _initialize() -> void:
	_run.call_deferred()


func _runtime(label: String) -> NetworkBridge:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var main := Node.new()
	main.name = "Main"
	branch.add_child(main)
	var bridge := NetworkBridge.new()
	bridge.name = "NetworkBridge"
	main.add_child(bridge)
	return bridge


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--delay-ms="): delay_ms = clampi(int(arg.get_slice("=", 1)), 0, 300)
		if arg.begins_with("--port="): port = int(arg.get_slice("=", 1))
	server = _runtime("Server")
	# Delay challenge transmission to keep simultaneous handshakes in flight.
	# Packets still use production RPC/TCP; this is not a WAN latency claim.
	for connection in server.session.challenge_requested.get_connections():
		server.session.challenge_requested.disconnect(connection.callable)
	server.session.challenge_requested.connect(_challenge)
	for index in 32:
		var client := _runtime("Client%d" % index)
		clients.append(client)
		client.client_rejected.connect(func(reason: StringName, _message: String) -> void: rejections.append({"client": index, "reason": reason}))
		client.client_connected.connect(func(_id: int) -> void: admissions += 1)
		client.client_match_event_received.connect(func(kind: StringName, _tick: int, payload: Dictionary) -> void:
			if kind == &"DRAFT_OFFER": client.send_card_selection(payload.offer_token, payload.card_ids[0])
		)
	for cycle in 3:
		if server.start_server({"port": port, "max_players": 32, "ban_file": "", "lobby_password": "burst-fixture", "test_match_seed": 920641}) != OK:
			_fail("server start")
			return
		var before := admissions
		var began := Time.get_ticks_msec()
		for index in clients.size():
			clients[index].start_client("127.0.0.1", port, "Burst%02d" % index, GameConstants.PROTOCOL_VERSION, "burst-fixture")
		if not await _until(func() -> bool: return admissions - before == 32 or not rejections.is_empty(), 12.0) or not rejections.is_empty():
			_fail("initial admission: %d/32, rejected=%s" % [admissions - before, rejections])
			return
		for client in clients: client.send_ready_state(true)
		if not await _until(func() -> bool: return server.lobby.all_humans_ready(), 5.0):
			_fail("ready")
			return
		for client in clients:
			if client.local_peer_id == server.lobby.leader_id: client.send_start_match()
		if not await _until(func() -> bool: return server.match_coordinator != null and server.match_coordinator.controls_enabled(), 12.0):
			_fail("active heat")
			return
		var replaced_id: int = clients.back().local_peer_id
		clients.back().stop()
		if not await _until(func() -> bool: return not server.lobby.players.has(replaced_id), 5.0):
			_fail("combat disconnect cleanup")
			return
		clients.back().start_client("127.0.0.1", port, "LatePilot", GameConstants.PROTOCOL_VERSION, "burst-fixture")
		if not await _until(func() -> bool: return clients.back().local_peer_id != 0, 5.0):
			_fail("reconnect")
			return
		if not server.lobby.players[clients.back().local_peer_id].spectator:
			_fail("reconnect gained participant authority")
			return
		print("SSF_ADMISSION_CYCLE=%s" % JSON.stringify({"cycle": cycle, "admitted": 32, "elapsed_ms": Time.get_ticks_msec() - began, "late_spectator": true, "pending_handshakes": server.session._pending_handshakes.size()}))
		for client in clients: client.stop()
		if not await _until(func() -> bool: return server.lobby.human_count() == 0, 5.0):
			_fail("cohort disconnect cleanup")
			return
		server.stop()
	print("SSF_ADMISSION_OK=%s" % JSON.stringify({"cycles": 3, "initial_admissions": 96, "late_spectators": 3, "rejections": rejections.size(), "challenge_delay_ms": delay_ms}))
	quit(0)


func _challenge(peer_id: int, challenge: String) -> void:
	if delay_ms > 0: await create_timer(delay_ms / 1000.0).timeout
	if server.role == NetworkBridge.Role.SERVER and server.session._pending_handshakes.has(peer_id):
		server.authentication_challenge.rpc_id(peer_id, challenge)


func _until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await process_frame
	return condition.call()


func _fail(message: String) -> void:
	printerr("SSF_ADMISSION_FAILED=" + message)
	for client in clients: client.stop()
	if server != null: server.stop()
	quit(1)
