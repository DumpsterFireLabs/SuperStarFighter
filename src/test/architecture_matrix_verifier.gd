extends SceneTree

## Combined functional coverage across modes, maps, stacked builds and mixed pilots.
## CPU samples are diagnostic unless --strict-physics-budget is explicitly requested.
const LoadFixture = preload("res://src/test/performance_benchmark.gd")
const Summary = preload("res://src/test/combined_performance_benchmark.gd")
const CASES_PATH := "res://tests/fixtures/architecture_matrix_cases.json"
const WARMUP := 60
const SAMPLES := 480
var case_index := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("SSF_MATRIX_HOST=" + JSON.stringify({"cpu": OS.get_processor_name(), "threads": OS.get_processor_count(), "os": OS.get_name(), "engine": Engine.get_version_info().string}))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="): case_index = int(argument.get_slice("=", 1))
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string(CASES_PATH))
	if case_index < 0 or case_index >= cases.size():
		quit(1)
		return
	var scenario: Dictionary = cases[case_index]
	var map_id := StringName(scenario.map)
	var config := MatchConfig.new()
	config.game_mode = int(scenario.mode)
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
	coordinator._map_rotation.assign([map_id])
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
	# Put ships in the field, not on perimeter anchors outside its influence.
	var refill_positions := {}
	for index in ids.size():
		var ship := world.combatants[ids[index]] as CombatantState
		if bool(scenario.field):
			var field := world.movement_fields[0]
			var radius := (field.inner_radius + field.outer_radius) * 0.5
			ship.position = field.center + Vector2.from_angle(TAU * index / ids.size()) * radius
		refill_positions[ship.peer_id] = ship.position
	var fixture := LoadFixture.new()
	var scheduler := NetworkReplicationScheduler.new()
	var npc := NpcPilotController.new()
	var npc_ids := lobby.npc_peer_ids_view()
	var difficulties := lobby.npc_difficulties_view()
	var times: Array[int] = []
	var phase_samples := {"input": [], "npc": [], "world": [], "coordinator": [], "replication": []}
	var collision_totals: Dictionary = {}
	var world_totals: Dictionary = {}
	var max_pending := 0
	var effect_activity := 0
	var active_ticks := 0
	var field_ticks := 0
	var pulse_ticks := 0
	var pilot_refills := 0
	var minimum_alive := ids.size()
	var minimum_projectiles := GameConstants.MAX_PROJECTILES_GLOBAL
	var flag_resets := 0
	var valid := ids.size() == 32 and npc_ids.size() == 16
	for tick in WARMUP + SAMPLES:
		# Exercise pickup/carry/navigation without a capture ending the measured
		# heat. Full match/capture acceptance lives in the match-loop verifier.
		if GameModeRules.uses_flag(config.game_mode) and tick % 60 == 0:
			coordinator._flag.reset(GameModeRules.objective_spawn(map_id))
			flag_resets += 1
		# Horizon kills must not silently turn a 32-pilot stress case into a
		# cheaper workload. Refill is outside the CPU sample, like projectiles.
		for peer in ids:
			var ship := world.combatants[peer] as CombatantState
			if not ship.alive and coordinator.machine.respawn_player(peer):
				world.respawn_peer(peer, ship.stats, refill_positions[peer])
				pilot_refills += 1
		fixture._fill_projectiles(world, ids)
		minimum_projectiles = mini(minimum_projectiles, world.projectile_registry.size())
		var alive := 0
		var influenced := false
		for ship: CombatantState in world.combatants.values():
			if not ship.alive: continue
			alive += 1
			for field in world.movement_fields:
				influenced = influenced or field.influence_at(ship.position) > 0.0
		minimum_alive = mini(minimum_alive, alive)
		if influenced and tick >= WARMUP: field_ticks += 1
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
		if tick >= WARMUP:
			times.append(elapsed)
			phase_samples.input.append(input_end - start)
			phase_samples.npc.append(npc_end - input_end)
			phase_samples.world.append(world_end - npc_end)
			phase_samples.coordinator.append(coordinator_end - world_end)
			phase_samples.replication.append(start + elapsed - coordinator_end)
			for phase in world.last_projectile_profile_usec:
				collision_totals[phase] = int(collision_totals.get(phase, 0)) + int(world.last_projectile_profile_usec[phase])
			for phase in world.last_step_profile_usec:
				world_totals[phase] = int(world_totals.get(phase, 0)) + int(world.last_step_profile_usec[phase])
		max_pending = maxi(max_pending, scheduler.payload_metrics().recovery_pending_chunks)
		if world.arena_effects.hidden_cover != 0 or world.arena_effects.warning or world.arena_effects.pulse_radius >= 0: effect_activity += 1
		if tick >= WARMUP and world.arena_effects.pulse_radius >= 0: pulse_ticks += 1
		valid = valid and not coordinator.is_finished() and world.projectile_registry.size() <= 1024
		for ship: CombatantState in world.combatants.values(): valid = valid and ship.position.is_finite() and ship.velocity.is_finite()
	var summary := Summary.summarize(times)
	var phases: Dictionary = {}
	for phase in phase_samples:
		var samples: Array[int] = []
		samples.assign(phase_samples[phase])
		phases[phase] = Summary.summarize(samples)
	print("SSF_MATRIX_PHASES=" + JSON.stringify({"phases": phases, "collision_totals": collision_totals, "world_totals": world_totals, "profiled": world.performance_profiling_enabled}))
	valid = valid and active_ticks == WARMUP + SAMPLES and times.size() == SAMPLES and max_pending <= ProjectilePacketCodec.correction_chunk_count(GameConstants.MAX_PROJECTILES_GLOBAL) and scheduler.outbound_bytes() > 0
	valid = valid and minimum_alive == 32 and minimum_projectiles == GameConstants.MAX_PROJECTILES_GLOBAL
	if world.arena_effects.enabled != 0: valid = valid and effect_activity > 0
	valid = valid and (not bool(scenario.field) or field_ticks > 0) and (not bool(scenario.solar) or pulse_ticks > 0)
	var timing_valid: bool = not "--strict-physics-budget" in OS.get_cmdline_user_args() or summary.over_physics_budget == 0
	print("SSF_ARCHITECTURE_MATRIX=" + JSON.stringify({"valid": valid and timing_valid, "functional_valid": valid, "timing_valid": timing_valid, "mode_id": config.game_mode, "mode": GameModeRules.mode_name(config.game_mode), "map": map_id, "humans": 16, "npcs": npc_ids.size(), "build": build, "effects_enabled": world.arena_effects.enabled, "effect_activity_ticks": effect_activity, "field_activity_ticks": field_ticks, "pulse_activity_ticks": pulse_ticks, "minimum_alive_before_step": minimum_alive, "minimum_projectiles_before_step": minimum_projectiles, "pilot_refills": pilot_refills, "flag_resets": flag_resets, "active_ticks": active_ticks, "timings": summary, "phase_work": coordinator.phase_work_snapshot(), "payload": scheduler.payload_metrics(), "scope": "Combined CPU work; includes human input, NPC decisions, world, coordinator and replication. Projectile/pilot refill, periodic flag reset and validation excluded. No socket, renderer or FPS claim."}))
	fixture.free()
	quit(0 if valid and timing_valid else 1)
