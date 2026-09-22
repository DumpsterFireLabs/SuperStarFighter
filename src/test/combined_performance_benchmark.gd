extends SceneTree

## Unprofiled shipping simulation/coordination/packet publication. Refill and
## sockets are excluded and reported; ClientMain live coverage measures transport.
const LoadFixture = preload("res://src/test/performance_benchmark.gd")
const WARMUP := 60
const SAMPLES := 360
const PHYSICS_BUDGET_USEC := 1000000.0 / GameConstants.PHYSICS_TICKS_PER_SECOND
var recovery_this_tick := false
var bytes_this_tick := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var map_id := ArenaLayout.DEFAULT_MAP_ID
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--benchmark-map="): map_id = ArenaLayout.normalized_map_id(StringName(arg.get_slice("=", 1)))
	var config := MatchConfig.new()
	config.game_mode = GameModeRules.Mode.KING_OF_THE_HILL
	config.draft_duration_seconds = 0.05
	config.countdown_duration_seconds = 0.05
	var world := AuthoritativeWorld.new()
	var lobby := ServerLobby.new(config)
	var ids: Array[int] = []
	for peer in range(1, 33):
		lobby.admit(peer, "Pilot%d" % peer)
		world.add_peer(peer)
		ids.append(peer)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 731901)
	coordinator._map_rotation.assign([map_id])
	coordinator.start(0)
	for tick in 120:
		world.step(1.0 / 60.0, false)
		coordinator.step(1.0 / 60.0)
		coordinator.drain_events()
		coordinator.drain_private_offers()
		if coordinator.controls_enabled(): break
	if not coordinator.controls_enabled():
		push_error("Combined fixture failed to enter active heat.")
		quit(1)
		return
	lobby.match_active = true
	# Remove draft randomness from the defensive load; pilots remain stationary.
	for combatant: CombatantState in world.combatants.values():
		combatant.stats = CombatStats.create_base()
	var fixture := LoadFixture.new()
	var scheduler := NetworkReplicationScheduler.new()
	# Model healthy recipients; transport latency is measured by the ENet fixture.
	var scheduler_ref: WeakRef = weakref(scheduler)
	scheduler.projectile_recovery_ready.connect(func(peer: int, packet: PackedByteArray) -> void:
		(scheduler_ref.get_ref() as NetworkReplicationScheduler).acknowledge_recovery(peer, packet.decode_u32(1), packet.decode_u16(6), packet.decode_u16(8)))
	scheduler.projectile_recovery_ready.connect(func(_peer: int, packet: PackedByteArray) -> void:
		recovery_this_tick = true
		bytes_this_tick += packet.size()
	)
	scheduler.projectile_correction_ready.connect(func(packet: PackedByteArray) -> void:
		recovery_this_tick = recovery_this_tick or packet[5] == ProjectilePacketCodec.KIND_FULL_CORRECTION
		bytes_this_tick += packet.size() * ids.size()
	)
	scheduler.projectile_batch_ready.connect(func(packet: PackedByteArray) -> void: bytes_this_tick += packet.size() * ids.size())
	scheduler.player_snapshot_ready.connect(func(_peer: int, packet: PackedByteArray) -> void: bytes_this_tick += packet.size())
	var samples: Array[int] = []
	var recovery: Array[int] = []
	var payload_bytes := 0
	var events := 0
	var minimum_projectiles := GameConstants.MAX_PROJECTILES_GLOBAL
	var valid := not world.performance_profiling_enabled
	for tick in WARMUP + SAMPLES:
		fixture._fill_projectiles(world, ids)
		minimum_projectiles = mini(minimum_projectiles, world.projectile_registry.size())
		recovery_this_tick = false
		bytes_this_tick = 0
		var started := Time.get_ticks_usec()
		world.step(1.0 / 60.0, true)
		coordinator.step(1.0 / 60.0)
		var published := coordinator.drain_events()
		scheduler.replicate_tick(world.server_tick, lobby, world)
		var elapsed := Time.get_ticks_usec() - started
		valid = valid and coordinator.controls_enabled()
		if tick >= WARMUP:
			samples.append(elapsed)
			payload_bytes += bytes_this_tick
			events += published.size()
			if recovery_this_tick: recovery.append(elapsed)
	var all_ticks := summarize(samples)
	var recovery_ticks := summarize(recovery)
	valid = valid and samples.size() == SAMPLES and recovery.size() >= 6 and payload_bytes > 0 and events > 0 and minimum_projectiles == GameConstants.MAX_PROJECTILES_GLOBAL
	# Defensive overload limits match the existing fixture, with recovery tails
	# independently gated so a once-per-second spike cannot hide below p95.
	valid = valid and all_ticks.p95_usec <= 20000 and all_ticks.p99_usec <= 24000 and all_ticks.max_usec <= 30000
	valid = valid and recovery_ticks.p95_usec <= 24000 and recovery_ticks.max_usec <= 30000
	if "--strict-physics-budget" in OS.get_cmdline_user_args():
		valid = valid and all_ticks.over_physics_budget == 0
	print("SSF_COMBINED_PERFORMANCE=" + JSON.stringify({"valid": valid, "profiled": false, "map_id": map_id, "game_mode": "KING_OF_THE_HILL", "per_tick": all_ticks, "full_recovery_tick": recovery_ticks, "physics_budget_usec": PHYSICS_BUDGET_USEC, "payload_bytes": payload_bytes, "coordinator_events": events, "players": ids.size(), "minimum_projectiles_before_step": minimum_projectiles, "scope": "32 stationary humans/1024 moving projectiles; real world, coordinator, event drain and scheduler; includes packet publication; excludes refill, RPC/socket transport and rendering; 60 warmup/360 measured ticks; overload acceptance, not a zero-overrun 60 Hz certification"}))
	fixture.free()
	quit(0 if valid else 1)

static func summarize(samples: Array[int]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var over := 0
	for sample in samples:
		if sample > PHYSICS_BUDGET_USEC: over += 1
	return {"samples": samples.size(), "p50_usec": NetworkBridge.percentile_usec(sorted, 0.5), "p95_usec": NetworkBridge.percentile_usec(sorted, 0.95), "p99_usec": NetworkBridge.percentile_usec(sorted, 0.99), "max_usec": sorted.back() if not sorted.is_empty() else 0, "over_physics_budget": over}
