class_name InputProfileTests
extends RefCounted

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")


static func run(context: TestContext) -> void:
	var settings_path := "res://.tools/ssf_input_profile_test.cfg"
	var absolute_path := ProjectSettings.globalize_path(settings_path)
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(absolute_path)
	var manager := InputProfileManagerScript.new()
	manager.settings_path = settings_path
	manager.load_settings()
	context.expect_equal(manager.active_scheme, InputProfileManagerScript.Scheme.KEYBOARD_MOUSE, "keyboard and mouse is the default control profile")
	context.expect_equal(manager.binding_text(&"move_up"), "W", "default keyboard profile flies forward with W")
	context.expect_equal(manager.binding_text(&"fire"), "Left Mouse", "default keyboard profile fires with the left mouse button")
	context.expect_equal(manager.binding_text(&"manual_reload"), "R", "keyboard profile reserves R for manual reload")
	context.expect_equal(manager.binding_text(&"special"), "Shift", "keyboard profile reserves Shift for special cards")
	context.expect_equal(manager.binding_text(&"global_pause"), "F10", "host global pause defaults to F10")
	var pause_key := InputEventKey.new()
	pause_key.physical_keycode = KEY_F9
	pause_key.pressed = true
	context.expect_true(manager.rebind(&"global_pause", pause_key, false), "host global pause can be rebound")
	context.expect_equal(manager.flight_mode, InputProfileManagerScript.FlightMode.RELATIVE, "Relative screen-aligned flight is the default")
	var idle_input := manager.movement_input_for_aim(PI * 0.5)
	context.expect_equal(idle_input, Vector2.ZERO, "idle Relative flight produces no movement input")
	context.expect_true(&"ui_accept" in manager.rebind_actions(), "keyboard profile exposes menu confirmation for rebinding")
	Input.action_press(&"move_up")
	var screen_relative_input := manager.movement_input_for_aim(PI * 0.5)
	context.expect_true(screen_relative_input.y > 0.99 and absf(screen_relative_input.x) < 0.01, "Relative flight converts screen-up into the correct ship-local input")
	context.expect_true(manager.world_movement_for_aim(PI * 0.5).dot(Vector2.UP) > 0.99, "Relative flight keeps W vertically upward on screen")
	Input.action_release(&"move_up")
	manager.set_flight_mode(InputProfileManagerScript.FlightMode.NEWTONIAN, false)
	manager.set_scheme(InputProfileManagerScript.Scheme.CONTROLLER, false)
	context.expect_true(manager.uses_controller(), "controller profile can be selected explicitly")
	context.expect_equal(manager.binding_text(&"global_pause"), "Unbound", "controller pause does not steal a gameplay button")
	context.expect_true(&"global_pause" in manager.rebind_actions(), "controller hosts can assign a global pause shortcut")
	context.expect_equal(manager.binding_text(&"move_left"), "Left Stick X −", "controller profile supplies analog left-stick movement")
	context.expect_equal(manager.binding_text(&"aim_right"), "Right Stick X +", "controller profile supplies independent right-stick aiming")
	context.expect_equal(manager.binding_text(&"fire"), "Right Trigger +", "controller profile fires with the right trigger")
	context.expect_equal(manager.binding_text(&"manual_reload"), "X / Square", "controller profile provides a default manual reload button")
	context.expect_equal(manager.binding_text(&"special"), "Left Stick Click", "controller profile provides a default special-card button")
	context.expect_true(&"ui_cancel" in manager.rebind_actions(), "controller profile exposes menu back for rebinding")
	context.expect_approx(InputMap.action_get_deadzone(&"aim_right"), InputProfileManagerScript.DEFAULT_CONTROLLER_DEADZONE, "controller deadzone is applied to runtime actions", 0.0001)
	Input.action_press(&"aim_right", 0.85)
	Input.action_press(&"aim_up", 0.45)
	var analog_aim: Vector2 = manager.aim_vector()
	context.expect_true(analog_aim.x > 0.0 and analog_aim.y < 0.0 and analog_aim.length() <= 1.0001, "controller aim reads a normalized analog direction")
	Input.action_release(&"aim_right")
	Input.action_release(&"aim_up")
	var remapped_fire := InputEventJoypadButton.new()
	remapped_fire.button_index = JOY_BUTTON_X
	remapped_fire.pressed = true
	context.expect_true(manager.rebind(&"fire", remapped_fire, false), "controller buttons can be remapped")
	context.expect_equal(manager.binding_text(&"fire"), "X / Square", "remapped controller button receives a readable prompt")
	var runtime_fire_events := InputMap.action_get_events(&"fire")
	context.expect_equal(runtime_fire_events.size(), 1, "active binding replaces the prior runtime event")
	context.expect_true(runtime_fire_events[0] is InputEventJoypadButton and runtime_fire_events[0].button_index == JOY_BUTTON_X, "runtime input map consumes the remapped controller button")
	var arbitrary_axis := InputEventJoypadMotion.new()
	arbitrary_axis.axis = JOY_AXIS_RIGHT_Y
	arbitrary_axis.axis_value = -0.9
	context.expect_true(manager.rebind(&"move_up", arbitrary_axis, false), "joystick axes can be remapped by direction")
	context.expect_equal(manager.binding_text(&"move_up"), "Right Stick Y −", "remapped joystick axis retains its direction")
	manager.set_controller_deadzone(0.31, false)
	context.expect_approx(InputMap.action_get_deadzone(&"move_up"), 0.31, "custom controller deadzone updates the runtime input map", 0.0001)
	context.expect_equal(manager.save_settings(), OK, "control profile saves successfully")
	var restored := InputProfileManagerScript.new()
	restored.settings_path = settings_path
	restored.load_settings()
	context.expect_true(restored.uses_controller(), "selected control profile persists between launches")
	context.expect_equal(restored.flight_mode, InputProfileManagerScript.FlightMode.NEWTONIAN, "an explicit Newtonian flight mode persists between launches")
	context.expect_approx(restored.controller_deadzone, 0.31, "controller deadzone persists between launches", 0.0001)
	context.expect_equal(restored.binding_text(&"fire"), "X / Square", "controller button remap persists between launches")
	context.expect_equal(restored.binding_text(&"move_up"), "Right Stick Y −", "joystick axis remap persists between launches")
	restored.set_scheme(InputProfileManagerScript.Scheme.KEYBOARD_MOUSE, false)
	context.expect_equal(restored.binding_text(&"global_pause"), "F9", "global pause remap survives save, reload and profile switching")
	context.expect_equal(restored.binding_text(&"fire"), "Left Mouse", "switching profiles restores the separately saved keyboard binding")
	var rejected_controller_button := InputEventJoypadButton.new()
	rejected_controller_button.button_index = JOY_BUTTON_A
	rejected_controller_button.pressed = true
	context.expect_false(restored.rebind(&"fire", rejected_controller_button, false), "keyboard profile rejects controller-only binding events")
	restored.restore_active_defaults(false)
	context.expect_equal(restored.binding_text(&"global_pause"), "F10", "restoring defaults restores the F10 host shortcut")
	context.expect_equal(restored.binding_text(&"pause_overlay"), "Escape", "profile defaults can be restored without affecting the other profile")
	manager.free()
	restored.free()
	DirAccess.remove_absolute(absolute_path)
	var runtime_defaults := InputProfileManagerScript.new()
	runtime_defaults.apply_active_bindings()
	runtime_defaults.free()
