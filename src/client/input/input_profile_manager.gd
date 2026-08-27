class_name InputProfileManager
extends Node

signal scheme_changed(scheme: Scheme)
signal flight_mode_changed(flight_mode: FlightMode)
signal bindings_changed()
signal controller_connections_changed()

enum Scheme {
	KEYBOARD_MOUSE,
	CONTROLLER,
}

enum FlightMode {
	NEWTONIAN,
	RELATIVE,
}

const SETTINGS_PATH: String = "user://super_star_fighter_settings.cfg"
const SETTINGS_SECTION: String = "input"
const KEYBOARD_SECTION: String = "input_keyboard_mouse"
const CONTROLLER_SECTION: String = "input_controller"
const DEFAULT_CONTROLLER_DEADZONE: float = 0.22
const MIN_CONTROLLER_DEADZONE: float = 0.05
const MAX_CONTROLLER_DEADZONE: float = 0.75
const FLIGHT_MODE_NAMES: Array[String] = ["Newtonian", "Relative"]

const MOVEMENT_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
]
const AIM_ACTIONS: Array[StringName] = [
	&"aim_up", &"aim_down", &"aim_left", &"aim_right",
]
const COMBAT_ACTIONS: Array[StringName] = [
	&"fire", &"shield", &"manual_reload", &"scoreboard", &"pause_overlay", &"diagnostics",
	&"spectator_previous", &"spectator_next",
]
const DRAFT_ACTIONS: Array[StringName] = [
	&"draft_1", &"draft_2", &"draft_3", &"draft_4", &"draft_5",
]
const MENU_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel",
]
const KEYBOARD_REBIND_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"fire", &"shield", &"manual_reload", &"scoreboard", &"pause_overlay", &"diagnostics",
	&"spectator_previous", &"spectator_next",
	&"draft_1", &"draft_2", &"draft_3", &"draft_4", &"draft_5",
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel",
]
const CONTROLLER_REBIND_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"aim_up", &"aim_down", &"aim_left", &"aim_right",
	&"fire", &"shield", &"manual_reload", &"scoreboard", &"pause_overlay", &"diagnostics",
	&"spectator_previous", &"spectator_next",
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel",
]
const ACTION_LABELS: Dictionary = {
	&"move_up": "Move Forward",
	&"move_down": "Move Backward",
	&"move_left": "Strafe Left",
	&"move_right": "Strafe Right",
	&"aim_up": "Aim Up",
	&"aim_down": "Aim Down",
	&"aim_left": "Aim Left",
	&"aim_right": "Aim Right",
	&"fire": "Fire",
	&"shield": "Shield",
	&"manual_reload": "Manual Reload",
	&"scoreboard": "Hold Scoreboard",
	&"pause_overlay": "Pilot Menu",
	&"diagnostics": "Diagnostics",
	&"spectator_previous": "Previous Spectator Target",
	&"spectator_next": "Next Spectator Target",
	&"draft_1": "Draft Card 1",
	&"draft_2": "Draft Card 2",
	&"draft_3": "Draft Card 3",
	&"draft_4": "Draft Card 4",
	&"draft_5": "Draft Card 5",
	&"ui_up": "Menu Up",
	&"ui_down": "Menu Down",
	&"ui_left": "Menu Left",
	&"ui_right": "Menu Right",
	&"ui_accept": "Menu Confirm",
	&"ui_cancel": "Menu Back",
}

var active_scheme: Scheme = Scheme.KEYBOARD_MOUSE
var flight_mode: FlightMode = FlightMode.NEWTONIAN
var controller_deadzone: float = DEFAULT_CONTROLLER_DEADZONE
var settings_path: String = SETTINGS_PATH
var keyboard_bindings: Dictionary = {}
var controller_bindings: Dictionary = {}


func _init() -> void:
	keyboard_bindings = _default_keyboard_bindings()
	controller_bindings = _default_controller_bindings()


func _ready() -> void:
	load_settings()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


func load_settings() -> void:
	keyboard_bindings = _default_keyboard_bindings()
	controller_bindings = _default_controller_bindings()
	active_scheme = Scheme.KEYBOARD_MOUSE
	flight_mode = FlightMode.NEWTONIAN
	controller_deadzone = DEFAULT_CONTROLLER_DEADZONE
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		active_scheme = _validated_scheme(int(config.get_value(SETTINGS_SECTION, "scheme", Scheme.KEYBOARD_MOUSE)))
		flight_mode = _validated_flight_mode(int(config.get_value(SETTINGS_SECTION, "flight_mode", FlightMode.NEWTONIAN)))
		controller_deadzone = clampf(
			float(config.get_value(SETTINGS_SECTION, "controller_deadzone", DEFAULT_CONTROLLER_DEADZONE)),
			MIN_CONTROLLER_DEADZONE,
			MAX_CONTROLLER_DEADZONE
		)
		_load_profile(config, KEYBOARD_SECTION, keyboard_bindings, KEYBOARD_REBIND_ACTIONS, Scheme.KEYBOARD_MOUSE)
		_load_profile(config, CONTROLLER_SECTION, controller_bindings, CONTROLLER_REBIND_ACTIONS, Scheme.CONTROLLER)
	apply_active_bindings()


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(SETTINGS_SECTION, "scheme", int(active_scheme))
	config.set_value(SETTINGS_SECTION, "flight_mode", int(flight_mode))
	config.set_value(SETTINGS_SECTION, "controller_deadzone", controller_deadzone)
	_save_profile(config, KEYBOARD_SECTION, keyboard_bindings, KEYBOARD_REBIND_ACTIONS)
	_save_profile(config, CONTROLLER_SECTION, controller_bindings, CONTROLLER_REBIND_ACTIONS)
	return config.save(settings_path)


func set_scheme(scheme: Scheme, save: bool = true) -> void:
	var validated := _validated_scheme(int(scheme))
	if active_scheme == validated:
		apply_active_bindings()
		return
	active_scheme = validated
	apply_active_bindings()
	if save:
		save_settings()
	scheme_changed.emit(active_scheme)


func set_controller_deadzone(value: float, save: bool = true) -> void:
	controller_deadzone = clampf(value, MIN_CONTROLLER_DEADZONE, MAX_CONTROLLER_DEADZONE)
	if active_scheme == Scheme.CONTROLLER:
		apply_active_bindings()
	if save:
		save_settings()


func set_flight_mode(value: FlightMode, save: bool = true) -> void:
	var validated := _validated_flight_mode(int(value))
	if flight_mode == validated:
		return
	flight_mode = validated
	if save:
		save_settings()
	flight_mode_changed.emit(flight_mode)


func restore_active_defaults(save: bool = true) -> void:
	if active_scheme == Scheme.CONTROLLER:
		controller_bindings = _default_controller_bindings()
		controller_deadzone = DEFAULT_CONTROLLER_DEADZONE
	else:
		keyboard_bindings = _default_keyboard_bindings()
	apply_active_bindings()
	if save:
		save_settings()
	bindings_changed.emit()


func rebind(action: StringName, event: InputEvent, save: bool = true) -> bool:
	if action not in rebind_actions():
		return false
	var serialized := _serialize_binding(event, active_scheme)
	if serialized.is_empty():
		return false
	if active_scheme == Scheme.CONTROLLER:
		controller_bindings[action] = serialized
	else:
		keyboard_bindings[action] = serialized
	apply_active_bindings()
	if save:
		save_settings()
	bindings_changed.emit()
	return true


func apply_active_bindings() -> void:
	var bindings := controller_bindings if active_scheme == Scheme.CONTROLLER else keyboard_bindings
	for action in managed_actions():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var analog_action := action in MOVEMENT_ACTIONS or action in AIM_ACTIONS
		InputMap.action_set_deadzone(action, controller_deadzone if active_scheme == Scheme.CONTROLLER and analog_action else 0.5)
		if bindings.has(action):
			var event := _deserialize_binding(bindings[action] as Dictionary)
			if event != null:
				InputMap.action_add_event(action, event)


func movement_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


func movement_input_for_aim(aim_angle: float) -> Vector2:
	var movement := movement_vector()
	return MovementSystem.world_to_ship_relative(movement, aim_angle) if flight_mode == FlightMode.RELATIVE else movement


func world_movement_for_aim(aim_angle: float) -> Vector2:
	var movement := movement_vector()
	return movement if flight_mode == FlightMode.RELATIVE else MovementSystem.ship_relative_to_world(movement, aim_angle)


func aim_vector() -> Vector2:
	if active_scheme != Scheme.CONTROLLER:
		return Vector2.ZERO
	return Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")


func uses_controller() -> bool:
	return active_scheme == Scheme.CONTROLLER


func rebind_actions() -> Array[StringName]:
	return CONTROLLER_REBIND_ACTIONS if active_scheme == Scheme.CONTROLLER else KEYBOARD_REBIND_ACTIONS


func binding_text(action: StringName) -> String:
	var bindings := controller_bindings if active_scheme == Scheme.CONTROLLER else keyboard_bindings
	if not bindings.has(action):
		return "Unbound"
	var event := _deserialize_binding(bindings[action] as Dictionary)
	return _event_display_text(event) if event != null else "Unbound"


func action_label(action: StringName) -> String:
	if flight_mode == FlightMode.RELATIVE:
		match action:
			&"move_up": return "Move Up"
			&"move_down": return "Move Down"
			&"move_left": return "Move Left"
			&"move_right": return "Move Right"
	return String(ACTION_LABELS.get(action, String(action).capitalize()))


func flight_mode_name() -> String:
	return FLIGHT_MODE_NAMES[int(flight_mode)]


func accepts_rebind_event(event: InputEvent) -> bool:
	if active_scheme == Scheme.CONTROLLER:
		return (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65)
	return (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)


func controller_status_text() -> String:
	var connected := Input.get_connected_joypads()
	if connected.is_empty():
		return "No controller detected · bindings can still be configured"
	var names: Array[String] = []
	for device_id in connected:
		var device_name := Input.get_joy_name(device_id)
		names.append(device_name if not device_name.is_empty() else "Controller %d" % (int(device_id) + 1))
	return "Detected: %s" % ", ".join(names)


static func managed_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for group in [MOVEMENT_ACTIONS, AIM_ACTIONS, COMBAT_ACTIONS, DRAFT_ACTIONS, MENU_ACTIONS]:
		for action in group:
			if action not in actions:
				actions.append(action)
	return actions


func _load_profile(
	config: ConfigFile,
	section: String,
	bindings: Dictionary,
	actions: Array[StringName],
	scheme: Scheme
) -> void:
	for action in actions:
		if not config.has_section_key(section, String(action)):
			continue
		var candidate: Variant = config.get_value(section, String(action), {})
		if candidate is not Dictionary:
			continue
		var event := _deserialize_binding(candidate as Dictionary)
		if event != null and not _serialize_binding(event, scheme).is_empty():
			bindings[action] = candidate


func _save_profile(config: ConfigFile, section: String, bindings: Dictionary, actions: Array[StringName]) -> void:
	for action in actions:
		if bindings.has(action):
			config.set_value(section, String(action), bindings[action])


func _default_keyboard_bindings() -> Dictionary:
	return {
		&"move_up": _key_binding(KEY_W),
		&"move_down": _key_binding(KEY_S),
		&"move_left": _key_binding(KEY_A),
		&"move_right": _key_binding(KEY_D),
		&"fire": _mouse_binding(MOUSE_BUTTON_LEFT),
		&"shield": _mouse_binding(MOUSE_BUTTON_RIGHT),
		&"manual_reload": _key_binding(KEY_R),
		&"scoreboard": _key_binding(KEY_TAB),
		&"pause_overlay": _key_binding(KEY_ESCAPE),
		&"diagnostics": _key_binding(KEY_F3),
		&"spectator_previous": _key_binding(KEY_A),
		&"spectator_next": _key_binding(KEY_D),
		&"draft_1": _key_binding(KEY_1),
		&"draft_2": _key_binding(KEY_2),
		&"draft_3": _key_binding(KEY_3),
		&"draft_4": _key_binding(KEY_4),
		&"draft_5": _key_binding(KEY_5),
		&"ui_up": _key_binding(KEY_UP),
		&"ui_down": _key_binding(KEY_DOWN),
		&"ui_left": _key_binding(KEY_LEFT),
		&"ui_right": _key_binding(KEY_RIGHT),
		&"ui_accept": _key_binding(KEY_ENTER),
		&"ui_cancel": _key_binding(KEY_ESCAPE),
	}


func _default_controller_bindings() -> Dictionary:
	return {
		&"move_up": _axis_binding(JOY_AXIS_LEFT_Y, -1.0),
		&"move_down": _axis_binding(JOY_AXIS_LEFT_Y, 1.0),
		&"move_left": _axis_binding(JOY_AXIS_LEFT_X, -1.0),
		&"move_right": _axis_binding(JOY_AXIS_LEFT_X, 1.0),
		&"aim_up": _axis_binding(JOY_AXIS_RIGHT_Y, -1.0),
		&"aim_down": _axis_binding(JOY_AXIS_RIGHT_Y, 1.0),
		&"aim_left": _axis_binding(JOY_AXIS_RIGHT_X, -1.0),
		&"aim_right": _axis_binding(JOY_AXIS_RIGHT_X, 1.0),
		&"fire": _axis_binding(JOY_AXIS_TRIGGER_RIGHT, 1.0),
		&"shield": _axis_binding(JOY_AXIS_TRIGGER_LEFT, 1.0),
		&"manual_reload": _button_binding(JOY_BUTTON_X),
		&"scoreboard": _button_binding(JOY_BUTTON_BACK),
		&"pause_overlay": _button_binding(JOY_BUTTON_START),
		&"diagnostics": _button_binding(JOY_BUTTON_Y),
		&"spectator_previous": _button_binding(JOY_BUTTON_LEFT_SHOULDER),
		&"spectator_next": _button_binding(JOY_BUTTON_RIGHT_SHOULDER),
		&"ui_up": _button_binding(JOY_BUTTON_DPAD_UP),
		&"ui_down": _button_binding(JOY_BUTTON_DPAD_DOWN),
		&"ui_left": _button_binding(JOY_BUTTON_DPAD_LEFT),
		&"ui_right": _button_binding(JOY_BUTTON_DPAD_RIGHT),
		&"ui_accept": _button_binding(JOY_BUTTON_A),
		&"ui_cancel": _button_binding(JOY_BUTTON_B),
	}


func _key_binding(keycode: Key) -> Dictionary:
	return {"type": "key", "physical_keycode": int(keycode), "shift": false, "alt": false, "ctrl": false, "meta": false}


func _mouse_binding(button_index: MouseButton) -> Dictionary:
	return {"type": "mouse_button", "button_index": int(button_index)}


func _button_binding(button_index: JoyButton) -> Dictionary:
	return {"type": "joy_button", "button_index": int(button_index)}


func _axis_binding(axis: JoyAxis, axis_value: float) -> Dictionary:
	return {"type": "joy_axis", "axis": int(axis), "axis_value": signf(axis_value)}


func _serialize_binding(event: InputEvent, scheme: Scheme) -> Dictionary:
	if scheme == Scheme.KEYBOARD_MOUSE:
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var physical := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
			if physical == KEY_NONE:
				return {}
			return {
				"type": "key",
				"physical_keycode": int(physical),
				"shift": key_event.shift_pressed,
				"alt": key_event.alt_pressed,
				"ctrl": key_event.ctrl_pressed,
				"meta": key_event.meta_pressed,
			}
		if event is InputEventMouseButton:
			return _mouse_binding((event as InputEventMouseButton).button_index)
		return {}
	if event is InputEventJoypadButton:
		return _button_binding((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < 0.65:
			return {}
		return _axis_binding(motion.axis, motion.axis_value)
	return {}


func _deserialize_binding(data: Dictionary) -> InputEvent:
	match String(data.get("type", "")):
		"key":
			var event := InputEventKey.new()
			event.physical_keycode = int(data.get("physical_keycode", KEY_NONE)) as Key
			event.shift_pressed = bool(data.get("shift", false))
			event.alt_pressed = bool(data.get("alt", false))
			event.ctrl_pressed = bool(data.get("ctrl", false))
			event.meta_pressed = bool(data.get("meta", false))
			return event
		"mouse_button":
			var event := InputEventMouseButton.new()
			event.button_index = int(data.get("button_index", MOUSE_BUTTON_NONE)) as MouseButton
			return event
		"joy_button":
			var event := InputEventJoypadButton.new()
			event.device = -1
			event.button_index = int(data.get("button_index", JOY_BUTTON_INVALID)) as JoyButton
			return event
		"joy_axis":
			var event := InputEventJoypadMotion.new()
			event.device = -1
			event.axis = int(data.get("axis", JOY_AXIS_INVALID)) as JoyAxis
			event.axis_value = signf(float(data.get("axis_value", 1.0)))
			return event
	return null


func _event_display_text(event: InputEvent) -> String:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "%s %s" % [_joy_axis_name(motion.axis), "+" if motion.axis_value > 0.0 else "−"]
	if event is InputEventJoypadButton:
		return _joy_button_name((event as InputEventJoypadButton).button_index)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left Mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right Mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP:
				return "Mouse Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Mouse Wheel Down"
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var pieces: Array[String] = []
		if key_event.ctrl_pressed:
			pieces.append("Ctrl")
		if key_event.alt_pressed:
			pieces.append("Alt")
		if key_event.shift_pressed:
			pieces.append("Shift")
		if key_event.meta_pressed:
			pieces.append("Meta")
		pieces.append(OS.get_keycode_string(key_event.physical_keycode))
		return "+".join(pieces)
	return event.as_text()


func _joy_axis_name(axis: JoyAxis) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left Stick X"
		JOY_AXIS_LEFT_Y:
			return "Left Stick Y"
		JOY_AXIS_RIGHT_X:
			return "Right Stick X"
		JOY_AXIS_RIGHT_Y:
			return "Right Stick Y"
		JOY_AXIS_TRIGGER_LEFT:
			return "Left Trigger"
		JOY_AXIS_TRIGGER_RIGHT:
			return "Right Trigger"
	return "Joystick Axis %d" % int(axis)


func _joy_button_name(button: JoyButton) -> String:
	match button:
		JOY_BUTTON_A:
			return "A / Cross"
		JOY_BUTTON_B:
			return "B / Circle"
		JOY_BUTTON_X:
			return "X / Square"
		JOY_BUTTON_Y:
			return "Y / Triangle"
		JOY_BUTTON_BACK:
			return "View / Back"
		JOY_BUTTON_START:
			return "Menu / Start"
		JOY_BUTTON_LEFT_SHOULDER:
			return "Left Bumper"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "Right Bumper"
		JOY_BUTTON_DPAD_UP:
			return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-Pad Right"
		JOY_BUTTON_LEFT_STICK:
			return "Left Stick Click"
		JOY_BUTTON_RIGHT_STICK:
			return "Right Stick Click"
	return "Controller Button %d" % int(button)


func _validated_scheme(value: int) -> Scheme:
	return Scheme.CONTROLLER if value == Scheme.CONTROLLER else Scheme.KEYBOARD_MOUSE


func _validated_flight_mode(value: int) -> FlightMode:
	return FlightMode.RELATIVE if value == FlightMode.RELATIVE else FlightMode.NEWTONIAN


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	controller_connections_changed.emit()
