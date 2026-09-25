extends SceneTree

## Combined functional coverage across modes, maps, stacked builds and mixed pilots.
## CPU samples are diagnostic unless --strict-physics-budget is explicitly requested.
const LoadFixture = preload("res://src/test/performance_benchmark.gd")
const Summary = preload("res://src/test/combined_performance_benchmark.gd")
var case_index := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="): case_index = int(argument.get_slice("=", 1))
	var maps: Array[StringName] = [&"core_arena", &"dead_freight", &"twin_suns", &"switchyard", &"prism_array"]
	if case_index < 0 or case_index >= maps.size():
		quit(1)
		return
	var config := MatchConfig.new()
	config.game_mode = case_index
	config.draft_duration_seconds = 0.05
	config.countdown_duration_seconds = 0.05
	config.arena_effects = {"mode": ArenaEffectRules.SIGNATURE, "mask": 7, "frequency": 2, "strength": 2}
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	world.performance_profiling_enabled = "--profile" in OS.get_cmdline_user_args()
	for peer in range(1, 17): lobby.admit(peer, "Pilot%d" % peer)
	lobby.request_npcs_enabled(1, true)
	var ids: Array[int] = []
	ids.assign(lobby.players.keys())
	ids.sort()
	for peer in ids: world.add_peer(peer)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 731901)
	coordinator.incremental_drafts = true
	coordinator._map_rotation.assign([maps[case_index]])
	coordinator.start(0)
	for step in 180:
		world.step(1.0 / 60.0, false)
		coordinator.step(1.0 / 60.0)
		coordinator.drain_events()
		coordinator.drain_private_offers()
		if coordinator.controls_enabled(): break
	if not coordinator.controls_enabled():
		push_error("matrix failed to enter heat")
		quit(1)
		return
	lobby.match_active = true
	var catalog := CardCatalog.create_default()
	var build := {&"rapid_cycling": 3, &"twin_shot": 3, &"ricochet_rounds": 3, &"piercing_rounds": 2, &"reinforced_hull": 4}
	for ship: CombatantState in world.combatants.values():
		ship.stats = StatSystem.derive(build, catalog)
		# Keep the measured heat alive; all movement, firing and hits still execute.
		ship.stats.max_health = 1000000.0
		ship.health = ship.stats.max_health
	var fixture := LoadFixture.new()
	var scheduler := NetworkReplicationScheduler.new()
	# Model healthy recipients; transport latency is measured by the TCP impairment fixture.
	var scheduler_ref: WeakRef = weakref(scheduler)
	scheduler.projectile_recovery_ready.connect(func(peer: int, packet: PackedByteArray) -> void:
		(scheduler_ref.get_ref() as NetworkReplicationScheduler).acknowledge_recovery(peer, packet.decode_u32(1), packet.decode_u16(6), packet.decode_u16(8)))
	var npc := NpcPilotController.new()
	var npc_ids := lobby.npc_peer_ids_view()
	var difficulties := lobby.npc_difficulties_view()
	var times: Array[int] = []
	var phase_samples := {"input": [], "npc": [], "world": [], "coordinator": [], "replication": []}
	var collision_totals: Dictionary = {}
	var max_pending := 0
	var effect_activity := 0
	var active_ticks := 0
	var valid := ids.size() == 32 and npc_ids.size() == 16
	for tick in 540:
		fixture._fill_projectiles(world, ids)
		var start := Time.get_ticks_usec()
		for peer in range(1, 17):
			world.submit_input(peer, PlayerInputFrame.new(tick + 1, tick + 1, Vector2.from_angle(peer + tick * 0.025), peer + tick * 0.07, tick % 3 != 0, tick % 11 == 0))
		var input_end := Time.get_ticks_usec()
		npc.submit_inputs(world, npc_ids, difficulties, coordinator.npc_overtime_elapsed(), coordinator.npc_objective_state())
		var npc_end := Time.get_ticks_usec()
		if coordinator.controls_enabled(): active_ticks += 1
		world.step(1.0 / 60.0, coordinator.controls_enabled())
		var world_end := Time.get_ticks_usec()
		coordinator.step(1.0 / 60.0)
		coordinator.drain_events()
		var coordinator_end := Time.get_ticks_usec()
		scheduler.replicate_tick(world.server_tick, lobby, world)
		var elapsed := Time.get_ticks_usec() - start
		if tick >= 60:
			times.append(elapsed)
			phase_samples.input.append(input_end - start)
			phase_samples.npc.append(npc_end - input_end)
			phase_samples.world.append(world_end - npc_end)
			phase_samples.coordinator.append(coordinator_end - world_end)
			phase_samples.replication.append(start + elapsed - coordinator_end)
			for phase in world.last_projectile_profile_usec:
				collision_totals[phase] = int(collision_totals.get(phase, 0)) + int(world.last_projectile_profile_usec[phase])
		max_pending = maxi(max_pending, scheduler.payload_metrics().recovery_pending_chunks)
		if world.arena_effects.hidden_cover != 0 or world.arena_effects.warning or world.arena_effects.pulse_radius >= 0: effect_activity += 1
		valid = valid and not coordinator.is_finished() and world.projectile_registry.size() <= 1024
		for ship: CombatantState in world.combatants.values(): valid = valid and ship.position.is_finite() and ship.velocity.is_finite()
	var summary := Summary.summarize(times)
	var phases: Dictionary = {}
	for phase in phase_samples:
		var samples: Array[int] = []
		samples.assign(phase_samples[phase])
		phases[phase] = Summary.summarize(samples)
	print("SSF_MATRIX_PHASES=" + JSON.stringify({"phases": phases, "collision_totals": collision_totals, "profiled": world.performance_profiling_enabled}))
	valid = valid and active_ticks >= 120 and times.size() == 480 and max_pending <= 27 and scheduler.outbound_bytes() > 0
	if world.arena_effects.enabled != 0: valid = valid and effect_activity > 0
	if "--strict-physics-budget" in OS.get_cmdline_user_args(): valid = valid and summary.over_physics_budget == 0
	print("SSF_ARCHITECTURE_MATRIX=" + JSON.stringify({"valid": valid, "mode": GameModeRules.mode_name(config.game_mode), "map": maps[case_index], "humans": 16, "npcs": npc_ids.size(), "build": build, "effects_enabled": world.arena_effects.enabled, "effect_activity_ticks": effect_activity, "active_ticks": active_ticks, "timings": summary, "phase_work": coordinator.phase_work_snapshot(), "payload": scheduler.payload_metrics(), "scope": "Combined CPU work; includes human input, NPC decisions, world, coordinator and replication. Refill and validation excluded. No socket, renderer or FPS claim."}))
	fixture.free()
	quit(0 if valid else 1)
