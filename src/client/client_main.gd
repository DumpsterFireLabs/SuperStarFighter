extends Node

var bridge: NetworkBridge
var network_world: NetworkWorldView
var offline_sandbox: OfflineSandbox
var audio_director: AudioDirector
var connection_canvas: CanvasLayer
var connection_screen: Control
var lobby_panel: PanelContainer
var host_field: LineEdit
var port_field: LineEdit
var name_field: LineEdit
var connection_status: Label
var lobby_label: Label
var rounds_control: SpinBox
var player_limit_control: SpinBox
var npcs_button: CheckButton
var start_button: Button
var match_panel: PanelContainer
var match_label: Label
var draft_panel: PanelContainer
var draft_title: Label
var draft_buttons: Array[Button] = []
var scoreboard_panel: PanelContainer
var scoreboard_label: Label
var results_panel: PanelContainer
var results_label: Label
var win_overlay: Control
var pause_overlay: PanelContainer
var pause_title: Label
var settings_panel: Control
var settings_return_to_pause: bool = false
var splash_screen: Control
var splash_dismissed: bool = false
var card_catalog := CardCatalog.create_default()
var active_offer_token: String = ""
var active_offer_deadline: int = -1
var latest_match_payload: Dictionary = {}
var _applying_lobby_state: bool = false
var interface_theme: Theme
var last_countdown_second: int = -1
var overtime_announced: bool = false
var last_state_name: String = "LOBBY"


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	offline_sandbox = $OfflineSandbox as OfflineSandbox
	offline_sandbox.set_sandbox_active(false)
	bridge = NetworkBridge.new()
	bridge.name = "NetworkBridge"
	add_child(bridge)
	bridge.client_connected.connect(_on_connected)
	bridge.client_lobby_updated.connect(_on_lobby_state)
	bridge.client_match_event_received.connect(_on_match_event)
	bridge.client_rejected.connect(_on_rejected)
	bridge.client_connection_lost.connect(_on_connection_lost)
	audio_director = AudioDirector.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	network_world = NetworkWorldView.new()
	network_world.name = "NetworkWorld"
	add_child(network_world)
	network_world.setup(bridge)
	network_world.presentation_event.connect(_on_world_presentation_event)
	_create_connection_ui(configuration)
	_create_match_ui()
	_create_pause_overlay()
	_create_settings_overlay()
	_create_splash_screen()
	audio_director.set_context(&"menu")
	print("SSF_MODE_READY=client port=%d sandbox=offline_combat network=enet" % configuration.get("port", GameConstants.DEFAULT_PORT))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_overlay") and not (event is InputEventKey and event.echo):
		if splash_screen != null and splash_screen.visible:
			_dismiss_splash()
		elif settings_panel != null and settings_panel.visible:
			_hide_settings()
		else:
			_toggle_pause_overlay()
		get_viewport().set_input_as_handled()
		return
	if splash_screen != null and splash_screen.visible and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		_dismiss_splash()
		get_viewport().set_input_as_handled()
		return
	if pause_overlay != null and pause_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		_show_connection_screen("Choose online play or the offline combat lab.")
	if event is InputEventKey and event.pressed and not event.echo and draft_panel != null and draft_panel.visible:
		for index in draft_buttons.size():
			if event.is_action_pressed("draft_%d" % (index + 1)):
				_select_draft_card(index)
				get_viewport().set_input_as_handled()
				break


func _create_connection_ui(configuration: Dictionary) -> void:
	interface_theme = Theme.new()
	interface_theme.default_font_size = 20
	_configure_interface_theme()
	connection_canvas = CanvasLayer.new()
	connection_canvas.layer = 20
	connection_canvas.name = "ConnectionUI"
	add_child(connection_canvas)
	connection_screen = Control.new()
	connection_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_screen.theme = interface_theme
	connection_canvas.add_child(connection_screen)
	var background := NeonBackdrop.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_screen.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700.0, 570.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("42e8ff"), 0.96))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	var title := Label.new()
	title.text = "✦ SUPER STAR FIGHTER ✦"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 48)
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "POWER UP · OUTGUN · OUTLAST"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("d39cff"))
	subtitle.add_theme_font_size_override("font_size", 25)
	content.add_child(subtitle)
	host_field = _add_labeled_field(content, "Server host", configuration.get("host", "127.0.0.1"))
	port_field = _add_labeled_field(content, "UDP port", str(configuration.get("port", GameConstants.DEFAULT_PORT)))
	name_field = _add_labeled_field(content, "Display name", "Pilot")
	name_field.max_length = 16
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	var connect_button := Button.new()
	connect_button.text = "Connect"
	connect_button.custom_minimum_size.y = 54.0
	connect_button.pressed.connect(_connect_online)
	buttons.add_child(connect_button)
	var offline_button := Button.new()
	offline_button.text = "Offline Combat Lab"
	offline_button.custom_minimum_size.y = 54.0
	offline_button.pressed.connect(_play_offline)
	buttons.add_child(offline_button)
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size.y = 54.0
	settings_button.pressed.connect(_show_settings.bind(false))
	buttons.add_child(settings_button)
	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(110.0, 54.0)
	quit_button.pressed.connect(get_tree().quit)
	buttons.add_child(quit_button)
	connection_status = Label.new()
	connection_status.text = "Direct IP uses UDP. Press F2 at any time to return here."
	connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connection_status.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(connection_status)
	_create_lobby_panel()


func _create_lobby_panel() -> void:
	lobby_panel = PanelContainer.new()
	lobby_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lobby_panel.position = Vector2(-664.0, 24.0)
	lobby_panel.custom_minimum_size = Vector2(640.0, 650.0)
	lobby_panel.theme = interface_theme
	lobby_panel.add_theme_stylebox_override("panel", _panel_style(Color("42e8ff"), 0.96))
	lobby_panel.visible = false
	connection_canvas.add_child(lobby_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	lobby_panel.add_child(content)
	var title := Label.new()
	title.text = "ONLINE LOBBY"
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 30)
	content.add_child(title)
	var player_scroll := ScrollContainer.new()
	player_scroll.custom_minimum_size = Vector2(610.0, 250.0)
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(player_scroll)
	lobby_label = Label.new()
	lobby_label.add_theme_font_size_override("font_size", 20)
	lobby_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_scroll.add_child(lobby_label)
	var rounds_row := HBoxContainer.new()
	content.add_child(rounds_row)
	var rounds_label := Label.new()
	rounds_label.text = "Rounds to win"
	rounds_row.add_child(rounds_label)
	rounds_control = SpinBox.new()
	rounds_control.min_value = GameConstants.MIN_ROUNDS_TO_WIN
	rounds_control.max_value = GameConstants.MAX_ROUNDS_TO_WIN
	rounds_control.value = GameConstants.DEFAULT_ROUNDS_TO_WIN
	rounds_control.custom_minimum_size = Vector2(130.0, 48.0)
	rounds_control.value_changed.connect(_on_rounds_changed)
	rounds_row.add_child(rounds_control)
	var limit_row := HBoxContainer.new()
	content.add_child(limit_row)
	var limit_label := Label.new()
	limit_label.text = "Player limit"
	limit_row.add_child(limit_label)
	player_limit_control = SpinBox.new()
	player_limit_control.min_value = GameConstants.MIN_PLAYERS
	player_limit_control.max_value = GameConstants.MAX_PLAYERS
	player_limit_control.value = GameConstants.DEFAULT_MAX_PLAYERS
	player_limit_control.custom_minimum_size = Vector2(130.0, 48.0)
	player_limit_control.value_changed.connect(_on_player_limit_changed)
	limit_row.add_child(player_limit_control)
	npcs_button = CheckButton.new()
	npcs_button.text = "Enable NPCs · fill empty seats when starting"
	npcs_button.custom_minimum_size.y = 48.0
	npcs_button.toggled.connect(_on_npcs_toggled)
	content.add_child(npcs_button)
	start_button = Button.new()
	start_button.text = "Force Start Match"
	start_button.custom_minimum_size.y = 54.0
	start_button.pressed.connect(bridge.send_start_match)
	content.add_child(start_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect"
	disconnect_button.custom_minimum_size.y = 54.0
	disconnect_button.pressed.connect(_disconnect_online)
	content.add_child(disconnect_button)


func _create_match_ui() -> void:
	match_panel = PanelContainer.new()
	match_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	match_panel.position = Vector2(-380.0, 20.0)
	match_panel.custom_minimum_size = Vector2(760.0, 112.0)
	match_panel.theme = interface_theme
	match_panel.add_theme_stylebox_override("panel", _panel_style(Color("42e8ff"), 0.9))
	match_panel.visible = false
	connection_canvas.add_child(match_panel)
	match_label = Label.new()
	match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_label.add_theme_font_size_override("font_size", 24)
	match_label.add_theme_color_override("font_color", Color("73f7ff"))
	match_panel.add_child(match_label)

	draft_panel = PanelContainer.new()
	draft_panel.set_anchors_preset(Control.PRESET_CENTER)
	draft_panel.position = Vector2(-600.0, -280.0)
	draft_panel.custom_minimum_size = Vector2(1200.0, 560.0)
	draft_panel.theme = interface_theme
	draft_panel.add_theme_stylebox_override("panel", _panel_style(Color("d39cff"), 0.98))
	draft_panel.visible = false
	connection_canvas.add_child(draft_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	draft_panel.add_child(content)
	draft_title = Label.new()
	draft_title.text = "CHOOSE YOUR UPGRADE"
	draft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_title.add_theme_font_size_override("font_size", 34)
	draft_title.add_theme_color_override("font_color", Color("d39cff"))
	content.add_child(draft_title)
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	content.add_child(cards)
	for index in GameConstants.CARD_OFFER_SIZE:
		var button := Button.new()
		button.custom_minimum_size = Vector2(224.0, 400.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_color_override("font_color", Color("e8f5ff"))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.pressed.connect(_select_draft_card.bind(index))
		cards.add_child(button)
		draft_buttons.append(button)

	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.position = Vector2(-450.0, -310.0)
	scoreboard_panel.custom_minimum_size = Vector2(900.0, 620.0)
	scoreboard_panel.theme = interface_theme
	scoreboard_panel.add_theme_stylebox_override("panel", _panel_style(Color("42e8ff"), 0.97))
	scoreboard_panel.visible = false
	connection_canvas.add_child(scoreboard_panel)
	var scoreboard_scroll := ScrollContainer.new()
	scoreboard_scroll.custom_minimum_size = Vector2(860.0, 580.0)
	scoreboard_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scoreboard_panel.add_child(scoreboard_scroll)
	scoreboard_label = Label.new()
	scoreboard_label.add_theme_font_size_override("font_size", 22)
	scoreboard_label.add_theme_color_override("font_color", Color("e8f5ff"))
	scoreboard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scoreboard_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scoreboard_scroll.add_child(scoreboard_label)

	win_overlay = Control.new()
	win_overlay.name = "WinScreen"
	win_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_overlay.visible = false
	connection_canvas.add_child(win_overlay)
	var win_background := NeonBackdrop.new()
	win_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_overlay.add_child(win_background)
	var win_tint := ColorRect.new()
	win_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_tint.color = Color("170b2f", 0.72)
	win_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_overlay.add_child(win_tint)
	results_panel = PanelContainer.new()
	results_panel.set_anchors_preset(Control.PRESET_CENTER)
	results_panel.position = Vector2(-480.0, -330.0)
	results_panel.custom_minimum_size = Vector2(960.0, 660.0)
	results_panel.theme = interface_theme
	results_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff36a"), 0.96))
	results_panel.visible = true
	win_overlay.add_child(results_panel)
	var results_scroll := ScrollContainer.new()
	results_scroll.custom_minimum_size = Vector2(920.0, 620.0)
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	results_panel.add_child(results_scroll)
	results_label = Label.new()
	results_label.add_theme_font_size_override("font_size", 24)
	results_label.add_theme_color_override("font_color", Color("fff36a"))
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.add_child(results_label)


func _add_labeled_field(parent: VBoxContainer, label_text: String, initial_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var field := LineEdit.new()
	field.text = initial_text
	field.custom_minimum_size.y = 48.0
	parent.add_child(field)
	return field


func _create_pause_overlay() -> void:
	pause_overlay = PanelContainer.new()
	pause_overlay.set_anchors_preset(Control.PRESET_CENTER)
	pause_overlay.position = Vector2(-320.0, -220.0)
	pause_overlay.custom_minimum_size = Vector2(640.0, 440.0)
	pause_overlay.theme = interface_theme
	pause_overlay.add_theme_stylebox_override("panel", _panel_style(Color("ff4fd8"), 0.98))
	pause_overlay.visible = false
	connection_canvas.add_child(pause_overlay)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	pause_overlay.add_child(content)
	pause_title = Label.new()
	pause_title.text = "PILOT MENU"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.add_theme_font_size_override("font_size", 38)
	pause_title.add_theme_color_override("font_color", Color("ff8ee8"))
	content.add_child(pause_title)
	var note := Label.new()
	note.text = "Online combat continues while this menu is open."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(note)
	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.custom_minimum_size.y = 58.0
	resume_button.pressed.connect(_hide_pause_overlay)
	content.add_child(resume_button)
	var settings_button := Button.new()
	settings_button.text = "Audio Settings"
	settings_button.custom_minimum_size.y = 58.0
	settings_button.pressed.connect(_show_settings.bind(true))
	content.add_child(settings_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect / Return to Menu"
	disconnect_button.custom_minimum_size.y = 58.0
	disconnect_button.pressed.connect(_return_from_pause)
	content.add_child(disconnect_button)
	var quit_button := Button.new()
	quit_button.text = "Quit Game"
	quit_button.custom_minimum_size.y = 58.0
	quit_button.pressed.connect(get_tree().quit)
	content.add_child(quit_button)


func _create_settings_overlay() -> void:
	settings_panel = Control.new()
	settings_panel.name = "SettingsScreen"
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	connection_canvas.add_child(settings_panel)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color("02040d", 0.88)
	settings_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720.0, 560.0)
	panel.theme = interface_theme
	panel.add_theme_stylebox_override("panel", _panel_style(Color("d39cff"), 0.98))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	panel.add_child(content)
	var title := Label.new()
	title.text = "AUDIO SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("d39cff"))
	content.add_child(title)
	_add_volume_setting(content, "Master Volume", &"master", audio_director.master_volume_percent)
	_add_volume_setting(content, "Music Volume", &"music", audio_director.music_volume_percent)
	_add_volume_setting(content, "Effects Volume", &"sfx", audio_director.sfx_volume_percent)
	var mute_button := CheckButton.new()
	mute_button.text = "Mute all audio"
	mute_button.button_pressed = audio_director.muted
	mute_button.custom_minimum_size.y = 48.0
	mute_button.toggled.connect(audio_director.set_muted)
	content.add_child(mute_button)
	var saved_note := Label.new()
	saved_note.text = "Settings save automatically and persist between launches."
	saved_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	saved_note.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(saved_note)
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size.y = 58.0
	back_button.pressed.connect(_hide_settings)
	content.add_child(back_button)


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
		&"master": audio_director.set_master_volume(value)
		&"music": audio_director.set_music_volume(value)
		&"sfx": audio_director.set_sfx_volume(value)


func _show_settings(return_to_pause: bool) -> void:
	settings_return_to_pause = return_to_pause
	if pause_overlay != null:
		pause_overlay.visible = false
	settings_panel.visible = true
	if network_world != null:
		network_world.input_blocked = return_to_pause


func _hide_settings() -> void:
	settings_panel.visible = false
	if settings_return_to_pause and not connection_screen.visible:
		pause_overlay.visible = true
		network_world.input_blocked = true
	else:
		network_world.input_blocked = false
	settings_return_to_pause = false


func _create_splash_screen() -> void:
	var splash_canvas := CanvasLayer.new()
	splash_canvas.layer = 40
	splash_canvas.name = "SplashUI"
	add_child(splash_canvas)
	splash_screen = Control.new()
	splash_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_canvas.add_child(splash_screen)
	var backdrop := NeonBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_screen.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_screen.add_child(center)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(content)
	var logo := SplashLogo.new()
	logo.custom_minimum_size = Vector2(520.0, 300.0)
	content.add_child(logo)
	var title := Label.new()
	title.text = "SUPER STAR FIGHTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", Color("f4fbff"))
	content.add_child(title)
	var flare := Label.new()
	flare.text = "✦  POWER UP · OUTGUN · OUTLAST  ✦"
	flare.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flare.add_theme_font_size_override("font_size", 28)
	flare.add_theme_color_override("font_color", Color("ff4fd8"))
	content.add_child(flare)
	var skip := Label.new()
	skip.text = "PRESS ANY KEY"
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip.add_theme_font_size_override("font_size", 18)
	skip.add_theme_color_override("font_color", Color("73f7ff"))
	content.add_child(skip)
	content.modulate = Color(1, 1, 1, 0)
	content.scale = Vector2(0.82, 0.82)
	content.pivot_offset = Vector2(260.0, 220.0)
	var intro := create_tween().set_parallel(true)
	intro.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(content, "modulate", Color.WHITE, 0.8)
	intro.tween_property(content, "scale", Vector2.ONE, 1.05)
	get_tree().create_timer(3.5).timeout.connect(_dismiss_splash)


func _dismiss_splash(immediate: bool = false) -> void:
	if splash_dismissed or splash_screen == null:
		return
	splash_dismissed = true
	if immediate:
		splash_screen.visible = false
		return
	var fade := create_tween()
	fade.tween_property(splash_screen, "modulate", Color(1, 1, 1, 0), 0.35)
	fade.finished.connect(func() -> void: splash_screen.visible = false)


func _toggle_pause_overlay() -> void:
	if connection_screen.visible:
		return
	pause_overlay.visible = not pause_overlay.visible
	network_world.input_blocked = pause_overlay.visible
	if offline_sandbox.visible:
		offline_sandbox.set_process(not pause_overlay.visible)
		offline_sandbox.set_physics_process(not pause_overlay.visible)


func _hide_pause_overlay() -> void:
	pause_overlay.visible = false
	network_world.input_blocked = false
	if offline_sandbox.visible:
		offline_sandbox.set_process(true)
		offline_sandbox.set_physics_process(true)


func _return_from_pause() -> void:
	_hide_pause_overlay()
	bridge.stop()
	_show_connection_screen("Returned to the main menu.")


func _connect_online() -> void:
	var port_text := port_field.text.strip_edges()
	if not port_text.is_valid_int():
		connection_status.text = "Port must be an integer from %d through %d." % [GameConstants.MIN_PORT, GameConstants.MAX_PORT]
		return
	var port := int(port_text)
	if port < GameConstants.MIN_PORT or port > GameConstants.MAX_PORT:
		connection_status.text = "Port must be from %d through %d." % [GameConstants.MIN_PORT, GameConstants.MAX_PORT]
		return
	var display_name := name_field.text.strip_edges()
	if not ServerLobby.is_valid_display_name(display_name):
		connection_status.text = NetworkProtocol.rejection_message(NetworkProtocol.REJECT_INVALID_NAME)
		return
	offline_sandbox.set_sandbox_active(false)
	network_world.set_network_active(false)
	connection_status.text = "Connecting to %s:%d…" % [host_field.text.strip_edges(), port]
	var error := bridge.start_client(host_field.text.strip_edges(), port, display_name)
	if error != OK:
		connection_status.text = bridge.last_error


func _play_offline() -> void:
	bridge.stop()
	latest_match_payload.clear()
	network_world.set_network_active(false)
	connection_screen.visible = false
	lobby_panel.visible = false
	match_panel.visible = false
	draft_panel.visible = false
	scoreboard_panel.visible = false
	results_panel.visible = false
	pause_overlay.visible = false
	settings_panel.visible = false
	win_overlay.visible = false
	offline_sandbox.set_sandbox_active(true)
	audio_director.set_context(&"gameplay")


func _disconnect_online() -> void:
	bridge.stop()
	_show_connection_screen("Disconnected. Ready to reconnect.")


func _show_connection_screen(message: String, is_error: bool = false) -> void:
	if bridge.role == NetworkBridge.Role.CLIENT:
		bridge.stop()
	network_world.set_network_active(false)
	offline_sandbox.set_sandbox_active(false)
	latest_match_payload.clear()
	active_offer_token = ""
	active_offer_deadline = -1
	connection_screen.visible = true
	lobby_panel.visible = false
	match_panel.visible = false
	draft_panel.visible = false
	scoreboard_panel.visible = false
	results_panel.visible = false
	pause_overlay.visible = false
	settings_panel.visible = false
	win_overlay.visible = false
	network_world.input_blocked = false
	connection_status.text = message
	connection_status.add_theme_color_override("font_color", Color("ff7994") if is_error else Color("aebbd4"))
	audio_director.set_context(&"menu")


func _on_connected(peer_id: int) -> void:
	connection_screen.visible = false
	lobby_panel.visible = true
	network_world.set_network_active(true)
	connection_status.text = "Connected as peer %d." % peer_id
	connection_status.add_theme_color_override("font_color", Color("62ff9b"))
	audio_director.set_context(&"lobby")


func _on_lobby_state(state: Dictionary) -> void:
	var lines: PackedStringArray = []
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		var badges: PackedStringArray = []
		if int(player.peer_id) == int(state.leader_id):
			badges.append("leader")
		if bool(player.spectator):
			badges.append("spectator")
		if bool(player.get("is_npc", false)):
			badges.append("NPC")
		var suffix := " [%s]" % ", ".join(badges) if not badges.is_empty() else ""
		lines.append("%s%s" % [player.display_name, suffix])
	var npc_count := int(state.get("npc_count", 0))
	var total_count := (state.get("players", []) as Array).size()
	lobby_panel.visible = not bool(state.get("match_active", false))
	lobby_label.text = "Players %d/%d · Humans %d · NPCs %d\n%s\n%s" % [total_count, state.get("player_limit", 32), total_count - npc_count, npc_count, "\n".join(lines), "Match active" if state.get("match_active", false) else "NPCs fill open seats when Force Start is pressed" if state.get("npcs_enabled", false) else "Waiting in lobby"]
	var is_leader := int(state.get("leader_id", 0)) == bridge.local_peer_id
	_applying_lobby_state = true
	rounds_control.value = int(state.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN))
	player_limit_control.max_value = int(state.get("server_capacity", GameConstants.MAX_PLAYERS))
	player_limit_control.value = int(state.get("player_limit", GameConstants.DEFAULT_MAX_PLAYERS))
	npcs_button.button_pressed = bool(state.get("npcs_enabled", false))
	_applying_lobby_state = false
	var settings_editable := is_leader and not bool(state.get("match_active", false))
	rounds_control.editable = settings_editable
	player_limit_control.editable = settings_editable
	npcs_button.disabled = not settings_editable
	var can_supply_opponent := total_count >= GameConstants.MIN_PLAYERS or bool(state.get("npcs_enabled", false))
	start_button.disabled = not settings_editable or not can_supply_opponent


func _on_rounds_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_lobby_config(roundi(value))


func _on_player_limit_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_player_limit(roundi(value))


func _on_npcs_toggled(enabled: bool) -> void:
	if not _applying_lobby_state:
		bridge.send_npcs_enabled(enabled)


func _on_match_event(event_type: StringName, _server_tick: int, payload: Dictionary) -> void:
	if event_type == &"REQUEST_REJECTED":
		lobby_label.text += "\nRejected: %s" % payload.get("message", "Unknown request")
		if draft_panel.visible and not active_offer_token.is_empty():
			for draft_button in draft_buttons:
				if draft_button.visible:
					draft_button.disabled = false
					draft_button.text = draft_button.text.trim_suffix("\n\nSELECTED")
	elif event_type == &"DRAFT_OFFER":
		_show_draft_offer(payload)
	elif event_type == &"STATE_CHANGED":
		var previous_state := String(latest_match_payload.get("state_name", last_state_name))
		latest_match_payload = payload.duplicate(true)
		network_world.apply_match_state(payload)
		_handle_state_presentation(previous_state, String(payload.get("state_name", "LOBBY")), payload)
		_update_match_presentation()
	elif event_type == &"DRAFT_RESOLVED":
		latest_match_payload["builds"] = payload.get("builds", {})
		active_offer_token = ""
		active_offer_deadline = -1
		draft_panel.visible = false
	elif event_type == &"PLAYER_ELIMINATED":
		var alive_peer_ids: Array = (latest_match_payload.get("alive_peer_ids", []) as Array).duplicate()
		for peer_value in payload.get("peer_ids", []):
			alive_peer_ids.erase(int(peer_value))
		latest_match_payload["alive_peer_ids"] = alive_peer_ids


func _process(_delta: float) -> void:
	if not latest_match_payload.is_empty():
		_update_match_presentation()
	if scoreboard_panel != null:
		scoreboard_panel.visible = match_panel.visible and Input.is_action_pressed("scoreboard")
		if scoreboard_panel.visible:
			_update_scoreboard()
	_update_timed_audio()


func _show_draft_offer(payload: Dictionary) -> void:
	active_offer_token = String(payload.get("offer_token", ""))
	active_offer_deadline = int(payload.get("deadline_tick", -1))
	var card_ids := payload.get("card_ids", []) as Array
	for index in draft_buttons.size():
		var button := draft_buttons[index]
		button.visible = index < card_ids.size()
		button.disabled = false
		button.set_meta("card_id", StringName(card_ids[index]) if index < card_ids.size() else &"")
		if index >= card_ids.size():
			continue
		var card := card_catalog.get_card(StringName(card_ids[index]))
		var current_stacks := _local_build_stack(card.card_id) if card != null else 0
		button.text = "%d\n\n%s\n%s\n%s · %.0f%% DROP\n\n%s\n\nSTACK %d → %d / %d" % [
			index + 1,
			card.display_name,
			card.category_name().to_upper(),
			card.rarity_name().to_upper(),
			card.rarity_drop_chance(),
			card.description,
			current_stacks,
			current_stacks + 1,
			card.max_stacks,
		] if card != null else String(card_ids[index])
		if card != null:
			var category_color := _draft_category_color(card.category)
			button.add_theme_color_override("font_color", card.rarity_color())
			button.add_theme_stylebox_override("normal", _draft_card_style(category_color, false))
			button.add_theme_stylebox_override("hover", _draft_card_style(category_color.lightened(0.18), true))
			button.add_theme_stylebox_override("pressed", _draft_card_style(category_color.lightened(0.28), true))
			button.add_theme_stylebox_override("focus", _draft_card_style(category_color.lightened(0.3), true))
			button.add_theme_stylebox_override("disabled", _draft_card_style(category_color.darkened(0.35), false))
			button.tooltip_text = "%s — %s (%.0f%% rarity-tier chance) — %s" % [card.display_name, card.rarity_name(), card.rarity_drop_chance(), card.description]
	draft_panel.visible = true
	match_panel.visible = true
	_update_match_presentation()


func _select_draft_card(index: int) -> void:
	if index < 0 or index >= draft_buttons.size():
		return
	var button := draft_buttons[index]
	if not button.visible or button.disabled:
		return
	var card_id := button.get_meta("card_id", &"") as StringName
	if card_id.is_empty():
		return
	bridge.send_card_selection(active_offer_token, card_id)
	audio_director.play_sfx(&"card_lock", "%s:%s" % [active_offer_token, card_id])
	for draft_button in draft_buttons:
		draft_button.disabled = true
	button.text += "\n\nSELECTED"
	var selected_color := Color("42e8ff")
	button.add_theme_stylebox_override("disabled", _draft_card_style(selected_color, true))


func _update_match_presentation() -> void:
	var state_name := String(latest_match_payload.get("state_name", "LOBBY"))
	if state_name == "LOBBY":
		match_panel.visible = false
		draft_panel.visible = false
		_set_win_screen_visible(false)
		lobby_panel.visible = bridge.role == NetworkBridge.Role.CLIENT
		return
	lobby_panel.visible = false
	match_panel.visible = true
	if state_name != "DRAFT":
		draft_panel.visible = false
	_set_win_screen_visible(state_name == "MATCH_RESULT")
	var deadline := int(latest_match_payload.get("deadline_tick", -1))
	if state_name == "DRAFT" and active_offer_deadline >= 0:
		deadline = active_offer_deadline
	var seconds_left := maxf(float(deadline - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0) if deadline >= 0 else 0.0
	var status := "%s · Round %d · Heat %d" % [
		state_name.replace("_", " ").capitalize(),
		int(latest_match_payload.get("round_number", 0)),
		int(latest_match_payload.get("heat_number", 0)),
	]
	if deadline >= 0:
		status += " · %.1fs" % seconds_left
	if state_name == "ACTIVE_HEAT":
		status += " · %d alive" % (latest_match_payload.get("alive_peer_ids", []) as Array).size()
		var overtime_tick := int(latest_match_payload.get("overtime_start_tick", -1))
		if overtime_tick >= 0:
			status += " · OVERTIME" if network_world.latest_server_tick >= overtime_tick else " · overtime in %.0fs" % maxf(float(overtime_tick - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0)
	elif state_name == "HEAT_RESULT":
		status += " · %s" % ("Tie" if bool(latest_match_payload.get("tied_heat", false)) else "%s wins heat" % _player_name(int(latest_match_payload.get("last_heat_winner", 0))))
	elif state_name == "ROUND_RESULT":
		status += " · %s wins round" % _player_name(int(latest_match_payload.get("last_round_winner", 0)))
	elif state_name == "MATCH_RESULT":
		status = "★ VICTORY · %s ★ · returning to lobby in %.1fs" % [_player_name(int(latest_match_payload.get("match_winner", 0))), seconds_left]
		results_label.text = _results_text(seconds_left)
	match_label.text = status
	if state_name == "DRAFT":
		draft_title.text = "CHOOSE 1 OF 5 UPGRADES · %.1fs · CLICK OR PRESS 1–5" % seconds_left


func _draft_category_color(category: int) -> Color:
	match category:
		CardDefinition.Category.SHIP:
			return Color("38d9ff")
		CardDefinition.Category.SHIELD:
			return Color("ae7cff")
		_:
			return Color("ff4fd8")


func _draft_card_style(color: Color, emphasized: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.72), 0.94 if emphasized else 0.86)
	style.border_color = Color(color, 0.95 if emphasized else 0.62)
	style.set_border_width_all(3 if emphasized else 2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


func _local_build_stack(card_id: StringName) -> int:
	var builds := latest_match_payload.get("builds", {}) as Dictionary
	var local_build := builds.get(bridge.local_peer_id, {}) as Dictionary
	return int(local_build.get(card_id, 0))


func _player_name(peer_id: int) -> String:
	for player_value in bridge.latest_lobby_state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == peer_id:
			return String(player.get("display_name", "Pilot"))
	return "Pilot %d" % peer_id


func _update_scoreboard() -> void:
	scoreboard_label.text = _scoreboard_text("SCOREBOARD")


func _scoreboard_text(title: String) -> String:
	var lines := PackedStringArray([title, "", "PILOT                         HEATS  ROUNDS  BUILD"])
	var scores := latest_match_payload.get("scores", {}) as Dictionary
	var builds := latest_match_payload.get("builds", {}) as Dictionary
	var participant_ids := latest_match_payload.get("participant_peer_ids", []) as Array
	for peer_value in participant_ids:
		var peer_id := int(peer_value)
		var score := scores.get(peer_id, {}) as Dictionary
		var build := builds.get(peer_id, {}) as Dictionary
		var card_parts := PackedStringArray()
		var card_ids := build.keys()
		card_ids.sort()
		for card_value in card_ids:
			var card_id := StringName(card_value)
			var card := card_catalog.get_card(card_id)
			card_parts.append("%s ×%d" % [card.display_name if card != null else String(card_id), int(build[card_value])])
		lines.append("%-28s  %d      %d       %s" % [
			_player_name(peer_id),
			int(score.get("heat_wins", 0)),
			int(score.get("round_wins", 0)),
			", ".join(card_parts) if not card_parts.is_empty() else "—",
		])
	lines.append("\nHold Tab to inspect · builds are public after each draft")
	return "\n".join(lines)


func _results_text(seconds_left: float) -> String:
	var winner_id := int(latest_match_payload.get("match_winner", 0))
	var headline := "✦ ✦ ✦\nVICTORY\n%s\nSUPER STAR CHAMPION\n✦ ✦ ✦\n\n" % _player_name(winner_id)
	var standings := _scoreboard_text("FINAL STANDINGS")
	return "%s%s\n\nReturning everyone to the lobby in %.1f seconds" % [headline, standings, seconds_left]


func _handle_state_presentation(previous_state: String, state_name: String, payload: Dictionary) -> void:
	last_state_name = state_name
	if state_name == "LOBBY":
		audio_director.set_context(&"lobby")
		_set_win_screen_visible(false)
		return
	audio_director.set_context(&"win" if state_name == "MATCH_RESULT" else &"gameplay")
	if previous_state == "LOBBY" and state_name == "DRAFT":
		audio_director.reset_match_deduplication()
	if state_name == "COUNTDOWN":
		last_countdown_second = -1
		overtime_announced = false
	elif state_name == "ROUND_RESULT":
		audio_director.play_sfx(&"round_win", str(payload.get("entered_tick", 0)))
	elif state_name == "MATCH_RESULT":
		audio_director.play_sfx(&"match_win", str(payload.get("entered_tick", 0)))


func _set_win_screen_visible(visible: bool) -> void:
	if win_overlay != null:
		win_overlay.visible = visible
	if results_panel != null:
		results_panel.visible = visible


func _update_timed_audio() -> void:
	if latest_match_payload.is_empty():
		return
	var state_name := String(latest_match_payload.get("state_name", "LOBBY"))
	if state_name == "COUNTDOWN":
		var deadline := int(latest_match_payload.get("deadline_tick", -1))
		var second := ceili(maxf(float(deadline - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0))
		if second != last_countdown_second and second >= 1 and second <= 3:
			last_countdown_second = second
			audio_director.play_sfx(&"countdown", "%d:%d" % [deadline, second])
	elif state_name == "ACTIVE_HEAT" and not overtime_announced:
		var overtime_tick := int(latest_match_payload.get("overtime_start_tick", -1))
		if overtime_tick >= 0 and network_world.latest_server_tick >= overtime_tick:
			overtime_announced = true
			audio_director.play_sfx(&"overtime", str(overtime_tick))


func _on_world_presentation_event(event_name: StringName, payload: Dictionary) -> void:
	var unique_key := "%s:%s" % [payload.get("owner_id", 0), payload.get("shot_sequence", 0)] if event_name in [&"fire", &"beam_fire"] else "%s:%s" % [payload.get("peer_id", 0), payload.get("server_tick", 0)]
	audio_director.play_sfx(event_name, unique_key)


func _configure_interface_theme() -> void:
	interface_theme.set_color("font_color", "Button", Color("e8f5ff"))
	interface_theme.set_color("font_hover_color", "Button", Color.WHITE)
	interface_theme.set_color("font_pressed_color", "Button", Color("fff36a"))
	interface_theme.set_stylebox("normal", "Button", _button_style(Color("42e8ff"), 0.2))
	interface_theme.set_stylebox("hover", "Button", _button_style(Color("42e8ff"), 0.42))
	interface_theme.set_stylebox("pressed", "Button", _button_style(Color("d39cff"), 0.5))
	interface_theme.set_stylebox("disabled", "Button", _button_style(Color("53627d"), 0.2))
	interface_theme.set_stylebox("normal", "LineEdit", _input_style())
	interface_theme.set_stylebox("focus", "LineEdit", _input_style(Color("42e8ff")))
	interface_theme.set_color("font_color", "LineEdit", Color("e8f5ff"))


func _panel_style(accent: Color, opacity: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Color("071024"), opacity)
	style.border_color = Color(accent, 0.86)
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(accent, 0.16)
	style.shadow_size = 12
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style


func _button_style(accent: Color, opacity: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.darkened(0.7), 0.78)
	style.border_color = Color(accent, opacity + 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _input_style(accent: Color = Color("53627d")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0d1730")
	style.border_color = Color(accent, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style


func _on_rejected(_reason: StringName, message: String) -> void:
	_show_connection_screen("CONNECTION REJECTED\n%s\nCheck the server settings, then try again." % message, true)


func _on_connection_lost(message: String) -> void:
	_show_connection_screen("CONNECTION LOST\n%s\nYou can reconnect from this screen." % message, true)


func _exit_tree() -> void:
	if bridge != null:
		bridge.stop()
