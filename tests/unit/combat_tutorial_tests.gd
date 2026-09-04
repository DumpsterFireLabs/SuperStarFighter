extends RefCounted

const Tutorial = preload("res://src/client/sandbox/combat_tutorial.gd")


static func run(context: TestContext, parent: Node) -> void:
	await _practice_layout(context, parent)
	var lab := OfflineSandbox.new()
	parent.add_child(lab)
	lab.set_physics_process(false)
	lab.load_preset(1)
	lab.set_target_settings(3, 200.0, 420.0, true, true, true)
	var saved_build: Dictionary = lab.build.duplicate()
	lab.start_tutorial()
	context.expect_true(lab.tutorial.active and not lab.editor_open, "guided introduction opens a live exercise from the paused lab")
	context.expect_true(lab.tutorial.panel.visible and not lab.editor_button.visible, "tutorial exposes guidance without competing build editor")
	var sequence := 1000
	for index in 90:
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick))
	context.expect_equal(lab.tutorial.step, Tutorial.Step.MOVE, "elapsed time cannot complete movement lesson")
	for index in 180:
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.UP))
		if lab.tutorial.step != Tutorial.Step.MOVE:
			break
	context.expect_equal(lab.tutorial.step, Tutorial.Step.FIRE, "actual authoritative movement advances first lesson")
	for index in 90:
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.ZERO, PI, index == 0))
	context.expect_equal(lab.tutorial.step, Tutorial.Step.FIRE, "firing a missed shot does not complete aiming exercise")
	for index in 90:
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.ZERO, 0.0, index == 0))
		if lab.tutorial.step != Tutorial.Step.FIRE:
			break
	context.expect_equal(lab.tutorial.step, Tutorial.Step.RELOAD, "authoritative hull-hit confirmation advances aiming exercise")
	for index in 180:
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.ZERO, 0.0, false, false, index == 0))
		if lab.tutorial.step != Tutorial.Step.RELOAD:
			break
	context.expect_equal(lab.tutorial.step, Tutorial.Step.SHIELD, "manual reload must actually finish before lesson advances")
	for index in 360:
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.ZERO, 0.0, false, true))
		if lab.tutorial.step != Tutorial.Step.SHIELD:
			break
	context.expect_equal(lab.tutorial.step, Tutorial.Step.PERFECT_GUARD, "real incoming projectile and facing shield advance blocking lesson")
	for index in 240:
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.ZERO, 0.0, false, true))
	context.expect_equal(lab.tutorial.step, Tutorial.Step.PERFECT_GUARD, "holding shield early does not substitute for a Perfect Guard")
	lab.tutorial.retry_step()
	for index in 360:
		var shield_now := false
		for projectile in lab.projectile_registry.all_projectiles():
			if projectile.owner_id == 2 and projectile.position.distance_to(lab.player.combatant.position) < 65.0:
				shield_now = true
		sequence += 1
		lab.step_lab(1.0 / 60.0, PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.ZERO, 0.0, false, shield_now))
		if lab.tutorial.step != Tutorial.Step.PERFECT_GUARD:
			break
	context.expect_equal(lab.tutorial.step, Tutorial.Step.ABILITY, "real timed shield collision completes Perfect Guard lesson")
	context.expect_equal(lab.selected_special_slot, 1, "ability exercise starts on another owned ability to require selection")
	lab._cycle_special(-1)
	sequence += 1
	var frame := PlayerInputFrame.new(sequence, lab.world.server_tick, Vector2.ZERO, 0.0, false, false, false, true, 999, 0)
	lab.step_lab(1.0 / 60.0, frame)
	context.expect_equal(lab.tutorial.step, Tutorial.Step.DRAFT, "selecting and successfully activating Afterburner completes ability exercise")
	context.expect_true(lab.tutorial.blocks_simulation(), "draft lesson pauses combat while making a choice")
	var tick: int = lab.world.server_tick
	lab.step_lab(1.0, frame)
	context.expect_equal(lab.world.server_tick, tick, "paused tutorial draft cannot advance authoritative simulation")
	lab.tutorial.choose_card(&"cloak")
	context.expect_equal(lab.tutorial.step, Tutorial.Step.DRAFT, "only offered tutorial draft cards can be selected")
	var health: float = lab.derived_stats.max_health
	context.expect_equal(lab.get_viewport().gui_get_focus_owner(), lab.tutorial.choices.get_child(0), "draft opens with first offered card focused for controller navigation")
	lab.tutorial.choose_card(&"reinforced_hull")
	context.expect_equal(lab.tutorial.step, Tutorial.Step.COMPLETE, "one valid draft choice completes introduction")
	context.expect_true(lab.derived_stats.max_health > health, "tutorial draft actually derives and applies the chosen card")
	lab.apply_accessibility_settings({"hud_scale": 1.5})
	context.expect_true(lab.tutorial.panel.position.y + lab.tutorial.panel.size.y <= lab.hud_root.size.y + 1.0, "tutorial panel fits scaled HUD safe bounds")
	lab.start_tutorial()
	context.expect_equal(lab.tutorial.step, Tutorial.Step.MOVE, "restart returns to first action with fresh exercise")
	lab.stop_tutorial()
	context.expect_equal(lab.build, saved_build, "skip or completion restores preexisting lab build after restarts")
	context.expect_equal(lab.target_count, 3, "return restores configured target count")
	context.expect_true(lab.targets_shielding and lab.targets_firing and lab.targets_moving, "return restores target behavior")
	context.expect_true(lab.editor_open and not lab.tutorial.active, "return opens normal paused free-play editor")
	lab.free()
	var scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := scene.instantiate()
	parent.add_child(client)
	client.splash_screen.hide()
	client.studio_splash.hide()
	var entry := client.find_child("GuidedIntroductionButton", true, false) as Button
	context.expect_true(entry != null and entry.text == "Learn to play", "main menu exposes an explicit guided introduction entry")
	if entry != null:
		entry.pressed.emit()
		context.expect_true(client.offline_sandbox.visible and client.offline_sandbox.tutorial.active, "main-menu lesson entry starts playable tutorial")
		context.expect_equal(client.offline_sandbox.tutorial.step, Tutorial.Step.MOVE, "main-menu lesson begins with movement immediately")
		var previous_scheme: int = client.input_profiles.active_scheme
		client.input_profiles.set_scheme(InputProfileManager.Scheme.CONTROLLER, false)
		client.offline_sandbox.tutorial._enter_step(Tutorial.Step.DRAFT)
		_press_pad(client.get_viewport(), JOY_BUTTON_A)
		context.expect_equal(client.offline_sandbox.tutorial.step, Tutorial.Step.COMPLETE, "production controller confirm picks focused draft upgrade")
		_press_pad(client.get_viewport(), JOY_BUTTON_A)
		context.expect_false(client.offline_sandbox.tutorial.active, "production controller confirm returns from completion to lab")
		client.input_profiles.set_scheme(previous_scheme, false)
		client._play_tutorial()
		client.offline_sandbox.set_sandbox_active(false)
		context.expect_false(client.offline_sandbox.tutorial.active, "leaving the lab closes tutorial state")
		client._play_offline()
		context.expect_true(client.offline_sandbox.editor_open and not client.offline_sandbox.tutorial.active, "ordinary Combat Lab entry after a lesson preserves free play")
	client.free()


static func _practice_layout(context: TestContext, parent: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	parent.add_child(viewport)
	var lab := OfflineSandbox.new()
	viewport.add_child(lab)
	lab.set_physics_process(false)
	lab.start_tutorial()
	lab.tutorial._enter_step(Tutorial.Step.PERFECT_GUARD)
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(2880, 1920), Vector2i(3440, 1440), Vector2i(5120, 1440)]:
		viewport.size = resolution
		for hud_scale in [1.0, 1.25, 1.5]:
			lab.apply_accessibility_settings({"hud_scale": hud_scale, "constrain_hud": true})
			await parent.get_tree().process_frame
			await parent.get_tree().process_frame
			lab.tutorial.layout()
			var lane: Rect2 = lab.tutorial.practice_screen_rect()
			var player_screen := lab.player.get_global_transform_with_canvas().origin
			var target_screen := (lab.targets[0] as CombatShipView).get_global_transform_with_canvas().origin
			var firing_path := Rect2(player_screen, Vector2.ZERO).expand(target_screen).grow(48.0 * lab.camera.zoom.x)
			var label := "%s at %.0f%%" % [resolution, hud_scale * 100.0]
			context.expect_true(lane.encloses(firing_path), "player, target and full firing path remain in practice lane: " + label)
			context.expect_false(lab.tutorial.panel.get_global_rect().intersects(firing_path), "instructions never obstruct incoming fire: " + label)
			context.expect_true(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(lab.tutorial.exit_button.get_global_rect()), "tutorial exit remains on screen: " + label)
	lab.stop_tutorial()
	context.expect_equal(lab.camera.zoom, Vector2.ONE, "leaving tutorial restores free-play camera zoom")
	context.expect_equal(lab.camera.limit_right, int(GameConstants.ARENA_SIZE.x), "leaving tutorial restores arena camera limits")
	viewport.free()


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
