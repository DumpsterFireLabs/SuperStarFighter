extends Node

## Owns settings controls, preferences, display modes, and binding capture.
## The client coordinates navigation between gameplay and these screens.

const NavigationScript = preload("res://src/client/ui/screen_navigation.gd")
const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const AccessibilityPreferencesScript = preload("res://src/client/presentation/accessibility_preferences.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
enum WindowModeOption {
	WINDOWED,
	BORDERLESS_FULLSCREEN,
	EXCLUSIVE_FULLSCREEN,
}
const WINDOW_MODE_LABELS: Array[String] = [
	"Windowed",
	"Borderless Fullscreen",
	"Exclusive Fullscreen",
]
const RESOLUTION_OPTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(2880, 1920),
	Vector2i(3440, 1440),
	Vector2i(3840, 1080),
	Vector2i(3840, 1600),
	Vector2i(3840, 2160),
	Vector2i(5120, 1440),
	Vector2i(5120, 2160),
]

var client: Node
var settings_panel: Control
var settings_tabs: TabContainer
var accessibility_preferences = AccessibilityPreferencesScript.new()
var hud_scale_control: HSlider
var hud_scale_value: Label
var reduced_shake_control: CheckButton
var reduced_flashes_control: CheckButton
var constrain_hud_control: CheckButton
var settings_back_button: Button
var window_mode_control: OptionButton
var resolution_control: OptionButton
var display_mode_note: Label
var control_scheme_control: OptionButton
var flight_mode_control: OptionButton
var controller_status_label: Label
var controller_deadzone_row: HBoxContainer
var controller_deadzone_slider: HSlider
var controller_deadzone_value: Label
var binding_rows: GridContainer
var binding_buttons: Dictionary = {}
var binding_capture_status: Label
var binding_capture_action: StringName = &""
var binding_capture_seconds: float = 0.0
var current_window_mode: int = WindowModeOption.WINDOWED
var current_resolution: Vector2i = Vector2i(1280, 720)


func initialize(client_root: Node) -> void:
	client = client_root


func _create_settings_overlay() -> void:
	settings_panel = Control.new()
	settings_panel.name = "SettingsScreen"
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	client.connection_controller.connection_canvas.add_child(settings_panel)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color("02040d", 0.88)
	settings_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920.0, 690.0)
	panel.theme = client.interface_theme
	panel.add_theme_stylebox_override("panel", client._panel_style(DesignTokensScript.BRAND_MAGENTA, 0.98))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("d39cff"))
	content.add_child(title)
	settings_tabs = TabContainer.new()
	settings_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	settings_tabs.get_tab_bar().gui_input.connect(NavigationScript.handle_tab_bar_input.bind(settings_tabs))
	settings_tabs.custom_minimum_size = Vector2(860.0, 500.0)
	settings_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(settings_tabs)
	_create_display_audio_settings_tab()
	_create_controls_settings_tab()
	_create_accessibility_settings_tab()
	settings_tabs.tab_changed.connect(_on_settings_tab_changed)
	var saved_note := Label.new()
	saved_note.text = "Settings and both control profiles save automatically."
	saved_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	saved_note.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(saved_note)
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.theme_type_variation = &"QuietButton"
	back_button.custom_minimum_size.y = 52.0
	back_button.pressed.connect(client._hide_settings)
	content.add_child(back_button)
	settings_back_button = back_button
	_configure_accessibility_focus()


func _create_accessibility_settings_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "ACCESSIBILITY"
	tab.add_theme_constant_override("separation", 16)
	settings_tabs.add_child(tab)
	var heading := Label.new()
	heading.text = "COMBAT READABILITY & COMFORT"
	heading.add_theme_font_size_override("font_size", 23)
	tab.add_child(heading)
	var scale_row := HBoxContainer.new()
	tab.add_child(scale_row)
	var scale_label := Label.new()
	scale_label.text = "HUD & combat text size"
	scale_label.custom_minimum_size.x = 280.0
	scale_row.add_child(scale_label)
	hud_scale_control = HSlider.new()
	hud_scale_control.name = "HUDScale"
	hud_scale_control.min_value = 100.0
	hud_scale_control.max_value = 150.0
	hud_scale_control.step = 10.0
	hud_scale_control.value = float(accessibility_preferences.values.hud_scale) * 100.0
	hud_scale_control.custom_minimum_size = Vector2(340.0, 48.0)
	hud_scale_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(hud_scale_control)
	hud_scale_value = Label.new()
	hud_scale_value.custom_minimum_size.x = 70.0
	hud_scale_value.text = "%d%%" % roundi(hud_scale_control.value)
	scale_row.add_child(hud_scale_value)
	hud_scale_control.value_changed.connect(func(value: float) -> void:
		hud_scale_value.text = "%d%%" % roundi(value)
		_change_accessibility_setting("hud_scale", value / 100.0)
	)
	hud_scale_control.gui_input.connect(_on_hud_scale_gui_input)
	reduced_shake_control = _add_accessibility_toggle(tab, "Disable camera shake and boost kick", "reduced_shake")
	reduced_flashes_control = _add_accessibility_toggle(tab, "Reduce combat flashes", "reduced_flashes")
	constrain_hud_control = _add_accessibility_toggle(tab, "Keep HUD within a centered 16:9 area", "constrain_hud")
	var note := Label.new()
	note.text = "Applies immediately to online play and the build laboratory.\nReduced flashes keeps impact outlines and damage information visible.\nUse Tab / Shift+Tab or controller D-pad to navigate; Left / Right adjusts size."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
	tab.add_child(note)


func _add_accessibility_toggle(parent: Control, title: String, key: String) -> CheckButton:
	var control := CheckButton.new()
	control.text = title
	control.theme_type_variation = &"SettingToggle"
	control.custom_minimum_size.y = 52.0
	control.button_pressed = bool(accessibility_preferences.values[key])
	control.toggled.connect(func(value: bool) -> void: _change_accessibility_setting(key, value))
	parent.add_child(control)
	return control


func _on_hud_scale_gui_input(event: InputEvent) -> void:
	# Godot's range keyboard shortcuts do not consume joypad navigation; keep
	# Left/Right on the slider instead of moving focus to a neighboring toggle.
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.is_action_pressed(&"ui_left"):
		hud_scale_control.value -= hud_scale_control.step
		hud_scale_control.accept_event()
	elif event.is_action_pressed(&"ui_right"):
		hud_scale_control.value += hud_scale_control.step
		hud_scale_control.accept_event()


func _change_accessibility_setting(key: String, value: Variant) -> void:
	accessibility_preferences.set_values({key: value})
	accessibility_preferences.save_settings()
	client._apply_accessibility_settings()


func _configure_accessibility_focus() -> void:
	var controls: Array[Control] = [settings_tabs.get_tab_bar(), hud_scale_control, reduced_shake_control, reduced_flashes_control, constrain_hud_control, settings_back_button]
	for index in range(1, controls.size() - 1):
		controls[index].focus_previous = controls[index].get_path_to(controls[index - 1])
		controls[index].focus_neighbor_top = controls[index].focus_previous
		controls[index].focus_next = controls[index].get_path_to(controls[index + 1])
		controls[index].focus_neighbor_bottom = controls[index].focus_next


func _on_settings_tab_changed(index: int) -> void:
	if not settings_panel.visible:
		return
	var first_control: Control = window_mode_control
	if index == 2:
		first_control = hud_scale_control
	elif index == 1:
		first_control = control_scheme_control
	var tab_bar := settings_tabs.get_tab_bar()
	tab_bar.focus_next = tab_bar.get_path_to(first_control)
	tab_bar.focus_neighbor_bottom = tab_bar.focus_next
	# Let players traverse every tab with Left/Right before entering its controls.
	if get_viewport().gui_get_focus_owner() != tab_bar:
		first_control.grab_focus()


func _create_display_audio_settings_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "DISPLAY & AUDIO"
	tab.add_theme_constant_override("separation", 14)
	settings_tabs.add_child(tab)
	var display_title := Label.new()
	display_title.text = "DISPLAY"
	display_title.add_theme_font_size_override("font_size", 23)
	display_title.add_theme_color_override("font_color", Color("73f7ff"))
	tab.add_child(display_title)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 16)
	tab.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "Display mode"
	mode_label.custom_minimum_size.x = 190.0
	mode_row.add_child(mode_label)
	window_mode_control = OptionButton.new()
	window_mode_control.custom_minimum_size = Vector2(430.0, 48.0)
	window_mode_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for mode_index in WINDOW_MODE_LABELS.size():
		window_mode_control.add_item(WINDOW_MODE_LABELS[mode_index], mode_index)
	window_mode_control.select(current_window_mode)
	window_mode_control.item_selected.connect(_on_window_mode_selected)
	mode_row.add_child(window_mode_control)
	var resolution_row := HBoxContainer.new()
	resolution_row.add_theme_constant_override("separation", 16)
	tab.add_child(resolution_row)
	var resolution_label := Label.new()
	resolution_label.text = "Resolution"
	resolution_label.custom_minimum_size.x = 190.0
	resolution_row.add_child(resolution_label)
	resolution_control = OptionButton.new()
	resolution_control.custom_minimum_size = Vector2(430.0, 48.0)
	resolution_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for resolution in RESOLUTION_OPTIONS:
		resolution_control.add_item("%d × %d" % [resolution.x, resolution.y])
	resolution_control.select(maxi(RESOLUTION_OPTIONS.find(current_resolution), 0))
	resolution_control.item_selected.connect(_on_resolution_selected)
	resolution_row.add_child(resolution_control)
	display_mode_note = Label.new()
	display_mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	display_mode_note.add_theme_color_override("font_color", Color("aebbd4"))
	tab.add_child(display_mode_note)
	_update_resolution_control_state()
	var audio_title := Label.new()
	audio_title.text = "AUDIO"
	audio_title.add_theme_font_size_override("font_size", 23)
	audio_title.add_theme_color_override("font_color", Color("73f7ff"))
	tab.add_child(audio_title)
	_add_volume_setting(tab, "Master Volume", &"master", client.audio_director.master_volume_percent)
	_add_volume_setting(tab, "Music Volume", &"music", client.audio_director.music_volume_percent)
	_add_volume_setting(tab, "Effects Volume", &"sfx", client.audio_director.sfx_volume_percent)
	var mute_button := CheckButton.new()
	mute_button.text = "Mute all audio"
	mute_button.theme_type_variation = &"SettingToggle"
	mute_button.button_pressed = client.audio_director.muted
	mute_button.custom_minimum_size.y = 48.0
	mute_button.toggled.connect(client.audio_director.set_muted)
	tab.add_child(mute_button)


func _create_controls_settings_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "CONTROLS"
	tab.add_theme_constant_override("separation", 8)
	settings_tabs.add_child(tab)
	var scheme_row := HBoxContainer.new()
	scheme_row.add_theme_constant_override("separation", 16)
	tab.add_child(scheme_row)
	var scheme_label := Label.new()
	scheme_label.text = "Active input"
	scheme_label.custom_minimum_size.x = 220.0
	scheme_row.add_child(scheme_label)
	control_scheme_control = OptionButton.new()
	control_scheme_control.custom_minimum_size = Vector2(540.0, 44.0)
	control_scheme_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_scheme_control.add_item("Keyboard & Mouse", InputProfileManagerScript.Scheme.KEYBOARD_MOUSE)
	control_scheme_control.add_item("Controller / Joystick", InputProfileManagerScript.Scheme.CONTROLLER)
	control_scheme_control.select(int(client.input_profiles.active_scheme))
	control_scheme_control.item_selected.connect(_on_control_scheme_selected)
	scheme_row.add_child(control_scheme_control)
	var flight_mode_row := HBoxContainer.new()
	flight_mode_row.add_theme_constant_override("separation", 16)
	tab.add_child(flight_mode_row)
	var flight_mode_label := Label.new()
	flight_mode_label.text = "Flight mode"
	flight_mode_label.custom_minimum_size.x = 220.0
	flight_mode_row.add_child(flight_mode_label)
	flight_mode_control = OptionButton.new()
	flight_mode_control.custom_minimum_size = Vector2(540.0, 44.0)
	flight_mode_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flight_mode_control.add_item("Newtonian · movement follows ship heading", InputProfileManagerScript.FlightMode.NEWTONIAN)
	flight_mode_control.add_item("Relative · movement follows the screen", InputProfileManagerScript.FlightMode.RELATIVE)
	flight_mode_control.select(int(client.input_profiles.flight_mode))
	flight_mode_control.item_selected.connect(_on_flight_mode_selected)
	flight_mode_row.add_child(flight_mode_control)
	controller_status_label = Label.new()
	controller_status_label.add_theme_color_override("font_color", Color("aebbd4"))
	controller_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(controller_status_label)
	controller_deadzone_row = HBoxContainer.new()
	controller_deadzone_row.add_theme_constant_override("separation", 16)
	tab.add_child(controller_deadzone_row)
	var deadzone_label := Label.new()
	deadzone_label.text = "Stick deadzone"
	deadzone_label.custom_minimum_size.x = 220.0
	controller_deadzone_row.add_child(deadzone_label)
	controller_deadzone_slider = HSlider.new()
	controller_deadzone_slider.min_value = InputProfileManagerScript.MIN_CONTROLLER_DEADZONE
	controller_deadzone_slider.max_value = InputProfileManagerScript.MAX_CONTROLLER_DEADZONE
	controller_deadzone_slider.step = 0.01
	controller_deadzone_slider.value = client.input_profiles.controller_deadzone
	controller_deadzone_slider.custom_minimum_size = Vector2(460.0, 40.0)
	controller_deadzone_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controller_deadzone_row.add_child(controller_deadzone_slider)
	controller_deadzone_value = Label.new()
	controller_deadzone_value.custom_minimum_size.x = 72.0
	controller_deadzone_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controller_deadzone_row.add_child(controller_deadzone_value)
	controller_deadzone_slider.value_changed.connect(_on_controller_deadzone_changed)
	binding_capture_status = Label.new()
	binding_capture_status.text = "Select a binding, then press its replacement input."
	binding_capture_status.add_theme_color_override("font_color", Color("fff36a"))
	binding_capture_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.add_child(binding_capture_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820.0, 250.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	binding_rows = GridContainer.new()
	binding_rows.columns = 2
	binding_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binding_rows.add_theme_constant_override("h_separation", 18)
	binding_rows.add_theme_constant_override("v_separation", 6)
	scroll.add_child(binding_rows)
	var reset_button := Button.new()
	reset_button.text = "Restore This Profile's Defaults"
	reset_button.theme_type_variation = &"SecondaryButton"
	reset_button.custom_minimum_size.y = 42.0
	reset_button.pressed.connect(_on_restore_control_defaults)
	tab.add_child(reset_button)
	_refresh_input_settings_ui()


func _refresh_input_settings_ui() -> void:
	if control_scheme_control == null:
		return
	control_scheme_control.select(int(client.input_profiles.active_scheme))
	flight_mode_control.select(int(client.input_profiles.flight_mode))
	controller_deadzone_row.visible = client.input_profiles.uses_controller()
	controller_deadzone_slider.set_value_no_signal(client.input_profiles.controller_deadzone)
	controller_deadzone_value.text = "%d%%" % roundi(client.input_profiles.controller_deadzone * 100.0)
	_update_controller_status()
	_rebuild_binding_rows()


func _rebuild_binding_rows() -> void:
	if binding_rows == null:
		return
	for child in binding_rows.get_children():
		binding_rows.remove_child(child)
		child.queue_free()
	binding_buttons.clear()
	for action in client.input_profiles.rebind_actions():
		var label := Label.new()
		label.text = client.input_profiles.action_label(action)
		label.custom_minimum_size = Vector2(360.0, 40.0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		binding_rows.add_child(label)
		var button := Button.new()
		button.text = client.input_profiles.binding_text(action)
		button.custom_minimum_size = Vector2(390.0, 40.0)
		button.pressed.connect(_begin_binding_capture.bind(action))
		binding_rows.add_child(button)
		binding_buttons[action] = button


func _on_control_scheme_selected(index: int) -> void:
	_cancel_binding_capture()
	client.input_profiles.set_scheme(control_scheme_control.get_item_id(index))
	_refresh_input_settings_ui()


func _on_flight_mode_selected(index: int) -> void:
	client.input_profiles.set_flight_mode(flight_mode_control.get_item_id(index))
	_refresh_input_settings_ui()


func _on_controller_deadzone_changed(value: float) -> void:
	client.input_profiles.set_controller_deadzone(value)
	controller_deadzone_value.text = "%d%%" % roundi(client.input_profiles.controller_deadzone * 100.0)


func _begin_binding_capture(action: StringName) -> void:
	binding_capture_action = action
	binding_capture_seconds = 8.0
	var prompt := "Press a controller button or move one axis fully" if client.input_profiles.uses_controller() else "Press a keyboard key or mouse button"
	binding_capture_status.text = "%s for %s…" % [prompt, client.input_profiles.action_label(action)]
	if binding_buttons.has(action):
		(binding_buttons[action] as Button).text = "PRESS INPUT…"


func _complete_binding_capture(event: InputEvent) -> void:
	var action := binding_capture_action
	var rebound: bool = client.input_profiles.rebind(action, event)
	if rebound:
		binding_capture_status.text = "%s is now %s." % [client.input_profiles.action_label(action), client.input_profiles.binding_text(action)]
	else:
		binding_capture_status.text = "That input is not valid for the selected profile."
	binding_capture_action = &""
	binding_capture_seconds = 0.0
	if not rebound:
		_rebuild_binding_rows()


func _cancel_binding_capture() -> void:
	if binding_capture_action.is_empty():
		return
	binding_capture_action = &""
	binding_capture_seconds = 0.0
	if binding_capture_status != null:
		binding_capture_status.text = "Binding capture timed out. Nothing changed."
	_rebuild_binding_rows()


func _on_restore_control_defaults() -> void:
	_cancel_binding_capture()
	client.input_profiles.restore_active_defaults()
	binding_capture_status.text = "Restored the selected profile's default bindings."
	_refresh_input_settings_ui()


func _on_control_scheme_changed(_scheme: int) -> void:
	_refresh_input_settings_ui()
	client._refresh_control_prompts()


func _on_flight_mode_changed(_flight_mode: int) -> void:
	_refresh_input_settings_ui()


func _on_control_bindings_changed() -> void:
	_rebuild_binding_rows()
	client._refresh_control_prompts()


func _update_controller_status() -> void:
	if controller_status_label == null:
		return
	controller_status_label.text = client.input_profiles.controller_status_text() if client.input_profiles.uses_controller() else "Keyboard and mouse is the default profile. Controller settings remain saved separately."


func _add_volume_setting(parent: VBoxContainer, title: String, channel: StringName, initial_value: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 190.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial_value
	slider.custom_minimum_size = Vector2(380.0, 48.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "%d%%" % roundi(initial_value)
	value_label.custom_minimum_size.x = 70.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(_on_volume_changed.bind(channel, value_label))


func _on_volume_changed(value: float, channel: StringName, value_label: Label) -> void:
	value_label.text = "%d%%" % roundi(value)
	match channel:
		&"master": client.audio_director.set_master_volume(value)
		&"music": client.audio_director.set_music_volume(value)
		&"sfx": client.audio_director.set_sfx_volume(value)


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= RESOLUTION_OPTIONS.size():
		return
	current_resolution = RESOLUTION_OPTIONS[index]
	if DisplayServer.get_name() != "headless":
		_apply_video_settings()
	_save_video_settings()


func _on_window_mode_selected(index: int) -> void:
	if index < 0 or index >= WINDOW_MODE_LABELS.size():
		return
	current_window_mode = window_mode_control.get_item_id(index)
	_update_resolution_control_state()
	if DisplayServer.get_name() != "headless":
		_apply_video_settings()
	_save_video_settings()


func _load_video_settings() -> void:
	var capture_resolution_value: Variant = get_tree().root.get_meta("ssf_presentation_capture_resolution", Vector2i.ZERO)
	if capture_resolution_value is Vector2i and capture_resolution_value != Vector2i.ZERO:
		current_window_mode = WindowModeOption.WINDOWED
		current_resolution = capture_resolution_value
		if DisplayServer.get_name() != "headless":
			_apply_video_settings()
		return
	if DisplayServer.get_name() != "headless":
		current_resolution = DisplayServer.window_get_size()
	var config := ConfigFile.new()
	if config.load(AudioDirector.SETTINGS_PATH) == OK:
		var configured_mode := int(config.get_value("video", "window_mode", WindowModeOption.WINDOWED))
		if configured_mode >= WindowModeOption.WINDOWED and configured_mode <= WindowModeOption.EXCLUSIVE_FULLSCREEN:
			current_window_mode = configured_mode
		var configured := Vector2i(
			int(config.get_value("video", "width", current_resolution.x)),
			int(config.get_value("video", "height", current_resolution.y))
		)
		if configured in RESOLUTION_OPTIONS:
			current_resolution = configured
	if current_resolution not in RESOLUTION_OPTIONS:
		current_resolution = RESOLUTION_OPTIONS[0]
	if DisplayServer.get_name() != "headless":
		_apply_video_settings()


func _apply_video_settings() -> void:
	match current_window_mode:
		WindowModeOption.BORDERLESS_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowModeOption.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(current_resolution)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(current_resolution)
			var screen := DisplayServer.window_get_current_screen()
			var usable_rect := DisplayServer.screen_get_usable_rect(screen)
			var safe_offset := Vector2i(
				maxi((usable_rect.size.x - current_resolution.x) / 2, 0),
				maxi((usable_rect.size.y - current_resolution.y) / 2, 0)
			)
			DisplayServer.window_set_position(usable_rect.position + safe_offset)


func _update_resolution_control_state() -> void:
	if resolution_control == null:
		return
	var uses_desktop_resolution := current_window_mode == WindowModeOption.BORDERLESS_FULLSCREEN
	resolution_control.disabled = uses_desktop_resolution
	if display_mode_note == null:
		return
	if uses_desktop_resolution:
		display_mode_note.text = "Borderless fullscreen uses the desktop's current resolution. Your selected resolution remains saved for other modes."
	elif current_window_mode == WindowModeOption.EXCLUSIVE_FULLSCREEN:
		display_mode_note.text = "Exclusive fullscreen requests the selected display mode; availability depends on the connected monitor and graphics driver."
	else:
		display_mode_note.text = "Windowed mode uses the selected client-area resolution."


func _save_video_settings() -> void:
	var config := ConfigFile.new()
	config.load(AudioDirector.SETTINGS_PATH)
	config.set_value("video", "window_mode", current_window_mode)
	config.set_value("video", "width", current_resolution.x)
	config.set_value("video", "height", current_resolution.y)
	config.save(AudioDirector.SETTINGS_PATH)



func capture_input(event: InputEvent) -> bool:
	if binding_capture_action.is_empty():
		return false
	if client.input_profiles.accepts_rebind_event(event):
		_complete_binding_capture(event)
		get_viewport().set_input_as_handled()
	return true


func _process(delta: float) -> void:
	if binding_capture_action.is_empty():
		return
	binding_capture_seconds = maxf(binding_capture_seconds - delta, 0.0)
	if binding_capture_seconds <= 0.0:
		_cancel_binding_capture()
