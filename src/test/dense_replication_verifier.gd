extends SceneTree

## 32 real, independently admitted TCP clients; Python counts proxy stream bytes.
var server: NetworkBridge
var clients: Array[NetworkBridge] = []
var recovered: Dictionary = {}
var running := false
var tick := 0
var recovery_rounds: Dictionary = {}
var last_recovery_ticks: Dictionary = {}
var snapshots: Dictionary = {}
var mutation_tick := -1
var exercise_recovery := false
var disconnected := false
var max_pending := 0
var first_recovery_ticks: Dictionary = {}
var max_inflight := 0

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
		exercise_recovery = exercise_recovery or argument == "--exercise-recovery"
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
				var entries: Array = decoded.get("spawned", [])
				var ids: Array[int] = []
				for projectile: ProjectileState in entries: ids.append(projectile.projectile_id)
				ids.sort()
				var expected: Array[int] = []
				var mutated := mutation_tick >= 0 and int(decoded.server_tick) >= mutation_tick
				for id in range(2 if mutated else 1, 1026 if mutated else 1025): expected.append(id)
				recovered[index] = ids == expected and (mutation_tick < 0 or mutated)
				last_recovery_ticks[index] = int(decoded.server_tick)
				recovery_rounds[index] = int(recovery_rounds.get(index, 0)) + 1
				if not first_recovery_ticks.has(index): first_recovery_ticks[index] = tick
		)
		client.client_snapshot_received.connect(func(_decoded: Dictionary) -> void: snapshots[index] = int(snapshots.get(index, 0)) + 1)
		client.client_connection_lost.connect(func(_reason: String) -> void: disconnected = true)
		client.start_client("127.0.0.1", port + 1, "Dense%d" % index, GameConstants.PROTOCOL_VERSION, "dense-fixture")
	var deadline := Time.get_ticks_msec() + 30000
	while not _all_admitted() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	if not _all_admitted():
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
	await create_timer(12.0 if exercise_recovery else 5.0).timeout
	var initial_complete := recovered.size() == 32 and not false in recovered.values()
	print("SSF_DENSE_INITIAL=" + JSON.stringify({"first_recovery_ticks": first_recovery_ticks, "recovered": recovered, "max_inflight": max_inflight}))
	if exercise_recovery:
		# Deliberately omit a delta: full recovery must repair both missing and
		# obsolete membership, not merely report the right projectile count.
		mutation_tick = tick + 1
		server.world.projectile_registry.remove(1)
		server.world.projectile_registry.add(ProjectileState.create(1025, peers[0], 1025, Vector2(740, 740), 0, stats))
		recovered.clear()
		await create_timer(12.0).timeout
		print("DENSE_SETTLEMENT_BEGIN")
		await create_timer(6.0).timeout
	running = false
	disconnected = disconnected or server.lobby.human_count() != 32
	var all_complete := initial_complete and recovered.size() == 32 and not disconnected and max_pending <= 27 and max_inflight <= 2 and snapshots.size() == 32
	for complete in recovered.values(): all_complete = all_complete and bool(complete)
	for count in snapshots.values(): all_complete = all_complete and int(count) > 20
	print("SSF_DENSE_RESULT=" + JSON.stringify({"passed": all_complete, "initial_complete": initial_complete, "clients": clients.size(), "recovered": recovered, "recovery_rounds": recovery_rounds, "last_recovery_ticks": last_recovery_ticks, "snapshots": snapshots, "mutation_tick": mutation_tick, "disconnected": disconnected, "max_pending": max_pending, "ticks": tick, "payload_bytes": server.replication.outbound_bytes(), "payload": server.replication.payload_metrics()}))
	for client in clients: client.stop()
	server.stop()
	quit(0 if all_complete else 1)


func _all_admitted() -> bool:
	if server.lobby.human_count() != 32: return false
	for client in clients:
		if client.local_peer_id <= 0 or not server.lobby.players.has(client.local_peer_id): return false
	return true

func _physics_process(_delta: float) -> bool:
	if running:
		tick += 1
		server.world.server_tick = tick
		server.replication.replicate_tick(tick, server.lobby, server.world)
		max_pending = maxi(max_pending, server.replication.payload_metrics().recovery_pending_chunks)
		max_inflight = maxi(max_inflight, server.replication.payload_metrics().recovery_inflight_chunks_per_peer)
	return false
