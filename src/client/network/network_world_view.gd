class_name NetworkWorldView
extends Node2D

var bridge: NetworkBridge
var local_peer_id: int = 0
var ships: Dictionary = {}
var authoritative_projectiles := ProjectileRegistry.new()
var projectile_layer: SandboxProjectileLayer
var prediction := ClientPredictionBuffer.new()
var interpolation := RemoteInterpolator.new()
var predicted_tracker := PredictedProjectileTracker.new()
var predicted_projectile_ids: Dictionary = {}
var local_weapon := WeaponState.new()
var local_stats := CombatStats.create_base()
var camera: Camera2D
var diagnostics_label: Label
var input_sequence: int = 0
var client_tick: int = 0
var input_send_accumulator: float = 0.0
var prediction_initialized: bool = false
var next_predicted_id: int = -1
var latest_acknowledged_input: int = 0
var latest_server_tick: int = 0
var match_payload: Dictionary = {}
var spectator_target_id: int = 0
var controls_enabled: bool = false
var card_catalog := CardCatalog.create_default()


func setup(network_bridge: NetworkBridge) -> void:
	bridge = network_bridge
	bridge.client_connected.connect(_on_connected)
	bridge.client_snapshot_received.connect(_on_snapshot)
	bridge.client_projectile_batch_received.connect(_on_projectile_batch)
	bridge.client_projectile_correction_received.connect(_on_projectile_correction)
	var arena := SandboxArena.new()
	arena.name = "Arena"
	add_child(arena)
	projectile_layer = SandboxProjectileLayer.new()
	projectile_layer.registry = authoritative_projectiles
	add_child(projectile_layer)
	local_weapon.reset(local_stats)
	_create_camera_and_hud()
	set_network_active(false)


func set_network_active(active: bool) -> void:
	if not active:
		reset_session()
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if diagnostics_label != null:
		var diagnostics_canvas := diagnostics_label.get_parent() as CanvasLayer
		diagnostics_canvas.visible = active


func reset_session() -> void:
	for ship_value in ships.values():
		(ship_value as SandboxShip).queue_free()
	ships.clear()
	for projectile in authoritative_projectiles.all_projectiles():
		authoritative_projectiles.remove(projectile.projectile_id)
	local_peer_id = 0
	input_sequence = 0
	client_tick = 0
	input_send_accumulator = 0.0
	prediction_initialized = false
	latest_acknowledged_input = 0
	latest_server_tick = 0
	match_payload.clear()
	spectator_target_id = 0
	controls_enabled = false
	next_predicted_id = -1
	predicted_projectile_ids.clear()
	prediction = ClientPredictionBuffer.new()
	interpolation = RemoteInterpolator.new()
	predicted_tracker = PredictedProjectileTracker.new()
	local_weapon = WeaponState.new()
	local_weapon.reset(local_stats)
	if camera != null:
		camera.position = ArenaLayout.center()


func _physics_process(delta: float) -> void:
	if local_peer_id == 0 or not ships.has(local_peer_id):
		return
	client_tick = SequenceMath.increment(client_tick)
	input_send_accumulator += delta
	var local_ship := ships[local_peer_id] as SandboxShip
	var aim_vector := get_global_mouse_position() - local_ship.global_position
	var aim_angle := local_ship.combatant.aim_angle
	if not aim_vector.is_zero_approx():
		aim_angle = aim_vector.angle()
	var local_movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var local_alive := local_ship.combatant.alive
	if not controls_enabled:
		local_movement = Vector2.ZERO
	var frame := PlayerInputFrame.new(
		input_sequence,
		client_tick,
		local_movement,
		aim_angle,
		controls_enabled and local_alive and Input.is_action_pressed("fire"),
		controls_enabled and local_alive and Input.is_action_pressed("shield")
	)
	var send_interval := 1.0 / GameConstants.INPUT_SEND_RATE
	if input_send_accumulator >= send_interval:
		input_send_accumulator = fmod(input_send_accumulator, send_interval)
		input_sequence = SequenceMath.increment(input_sequence)
		frame.sequence = input_sequence
		bridge.send_input(frame)
	if prediction_initialized and local_alive and controls_enabled:
		prediction.predict(frame, local_stats, delta)
		local_ship.global_position = prediction.visual_position(delta)
		local_ship.combatant.position = local_ship.global_position
		local_ship.combatant.velocity = prediction.predicted_velocity
		local_ship.combatant.aim_angle = aim_angle
		local_ship.queue_redraw()
	local_weapon.step(local_stats, delta)
	if frame.firing and local_weapon.try_fire(local_stats, frame.shielding):
		_spawn_predicted_projectile(local_ship, aim_angle)
	_update_remote_ships()
	_step_projectile_visuals(delta)
	_update_camera(local_ship, delta)
	predicted_tracker.step(_now_seconds())
	_update_diagnostics()


func _on_connected(peer_id: int) -> void:
	local_peer_id = peer_id
	set_network_active(true)


func _on_snapshot(decoded: Dictionary) -> void:
	latest_acknowledged_input = int(decoded.acknowledged_input)
	latest_server_tick = int(decoded.server_tick)
	var receive_time := _now_seconds()
	var present_ids: Dictionary = {}
	for state_value in decoded.states:
		var state := state_value as Dictionary
		var peer_id := int(state.peer_id)
		present_ids[peer_id] = true
		var ship := _ensure_ship(peer_id, state)
		_apply_snapshot_resources(ship, state)
		if peer_id == local_peer_id:
			if not prediction_initialized:
				prediction.predicted_position = state.position
				prediction.predicted_velocity = state.velocity
				ship.global_position = state.position
				camera.position = state.position
				prediction_initialized = true
			else:
				prediction.reconcile(state.position, state.velocity, decoded.acknowledged_input, local_stats)
			local_weapon.ammunition = int(state.ammunition)
		else:
			interpolation.add_sample(peer_id, receive_time, state)
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if not present_ids.has(peer_id):
			(ships[peer_id] as SandboxShip).queue_free()
			ships.erase(peer_id)
			interpolation.remove_peer(peer_id)
	_update_spectator_target()


func apply_match_state(payload: Dictionary) -> void:
	match_payload = payload.duplicate(true)
	controls_enabled = String(payload.get("state_name", "")) == "ACTIVE_HEAT"
	var builds := payload.get("builds", {}) as Dictionary
	if builds.has(local_peer_id):
		local_stats = StatSystem.derive(builds[local_peer_id] as Dictionary, card_catalog)
	if String(payload.get("state_name", "")) == "COUNTDOWN":
		local_weapon.reset(local_stats)
		prediction_initialized = false
	_update_spectator_target()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _local_is_eliminated():
		return
	var direction := 0
	if event is InputEventKey and not event.echo:
		if not event.pressed:
			return
		if event.physical_keycode == KEY_A:
			direction = -1
		elif event.physical_keycode == KEY_D:
			direction = 1
	elif event is InputEventMouseButton:
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			direction = -1
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			direction = 1
	else:
		return
	if direction != 0:
		_cycle_spectator(direction)
		get_viewport().set_input_as_handled()


func _on_projectile_batch(decoded: Dictionary) -> void:
	for projectile_value in decoded.spawned:
		var projectile := projectile_value as ProjectileState
		if projectile.owner_id == local_peer_id and predicted_projectile_ids.has(projectile.shot_sequence):
			var predicted_id := int(predicted_projectile_ids[projectile.shot_sequence])
			authoritative_projectiles.remove(predicted_id)
			predicted_projectile_ids.erase(projectile.shot_sequence)
			predicted_tracker.reconcile(projectile.owner_id, projectile.shot_sequence)
		authoritative_projectiles.add(projectile)
	for projectile_id in decoded.removed:
		authoritative_projectiles.remove(int(projectile_id))


func _on_projectile_correction(decoded: Dictionary) -> void:
	var authoritative_ids: Dictionary = {}
	for projectile_value in decoded.spawned:
		var projectile := projectile_value as ProjectileState
		authoritative_ids[projectile.projectile_id] = true
		var existing := authoritative_projectiles.get_projectile(projectile.projectile_id)
		if existing == null:
			authoritative_projectiles.add(projectile)
		else:
			existing.position = projectile.position
			existing.velocity = projectile.velocity
	for projectile in authoritative_projectiles.all_projectiles():
		if projectile.projectile_id > 0 and not authoritative_ids.has(projectile.projectile_id):
			authoritative_projectiles.remove(projectile.projectile_id)


func _ensure_ship(peer_id: int, state: Dictionary) -> SandboxShip:
	if ships.has(peer_id):
		return ships[peer_id] as SandboxShip
	var ship := SandboxShip.new()
	var color := Color.from_hsv(fposmod(peer_id * 0.173, 1.0), 0.7, 1.0)
	ship.setup(peer_id, local_stats, state.position, color, peer_id == local_peer_id)
	add_child(ship)
	ships[peer_id] = ship
	return ship


func _apply_snapshot_resources(ship: SandboxShip, state: Dictionary) -> void:
	ship.combatant.position = state.position
	ship.combatant.velocity = state.velocity
	ship.combatant.aim_angle = state.aim_angle
	ship.combatant.health = state.health
	ship.combatant.shield.energy = state.shield
	ship.combatant.shield.active = state.shielding
	ship.combatant.weapon.ammunition = state.ammunition
	ship.combatant.alive = state.alive
	if not state.alive:
		ship.set_eliminated()
	ship.queue_redraw()


func _update_remote_ships() -> void:
	var now := _now_seconds()
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if peer_id == local_peer_id:
			continue
		var sample := interpolation.sample(peer_id, now)
		if sample.ok:
			var ship := ships[peer_id] as SandboxShip
			ship.global_position = sample.position
			ship.combatant.position = sample.position
			ship.combatant.velocity = sample.velocity
			ship.combatant.aim_angle = sample.aim_angle
			ship.queue_redraw()


func _spawn_predicted_projectile(ship: SandboxShip, aim_angle: float) -> void:
	var muzzle := ship.global_position + Vector2.from_angle(aim_angle) * 31.0
	for angle in MovementSystem.spread_angles(aim_angle, local_stats.projectile_count, local_stats.projectile_spread_degrees):
		var projectile := ProjectileState.create(next_predicted_id, local_peer_id, local_weapon.shot_sequence, muzzle, angle, local_stats)
		authoritative_projectiles.add(projectile)
		predicted_projectile_ids[local_weapon.shot_sequence] = next_predicted_id
		next_predicted_id -= 1
	predicted_tracker.add(local_peer_id, local_weapon.shot_sequence, _now_seconds())


func _step_projectile_visuals(delta: float) -> void:
	for projectile in authoritative_projectiles.all_projectiles():
		if not projectile.step(delta):
			authoritative_projectiles.remove(projectile.projectile_id)
	projectile_layer.queue_redraw()


func _update_camera(local_ship: SandboxShip, delta: float) -> void:
	var target_position := local_ship.global_position
	if not local_ship.combatant.alive:
		if spectator_target_id != 0 and ships.has(spectator_target_id):
			target_position = (ships[spectator_target_id] as SandboxShip).global_position
		else:
			target_position = ArenaLayout.center()
	camera.position = camera.position.lerp(target_position, 1.0 - exp(-8.0 * delta))


func _create_camera_and_hud() -> void:
	camera = Camera2D.new()
	camera.position = ArenaLayout.center()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameConstants.ARENA_SIZE.x)
	camera.limit_bottom = int(GameConstants.ARENA_SIZE.y)
	camera.enabled = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	canvas.name = "NetworkDiagnostics"
	add_child(canvas)
	diagnostics_label = Label.new()
	diagnostics_label.position = Vector2(20.0, 20.0)
	diagnostics_label.add_theme_color_override("font_color", Color("73f7ff"))
	diagnostics_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(diagnostics_label)


func _update_diagnostics() -> void:
	var resources := ""
	if ships.has(local_peer_id):
		var local_ship := ships[local_peer_id] as SandboxShip
		resources = "HP %.0f · SHIELD %.0f · AMMO %d" % [local_ship.combatant.health, local_ship.combatant.shield.energy, local_ship.combatant.weapon.ammunition]
		if not local_ship.combatant.alive:
			resources = "SPECTATING %d · A/D or mouse buttons to cycle" % spectator_target_id
	diagnostics_label.text = "%s\nNETWORK · FPS %d · RTT %d ms · peer %d · ack %d\nerror %.2f px · snaps %d · players %d · projectiles %d · interpolation 100 ms" % [resources, Engine.get_frames_per_second(), bridge.get_round_trip_time_ms(), local_peer_id, latest_acknowledged_input, prediction.last_reconciliation_error, prediction.snap_count, ships.size(), authoritative_projectiles.size()]


func _local_is_eliminated() -> bool:
	return ships.has(local_peer_id) and not (ships[local_peer_id] as SandboxShip).combatant.alive


func _living_spectator_targets() -> Array[int]:
	var result: Array[int] = []
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if peer_id != local_peer_id and (ships[peer_id] as SandboxShip).combatant.alive:
			result.append(peer_id)
	result.sort()
	return result


func _update_spectator_target() -> void:
	if not _local_is_eliminated():
		spectator_target_id = 0
		return
	var targets := _living_spectator_targets()
	if targets.is_empty():
		spectator_target_id = 0
	elif spectator_target_id not in targets:
		spectator_target_id = targets[0]


func _cycle_spectator(direction: int) -> void:
	var targets := _living_spectator_targets()
	if targets.is_empty():
		spectator_target_id = 0
		return
	var current_index := targets.find(spectator_target_id)
	if current_index < 0:
		current_index = 0
	spectator_target_id = targets[posmod(current_index + direction, targets.size())]


static func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
