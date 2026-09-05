extends RefCounted

const Preferences = preload("res://src/client/presentation/accessibility_preferences.gd")


static func run(context: TestContext, parent: Node) -> void:
	var preferences = Preferences.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	preferences.settings_path = "res://reports/accessibility-test-%d.cfg" % Time.get_ticks_usec()
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", 37)
	config.save(preferences.settings_path)
	preferences.set_values({"hud_scale": 8.0, "reduced_shake": true, "reduced_flashes": true, "constrain_hud": false})
	context.expect_approx(float(preferences.values.hud_scale), 1.5, "accessibility scale clamps unsafe settings")
	context.expect_equal(preferences.save_settings(), OK, "accessibility preferences save")
	var restored = Preferences.new()
	restored.settings_path = preferences.settings_path
	restored.load_settings()
	context.expect_equal(restored.values, preferences.values, "all accessibility preferences survive reload")
	config.load(preferences.settings_path)
	context.expect_equal(config.get_value("audio", "master_volume"), 37, "saving accessibility preserves unrelated settings")
	preferences.set_values({"hud_scale": NAN})
	context.expect_approx(float(preferences.values.hud_scale), 1.0, "nonfinite HUD scale falls back safely")
	for viewport in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(3440, 1440), Vector2(5120, 1440)]:
		var safe: Rect2 = Preferences.hud_safe_rect(viewport)
		context.expect_approx(safe.get_center().x, viewport.x * 0.5, "HUD safe area stays centered at %s" % viewport)
		context.expect_true(safe.size.x <= viewport.y * 16.0 / 9.0, "HUD safe area limits peripheral reading at %s" % viewport)
		context.expect_equal(Preferences.hud_safe_rect(viewport, false).size, viewport, "HUD safe-area preference can restore full width at %s" % viewport)
	var scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := scene.instantiate()
	parent.add_child(client)
	client.settings_controller.accessibility_preferences.settings_path = preferences.settings_path
	var previous_scheme: int = client.input_profiles.active_scheme
	client.input_profiles.set_scheme(InputProfileManager.Scheme.KEYBOARD_MOUSE, false)
	client.settings_controller.accessibility_preferences.set_values(Preferences.DEFAULTS)
	client._apply_accessibility_settings()
	client.splash_screen.hide()
	client.studio_splash.hide()
	client._show_settings(false)
	client.settings_controller.settings_tabs.current_tab = 2
	client.settings_controller.hud_scale_control.value = 100.0
	client.settings_controller.reduced_shake_control.set_pressed_no_signal(false)
	client.settings_controller.reduced_flashes_control.set_pressed_no_signal(false)
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.settings_controller.hud_scale_control, "opening accessibility gives focus to HUD size")
	_press_key(client.get_viewport(), KEY_TAB)
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.settings_controller.reduced_shake_control, "real Tab input reaches shake control")
	_press_key(client.get_viewport(), KEY_TAB, true)
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.settings_controller.hud_scale_control, "real Shift+Tab returns to size control")
	client.input_profiles.set_scheme(InputProfileManager.Scheme.CONTROLLER, false)
	client.settings_controller.settings_tabs.get_tab_bar().grab_focus()
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.settings_controller.settings_tabs.get_tab_bar(), "settings tab selector takes keyboard/controller focus")
	_press_pad(client.get_viewport(), JOY_BUTTON_DPAD_LEFT)
	context.expect_equal(client.settings_controller.settings_tabs.current_tab, 1, "controller can move from accessibility to controls tab")
	_press_pad(client.get_viewport(), JOY_BUTTON_DPAD_RIGHT)
	context.expect_equal(client.settings_controller.settings_tabs.current_tab, 2, "controller can return to accessibility tab without focus being stolen")
	_press_pad(client.get_viewport(), JOY_BUTTON_DPAD_DOWN)
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.settings_controller.hud_scale_control, "controller can enter selected tab's first control")
	_press_pad(client.get_viewport(), JOY_BUTTON_DPAD_RIGHT)
	context.expect_approx(client.settings_controller.hud_scale_control.value, 110.0, "controller D-pad adjusts focused HUD size")
	context.expect_approx(float(client.network_world.accessibility_settings.hud_scale), 1.1, "controller size adjustment reaches online HUD immediately")
	_press_key(client.get_viewport(), KEY_TAB)
	_press_pad(client.get_viewport(), JOY_BUTTON_A)
	context.expect_true(client.settings_controller.reduced_shake_control.button_pressed, "controller confirm toggles focused shake setting")
	client.network_world.trigger_camera_shake(9.0, 0.3)
	client.network_world.trigger_afterburner_feedback(Vector2.RIGHT)
	context.expect_approx(client.network_world.camera_shake_remaining, 0.0, "disabled shake cannot start from combat feedback")
	context.expect_approx(client.network_world.camera_kick_remaining, 0.0, "disabled shake also suppresses boost kick")
	_press_pad(client.get_viewport(), JOY_BUTTON_DPAD_DOWN)
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.settings_controller.reduced_flashes_control, "controller D-pad traverses accessibility settings")
	_press_pad(client.get_viewport(), JOY_BUTTON_A)
	context.expect_true(client.network_world.effects_layer.reduced_flashes, "controller flash preference reaches combat effects")
	var ship: CombatShipView = client.network_world._ensure_ship(1, {"position": Vector2.ZERO})
	context.expect_true(ship.reduced_flashes, "ships joining after setting changes inherit reduced flashes")
	client.settings_controller._change_accessibility_setting("reduced_flashes", false)
	context.expect_false(ship.reduced_flashes, "preference changes reach ships already on screen")
	client.network_world.effects_layer.spawn_damage(Vector2.ZERO, Vector2.RIGHT)
	context.expect_equal(client.network_world.effects_layer.effects.size(), 1, "reduced flashes retains damage location cue")
	client.network_world.effects_layer.clear_effects()
	client.settings_controller._change_accessibility_setting("hud_scale", 1.5)
	context.expect_equal(client.network_world.hud_root.scale, Vector2(1.5, 1.5), "combat HUD text and bars scale together")
	context.expect_true(client.network_world.hud_panel.size.x + 16.0 + 420.0 + 24.0 < client.network_world.hud_root.size.x, "largest HUD leaves room for kill feed")
	_press_pad(client.get_viewport(), JOY_BUTTON_B)
	context.expect_false(client.settings_controller.settings_panel.visible, "controller cancel exits accessibility settings")
	client.connection_controller.connection_tabs.current_tab = 0
	client.connection_controller.connection_tabs.get_tab_bar().grab_focus()
	_press_pad(client.get_viewport(), JOY_BUTTON_DPAD_RIGHT)
	context.expect_equal(client.connection_controller.connection_tabs.current_tab, 1, "controller can select direct connection from the LAN tab")
	_press_pad(client.get_viewport(), JOY_BUTTON_DPAD_RIGHT)
	context.expect_equal(client.connection_controller.connection_tabs.current_tab, 2, "controller can select hosting from the direct connection tab")
	client.input_profiles.set_scheme(InputProfileManager.Scheme.KEYBOARD_MOUSE, false)
	client._play_offline()
	client.offline_sandbox.set_editor_open(true)
	client.offline_sandbox.lab_panel.search.grab_focus()
	_press_key(client.get_viewport(), KEY_F2)
	context.expect_false(client.offline_sandbox.editor_open, "production F2 leaves the focused lab editor and enters flight")
	context.expect_false(client.f2_return_confirmation.visible, "lab handles F2 before parent return-menu confirmation")
	context.expect_true(client.offline_sandbox.visible and not client.connection_controller.connection_screen.visible, "lab flight remains in the current offline session")
	_press_key(client.get_viewport(), KEY_F2)
	context.expect_true(client.offline_sandbox.editor_open, "production F2 returns from flight to the lab editor")
	context.expect_false(client.f2_return_confirmation.visible, "returning to editor does not trigger parent menu action")
	client.input_profiles.set_scheme(previous_scheme, false)
	client.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences.settings_path))


static func _press_key(viewport: Viewport, code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	viewport.push_input(event)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event)


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
