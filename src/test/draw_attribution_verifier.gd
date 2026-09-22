extends SceneTree

## Instrumented sibling of dense_render_replay.gd. Measures CPU time submitting
## CanvasItem drawing commands, not frame throughput or GPU execution time.
class MeasuredShip extends CombatShipView:
	var draw_usec := 0
	func _draw() -> void:
		var began := Time.get_ticks_usec()
		super._draw()
		draw_usec = Time.get_ticks_usec() - began

class MeasuredProjectiles extends ProjectileLayer:
	var replay_time_msec := 0.0
	var draw_usec := 0
	func _animation_time_msec() -> float:
		return replay_time_msec
	func _draw() -> void:
		var began := Time.get_ticks_usec()
		super._draw()
		draw_usec = Time.get_ticks_usec() - began

class MeasuredEffects extends CombatEffectsLayer:
	var draw_usec := 0
	func _draw() -> void:
		var began := Time.get_ticks_usec()
		super._draw()
		draw_usec = Time.get_ticks_usec() - began

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var arena := Node2D.new()
	arena.scale = Vector2(0.6, 0.6)
	root.add_child(arena)
	var ships: Array[MeasuredShip] = []
	for index in 32:
		var ship := MeasuredShip.new()
		ship.setup(index + 1, CombatStats.create_base(), Vector2(250 + (index % 8) * 380, 250 + (index / 8) * 400), Color("42e8ff"), index == 0, "Pilot %d" % index, ShipAppearance.PATTERNS[index % 6])
		arena.add_child(ship)
		ship.set_process(false)
		ship.reduced_flashes = true
		ship.thruster_particles.emitting = false
		ship.combatant.shield.active = true
		ships.append(ship)
	var registry := ProjectileRegistry.presentation_store()
	var layer := MeasuredProjectiles.new()
	layer.dense_meshes_enabled = not "--legacy-projectiles" in OS.get_cmdline_user_args()
	print("SSF_DRAW_VARIANT=" + ("cached_meshes" if layer.dense_meshes_enabled else "legacy"))
	layer.registry = registry
	arena.add_child(layer)
	var effects := MeasuredEffects.new()
	arena.add_child(effects)
	effects.set_process(false)
	for index in 1024:
		var projectile := ProjectileState.create(index + 1, index % 32 + 1, index, Vector2.ZERO, 0, CombatStats.create_base())
		projectile.is_beam = index % 4 == 1
		projectile.is_mine = index % 4 == 2
		projectile.is_missile = index % 4 == 3
		projectile.mine_activation_remaining = 0
		registry.add(projectile)
	var ship_times: Array[int] = []
	var projectile_times: Array[int] = []
	var effect_times: Array[int] = []
	var total_times: Array[int] = []
	var update_times: Array[int] = []
	var minimum_drawn := 1024
	for tick in 660:
		var started := Time.get_ticks_usec()
		for projectile in registry.all_projectiles():
			var id := projectile.projectile_id
			projectile.position = Vector2(60 + posmod(id * 73 + tick * 7, 3080), 60 + posmod(id * 37 + tick * 3, 1680))
			projectile.velocity = Vector2.from_angle(id * 0.31 + tick * 0.02) * 900
		for ship in ships:
			ship.combatant.aim_angle = tick * 0.025 + ship.combatant.peer_id * 0.3
			ship.queue_redraw()
		effects._process(1.0 / 60.0)
		if tick % 4 == 0:
			for index in 4:
				effects.spawn_mine_explosion(Vector2(180 + posmod(tick * 31 + index * 710, 2820), 200 + posmod(tick * 19 + index * 370, 1400)))
		layer.replay_time_msec = tick * 1000.0 / 60.0
		layer.queue_redraw()
		var update_usec := Time.get_ticks_usec() - started
		await process_frame
		await RenderingServer.frame_post_draw
		if tick < 60: continue
		var ship_usec := 0
		for ship in ships: ship_usec += ship.draw_usec
		ship_times.append(ship_usec)
		projectile_times.append(layer.draw_usec)
		effect_times.append(effects.draw_usec)
		total_times.append(ship_usec + layer.draw_usec + effects.draw_usec)
		update_times.append(update_usec)
		minimum_drawn = mini(minimum_drawn, layer.last_drawn_projectiles)
	await process_frame
	var hash_state := HashingContext.new()
	hash_state.start(HashingContext.HASH_SHA256)
	for projectile in registry.all_projectiles(): hash_state.update(var_to_bytes([projectile.position, projectile.velocity]))
	print("SSF_DRAW_ATTRIBUTION=" + JSON.stringify({"valid": total_times.size() == 600 and minimum_drawn == 1024, "cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(), "frames": total_times.size(), "minimum_drawn": minimum_drawn, "final_state_sha256": hash_state.finish().hex_encode(), "ships": _summary(ship_times), "projectiles": _summary(projectile_times), "effects": _summary(effect_times), "draw_callback_sum": _summary(total_times), "fixture_updates": _summary(update_times), "scope": "Instrumented CPU draw-command callback time, 600 fixed workload frames after 60 warmup; same ordnance replay as dense fixture. Excludes engine render traversal, GPU execution, presentation wait, simulation and networking. Does not measure achievable FPS."}))
	root.get_texture().get_image().save_png("res://.tools/draw-attribution.png")
	quit(0 if minimum_drawn == 1024 else 1)

func _summary(samples: Array[int]) -> Dictionary:
	var total := 0
	for value in samples: total += value
	samples.sort()
	return {"mean_usec": float(total) / samples.size(), "p50_usec": NetworkBridge.percentile_usec(samples, 0.5), "p95_usec": NetworkBridge.percentile_usec(samples, 0.95), "max_usec": samples.back()}
