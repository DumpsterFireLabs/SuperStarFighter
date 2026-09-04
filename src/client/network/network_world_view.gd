class_name NetworkWorldView
extends Node2D

## Coordinates network events and presentation owners; simulation and rendering
## state live in the focused owners below. The explicit compatibility accessors
## keep existing integration tools and callers on the same objects.

const AccessibilityPreferencesScript = preload("res://src/client/presentation/accessibility_preferences.gd")
const CombatActionLatchScript = preload("res://src/client/input/combat_action_latch.gd")
const CompetitiveViewPolicyScript = preload("res://src/client/presentation/competitive_view_policy.gd")
const MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS: float = NetworkLocalPrediction.MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS

signal presentation_event(event_name: StringName, payload: Dictionary)

var bridge: NetworkBridge
var input_profiles: Node
var local_peer_id: int = 0
var _network_active: bool = false
var accessibility_settings: Dictionary = AccessibilityPreferencesScript.DEFAULTS.duplicate()
var latest_server_tick: int = 0
var match_payload: Dictionary = {}
var controls_enabled: bool = false
var card_catalog := CardCatalog.create_default()
var local_prediction: NetworkLocalPrediction = NetworkLocalPrediction.new()
var replicated_visuals: NetworkReplicatedVisuals = NetworkReplicatedVisuals.new()
var hud_camera: NetworkHudCamera = NetworkHudCamera.new()

# Typed compatibility accessors. Runtime coordination calls owners directly.
var arena: ArenaView:
	get: return replicated_visuals.arena
	set(value): replicated_visuals.arena = value
var ships: Dictionary:
	get: return replicated_visuals.ships
	set(value): replicated_visuals.ships = value
var authoritative_projectiles: ProjectileRegistry:
	get: return replicated_visuals.authoritative_projectiles
	set(value): replicated_visuals.authoritative_projectiles = value
var projectile_layer: ProjectileLayer:
	get: return replicated_visuals.projectile_layer
	set(value): replicated_visuals.projectile_layer = value
var effects_layer: CombatEffectsLayer:
	get: return replicated_visuals.effects_layer
	set(value): replicated_visuals.effects_layer = value
var indicator_layer: OffscreenIndicatorLayer:
	get: return hud_camera.indicator_layer
	set(value): hud_camera.indicator_layer = value
var powerup_layer: Node2D:
	get: return replicated_visuals.powerup_layer
	set(value): replicated_visuals.powerup_layer = value
var prediction: ClientPredictionBuffer:
	get: return local_prediction.prediction
	set(value): local_prediction.prediction = value
var interpolation: RemoteInterpolator:
	get: return replicated_visuals.interpolation
	set(value): replicated_visuals.interpolation = value
var predicted_tracker: PredictedProjectileTracker:
	get: return local_prediction.predicted_tracker
	set(value): local_prediction.predicted_tracker = value
var predicted_projectile_ids: Dictionary:
	get: return local_prediction.predicted_projectile_ids
	set(value): local_prediction.predicted_projectile_ids = value
var local_weapon: WeaponState:
	get: return local_prediction.local_weapon
	set(value): local_prediction.local_weapon = value
var local_stats: CombatStats:
	get: return local_prediction.local_stats
	set(value): local_prediction.local_stats = value
var competitive_view_policy: CompetitiveViewPolicyScript:
	get: return hud_camera.competitive_view_policy
	set(value): hud_camera.competitive_view_policy = value
var camera: Camera2D:
	get: return hud_camera.camera
	set(value): hud_camera.camera = value
var diagnostics_label: Label:
	get: return hud_camera.diagnostics_label
	set(value): hud_camera.diagnostics_label = value
var hud_panel: PanelContainer:
	get: return hud_camera.hud_panel
	set(value): hud_camera.hud_panel = value
var hud_root: Control:
	get: return hud_camera.hud_root
	set(value): hud_camera.hud_root = value
var match_status_label: Label:
	get: return hud_camera.match_status_label
	set(value): hud_camera.match_status_label = value
var resources_label: Label:
	get: return hud_camera.resources_label
	set(value): hud_camera.resources_label = value
var combat_status_label: Label:
	get: return hud_camera.combat_status_label
	set(value): hud_camera.combat_status_label = value
var spectator_label: Label:
	get: return hud_camera.spectator_label
	set(value): hud_camera.spectator_label = value
var combat_feedback_panel: CombatFeedbackPanel:
	get: return hud_camera.combat_feedback_panel
	set(value): hud_camera.combat_feedback_panel = value
var kill_feed: Control:
	get: return hud_camera.kill_feed
	set(value): hud_camera.kill_feed = value
var health_bar: ProgressBar:
	get: return hud_camera.health_bar
	set(value): hud_camera.health_bar = value
var shield_bar: ProgressBar:
	get: return hud_camera.shield_bar
	set(value): hud_camera.shield_bar = value
var input_sequence: int:
	get: return local_prediction.input_sequence
	set(value): local_prediction.input_sequence = value
var client_tick: int:
	get: return local_prediction.client_tick
	set(value): local_prediction.client_tick = value
var input_send_accumulator: float:
	get: return local_prediction.input_send_accumulator
	set(value): local_prediction.input_send_accumulator = value
var prediction_initialized: bool:
	get: return local_prediction.prediction_initialized
	set(value): local_prediction.prediction_initialized = value
var next_predicted_id: int:
	get: return local_prediction.next_predicted_id
	set(value): local_prediction.next_predicted_id = value
var latest_acknowledged_input: int:
	get: return local_prediction.latest_acknowledged_input
	set(value): local_prediction.latest_acknowledged_input = value
var spectator_target_id: int:
	get: return hud_camera.spectator_target_id
	set(value): hud_camera.spectator_target_id = value
var toggle_status_label: Label:
	get: return hud_camera.toggle_status_label
	set(value): hud_camera.toggle_status_label = value
var action_latch: CombatActionLatchScript:
	get: return local_prediction.action_latch
	set(value): local_prediction.action_latch = value
var input_blocked: bool:
	get: return local_prediction.input_blocked
	set(value): local_prediction.input_blocked = value
var presentation_states: Dictionary:
	get: return replicated_visuals.presentation_states
	set(value): replicated_visuals.presentation_states = value
var camera_shake_remaining: float:
	get: return hud_camera.camera_shake_remaining
	set(value): hud_camera.camera_shake_remaining = value
var camera_shake_intensity: float:
	get: return hud_camera.camera_shake_intensity
	set(value): hud_camera.camera_shake_intensity = value
var camera_kick_remaining: float:
	get: return hud_camera.camera_kick_remaining
	set(value): hud_camera.camera_kick_remaining = value
var camera_kick_duration: float:
	get: return hud_camera.camera_kick_duration
	set(value): hud_camera.camera_kick_duration = value
var camera_kick_offset: Vector2:
	get: return hud_camera.camera_kick_offset
	set(value): hud_camera.camera_kick_offset = value
var diagnostics_visible: bool:
	get: return hud_camera.diagnostics_visible
	set(value): hud_camera.diagnostics_visible = value
var special_activation_sends_remaining: int:
	get: return local_prediction.special_activation_sends_remaining
	set(value): local_prediction.special_activation_sends_remaining = value
var special_activation_sequence: int:
	get: return local_prediction.special_activation_sequence
	set(value): local_prediction.special_activation_sequence = value
var selected_special_slot: int:
	get: return local_prediction.selected_special_slot
	set(value): local_prediction.selected_special_slot = value
var special_activation_slot: int:
	get: return local_prediction.special_activation_slot
	set(value): local_prediction.special_activation_slot = value
var local_active_ordnance: int:
	get: return local_prediction.local_active_ordnance
	set(value): local_prediction.local_active_ordnance = value
var local_active_mines: int:
	get: return local_prediction.local_active_mines
	set(value): local_prediction.local_active_mines = value
var local_budget_evictions: int:
	get: return local_prediction.local_budget_evictions
	set(value): local_prediction.local_budget_evictions = value
var budget_warning_remaining: float:
	get: return local_prediction.budget_warning_remaining
	set(value): local_prediction.budget_warning_remaining = value
var local_special_cooldown_remaining: float:
	get: return local_prediction.local_special_cooldown_remaining
	set(value): local_prediction.local_special_cooldown_remaining = value
var local_mine_charges_remaining: int:
	get: return local_prediction.local_mine_charges_remaining
	set(value): local_prediction.local_mine_charges_remaining = value
var local_mine_cooldown_remaining: float:
	get: return local_prediction.local_mine_cooldown_remaining
	set(value): local_prediction.local_mine_cooldown_remaining = value
var local_missile_charges_remaining: int:
	get: return local_prediction.local_missile_charges_remaining
	set(value): local_prediction.local_missile_charges_remaining = value
var local_missile_cooldown_remaining: float:
	get: return local_prediction.local_missile_cooldown_remaining
	set(value): local_prediction.local_missile_cooldown_remaining = value
var local_cloak_charges_remaining: int:
	get: return local_prediction.local_cloak_charges_remaining
	set(value): local_prediction.local_cloak_charges_remaining = value
var local_cloak_remaining: float:
	get: return local_prediction.local_cloak_remaining
	set(value): local_prediction.local_cloak_remaining = value
var local_cloak_cooldown_remaining: float:
	get: return local_prediction.local_cloak_cooldown_remaining
	set(value): local_prediction.local_cloak_cooldown_remaining = value
var local_breakaway_remaining: float:
	get: return local_prediction.local_breakaway_remaining
	set(value): local_prediction.local_breakaway_remaining = value
var local_kinetic_vent_charge: float:
	get: return local_prediction.local_kinetic_vent_charge
	set(value): local_prediction.local_kinetic_vent_charge = value
var local_breakaway_cooldown_remaining: float:
	get: return local_prediction.local_breakaway_cooldown_remaining
	set(value): local_prediction.local_breakaway_cooldown_remaining = value
var _nearest_incoming_cache: ProjectileState:
	get: return hud_camera._nearest_incoming_cache
	set(value): hud_camera._nearest_incoming_cache = value
var _nearest_incoming_revision: int:
	get: return hud_camera._nearest_incoming_revision
	set(value): hud_camera._nearest_incoming_revision = value
var _incoming_refresh_accumulator: float:
	get: return hud_camera._incoming_refresh_accumulator
	set(value): hud_camera._incoming_refresh_accumulator = value
var _diagnostics_refresh_accumulator: float:
	get: return hud_camera._diagnostics_refresh_accumulator
	set(value): hud_camera._diagnostics_refresh_accumulator = value
var expired_predicted_volleys: int:
	get: return local_prediction.expired_predicted_volleys
	set(value): local_prediction.expired_predicted_volleys = value
var last_snapshot_receive_time: float:
	get: return replicated_visuals.last_snapshot_receive_time
	set(value): replicated_visuals.last_snapshot_receive_time = value
var snapshot_jitter_ms: float:
	get: return replicated_visuals.snapshot_jitter_ms
	set(value): replicated_visuals.snapshot_jitter_ms = value
var snapshot_gap_count: int:
	get: return replicated_visuals.snapshot_gap_count
	set(value): replicated_visuals.snapshot_gap_count = value
var interpolation_sample_count: int:
	get: return replicated_visuals.interpolation_sample_count
	set(value): replicated_visuals.interpolation_sample_count = value
var interpolation_extrapolated_count: int:
	get: return replicated_visuals.interpolation_extrapolated_count
	set(value): replicated_visuals.interpolation_extrapolated_count = value


func _init() -> void:
	local_prediction.view = self
	replicated_visuals.view = self
	hud_camera.view = self


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
	local_peer_id = 0
	latest_server_tick = 0
	match_payload.clear()
	controls_enabled = false
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
	if local_peer_id == 0 or not replicated_visuals.ships.has(local_peer_id):
		return
	var local_ship := replicated_visuals.ships[local_peer_id] as CombatShipView
	local_prediction.step(delta, local_ship)
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


func _advance_input_clock() -> void:
	local_prediction._advance_input_clock()


func _on_connected(peer_id: int) -> void:
	local_peer_id = peer_id
	set_network_active(true)


func _on_snapshot(decoded: Dictionary) -> void:
	local_prediction.latest_acknowledged_input = int(decoded.acknowledged_input)
	var receive_time := _now_seconds()
	replicated_visuals._record_snapshot_arrival(int(decoded.server_tick), receive_time)
	latest_server_tick = int(decoded.server_tick)
	var present_ids: Dictionary = {}
	for state_value in decoded.states:
		var state := state_value as Dictionary
		var peer_id := int(state.peer_id)
		present_ids[peer_id] = true
		var ship := replicated_visuals._ensure_ship(peer_id, state)
		var revived := bool(state.alive) and not ship.combatant.alive
		ship.visible = String(match_payload.get("state_name", "")) != "DRAFT"
		replicated_visuals._handle_snapshot_feedback(peer_id, state, ship)
		replicated_visuals._apply_snapshot_resources(ship, state)
		if peer_id == local_peer_id:
			local_prediction.apply_local_snapshot(decoded, state, ship, revived)
		else:
			replicated_visuals.interpolation.add_sample(peer_id, receive_time, latest_server_tick, state)
	replicated_visuals.remove_missing_ships(present_ids)
	hud_camera._update_spectator_target()


func _sync_predicted_resources(ship: CombatShipView) -> void:
	local_prediction._sync_predicted_resources(ship)


func apply_match_state(payload: Dictionary) -> void:
	match_payload = payload.duplicate(true)
	hud_camera._update_competitive_view()
	var state_name := String(payload.get("state_name", ""))
	controls_enabled = state_name == "ACTIVE_HEAT"
	replicated_visuals.apply_match_state(payload, state_name)
	hud_camera.apply_match_state(state_name)
	apply_builds(payload.get("builds", {}) as Dictionary)
	if String(payload.get("state_name", "")) == "COUNTDOWN":
		local_prediction.reset_for_countdown()
		replicated_visuals.reset_for_countdown()
		hud_camera.reset_for_countdown()
	hud_camera._update_spectator_target()


func _update_competitive_view() -> void:
	hud_camera._update_competitive_view()


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


func apply_objective_state(objective: Dictionary) -> void:
	match_payload["objective"] = objective.duplicate(true)
	if replicated_visuals.arena != null:
		replicated_visuals.arena.set_objective(objective)


func apply_builds(builds: Dictionary) -> void:
	replicated_visuals.apply_builds(builds)
	local_prediction.local_stats = _stats_for_peer(local_peer_id, builds)


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


func _unhandled_input(event: InputEvent) -> void:
	hud_camera._unhandled_input(event)


func _on_projectile_batch(decoded: Dictionary) -> void:
	replicated_visuals._on_projectile_batch(decoded)


func _on_projectile_correction(decoded: Dictionary) -> void:
	replicated_visuals._on_projectile_correction(decoded)


func _ensure_ship(peer_id: int, state: Dictionary) -> CombatShipView:
	return replicated_visuals._ensure_ship(peer_id, state)


func _apply_snapshot_resources(ship: CombatShipView, state: Dictionary) -> void:
	replicated_visuals._apply_snapshot_resources(ship, state)


func _stats_for_peer(peer_id: int, builds: Dictionary = {}) -> CombatStats:
	return replicated_visuals._stats_for_peer(peer_id, builds)


func _build_for_peer(peer_id: int) -> Dictionary:
	return replicated_visuals._build_for_peer(peer_id)


func _emit_weapon_shot(
	owner_id: int,
	shot_sequence: int,
	position: Vector2,
	projectile: ProjectileState = null
) -> void:
	replicated_visuals._emit_weapon_shot(owner_id, shot_sequence, position, projectile)


func _audio_listener_position() -> Vector2:
	return hud_camera._audio_listener_position()


func _update_remote_ships() -> void:
	replicated_visuals._update_remote_ships()


func _spawn_predicted_projectile(ship: CombatShipView, aim_angle: float) -> void:
	local_prediction._spawn_predicted_projectile(ship, aim_angle)


func _expire_unconfirmed_predicted_projectiles(now_seconds: float) -> void:
	local_prediction._expire_unconfirmed_predicted_projectiles(now_seconds)


func _remove_predicted_volley(shot_sequence: int) -> void:
	local_prediction._remove_predicted_volley(shot_sequence)


func _reconcile_predicted_projectile(projectile: ProjectileState) -> void:
	local_prediction._reconcile_predicted_projectile(projectile)


func _projectile_confirmation_timeout_seconds() -> float:
	return local_prediction._projectile_confirmation_timeout_seconds()


func _record_snapshot_arrival(server_tick: int, receive_time: float) -> void:
	replicated_visuals._record_snapshot_arrival(server_tick, receive_time)


func _step_projectile_visuals(delta: float) -> void:
	replicated_visuals._step_projectile_visuals(delta)


func _synchronize_projectile(existing: ProjectileState, incoming: ProjectileState) -> bool:
	return replicated_visuals._synchronize_projectile(existing, incoming)


func _emit_rebound_feedback(projectile: ProjectileState) -> void:
	replicated_visuals._emit_rebound_feedback(projectile)


func _separate_local_visual_from_remote(local_ship: CombatShipView) -> void:
	local_prediction._separate_local_visual_from_remote(local_ship)


func _local_visual_candidate_available(position: Vector2, contacted_peer_id: int, minimum_distance: float) -> bool:
	return local_prediction._local_visual_candidate_available(position, contacted_peer_id, minimum_distance)


func _update_camera(local_ship: CombatShipView, delta: float) -> void:
	hud_camera._update_camera(local_ship, delta)


func _create_camera_and_hud() -> void:
	hud_camera._create_camera_and_hud()


func apply_combat_feedback(payload: Dictionary) -> void:
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


func _layout_accessible_hud() -> void:
	hud_camera._layout_accessible_hud()


func _update_diagnostics(delta: float = 0.0) -> void:
	hud_camera._update_diagnostics(delta)


func _local_is_eliminated() -> bool:
	return hud_camera._local_is_eliminated()


func _living_spectator_targets() -> Array[int]:
	return hud_camera._living_spectator_targets()


func _update_spectator_target() -> void:
	hud_camera._update_spectator_target()


func _cycle_spectator(direction: int) -> void:
	hud_camera._cycle_spectator(direction)


func nearest_incoming_offscreen_projectile() -> ProjectileState:
	return hud_camera.nearest_incoming_offscreen_projectile()


func _refresh_nearest_incoming_projectile() -> void:
	hud_camera._refresh_nearest_incoming_projectile()


func _visible_world_rect() -> Rect2:
	return hud_camera._visible_world_rect()


func trigger_camera_shake(intensity: float, duration: float) -> void:
	hud_camera.trigger_camera_shake(intensity, duration)


func trigger_afterburner_feedback(forward: Vector2) -> void:
	hud_camera.trigger_afterburner_feedback(forward)


func _create_indicator_layer() -> void:
	hud_camera._create_indicator_layer()


func _handle_snapshot_feedback(peer_id: int, state: Dictionary, ship: CombatShipView) -> void:
	replicated_visuals._handle_snapshot_feedback(peer_id, state, ship)


func _update_overtime_presentation() -> void:
	replicated_visuals._update_overtime_presentation()


func _update_camera_shake(delta: float) -> void:
	hud_camera._update_camera_shake(delta)


func gameplay_mouse_position() -> Vector2:
	return hud_camera.gameplay_mouse_position()


func _unshaken_mouse_world_position() -> Vector2:
	return hud_camera._unshaken_mouse_world_position()


func _player_color(peer_id: int) -> Color:
	return replicated_visuals._player_color(peer_id)


func _player_pattern(peer_id: int) -> StringName:
	return replicated_visuals._player_pattern(peer_id)


func team_for_peer(peer_id: int) -> int:
	return replicated_visuals.team_for_peer(peer_id)


func is_friendly_peer(peer_id: int) -> bool:
	return replicated_visuals.is_friendly_peer(peer_id)


func _display_name(peer_id: int) -> String:
	return replicated_visuals._display_name(peer_id)


func _player_identity(peer_id: int) -> Dictionary:
	return replicated_visuals._player_identity(peer_id)


func _make_resource_bar(color: Color) -> ProgressBar:
	return hud_camera._make_resource_bar(color)


func _hud_panel_style() -> StyleBoxFlat:
	return hud_camera._hud_panel_style()


func _flat_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	return hud_camera._flat_style(background, border, width)


static func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
