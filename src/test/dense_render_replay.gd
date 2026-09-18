extends SceneTree

## Fixed-step presentation replay; no network/NPC/random wall-clock trajectories.
class ReplayProjectiles extends ProjectileLayer:
	var replay_time_msec := 0.0
	func _animation_time_msec() -> float:
		return replay_time_msec

var expected_fps := 60.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expected-fps="): expected_fps = clampf(float(arg.get_slice("=", 1)), 1, 240)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var arena := Node2D.new()
	arena.scale = Vector2(0.6, 0.6)
	root.add_child(arena)
	var ships: Array[CombatShipView] = []
	for index in 32:
		var ship := CombatShipView.new()
		ship.setup(index + 1, CombatStats.create_base(), Vector2(250 + (index % 8) * 380, 250 + (index / 8) * 400), Color("42e8ff"), index == 0, "Pilot %d" % index, ShipAppearance.PATTERNS[index % 6])
		arena.add_child(ship)
		ship.set_process(false)
		ship.reduced_flashes = true
		ship.thruster_particles.emitting = false
		ship.combatant.shield.active = true
		ships.append(ship)
	var registry := ProjectileRegistry.presentation_store()
	var layer := ReplayProjectiles.new()
	layer.registry = registry
	arena.add_child(layer)
	var effects := CombatEffectsLayer.new()
	arena.add_child(effects)
	effects.set_process(false)
	var stats := CombatStats.create_base()
	for index in 1024:
		var projectile := ProjectileState.create(index + 1, index % 32 + 1, index, Vector2.ZERO, 0.0, stats)
		projectile.is_beam = index % 4 == 1
		projectile.is_mine = index % 4 == 2
		projectile.is_missile = index % 4 == 3
		projectile.mine_activation_remaining = 0.0
		registry.add(projectile)
	var samples: Array[int] = []
	var cpu: Array[int] = []
	var calls: Array[int] = []
	var previous := Time.get_ticks_usec()
	var hash_state := HashingContext.new()
	hash_state.start(HashingContext.HASH_SHA256)
	var minimum_drawn := 1024
	var peak_effects := 0
	for tick in 660:
		var started := Time.get_ticks_usec()
		for projectile in registry.all_projectiles():
			var id := projectile.projectile_id
			projectile.position = Vector2(60 + posmod(id * 73 + tick * 7, 3080), 60 + posmod(id * 37 + tick * 3, 1680))
			projectile.velocity = Vector2.from_angle(id * 0.31 + tick * 0.02) * 900.0
		for ship in ships:
			ship.combatant.aim_angle = tick * 0.025 + ship.combatant.peer_id * 0.3
			ship.queue_redraw()
		effects._process(1.0 / 60.0)
		if tick % 4 == 0:
			for index in 4:
				effects.spawn_mine_explosion(Vector2(180 + posmod(tick * 31 + index * 710, 2820), 200 + posmod(tick * 19 + index * 370, 1400)))
		peak_effects = maxi(peak_effects, effects.effects.size())
		layer.replay_time_msec = tick * 1000.0 / 60.0
		layer.queue_redraw()
		var elapsed := Time.get_ticks_usec() - started
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if tick >= 60:
			samples.append(now - previous)
			cpu.append(elapsed)
			calls.append(roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			minimum_drawn = mini(minimum_drawn, layer.last_drawn_projectiles)
		previous = now
	await process_frame
	for projectile in registry.all_projectiles():
		hash_state.update(var_to_bytes([projectile.position, projectile.velocity]))
	var valid := samples.size() == 600 and minimum_drawn == 1024 and peak_effects >= 24
	cpu.sort()
	calls.sort()
	print("SSF_DENSE_REPLAY=" + JSON.stringify({"valid": valid, "pacing": preload("res://src/test/frame_timing_summary.gd").summarize(samples, expected_fps), "final_state_sha256": hash_state.finish().hex_encode(), "minimum_drawn_projectiles": minimum_drawn, "ships": ships.size(), "peak_effects": peak_effects, "update_p95_usec": NetworkBridge.percentile_usec(cpu, 0.95), "draw_calls_p95": NetworkBridge.percentile_usec(calls, 0.95), "scope": "600 rendered fixed-step frames after 60 warmup; 32 ships, 1024 mixed ordnance and bounded mine explosions; deterministic positions, angles, effect ages and cosmetic animation clock; no transport, simulation collision or audio"}))
	quit(0 if valid else 1)
