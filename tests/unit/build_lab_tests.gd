extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	var lab := OfflineSandbox.new()
	parent.add_child(lab)
	lab.set_physics_process(false)
	context.expect_true(lab.player.combatant == lab.world.combatants[1], "lab ship renders the authoritative combatant directly")
	context.expect_true(lab.projectile_registry == lab.world.projectile_registry, "lab renders the authoritative projectile registry")
	context.expect_true(lab.editor_open, "lab opens paused with its build editor accessible")
	context.expect_true(lab.lab_panel.matching_card_ids(" MISSILE ").has(&"hunter_missiles"), "lab card search matches trimmed case-insensitive descriptions")
	context.expect_empty(lab.lab_panel.matching_card_ids("no such card 9487"), "lab search represents no matches")
	lab.lab_panel._refresh_cards("no such card 9487")
	context.expect_true(lab.lab_panel.add_button.disabled, "no-match search cannot grant an unrelated hidden card")
	lab.lab_panel._refresh_cards("")
	for index in lab.PRESET_BUILDS.size():
		for card_id in lab.PRESET_BUILDS[index]:
			context.expect_true(lab.catalog.get_card(card_id) != null, "lab preset %s references a real card %s" % [lab.PRESET_NAMES[index], card_id])
		lab.load_preset(index)
		var expected := StatSystem.derive(lab.build, lab.catalog)
		context.expect_approx(lab.player.combatant.stats.projectile_damage, expected.projectile_damage, "lab preset derives authoritative damage")
		context.expect_equal(lab.player.combatant.weapon.ammunition, expected.magazine_size, "changing a build resets its magazine to the derived capacity")
	context.expect_true(lab.derived_stats.afterburner_enabled and lab.derived_stats.mine_layer_enabled and lab.derived_stats.missile_launcher_enabled and lab.derived_stats.cloak_enabled, "ability preset enables all four independent abilities")
	lab.selected_card_index = lab.catalog.all_ids().find(&"hunter_missiles")
	lab.remove_selected_card()
	context.expect_false(lab.player.combatant.stats.missile_launcher_enabled, "removing the final ability card removes the capability")
	context.expect_equal(lab.player.combatant.missile_charges_remaining, 0, "removing the final ability card clears its inventory")
	lab.load_preset(0)
	context.expect_empty(lab.build, "base preset clears the build")
	lab.set_target_settings(3, 200.0, 500.0, true, false, true)
	context.expect_equal(lab.target_count, 3, "lab target control selects active population")
	context.expect_equal(roundi(lab.lab_panel.count_control.value), 3, "programmatic target setup stays synchronized with visible controls")
	context.expect_approx(lab.targets[0].combatant.health, 200.0, "lab target HP uses actual combatant health")
	context.expect_false(lab.targets[3].combatant.alive, "inactive lab targets cannot collide or take damage")
	context.expect_true(lab.targets_shielding and lab.targets_moving, "lab shield and movement controls update target behavior")
	for distance in [160.0, 420.0, 900.0]:
		lab.set_target_settings(5, 100.0, distance, false, false, false)
		for target in lab.targets:
			context.expect_true(ArenaCollisionSystem.is_ship_position_clear(target.combatant.position, lab.world.map_id), "lab target placement stays clear of map geometry at range %.0f" % distance)
	lab.set_target_settings(1, 100.0, 160.0, false, false, false)
	for tick in 24:
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(tick + 1, tick, Vector2.ZERO, 0.0, tick == 0))
	context.expect_equal(lab.shots_fired, 1, "lab shot counter records authoritative trigger shots")
	context.expect_equal(lab.hull_hits, 1, "lab hull-hit counter records authoritative collisions")
	context.expect_approx(lab.measured_damage, 25.0, "lab damage counter reflects actual target HP removed")
	context.expect_approx(lab.targets[0].combatant.health, 75.0, "lab damage matches multiplayer projectile damage")
	context.expect_approx(lab.measured_dps(), 62.5, "lab measured DPS includes active flight time after the first shot", 0.01)
	var time_before := lab.measurement_seconds
	lab.set_editor_open(true)
	lab._physics_process(1.0)
	context.expect_approx(lab.measurement_seconds, time_before, "paused editor does not dilute measured DPS")
	lab._reset_combatants()
	context.expect_approx(lab.measured_damage, 0.0, "encounter reset clears measurement counters")
	context.expect_equal(lab.projectile_registry.size(), 0, "encounter reset clears authoritative projectiles")
	context.expect_approx(lab.player.combatant.health, lab.derived_stats.max_health, "encounter reset revives and refills player")
	lab.set_target_settings(1, 10.0, 160.0, false, false, false)
	lab._apply_damage_events([{"projectile_id": 999, "attacker_id": 1, "target_id": 2, "damage": 500.0}])
	context.expect_approx(lab.measured_damage, 10.0, "lab damage readout caps overkill at actual remaining HP")
	context.expect_equal(lab.kill_feed.entries.size(), 1, "lab authoritative elimination populates shared kill feed")
	lab.set_target_settings(1, 100.0, 160.0, true, false, false)
	for tick in 24:
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(100 + tick, tick, Vector2.ZERO, 0.0, tick == 0))
	context.expect_equal(lab.blocked_shots, 1, "lab differentiates authoritative shield blocks from hull hits")
	context.expect_equal(lab.hull_hits, 0, "shielded lab hit does not count as a hull hit")
	context.expect_approx(lab.measured_damage, 0.0, "shielded lab hit does not report hull damage")
	context.expect_false(lab.overtime_enabled, "lab remains untimed unless overtime is explicitly enabled")
	lab.heat_elapsed = 120.0
	lab._toggle_overtime_debug()
	context.expect_true(lab.overtime_enabled, "lab overtime control enables authoritative overtime even after a long untimed session")
	lab.apply_accessibility_settings({"hud_scale": 1.5, "reduced_shake": true, "reduced_flashes": true, "constrain_hud": true})
	lab._trigger_afterburner_feedback(Vector2.RIGHT)
	context.expect_approx(lab.camera_kick_remaining, 0.0, "lab reduced-shake preference suppresses boost camera kick")
	context.expect_approx(lab.hud_root.scale.x, 1.5, "lab HUD inherits readable text scaling")
	var profiles := InputProfileManager.new()
	parent.add_child(profiles)
	var previous_scheme: int = profiles.active_scheme
	profiles.set_scheme(InputProfileManager.Scheme.CONTROLLER, false)
	lab.set_input_profile_manager(profiles)
	lab.set_editor_open(true)
	context.expect_equal(lab.get_viewport().gui_get_focus_owner(), lab.editor_button, "controller editor entry focuses the play button")
	lab.lab_panel.count_control.get_line_edit().grab_focus()
	_press_pad(lab.get_viewport(), JOY_BUTTON_DPAD_RIGHT)
	context.expect_equal(lab.target_count, 2, "controller D-pad changes the focused target count")
	context.expect_approx(lab.targets[1].combatant.health, 100.0, "controller target edit immediately resets authoritative encounter")
	lab.set_editor_open(false)
	_press_pad(lab.get_viewport(), JOY_BUTTON_A)
	context.expect_true(lab.editor_open, "controller confirm opens the editor from active range")
	lab.load_preset(4)
	context.expect_equal(lab.lab_panel.preset_control.selected, 4, "preset selector reflects a programmatically loaded build")
	lab.set_editor_open(false)
	Input.action_press("fire")
	lab._physics_process(1.0 / 60.0)
	context.expect_equal(lab.shots_fired, 0, "held confirm/fire cannot click through the editor into a shot")
	Input.action_release("fire")
	profiles.set_scheme(previous_scheme, false)
	lab.free()
	profiles.free()


static func _press_pad(viewport: Viewport, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	event.pressure = 1.0
	viewport.push_input(event)
	event = event.duplicate()
	event.pressed = false
	event.pressure = 0.0
	viewport.push_input(event)
