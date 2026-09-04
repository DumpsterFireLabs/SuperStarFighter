extends Node

const DraftScreenControllerScript = preload("res://src/client/ui/draft_screen_controller.gd")
const StandingsScreenControllerScript = preload("res://src/client/ui/standings_screen_controller.gd")
const RESULTS_ACTION_EXPLANATION = StandingsScreenControllerScript.RESULTS_ACTION_EXPLANATION
const CardDetailsText = preload("res://src/client/ui/card_details_text.gd")

const SettingsControllerScript = preload("res://src/client/ui/settings_controller.gd")
const ConnectionControllerScript = preload("res://src/client/ui/connection_controller.gd")

var draft_controller := DraftScreenControllerScript.new()
var standings_controller := StandingsScreenControllerScript.new()

var settings_controller := SettingsControllerScript.new()
var connection_controller := ConnectionControllerScript.new()

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const CardHoverButtonScript = preload("res://src/client/ui/card_hover_button.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const StandingsModelScript = preload("res://src/client/presentation/standings_model.gd")
const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const CROSSHAIR_TEXTURE: Texture2D = preload("res://assets/ui/crosshair.svg")
const DUMPSTER_FIRE_LABS_TEXTURE: Texture2D = preload("res://assets/ui/dumpster_fire_labs.png")
const STUDIO_SPLASH_AUTO_ADVANCE_SECONDS: float = 4.0
const SPLASH_AUTO_ADVANCE_SECONDS: float = 10.0
const HEAT_BEGIN_LEAD_SECONDS: float = 0.10
const HEAT_BEGIN_FADE_SECONDS: float = 0.10
const WindowModeOption = SettingsControllerScript.WindowModeOption
const WINDOW_MODE_LABELS = SettingsControllerScript.WINDOW_MODE_LABELS
const RESOLUTION_OPTIONS = SettingsControllerScript.RESOLUTION_OPTIONS


var bridge: NetworkBridge
var network_world: NetworkWorldView
var offline_sandbox: OfflineSandbox
var audio_director: AudioDirector
var input_profiles: Node
## Compatibility handles for existing capture/test tools. Screen state lives in its controller.
var gameplay_cursor_canvas: CanvasLayer
var gameplay_cursor: Sprite2D


var match_panel: PanelContainer
var match_label: Label
var heat_intro_panel: PanelContainer
var heat_intro_kicker: Label
var heat_intro_title: Label
var heat_intro_subtitle: Label
var draft_panel: PanelContainer:
	get: return draft_controller.draft_panel
	set(value): draft_controller.draft_panel = value
var draft_title: Label:
	get: return draft_controller.draft_title
	set(value): draft_controller.draft_title = value
var draft_buttons: Array[Button]:
	get: return draft_controller.draft_buttons
	set(value): draft_controller.draft_buttons = value
var draft_rarity_labels: Array[Label]:
	get: return draft_controller.draft_rarity_labels
	set(value): draft_controller.draft_rarity_labels = value
var draft_bye_label: Label:
	get: return draft_controller.draft_bye_label
	set(value): draft_controller.draft_bye_label = value
var draft_confirmation_row: HBoxContainer:
	get: return draft_controller.draft_confirmation_row
	set(value): draft_controller.draft_confirmation_row = value
var draft_confirmation_label: Label:
	get: return draft_controller.draft_confirmation_label
	set(value): draft_controller.draft_confirmation_label = value
var draft_confirm_button: Button:
	get: return draft_controller.draft_confirm_button
	set(value): draft_controller.draft_confirm_button = value
var draft_change_button: Button:
	get: return draft_controller.draft_change_button
	set(value): draft_controller.draft_change_button = value
var scoreboard_panel: PanelContainer:
	get: return standings_controller.scoreboard_panel
	set(value): standings_controller.scoreboard_panel = value
var scoreboard_label: Label:
	get: return standings_controller.scoreboard_label
	set(value): standings_controller.scoreboard_label = value
var scoreboard_context_label: Label:
	get: return standings_controller.scoreboard_context_label
	set(value): standings_controller.scoreboard_context_label = value
var scoreboard_media_label: Label:
	get: return standings_controller.scoreboard_media_label
	set(value): standings_controller.scoreboard_media_label = value
var scoreboard_hill_heading: Label:
	get: return standings_controller.scoreboard_hill_heading
	set(value): standings_controller.scoreboard_hill_heading = value
var scoreboard_rows_container: VBoxContainer:
	get: return standings_controller.scoreboard_rows_container
	set(value): standings_controller.scoreboard_rows_container = value
var scoreboard_hint_label: Label:
	get: return standings_controller.scoreboard_hint_label
	set(value): standings_controller.scoreboard_hint_label = value
var scoreboard_open: bool:
	get: return standings_controller.scoreboard_open
	set(value): standings_controller.scoreboard_open = value
var _scoreboard_rows_dirty: bool:
	get: return standings_controller._scoreboard_rows_dirty
	set(value): standings_controller._scoreboard_rows_dirty = value
var results_panel: PanelContainer:
	get: return standings_controller.results_panel
	set(value): standings_controller.results_panel = value
var results_label: Label:
	get: return standings_controller.results_label
	set(value): standings_controller.results_label = value
var results_winner_label: Label:
	get: return standings_controller.results_winner_label
	set(value): standings_controller.results_winner_label = value
var results_standings_container: VBoxContainer:
	get: return standings_controller.results_standings_container
	set(value): standings_controller.results_standings_container = value
var results_rematch_button: Button:
	get: return standings_controller.results_rematch_button
	set(value): standings_controller.results_rematch_button = value
var results_action_note: Label:
	get: return standings_controller.results_action_note
	set(value): standings_controller.results_action_note = value
var _rematch_requested: bool:
	get: return standings_controller._rematch_requested
	set(value): standings_controller._rematch_requested = value
var results_extend_button: Button:
	get: return standings_controller.results_extend_button
	set(value): standings_controller.results_extend_button = value
var results_return_button: Button:
	get: return standings_controller.results_return_button
	set(value): standings_controller.results_return_button = value
var _results_rows_dirty: bool:
	get: return standings_controller._results_rows_dirty
	set(value): standings_controller._results_rows_dirty = value
var _extend_match_requested: bool:
	get: return standings_controller._extend_match_requested
	set(value): standings_controller._extend_match_requested = value
var _return_to_lobby_requested: bool:
	get: return standings_controller._return_to_lobby_requested
	set(value): standings_controller._return_to_lobby_requested = value
var win_overlay: Control:
	get: return standings_controller.win_overlay
	set(value): standings_controller.win_overlay = value
var pause_overlay: PanelContainer
var pause_title: Label
var settings_panel: Control:
	get:
		return settings_controller.settings_panel
var settings_tabs: TabContainer:
	get:
		return settings_controller.settings_tabs
var accessibility_preferences:
	get:
		return settings_controller.accessibility_preferences
var hud_scale_control: HSlider:
	get:
		return settings_controller.hud_scale_control

var reduced_shake_control: CheckButton:
	get:
		return settings_controller.reduced_shake_control
var reduced_flashes_control: CheckButton:
	get:
		return settings_controller.reduced_flashes_control


var window_mode_control: OptionButton:
	get:
		return settings_controller.window_mode_control
var resolution_control: OptionButton:
	get:
		return settings_controller.resolution_control

var control_scheme_control: OptionButton:
	get:
		return settings_controller.control_scheme_control
var flight_mode_control: OptionButton:
	get:
		return settings_controller.flight_mode_control


var binding_rows: GridContainer:
	get:
		return settings_controller.binding_rows


var current_window_mode: int:
	get:
		return settings_controller.current_window_mode
	set(value):
		settings_controller.current_window_mode = value
var current_resolution: Vector2i:
	get:
		return settings_controller.current_resolution
	set(value):
		settings_controller.current_resolution = value

var settings_return_to_pause: bool = false
var settings_return_to_lobby: bool = false
var credits_panel: Control
var credits_button: Button
var splash_screen: Control
var studio_splash: Control
var game_splash: Control
var splash_neon_backdrop: Control
var splash_auto_timer: Timer
var splash_stage: int = 0
var splash_transitioning: bool = false
var splash_dismissed: bool = false
var card_catalog := CardCatalog.create_default()
var active_offer_token: String:
	get: return draft_controller.active_offer_token
	set(value): draft_controller.active_offer_token = value
var active_offer_deadline: int:
	get: return draft_controller.active_offer_deadline
	set(value): draft_controller.active_offer_deadline = value
var pending_draft_index: int:
	get: return draft_controller.pending_draft_index
	set(value): draft_controller.pending_draft_index = value
var latest_match_payload: Dictionary = {}

var interface_theme: Theme
var last_countdown_second: int = -1
var overtime_announced: bool = false
var last_state_name: String = "LOBBY"
var pause_resume_button: Button
var pause_disconnect_button: Button
var f2_return_confirmation: ConfirmationDialog
var _application_has_focus: bool = true
var _disconnect_in_progress: bool = false


var _native_gameplay_cursor_active: bool = false


func _init() -> void:
	draft_controller.initialize(self)
	draft_controller.name = "DraftScreenController"
	add_child(draft_controller)
	standings_controller.initialize(self)
	standings_controller.name = "StandingsScreenController"
	add_child(standings_controller)
	settings_controller.initialize(self)
	settings_controller.name = "SettingsController"
	add_child(settings_controller)
	connection_controller.initialize(self)
	connection_controller.name = "ConnectionController"
	add_child(connection_controller)


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	offline_sandbox = $OfflineSandbox as OfflineSandbox
	offline_sandbox.set_sandbox_active(false)
	input_profiles = InputProfileManagerScript.new()
	input_profiles.name = "InputProfileManager"
	input_profiles.scheme_changed.connect(settings_controller._on_control_scheme_changed)
	input_profiles.flight_mode_changed.connect(settings_controller._on_flight_mode_changed)
	input_profiles.bindings_changed.connect(settings_controller._on_control_bindings_changed)
	input_profiles.controller_connections_changed.connect(settings_controller._update_controller_status)
	add_child(input_profiles)
	offline_sandbox.set_input_profile_manager(input_profiles)
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
	offline_sandbox.presentation_event.connect(_on_world_presentation_event)
	settings_controller._load_video_settings()
	network_world = NetworkWorldView.new()
	network_world.name = "NetworkWorld"
	add_child(network_world)
	network_world.setup(bridge, input_profiles)
	settings_controller.accessibility_preferences.load_settings()
	_apply_accessibility_settings()
	network_world.presentation_event.connect(_on_world_presentation_event)
	connection_controller._create_connection_ui(configuration)
	connection_controller.start_discovery()
	_create_match_ui()
	_create_pause_overlay()
	_create_f2_return_confirmation()
	settings_controller._create_settings_overlay()
	_create_credits_overlay()
	_create_gameplay_cursor()
	_create_splash_screen()
	audio_director.set_context(&"menu")
	print("SSF_MODE_READY=client port=%d sandbox=offline_combat network=enet" % configuration.get("port", GameConstants.DEFAULT_PORT))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_has_focus = false
		if gameplay_cursor != null:
			gameplay_cursor.visible = false
		if DisplayServer.get_name() != "headless":
			_set_native_gameplay_cursor(false)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_application_has_focus = true
		call_deferred("_update_pointer_visibility")


var card_inspector: CanvasLayer


func _inspect_card(button: CardHoverButton) -> void:
	card_inspector.open(button)
	network_world.input_blocked = true


func _unhandled_input(event: InputEvent) -> void:
	if draft_panel != null and draft_panel.visible and pending_draft_index >= 0 and (event.is_action_pressed("pause_overlay") or event.is_action_pressed(&"ui_cancel")) and not (event is InputEventKey and event.echo):
		_cancel_draft_confirmation()
		get_viewport().set_input_as_handled()
		return
	if (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_overlay")) and not (event is InputEventKey and event.echo):
		if credits_panel != null and credits_panel.visible:
			_hide_credits()
			get_viewport().set_input_as_handled()
			return
		if connection_controller.dismiss_modal():
			get_viewport().set_input_as_handled()
			return
		if settings_controller.settings_panel != null and settings_controller.settings_panel.visible:
			_hide_settings()
			get_viewport().set_input_as_handled()
			return
		if pause_overlay != null and pause_overlay.visible:
			_hide_pause_overlay()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"pause_overlay"):
			_toggle_pause_overlay()
			get_viewport().set_input_as_handled()
			return
	if pause_overlay != null and pause_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		_request_f2_return_to_menu()
		get_viewport().set_input_as_handled()
		return
	if draft_panel != null and draft_panel.visible:
		for index in draft_buttons.size():
			if event.is_action_pressed("draft_%d" % (index + 1)):
				_select_draft_card(index)
				get_viewport().set_input_as_handled()
				break


func _input(event: InputEvent) -> void:
	if card_inspector != null and card_inspector.visible:
		if event.is_action_released(&"scoreboard") and scoreboard_open:
			card_inspector.close(false)
			_set_scoreboard_open(false)
			get_viewport().set_input_as_handled()
		else:
			card_inspector.handle_input(event)
		return
	if settings_controller.capture_input(event):
		return
	if splash_screen != null and splash_screen.visible and _is_start_input(event):
		_dismiss_splash()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"scoreboard") and not (event is InputEventKey and event.echo):
		if _scoreboard_available():
			_set_scoreboard_open(true)
			get_viewport().set_input_as_handled()
	elif event.is_action_released(&"scoreboard"):
		if scoreboard_open:
			_set_scoreboard_open(false)
			get_viewport().set_input_as_handled()


func _is_start_input(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65)


func _create_match_ui() -> void:
	card_inspector = preload("res://src/client/ui/card_inspector.gd").new()
	add_child(card_inspector)
	card_inspector.closed.connect(func() -> void: network_world.input_blocked = pause_overlay != null and pause_overlay.visible)
	match_panel = PanelContainer.new()
	match_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	match_panel.position = Vector2(-380.0, 20.0)
	match_panel.custom_minimum_size = Vector2(760.0, 112.0)
	match_panel.theme = interface_theme
	match_panel.add_theme_stylebox_override("panel", _panel_style(DesignTokensScript.INTERACTIVE, 0.9))
	match_panel.visible = false
	connection_controller.connection_canvas.add_child(match_panel)
	match_label = Label.new()
	match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_label.add_theme_font_size_override("font_size", 24)
	match_label.add_theme_color_override("font_color", Color("73f7ff"))
	match_panel.add_child(match_label)

	heat_intro_panel = PanelContainer.new()
	heat_intro_panel.name = "HeatIntro"
	heat_intro_panel.set_anchors_preset(Control.PRESET_CENTER)
	heat_intro_panel.position = Vector2(-300.0, -125.0)
	heat_intro_panel.custom_minimum_size = Vector2(600.0, 250.0)
	heat_intro_panel.theme = interface_theme
	heat_intro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_intro_panel.add_theme_stylebox_override("panel", _heat_intro_style())
	heat_intro_panel.visible = false
	connection_controller.connection_canvas.add_child(heat_intro_panel)
	var heat_intro_content := VBoxContainer.new()
	heat_intro_content.alignment = BoxContainer.ALIGNMENT_CENTER
	heat_intro_content.add_theme_constant_override("separation", 8)
	heat_intro_panel.add_child(heat_intro_content)
	heat_intro_kicker = Label.new()
	heat_intro_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heat_intro_kicker.add_theme_font_size_override("font_size", 18)
	heat_intro_kicker.add_theme_color_override("font_color", Color("d39cff"))
	heat_intro_content.add_child(heat_intro_kicker)
	heat_intro_title = Label.new()
	heat_intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heat_intro_title.add_theme_font_size_override("font_size", 72)
	heat_intro_title.add_theme_color_override("font_color", Color("fff36a"))
	heat_intro_content.add_child(heat_intro_title)
	heat_intro_subtitle = Label.new()
	heat_intro_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heat_intro_subtitle.add_theme_font_size_override("font_size", 20)
	heat_intro_subtitle.add_theme_color_override("font_color", Color("bdeeff"))
	heat_intro_content.add_child(heat_intro_subtitle)

	draft_controller.create_ui()
	standings_controller.create_ui()


func _create_draft_card_content(button: Button, index: int) -> void:
	draft_controller._create_draft_card_content(button, index)


func _create_pause_overlay() -> void:
	pause_overlay = PanelContainer.new()
	pause_overlay.set_anchors_preset(Control.PRESET_CENTER)
	pause_overlay.position = Vector2(-320.0, -220.0)
	pause_overlay.custom_minimum_size = Vector2(640.0, 440.0)
	pause_overlay.theme = interface_theme
	pause_overlay.add_theme_stylebox_override("panel", _panel_style(DesignTokensScript.BRAND_MAGENTA, 0.98))
	pause_overlay.visible = false
	connection_controller.connection_canvas.add_child(pause_overlay)
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
	pause_resume_button = Button.new()
	pause_resume_button.text = "Resume"
	pause_resume_button.theme_type_variation = &"PrimaryButton"
	pause_resume_button.custom_minimum_size.y = 58.0
	pause_resume_button.pressed.connect(_hide_pause_overlay)
	content.add_child(pause_resume_button)
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.theme_type_variation = &"SecondaryButton"
	settings_button.custom_minimum_size.y = 58.0
	settings_button.pressed.connect(_show_settings.bind(true))
	content.add_child(settings_button)
	pause_disconnect_button = Button.new()
	pause_disconnect_button.name = "PauseDisconnectButton"
	pause_disconnect_button.text = "Disconnect / Return to Menu"
	pause_disconnect_button.theme_type_variation = &"DangerButton"
	pause_disconnect_button.custom_minimum_size.y = 58.0
	pause_disconnect_button.pressed.connect(_return_from_pause)
	content.add_child(pause_disconnect_button)
	var quit_button := Button.new()
	quit_button.text = "Quit Game"
	quit_button.theme_type_variation = &"DangerButton"
	quit_button.custom_minimum_size.y = 58.0
	quit_button.pressed.connect(get_tree().quit)
	content.add_child(quit_button)


func _create_f2_return_confirmation() -> void:
	f2_return_confirmation = ConfirmationDialog.new()
	f2_return_confirmation.title = "LEAVE CURRENT GAME?"
	f2_return_confirmation.ok_button_text = "RETURN TO MAIN MENU"
	f2_return_confirmation.cancel_button_text = "STAY IN GAME"
	f2_return_confirmation.exclusive = true
	f2_return_confirmation.theme = interface_theme
	f2_return_confirmation.confirmed.connect(_confirm_f2_return_to_menu)
	f2_return_confirmation.canceled.connect(_cancel_f2_return_to_menu)
	connection_controller.connection_canvas.add_child(f2_return_confirmation)
	f2_return_confirmation.get_ok_button().theme_type_variation = &"DangerButton"


func _change_accessibility_setting(key: String, value: Variant) -> void:
	settings_controller._change_accessibility_setting(key, value)


func _apply_accessibility_settings() -> void:
	settings_controller.apply_accessible_theme()
	if network_world != null:
		network_world.apply_accessibility_settings(settings_controller.accessibility_preferences.values)
	if offline_sandbox != null and offline_sandbox.has_method("apply_accessibility_settings"):
		offline_sandbox.apply_accessibility_settings(settings_controller.accessibility_preferences.values)


func _refresh_input_settings_ui() -> void:
	settings_controller._refresh_input_settings_ui()


func _refresh_control_prompts() -> void:
	if scoreboard_hint_label != null:
		scoreboard_hint_label.text = "HOLD %s · ARROWS SELECT · I / Y INSPECT · THE MATCH CONTINUES" % input_profiles.binding_text(&"scoreboard").to_upper()


func _update_resolution_control_state() -> void:
	settings_controller._update_resolution_control_state()


func _show_settings(return_to_pause: bool) -> void:
	settings_return_to_pause = return_to_pause
	settings_return_to_lobby = not return_to_pause and connection_controller.lobby_panel != null and connection_controller.lobby_panel.visible
	if pause_overlay != null:
		pause_overlay.visible = false
	settings_controller.settings_panel.visible = true
	settings_controller._refresh_input_settings_ui()
	if network_world != null:
		network_world.input_blocked = return_to_pause
	settings_controller._on_settings_tab_changed(settings_controller.settings_tabs.current_tab)


func _hide_settings() -> void:
	settings_controller._cancel_binding_capture()
	settings_controller.settings_panel.visible = false
	if settings_return_to_pause and not connection_controller.connection_screen.visible:
		pause_overlay.visible = true
		network_world.input_blocked = true
		pause_resume_button.grab_focus()
	elif settings_return_to_lobby and connection_controller.lobby_panel != null and connection_controller.lobby_panel.visible:
		network_world.input_blocked = false
		connection_controller.lobby_settings_button.grab_focus()
	else:
		network_world.input_blocked = false
		if connection_controller.connection_screen.visible and connection_controller.connection_primary_button != null:
			connection_controller.connection_primary_button.grab_focus()
	settings_return_to_pause = false
	settings_return_to_lobby = false


func _create_credits_overlay() -> void:
	credits_panel = Control.new()
	credits_panel.name = "CreditsScreen"
	credits_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	credits_panel.visible = false
	connection_controller.connection_canvas.add_child(credits_panel)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color("02040d", 0.92)
	credits_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	credits_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960.0, 610.0)
	panel.theme = interface_theme
	panel.add_theme_stylebox_override("panel", _panel_style(Color("ff8a3d"), 0.98))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	var kicker := Label.new()
	kicker.text = "✦  DUMPSTER FIRE LABS PRESENTS  ✦"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", 17)
	kicker.add_theme_color_override("font_color", Color("ffb45f"))
	content.add_child(kicker)
	var title := Label.new()
	title.text = "THANKS FOR PLAYING!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("fff1bf"))
	content.add_child(title)
	var thank_you := Label.new()
	thank_you.text = "To everyone who stepped into the arena—thank you for giving the game a shot.\nI set out to make the kind of game I’d have a blast playing with friends, whether at a LAN party or online.\nI hope you had as much fun playing—and testing—it as I did making it!"
	thank_you.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	thank_you.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thank_you.custom_minimum_size = Vector2(900.0, 0.0)
	thank_you.add_theme_font_size_override("font_size", 18)
	thank_you.add_theme_color_override("font_color", Color("f4fbff"))
	content.add_child(thank_you)
	_add_credit_block(content, "CREATED BY", "Graphite")
	_add_credit_block(content, "TESTERS", "Champ")
	_add_credit_block(content, "HONOURABLE MENTIONS", "Equip  ·  jbohack  ·  KingRat  ·  DoomGuy  ·  Adam  ·  WhackyJacky  ·  Hipu  ·  Krusty Dave  ·  NoPE  ·  OSINTI4L  ·  TurboDoink  ·  ChatGPT")
	var back_center := CenterContainer.new()
	content.add_child(back_center)
	var back_button := Button.new()
	back_button.text = "BACK TO MAIN MENU"
	back_button.theme_type_variation = &"PrimaryButton"
	back_button.custom_minimum_size = Vector2(300.0, 52.0)
	back_button.pressed.connect(_hide_credits)
	back_center.add_child(back_button)


func _add_credit_block(parent: VBoxContainer, role: String, names: String) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	var role_label := Label.new()
	role_label.text = role
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.add_theme_font_size_override("font_size", 15)
	role_label.add_theme_color_override("font_color", Color("73f7ff"))
	block.add_child(role_label)
	var names_label := Label.new()
	names_label.text = names
	names_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	names_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names_label.custom_minimum_size = Vector2(650.0, 0.0)
	names_label.add_theme_font_size_override("font_size", 24)
	names_label.add_theme_color_override("font_color", Color("f4fbff"))
	block.add_child(names_label)


func _show_credits() -> void:
	credits_panel.visible = true
	for child in credits_panel.find_children("*", "Button", true, false):
		(child as Button).grab_focus()
		break


func _hide_credits() -> void:
	credits_panel.visible = false
	if connection_controller.connection_screen.visible and credits_button != null:
		credits_button.grab_focus()


func _create_gameplay_cursor() -> void:
	gameplay_cursor_canvas = CanvasLayer.new()
	gameplay_cursor_canvas.name = "GameplayCursor"
	gameplay_cursor_canvas.layer = 30
	add_child(gameplay_cursor_canvas)
	gameplay_cursor = Sprite2D.new()
	gameplay_cursor.name = "Crosshair"
	gameplay_cursor.texture = CROSSHAIR_TEXTURE
	gameplay_cursor.centered = true
	gameplay_cursor.visible = false
	gameplay_cursor_canvas.add_child(gameplay_cursor)


func _create_splash_screen() -> void:
	var splash_canvas := CanvasLayer.new()
	splash_canvas.layer = 40
	splash_canvas.name = "SplashUI"
	add_child(splash_canvas)
	splash_screen = Control.new()
	splash_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_canvas.add_child(splash_screen)
	var studio_backdrop := ColorRect.new()
	studio_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio_backdrop.color = Color("1d3a3a")
	splash_screen.add_child(studio_backdrop)
	splash_neon_backdrop = NeonBackdrop.new()
	splash_neon_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_neon_backdrop.visible = false
	splash_screen.add_child(splash_neon_backdrop)
	studio_splash = Control.new()
	studio_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_screen.add_child(studio_splash)
	var studio_center := CenterContainer.new()
	studio_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio_splash.add_child(studio_center)
	var studio_content := VBoxContainer.new()
	studio_content.alignment = BoxContainer.ALIGNMENT_CENTER
	studio_content.add_theme_constant_override("separation", 12)
	studio_center.add_child(studio_content)
	var studio_logo := TextureRect.new()
	studio_logo.name = "DumpsterFireLabsLogo"
	studio_logo.texture = DUMPSTER_FIRE_LABS_TEXTURE
	studio_logo.custom_minimum_size = Vector2(470.0, 470.0)
	studio_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	studio_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	studio_content.add_child(studio_logo)
	var quote := Label.new()
	quote.name = "StudioQuote"
	quote.text = "“Now with 1000% more slop!”"
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.add_theme_font_size_override("font_size", 30)
	quote.add_theme_color_override("font_color", Color("ffe7a8"))
	studio_content.add_child(quote)
	var studio_skip := Label.new()
	studio_skip.text = "PRESS ANY INPUT TO CONTINUE"
	studio_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	studio_skip.add_theme_font_size_override("font_size", 16)
	studio_skip.add_theme_color_override("font_color", Color("7ee0bd"))
	studio_content.add_child(studio_skip)
	game_splash = Control.new()
	game_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_splash.visible = false
	splash_screen.add_child(game_splash)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_splash.add_child(center)
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
	skip.text = "PRESS ANY INPUT TO START"
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip.add_theme_font_size_override("font_size", 18)
	skip.add_theme_color_override("font_color", Color("73f7ff"))
	content.add_child(skip)
	studio_content.modulate = Color(1, 1, 1, 0)
	studio_content.scale = Vector2(0.88, 0.88)
	studio_content.pivot_offset = Vector2(235.0, 270.0)
	var intro := create_tween().set_parallel(true)
	intro.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(studio_content, "modulate", Color.WHITE, 0.8)
	intro.tween_property(studio_content, "scale", Vector2.ONE, 1.05)
	splash_auto_timer = Timer.new()
	splash_auto_timer.one_shot = true
	splash_auto_timer.timeout.connect(_on_splash_auto_advance)
	splash_screen.add_child(splash_auto_timer)
	splash_auto_timer.start(STUDIO_SPLASH_AUTO_ADVANCE_SECONDS)


func _on_splash_auto_advance() -> void:
	_dismiss_splash()


func _dismiss_splash(immediate: bool = false) -> void:
	if splash_dismissed or splash_screen == null or splash_transitioning:
		return
	if immediate:
		splash_dismissed = true
		if splash_auto_timer != null:
			splash_auto_timer.stop()
		splash_screen.visible = false
		_focus_connection_menu()
		return
	if splash_stage == 0:
		_transition_to_game_splash()
		return
	splash_dismissed = true
	if splash_auto_timer != null:
		splash_auto_timer.stop()
	var fade := create_tween()
	fade.tween_property(splash_screen, "modulate", Color(1, 1, 1, 0), 0.35)
	fade.finished.connect(_finish_splash_dismissal)


func _transition_to_game_splash() -> void:
	splash_stage = 1
	splash_transitioning = true
	if splash_auto_timer != null:
		splash_auto_timer.stop()
	var fade_out := create_tween()
	fade_out.tween_property(studio_splash, "modulate", Color(1, 1, 1, 0), 0.3)
	fade_out.finished.connect(_finish_studio_splash)


func _finish_studio_splash() -> void:
	if splash_dismissed:
		return
	studio_splash.visible = false
	splash_neon_backdrop.visible = true
	game_splash.visible = true
	game_splash.modulate = Color(1, 1, 1, 0)
	var intro := create_tween().set_parallel(true)
	intro.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(game_splash, "modulate", Color.WHITE, 0.6)
	intro.finished.connect(_finish_game_splash_intro)


func _finish_game_splash_intro() -> void:
	if splash_dismissed:
		return
	splash_transitioning = false
	if splash_auto_timer != null:
		splash_auto_timer.start(SPLASH_AUTO_ADVANCE_SECONDS)


func _finish_splash_dismissal() -> void:
	splash_screen.visible = false
	_focus_connection_menu()


func _focus_connection_menu() -> void:
	if connection_controller.connection_primary_button != null:
		connection_controller.connection_primary_button.grab_focus()


func _toggle_pause_overlay() -> void:
	if connection_controller.connection_screen.visible:
		return
	_set_scoreboard_open(false)
	pause_overlay.visible = not pause_overlay.visible
	network_world.input_blocked = pause_overlay.visible
	if pause_overlay.visible and pause_resume_button != null:
		pause_resume_button.grab_focus()
	if offline_sandbox.visible:
		offline_sandbox.set_process(not pause_overlay.visible)
		offline_sandbox.set_physics_process(not pause_overlay.visible)


func _hide_pause_overlay() -> void:
	pause_overlay.visible = false
	network_world.input_blocked = false
	get_viewport().gui_release_focus()
	if offline_sandbox.visible:
		offline_sandbox.set_process(true)
		offline_sandbox.set_physics_process(true)


func _return_from_pause() -> void:
	_hide_pause_overlay()
	_disconnect_online("Returned to the main menu.")


func _request_f2_return_to_menu() -> void:
	if f2_return_confirmation == null or not _f2_would_leave_session():
		_show_connection_screen("Choose online play or the offline combat lab.")
		return
	if f2_return_confirmation.visible:
		return
	var hosting := connection_controller.is_hosting()
	if hosting:
		f2_return_confirmation.dialog_text = "You are hosting this game.\n\nReturning to the main menu will stop the server and disconnect every player."
		f2_return_confirmation.ok_button_text = "STOP SERVER"
	elif offline_sandbox.visible:
		f2_return_confirmation.dialog_text = "Return to the main menu and leave the Combat Lab?"
		f2_return_confirmation.ok_button_text = "RETURN TO MAIN MENU"
	else:
		f2_return_confirmation.dialog_text = "Returning to the main menu will disconnect you from the current game."
		f2_return_confirmation.ok_button_text = "DISCONNECT"
	f2_return_confirmation.popup_centered(Vector2i(680, 260))
	_set_f2_confirmation_gameplay_blocked(true)


func _f2_would_leave_session() -> bool:
	if offline_sandbox != null and offline_sandbox.visible:
		return true
	if connection_controller.is_hosting():
		return true
	return bridge != null and bridge.role == NetworkBridge.Role.CLIENT


func _confirm_f2_return_to_menu() -> void:
	_show_connection_screen("Returned to the main menu.")


func _cancel_f2_return_to_menu() -> void:
	_set_f2_confirmation_gameplay_blocked(false)


func _set_f2_confirmation_gameplay_blocked(blocked: bool) -> void:
	if network_world != null:
		network_world.input_blocked = blocked
	if offline_sandbox != null and offline_sandbox.visible:
		offline_sandbox.set_process(not blocked)
		offline_sandbox.set_physics_process(not blocked)
	_update_pointer_visibility()


func _play_tutorial() -> void:
	_play_offline()
	offline_sandbox.start_tutorial()


func _play_offline() -> void:
	bridge.stop()
	connection_controller._stop_hosted_server()
	_set_scoreboard_open(false)
	latest_match_payload.clear()
	network_world.set_network_active(false)
	connection_controller.connection_screen.visible = false
	connection_controller.lobby_panel.visible = false
	match_panel.visible = false
	heat_intro_panel.visible = false
	draft_controller.clear_offer()
	standings_controller.reset_session()
	pause_overlay.visible = false
	settings_controller.settings_panel.visible = false
	credits_panel.visible = false
	offline_sandbox.set_sandbox_active(true)
	audio_director.set_context(&"gameplay")


func _disconnect_online(message: String = "Disconnected. Ready to reconnect.") -> void:
	if _disconnect_in_progress:
		return
	_disconnect_in_progress = true
	_show_connection_screen(message)
	_disconnect_in_progress = false


func _show_connection_screen(message: String, is_error: bool = false) -> void:
	if card_inspector != null:
		card_inspector.close(false)
	if f2_return_confirmation != null and f2_return_confirmation.visible:
		f2_return_confirmation.hide()
	if bridge.role == NetworkBridge.Role.CLIENT:
		bridge.stop()
	connection_controller.reset_connection(message, is_error)
	network_world.set_network_active(false)
	_set_scoreboard_open(false)
	offline_sandbox.set_sandbox_active(false)
	latest_match_payload.clear()
	draft_controller.clear_offer()
	match_panel.visible = false
	heat_intro_panel.visible = false
	draft_controller.clear_offer()
	standings_controller.reset_session()
	pause_overlay.visible = false
	settings_controller.settings_panel.visible = false
	credits_panel.visible = false
	network_world.input_blocked = false
	audio_director.set_context(&"menu")
	_focus_connection_menu()


func _on_connected(peer_id: int) -> void:
	network_world.set_network_active(false, false)
	audio_director.set_context(&"lobby")
	connection_controller.show_connected(peer_id)


func _on_lobby_state(state: Dictionary) -> void:
	_scoreboard_rows_dirty = true
	_results_rows_dirty = true
	if not bool(state.get("match_active", false)):
		_set_scoreboard_open(false)
		network_world.set_network_active(false, false)
	connection_controller.render_lobby(state)


func _on_match_event(event_type: StringName, server_tick: int, payload: Dictionary) -> void:
	if event_type == &"COMBAT_FEEDBACK":
		network_world.apply_combat_feedback(payload)
	elif event_type == &"MINE_DETONATIONS":
		network_world.apply_mine_detonations(server_tick, payload.get("events", []) as Array)
	elif event_type == &"REQUEST_REJECTED":
		standings_controller.reset_actions()
		connection_controller.lobby_label.text += "\nRejected: %s" % payload.get("message", "Unknown request")
		connection_controller.show_request_rejection(String(payload.get("message", "Unknown request")))
		standings_controller.show_request_rejection(String(payload.get("message", "Unknown request")))
		draft_controller.recover_rejected_offer()
	elif event_type == &"DRAFT_OFFER":
		_show_draft_offer(payload)
	elif event_type == &"MATCH_START_ACCEPTED" and bool(payload.get("fresh_rematch", false)):
		network_world.reset_match_presentation()
		audio_director.reset_match_deduplication()
		_rematch_requested = false
	elif event_type == &"STATE_CHANGED":
		var previous_state := String(latest_match_payload.get("state_name", last_state_name))
		latest_match_payload = payload.duplicate(true)
		_scoreboard_rows_dirty = true
		_results_rows_dirty = true
		var entering_match := String(payload.get("state_name", "LOBBY")) != "LOBBY"
		if entering_match:
			network_world.set_network_active(true)
		else:
			network_world.reset_match_presentation()
			network_world.set_network_active(false, false)
		connection_controller.connection_screen.visible = not entering_match
		if not entering_match:
			connection_controller.connection_form_panel.visible = false
		network_world.apply_match_state(payload)
		audio_director.set_objective_baseline(payload.get("objective", {}) as Dictionary)
		_handle_state_presentation(previous_state, String(payload.get("state_name", "LOBBY")), payload)
		_update_match_presentation()
	elif event_type == &"DRAFT_RESOLVED":
		latest_match_payload["builds"] = payload.get("builds", {})
		_scoreboard_rows_dirty = true
		_results_rows_dirty = true
		draft_controller.clear_offer()
	elif event_type == &"PLAYER_ELIMINATED":
		var alive_peer_ids: Array = (latest_match_payload.get("alive_peer_ids", []) as Array).duplicate()
		for peer_value in payload.get("peer_ids", []):
			alive_peer_ids.erase(int(peer_value))
		latest_match_payload["alive_peer_ids"] = alive_peer_ids
		latest_match_payload["respawn_deadlines"] = (payload.get("respawn_deadlines", {}) as Dictionary).duplicate(true)
		var eliminations := payload.get("eliminations", []) as Array
		if eliminations.is_empty():
			for peer_value in payload.get("peer_ids", []):
				eliminations.append({
					"killer_id": 0,
					"victim_id": int(peer_value),
					"reason": String(payload.get("reason", "combat")),
				})
		network_world.add_kill_feed_entries(eliminations, server_tick)
		if payload.has("scores"):
			latest_match_payload["scores"] = (payload.scores as Dictionary).duplicate(true)
			_scoreboard_rows_dirty = true
			_results_rows_dirty = true
	elif event_type == &"PLAYER_RESPAWNED":
		latest_match_payload["alive_peer_ids"] = (payload.get("alive_peer_ids", []) as Array).duplicate()
		latest_match_payload["respawn_deadlines"] = (payload.get("respawn_deadlines", {}) as Dictionary).duplicate(true)
	elif event_type in [&"OBJECTIVE_UPDATED", &"OBJECTIVE_TRANSITION"]:
		latest_match_payload["objective"] = (payload.get("objective", {}) as Dictionary).duplicate(true)
		_scoreboard_rows_dirty = true
		network_world.apply_objective_state(latest_match_payload.get("objective", {}) as Dictionary)
		audio_director.observe_objective(latest_match_payload.get("objective", {}) as Dictionary, bridge.local_peer_id, latest_match_payload.get("teams", {}) as Dictionary)
	elif event_type == &"CARD_POWERUP_SPAWNED":
		network_world.add_card_powerup(payload)
	elif event_type == &"CARD_POWERUP_REMOVED":
		if network_world.powerup_layer != null:
			network_world.powerup_layer.remove_powerup(int(payload.get("powerup_id", 0)))
	elif event_type == &"CARD_POWERUP_COLLECTED":
		latest_match_payload["builds"] = payload.get("builds", latest_match_payload.get("builds", {}))
		_scoreboard_rows_dirty = true
		_results_rows_dirty = true
		network_world.apply_builds(latest_match_payload.get("builds", {}) as Dictionary)
		network_world.collect_card_powerup(payload)
		audio_director.play_sfx(&"card_lock", "powerup:%d" % int(payload.get("powerup_id", 0)))


func _process(_delta: float) -> void:
	if not latest_match_payload.is_empty():
		_update_match_presentation()
	if scoreboard_panel != null:
		if scoreboard_open and not _scoreboard_available():
			scoreboard_open = false
		scoreboard_panel.visible = scoreboard_open
		if scoreboard_panel.visible:
			_update_scoreboard()
	_update_pointer_visibility()
	_update_timed_audio()


func _update_pointer_visibility() -> void:
	if input_profiles == null:
		return
	if not _application_has_focus:
		if gameplay_cursor != null:
			gameplay_cursor.visible = false
		if DisplayServer.get_name() != "headless":
			_set_native_gameplay_cursor(false)
			if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var gameplay_visible := offline_sandbox.visible or network_world.visible
	var interactive_overlay := connection_controller.connection_screen.visible or settings_controller.settings_panel.visible or credits_panel.visible or pause_overlay.visible or draft_panel.visible or win_overlay.visible or (f2_return_confirmation != null and f2_return_confirmation.visible)
	var gameplay_pointer_active := gameplay_visible and not interactive_overlay
	var native_gameplay_cursor: bool = gameplay_pointer_active and not input_profiles.uses_controller() and _uses_native_gameplay_cursor()
	var pointer_position := network_world.gameplay_mouse_position() if network_world.visible else get_viewport().get_mouse_position()
	if gameplay_pointer_active and network_world.competitive_view_policy.active and not input_profiles.uses_controller() and DisplayServer.get_name() != "headless" and not pointer_position.is_equal_approx(get_viewport().get_mouse_position()):
		get_viewport().warp_mouse(pointer_position)
	if gameplay_cursor != null:
		gameplay_cursor.visible = gameplay_pointer_active and not input_profiles.uses_controller() and not native_gameplay_cursor
		if gameplay_cursor.visible:
			gameplay_cursor.position = pointer_position
	if DisplayServer.get_name() == "headless":
		return
	_set_native_gameplay_cursor(native_gameplay_cursor)
	var desired_mode := _pointer_mode_for_gameplay(gameplay_pointer_active, native_gameplay_cursor)
	if Input.mouse_mode != desired_mode:
		Input.mouse_mode = desired_mode


func _uses_native_gameplay_cursor() -> bool:
	return OS.get_name() == "macOS"


func _set_native_gameplay_cursor(active: bool) -> void:
	if _native_gameplay_cursor_active == active:
		return
	_native_gameplay_cursor_active = active
	if active:
		Input.set_custom_mouse_cursor(CROSSHAIR_TEXTURE, Input.CURSOR_ARROW, CROSSHAIR_TEXTURE.get_size() * 0.5)
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func _pointer_mode_for_gameplay(gameplay_pointer_active: bool, native_gameplay_cursor: bool = false) -> int:
	if not gameplay_pointer_active:
		return Input.MOUSE_MODE_VISIBLE
	return Input.MOUSE_MODE_CONFINED if native_gameplay_cursor else Input.MOUSE_MODE_CONFINED_HIDDEN


func _show_draft_offer(payload: Dictionary) -> void:
	draft_controller._show_draft_offer(payload)


func _select_draft_card(index: int) -> void:
	draft_controller._select_draft_card(index)


func _confirm_draft_card() -> void:
	draft_controller._confirm_draft_card()


func _cancel_draft_confirmation() -> void:
	draft_controller._cancel_draft_confirmation()


func _show_draft_bye(deadline_tick: int) -> void:
	draft_controller._show_draft_bye(deadline_tick)


func _update_match_presentation() -> void:
	var state_name := String(latest_match_payload.get("state_name", "LOBBY"))
	if state_name == "LOBBY":
		match_panel.visible = false
		heat_intro_panel.visible = false
		network_world.set_match_status("")
		draft_panel.visible = false
		_set_win_screen_visible(false)
		connection_controller.lobby_panel.visible = bridge.role == NetworkBridge.Role.CLIENT
		connection_controller.connection_screen.visible = bridge.role == NetworkBridge.Role.CLIENT
		if connection_controller.connection_screen.visible:
			connection_controller.connection_form_panel.visible = false
		network_world.set_network_active(false, false)
		return
	connection_controller.lobby_panel.visible = false
	match_panel.visible = false
	if state_name != "DRAFT":
		draft_panel.visible = false
	_set_win_screen_visible(state_name == "MATCH_RESULT")
	var deadline := int(latest_match_payload.get("deadline_tick", -1))
	if state_name == "DRAFT" and active_offer_deadline >= 0:
		deadline = active_offer_deadline
	var seconds_left := maxf(float(deadline - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0) if deadline >= 0 else 0.0
	_update_heat_intro(state_name, seconds_left)
	var status := "%s · %s · %s · Round %d · Heat %d" % [
		state_name.replace("_", " ").capitalize(),
		String(latest_match_payload.get("game_mode_name", GameModeRules.mode_name(int(latest_match_payload.get("game_mode", GameModeRules.Mode.DEATH_MATCH))))),
		String(latest_match_payload.get("map_name", ArenaLayout.display_name())),
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
		var heat_team := int(latest_match_payload.get("last_heat_winner_team", 0))
		var heat_winner := GameModeRules.team_name(heat_team) if heat_team > 0 else _player_name(int(latest_match_payload.get("last_heat_winner", 0)))
		status += " · %s" % ("Tie" if bool(latest_match_payload.get("tied_heat", false)) else "%s wins heat" % heat_winner)
	elif state_name == "ROUND_RESULT":
		var round_team := int(latest_match_payload.get("last_round_winner_team", 0))
		status += " · %s wins round" % (GameModeRules.team_name(round_team) if round_team > 0 else _player_name(int(latest_match_payload.get("last_round_winner", 0))))
	elif state_name == "MATCH_RESULT":
		var winner_team := int(latest_match_payload.get("match_winner_team", 0))
		status = "★ VICTORY · %s ★" % (GameModeRules.team_name(winner_team) if winner_team > 0 else _player_name(int(latest_match_payload.get("match_winner", 0))))
		_update_results_screen()
	match_label.text = status
	network_world.set_match_status(_combat_hud_status(state_name, seconds_left))
	if state_name == "DRAFT":
		draft_controller.update_countdown(deadline, seconds_left)


func _update_heat_intro(state_name: String, seconds_left: float) -> void:
	if heat_intro_panel == null:
		return
	if state_name == "COUNTDOWN":
		heat_intro_panel.visible = true
		heat_intro_panel.modulate.a = 1.0
		heat_intro_kicker.text = "%s  //  ROUND %d  //  HEAT %d" % [
			String(latest_match_payload.get("map_name", ArenaLayout.display_name())).to_upper(),
			int(latest_match_payload.get("round_number", 0)),
			int(latest_match_payload.get("heat_number", 0)),
		]
		var beginning := seconds_left <= HEAT_BEGIN_LEAD_SECONDS + 0.0001
		heat_intro_title.text = "BEGIN" if beginning else "READY"
		if beginning:
			heat_intro_subtitle.text = "WEAPONS ENGAGING"
		else:
			var map_id := StringName(latest_match_payload.get("map_id", ArenaLayout.DEFAULT_MAP_ID))
			var mechanic := ArenaLayout.mechanic_prompt(map_id)
			heat_intro_subtitle.text = (
				"WEAPONS LOCKED  ·  BEGIN IN %.1f" % seconds_left
				if mechanic.is_empty()
				else "%s  ·  BEGIN IN %.1f" % [mechanic, seconds_left]
			)
		return
	if state_name == "ACTIVE_HEAT":
		var entered_tick := int(latest_match_payload.get("entered_tick", network_world.latest_server_tick))
		var elapsed := maxf(float(network_world.latest_server_tick - entered_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0)
		if elapsed < HEAT_BEGIN_FADE_SECONDS:
			heat_intro_panel.visible = true
			heat_intro_panel.modulate.a = 1.0 - clampf(elapsed / HEAT_BEGIN_FADE_SECONDS, 0.0, 1.0)
			heat_intro_kicker.text = "%s  //  ROUND %d  //  HEAT %d" % [
				String(latest_match_payload.get("map_name", ArenaLayout.display_name())).to_upper(),
				int(latest_match_payload.get("round_number", 0)),
				int(latest_match_payload.get("heat_number", 0)),
			]
			heat_intro_title.text = "BEGIN"
			heat_intro_subtitle.text = "WEAPONS HOT  ·  %s" % _mode_objective_prompt().to_upper()
			return
	heat_intro_panel.visible = false
	heat_intro_panel.modulate.a = 1.0


func _combat_hud_status(state_name: String, seconds_left: float) -> String:
	var state_label := state_name.replace("_", " ").to_upper()
	var mode_label := String(latest_match_payload.get("game_mode_name", GameModeRules.mode_name(int(latest_match_payload.get("game_mode", GameModeRules.Mode.DEATH_MATCH))))).to_upper()
	if bool(latest_match_payload.get("competitive_view", false)):
		mode_label += " · COMPETITIVE 16:9"
	var map_label := String(latest_match_payload.get("map_name", ArenaLayout.display_name())).to_upper()
	var round_heat := "ROUND %d / HEAT %d" % [int(latest_match_payload.get("round_number", 0)), int(latest_match_payload.get("heat_number", 0))]
	var local_team := network_world.team_for_peer(bridge.local_peer_id) if bridge != null else 0
	if local_team > 0:
		round_heat = "R%d / H%d · T%d ○ALLY ◇ENEMY" % [int(latest_match_payload.get("round_number", 0)), int(latest_match_payload.get("heat_number", 0)), local_team]
	var detail_parts := PackedStringArray()
	var objective_status := ""
	if state_name == "ACTIVE_HEAT":
		detail_parts.append("%d ALIVE" % (latest_match_payload.get("alive_peer_ids", []) as Array).size())
		objective_status = _objective_status_text()
		var overtime_tick := int(latest_match_payload.get("overtime_start_tick", -1))
		if overtime_tick >= 0:
			var end_tick := int(latest_match_payload.get("heat_end_tick", -1))
			var overtime_label := "OVERTIME"
			if end_tick >= 0:
				overtime_label += " · ENDS %.0fs" % maxf(float(end_tick - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0)
			detail_parts.append(overtime_label if network_world.latest_server_tick >= overtime_tick else "OVERTIME IN %.0fs" % maxf(float(overtime_tick - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0))
	elif state_name in ["COUNTDOWN", "HEAT_RESULT", "ROUND_RESULT"]:
		if state_name == "HEAT_RESULT" and bool(latest_match_payload.get("heat_time_limit_reached", false)):
			detail_parts.append("TIME LIMIT")
		detail_parts.append("%.1fs" % seconds_left)
	var lines := PackedStringArray([
		"%s  ·  %s" % [state_label, mode_label],
		"%s  ·  %s" % [map_label, round_heat],
	])
	if state_name == "ACTIVE_HEAT" and network_world.hud_camera.uses_compact_hud():
		var short_modes := ["DM", "TEAM DM", "HILL", "CTF", "TEAM CTF"]
		var mode := clampi(int(latest_match_payload.get("game_mode", 0)), 0, short_modes.size() - 1)
		lines = PackedStringArray([
			"%s · R%d / H%d%s" % [short_modes[mode], int(latest_match_payload.get("round_number", 0)), int(latest_match_payload.get("heat_number", 0)), " · T%d" % local_team if local_team > 0 else ""],
			map_label,
		])
	if not detail_parts.is_empty():
		lines.append("  ·  ".join(detail_parts))
	if not objective_status.is_empty():
		lines.append(objective_status)
	return "\n".join(lines)


func _mode_objective_prompt() -> String:
	match int(latest_match_payload.get("game_mode", GameModeRules.Mode.DEATH_MATCH)):
		GameModeRules.Mode.TEAM_DEATH_MATCH:
			return "eliminate the enemy team"
		GameModeRules.Mode.KING_OF_THE_HILL:
			return "hold the control point"
		GameModeRules.Mode.CAPTURE_THE_FLAG:
			return "carry the flag back to your base"
		GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG:
			return "carry the flag to your team base"
		_:
			return "last ship standing"


func _objective_status_text() -> String:
	var respawn_status := _local_respawn_status_text()
	if not respawn_status.is_empty():
		return respawn_status
	var objective := latest_match_payload.get("objective", {}) as Dictionary
	if objective.is_empty():
		return ""
	var mode := int(objective.get("mode", GameModeRules.Mode.DEATH_MATCH))
	if mode == GameModeRules.Mode.KING_OF_THE_HILL:
		var progress := objective.get("progress", {}) as Dictionary
		var controller_id := int(objective.get("controller_id", 0))
		if controller_id == 0:
			var control_label := "HILL CONTESTED" if bool(objective.get("contested", false)) else "HILL NEUTRAL"
			var leader_id := 0
			var leader_seconds := 0.0
			var tied_lead := false
			for peer_value in progress.keys():
				var peer_id := int(peer_value)
				var seconds := float(progress[peer_value])
				if seconds > leader_seconds:
					leader_id = peer_id
					leader_seconds = seconds
					tied_lead = false
				elif is_equal_approx(seconds, leader_seconds):
					tied_lead = true
			if leader_id != 0:
				return "%s · %s %.1f/%.0fs" % [
					control_label,
					"TIED LEAD" if tied_lead else "LEADER %s" % _player_name(leader_id).to_upper().left(14),
					leader_seconds,
					float(objective.get("target_seconds", GameModeRules.HILL_HOLD_SECONDS)),
				]
			return control_label
		var held := float(progress.get(controller_id, progress.get(str(controller_id), 0.0)))
		return "HILL %s %.1f/%.0fs" % [_player_name(controller_id).to_upper(), held, float(objective.get("target_seconds", GameModeRules.HILL_HOLD_SECONDS))]
	if GameModeRules.uses_flag(mode):
		var carrier_id := int(objective.get("flag_carrier_id", 0))
		if carrier_id != 0:
			return "FLAG: %s" % _player_name(carrier_id).to_upper()
		var flag_position := objective.get("flag_position", Vector2.ZERO) as Vector2
		var spawn_position := objective.get("position", flag_position) as Vector2
		return "FLAG DROPPED" if flag_position.distance_to(spawn_position) > 1.0 else "FLAG AT CENTER"
	return ""


func _local_respawn_status_text() -> String:
	if bridge == null or bridge.local_peer_id == 0:
		return ""
	var deadlines := latest_match_payload.get("respawn_deadlines", {}) as Dictionary
	var deadline := int(deadlines.get(bridge.local_peer_id, deadlines.get(str(bridge.local_peer_id), -1)))
	if deadline < 0:
		return ""
	var seconds := maxf(
		float(deadline - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND,
		0.0
	)
	return "RESPAWN · WAITING FOR CLEAR SPACE" if seconds <= 0.0 else "RESPAWN %.1fs" % seconds


func _draft_category_color(category: int) -> Color:
	return draft_controller._draft_category_color(category)


func _draft_card_style(color: Color, emphasized: bool) -> StyleBoxFlat:
	return draft_controller._draft_card_style(color, emphasized)


func _draft_card_focus_style(rarity_color: Color) -> StyleBoxFlat:
	return draft_controller._draft_card_focus_style(rarity_color)


func _local_build_stack(card_id: StringName) -> int:
	return draft_controller._local_build_stack(card_id)


func _local_build() -> Dictionary:
	return draft_controller._local_build()


func _player_name(peer_id: int) -> String:
	for player_value in bridge.latest_lobby_state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == peer_id:
			return String(player.get("display_name", "Pilot"))
	return "Pilot %d" % peer_id


func _player_team(peer_id: int) -> int:
	var teams := latest_match_payload.get("teams", {}) as Dictionary
	if teams.has(peer_id):
		return int(teams[peer_id])
	if teams.has(str(peer_id)):
		return int(teams[str(peer_id)])
	for player_value in bridge.latest_lobby_state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == peer_id:
			return int(player.get("team_id", 0))
	return 0


func _update_scoreboard() -> void:
	standings_controller._update_scoreboard()


func _set_scoreboard_open(open: bool) -> void:
	standings_controller._set_scoreboard_open(open)


func _scoreboard_available() -> bool:
	if network_world == null or not network_world.visible or pause_overlay != null and pause_overlay.visible:
		return false
	return String(latest_match_payload.get("state_name", "LOBBY")) in ["DRAFT", "COUNTDOWN", "ACTIVE_HEAT", "HEAT_RESULT", "ROUND_RESULT"]


func _add_scoreboard_row(rank: int, peer_id: int) -> void:
	standings_controller._add_scoreboard_row(rank, peer_id)


func _hill_score(peer_id: int) -> float:
	return standings_controller._hill_score(peer_id)


func _update_results_screen() -> void:
	standings_controller._update_results_screen()


func _on_results_rematch_pressed() -> void:
	standings_controller._on_results_rematch_pressed()


func _on_results_extend_pressed() -> void:
	standings_controller._on_results_extend_pressed()


func _on_results_return_pressed() -> void:
	standings_controller._on_results_return_pressed()


func _result_peer_ids() -> Array[int]:
	return standings_controller._result_peer_ids()


func _result_score(peer_id: int) -> Dictionary:
	return standings_controller._result_score(peer_id)


func _result_build(peer_id: int) -> Dictionary:
	return standings_controller._result_build(peer_id)


func _add_result_build(parent: HBoxContainer, peer_id: int, container_name: String = "FinalBuildCards") -> void:
	standings_controller._add_result_build(parent, peer_id, container_name)


func _result_card_tooltip(card: CardDefinition, stacks: int, stack_heading: String = "OWNED STACKS") -> String:
	return CardDetailsText.tooltip(card, stacks, stack_heading)


func _card_stat_name(property_name: String) -> String:
	return CardDetailsText._card_stat_name(property_name)


func _add_result_row(rank: int, peer_id: int, winner: bool) -> void:
	standings_controller._add_result_row(rank, peer_id, winner)


func _add_results_column_heading(parent: HBoxContainer, text_value: String, width: float, expand: bool = false) -> Label:
	return standings_controller._add_results_column_heading(parent, text_value, width, expand)


func _results_row_style(accent: Color, winner: bool) -> StyleBoxFlat:
	return standings_controller._results_row_style(accent, winner)


func _result_card_chip_style(color: Color, hovered: bool) -> StyleBoxFlat:
	return standings_controller._result_card_chip_style(color, hovered)


func _result_card_chip_focus_style(rarity_color: Color) -> StyleBoxFlat:
	return standings_controller._result_card_chip_focus_style(rarity_color)


func _handle_state_presentation(previous_state: String, state_name: String, payload: Dictionary) -> void:
	last_state_name = state_name
	if state_name == "LOBBY":
		standings_controller.reset_actions()
		audio_director.set_context(&"lobby")
		_set_win_screen_visible(false)
		return
	audio_director.set_context(&"win" if state_name == "MATCH_RESULT" else &"gameplay")
	if previous_state == "LOBBY" and state_name == "DRAFT":
		audio_director.reset_match_deduplication()
	if state_name == "COUNTDOWN":
		audio_director.reset_match_deduplication()
		last_countdown_second = -1
		overtime_announced = false
	elif state_name == "ROUND_RESULT":
		audio_director.play_sfx(&"round_win", str(payload.get("entered_tick", 0)))
	elif state_name == "MATCH_RESULT":
		standings_controller.reset_actions(true)
		audio_director.play_sfx(&"match_win", str(payload.get("entered_tick", 0)))


func _set_win_screen_visible(visible: bool) -> void:
	standings_controller._set_win_screen_visible(visible)


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
	payload = _world_audio_details(payload)
	if event_name == &"weapon_fire":
		audio_director.play_weapon_shot(
			payload.get("profile"),
			int(payload.get("owner_id", 0)),
			int(payload.get("shot_sequence", 0)),
			payload.get("position", Vector2.ZERO) as Vector2,
			payload.get("listener_position", Vector2.ZERO) as Vector2,
			bool(payload.get("local", false))
		)
		return
	var unique_key := ""
	if event_name in [&"projectile_impact", &"ricochet", &"missile_launch"]:
		unique_key = "%s:%s" % [payload.get("projectile_id", 0), payload.get("ricochets_remaining", -1)]
	else:
		unique_key = "%s:%s" % [payload.get("peer_id", 0), payload.get("server_tick", payload.get("projectile_id", 0))]
	var volume_db := 0.0
	if payload.has("position") and payload.has("listener_position"):
		volume_db = audio_director.world_sfx_volume_db(
			payload.get("position", Vector2.ZERO) as Vector2,
			payload.get("listener_position", Vector2.ZERO) as Vector2
		)
	audio_director.play_sfx(event_name, unique_key, volume_db, payload)


func _world_audio_details(payload: Dictionary) -> Dictionary:
	var details := payload.duplicate()
	if network_world == null or not network_world.visible:
		return details
	var peer_id := int(details.get("peer_id", details.get("owner_id", 0)))
	if peer_id != 0:
		if not details.has("local"):
			details["local"] = peer_id == bridge.local_peer_id
		var source_ship := network_world.ships.get(peer_id) as CombatShipView
		if source_ship != null and not details.has("position"):
			details["position"] = source_ship.global_position
	if not details.has("listener_position"):
		var local_ship := network_world.ships.get(bridge.local_peer_id) as CombatShipView
		if local_ship != null:
			details["listener_position"] = local_ship.global_position
		elif network_world.camera != null:
			details["listener_position"] = network_world.camera.global_position
	return details


func _panel_style(accent: Color, opacity: float) -> StyleBoxFlat:
	return DesignTokensScript.panel_style(accent, opacity)


func _heat_intro_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("050b1de8")
	style.border_color = Color("fff36a")
	style.set_border_width_all(4)
	style.set_corner_radius_all(22)
	style.shadow_color = Color("42e8ff55")
	style.shadow_size = 22
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	return style


func _on_rejected(reason: StringName, message: String) -> void:
	_show_connection_screen("CONNECTION REJECTED\n%s\nCheck the server settings, then try again." % message, true)
	if reason == NetworkProtocol.REJECT_INVALID_PASSWORD:
		connection_controller.connection_tabs.current_tab = 1
		connection_controller.direct_password_field.grab_focus()


func _on_connection_lost(message: String) -> void:
	_show_connection_screen("CONNECTION LOST\n%s\nYou can reconnect from this screen." % message, true)


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(connection_controller):
		connection_controller.shutdown()
	if bridge != null:
		bridge.stop()
