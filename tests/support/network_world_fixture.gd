class_name NetworkWorldFixture
extends NetworkWorldView

## Test-only compatibility surface for integration fixtures.
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


func _advance_input_clock() -> void:
	local_prediction._advance_input_clock()


func _sync_predicted_resources(ship: CombatShipView) -> void:
	local_prediction._sync_predicted_resources(ship)


func _update_competitive_view() -> void:
	hud_camera._update_competitive_view()


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


func _refresh_nearest_incoming_projectile() -> void:
	hud_camera._refresh_nearest_incoming_projectile()


func _visible_world_rect() -> Rect2:
	return hud_camera._visible_world_rect()


func _create_indicator_layer() -> void:
	hud_camera._create_indicator_layer()


func _handle_snapshot_feedback(peer_id: int, state: Dictionary, ship: CombatShipView) -> void:
	replicated_visuals._handle_snapshot_feedback(peer_id, state, ship)


func _update_overtime_presentation() -> void:
	replicated_visuals._update_overtime_presentation()


func _update_camera_shake(delta: float) -> void:
	hud_camera._update_camera_shake(delta)


func _unshaken_mouse_world_position() -> Vector2:
	return hud_camera._unshaken_mouse_world_position()


func _player_color(peer_id: int) -> Color:
	return replicated_visuals._player_color(peer_id)


func _player_pattern(peer_id: int) -> StringName:
	return replicated_visuals._player_pattern(peer_id)


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
