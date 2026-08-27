class_name NetworkWorldView
extends Node2D

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
signal presentation_event(event_name: StringName, payload: Dictionary)

var bridge: NetworkBridge
var input_profiles: Node
var arena: SandboxArena
var local_peer_id: int = 0
var ships: Dictionary = {}
var authoritative_projectiles := ProjectileRegistry.new()
var projectile_layer: SandboxProjectileLayer
var effects_layer: CombatEffectsLayer
var indicator_layer: OffscreenIndicatorLayer
var prediction := ClientPredictionBuffer.new()
var interpolation := RemoteInterpolator.new()
var predicted_tracker := PredictedProjectileTracker.new()
var predicted_projectile_ids: Dictionary = {}
var local_weapon := WeaponState.new()
var local_stats := CombatStats.create_base()
var camera: Camera2D
var diagnostics_label: Label
var hud_panel: PanelContainer
var match_status_label: Label
var resources_label: Label
var combat_status_label: Label
var spectator_label: Label
var health_bar: ProgressBar
var shield_bar: ProgressBar
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
var input_blocked: bool = false
var presentation_states: Dictionary = {}
var camera_shake_remaining: float = 0.0
var camera_shake_intensity: float = 0.0
var diagnostics_visible: bool = false


func setup(network_bridge: NetworkBridge, profile_manager: Node = null) -> void:
	bridge = network_bridge
	input_profiles = profile_manager
	bridge.client_connected.connect(_on_connected)
	bridge.client_snapshot_received.connect(_on_snapshot)
	bridge.client_projectile_batch_received.connect(_on_projectile_batch)
	bridge.client_projectile_correction_received.connect(_on_projectile_correction)
	arena = SandboxArena.new()
	arena.name = "Arena"
	add_child(arena)
	projectile_layer = SandboxProjectileLayer.new()
	projectile_layer.registry = authoritative_projectiles
	projectile_layer.z_index = 2
	add_child(projectile_layer)
	effects_layer = CombatEffectsLayer.new()
	effects_layer.name = "CombatEffects"
	effects_layer.z_index = 5
	add_child(effects_layer)
	local_weapon.reset(local_stats)
	_create_camera_and_hud()
	_create_indicator_layer()
	set_network_active(false)


func set_network_active(active: bool, reset_when_inactive: bool = true) -> void:
	if not active and reset_when_inactive:
		reset_session()
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if camera != null:
		camera.enabled = active
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
	presentation_states.clear()
	camera_shake_remaining = 0.0
	camera_shake_intensity = 0.0
	prediction = ClientPredictionBuffer.new()
	interpolation = RemoteInterpolator.new()
	predicted_tracker = PredictedProjectileTracker.new()
	local_weapon = WeaponState.new()
	local_weapon.reset(local_stats)
	if effects_layer != null:
		effects_layer.clear_effects()
	if arena != null:
		arena.set_map_id(ArenaLayout.DEFAULT_MAP_ID)
		arena.set_overtime(false, OvertimeSystem.initial_radius())
	if camera != null:
		camera.position = ArenaLayout.center(ArenaLayout.DEFAULT_MAP_ID)
		camera.offset = Vector2.ZERO


func reset_match_presentation() -> void:
	var connected_peer_id := local_peer_id
	var continuing_input_sequence := input_sequence
	var continuing_client_tick := client_tick
	reset_session()
	local_peer_id = connected_peer_id
	input_sequence = continuing_input_sequence
	client_tick = continuing_client_tick


func _physics_process(delta: float) -> void:
	if local_peer_id == 0 or not ships.has(local_peer_id):
		return
	client_tick = SequenceMath.increment(client_tick)
	input_send_accumulator += delta
	var local_ship := ships[local_peer_id] as SandboxShip
	var aim_vector: Vector2 = input_profiles.aim_vector() if input_profiles != null and input_profiles.uses_controller() else _unshaken_mouse_world_position() - local_ship.global_position
	var aim_angle := local_ship.combatant.aim_angle
	if not aim_vector.is_zero_approx():
		aim_angle = aim_vector.angle()
	var local_movement: Vector2 = input_profiles.movement_input_for_aim(aim_angle) if input_profiles != null else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var local_alive := local_ship.combatant.alive
	if not controls_enabled or input_blocked:
		local_movement = Vector2.ZERO
	var frame := PlayerInputFrame.new(
		input_sequence,
		client_tick,
		local_movement,
		aim_angle,
		controls_enabled and not input_blocked and local_alive and Input.is_action_pressed("fire"),
		controls_enabled and not input_blocked and local_alive and Input.is_action_pressed("shield"),
		controls_enabled and not input_blocked and local_alive and Input.is_action_pressed("manual_reload")
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
	if frame.manual_reload:
		local_weapon.request_reload(local_stats)
	if frame.firing and local_weapon.try_fire(local_stats, frame.shielding):
		_spawn_predicted_projectile(local_ship, aim_angle)
	local_ship.combatant.weapon.ammunition = local_weapon.ammunition
	local_ship.combatant.weapon.reloading = local_weapon.reloading
	local_ship.combatant.weapon.reload_remaining = local_weapon.reload_remaining
	local_ship.queue_redraw()
	_update_remote_ships()
	_step_projectile_visuals(delta)
	_update_camera(local_ship, delta)
	_update_camera_shake(delta)
	_update_overtime_presentation()
	predicted_tracker.step(_now_seconds())
	_update_diagnostics()
	queue_redraw()


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
		_handle_snapshot_feedback(peer_id, state, ship)
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
	var payload_map_id := StringName(payload.get("map_id", ArenaLayout.DEFAULT_MAP_ID))
	if arena != null:
		arena.set_map_id(payload_map_id)
	var state_name := String(payload.get("state_name", ""))
	controls_enabled = state_name == "ACTIVE_HEAT"
	if hud_panel != null:
		hud_panel.visible = state_name in ["COUNTDOWN", "ACTIVE_HEAT", "HEAT_RESULT", "ROUND_RESULT"]
	var builds := payload.get("builds", {}) as Dictionary
	if builds.has(local_peer_id):
		local_stats = StatSystem.derive(builds[local_peer_id] as Dictionary, card_catalog)
	if String(payload.get("state_name", "")) == "COUNTDOWN":
		local_weapon.reset(local_stats)
		prediction_initialized = false
		presentation_states.clear()
		if effects_layer != null:
			effects_layer.clear_effects()
		snap_camera_to_local_ship()
	_update_spectator_target()


func snap_camera_to_local_ship() -> void:
	if camera == null or not ships.has(local_peer_id):
		return
	camera.position = (ships[local_peer_id] as SandboxShip).global_position


func set_match_status(status: String) -> void:
	if match_status_label != null:
		match_status_label.text = status


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"diagnostics") and not (event is InputEventKey and event.echo):
		diagnostics_visible = not diagnostics_visible
		diagnostics_label.visible = diagnostics_visible
		get_viewport().set_input_as_handled()
		return
	if not _local_is_eliminated() or input_blocked:
		return
	var direction := 0
	if event.is_action_pressed(&"spectator_previous") and not (event is InputEventKey and event.echo):
		direction = -1
	elif event.is_action_pressed(&"spectator_next") and not (event is InputEventKey and event.echo):
		direction = 1
	if direction != 0:
		_cycle_spectator(direction)
		get_viewport().set_input_as_handled()


func _on_projectile_batch(decoded: Dictionary) -> void:
	for projectile_value in decoded.spawned:
		var projectile := projectile_value as ProjectileState
		if projectile.owner_id == local_peer_id and predicted_projectile_ids.has(projectile.shot_sequence):
			var predicted_ids := predicted_projectile_ids[projectile.shot_sequence] as Array
			for predicted_id in predicted_ids:
				authoritative_projectiles.remove(int(predicted_id))
			predicted_projectile_ids.erase(projectile.shot_sequence)
			predicted_tracker.reconcile(projectile.owner_id, projectile.shot_sequence)
		authoritative_projectiles.add(projectile)
		presentation_event.emit(&"beam_fire" if projectile.is_beam else &"fire", {"projectile_id": projectile.projectile_id, "owner_id": projectile.owner_id, "shot_sequence": projectile.shot_sequence})
	for projectile_id in decoded.removed:
		var projectile := authoritative_projectiles.get_projectile(int(projectile_id))
		if projectile != null and effects_layer != null:
			effects_layer.spawn_impact(projectile.position)
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
		var existing := ships[peer_id] as SandboxShip
		existing.display_name = _display_name(peer_id)
		return existing
	var ship := SandboxShip.new()
	var color := _player_color(peer_id)
	ship.setup(peer_id, local_stats, state.position, color, peer_id == local_peer_id, _display_name(peer_id))
	add_child(ship)
	ships[peer_id] = ship
	return ship


func _apply_snapshot_resources(ship: SandboxShip, state: Dictionary) -> void:
	var was_alive := ship.combatant.alive
	if bool(state.alive) and not was_alive:
		ship.reset_ship(local_stats, state.position)
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
	var predicted_ids: Array[int] = []
	for angle in MovementSystem.spread_angles(aim_angle, local_stats.projectile_count, local_stats.projectile_spread_degrees):
		var projectile := ProjectileState.create(next_predicted_id, local_peer_id, local_weapon.shot_sequence, muzzle, angle, local_stats)
		authoritative_projectiles.add(projectile)
		predicted_ids.append(next_predicted_id)
		next_predicted_id -= 1
	predicted_projectile_ids[local_weapon.shot_sequence] = predicted_ids
	predicted_tracker.add(local_peer_id, local_weapon.shot_sequence, _now_seconds())
	presentation_event.emit(&"beam_fire" if local_stats.beam_weapon else &"fire", {"owner_id": local_peer_id, "shot_sequence": local_weapon.shot_sequence})


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
			target_position = ArenaLayout.center(arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID)
	camera.position = camera.position.lerp(target_position, 1.0 - exp(-8.0 * delta))


func _create_camera_and_hud() -> void:
	camera = Camera2D.new()
	camera.position = ArenaLayout.center(arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID)
	camera.enabled = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	canvas.name = "CombatHUD"
	canvas.layer = 10
	add_child(canvas)
	hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(16.0, 16.0)
	hud_panel.custom_minimum_size = Vector2(430.0, 148.0)
	hud_panel.add_theme_stylebox_override("panel", _hud_panel_style())
	hud_panel.visible = false
	canvas.add_child(hud_panel)
	var hud_content := VBoxContainer.new()
	hud_content.add_theme_constant_override("separation", 3)
	hud_panel.add_child(hud_content)
	match_status_label = Label.new()
	match_status_label.add_theme_font_size_override("font_size", 16)
	match_status_label.add_theme_color_override("font_color", Color("73f7ff"))
	match_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hud_content.add_child(match_status_label)
	resources_label = Label.new()
	resources_label.add_theme_font_size_override("font_size", 17)
	resources_label.add_theme_color_override("font_color", Color("e8f5ff"))
	hud_content.add_child(resources_label)
	health_bar = _make_resource_bar(Color("54ff8b"))
	hud_content.add_child(health_bar)
	shield_bar = _make_resource_bar(Color("5cf6ff"))
	hud_content.add_child(shield_bar)
	combat_status_label = Label.new()
	combat_status_label.add_theme_font_size_override("font_size", 14)
	combat_status_label.add_theme_color_override("font_color", Color("aebbd4"))
	hud_content.add_child(combat_status_label)
	spectator_label = Label.new()
	spectator_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spectator_label.position = Vector2(-360.0, -92.0)
	spectator_label.custom_minimum_size = Vector2(720.0, 64.0)
	spectator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spectator_label.add_theme_font_size_override("font_size", 24)
	spectator_label.add_theme_color_override("font_color", Color("fff36a"))
	canvas.add_child(spectator_label)
	diagnostics_label = Label.new()
	diagnostics_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	diagnostics_label.position = Vector2(-620.0, -120.0)
	diagnostics_label.custom_minimum_size = Vector2(600.0, 96.0)
	diagnostics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	diagnostics_label.add_theme_color_override("font_color", Color("73f7ff"))
	diagnostics_label.add_theme_font_size_override("font_size", 16)
	diagnostics_label.visible = false
	canvas.add_child(diagnostics_label)


func _update_diagnostics() -> void:
	var resources := "Waiting for combat snapshot"
	var diagnostics_hint: String = input_profiles.binding_text(&"diagnostics") if input_profiles != null else "F3"
	var scoreboard_hint: String = input_profiles.binding_text(&"scoreboard") if input_profiles != null else "Tab"
	var combat_status := "%s network diagnostics · Hold %s scoreboard" % [diagnostics_hint, scoreboard_hint]
	if ships.has(local_peer_id):
		var local_ship := ships[local_peer_id] as SandboxShip
		health_bar.max_value = local_stats.max_health
		health_bar.value = local_ship.combatant.health
		shield_bar.max_value = local_stats.shield_capacity
		shield_bar.value = local_ship.combatant.shield.energy
		resources = "HULL %.0f/%.0f   SHIELD %.0f/%.0f   AMMO %d/%d" % [local_ship.combatant.health, local_stats.max_health, local_ship.combatant.shield.energy, local_stats.shield_capacity, local_ship.combatant.weapon.ammunition, local_stats.magazine_size]
		var reload_hint: String = input_profiles.binding_text(&"manual_reload") if input_profiles != null else "R"
		combat_status = "%s diagnostics   ·   Hold %s scoreboard   ·   %s reload" % [diagnostics_hint, scoreboard_hint, reload_hint]
		if not local_ship.combatant.alive:
			resources = "SHIP ELIMINATED"
			var previous_hint: String = input_profiles.binding_text(&"spectator_previous") if input_profiles != null else "A"
			var next_hint: String = input_profiles.binding_text(&"spectator_next") if input_profiles != null else "D"
			spectator_label.text = "SPECTATING %s   ◀ %s     %s ▶" % [_display_name(spectator_target_id), previous_hint, next_hint] if spectator_target_id != 0 else "NO SURVIVING TARGET · ARENA VIEW"
			spectator_label.visible = true
		else:
			spectator_label.visible = false
	resources_label.text = resources
	combat_status_label.text = combat_status
	diagnostics_label.text = "NETWORK · FPS %d · RTT %d ms · peer %d · ack %d\nerror %.2f px · snaps %d · players %d · projectiles %d · interpolation 100 ms" % [Engine.get_frames_per_second(), bridge.get_round_trip_time_ms(), local_peer_id, latest_acknowledged_input, prediction.last_reconciliation_error, prediction.snap_count, ships.size(), authoritative_projectiles.size()]


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


func nearest_incoming_offscreen_projectile() -> ProjectileState:
	if not ships.has(local_peer_id):
		return null
	var local_position := (ships[local_peer_id] as SandboxShip).global_position
	var nearest: ProjectileState
	var nearest_distance := INF
	for projectile in authoritative_projectiles.all_projectiles():
		if projectile.owner_id == local_peer_id:
			continue
		var offset := local_position - projectile.position
		var distance := offset.length()
		if distance <= 0.001 or projectile.velocity.normalized().dot(offset / distance) < 0.72:
			continue
		if distance < nearest_distance:
			nearest = projectile
			nearest_distance = distance
	return nearest


func trigger_camera_shake(intensity: float, duration: float) -> void:
	camera_shake_intensity = maxf(camera_shake_intensity, intensity)
	camera_shake_remaining = maxf(camera_shake_remaining, duration)


func _create_indicator_layer() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "OffscreenIndicators"
	canvas.layer = 8
	add_child(canvas)
	indicator_layer = OffscreenIndicatorLayer.new()
	indicator_layer.setup(self)
	canvas.add_child(indicator_layer)


func _handle_snapshot_feedback(peer_id: int, state: Dictionary, ship: SandboxShip) -> void:
	if not presentation_states.has(peer_id):
		presentation_states[peer_id] = state.duplicate(true)
		return
	var previous := presentation_states[peer_id] as Dictionary
	var health_drop := float(previous.get("health", 0.0)) - float(state.get("health", 0.0))
	var shield_drop := float(previous.get("shield", 0.0)) - float(state.get("shield", 0.0))
	if health_drop > 0.05:
		ship.flash_damage()
		var direction := -(state.get("velocity", Vector2.ZERO) as Vector2).normalized()
		if direction.is_zero_approx():
			direction = Vector2.from_angle(float(state.get("aim_angle", 0.0)) + PI)
		if effects_layer != null:
			effects_layer.spawn_damage(state.position, direction)
		presentation_event.emit(&"damage", {"peer_id": peer_id, "server_tick": latest_server_tick})
		if peer_id == local_peer_id:
			trigger_camera_shake(5.0, 0.16)
	if not bool(previous.get("shielding", false)) and bool(state.get("shielding", false)):
		presentation_event.emit(&"shield_on", {"peer_id": peer_id, "server_tick": latest_server_tick})
	if shield_drop > 2.0 and bool(previous.get("shielding", false)):
		ship.flash_shield_block()
		presentation_event.emit(&"shield_block", {"peer_id": peer_id, "server_tick": latest_server_tick})
	var depletion_threshold := (
		local_stats.shield_depletion_threshold
		if peer_id == local_peer_id
		else GameConstants.SHIELD_DEPLETION_THRESHOLD
	)
	if float(previous.get("shield", 0.0)) >= depletion_threshold and float(state.get("shield", 0.0)) < depletion_threshold:
		presentation_event.emit(&"shield_break", {"peer_id": peer_id, "server_tick": latest_server_tick})
	if bool(previous.get("alive", true)) and not bool(state.get("alive", true)):
		if effects_layer != null:
			effects_layer.spawn_elimination(state.position, ship.ship_color)
		presentation_event.emit(&"elimination", {"peer_id": peer_id, "server_tick": latest_server_tick})
		if peer_id == local_peer_id:
			trigger_camera_shake(9.0, 0.3)
	if peer_id == local_peer_id and int(state.get("ammunition", 0)) > int(previous.get("ammunition", 0)) + 1:
		presentation_event.emit(&"reload", {"peer_id": peer_id, "server_tick": latest_server_tick})
	presentation_states[peer_id] = state.duplicate(true)


func _update_overtime_presentation() -> void:
	if arena == null:
		return
	var overtime_tick := int(match_payload.get("overtime_start_tick", -1))
	var active := controls_enabled and overtime_tick >= 0 and latest_server_tick >= overtime_tick
	var radius := OvertimeSystem.initial_radius()
	if active:
		var elapsed := GameConstants.OVERTIME_START_SECONDS + float(latest_server_tick - overtime_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND
		radius = OvertimeSystem.radius_at(elapsed)
	arena.set_overtime(active, radius)


func _update_camera_shake(delta: float) -> void:
	if camera == null:
		return
	if camera_shake_remaining <= 0.0:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
		return
	camera_shake_remaining = maxf(camera_shake_remaining - delta, 0.0)
	var fade := minf(camera_shake_remaining * 8.0, 1.0)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * camera_shake_intensity * fade


func _unshaken_mouse_world_position() -> Vector2:
	if camera == null:
		return get_global_mouse_position()
	var screen_offset := get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
	return camera.position + Vector2(screen_offset.x / camera.zoom.x, screen_offset.y / camera.zoom.y)


func _player_color(peer_id: int) -> Color:
	var palette: Array[Color] = [
		Color("42e8ff"), Color("ff4f78"), Color("fff36a"), Color("62ff9b"),
		Color("d39cff"), Color("ff9f43"), Color("5cf6ff"), Color("ff66d4"),
	]
	return palette[posmod(peer_id, palette.size())]


func _display_name(peer_id: int) -> String:
	for player_value in bridge.latest_lobby_state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == peer_id:
			return String(player.get("display_name", "Pilot %d" % peer_id))
	return "Pilot %d" % peer_id


func _make_resource_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(390.0, 12.0)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _flat_style(Color("101a36"), Color("31466c"), 1))
	bar.add_theme_stylebox_override("fill", _flat_style(Color(color.darkened(0.45), 0.94), color, 1))
	return bar


func _hud_panel_style() -> StyleBoxFlat:
	var style := _flat_style(Color("071024", 0.9), Color("42e8ff", 0.75), 2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _flat_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(10)
	return style


static func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
