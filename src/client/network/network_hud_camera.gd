class_name NetworkHudCamera
extends RefCounted

## Owns HUD, camera motion, spectator selection and offscreen indicators.

const AccessibilityPreferencesScript = preload("res://src/client/presentation/accessibility_preferences.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const KillFeedScript = preload("res://src/client/ui/kill_feed.gd")

const ViewContext = preload("res://src/client/network/client_view_context.gd")
var context: ViewContext
var visuals: NetworkReplicatedVisuals
var local_prediction: NetworkLocalPrediction
var indicator_layer: OffscreenIndicatorLayer
var competitive_view_policy = preload("res://src/client/presentation/competitive_view_policy.gd").new()
var camera: Camera2D:
	get: return context.camera
	set(value): context.camera = value
var diagnostics_label: Label
var hud_panel: PanelContainer
var hud_root: Control
var match_status_label: Label
var resources_label: Label
var combat_status_label: Label
var spectator_label: Label
var spectator_curtain: ColorRect
var combat_feedback_panel: CombatFeedbackPanel
var kill_feed: Control
var health_bar: ProgressBar
var shield_bar: ProgressBar
var spectator_target_id: int = 0
var toggle_status_label: Label
var camera_shake_remaining: float = 0.0
var camera_shake_intensity: float = 0.0
var camera_kick_remaining: float = 0.0
var camera_kick_duration: float = 0.0
var camera_kick_offset: Vector2 = Vector2.ZERO
var diagnostics_visible: bool = false
var _nearest_incoming_cache: ProjectileState
var _nearest_incoming_revision: int = -1
var _incoming_refresh_accumulator: float = 0.0
var _diagnostics_refresh_accumulator: float = 0.0


func add_kill_feed_entries(eliminations: Array, server_tick: int) -> void:
	if kill_feed != null:
		kill_feed.add_eliminations(
			eliminations,
			server_tick,
			context.local_peer_id,
			context.match_payload.get("players", []) as Array
		)


func snap_camera_to_local_ship() -> void:
	if camera == null or not visuals.ships.has(context.local_peer_id):
		return
	camera.position = (visuals.ships[context.local_peer_id] as CombatShipView).global_position


func set_match_status(status: String) -> void:
	if match_status_label != null:
		match_status_label.text = status


func _unhandled_input(event: InputEvent) -> void:
	if not context.surface.visible:
		return
	if event.is_action_pressed(&"diagnostics") and not (event is InputEventKey and event.echo):
		diagnostics_visible = not diagnostics_visible
		diagnostics_label.visible = diagnostics_visible
		context.surface.get_viewport().set_input_as_handled()
		return
	if not _local_is_eliminated() or local_prediction.input_blocked:
		return
	var direction := 0
	if event.is_action_pressed(&"spectator_previous") and not (event is InputEventKey and event.echo):
		direction = -1
	elif event.is_action_pressed(&"spectator_next") and not (event is InputEventKey and event.echo):
		direction = 1
	if direction != 0:
		_cycle_spectator(direction)
		context.surface.get_viewport().set_input_as_handled()


func _audio_listener_position() -> Vector2:
	if visuals.ships.has(context.local_peer_id):
		return (visuals.ships[context.local_peer_id] as CombatShipView).global_position
	return camera.position if camera != null else Vector2.ZERO


func _update_camera(local_ship: CombatShipView, delta: float) -> void:
	var target_position := local_ship.global_position
	if not local_ship.combatant.alive:
		if spectator_target_id != 0 and visuals.ships.has(spectator_target_id):
			target_position = (visuals.ships[spectator_target_id] as CombatShipView).global_position
		else:
			target_position = local_ship.global_position if _restricted_team_spectating() else ArenaLayout.center(visuals.arena.map_id if visuals.arena != null else ArenaLayout.DEFAULT_MAP_ID)
	camera.position = camera.position.lerp(target_position, 1.0 - exp(-8.0 * delta))


func _create_camera_and_hud() -> void:
	camera = Camera2D.new()
	camera.position = ArenaLayout.center(visuals.arena.map_id if visuals.arena != null else ArenaLayout.DEFAULT_MAP_ID)
	camera.enabled = true
	context.surface.add_child(camera)
	var spectator_canvas := CanvasLayer.new()
	spectator_canvas.name = "SpectatorPrivacy"
	spectator_canvas.layer = 9 # Covers world/indicators, leaving the HUD readable.
	context.surface.add_child(spectator_canvas)
	spectator_curtain = ColorRect.new()
	spectator_curtain.color = Color("080e1a")
	spectator_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spectator_canvas.add_child(spectator_curtain)
	spectator_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	spectator_curtain.hide()
	var canvas := CanvasLayer.new()
	canvas.name = "CombatHUD"
	canvas.layer = 10
	context.surface.add_child(canvas)
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
	var feedback_anchor := VBoxContainer.new()
	feedback_anchor.name = "CombatFeedbackAnchor"
	feedback_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback_anchor.alignment = BoxContainer.ALIGNMENT_END
	hud_root.add_child(feedback_anchor)
	feedback_anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	feedback_anchor.offset_left = -180.0
	feedback_anchor.offset_right = 180.0
	# Leave the outer navigation markers and spectator controls unobstructed.
	# The container sizes the box to its visible text and keeps its bottom fixed.
	feedback_anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feedback_anchor.offset_top = -390.0
	feedback_anchor.offset_bottom = -210.0
	combat_feedback_panel = CombatFeedbackPanel.new()
	combat_feedback_panel.name = "CombatFeedback"
	feedback_anchor.add_child(combat_feedback_panel)
	context.surface.get_viewport().size_changed.connect(_layout_accessible_hud)
	_layout_accessible_hud()


func apply_combat_feedback(payload: Dictionary) -> void:
	var names: Dictionary = {}
	for player in context.match_payload.get("players", []):
		names[int(player.get("peer_id", 0))] = String(player.get("display_name", "Pilot"))
	if combat_feedback_panel != null:
		combat_feedback_panel.apply_feedback(payload, context.local_peer_id, names)


func _layout_accessible_hud() -> void:
	if hud_root == null:
		return
	var safe_rect: Rect2 = AccessibilityPreferencesScript.hud_safe_rect(context.surface.get_viewport_rect().size, bool(context.accessibility_settings.constrain_hud))
	var hud_scale := float(context.accessibility_settings.hud_scale)
	hud_root.position = safe_rect.position
	hud_root.scale = Vector2.ONE * hud_scale
	hud_root.size = safe_rect.size / hud_scale
	# Keep essential resources at the viewport edge even when other HUD
	# elements use the centered safe area on ultrawide displays.
	hud_panel.position = Vector2(16.0 - safe_rect.position.x / hud_scale, 16.0)
	var panel_width := minf(430.0, maxf(240.0, hud_root.size.x - 420.0 - 56.0))
	hud_panel.custom_minimum_size.x = panel_width
	hud_panel.size.x = panel_width
	match_status_label.custom_minimum_size.x = maxf(panel_width - 40.0, 100.0)
	spectator_label.custom_minimum_size.x = minf(720.0, hud_root.size.x - 32.0)
	spectator_label.size.x = spectator_label.custom_minimum_size.x
	spectator_label.position.x = (hud_root.size.x - spectator_label.size.x) * 0.5
	spectator_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func uses_compact_hud() -> bool:
	return float(context.accessibility_settings.hud_scale) >= 1.25 or visuals.ships.size() >= 16


func _update_diagnostics(delta: float = 0.0) -> void:
	var compact := uses_compact_hud()
	local_prediction.current_special_slot()
	var selected := local_prediction.selected_special_slot
	var resources := "Waiting for combat snapshot"
	var diagnostics_hint: String = context.input_profiles.binding_text(&"diagnostics") if context.input_profiles != null else "F3"
	var scoreboard_hint: String = context.input_profiles.binding_text(&"scoreboard") if context.input_profiles != null else "Tab"
	var combat_status := "%s network diagnostics · Hold %s scoreboard" % [diagnostics_hint, scoreboard_hint]
	if visuals.ships.has(context.local_peer_id):
		var local_ship := visuals.ships[context.local_peer_id] as CombatShipView
		health_bar.max_value = local_prediction.local_stats.max_health
		health_bar.value = local_ship.combatant.health
		shield_bar.max_value = local_prediction.local_stats.shield_capacity
		shield_bar.value = local_ship.combatant.shield.energy
		resources = "HULL %.0f/%.0f   SHIELD %.0f/%.0f   AMMO %d/%d" % [local_ship.combatant.health, local_prediction.local_stats.max_health, local_ship.combatant.shield.energy, local_prediction.local_stats.shield_capacity, local_ship.combatant.weapon.ammunition, local_prediction.local_stats.magazine_size]
		if compact:
			resources = "HULL %.0f · SHIELD %.0f\nAMMO %d/%d" % [local_ship.combatant.health, local_ship.combatant.shield.energy, local_ship.combatant.weapon.ammunition, local_prediction.local_stats.magazine_size]
		if local_prediction.local_stats.mine_layer_enabled and (not compact or selected == SpecialAbilitySelection.Slot.MINE):
			var mine_status := "%d" % local_prediction.local_mine_charges_remaining
			if local_prediction.local_mine_cooldown_remaining > 0.05:
				mine_status += " (%.1fs)" % local_prediction.local_mine_cooldown_remaining
			resources += "   MINES %s" % mine_status
		if local_prediction.local_stats.missile_launcher_enabled and (not compact or selected == SpecialAbilitySelection.Slot.MISSILE):
			var missile_status := "%d" % local_prediction.local_missile_charges_remaining
			if local_prediction.local_missile_cooldown_remaining > 0.05:
				missile_status += " (%.1fs)" % local_prediction.local_missile_cooldown_remaining
			resources += "   MISSILES %s" % missile_status
		if local_prediction.local_stats.cloak_enabled and (not compact or selected == SpecialAbilitySelection.Slot.CLOAK or local_prediction.local_cloak_remaining > 0.0):
			var cloak_status := "ACTIVE" if local_prediction.local_cloak_remaining > 0.0 else "READY"
			if local_prediction.local_cloak_remaining <= 0.0 and local_prediction.local_cloak_cooldown_remaining > 0.05:
				cloak_status = "%.1fs" % local_prediction.local_cloak_cooldown_remaining
			resources += "   CLOAK %s" % cloak_status
		if local_prediction.local_stats.kinetic_vent_enabled:
			resources += "   VENT %.0f/%.0f" % [local_prediction.local_kinetic_vent_charge, GameConstants.KINETIC_VENT_MAXIMUM_CHARGE]
		if local_prediction.local_stats.breakaway_thrusters_enabled:
			var breakaway_status := "ACTIVE" if local_prediction.local_breakaway_remaining > 0.0 else ("%.1fs" % local_prediction.local_breakaway_cooldown_remaining if local_prediction.local_breakaway_cooldown_remaining > 0.05 else "READY")
			resources += "   BREAKAWAY %s" % breakaway_status
		var reload_hint: String = context.input_profiles.binding_text(&"manual_reload") if context.input_profiles != null else "R"
		combat_status = "%s diagnostics   ·   Hold %s scoreboard   ·   %s reload" % [diagnostics_hint, scoreboard_hint, reload_hint]
		# Controls remain discoverable in countdown and pause/settings. During
		# combat reserve this space for selected abilities and actionable warnings.
		if String(context.match_payload.get("state_name", "")) == "ACTIVE_HEAT":
			combat_status = ""
		local_prediction.current_special_slot()
		if local_prediction.selected_special_slot >= 0:
			var special_hint: String = context.input_profiles.binding_text(&"special") if context.input_profiles != null else "Shift"
			var cycle_hint: String = "%s/%s" % [context.input_profiles.binding_text(&"special_previous"), context.input_profiles.binding_text(&"special_next")] if context.input_profiles != null else "Q/E"
			combat_status += "\n%s %s · %s select" % [special_hint, SpecialAbilitySelection.label(local_prediction.selected_special_slot), cycle_hint]
		if local_prediction.local_stats.mine_layer_enabled and (not compact or selected == SpecialAbilitySelection.Slot.MINE):
			combat_status += " · DEPLOYED %d/16" % local_prediction.local_active_mines
		if local_prediction.budget_warning_remaining > 0.0:
			combat_status += "\nORDNANCE LIMIT · oldest eligible weapon replaced"
		if not local_ship.combatant.alive:
			# Elimination can leave authoritative shield energy above zero (for
			# example, damage that bypasses shields). Do not present that stale
			# resource as an available shield while spectating.
			shield_bar.value = 0.0
			resources = "SHIP ELIMINATED"
			var previous_hint: String = context.input_profiles.binding_text(&"spectator_previous") if context.input_profiles != null else "A"
			var next_hint: String = context.input_profiles.binding_text(&"spectator_next") if context.input_profiles != null else "D"
			spectator_label.text = "SPECTATING %s   ◀ %s     %s ▶" % [visuals._display_name(spectator_target_id), previous_hint, next_hint] if spectator_target_id != 0 else "NO SURVIVING TARGET · ARENA VIEW"
			if spectator_target_id == 0 and _restricted_team_spectating():
				spectator_label.text = "NO VISIBLE TEAMMATE · WAITING TO REJOIN"
			spectator_label.visible = true
		else:
			spectator_label.visible = false
	resources_label.text = resources
	combat_status_label.text = combat_status.strip_edges()
	combat_status_label.visible = not combat_status_label.text.is_empty()
	if toggle_status_label == null and hud_root != null:
		toggle_status_label = local_prediction.action_latch.create_status_label(hud_root)
	if toggle_status_label != null:
		toggle_status_label.text = local_prediction.action_latch.status(context.accessibility_settings)
	_diagnostics_refresh_accumulator += maxf(delta, 0.0)
	if diagnostics_visible and _diagnostics_refresh_accumulator >= 0.25:
		_diagnostics_refresh_accumulator = fmod(_diagnostics_refresh_accumulator, 0.25)
		var network_stats := context.bridge.get_network_statistics()
		var extrapolation_percent := (
			float(visuals.interpolation_extrapolated_count) / visuals.interpolation_sample_count * 100.0
			if visuals.interpolation_sample_count > 0
			else 0.0
		)
		diagnostics_label.text = (
			"NETWORK · FPS %d · RTT %d ± %d ms · TCP\n"
			+ "SNAP · jitter %.1f ms · gaps %d · extrap %.1f%% · buffer %d ms\n"
			+ "PRED · error %.2f px · snaps %d · pending %d · expired shots %d · ack %d"
		) % [
			Engine.get_frames_per_second(),
			int(network_stats.rtt_ms),
			int(network_stats.rtt_variance_ms),
			visuals.snapshot_jitter_ms,
			visuals.snapshot_gap_count,
			extrapolation_percent,
			roundi(RemoteInterpolator.INTERPOLATION_DELAY_SECONDS * 1000.0),
			local_prediction.prediction.last_reconciliation_error,
			local_prediction.prediction.snap_count,
			local_prediction.prediction.buffered_inputs.size(),
			local_prediction.expired_predicted_volleys,
			local_prediction.latest_acknowledged_input,
		]


func _local_is_eliminated() -> bool:
	return visuals.ships.has(context.local_peer_id) and not (visuals.ships[context.local_peer_id] as CombatShipView).combatant.alive


func _restricted_team_spectating() -> bool:
	return bool(context.match_payload.get("competitive_view", false)) and GameModeRules.is_team_mode(int(context.match_payload.get("game_mode", 0))) and visuals.team_for_peer(context.local_peer_id) > 0


func _living_spectator_targets() -> Array[int]:
	var result: Array[int] = []
	for peer_value in visuals.ships.keys():
		var peer_id := int(peer_value)
		var ship := visuals.ships[peer_id] as CombatShipView
		if _restricted_team_spectating() and not visuals.is_friendly_peer(peer_id):
			continue
		if peer_id != context.local_peer_id and ship.combatant.alive and not ship.combatant.is_cloaked():
			result.append(peer_id)
	result.sort()
	return result


func _update_spectator_target() -> void:
	if spectator_curtain != null:
		spectator_curtain.hide()
	if not _local_is_eliminated():
		spectator_target_id = 0
		return
	var targets := _living_spectator_targets()
	if targets.is_empty():
		spectator_target_id = 0
	elif spectator_target_id not in targets:
		spectator_target_id = targets[0]
	if spectator_curtain != null:
		spectator_curtain.visible = context._network_active and _restricted_team_spectating() and spectator_target_id == 0 and String(context.match_payload.get("state_name", "")) in ["ACTIVE_HEAT", "OVERTIME"]


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
	if _nearest_incoming_revision != visuals.authoritative_projectiles.revision:
		_refresh_nearest_incoming_projectile()
	return _nearest_incoming_cache


func _refresh_nearest_incoming_projectile() -> void:
	_nearest_incoming_cache = null
	_nearest_incoming_revision = visuals.authoritative_projectiles.revision
	if not visuals.ships.has(context.local_peer_id):
		return
	var local_position := (visuals.ships[context.local_peer_id] as CombatShipView).global_position
	var nearest_distance := INF
	for projectile_id in visuals.authoritative_projectiles.ordered_ids_view():
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := visuals.authoritative_projectiles.get_projectile(projectile_id)
		if projectile == null:
			continue
		if visuals.is_friendly_peer(projectile.owner_id):
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
	var viewport_size := context.surface.get_viewport_rect().size
	var zoom := Vector2(maxf(camera.zoom.x, 0.001), maxf(camera.zoom.y, 0.001))
	var world_size := viewport_size / zoom
	return Rect2(camera.position - world_size * 0.5, world_size)


func trigger_camera_shake(intensity: float, duration: float) -> void:
	if bool(context.accessibility_settings.reduced_shake):
		return
	camera_shake_intensity = maxf(camera_shake_intensity, intensity)
	camera_shake_remaining = maxf(camera_shake_remaining, duration)


func trigger_afterburner_feedback(forward: Vector2) -> void:
	if bool(context.accessibility_settings.reduced_shake):
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
	context.surface.add_child(canvas)
	indicator_layer = OffscreenIndicatorLayer.new()
	indicator_layer.setup(self, visuals, context)
	canvas.add_child(indicator_layer)


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


func gameplay_mouse_position() -> Vector2:
	return competitive_view_policy.gameplay_point(context.surface.get_viewport().get_mouse_position())


func _unshaken_mouse_world_position() -> Vector2:
	if camera == null:
		return context.surface.get_canvas_transform().affine_inverse() * gameplay_mouse_position()
	var screen_offset := gameplay_mouse_position() - context.surface.get_viewport_rect().size * 0.5
	return camera.position + Vector2(screen_offset.x / camera.zoom.x, screen_offset.y / camera.zoom.y)


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


func _update_competitive_view() -> void:
	if context.surface.is_inside_tree():
		competitive_view_policy.apply(context.surface.get_window(), context._network_active and bool(context.match_payload.get("competitive_view", false)))


func step_incoming_refresh(delta: float) -> void:
	_incoming_refresh_accumulator += maxf(delta, 0.0)
	if _incoming_refresh_accumulator >= 0.1:
		_incoming_refresh_accumulator = fmod(_incoming_refresh_accumulator, 0.1)
		_refresh_nearest_incoming_projectile()


func reset_session() -> void:
	competitive_view_policy.restore()
	if spectator_curtain != null:
		spectator_curtain.hide()
	if combat_feedback_panel != null:
		combat_feedback_panel.clear_feedback(true)
	spectator_target_id = 0
	camera_shake_remaining = 0.0
	camera_shake_intensity = 0.0
	camera_kick_remaining = 0.0
	camera_kick_duration = 0.0
	camera_kick_offset = Vector2.ZERO
	_nearest_incoming_cache = null
	_nearest_incoming_revision = -1
	_incoming_refresh_accumulator = 0.0
	_diagnostics_refresh_accumulator = 0.0
	if kill_feed != null:
		kill_feed.clear()
	if camera != null:
		camera.position = ArenaLayout.center(ArenaLayout.DEFAULT_MAP_ID)
		camera.offset = Vector2.ZERO


func apply_match_state(state_name: String) -> void:
	_nearest_incoming_revision = -1
	if hud_panel != null:
		hud_panel.visible = state_name in ["COUNTDOWN", "ACTIVE_HEAT", "HEAT_RESULT", "ROUND_RESULT"]
	if kill_feed != null:
		kill_feed.set_match_state(state_name)


func reset_for_countdown() -> void:
	if combat_feedback_panel != null:
		combat_feedback_panel.clear_feedback(true)
	snap_camera_to_local_ship()


func shutdown() -> void:
	competitive_view_policy.restore()
	if context.surface.is_inside_tree() and context.surface.get_viewport().size_changed.is_connected(_layout_accessible_hud):
		context.surface.get_viewport().size_changed.disconnect(_layout_accessible_hud)


func apply_accessibility_settings(settings: Dictionary) -> void:
	if bool(settings.reduced_shake):
		camera_shake_remaining = 0.0
		camera_kick_remaining = 0.0
		if camera != null:
			camera.offset = Vector2.ZERO
	_layout_accessible_hud()


func reset_feedback_for_life(generation: int) -> void:
	if combat_feedback_panel != null:
		combat_feedback_panel.reset_for_life(generation)
