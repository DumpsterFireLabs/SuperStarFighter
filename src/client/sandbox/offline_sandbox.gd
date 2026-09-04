class_name OfflineSandbox
extends Node2D

const LabPanelScript = preload("res://src/client/sandbox/lab_panel.gd")
const TutorialScript = preload("res://src/client/sandbox/combat_tutorial.gd")
const AbilitySelection = preload("res://src/shared/combat/special_ability_selection.gd")
const FeedbackPresentation = preload("res://src/client/presentation/combat_feedback_presentation.gd")
const KillFeedScript = preload("res://src/client/ui/kill_feed.gd")
const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")
const TARGET_COUNT: int = 5
const TARGET_COLORS: Array[Color] = [Color("ff4f78"), Color("ff9f43"), Color("b66cff"), Color("62ff9b"), Color("ffd95a")]
const PRESET_NAMES: Array[String] = ["Base ship", "Rapid scatter", "Beam specialist", "Shield tank", "All abilities"]
const LAB_MAP_IDS: Array[StringName] = [&"core_arena", &"solar_tide"]
const PRESET_BUILDS: Array[Dictionary] = [
	{}, {&"rapid_cycling": 2, &"twin_shot": 2, &"extended_magazine": 2},
	{&"beam_emitter": 1, &"heavy_rounds": 2, &"quick_loader": 2},
	{&"reinforced_hull": 2, &"capacitor_bank": 2, &"quick_charge": 2},
	{&"afterburner": 1, &"mine_layer": 1, &"hunter_missiles": 1, &"cloak": 1},
]
signal presentation_event(event_name: StringName, payload: Dictionary)

var catalog: CardCatalog = CardCatalog.create_default()
var build: Dictionary = {}
var selected_card_index: int = 0
var selected_special_slot: int = -1
var derived_stats: CombatStats = CombatStats.create_base()
var world := AuthoritativeWorld.new()
var player: CombatShipView
var targets: Array[CombatShipView] = []
var ships_by_id: Dictionary = {}
var projectile_registry: ProjectileRegistry
var projectile_layer: ProjectileLayer
var effects_layer: CombatEffectsLayer
var arena: ArenaView
var camera: Camera2D
var status_label: Label
var feedback_label: Label
var card_label: Label
var help_label: Label
var hud_canvas: CanvasLayer
var hud_root: Control
var lab_panel: Control
var editor_button: Button
var kill_feed: Control
var kill_feed_event_sequence: int = 0
var heat_elapsed: float = 0.0
var overtime_debug_stage: int = 0
var overtime_enabled: bool = false
var targets_shielding: bool = false
var targets_firing: bool = false
var targets_moving: bool = false
var target_health: float = 100.0
var target_count: int = 1
var target_distance: float = 420.0
var input_profiles: Node
var editor_open: bool = true
var combat_input_armed: bool = false
var input_sequence: int = 0
var special_sequence: int = 0
var shots_fired: int = 0
var hull_hits: int = 0
var blocked_shots: int = 0
var measured_damage: float = 0.0
var measurement_seconds: float = 0.0
var measurement_started: bool = false
var last_damage_source: String = "none"
var feedback_remaining: float = 0.0
var hud_refresh_remaining: float = 0.0
var camera_kick_remaining: float = 0.0
var camera_kick_duration: float = 0.0
var camera_kick_offset: Vector2 = Vector2.ZERO
var accessibility: Dictionary = {}
var toggle_status_label: Label
var action_latch = preload("res://src/client/input/combat_action_latch.gd").new()
var tutorial: RefCounted


func _ready() -> void:
	arena = ArenaView.new()
	arena.name = "Arena"
	add_child(arena)
	projectile_registry = world.projectile_registry
	projectile_layer = ProjectileLayer.new()
	projectile_layer.name = "Projectiles"
	projectile_layer.registry = projectile_registry
	add_child(projectile_layer)
	effects_layer = CombatEffectsLayer.new()
	effects_layer.name = "CombatEffects"
	effects_layer.z_index = 5
	add_child(effects_layer)
	_create_ships()
	_create_camera()
	_create_hud()
	_reset_combatants()
	_update_card_label()
	get_viewport().size_changed.connect(_layout_hud)
	print("SSF_SANDBOX_READY=offline_combat")


func _physics_process(delta: float) -> void:
	if editor_open or (tutorial != null and tutorial.blocks_simulation()):
		action_latch.reset()
		_update_camera(delta)
		return
	if not combat_input_armed:
		if Input.is_action_pressed("fire") or Input.is_action_pressed("special"):
			return
		combat_input_armed = true
	var aim_vector: Vector2 = input_profiles.aim_vector() if input_profiles != null and input_profiles.uses_controller() else get_global_mouse_position() - player.global_position
	var aim_angle := player.combatant.aim_angle if aim_vector.is_zero_approx() else aim_vector.angle()
	var movement: Vector2 = input_profiles.movement_input_for_aim(aim_angle) if input_profiles != null else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input_sequence = SequenceMath.increment(input_sequence)
	var pressed := Input.is_action_just_pressed("special")
	if pressed:
		special_sequence = SequenceMath.increment(special_sequence)
	var frame := PlayerInputFrame.new(input_sequence, world.server_tick, movement, aim_angle, action_latch.sample(&"fire", Input.is_action_pressed("fire"), bool(accessibility.get("toggle_fire", false)), player.combatant.alive), action_latch.sample(&"shield", Input.is_action_pressed("shield"), bool(accessibility.get("toggle_shield", false)), player.combatant.alive), Input.is_action_pressed("manual_reload"), pressed, special_sequence)
	# Selection is shared with the network client; the authoritative step activates
	# exactly the selected ability, including its inventory and cooldown rules.
	if InputMap.has_action("special_previous") and Input.is_action_just_pressed("special_previous"):
		_cycle_special(-1)
	if InputMap.has_action("special_next") and Input.is_action_just_pressed("special_next"):
		_cycle_special(1)
	frame.special_slot = selected_special_slot
	step_lab(delta, frame)
	_update_camera(delta)
	hud_refresh_remaining -= delta
	if hud_refresh_remaining <= 0.0:
		_update_hud()
		hud_refresh_remaining = 0.1


## The live lab and regression fixtures use the same server simulation entry point.
func step_lab(delta: float, frame: PlayerInputFrame) -> void:
	if tutorial != null and tutorial.blocks_simulation():
		return
	if feedback_remaining > 0.0:
		feedback_remaining = maxf(feedback_remaining - delta, 0.0)
		if feedback_remaining == 0.0:
			feedback_label.text = ""
	var before := _presentation_states()
	world.submit_input(1, frame)
	player.set_thrust_input(frame.movement)
	for index in targets.size():
		var target := targets[index].combatant
		var angle := (player.combatant.position - target.position).angle()
		var movement := Vector2(0.55 * sin(heat_elapsed * 1.6 + index), 0.0) if targets_moving else Vector2.ZERO
		world.submit_input(target.peer_id, PlayerInputFrame.new(frame.sequence, world.server_tick, movement, angle, targets_firing and not player.combatant.is_cloaked(), targets_shielding))
	world.step(delta)
	heat_elapsed += maxf(delta, 0.0)
	if overtime_enabled:
		world.apply_overtime(heat_elapsed, delta)
	_sync_presentation(before)
	_consume_feedback()
	var batch := world.drain_projectile_batch()
	for projectile_value in batch.spawned:
		var projectile := projectile_value as ProjectileState
		if projectile.is_missile and not projectile.has_rebounded:
			_emit_effect(&"missile_launch", {"projectile_id": projectile.projectile_id, "owner_id": projectile.owner_id}, projectile.position)
	for detonation in world.drain_mine_detonations():
		effects_layer.spawn_mine_explosion(detonation.position)
		_emit_effect(&"mine_detonated", detonation, detonation.position)
	if measurement_started:
		measurement_seconds += maxf(delta, 0.0)
	projectile_layer.queue_redraw()
	arena.set_overtime(overtime_enabled and OvertimeSystem.is_active(heat_elapsed), OvertimeSystem.radius_at(heat_elapsed))
	if tutorial != null:
		tutorial.after_step(frame)


func _presentation_states() -> Dictionary:
	var result: Dictionary = {}
	for peer_id in ships_by_id:
		var ship := ships_by_id[peer_id] as CombatShipView
		result[peer_id] = {"alive": ship.combatant.alive, "health": ship.combatant.health, "shot": ship.combatant.weapon.shot_sequence, "boost": ship.combatant.afterburner_remaining, "vent": ship.combatant.kinetic_vent_feedback_remaining}
	return result


func _sync_presentation(before: Dictionary) -> void:
	var kills: Dictionary = {}
	for event in world.drain_kill_events():
		kills[int(event.target_id)] = int(event.killer_id)
	var eliminations: Array[Dictionary] = []
	for peer_id in ships_by_id:
		var ship := ships_by_id[peer_id] as CombatShipView
		var state := ship.combatant
		var previous: Dictionary = before[peer_id]
		ship.global_position = state.position
		ship.velocity = state.velocity
		ship.set_movement_field_strength(ArenaMovementSystem.influence_at(state.position, world.map_id))
		if previous.alive and not state.alive:
			ship.set_eliminated()
			var killer := int(kills.get(peer_id, 0))
			eliminations.append({"killer_id": killer, "victim_id": peer_id, "reason": "combat" if killer > 0 else "environment"})
			if not bool(accessibility.get("reduced_flashes", false)):
				effects_layer.spawn_elimination(state.position, ship.ship_color, peer_id == 1)
		elif state.health < float(previous.health) and not bool(accessibility.get("reduced_flashes", false)):
			ship.flash_damage()
		if state.weapon.shot_sequence != int(previous.shot):
			if peer_id == 1:
				shots_fired += 1
				measurement_started = true
			_emit_effect(&"weapon_fire", {"owner_id": peer_id, "shot_sequence": state.weapon.shot_sequence, "profile": WeaponSoundProfileScript.from_stats(state.stats, build if peer_id == 1 else {}, catalog)}, state.position)
		if state.afterburner_remaining > float(previous.boost):
			ship.flash_afterburner(state.afterburner_remaining)
			if peer_id == 1:
				_trigger_afterburner_feedback(Vector2.from_angle(state.aim_angle))
			_emit_effect(&"afterburner", {"peer_id": peer_id}, state.position)
		if state.kinetic_vent_feedback_remaining > float(previous.vent):
			effects_layer.spawn_kinetic_vent(state.position)
			_emit_effect(&"kinetic_vent", {"peer_id": peer_id}, state.position)
		ship.queue_redraw()
	if not eliminations.is_empty():
		kill_feed_event_sequence += 1
		kill_feed.add_eliminations(eliminations, kill_feed_event_sequence, 1, _kill_feed_identities())


func _consume_feedback() -> void:
	# This feedback is damage actually resolved by the world, after shields,
	# overkill and attribution. It is not estimated from weapon stats or HP deltas.
	var recipients: Dictionary = world.drain_combat_feedback()
	for peer_id in recipients:
		var event: Dictionary = recipients[peer_id]
		var ship := ships_by_id.get(int(peer_id)) as CombatShipView
		if int(event.get("guard_count", 0)) > 0 and ship != null:
			if not bool(accessibility.get("reduced_flashes", false)):
				ship.flash_shield_block()
			_emit_effect(&"shield_block", {"peer_id": peer_id}, ship.global_position)
		if int(peer_id) == 1:
			if tutorial != null:
				tutorial.observe_feedback(event)
			hull_hits += int(event.get("hit_count", 0))
			blocked_shots += int(event.get("blocked_count", 0))
			measured_damage += float(event.get("hit_damage", 0.0))
			if int(event.get("hit_count", 0)) > 0:
				measurement_started = true
				last_damage_source = String(event.get("last_hit_source", "projectile")).replace("_", " ")
			var messages := PackedStringArray()
			for value in [FeedbackPresentation.hit_text(event), FeedbackPresentation.block_text(event), FeedbackPresentation.guard_text(event)]:
				if not value.is_empty():
					messages.append(value)
			if event.has("death"):
				var names: Dictionary = {}
				for identity in _kill_feed_identities():
					names[identity.peer_id] = identity.display_name
				feedback_label.text = FeedbackPresentation.death_text(event.death, 1, names)
				feedback_remaining = 0.0
			elif not messages.is_empty() and player.combatant.alive:
				feedback_label.text = " · ".join(messages)
				feedback_remaining = 2.0


func _emit_effect(event_name: StringName, payload: Dictionary, origin: Vector2) -> void:
	payload["position"] = origin
	payload["listener_position"] = player.global_position
	payload["local"] = int(payload.get("owner_id", payload.get("peer_id", 0))) == 1
	payload["server_tick"] = world.server_tick
	presentation_event.emit(event_name, payload)


func set_sandbox_active(active: bool) -> void:
	action_latch.reset()
	if not active and tutorial != null and tutorial.active:
		tutorial.stop()
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if camera != null:
		camera.enabled = active
	if hud_canvas != null:
		hud_canvas.visible = active
	if not active and kill_feed != null:
		kill_feed.clear()
	if active and editor_open and input_profiles != null and input_profiles.uses_controller():
		editor_button.grab_focus()


func set_input_profile_manager(profile_manager: Node) -> void:
	input_profiles = profile_manager
	if not input_profiles.scheme_changed.is_connected(_on_input_profile_changed):
		input_profiles.scheme_changed.connect(_on_input_profile_changed)
	if not input_profiles.bindings_changed.is_connected(_update_help_text):
		input_profiles.bindings_changed.connect(_update_help_text)
	_update_help_text()


func _unhandled_input(event: InputEvent) -> void:
	if tutorial != null and tutorial.active:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_Y:
				tutorial.retry_step()
				get_viewport().set_input_as_handled()
			elif event.physical_keycode == KEY_F2:
				tutorial.stop()
				get_viewport().set_input_as_handled()
		return
	if not editor_open and event.is_action_pressed("ui_accept"):
		set_editor_open(true)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F2:
		set_editor_open(not editor_open)
		get_viewport().set_input_as_handled()
	elif not editor_open:
		match event.physical_keycode:
			KEY_Y: _reset_combatants()
			KEY_O:
				if event.shift_pressed:
					_cycle_overtime_debug()
				else:
					_toggle_overtime_debug()
			KEY_F1: help_label.visible = not help_label.visible


func _create_ships() -> void:
	for index in TARGET_COUNT + 1:
		var ship := CombatShipView.new()
		var state := world.add_peer(index + 1)
		ship.setup(index + 1, state.stats, state.position, Color("42e8ff") if index == 0 else TARGET_COLORS[index - 1], index == 0, "You" if index == 0 else "Target %d" % index)
		ship.combatant = state
		# The shared world owns collisions; these nodes only draw its state.
		ship.collision_layer = 0
		ship.collision_mask = 0
		add_child(ship)
		ships_by_id[index + 1] = ship
		if index == 0:
			player = ship
		else:
			targets.append(ship)


func _create_camera() -> void:
	camera = Camera2D.new()
	camera.name = "FollowCamera"
	camera.position = player.global_position
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameConstants.ARENA_SIZE.x)
	camera.limit_bottom = int(GameConstants.ARENA_SIZE.y)
	camera.limit_smoothed = true
	add_child(camera)


func _create_hud() -> void:
	hud_canvas = CanvasLayer.new()
	hud_canvas.name = "CombatHUD"
	add_child(hud_canvas)
	hud_root = Control.new()
	hud_root.theme = DesignTokens.create_interface_theme()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_canvas.add_child(hud_root)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(status_label)
	feedback_label = Label.new()
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_font_size_override("font_size", 18)
	feedback_label.add_theme_color_override("font_color", Color("ffd95a"))
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(feedback_label)
	editor_button = Button.new()
	editor_button.text = "Enter range · F2"
	editor_button.theme_type_variation = &"PrimaryButton"
	editor_button.custom_minimum_size.y = DesignTokens.CONTROL_HEIGHT
	editor_button.pressed.connect(func() -> void: set_editor_open(not editor_open))
	hud_root.add_child(editor_button)
	lab_panel = LabPanelScript.new()
	lab_panel.name = "BuildEditor"
	hud_root.add_child(lab_panel)
	lab_panel.configure(self)
	tutorial = TutorialScript.new()
	tutorial.configure(self, hud_root)
	card_label = lab_panel.card_description
	help_label = lab_panel.help_label
	kill_feed = KillFeedScript.new()
	kill_feed.name = "KillFeed"
	hud_canvas.add_child(kill_feed)
	kill_feed.set_match_state("ACTIVE_HEAT")
	_update_help_text()
	_layout_hud()


func set_editor_open(value: bool) -> void:
	action_latch.reset()
	editor_open = value
	combat_input_armed = false
	lab_panel.visible = value
	editor_button.text = "Enter range · F2" if value else "Edit build · F2"
	# Release focused text/buttons before combat resumes. A click on the editor
	# never becomes a held shot in the same input frame.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	if value:
		if input_profiles != null and input_profiles.uses_controller():
			editor_button.grab_focus()
		else:
			lab_panel.focus_search()
	_update_hud()


func _layout_hud() -> void:
	if hud_root == null:
		return
	var viewport := get_viewport_rect().size
	var hud_scale := clampf(float(accessibility.get("hud_scale", 1.0)), 1.0, 1.5)
	var safe_width := minf(viewport.x, 1920.0) if bool(accessibility.get("constrain_hud", true)) else viewport.x
	hud_root.position = Vector2((viewport.x - safe_width) * 0.5 + 20.0, 16.0)
	hud_root.scale = Vector2.ONE * hud_scale
	hud_root.size = Vector2((safe_width - 40.0) / hud_scale, (viewport.y - 32.0) / hud_scale)
	status_label.position = Vector2.ZERO
	status_label.size = Vector2(hud_root.size.x, 62.0)
	editor_button.position = Vector2(0.0, 68.0)
	feedback_label.position = Vector2(260.0, 68.0)
	feedback_label.size = Vector2(maxf(hud_root.size.x - 260.0, 100.0), 54.0)
	lab_panel.position = Vector2(0.0, 132.0)
	lab_panel.size = Vector2(minf(520.0, hud_root.size.x), maxf(hud_root.size.y - 132.0, 120.0))
	if tutorial != null:
		tutorial.layout()


func start_tutorial() -> void:
	tutorial.start()


func stop_tutorial() -> void:
	tutorial.stop()


func apply_accessibility_settings(values: Dictionary) -> void:
	accessibility = values.duplicate()
	action_latch.reset()
	if arena != null:
		arena.set_high_contrast(bool(values.get("high_contrast", false)))
	if bool(values.get("reduced_shake", false)):
		camera_kick_remaining = 0.0
		if camera != null:
			camera.offset = Vector2.ZERO
	if effects_layer != null:
		effects_layer.set("reduced_flashes", bool(values.get("reduced_flashes", false)))
	for ship_value in ships_by_id.values():
		(ship_value as CombatShipView).high_contrast = bool(values.get("high_contrast", false))
		(ship_value as CombatShipView).queue_redraw()
		(ship_value as CombatShipView).reduced_flashes = bool(values.get("reduced_flashes", false))
	_layout_hud()


func _update_help_text() -> void:
	if help_label == null:
		return
	var special := input_profiles.binding_text(&"special") as String if input_profiles != null else "Shift"
	help_label.text = "F2 edit / fly · Enter or controller A opens editor\nY reset encounter\nQ/E or D-pad select ability · %s activate\nO toggle overtime · Shift+O cycle stages\nBuild and target changes reset the encounter.\nRange stays untimed until overtime is enabled." % special


func _on_input_profile_changed(_scheme: int) -> void:
	_update_help_text()


func _cycle_special(direction: int) -> void:
	selected_special_slot = AbilitySelection.cycle(selected_special_slot, derived_stats, direction)
	_update_hud()


func _update_hud() -> void:
	if status_label == null or player == null:
		return
	var state := player.combatant
	var special_name := AbilitySelection.label(selected_special_slot)
	var cooldown := 0.0
	var charges := -1
	match selected_special_slot:
		0: cooldown = state.afterburner_cooldown_remaining
		1:
			cooldown = state.mine_cooldown_remaining
			charges = state.mine_charges_remaining
		2:
			cooldown = state.missile_cooldown_remaining
			charges = state.missile_charges_remaining
		3:
			cooldown = state.cloak_cooldown_remaining
			charges = state.cloak_charges_remaining
	if selected_special_slot >= 0:
		special_name += " ×%d" % charges if charges >= 0 else ""
		special_name += " (%.1fs)" % cooldown if cooldown > 0.0 else " READY" if charges != 0 else " EMPTY"
	status_label.text = "COMBAT LAB · %s · %s · HP %.0f/%.0f · Ammo %d/%d · Ability: %s\n%d shots · %d hull hits · %d blocked · %.1f damage / %.1fs = %.1f DPS" % ["PAUSED" if editor_open else "LIVE", ArenaLayout.display_name(world.map_id), state.health, state.stats.max_health, state.weapon.ammunition, state.stats.magazine_size, special_name, shots_fired, hull_hits, blocked_shots, measured_damage, measurement_seconds, measured_dps()]
	if toggle_status_label == null and hud_root != null:
		toggle_status_label = action_latch.create_status_label(hud_root)
	if toggle_status_label != null:
		toggle_status_label.text = action_latch.status(accessibility)
	if lab_panel != null:
		lab_panel.refresh_telemetry()


func measured_dps() -> float:
	return measured_damage / measurement_seconds if measurement_seconds > 0.0 else 0.0


func reset_measurements() -> void:
	shots_fired = 0
	hull_hits = 0
	blocked_shots = 0
	measured_damage = 0.0
	measurement_seconds = 0.0
	measurement_started = false
	last_damage_source = "none"
	feedback_label.text = ""
	feedback_remaining = 0.0
	_update_hud()


func _update_card_label() -> void:
	if card_label == null:
		return
	selected_card_index = wrapi(selected_card_index, 0, catalog.size())
	var card_id := catalog.all_ids()[selected_card_index]
	var card := catalog.get_card(card_id)
	card_label.text = "%s · ×%d\n%s" % [card.display_name, int(build.get(card_id, 0)), card.description]
	card_label.add_theme_color_override("font_color", card.rarity_color())
	for row in StatSystem.compare_pick_typed(build, card, catalog):
		card_label.text += "\n%s: %.2f → %.2f%s" % [String(row.property).replace("_", " "), row.before, row.after, " (limit)" if row.limited else ""]


func _grant_selected_card() -> void:
	var card_id := catalog.all_ids()[selected_card_index]
	build[card_id] = int(build.get(card_id, 0)) + 1
	_apply_build()


func remove_selected_card() -> void:
	var card_id := catalog.all_ids()[selected_card_index]
	var stacks := int(build.get(card_id, 0)) - 1
	if stacks > 0:
		build[card_id] = stacks
	else:
		build.erase(card_id)
	_apply_build()


func load_preset(index: int) -> void:
	if index < 0 or index >= PRESET_BUILDS.size():
		return
	build = PRESET_BUILDS[index].duplicate()
	_apply_build()


func _apply_build() -> void:
	derived_stats = StatSystem.derive(build, catalog)
	selected_special_slot = -1
	_cycle_special(1)
	projectile_layer.set_beam_builds({1: build}, catalog)
	player.set_shield_build(build, catalog)
	_reset_combatants()
	_update_card_label()
	lab_panel.refresh_build()


func set_target_settings(count_value: int, health_value: float, distance_value: float, shields_value: bool, firing_value: bool, moving_value: bool) -> void:
	target_count = clampi(count_value, 1, TARGET_COUNT)
	target_health = clampf(health_value, 10.0, 600.0)
	target_distance = clampf(distance_value, 160.0, 900.0)
	targets_shielding = shields_value
	targets_firing = firing_value
	targets_moving = moving_value
	lab_panel.sync_target_controls()
	_reset_combatants()


func set_lab_map(index: int) -> void:
	if index < 0 or index >= LAB_MAP_IDS.size():
		return
	world.set_map_id(LAB_MAP_IDS[index])
	arena.set_map_id(world.map_id)
	_reset_combatants()


func _reset_combatants() -> void:
	action_latch.reset()
	world.clear_projectiles()
	# These clear firing lanes keep targets immediately useful on both lab maps.
	# Solar Tide starts close enough to reach the current in a few seconds.
	var origin := Vector2(950.0, 650.0) if world.map_id == &"solar_tide" else Vector2(500.0, 720.0)
	player.reset_ship(derived_stats, origin)
	camera.position = origin
	camera.offset = Vector2.ZERO
	camera_kick_remaining = 0.0
	camera.reset_smoothing()
	for index in targets.size():
		var stats := CombatStats.create_base()
		stats.max_health = target_health
		targets[index].reset_ship(stats, origin + Vector2(target_distance, index * 110.0))
		targets[index].combatant.aim_angle = PI
		targets[index].visible = index < target_count
		if index >= target_count:
			world.set_spectator(index + 2)
	for peer_id in ships_by_id:
		var ship := ships_by_id[peer_id] as CombatShipView
		ship.collision_layer = 0
		ship.collision_mask = 0
		world.latest_inputs[peer_id] = PlayerInputFrame.new(int(world.acknowledged_inputs.get(peer_id, 0)), world.server_tick)
	world.drain_kill_events()
	world.drain_combat_feedback()
	world.drain_mine_detonations()
	world.drain_projectile_batch()
	effects_layer.clear_effects()
	kill_feed.clear()
	kill_feed_event_sequence = 0
	heat_elapsed = 0.0
	overtime_debug_stage = 0
	overtime_enabled = false
	arena.set_overtime(false, OvertimeSystem.initial_radius())
	reset_measurements()
	_update_hud()


## Test/capture helper also delegates damage resolution to the authoritative world.
func _apply_damage_events(events: Array[Dictionary]) -> void:
	var before := _presentation_states()
	for peer_id in world._resolve_damage_events(events):
		projectile_registry.schedule_owner_cleanup(peer_id)
	_sync_presentation(before)
	_consume_feedback()
	_update_hud()


func _kill_feed_identities() -> Array[Dictionary]:
	var identities: Array[Dictionary] = []
	for peer_id in ships_by_id:
		var ship := ships_by_id[peer_id] as CombatShipView
		identities.append({"peer_id": peer_id, "display_name": ship.display_name, "ship_color": ship.ship_color.to_html(false)})
	return identities


func _update_camera(delta: float) -> void:
	var focus := player.global_position if player.combatant.alive else targets[0].global_position
	camera.position = camera.position.lerp(focus, 1.0 - exp(-8.0 * delta))
	if camera_kick_remaining > 0.0 and not bool(accessibility.get("reduced_shake", false)):
		var fraction := clampf(camera_kick_remaining / maxf(camera_kick_duration, 0.001), 0.0, 1.0)
		camera.offset = camera_kick_offset * fraction * fraction
		camera_kick_remaining = maxf(camera_kick_remaining - maxf(delta, 0.0), 0.0)
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))


func _trigger_afterburner_feedback(forward: Vector2) -> void:
	if bool(accessibility.get("reduced_shake", false)):
		return
	camera_kick_duration = 0.18
	camera_kick_remaining = camera_kick_duration
	camera_kick_offset = -forward.normalized() * 5.5


func _cycle_overtime_debug() -> void:
	overtime_debug_stage = (overtime_debug_stage + 1) % 4
	overtime_enabled = overtime_debug_stage > 0
	match overtime_debug_stage:
		0: heat_elapsed = 0.0
		1: heat_elapsed = GameConstants.OVERTIME_START_SECONDS - GameConstants.OVERTIME_WARNING_SECONDS
		2: heat_elapsed = GameConstants.OVERTIME_START_SECONDS
		3: heat_elapsed = GameConstants.OVERTIME_START_SECONDS + GameConstants.OVERTIME_SHRINK_SECONDS


func _toggle_overtime_debug() -> void:
	heat_elapsed = next_overtime_toggle_time(heat_elapsed if overtime_enabled else 0.0)
	overtime_debug_stage = 0 if heat_elapsed == 0.0 else 2
	overtime_enabled = overtime_debug_stage > 0


static func next_overtime_toggle_time(current_heat_elapsed: float) -> float:
	var warning_start := GameConstants.OVERTIME_START_SECONDS - GameConstants.OVERTIME_WARNING_SECONDS
	return 0.0 if current_heat_elapsed >= warning_start else GameConstants.OVERTIME_START_SECONDS
