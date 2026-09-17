class_name NetworkWorldView
extends Node2D

## Coordinates network events and presentation owners; simulation and rendering
## state live in focused owners with explicit observations and signal outputs.
## Legacy convenience accessors live only in NetworkWorldFixture.

const AccessibilityPreferencesScript = preload("res://src/client/presentation/accessibility_preferences.gd")
const CombatActionLatchScript = preload("res://src/client/input/combat_action_latch.gd")
const CompetitiveViewPolicyScript = preload("res://src/client/presentation/competitive_view_policy.gd")
const MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS: float = NetworkLocalPrediction.MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS

signal presentation_event(event_name: StringName, payload: Dictionary)

const ClientMatchState = preload("res://src/client/network/client_match_state.gd")
var context := preload("res://src/client/network/client_view_context.gd").new()
var bridge: NetworkBridge:
	get: return context.bridge
	set(value): context.bridge = value
var input_profiles: Node:
	get: return context.input_profiles
	set(value): context.input_profiles = value
var local_peer_id: int:
	get: return context.local_peer_id
	set(value): context.local_peer_id = value
var _network_active: bool:
	get: return context._network_active
	set(value): context._network_active = value
var accessibility_settings: Dictionary:
	get: return context.accessibility_settings
	set(value): context.accessibility_settings = value
var latest_server_tick: int:
	get: return context.latest_server_tick
	set(value): context.latest_server_tick = value
var controls_enabled: bool:
	get: return context.controls_enabled
	set(value): context.controls_enabled = value
var match_paused: bool:
	get: return context.match_paused
	set(value): context.match_paused = value
var card_catalog: CardCatalog:
	get: return context.card_catalog
	set(value): context.card_catalog = value
var match_state: ClientMatchState:
	get: return context.match_state
	set(value): context.match_state = value
var match_payload: Dictionary:
	get: return context.match_payload
	set(value): context.match_payload = value
var local_prediction: NetworkLocalPrediction = NetworkLocalPrediction.new()
var replicated_visuals: NetworkReplicatedVisuals = NetworkReplicatedVisuals.new()
var hud_camera: NetworkHudCamera = NetworkHudCamera.new()

var input_blocked: bool:
	get: return local_prediction.input_blocked
	set(value): local_prediction.input_blocked = value


func _init() -> void:
	context.presentation_event.connect(_forward_presentation_event)
	configure_owners()


func configure_owners() -> void:
	context.surface = self
	local_prediction.context = context
	replicated_visuals.context = context
	hud_camera.context = context
	local_prediction.visuals = replicated_visuals
	hud_camera.visuals = replicated_visuals
	hud_camera.local_prediction = local_prediction
	replicated_visuals.projectile_observed.connect(local_prediction._reconcile_predicted_projectile)
	replicated_visuals.local_resources_received.connect(local_prediction.receive_visual_resources)
	replicated_visuals.ordnance_reset.connect(local_prediction.reset_ordnance)
	replicated_visuals.camera_shake_requested.connect(hud_camera.trigger_camera_shake)
	local_prediction.afterburner_requested.connect(hud_camera.trigger_afterburner_feedback)
	local_prediction.life_received.connect(hud_camera.reset_feedback_for_life)


func setup(network_bridge: NetworkBridge, profile_manager: Node = null) -> void:
	bridge = network_bridge
	input_profiles = profile_manager
	bridge.client_connected.connect(_on_connected)
	bridge.client_snapshot_received.connect(_on_snapshot)
	bridge.client_projectile_batch_received.connect(replicated_visuals._on_projectile_batch)
	bridge.client_projectile_correction_received.connect(replicated_visuals._on_projectile_correction)
	replicated_visuals.create_layers()
	local_prediction.local_weapon.reset(local_prediction.local_stats)
	hud_camera._create_camera_and_hud()
	hud_camera._create_indicator_layer()
	set_network_active(false)


func set_network_active(active: bool, reset_when_inactive: bool = true) -> void:
	_network_active = active
	hud_camera._update_competitive_view()
	if not active:
		local_prediction.action_latch.reset()
	if not active and reset_when_inactive:
		reset_session()
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if hud_camera.camera != null:
		hud_camera.camera.enabled = active
	if hud_camera.diagnostics_label != null:
		var diagnostics_canvas := hud_camera.hud_root.get_parent() as CanvasLayer
		diagnostics_canvas.visible = active


func reset_session() -> void:
	match_state.reset()
	local_peer_id = 0
	latest_server_tick = 0
	controls_enabled = false
	match_paused = false
	local_prediction.reset_session()
	replicated_visuals.reset_session()
	hud_camera.reset_session()


func reset_match_presentation() -> void:
	var connected_peer_id := local_peer_id
	var continuing_input_sequence := local_prediction.input_sequence
	var continuing_client_tick := local_prediction.client_tick
	reset_session()
	local_peer_id = connected_peer_id
	local_prediction.input_sequence = continuing_input_sequence
	local_prediction.client_tick = continuing_client_tick


func _physics_process(delta: float) -> void:
	if match_paused:
		return
	if local_peer_id == 0 or not replicated_visuals.ships.has(local_peer_id):
		return
	var local_ship := replicated_visuals.ships[local_peer_id] as CombatShipView
	local_prediction.step(delta, local_ship, hud_camera._unshaken_mouse_world_position())
	replicated_visuals._update_remote_ships()
	local_prediction._separate_local_visual_from_remote(local_ship)
	replicated_visuals._step_projectile_visuals(delta)
	hud_camera.step_incoming_refresh(delta)
	hud_camera._update_camera(local_ship, delta)
	hud_camera._update_camera_shake(delta)
	replicated_visuals._update_overtime_presentation()
	local_prediction._expire_unconfirmed_predicted_projectiles(_now_seconds())
	hud_camera._update_diagnostics(delta)
	queue_redraw()


func _on_connected(peer_id: int) -> void:
	local_peer_id = peer_id
	set_network_active(true)


func _on_snapshot(decoded: Dictionary) -> void:
	local_prediction.latest_acknowledged_input = int(decoded.acknowledged_input)
	var receive_time := _now_seconds()
	replicated_visuals._record_snapshot_arrival(int(decoded.server_tick), receive_time)
	if not match_paused:
		latest_server_tick = int(decoded.server_tick)
	var present_ids: Dictionary = {}
	var identities := replicated_visuals.snapshot_identities(decoded.states)
	for state_value in decoded.states:
		var state := state_value as Dictionary
		var peer_id := int(state.peer_id)
		present_ids[peer_id] = true
		var ship := replicated_visuals._ensure_ship_from_identity(peer_id, state, identities.get(peer_id, {}))
		var revived := bool(state.alive) and not ship.combatant.alive
		ship.visible = String(match_payload.get("state_name", "")) != "DRAFT"
		replicated_visuals._handle_snapshot_feedback(peer_id, state, ship)
		replicated_visuals._apply_snapshot_resources(ship, state)
		if peer_id == local_peer_id:
			local_prediction.apply_local_snapshot(decoded, state, ship, revived)
		else:
			replicated_visuals.interpolation.add_sample(peer_id, receive_time, latest_server_tick, state)
			if match_paused:
				ship.global_position = state.position
				ship.combatant.position = state.position
				ship.combatant.aim_angle = float(state.aim_angle)
				ship.queue_redraw()
	replicated_visuals.remove_missing_ships(present_ids)
	hud_camera._update_spectator_target()


func apply_match_state(payload: Dictionary, server_tick: int = -1) -> void:
	match_state.replace(payload, server_tick)
	hud_camera._update_competitive_view()
	var state_name := String(payload.get("state_name", ""))
	apply_match_pause(bool(payload.get("paused", false)))
	replicated_visuals.apply_match_state(match_payload, state_name)
	hud_camera.apply_match_state(state_name)
	apply_builds(payload.get("builds", {}) as Dictionary)
	if String(payload.get("state_name", "")) == "COUNTDOWN":
		local_prediction.reset_for_countdown()
		replicated_visuals.reset_for_countdown()
		hud_camera.reset_for_countdown()
	hud_camera._update_spectator_target()


func apply_match_pause(paused: bool) -> void:
	if match_paused != paused:
		local_prediction.action_latch.reset()
		local_prediction.special_activation_sends_remaining = 0
		local_prediction.special_activation_deadline_msec = 0
		local_prediction.prediction.buffered_inputs.clear()
		local_prediction.prediction_initialized = false
		for shot_sequence in local_prediction.predicted_projectile_ids.keys():
			local_prediction._remove_predicted_volley(int(shot_sequence))
		replicated_visuals.interpolation.clear()
	match_paused = paused
	if replicated_visuals.arena != null:
		replicated_visuals.arena.effect_paused = paused
	match_state.update_fields({"paused": paused})
	controls_enabled = not paused and String(match_payload.get("state_name", "")) == "ACTIVE_HEAT"


func _exit_tree() -> void:
	hud_camera.shutdown()
	if is_instance_valid(bridge):
		if bridge.client_connected.is_connected(_on_connected):
			bridge.client_connected.disconnect(_on_connected)
		if bridge.client_snapshot_received.is_connected(_on_snapshot):
			bridge.client_snapshot_received.disconnect(_on_snapshot)
		if bridge.client_projectile_batch_received.is_connected(replicated_visuals._on_projectile_batch):
			bridge.client_projectile_batch_received.disconnect(replicated_visuals._on_projectile_batch)
		if bridge.client_projectile_correction_received.is_connected(replicated_visuals._on_projectile_correction):
			bridge.client_projectile_correction_received.disconnect(replicated_visuals._on_projectile_correction)


func apply_objective_state(objective: Dictionary, server_tick: int = -1, periodic: bool = false) -> bool:
	if not match_state.apply_objective(objective, server_tick, periodic):
		return false
	if replicated_visuals.arena != null:
		replicated_visuals.arena.set_objective(objective)
	return true


func apply_builds(builds: Dictionary) -> void:
	# Commit the detached build before updating current ships. Respawn and cloak
	# reappearance derive from this same data, including an empty-build reset.
	match_state.update_fields({"builds": builds})
	replicated_visuals.apply_builds(match_payload.builds)
	local_prediction.local_stats = replicated_visuals._stats_for_peer(local_peer_id)


func add_card_powerup(payload: Dictionary) -> void:
	replicated_visuals.add_card_powerup(payload)


func collect_card_powerup(payload: Dictionary) -> void:
	replicated_visuals.collect_card_powerup(payload)


func add_kill_feed_entries(eliminations: Array, server_tick: int) -> void:
	hud_camera.add_kill_feed_entries(eliminations, server_tick)


func snap_camera_to_local_ship() -> void:
	hud_camera.snap_camera_to_local_ship()


func set_match_status(status: String) -> void:
	hud_camera.set_match_status(status)


func _input(event: InputEvent) -> void:
	if match_paused:
		return
	if local_prediction.input_blocked or (not controls_enabled and String(match_payload.get("state_name", "")) != "COUNTDOWN"):
		return
	var ship := replicated_visuals.ships.get(local_peer_id) as CombatShipView
	if ship == null or not ship.combatant.alive:
		return
	var direction := SpecialAbilitySelection.direction_for_event(event)
	if direction != 0:
		local_prediction.selected_special_slot = SpecialAbilitySelection.cycle(
			SpecialAbilitySelection.ensure_owned(local_prediction.selected_special_slot, local_prediction.local_stats),
			local_prediction.local_stats, direction)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	hud_camera._unhandled_input(event)


func apply_combat_feedback(payload: Dictionary) -> void:
	replicated_visuals.apply_shield_feedback(payload)
	hud_camera.apply_combat_feedback(payload)


func apply_mine_detonations(server_tick: int, events: Array) -> void:
	replicated_visuals.apply_mine_detonations(server_tick, events)


func apply_accessibility_settings(values: Dictionary) -> void:
	var normalized = AccessibilityPreferencesScript.new()
	normalized.set_values(values)
	accessibility_settings = normalized.values.duplicate()
	local_prediction.action_latch.reset()
	replicated_visuals.apply_accessibility_settings(accessibility_settings)
	hud_camera.apply_accessibility_settings(accessibility_settings)


func nearest_incoming_offscreen_projectile() -> ProjectileState:
	return hud_camera.nearest_incoming_offscreen_projectile()


func trigger_camera_shake(intensity: float, duration: float) -> void:
	hud_camera.trigger_camera_shake(intensity, duration)


func trigger_afterburner_feedback(forward: Vector2) -> void:
	hud_camera.trigger_afterburner_feedback(forward)


func gameplay_mouse_position() -> Vector2:
	return hud_camera.gameplay_mouse_position()


func team_for_peer(peer_id: int) -> int:
	return replicated_visuals.team_for_peer(peer_id)


func is_friendly_peer(peer_id: int) -> bool:
	return replicated_visuals.is_friendly_peer(peer_id)


static func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _forward_presentation_event(event_name: StringName, payload: Dictionary) -> void:
	presentation_event.emit(event_name, payload)
