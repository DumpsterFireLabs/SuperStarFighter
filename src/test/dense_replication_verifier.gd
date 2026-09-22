extends SceneTree

## 32 real, independently admitted ENet clients; Python counts proxy datagrams.
var server: NetworkBridge
var clients: Array[NetworkBridge] = []
var recovered: Dictionary = {}
var running := false
var tick := 0

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
	var port := 17880
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="): port = int(argument.get_slice("=", 1))
	server = _runtime("Server")
	if server.start_server({"port": port, "max_players": 32, "ban_file": "", "lobby_password": "dense-fixture"}) != OK:
		push_error("Dense failure: " + server.last_error)
		quit(1)
		return
	for index in 32:
		var client := _runtime("Client%d" % index)
		clients.append(client)
		client.client_projectile_correction_received.connect(func(decoded: Dictionary) -> void:
			if bool(decoded.get("complete_snapshot", false)):
				recovered[index] = (decoded.get("spawned", []) as Array).size()
		)
		client.start_client("127.0.0.1", port + 1, "Dense%d" % index, GameConstants.PROTOCOL_VERSION, "dense-fixture")
	var deadline := Time.get_ticks_msec() + 15000
	while server.lobby.human_count() < 32 and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	if server.lobby.human_count() != 32:
		push_error("dense admission failed")
		push_error("Dense failure: " + server.last_error)
		quit(1)
		return
	server.set_physics_process(false)
	var stats := CombatStats.create_base()
	for client in clients: server.world.add_peer(client.local_peer_id, stats)
	var peers := server.lobby.human_peer_ids_view()
	for index in 1024:
		var projectile := ProjectileState.create(index + 1, peers[index / 32], index, Vector2(700 + index % 32, 700 + index / 32), 0, stats)
		server.world.projectile_registry.add(projectile)
	server.lobby.match_active = true
	server.replication.reset_outbound_bytes()
	running = true
	print("DENSE_MEASUREMENT_BEGIN")
	await create_timer(5.0).timeout
	running = false
	var all_complete := recovered.size() == 32
	for count in recovered.values(): all_complete = all_complete and int(count) == 1024
	print("SSF_DENSE_RESULT=" + JSON.stringify({"passed": all_complete, "clients": clients.size(), "recovered": recovered, "ticks": tick, "payload_bytes": server.replication.outbound_bytes(), "payload": server.replication.payload_metrics()}))
	for client in clients: client.stop()
	server.stop()
	quit(0 if all_complete else 1)

func _physics_process(_delta: float) -> bool:
	if running:
		tick += 1
		server.world.server_tick = tick
		server.replication.replicate_tick(tick, server.lobby, server.world)
	return false
