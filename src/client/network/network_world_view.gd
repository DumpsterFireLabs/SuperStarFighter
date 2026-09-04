class_name NetworkWorldView
extends Node2D

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const AccessibilityPreferencesScript = preload("res://src/client/presentation/accessibility_preferences.gd")

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const PowerupLayerScript = preload("res://src/client/presentation/powerup_layer.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const KillFeedScript = preload("res://src/client/ui/kill_feed.gd")
const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")
const PROJECTILE_COLLISION_ITERATIONS: int = 16
const COLLISION_SURFACE_EPSILON: float = 0.35
const LOCAL_CONTACT_ESCAPE_SPEED: float = 180.0
const MIN_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS: float = 0.4
const MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS: float = 1.25
const PROJECTILE_CONFIRMATION_RTT_MULTIPLIER: float = 2.0
const PROJECTILE_CONFIRMATION_GRACE_SECONDS: float = 0.2
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
var powerup_layer: Node2D
var prediction := ClientPredictionBuffer.new()
var interpolation := RemoteInterpolator.new()
var predicted_tracker := PredictedProjectileTracker.new()
var predicted_projectile_ids: Dictionary = {}
var local_weapon := WeaponState.new()
var local_stats := CombatStats.create_base()
var camera: Camera2D
var diagnostics_label: Label
var hud_panel: PanelContainer
var hud_root: Control
var accessibility_settings: Dictionary = AccessibilityPreferencesScript.DEFAULTS.duplicate()
var match_status_label: Label
var resources_label: Label
var combat_status_label: Label
var spectator_label: Label
var combat_feedback_panel: CombatFeedbackPanel
var kill_feed: Control
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
var toggle_status_label: Label
var action_latch = preload("res://src/client/input/combat_action_latch.gd").new()
var input_blocked: bool = false:
	set(value):
		input_blocked = value
		if value:
			action_latch.reset()
var presentation_states: Dictionary = {}
var camera_shake_remaining: float = 0.0
var camera_shake_intensity: float = 0.0
var camera_kick_remaining: float = 0.0
var camera_kick_duration: float = 0.0
var camera_kick_offset: Vector2 = Vector2.ZERO
var diagnostics_visible: bool = false
var special_activation_sends_remaining: int = 0
var special_activation_sequence: int = 0
var selected_special_slot: int = -1
var special_activation_slot: int = -1
var local_active_ordnance: int = 0
var local_active_mines: int = 0
var local_budget_evictions: int = 0
var budget_warning_remaining: float = 0.0
var local_special_cooldown_remaining: float = 0.0
var local_mine_charges_remaining: int = 0
var local_mine_cooldown_remaining: float = 0.0
var local_missile_charges_remaining: int = 0
var local_missile_cooldown_remaining: float = 0.0
var local_cloak_charges_remaining: int = 0
var local_cloak_remaining: float = 0.0
var local_cloak_cooldown_remaining: float = 0.0
var local_breakaway_remaining: float = 0.0
var local_kinetic_vent_charge: float = 0.0
var local_breakaway_cooldown_remaining: float = 0.0
var _nearest_incoming_cache: ProjectileState
var _nearest_incoming_revision: int = -1
var _incoming_refresh_accumulator: float = 0.0
var _diagnostics_refresh_accumulator: float = 0.0
var expired_predicted_volleys: int = 0
var last_snapshot_receive_time: float = -1.0
var snapshot_jitter_ms: float = 0.0
var snapshot_gap_count: int = 0
var interpolation_sample_count: int = 0
var interpolation_extrapolated_count: int = 0


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
	powerup_layer = PowerupLayerScript.new()
	powerup_layer.name = "CardPowerups"
	powerup_layer.z_index = 1
	add_child(powerup_layer)
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
	if not active:
		action_latch.reset()
	if not active and reset_when_inactive:
		reset_session()
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if camera != null:
		camera.enabled = active
	if diagnostics_label != null:
		var diagnostics_canvas := hud_root.get_parent() as CanvasLayer
		diagnostics_canvas.visible = active


func reset_session() -> void:
	action_latch.reset()
	if combat_feedback_panel != null:
		combat_feedback_panel.clear_feedback(true)
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
	camera_kick_remaining = 0.0
	camera_kick_duration = 0.0
	camera_kick_offset = Vector2.ZERO
	special_activation_sends_remaining = 0
	special_activation_sequence = 0
	selected_special_slot = -1
	special_activation_slot = -1
	local_active_ordnance = 0
	local_active_mines = 0
	local_budget_evictions = 0
	budget_warning_remaining = 0.0
	local_special_cooldown_remaining = 0.0
	local_mine_charges_remaining = 0
	local_mine_cooldown_remaining = 0.0
	local_missile_charges_remaining = 0
	local_missile_cooldown_remaining = 0.0
	local_cloak_charges_remaining = 0
	local_cloak_remaining = 0.0
	local_cloak_cooldown_remaining = 0.0
	local_breakaway_remaining = 0.0
	local_kinetic_vent_charge = 0.0
	local_breakaway_cooldown_remaining = 0.0
	_nearest_incoming_cache = null
	_nearest_incoming_revision = -1
	_incoming_refresh_accumulator = 0.0
	_diagnostics_refresh_accumulator = 0.0
	expired_predicted_volleys = 0
	last_snapshot_receive_time = -1.0
	snapshot_jitter_ms = 0.0
	snapshot_gap_count = 0
	interpolation_sample_count = 0
	interpolation_extrapolated_count = 0
	prediction = ClientPredictionBuffer.new()
	interpolation = RemoteInterpolator.new()
	predicted_tracker = PredictedProjectileTracker.new()
	local_weapon = WeaponState.new()
	local_weapon.reset(local_stats)
	if projectile_layer != null:
		projectile_layer.set_beam_builds({}, card_catalog)
		projectile_layer.set_team_identity({}, 0, false)
	if effects_layer != null:
		effects_layer.clear_effects()
	if powerup_layer != null:
		powerup_layer.clear_powerups()
	if kill_feed != null:
		kill_feed.clear()
	if arena != null:
		arena.set_map_id(ArenaLayout.DEFAULT_MAP_ID)
		arena.set_overtime(false, OvertimeSystem.initial_radius())
		arena.set_objective({})
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
	_advance_input_clock()
	input_send_accumulator += delta
	local_special_cooldown_remaining = maxf(local_special_cooldown_remaining - maxf(delta, 0.0), 0.0)
	budget_warning_remaining = maxf(budget_warning_remaining - maxf(delta, 0.0), 0.0)
	local_mine_cooldown_remaining = maxf(local_mine_cooldown_remaining - maxf(delta, 0.0), 0.0)
	local_missile_cooldown_remaining = maxf(local_missile_cooldown_remaining - maxf(delta, 0.0), 0.0)
	local_cloak_remaining = maxf(local_cloak_remaining - maxf(delta, 0.0), 0.0)
	local_cloak_cooldown_remaining = maxf(local_cloak_cooldown_remaining - maxf(delta, 0.0), 0.0)
	local_breakaway_remaining = maxf(local_breakaway_remaining - maxf(delta, 0.0), 0.0)
	local_breakaway_cooldown_remaining = maxf(local_breakaway_cooldown_remaining - maxf(delta, 0.0), 0.0)
	var local_ship := ships[local_peer_id] as SandboxShip
	var aim_vector: Vector2 = input_profiles.aim_vector() if input_profiles != null and input_profiles.uses_controller() else _unshaken_mouse_world_position() - local_ship.global_position
	var aim_angle := local_ship.combatant.aim_angle
	if not aim_vector.is_zero_approx():
		aim_angle = aim_vector.angle()
	var local_movement: Vector2 = input_profiles.movement_input_for_aim(aim_angle) if input_profiles != null else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var local_alive := local_ship.combatant.alive
	if not controls_enabled or input_blocked:
		local_movement = Vector2.ZERO
	local_ship.set_thrust_input(local_movement)
	var afterburner_ready := local_stats.afterburner_enabled and local_special_cooldown_remaining <= 0.0
	var mine_ready := local_stats.mine_layer_enabled and local_mine_charges_remaining > 0 and local_mine_cooldown_remaining <= 0.0
	var missile_ready := local_stats.missile_launcher_enabled and local_missile_charges_remaining > 0 and local_missile_cooldown_remaining <= 0.0
	var cloak_ready := local_stats.cloak_enabled and local_cloak_charges_remaining > 0 and local_cloak_remaining <= 0.0 and local_cloak_cooldown_remaining <= 0.0
	selected_special_slot = SpecialAbilitySelection.ensure_owned(selected_special_slot, local_stats)
	if controls_enabled and not input_blocked and local_alive:
		if Input.is_action_just_pressed("special_previous"):
			selected_special_slot = SpecialAbilitySelection.cycle(selected_special_slot, local_stats, -1)
		if Input.is_action_just_pressed("special_next"):
			selected_special_slot = SpecialAbilitySelection.cycle(selected_special_slot, local_stats, 1)
	var readiness := [afterburner_ready, mine_ready, missile_ready, cloak_ready]
	var special_just_pressed := (
		controls_enabled
		and not input_blocked
		and local_alive
		and selected_special_slot >= 0 and bool(readiness[selected_special_slot])
		and Input.is_action_just_pressed("special")
	)
	if special_just_pressed:
		special_activation_sends_remaining = 3
		special_activation_sequence = input_sequence
		special_activation_slot = selected_special_slot
	elif not controls_enabled or input_blocked or not local_alive:
		special_activation_sends_remaining = 0
	var frame := PlayerInputFrame.new(
		input_sequence,
		client_tick,
		local_movement,
		aim_angle,
		action_latch.sample(&"fire", Input.is_action_pressed("fire"), bool(accessibility_settings.toggle_fire), controls_enabled and not input_blocked and local_alive and local_cloak_remaining <= 0.0),
		action_latch.sample(&"shield", Input.is_action_pressed("shield"), bool(accessibility_settings.toggle_shield), controls_enabled and not input_blocked and local_alive),
		controls_enabled and not input_blocked and local_alive and Input.is_action_pressed("manual_reload"),
		special_activation_sends_remaining > 0,
		special_activation_sequence,
		special_activation_slot
	)
	var send_interval := 1.0 / GameConstants.INPUT_SEND_RATE
	if input_send_accumulator >= send_interval:
		input_send_accumulator = fmod(input_send_accumulator, send_interval)
		bridge.send_input(frame)
		special_activation_sends_remaining = maxi(special_activation_sends_remaining - 1, 0)
	if prediction_initialized and local_alive and controls_enabled:
		prediction.predict(frame, local_stats, delta, arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID, local_breakaway_remaining > 0.0)
		_sync_predicted_resources(local_ship)
		if prediction.last_actions & CombatantState.ACTION_BOOST:
			local_ship.flash_afterburner(local_stats.afterburner_duration)
			trigger_afterburner_feedback(Vector2.from_angle(aim_angle))
			presentation_event.emit(&"afterburner", {
				"peer_id": local_peer_id,
				"server_tick": client_tick,
				"position": local_ship.global_position,
				"listener_position": local_ship.global_position,
				"local": true,
			})
		local_ship.global_position = prediction.visual_position(delta)
		local_ship.combatant.position = local_ship.global_position
		local_ship.combatant.velocity = prediction.predicted_velocity
		local_ship.combatant.aim_angle = aim_angle
		local_ship.queue_redraw()
		if prediction.last_actions & CombatantState.ACTION_SHOT:
			_spawn_predicted_projectile(local_ship, aim_angle)
	local_ship.combatant.weapon.ammunition = local_weapon.ammunition
	local_ship.combatant.weapon.reloading = local_weapon.reloading
	local_ship.combatant.weapon.reload_remaining = local_weapon.reload_remaining
	local_ship.queue_redraw()
	_update_remote_ships()
	_separate_local_visual_from_remote(local_ship)
	_step_projectile_visuals(delta)
	_incoming_refresh_accumulator += maxf(delta, 0.0)
	if _incoming_refresh_accumulator >= 0.1:
		_incoming_refresh_accumulator = fmod(_incoming_refresh_accumulator, 0.1)
		_refresh_nearest_incoming_projectile()
	_update_camera(local_ship, delta)
	_update_camera_shake(delta)
	_update_overtime_presentation()
	_expire_unconfirmed_predicted_projectiles(_now_seconds())
	_update_diagnostics(delta)
	queue_redraw()


func _advance_input_clock() -> void:
	client_tick = SequenceMath.increment(client_tick)
	# Every predicted physics frame needs its own sequence, including frames
	# between the 30 Hz network sends. Otherwise an acknowledgement for the
	# previous send can incorrectly prune newer local movement from replay.
	input_sequence = SequenceMath.increment(input_sequence)


func _on_connected(peer_id: int) -> void:
	local_peer_id = peer_id
	set_network_active(true)


func _on_snapshot(decoded: Dictionary) -> void:
	latest_acknowledged_input = int(decoded.acknowledged_input)
	var receive_time := _now_seconds()
	_record_snapshot_arrival(int(decoded.server_tick), receive_time)
	latest_server_tick = int(decoded.server_tick)
	var present_ids: Dictionary = {}
	for state_value in decoded.states:
		var state := state_value as Dictionary
		var peer_id := int(state.peer_id)
		present_ids[peer_id] = true
		var ship := _ensure_ship(peer_id, state)
		var revived := bool(state.alive) and not ship.combatant.alive
		ship.visible = String(match_payload.get("state_name", "")) != "DRAFT"
		_handle_snapshot_feedback(peer_id, state, ship)
		_apply_snapshot_resources(ship, state)
		if peer_id == local_peer_id:
			var correction := state.duplicate()
			var local_state := decoded.get("local_state", {}) as Dictionary
			if int(local_state.get("peer_id", 0)) == local_peer_id:
				correction.merge(local_state, true)
				local_active_ordnance = int(local_state.get("active_ordnance", 0))
				local_active_mines = int(local_state.get("active_mines", 0))
				var evictions := int(local_state.get("budget_evictions", 0))
				if evictions > local_budget_evictions:
					budget_warning_remaining = 2.0
				local_budget_evictions = evictions
			var new_life := prediction.simulated_combatant != null and int(correction.get("life_generation", prediction.simulated_combatant.life_generation)) != prediction.simulated_combatant.life_generation
			if not prediction_initialized or revived or new_life or not bool(state.alive):
				if combat_feedback_panel != null:
					combat_feedback_panel.reset_for_life(int(correction.get("life_generation", 0)))
				prediction.reset_to_snapshot(correction, local_stats)
				if revived or new_life or not bool(state.alive):
					special_activation_sends_remaining = 0
					for shot_sequence in predicted_projectile_ids.keys():
						_remove_predicted_volley(int(shot_sequence))
					predicted_tracker = PredictedProjectileTracker.new()
				ship.global_position = state.position
				camera.position = state.position
				prediction_initialized = true
			else:
				prediction.reconcile(
					state.position,
					state.velocity,
					decoded.acknowledged_input,
					local_stats,
					arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID,
					local_breakaway_remaining > 0.0,
					correction
				)
			_sync_predicted_resources(ship)
		else:
			interpolation.add_sample(peer_id, receive_time, latest_server_tick, state)
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if not present_ids.has(peer_id):
			(ships[peer_id] as SandboxShip).queue_free()
			ships.erase(peer_id)
			interpolation.remove_peer(peer_id)
			# A cloak disappearance is not a death. Forget prior feedback as well
			# as interpolation so reappearance cannot flash stale damage/guard FX.
			presentation_states.erase(peer_id)
	_update_spectator_target()


func _sync_predicted_resources(ship: SandboxShip) -> void:
	var simulated := prediction.simulated_combatant
	if simulated == null:
		return
	local_weapon = simulated.weapon
	local_special_cooldown_remaining = simulated.afterburner_cooldown_remaining
	local_mine_charges_remaining = simulated.mine_charges_remaining
	local_mine_cooldown_remaining = simulated.mine_cooldown_remaining
	local_missile_charges_remaining = simulated.missile_charges_remaining
	local_missile_cooldown_remaining = simulated.missile_cooldown_remaining
	local_cloak_charges_remaining = simulated.cloak_charges_remaining
	local_cloak_remaining = simulated.cloak_remaining
	local_cloak_cooldown_remaining = simulated.cloak_cooldown_remaining
	local_breakaway_remaining = simulated.breakaway_remaining
	local_breakaway_cooldown_remaining = simulated.breakaway_cooldown_remaining
	local_kinetic_vent_charge = simulated.shield.kinetic_vent_charge
	ship.combatant.weapon = local_weapon
	# Keep presentation resources separate from the replay state: snapshots
	# update the visual ship before the buffered inputs have been replayed.
	ship.combatant.shield.energy = simulated.shield.energy
	ship.combatant.shield.active = simulated.shield.active
	ship.combatant.cloak_remaining = simulated.cloak_remaining
	ship.combatant.breakaway_remaining = simulated.breakaway_remaining


func apply_match_state(payload: Dictionary) -> void:
	match_payload = payload.duplicate(true)
	var payload_map_id := StringName(payload.get("map_id", ArenaLayout.DEFAULT_MAP_ID))
	if arena != null:
		arena.set_map_id(payload_map_id)
		arena.local_peer_id = local_peer_id
		arena.local_team_id = team_for_peer(local_peer_id)
		arena.pilot_names.clear()
		for player in payload.get("players", []):
			var peer_id := int(player.get("peer_id", 0))
			arena.pilot_names[peer_id] = _display_name(peer_id)
		arena.set_objective(payload.get("objective", {}) as Dictionary)
	var state_name := String(payload.get("state_name", ""))
	controls_enabled = state_name == "ACTIVE_HEAT"
	for ship_value in ships.values():
		var ship := ship_value as SandboxShip
		ship.visible = state_name != "DRAFT"
		ship.display_name = _display_name(ship.combatant.peer_id)
		ship.set_ship_appearance(_player_color(ship.combatant.peer_id), _player_pattern(ship.combatant.peer_id))
		ship.set_team_identity(team_for_peer(ship.combatant.peer_id), team_for_peer(local_peer_id))
	if projectile_layer != null:
		projectile_layer.set_team_identity(match_payload.get("teams", {}) as Dictionary, team_for_peer(local_peer_id), GameModeRules.is_team_mode(int(match_payload.get("game_mode", 0))))
	_nearest_incoming_revision = -1
	if hud_panel != null:
		hud_panel.visible = state_name in ["COUNTDOWN", "ACTIVE_HEAT", "HEAT_RESULT", "ROUND_RESULT"]
	if kill_feed != null:
		kill_feed.set_match_state(state_name)
	apply_builds(payload.get("builds", {}) as Dictionary)
	if powerup_layer != null:
		powerup_layer.set_powerups(payload.get("powerups", []) as Array)
	if String(payload.get("state_name", "")) == "COUNTDOWN":
		if combat_feedback_panel != null:
			combat_feedback_panel.clear_feedback(true)
		local_weapon.reset(local_stats)
		prediction_initialized = false
		# Spawn changes are authoritative teleports. Discard interpolation from
		# the previous heat so remote humans and NPCs snap to their new starts.
		interpolation.clear()
		presentation_states.clear()
		if effects_layer != null:
			effects_layer.clear_effects()
		snap_camera_to_local_ship()
	_update_spectator_target()


func apply_objective_state(objective: Dictionary) -> void:
	match_payload["objective"] = objective.duplicate(true)
	if arena != null:
		arena.set_objective(objective)


func apply_builds(builds: Dictionary) -> void:
	if projectile_layer != null:
		projectile_layer.set_beam_builds(builds, card_catalog)
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		var ship := ships[peer_id] as SandboxShip
		ship.combatant.stats = _stats_for_peer(peer_id, builds).duplicate_stats()
		ship.set_shield_build(builds.get(peer_id, builds.get(str(peer_id), {})) as Dictionary, card_catalog)
	local_stats = _stats_for_peer(local_peer_id, builds)


func add_card_powerup(payload: Dictionary) -> void:
	if powerup_layer != null:
		powerup_layer.add_powerup(payload)


func collect_card_powerup(payload: Dictionary) -> void:
	if powerup_layer != null:
		powerup_layer.remove_powerup(int(payload.get("powerup_id", 0)))
	if effects_layer != null:
		var card := card_catalog.get_card(StringName(payload.get("card_id", &"")))
		effects_layer.spawn_impact(payload.get("position", Vector2.ZERO) as Vector2, card.rarity_color() if card != null else Color("42e8ff"))


func add_kill_feed_entries(eliminations: Array, server_tick: int) -> void:
	if kill_feed != null:
		kill_feed.add_eliminations(
			eliminations,
			server_tick,
			local_peer_id,
			match_payload.get("players", []) as Array
		)


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
	var emitted_shots: Dictionary = {}
	for projectile_value in decoded.spawned:
		var projectile := projectile_value as ProjectileState
		if not projectile.is_mine:
			_reconcile_predicted_projectile(projectile)
		var existing := authoritative_projectiles.get_projectile(projectile.projectile_id)
		if existing == null:
			authoritative_projectiles.add(projectile)
			if projectile.has_rebounded:
				_emit_rebound_feedback(projectile)
		else:
			var newly_rebounded := _synchronize_projectile(existing, projectile)
			if newly_rebounded:
				_emit_rebound_feedback(projectile)
		if projectile.is_mine or existing != null or projectile.has_rebounded:
			continue
		if projectile.is_missile:
			presentation_event.emit(&"missile_launch", {
				"projectile_id": projectile.projectile_id,
				"owner_id": projectile.owner_id,
				"position": projectile.position,
				"listener_position": _audio_listener_position(),
				"server_tick": latest_server_tick,
			})
			continue
		var shot_key := "%d:%d" % [projectile.owner_id, projectile.shot_sequence]
		if not emitted_shots.has(shot_key):
			emitted_shots[shot_key] = true
			_emit_weapon_shot(projectile.owner_id, projectile.shot_sequence, projectile.position, projectile)
	for projectile_id in decoded.removed:
		var projectile := authoritative_projectiles.get_projectile(int(projectile_id))
		if projectile != null and effects_layer != null and not projectile.is_mine:
			effects_layer.spawn_impact(projectile.position)
		if projectile != null and not projectile.is_mine:
			presentation_event.emit(&"projectile_impact", {
				"projectile_id": projectile.projectile_id,
				"owner_id": projectile.owner_id,
				"position": projectile.position,
				"listener_position": _audio_listener_position(),
				"server_tick": latest_server_tick,
			})
		authoritative_projectiles.remove(int(projectile_id))


func _on_projectile_correction(decoded: Dictionary) -> void:
	var authoritative_ids: Dictionary = {}
	for projectile_value in decoded.spawned:
		var projectile := projectile_value as ProjectileState
		# A correction can be the first authoritative evidence of a shot when its
		# unreliable delta was lost. Promote it immediately instead of rendering
		# the authoritative and predicted copies together until the timeout.
		if not projectile.is_mine:
			_reconcile_predicted_projectile(projectile)
		authoritative_ids[projectile.projectile_id] = true
		var existing := authoritative_projectiles.get_projectile(projectile.projectile_id)
		if existing == null:
			authoritative_projectiles.add(projectile)
			if projectile.has_rebounded:
				_emit_rebound_feedback(projectile)
		else:
			var newly_rebounded := _synchronize_projectile(existing, projectile)
			if newly_rebounded:
				_emit_rebound_feedback(projectile)
	if bool(decoded.get("complete_snapshot", true)):
		for projectile in authoritative_projectiles.all_projectiles():
			if projectile.projectile_id > 0 and not authoritative_ids.has(projectile.projectile_id):
				authoritative_projectiles.remove(projectile.projectile_id)


func _ensure_ship(peer_id: int, state: Dictionary) -> SandboxShip:
	if ships.has(peer_id):
		var existing := ships[peer_id] as SandboxShip
		existing.display_name = _display_name(peer_id)
		# Lobby state and snapshots use independent ENet channels. A guest can
		# receive the first snapshot before the final reliable lobby update, so
		# refresh identity data instead of freezing whatever was available when
		# the presentation node happened to be created.
		existing.set_ship_appearance(_player_color(peer_id), _player_pattern(peer_id))
		return existing
	var ship := SandboxShip.new()
	ship.reduced_flashes = bool(accessibility_settings.reduced_flashes)
	ship.high_contrast = bool(accessibility_settings.high_contrast)
	var color := _player_color(peer_id)
	ship.setup(peer_id, _stats_for_peer(peer_id), state.position, color, peer_id == local_peer_id, _display_name(peer_id), _player_pattern(peer_id))
	ship.set_team_identity(team_for_peer(peer_id), team_for_peer(local_peer_id))
	ship.set_shield_build(_build_for_peer(peer_id), card_catalog)
	add_child(ship)
	ships[peer_id] = ship
	return ship


func _apply_snapshot_resources(ship: SandboxShip, state: Dictionary) -> void:
	var was_alive := ship.combatant.alive
	if bool(state.alive) and not was_alive:
		ship.reset_ship(_stats_for_peer(ship.combatant.peer_id), state.position)
	ship.combatant.position = state.position
	ship.combatant.velocity = state.velocity
	ship.combatant.aim_angle = state.aim_angle
	ship.combatant.health = state.health
	ship.combatant.shield.energy = state.shield
	ship.combatant.shield.active = state.shielding
	ship.combatant.afterburner_remaining = 0.1 if bool(state.get("afterburner_active", false)) else 0.0
	ship.combatant.mine_charges_remaining = int(state.get("mine_charges", 0))
	ship.combatant.mine_cooldown_remaining = float(state.get("mine_cooldown", 0.0))
	ship.combatant.missile_charges_remaining = int(state.get("missile_charges", 0))
	ship.combatant.missile_cooldown_remaining = float(state.get("missile_cooldown", 0.0))
	ship.combatant.cloak_remaining = maxf(ship.combatant.cloak_remaining, 0.1) if bool(state.get("cloaked", false)) else 0.0
	ship.combatant.cloak_charges_remaining = int(state.get("cloak_charges", 0))
	ship.combatant.cloak_cooldown_remaining = float(state.get("cloak_cooldown", 0.0))
	ship.combatant.shield.perfect_guard_window_remaining = 0.1 if bool(state.get("perfect_guard_active", false)) else 0.0
	ship.combatant.breakaway_remaining = 0.1 if bool(state.get("breakaway_active", false)) else 0.0
	ship.combatant.kinetic_vent_feedback_remaining = 0.1 if bool(state.get("kinetic_vent_active", false)) else 0.0
	ship.combatant.shield.kinetic_vent_charge = float(state.get("kinetic_vent_charge", 0.0))
	ship.combatant.breakaway_cooldown_remaining = float(state.get("breakaway_cooldown", 0.0))
	if ship.combatant.peer_id == local_peer_id:
		local_mine_charges_remaining = ship.combatant.mine_charges_remaining
		local_mine_cooldown_remaining = ship.combatant.mine_cooldown_remaining
		local_missile_charges_remaining = ship.combatant.missile_charges_remaining
		local_missile_cooldown_remaining = ship.combatant.missile_cooldown_remaining
		local_cloak_charges_remaining = ship.combatant.cloak_charges_remaining
		local_cloak_remaining = maxf(local_cloak_remaining, 0.1) if bool(state.get("cloaked", false)) else 0.0
		local_cloak_cooldown_remaining = ship.combatant.cloak_cooldown_remaining
		local_breakaway_remaining = maxf(local_breakaway_remaining, 0.1) if bool(state.get("breakaway_active", false)) else 0.0
		local_kinetic_vent_charge = ship.combatant.shield.kinetic_vent_charge
		local_breakaway_cooldown_remaining = ship.combatant.breakaway_cooldown_remaining
	if bool(state.get("afterburner_active", false)):
		ship.sustain_afterburner(0.14)
	ship.combatant.weapon.ammunition = state.ammunition
	ship.combatant.alive = state.alive
	if not state.alive:
		ship.set_eliminated()
	ship.queue_redraw()


func _stats_for_peer(peer_id: int, builds: Dictionary = {}) -> CombatStats:
	var source_builds := builds if not builds.is_empty() else match_payload.get("builds", {}) as Dictionary
	var build := source_builds.get(peer_id, source_builds.get(str(peer_id), {})) as Dictionary
	return StatSystem.derive(build, card_catalog)


func _build_for_peer(peer_id: int) -> Dictionary:
	var builds := match_payload.get("builds", {}) as Dictionary
	return builds.get(peer_id, builds.get(str(peer_id), {})) as Dictionary


func _emit_weapon_shot(
	owner_id: int,
	shot_sequence: int,
	position: Vector2,
	projectile: ProjectileState = null
) -> void:
	var stats := local_stats.duplicate_stats() if owner_id == local_peer_id else _stats_for_peer(owner_id).duplicate_stats()
	if projectile != null:
		stats.projectile_damage = projectile.damage
		stats.projectile_speed = projectile.velocity.length()
		stats.pierce_count = projectile.remaining_pierces
		stats.ricochet_count = projectile.remaining_ricochets
		stats.beam_weapon = projectile.is_beam
	var profile = WeaponSoundProfileScript.from_stats(stats, _build_for_peer(owner_id), card_catalog)
	presentation_event.emit(&"weapon_fire", {
		"profile": profile,
		"owner_id": owner_id,
		"shot_sequence": shot_sequence,
		"position": position,
		"listener_position": _audio_listener_position(),
		"local": owner_id == local_peer_id,
	})


func _audio_listener_position() -> Vector2:
	if ships.has(local_peer_id):
		return (ships[local_peer_id] as SandboxShip).global_position
	return camera.position if camera != null else Vector2.ZERO


func _update_remote_ships() -> void:
	var now := _now_seconds()
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if peer_id == local_peer_id:
			continue
		var sample := interpolation.sample(peer_id, now)
		if sample.ok:
			interpolation_sample_count += 1
			if bool(sample.extrapolated):
				interpolation_extrapolated_count += 1
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
	_emit_weapon_shot(local_peer_id, local_weapon.shot_sequence, muzzle)


func _expire_unconfirmed_predicted_projectiles(now_seconds: float) -> void:
	for key in predicted_tracker.step(now_seconds, _projectile_confirmation_timeout_seconds()):
		var parts := key.split(":", false, 1)
		if parts.size() != 2 or int(parts[0]) != local_peer_id:
			continue
		_remove_predicted_volley(int(parts[1]))
		expired_predicted_volleys += 1


func _remove_predicted_volley(shot_sequence: int) -> void:
	if not predicted_projectile_ids.has(shot_sequence):
		return
	for predicted_id in predicted_projectile_ids[shot_sequence] as Array:
		authoritative_projectiles.remove(int(predicted_id))
	predicted_projectile_ids.erase(shot_sequence)


func _reconcile_predicted_projectile(projectile: ProjectileState) -> void:
	if projectile.owner_id != local_peer_id or not predicted_projectile_ids.has(projectile.shot_sequence):
		return
	_remove_predicted_volley(projectile.shot_sequence)
	predicted_tracker.reconcile(projectile.owner_id, projectile.shot_sequence)


func _projectile_confirmation_timeout_seconds() -> float:
	var rtt_seconds := 0.0
	if bridge != null:
		rtt_seconds = maxf(float(bridge.get_round_trip_time_ms()), 0.0) / 1000.0
	return clampf(
		maxf(
			MIN_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS,
			rtt_seconds * PROJECTILE_CONFIRMATION_RTT_MULTIPLIER + PROJECTILE_CONFIRMATION_GRACE_SECONDS
		),
		MIN_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS,
		MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS
	)


func _record_snapshot_arrival(server_tick: int, receive_time: float) -> void:
	if last_snapshot_receive_time >= 0.0:
		var expected_interval := 1.0 / GameConstants.PLAYER_SNAPSHOT_RATE
		var arrival_deviation := absf(receive_time - last_snapshot_receive_time - expected_interval)
		snapshot_jitter_ms = lerpf(snapshot_jitter_ms, arrival_deviation * 1000.0, 0.1)
	if latest_server_tick != 0:
		var tick_delta := (server_tick - latest_server_tick) & SequenceMath.UINT32_MASK
		var expected_tick_delta := GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PLAYER_SNAPSHOT_RATE
		if tick_delta > expected_tick_delta and tick_delta < GameConstants.PHYSICS_TICKS_PER_SECOND * 5:
			snapshot_gap_count += maxi(floori(float(tick_delta) / expected_tick_delta) - 1, 0)
	last_snapshot_receive_time = receive_time


func _step_projectile_visuals(delta: float) -> void:
	for projectile_id in authoritative_projectiles.ordered_ids_view():
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := authoritative_projectiles.get_projectile(projectile_id)
		if projectile == null:
			continue
		if projectile.is_mine:
			projectile.step_mine_activation(delta)
			projectile.position += projectile.velocity * maxf(delta, 0.0)
			continue
		var safe_delta := maxf(delta, 0.0)
		projectile.lifetime_remaining -= safe_delta
		if projectile.lifetime_remaining <= 0.0:
			authoritative_projectiles.remove(projectile.projectile_id)
			continue
		var travel_remaining := projectile.velocity.length() * safe_delta
		var collision_iterations := 0
		while travel_remaining > 0.001 and collision_iterations < PROJECTILE_COLLISION_ITERATIONS:
			if authoritative_projectiles.get_projectile(projectile.projectile_id) == null or projectile.velocity.is_zero_approx():
				break
			collision_iterations += 1
			var direction := projectile.velocity.normalized()
			var start := projectile.position
			var finish := start + direction * travel_remaining
			var obstacle_hit: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(
				start,
				finish,
				projectile.radius,
				arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID
			)
			if obstacle_hit == null:
				projectile.position = finish
				break
			var collision_fraction := clampf(float(obstacle_hit.get("fraction", 0.0)), 0.0, 1.0)
			projectile.position = obstacle_hit.position as Vector2
			travel_remaining *= maxf(1.0 - collision_fraction, 0.0)
			var obstacle_normal := obstacle_hit.normal as Vector2
			if projectile.ricochet(obstacle_normal):
				presentation_event.emit(&"ricochet", {
					"projectile_id": projectile.projectile_id,
					"owner_id": projectile.owner_id,
					"ricochets_remaining": projectile.remaining_ricochets,
					"position": projectile.position,
					"listener_position": _audio_listener_position(),
				})
				projectile.position += obstacle_normal * COLLISION_SURFACE_EPSILON
				travel_remaining = maxf(travel_remaining - COLLISION_SURFACE_EPSILON, 0.0)
				continue
			presentation_event.emit(&"projectile_impact", {
				"projectile_id": projectile.projectile_id,
				"owner_id": projectile.owner_id,
				"position": projectile.position,
				"listener_position": _audio_listener_position(),
				"server_tick": latest_server_tick,
			})
			authoritative_projectiles.remove(projectile.projectile_id)
			break
	if projectile_layer != null:
		projectile_layer.visible_world_rect = _visible_world_rect()
		projectile_layer.queue_redraw()
	if effects_layer != null:
		effects_layer.visible_world_rect = _visible_world_rect()


func _synchronize_projectile(existing: ProjectileState, incoming: ProjectileState) -> bool:
	var newly_rebounded := incoming.has_rebounded and not existing.has_rebounded
	existing.owner_id = incoming.owner_id
	existing.position = incoming.position
	existing.velocity = incoming.velocity
	existing.damage = incoming.damage
	existing.remaining_pierces = incoming.remaining_pierces
	existing.remaining_ricochets = incoming.remaining_ricochets
	existing.lifetime_remaining = incoming.lifetime_remaining
	existing.is_beam = incoming.is_beam
	existing.is_mine = incoming.is_mine
	existing.is_missile = incoming.is_missile
	existing.mine_activation_remaining = incoming.mine_activation_remaining
	existing.has_rebounded = incoming.has_rebounded
	existing.radius = incoming.radius
	return newly_rebounded


func _emit_rebound_feedback(projectile: ProjectileState) -> void:
	if effects_layer != null:
		effects_layer.spawn_rebound(projectile.position)
	presentation_event.emit(&"rebound", {
		"projectile_id": projectile.projectile_id,
		"owner_id": projectile.owner_id,
		"position": projectile.position,
		"listener_position": _audio_listener_position(),
		"server_tick": latest_server_tick,
	})


func _separate_local_visual_from_remote(local_ship: SandboxShip) -> void:
	if not prediction_initialized or not local_ship.combatant.alive:
		return
	var target_distance := GameConstants.SHIP_COLLISION_RADIUS * 2.0 + 1.0
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if peer_id == local_peer_id:
			continue
		var remote := ships[peer_id] as SandboxShip
		if not remote.combatant.alive:
			continue
		var difference := prediction.predicted_position - remote.global_position
		if difference.length_squared() >= target_distance * target_distance:
			continue
		var preferred := difference.normalized()
		if preferred.is_zero_approx():
			preferred = Vector2.from_angle(float(posmod(local_peer_id * 31 + peer_id * 17, 360)) * PI / 180.0)
		var candidate := Vector2.INF
		var best_cost := INF
		for sample_index in 24:
			var direction := preferred.rotated(TAU * float(sample_index) / 24.0)
			var proposed := remote.global_position + direction * target_distance
			if not _local_visual_candidate_available(proposed, peer_id, target_distance):
				continue
			var cost := prediction.predicted_position.distance_squared_to(proposed) + float(sample_index) * 0.001
			if cost < best_cost:
				candidate = proposed
				best_cost = cost
		if candidate == Vector2.INF:
			continue
		var separation_normal := (candidate - remote.global_position).normalized()
		var inward_speed := minf(prediction.predicted_velocity.dot(separation_normal), 0.0)
		prediction.predicted_velocity -= separation_normal * inward_speed
		prediction.predicted_velocity += separation_normal * LOCAL_CONTACT_ESCAPE_SPEED
		prediction.predicted_velocity = prediction.predicted_velocity.limit_length(maxf(local_stats.max_speed * 2.5, 1.0))
		prediction.predicted_position = candidate
		prediction.smoothing_offset = Vector2.ZERO
		prediction.smoothing_remaining = 0.0
		local_ship.global_position = candidate
		local_ship.combatant.position = candidate
		local_ship.combatant.velocity = prediction.predicted_velocity


func _local_visual_candidate_available(position: Vector2, contacted_peer_id: int, minimum_distance: float) -> bool:
	var selected_map := arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID
	if not ArenaCollisionSystem.is_ship_position_clear(position, selected_map, 1.0):
		return false
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if peer_id == local_peer_id or peer_id == contacted_peer_id:
			continue
		var other := ships[peer_id] as SandboxShip
		if other.combatant.alive and position.distance_to(other.global_position) < minimum_distance:
			return false
	return true


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
	hud_root = Control.new()
	hud_root.name = "HUDSafeArea"
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_root)
	hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(16.0, 16.0)
	hud_panel.custom_minimum_size = Vector2(430.0, 148.0)
	hud_panel.add_theme_stylebox_override("panel", _hud_panel_style())
	hud_panel.visible = false
	hud_root.add_child(hud_panel)
	var hud_content := VBoxContainer.new()
	hud_content.add_theme_constant_override("separation", 3)
	hud_panel.add_child(hud_content)
	match_status_label = Label.new()
	match_status_label.custom_minimum_size.x = 390.0
	match_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	match_status_label.add_theme_font_size_override("font_size", 15)
	match_status_label.add_theme_color_override("font_color", DesignTokensScript.INTERACTIVE)
	hud_content.add_child(match_status_label)
	resources_label = Label.new()
	resources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resources_label.add_theme_font_size_override("font_size", 17)
	resources_label.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
	hud_content.add_child(resources_label)
	health_bar = _make_resource_bar(DesignTokensScript.HEALTH)
	hud_content.add_child(health_bar)
	shield_bar = _make_resource_bar(DesignTokensScript.SHIELD)
	hud_content.add_child(shield_bar)
	combat_status_label = Label.new()
	combat_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combat_status_label.add_theme_font_size_override("font_size", 14)
	combat_status_label.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
	hud_content.add_child(combat_status_label)
	spectator_label = Label.new()
	spectator_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spectator_label.position = Vector2(-360.0, -92.0)
	spectator_label.custom_minimum_size = Vector2(720.0, 64.0)
	spectator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spectator_label.add_theme_font_size_override("font_size", 24)
	spectator_label.add_theme_color_override("font_color", DesignTokensScript.FOCUS)
	hud_root.add_child(spectator_label)
	kill_feed = KillFeedScript.new()
	kill_feed.name = "KillFeed"
	hud_root.add_child(kill_feed)
	diagnostics_label = Label.new()
	diagnostics_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	diagnostics_label.position = Vector2(-620.0, -120.0)
	diagnostics_label.custom_minimum_size = Vector2(600.0, 96.0)
	diagnostics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	diagnostics_label.add_theme_color_override("font_color", DesignTokensScript.INTERACTIVE)
	diagnostics_label.add_theme_font_size_override("font_size", 16)
	diagnostics_label.visible = false
	hud_root.add_child(diagnostics_label)
	combat_feedback_panel = CombatFeedbackPanel.new()
	combat_feedback_panel.name = "CombatFeedback"
	hud_root.add_child(combat_feedback_panel)
	combat_feedback_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	combat_feedback_panel.offset_left = -250.0
	combat_feedback_panel.offset_right = 250.0
	# Leave the outer navigation markers and spectator controls unobstructed.
	combat_feedback_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	combat_feedback_panel.offset_top = -320.0
	combat_feedback_panel.offset_bottom = -210.0
	get_viewport().size_changed.connect(_layout_accessible_hud)
	_layout_accessible_hud()


func apply_combat_feedback(payload: Dictionary) -> void:
	var names: Dictionary = {}
	for player in match_payload.get("players", []):
		names[int(player.get("peer_id", 0))] = String(player.get("display_name", "Pilot"))
	if combat_feedback_panel != null:
		combat_feedback_panel.apply_feedback(payload, local_peer_id, names)


func apply_mine_detonations(server_tick: int, events: Array) -> void:
	if server_tick + GameConstants.PHYSICS_TICKS_PER_SECOND < latest_server_tick:
		return
	for event in events:
		if effects_layer != null:
			effects_layer.spawn_mine_explosion(event.position as Vector2)
		var payload := (event as Dictionary).duplicate()
		payload["server_tick"] = server_tick
		payload["listener_position"] = _audio_listener_position()
		presentation_event.emit(&"mine_detonated", payload)


func apply_accessibility_settings(values: Dictionary) -> void:
	var normalized = AccessibilityPreferencesScript.new()
	normalized.set_values(values)
	accessibility_settings = normalized.values.duplicate()
	action_latch.reset()
	if arena != null and arena.static_layer != null:
		arena.static_layer.high_contrast = bool(accessibility_settings.high_contrast)
		arena.static_layer.queue_redraw()
	if effects_layer != null:
		effects_layer.reduced_flashes = bool(accessibility_settings.reduced_flashes)
	for ship_value in ships.values():
		(ship_value as SandboxShip).high_contrast = bool(accessibility_settings.high_contrast)
		(ship_value as SandboxShip).reduced_flashes = bool(accessibility_settings.reduced_flashes)
		(ship_value as SandboxShip).queue_redraw()
	if bool(accessibility_settings.reduced_shake):
		camera_shake_remaining = 0.0
		camera_kick_remaining = 0.0
		if camera != null:
			camera.offset = Vector2.ZERO
	_layout_accessible_hud()


func _layout_accessible_hud() -> void:
	if hud_root == null:
		return
	var safe_rect: Rect2 = AccessibilityPreferencesScript.hud_safe_rect(get_viewport_rect().size, bool(accessibility_settings.constrain_hud))
	var hud_scale := float(accessibility_settings.hud_scale)
	hud_root.position = safe_rect.position
	hud_root.scale = Vector2.ONE * hud_scale
	hud_root.size = safe_rect.size / hud_scale
	var panel_width := minf(430.0, maxf(240.0, hud_root.size.x - 420.0 - 56.0))
	hud_panel.custom_minimum_size.x = panel_width
	hud_panel.size.x = panel_width
	match_status_label.custom_minimum_size.x = maxf(panel_width - 40.0, 100.0)
	spectator_label.custom_minimum_size.x = minf(720.0, hud_root.size.x - 32.0)
	spectator_label.size.x = spectator_label.custom_minimum_size.x
	spectator_label.position.x = (hud_root.size.x - spectator_label.size.x) * 0.5
	spectator_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _update_diagnostics(delta: float = 0.0) -> void:
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
		if local_stats.mine_layer_enabled:
			var mine_status := "%d" % local_mine_charges_remaining
			if local_mine_cooldown_remaining > 0.05:
				mine_status += " (%.1fs)" % local_mine_cooldown_remaining
			resources += "   MINES %s" % mine_status
		if local_stats.missile_launcher_enabled:
			var missile_status := "%d" % local_missile_charges_remaining
			if local_missile_cooldown_remaining > 0.05:
				missile_status += " (%.1fs)" % local_missile_cooldown_remaining
			resources += "   MISSILES %s" % missile_status
		if local_stats.cloak_enabled:
			var cloak_status := "ACTIVE" if local_cloak_remaining > 0.0 else "%d" % local_cloak_charges_remaining
			if local_cloak_remaining <= 0.0 and local_cloak_cooldown_remaining > 0.05:
				cloak_status += " (%.1fs)" % local_cloak_cooldown_remaining
			resources += "   CLOAK %s" % cloak_status
		if local_stats.kinetic_vent_enabled:
			resources += "   VENT %.0f/%.0f" % [local_kinetic_vent_charge, GameConstants.KINETIC_VENT_MAXIMUM_CHARGE]
		if local_stats.breakaway_thrusters_enabled:
			var breakaway_status := "ACTIVE" if local_breakaway_remaining > 0.0 else ("%.1fs" % local_breakaway_cooldown_remaining if local_breakaway_cooldown_remaining > 0.05 else "READY")
			resources += "   BREAKAWAY %s" % breakaway_status
		var reload_hint: String = input_profiles.binding_text(&"manual_reload") if input_profiles != null else "R"
		combat_status = "%s diagnostics   ·   Hold %s scoreboard   ·   %s reload" % [diagnostics_hint, scoreboard_hint, reload_hint]
		selected_special_slot = SpecialAbilitySelection.ensure_owned(selected_special_slot, local_stats)
		if selected_special_slot >= 0:
			var special_hint: String = input_profiles.binding_text(&"special") if input_profiles != null else "Shift"
			var cycle_hint: String = "%s/%s" % [input_profiles.binding_text(&"special_previous"), input_profiles.binding_text(&"special_next")] if input_profiles != null else "Q/E"
			combat_status += "\n%s %s · %s select" % [special_hint, SpecialAbilitySelection.label(selected_special_slot), cycle_hint]
		if local_stats.mine_layer_enabled:
			combat_status += " · DEPLOYED %d/16" % local_active_mines
		if budget_warning_remaining > 0.0:
			combat_status += "\nORDNANCE LIMIT · oldest eligible weapon replaced"
		if not local_ship.combatant.alive:
			# Elimination can leave authoritative shield energy above zero (for
			# example, damage that bypasses shields). Do not present that stale
			# resource as an available shield while spectating.
			shield_bar.value = 0.0
			resources = "SHIP ELIMINATED"
			var previous_hint: String = input_profiles.binding_text(&"spectator_previous") if input_profiles != null else "A"
			var next_hint: String = input_profiles.binding_text(&"spectator_next") if input_profiles != null else "D"
			spectator_label.text = "SPECTATING %s   ◀ %s     %s ▶" % [_display_name(spectator_target_id), previous_hint, next_hint] if spectator_target_id != 0 else "NO SURVIVING TARGET · ARENA VIEW"
			spectator_label.visible = true
		else:
			spectator_label.visible = false
	resources_label.text = resources
	combat_status_label.text = combat_status
	if toggle_status_label == null and hud_root != null:
		toggle_status_label = action_latch.create_status_label(hud_root)
	if toggle_status_label != null:
		toggle_status_label.text = action_latch.status(accessibility_settings)
	_diagnostics_refresh_accumulator += maxf(delta, 0.0)
	if diagnostics_visible and _diagnostics_refresh_accumulator >= 0.25:
		_diagnostics_refresh_accumulator = fmod(_diagnostics_refresh_accumulator, 0.25)
		var network_stats := bridge.get_network_statistics()
		var extrapolation_percent := (
			float(interpolation_extrapolated_count) / interpolation_sample_count * 100.0
			if interpolation_sample_count > 0
			else 0.0
		)
		diagnostics_label.text = (
			"NETWORK · FPS %d · RTT %d ± %d ms · loss %.2f%% · throttle %.0f%%\n"
			+ "SNAP · jitter %.1f ms · gaps %d · extrap %.1f%% · buffer %d ms\n"
			+ "PRED · error %.2f px · snaps %d · pending %d · expired shots %d · ack %d"
		) % [
			Engine.get_frames_per_second(),
			int(network_stats.rtt_ms),
			int(network_stats.rtt_variance_ms),
			float(network_stats.packet_loss_percent),
			float(network_stats.packet_throttle_percent),
			snapshot_jitter_ms,
			snapshot_gap_count,
			extrapolation_percent,
			roundi(RemoteInterpolator.INTERPOLATION_DELAY_SECONDS * 1000.0),
			prediction.last_reconciliation_error,
			prediction.snap_count,
			prediction.buffered_inputs.size(),
			expired_predicted_volleys,
			latest_acknowledged_input,
		]


func _local_is_eliminated() -> bool:
	return ships.has(local_peer_id) and not (ships[local_peer_id] as SandboxShip).combatant.alive


func _living_spectator_targets() -> Array[int]:
	var result: Array[int] = []
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		var ship := ships[peer_id] as SandboxShip
		if peer_id != local_peer_id and ship.combatant.alive and not ship.combatant.is_cloaked():
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
	if _nearest_incoming_revision != authoritative_projectiles.revision:
		_refresh_nearest_incoming_projectile()
	return _nearest_incoming_cache


func _refresh_nearest_incoming_projectile() -> void:
	_nearest_incoming_cache = null
	_nearest_incoming_revision = authoritative_projectiles.revision
	if not ships.has(local_peer_id):
		return
	var local_position := (ships[local_peer_id] as SandboxShip).global_position
	var nearest_distance := INF
	for projectile_id in authoritative_projectiles.ordered_ids_view():
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := authoritative_projectiles.get_projectile(projectile_id)
		if projectile == null:
			continue
		if is_friendly_peer(projectile.owner_id):
			continue
		var offset := local_position - projectile.position
		var distance := offset.length()
		if distance <= 0.001 or projectile.velocity.normalized().dot(offset / distance) < 0.72:
			continue
		if distance < nearest_distance:
			_nearest_incoming_cache = projectile
			nearest_distance = distance


func _visible_world_rect() -> Rect2:
	if camera == null:
		return Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)
	var viewport_size := get_viewport_rect().size
	var zoom := Vector2(maxf(camera.zoom.x, 0.001), maxf(camera.zoom.y, 0.001))
	var world_size := viewport_size / zoom
	return Rect2(camera.position - world_size * 0.5, world_size)


func trigger_camera_shake(intensity: float, duration: float) -> void:
	if bool(accessibility_settings.reduced_shake):
		return
	camera_shake_intensity = maxf(camera_shake_intensity, intensity)
	camera_shake_remaining = maxf(camera_shake_remaining, duration)


func trigger_afterburner_feedback(forward: Vector2) -> void:
	if bool(accessibility_settings.reduced_shake):
		return
	var direction := forward.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	camera_kick_duration = 0.18
	camera_kick_remaining = camera_kick_duration
	camera_kick_offset = -direction * 5.5
	trigger_camera_shake(2.4, 0.11)


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
			effects_layer.spawn_damage(state.position, direction, peer_id == local_peer_id)
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
	if not bool(previous.get("kinetic_vent_active", false)) and bool(state.get("kinetic_vent_active", false)):
		if effects_layer != null:
			effects_layer.spawn_kinetic_vent(state.position)
		presentation_event.emit(&"kinetic_vent", {"peer_id": peer_id, "server_tick": latest_server_tick})
		if peer_id == local_peer_id:
			trigger_camera_shake(3.0, 0.12)
	if not bool(previous.get("afterburner_active", false)) and bool(state.get("afterburner_active", false)):
		ship.flash_afterburner(ship.combatant.stats.afterburner_duration)
		if peer_id != local_peer_id:
			presentation_event.emit(&"afterburner", {
				"peer_id": peer_id,
				"server_tick": latest_server_tick,
				"position": state.get("position", Vector2.ZERO),
				"listener_position": _audio_listener_position(),
				"local": false,
			})
	if not bool(previous.get("breakaway_active", false)) and bool(state.get("breakaway_active", false)):
		presentation_event.emit(&"breakaway", {"peer_id": peer_id, "server_tick": latest_server_tick})
	if bool(previous.get("alive", true)) and not bool(state.get("alive", true)):
		if effects_layer != null:
			effects_layer.spawn_elimination(state.position, ship.ship_color, peer_id == local_peer_id)
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
	var center := match_payload.get("overtime_center", ArenaLayout.center(arena.map_id)) as Vector2
	var minimum_radius := float(match_payload.get("overtime_minimum_radius", GameConstants.OVERTIME_MINIMUM_RADIUS))
	var radius := OvertimeSystem.initial_radius(center)
	if active:
		var elapsed := GameConstants.OVERTIME_START_SECONDS + float(latest_server_tick - overtime_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND
		radius = OvertimeSystem.radius_at(elapsed, center, minimum_radius)
	arena.set_overtime(active, radius, center)


func _update_camera_shake(delta: float) -> void:
	if camera == null:
		return
	var safe_delta := maxf(delta, 0.0)
	var desired_offset := Vector2.ZERO
	if camera_kick_remaining > 0.0:
		var kick_fraction := clampf(camera_kick_remaining / maxf(camera_kick_duration, 0.001), 0.0, 1.0)
		desired_offset += camera_kick_offset * kick_fraction * kick_fraction
		camera_kick_remaining = maxf(camera_kick_remaining - safe_delta, 0.0)
	if camera_shake_remaining <= 0.0 and desired_offset.is_zero_approx():
		camera.offset = camera.offset.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
		return
	if camera_shake_remaining > 0.0:
		camera_shake_remaining = maxf(camera_shake_remaining - safe_delta, 0.0)
		var fade := minf(camera_shake_remaining * 8.0, 1.0)
		desired_offset += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * camera_shake_intensity * fade
	camera.offset = desired_offset


func _unshaken_mouse_world_position() -> Vector2:
	if camera == null:
		return get_global_mouse_position()
	var screen_offset := get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
	return camera.position + Vector2(screen_offset.x / camera.zoom.x, screen_offset.y / camera.zoom.y)


func _player_color(peer_id: int) -> Color:
	var player := _player_identity(peer_id)
	if not player.is_empty():
		return Color.from_string("#%s" % String(player.get("ship_color", "42e8ff")), Color("42e8ff"))
	return Color("42e8ff")


func _player_pattern(peer_id: int) -> StringName:
	var player := _player_identity(peer_id)
	if not player.is_empty():
		var pattern := ShipAppearanceScript.normalized_pattern(String(player.get("ship_pattern", ShipAppearanceScript.SOLID)))
		return pattern if not pattern.is_empty() else ShipAppearanceScript.SOLID
	return ShipAppearanceScript.SOLID


func team_for_peer(peer_id: int) -> int:
	if not GameModeRules.is_team_mode(int(match_payload.get("game_mode", 0))):
		return 0
	var teams := match_payload.get("teams", {}) as Dictionary
	return int(teams.get(peer_id, teams.get(str(peer_id), 0)))


func is_friendly_peer(peer_id: int) -> bool:
	var local_team := team_for_peer(local_peer_id)
	return peer_id == local_peer_id or local_team > 0 and team_for_peer(peer_id) == local_team


func _display_name(peer_id: int) -> String:
	var player := _player_identity(peer_id)
	if not player.is_empty():
		return String(player.get("display_name", "Pilot %d" % peer_id))
	return "Pilot %d" % peer_id


func _player_identity(peer_id: int) -> Dictionary:
	var identity_sources: Array = [match_payload.get("players", [])]
	if bridge != null:
		identity_sources.append(bridge.latest_lobby_state.get("players", []))
	for players_value in identity_sources:
		for player_value in players_value as Array:
			var player := player_value as Dictionary
			if int(player.get("peer_id", 0)) == peer_id:
				return player
	return {}


func _make_resource_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(390.0, 12.0)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _flat_style(DesignTokensScript.SURFACE_MUTED, Color("31466c"), 1))
	bar.add_theme_stylebox_override("fill", _flat_style(Color(color.darkened(0.45), 0.94), color, 1))
	return bar


func _hud_panel_style() -> StyleBoxFlat:
	var style := _flat_style(Color(DesignTokensScript.SURFACE, 0.9), Color(DesignTokensScript.INTERACTIVE, 0.75), 2)
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
