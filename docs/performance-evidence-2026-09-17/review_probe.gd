extends SceneTree

# Review-only experiments. No production behavior or timing policy is changed.
const MatchState = preload("res://src/client/network/client_match_state.gd")
const LoadFixture = preload("res://src/test/performance_benchmark.gd")
const PackedCodec = preload("res://docs/performance-evidence-2026-09-17/packed_codec_prototype.gd")

class SharedState extends MatchState:
	func update_fields(fields: Dictionary) -> void:
		var next := payload.duplicate()
		var detached := fields.duplicate(true)
		_freeze(detached)
		next.merge(detached, true)
		next.make_read_only()
		_payload = next
		changed.emit()

var valid := true

func _initialize() -> void:
	_run.call_deferred()

func summary(samples: Array[int]) -> Dictionary:
	var total := 0
	for value in samples: total += value
	var sorted := samples.duplicate()
	sorted.sort()
	return {"samples": samples.size(), "mean_usec": float(total) / maxi(samples.size(), 1),
		"p50_usec": NetworkBridge.percentile_usec(sorted, 0.5), "p95_usec": NetworkBridge.percentile_usec(sorted, 0.95), "max_usec": sorted.back()}

func _run() -> void:
	print("PERF_REVIEW_MACHINE=" + JSON.stringify({"cpu": OS.get_processor_name(), "logical_cpus": OS.get_processor_count(), "godot": Engine.get_version_info().string}))
	_profile_overhead()
	_state_copy()
	_geometry_lookup()
	_replication()
	_packet_encoding()
	_combined_load()
	print("PERF_REVIEW_VALID=" + str(valid))
	quit(0 if valid else 1)

func _profile_overhead() -> void:
	var times: Array = [[], []]
	var matching := true
	for trial in 3:
		var worlds := [AuthoritativeWorld.new(), AuthoritativeWorld.new()]
		var npcs := [NpcPilotController.new(), NpcPilotController.new()]
		var fixtures := [LoadFixture.new(), LoadFixture.new()]
		var ids: Array[int] = []
		var difficulties := {}
		for i in 32:
			var peer := ServerLobby.NPC_PEER_ID_BASE + i + 1
			ids.append(peer)
			difficulties[peer] = NpcPilotController.Difficulty.INSANE
			for world: AuthoritativeWorld in worlds:
				world.add_peer(peer).position = ArenaLayout.spawn_anchors()[i % ArenaLayout.spawn_anchors().size()]
		worlds[1].performance_profiling_enabled = true
		for j in 2: fixtures[j]._fill_projectiles(worlds[j], ids)
		for tick in 160:
			for index in 2:
				var j := (index + tick + trial) % 2
				var started := Time.get_ticks_usec()
				npcs[j].submit_inputs(worlds[j], ids, difficulties)
				worlds[j].step(1.0 / 60.0)
				if tick >= 40: times[j].append(Time.get_ticks_usec() - started)
				worlds[j].drain_projectile_batch()
				fixtures[j]._fill_projectiles(worlds[j], ids)
			matching = matching and worlds[0].snapshot_states() == worlds[1].snapshot_states()
		for fixture: Node in fixtures: fixture.free()
	var off: Array[int] = []; off.assign(times[0])
	var on: Array[int] = []; on.assign(times[1])
	valid = valid and matching
	print("PERF_REVIEW_PROFILING=" + JSON.stringify({"disabled": summary(off), "enabled": summary(on), "ship_snapshots_equal_every_tick": matching, "trials": 3, "scope": "32 NPC/1024 projectile overload; alternating order; 40 warmup and 120 measured ticks per trial; excludes refill/replication/render"}))

func _state_copy() -> void:
	var lobby := ServerLobby.new()
	var world := AuthoritativeWorld.new()
	for peer in range(1,33):
		lobby.admit(peer, "Pilot%d" % peer)
		world.add_peer(peer)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 731901)
	var payload := coordinator.current_state_payload()
	var builds := {}
	var cards := CardCatalog.create_default().all_ids()
	for peer in range(1,33):
		var build := {}
		for i in mini(cards.size(), 16): build[cards[i]] = 1
		builds[peer] = build
	payload["builds"] = builds
	var current := MatchState.new()
	var shared := SharedState.new()
	current.replace(payload); shared.replace(payload)
	var original := shared.payload
	var times: Array = [[], []]
	var states := [current, shared]
	for tick in 640:
		var fields := {"objective": {"active": true, "progress": {1: float(tick)}, "position": Vector2(1200, 900)}}
		for index in 2:
			var j := (index + tick) % 2
			var started := Time.get_ticks_usec()
			states[j].update_fields(fields)
			if tick >= 40: times[j].append(Time.get_ticks_usec() - started)
		fields.objective.progress[1] = -999.0
		valid = valid and current.payload == shared.payload and shared.payload.objective.progress[1] == float(tick)
	valid = valid and original == payload and shared.payload.is_read_only() and shared.payload.builds[1].is_read_only()
	var a: Array[int] = []; a.assign(times[0])
	var b: Array[int] = []; b.assign(times[1])
	print("PERF_REVIEW_STATE=" + JSON.stringify({"full_copy": summary(a), "structural_sharing_prototype": summary(b), "payload_bytes": var_to_bytes(payload).size(), "players": 32, "cards_each": 16, "scope": "one objective-field update; same values, detached incoming fields, immutable old observations; no UI signal consumers"}))

func _geometry_lookup() -> void:
	var geometry := ArenaCollisionSystem.projectile_geometry(ArenaLayout.DEFAULT_MAP_ID, 7.0)
	var times: Array = [[], []]
	var hits := [0, 0]
	for batch in 64:
		for index in 2:
			var cached := (index + batch) % 2
			var started := Time.get_ticks_usec()
			for i in 1024:
				var start := Vector2(80 + (i % 64) * 48, 90 + (i / 64) * 94)
				var finish := start + Vector2.from_angle(float(posmod(i * 47, 360)) * PI / 180.0) * 20.0
				var hit: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(start, finish, 7.0, ArenaLayout.DEFAULT_MAP_ID, geometry if cached else {})
				if hit != null: hits[cached] += 1
			if batch >= 4: times[cached].append(Time.get_ticks_usec() - started)
	valid = valid and hits[0] == hits[1]
	var a: Array[int] = []; a.assign(times[0])
	var b: Array[int] = []; b.assign(times[1])
	print("PERF_REVIEW_GEOMETRY=" + JSON.stringify({"lookup_per_sweep": summary(a), "reuse_geometry": summary(b), "hits_equal": hits[0] == hits[1], "scope": "1024 fixed 20px sweeps per sample, default map and radius7; warm geometry cache; alternating order; no rendering"}))

func _replication() -> void:
	for humans in [1,16,32]:
		var world := AuthoritativeWorld.new()
		var lobby := ServerLobby.new()
		var ids: Array[int] = []
		for peer in range(1,33):
			world.add_peer(peer)
			ids.append(peer)
			if peer <= humans: lobby.admit(peer, "Pilot%d" % peer)
		lobby.match_active = true
		var fixture := LoadFixture.new()
		fixture._fill_projectiles(world, ids)
		var scheduler := NetworkReplicationScheduler.new()
		var times: Array[int] = []
		var correction_times: Array[int] = []
		for tick in 660:
			world.server_tick = tick
			var began := Time.get_ticks_usec()
			scheduler.replicate_tick(tick, lobby, world)
			var elapsed := Time.get_ticks_usec() - began
			if tick == 59: scheduler.reset_outbound_bytes()
			if tick >= 60:
				times.append(elapsed)
				if tick % 60 == 0: correction_times.append(elapsed)
		print("PERF_REVIEW_REPLICATION=" + JSON.stringify({"humans": humans, "per_tick": summary(times), "full_recovery_tick": summary(correction_times), "payload_bytes_per_second_total": scheduler.outbound_bytes() / 10.0, "scope": "32 ships/1024 stable projectiles; codec and scheduler only, no RPC/socket/transport; 600 measured ticks after60 warmup"}))
		fixture.free()

func _packet_encoding() -> void:
	var world := AuthoritativeWorld.new()
	var fixture := LoadFixture.new()
	var ids: Array[int] = []
	for peer in range(1,33): ids.append(peer)
	fixture._fill_projectiles(world, ids)
	var projectiles := world.active_projectiles()
	var times: Array = [[], []]
	var equal := true
	for iteration in 124:
		var packets: Array = [null, null]
		for index in 2:
			var j := (index + iteration) % 2
			var began := Time.get_ticks_usec()
			packets[j] = ProjectilePacketCodec.encode_correction_chunks(iteration, iteration, projectiles, true) if j == 0 else PackedCodec.encode_correction_chunks(iteration, iteration, projectiles, true)
			if iteration >= 4: times[j].append(Time.get_ticks_usec() - began)
		equal = equal and packets[0] == packets[1]
	# Mixed flags, clamp boundaries, signed velocity and wrapping IDs.
	for i in 40:
		var p := projectiles[i]
		p.projectile_id = 0xffffffff - i
		p.owner_id = i
		p.shot_sequence = -1
		p.position = Vector2(-10.0, 9000.0)
		p.velocity = Vector2(-5000.0, 5000.0)
		p.damage = 999.0
		p.remaining_pierces = 999
		p.remaining_ricochets = -1
		p.is_mine = i % 2 == 0
		p.is_beam = i % 3 == 0
		p.is_missile = i % 5 == 0
		p.has_rebounded = i % 7 == 0
		p.missile_target_id = 0xffffffff
		p.mine_activation_remaining = 80.0
		p.lifetime_remaining = -1.0
	var removed: Array[int] = [1, 0xffffffff]
	equal = equal and ProjectilePacketCodec.encode_batch_chunks(0xffffffff, 65535, projectiles, removed) == PackedCodec.encode_batch_chunks(0xffffffff, 65535, projectiles, removed)
	valid = valid and equal
	var a: Array[int] = []; a.assign(times[0])
	var b: Array[int] = []; b.assign(times[1])
	print("PERF_REVIEW_CODEC=" + JSON.stringify({"current": summary(a), "presized_native_writes_prototype": summary(b), "byte_identical": equal, "scope": "1024 projectile full recovery, 120 paired alternating samples; plus mixed flag/clamp/wrap vectors; no transport"}))
	fixture.free()

func _combined_load() -> void:
	var world := AuthoritativeWorld.new()
	var lobby := ServerLobby.new()
	var ids: Array[int] = []
	for peer in range(1,33):
		world.add_peer(peer).position = ArenaLayout.spawn_anchors()[(peer - 1) % ArenaLayout.spawn_anchors().size()]
		lobby.admit(peer, "Pilot%d" % peer)
		ids.append(peer)
	lobby.match_active = true
	var fixture := LoadFixture.new()
	fixture._fill_projectiles(world, ids)
	var scheduler := NetworkReplicationScheduler.new()
	var samples: Array[int] = []
	var recovery: Array[int] = []
	var over_budget := 0
	for i in 420:
		var start := Time.get_ticks_usec()
		world.step(1.0 / 60.0, true, false)
		scheduler.replicate_tick(world.server_tick, lobby, world)
		var elapsed := Time.get_ticks_usec() - start
		if i >= 60:
			samples.append(elapsed)
			if world.server_tick % 60 == 12: recovery.append(elapsed)
			if elapsed > 16667: over_budget += 1
		fixture._fill_projectiles(world, ids)
	print("PERF_REVIEW_COMBINED=" + JSON.stringify({"per_tick": summary(samples), "full_recovery_tick": summary(recovery), "ticks_over_16_667_usec": over_budget, "scope": "32 stationary humans/1024 moving projectiles; real world plus scheduler, profiling disabled; excludes refill, inputs, coordinator, RPC and client; first recovery at tick12 then every60"}))
	fixture.free()
