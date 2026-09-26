extends Node

const DraftScreenControllerScript = preload("res://src/client/ui/draft_screen_controller.gd")
const StandingsScreenControllerScript = preload("res://src/client/ui/standings_screen_controller.gd")

const SettingsControllerScript = preload("res://src/client/ui/settings_controller.gd")
const ConnectionControllerScript = preload("res://src/client/ui/connection_controller.gd")
const AdminPanelScript = preload("res://src/client/ui/admin_panel.gd")

var draft_controller := DraftScreenControllerScript.new()
var standings_controller := StandingsScreenControllerScript.new()

var settings_controller := SettingsControllerScript.new()
var connection_controller := ConnectionControllerScript.new()
var admin_panel := AdminPanelScript.new()

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const CardHoverButtonScript = preload("res://src/client/ui/card_hover_button.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
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
var gameplay_cursor_canvas: CanvasLayer
var gameplay_cursor: Sprite2D


var match_panel: PanelContainer
var match_label: Label
var heat_intro_panel: PanelContainer
var heat_intro_kicker: Label
var heat_intro_title: Label
var heat_intro_subtitle: Label
var pause_overlay: PanelContainer
var pause_title: Label

var settings_return_to_pause: bool = false
var settings_return_to_lobby: bool = false
var credits_panel: Control
var splash_screen: Control
var studio_splash: Control
var game_splash: Control
var splash_neon_backdrop: Control
var splash_auto_timer: Timer
var splash_stage: int = 0
var splash_transitioning: bool = false
var splash_dismissed: bool = false
var card_catalog := CardCatalog.create_default()
var match_state := preload("res://src/client/network/client_match_state.gd").new()
var latest_match_payload: Dictionary:
	get: return match_state.payload
	set(value): match_state.replace(value)

var interface_theme: Theme
var last_countdown_second: int = -1
var overtime_announced: bool = false
var last_state_name: String = "LOBBY"
var pause_resume_button: Button
var global_pause_button: Button
var global_pause_notice: Label
var pause_note: Label
var pause_disconnect_button: Button
var f2_return_confirmation: ConfirmationDialog
var _application_has_focus: bool = true
var _disconnect_in_progress: bool = false


var _native_gameplay_cursor_active: bool = false


func _init() -> void:
	match_state.changed.connect(standings_controller.invalidate_context)
	draft_controller.inspection_requested.connect(_inspect_card)
	draft_controller.presentation_changed.connect(_update_match_presentation)
	draft_controller.name = "DraftScreenController"
	add_child(draft_controller)
	standings_controller.inspection_requested.connect(_inspect_card)
	standings_controller.inspection_close_requested.connect(func() -> void:
		if card_inspector != null: card_inspector.close(false)
	)
	standings_controller.control_prompts_changed.connect(_refresh_control_prompts)
	standings_controller.name = "StandingsScreenController"
	add_child(standings_controller)
	settings_controller.close_requested.connect(_hide_settings)
	settings_controller.accessibility_changed.connect(_apply_accessibility_settings)
	settings_controller.control_prompts_changed.connect(_refresh_control_prompts)
	settings_controller.name = "SettingsController"
	add_child(settings_controller)
	connection_controller.tutorial_requested.connect(_play_tutorial)
	connection_controller.offline_requested.connect(_play_offline)
	connection_controller.settings_requested.connect(_show_settings.bind(false))
	connection_controller.credits_requested.connect(_show_credits)
	connection_controller.disconnect_requested.connect(_disconnect_online)
	connection_controller.connection_requested.connect(_prepare_connection)
	connection_controller.name = "ConnectionController"
	add_child(connection_controller)
	connection_controller.lobby.admin_requested.connect(_show_admin)
	admin_panel.name = "AdminPanelController"
	add_child(admin_panel)
	admin_panel.access_changed.connect(func(_unlocked: bool) -> void: standings_controller.invalidate_context())
	standings_controller.admin_requested.connect(_show_admin)


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	offline_sandbox = $OfflineSandbox as OfflineSandbox
	offline_sandbox.set_sandbox_active(false)
	input_profiles = InputProfileManagerScript.new()
	input_profiles.name = "InputProfileManager"
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
	admin_panel.configure(bridge)
	audio_director = AudioDirector.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	offline_sandbox.presentation_event.connect(_on_world_presentation_event)
	interface_theme = DesignTokensScript.create_interface_theme()
	settings_controller.configure(audio_director, input_profiles, interface_theme)
	input_profiles.scheme_changed.connect(settings_controller._on_control_scheme_changed)
	input_profiles.flight_mode_changed.connect(settings_controller._on_flight_mode_changed)
	input_profiles.bindings_changed.connect(settings_controller._on_control_bindings_changed)
	input_profiles.controller_connections_changed.connect(settings_controller._update_controller_status)
	settings_controller._load_video_settings()
	network_world = NetworkWorldView.new()
	network_world.match_state = match_state
	network_world.name = "NetworkWorld"
	add_child(network_world)
	network_world.setup(bridge, input_profiles)
	settings_controller.accessibility_preferences.load_settings()
	_apply_accessibility_settings()
	network_world.presentation_event.connect(_on_world_presentation_event)
	connection_controller.configure(bridge, interface_theme)
	connection_controller.create_ui(configuration)
	admin_panel.create_ui(connection_controller.connection_canvas, interface_theme)
	settings_controller.register_interface_scope(connection_controller.connection_canvas)
	settings_controller.register_interface_scope(network_world)
	settings_controller.register_interface_scope(offline_sandbox)
	standings_controller.configure(bridge, audio_director, card_catalog, interface_theme, connection_controller.connection_canvas, _standings_context, _scoreboard_available)
	standings_controller.set_admin_access_provider(admin_panel.is_authenticated)
	connection_controller.start_discovery()
	_create_match_ui()
	_create_pause_overlay()
	_create_f2_return_confirmation()
	settings_controller._create_settings_overlay(connection_controller.connection_canvas)
	_create_credits_overlay()
	_create_gameplay_cursor()
	_create_splash_screen()
	audio_director.set_context(&"menu")
	print("SSF_MODE_READY=client port=%d sandbox=offline_combat network=tcp" % configuration.get("port", GameConstants.DEFAULT_PORT))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_log_client_lifecycle("window_close_requested")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
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
	if draft_controller.draft_panel != null and draft_controller.draft_panel.visible and draft_controller.pending_draft_index >= 0 and (event.is_action_pressed("pause_overlay") or event.is_action_pressed(&"ui_cancel")) and not (event is InputEventKey and event.echo):
		draft_controller.cancel_draft_confirmation()
		get_viewport().set_input_as_handled()
		return
	if (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_overlay")) and not (event is InputEventKey and event.echo):
		if admin_panel.is_visible():
			admin_panel.hide_panel()
			get_viewport().set_input_as_handled()
			return
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
	if draft_controller.draft_panel != null and draft_controller.draft_panel.visible:
		for index in draft_controller.draft_buttons.size():
			if event.is_action_pressed("draft_%d" % (index + 1)):
				draft_controller.select_draft_card(index)
				get_viewport().set_input_as_handled()
				break


func _input(event: InputEvent) -> void:
	# Rebinding must capture the key without pausing or resuming the match.
	if settings_controller.capture_input(event):
		return
	if event is InputEventKey and event.pressed and event.alt_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if not event.echo:
			settings_controller.toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"global_pause", true, true) and _can_toggle_global_pause():
		if not event.is_echo():
			_toggle_global_pause()
		get_viewport().set_input_as_handled()
		return
	# Consume key-repeat before either the inspector or GUI focus traversal.
	if standings_controller.scoreboard_open and event.is_action_pressed(&"scoreboard", true):
		get_viewport().set_input_as_handled()
		return
	if card_inspector != null and card_inspector.visible:
		if event.is_action_released(&"scoreboard") and standings_controller.scoreboard_open:
			card_inspector.close(false)
			standings_controller.set_scoreboard_open(false)
			get_viewport().set_input_as_handled()
		else:
			card_inspector.handle_input(event)
		return
	if splash_screen != null and splash_screen.visible and _is_start_input(event):
		_dismiss_splash()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"scoreboard") and not (event is InputEventKey and event.echo):
		if _scoreboard_available():
			standings_controller.set_scoreboard_open(true)
			get_viewport().set_input_as_handled()
	elif event.is_action_released(&"scoreboard"):
		if standings_controller.scoreboard_open:
			standings_controller.set_scoreboard_open(false)
			get_viewport().set_input_as_handled()


func _is_start_input(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65)


func _create_match_ui() -> void:
	card_inspector = preload("res://src/client/ui/card_inspector.gd").new()
	add_child(card_inspector)
	settings_controller.register_interface_scope(card_inspector)
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

	draft_controller.configure(bridge, audio_director, card_catalog, interface_theme, connection_controller.connection_canvas, _draft_context)
	draft_controller.create_ui()
	standings_controller.create_ui()


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
	pause_note = Label.new()
	pause_note.text = "Online combat continues while this menu is open."
	pause_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_note.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(pause_note)
	global_pause_button = Button.new()
	global_pause_button.name = "GlobalPauseButton"
	global_pause_button.custom_minimum_size.y = 58.0
	global_pause_button.theme_type_variation = &"PrimaryButton"
	global_pause_button.visible = false
	global_pause_button.pressed.connect(_toggle_global_pause)
	content.add_child(global_pause_button)
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
	var admin_button := Button.new()
	admin_button.name = "PauseAdminButton"
	admin_button.text = "Server Admin"
	admin_button.theme_type_variation = &"SecondaryButton"
	admin_button.custom_minimum_size.y = 58.0
	admin_button.pressed.connect(_show_admin)
	content.add_child(admin_button)
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
	var notice_canvas := CanvasLayer.new()
	notice_canvas.layer = 21
	add_child(notice_canvas)
	global_pause_notice = Label.new()
	global_pause_notice.name = "GlobalPauseNotice"
	global_pause_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	global_pause_notice.add_theme_font_size_override("font_size", 26)
	global_pause_notice.add_theme_color_override("font_color", Color("fff36a"))
	global_pause_notice.add_theme_color_override("font_outline_color", Color("02040d"))
	global_pause_notice.add_theme_constant_override("outline_size", 10)
	global_pause_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_pause_notice.visible = false
	notice_canvas.add_child(global_pause_notice)
	global_pause_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	global_pause_notice.offset_top = 12.0


func _can_toggle_global_pause() -> bool:
	var is_host := bridge.local_peer_id != 0 and bridge.local_peer_id == int(bridge.latest_lobby_state.get("leader_id", 0))
	var state_name := String(latest_match_payload.get("state_name", "LOBBY"))
	return is_host and state_name not in ["LOBBY", "MATCH_RESULT"] and not latest_match_payload.is_empty() and _awaiting_reconnect_names().is_empty()


func _awaiting_reconnect_names() -> Array:
	return latest_match_payload.get("awaiting_reconnect", []) as Array


func _toggle_global_pause() -> void:
	if _can_toggle_global_pause():
		bridge.send_match_paused(not network_world.match_paused)


func _update_global_pause_ui() -> void:
	var paused := network_world.match_paused
	var is_host := bridge.local_peer_id != 0 and bridge.local_peer_id == int(bridge.latest_lobby_state.get("leader_id", 0))
	global_pause_button.visible = _can_toggle_global_pause()
	global_pause_button.text = "Resume Match for Everyone" if paused else "Pause Match for Everyone"
	var binding: String = input_profiles.binding_text(&"global_pause")
	if binding != "Unbound":
		global_pause_button.text += " · " + binding
	pause_resume_button.text = "Close Menu" if paused else "Resume"
	pause_note.text = "Match and timers are paused for everyone." if paused else "Online combat continues while this menu is open."
	global_pause_notice.visible = paused
	var resume_hint := "%s to resume for everyone." % binding if binding != "Unbound" else "Open the pilot menu to resume for everyone."
	global_pause_notice.text = "INTERMISSION · MATCH PAUSED\n" + (resume_hint if is_host else "Waiting for the host to resume.")
	var awaiting := _awaiting_reconnect_names()
	if paused and not awaiting.is_empty():
		global_pause_notice.text = "MATCH PAUSED · PILOT DISCONNECTED\nWaiting for %s to reconnect." % ", ".join(PackedStringArray(awaiting))


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


func _apply_accessibility_settings() -> void:
	settings_controller.apply_accessible_theme()
	if network_world != null:
		network_world.apply_accessibility_settings(settings_controller.accessibility_preferences.values)
	if offline_sandbox != null and offline_sandbox.has_method("apply_accessibility_settings"):
		offline_sandbox.apply_accessibility_settings(settings_controller.accessibility_preferences.values)


func _refresh_control_prompts() -> void:
	if standings_controller.scoreboard_hint_label != null:
		standings_controller.scoreboard_hint_label.text = "HOLD %s · ARROWS SELECT · I / Y INSPECT · THE MATCH CONTINUES" % input_profiles.binding_text(&"scoreboard").to_upper()


func _show_settings(return_to_pause: bool) -> void:
	settings_return_to_pause = return_to_pause
	settings_return_to_lobby = not return_to_pause and connection_controller.is_lobby_visible()
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
	if settings_return_to_pause and not connection_controller.is_visible():
		pause_overlay.visible = true
		network_world.input_blocked = true
		pause_resume_button.grab_focus()
	elif settings_return_to_lobby and connection_controller.is_lobby_visible():
		network_world.input_blocked = false
		connection_controller.focus_settings()
	else:
		network_world.input_blocked = false
		if connection_controller.is_visible():
			connection_controller.focus_menu()
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
	if connection_controller.is_visible():
		connection_controller.focus_credits()


func _create_gameplay_cursor() -> void:
	gameplay_cursor_canvas = CanvasLayer.new()
	gameplay_cursor_canvas.name = "GameplayCursor"
	gameplay_cursor_canvas.layer = 30
	add_child(gameplay_cursor_canvas)
	settings_controller.register_interface_scope(gameplay_cursor_canvas)
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
	settings_controller.register_interface_scope(splash_canvas)
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
	if connection_controller.is_visible():
		connection_controller.focus_menu()


func _toggle_pause_overlay() -> void:
	if connection_controller.is_visible():
		return
	standings_controller.set_scoreboard_open(false)
	pause_overlay.visible = not pause_overlay.visible
	network_world.input_blocked = pause_overlay.visible
	if pause_overlay.visible and pause_resume_button != null:
		pause_resume_button.grab_focus()
	if offline_sandbox.visible:
		offline_sandbox.set_process(not pause_overlay.visible)
		offline_sandbox.set_physics_process(not pause_overlay.visible)


func _show_admin() -> void:
	admin_panel.show_panel()


func _hide_pause_overlay() -> void:
	pause_overlay.visible = false
	network_world.input_blocked = false
	get_viewport().gui_release_focus()
	if offline_sandbox.visible:
		offline_sandbox.set_process(true)
		offline_sandbox.set_physics_process(true)


func _return_from_pause() -> void:
	_hide_pause_overlay()
	if bridge.role == NetworkBridge.Role.CLIENT:
		bridge.leave_server()
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
	if bridge.role == NetworkBridge.Role.CLIENT:
		bridge.leave_server()
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
	admin_panel.reset_session()
	bridge.stop()
	connection_controller.stop_hosting()
	standings_controller.set_scoreboard_open(false)
	match_state.reset()
	network_world.set_network_active(false)
	connection_controller.hide_screens()
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
	admin_panel.reset_session()
	if card_inspector != null:
		card_inspector.close(false)
	if f2_return_confirmation != null and f2_return_confirmation.visible:
		f2_return_confirmation.hide()
	if bridge.role == NetworkBridge.Role.CLIENT:
		bridge.stop()
	connection_controller.reset_connection(message, is_error)
	network_world.set_network_active(false)
	standings_controller.set_scoreboard_open(false)
	offline_sandbox.set_sandbox_active(false)
	match_state.reset()
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


func _prepare_connection() -> void:
	offline_sandbox.set_sandbox_active(false)
	network_world.set_network_active(false)


func _on_connected(peer_id: int) -> void:
	network_world.set_network_active(false, false)
	audio_director.set_context(&"lobby")
	connection_controller.show_connected(peer_id)


func _on_lobby_state(state: Dictionary) -> void:
	standings_controller.invalidate_context()
	standings_controller.invalidate_rows()
	if not bool(state.get("match_active", false)):
		standings_controller.set_scoreboard_open(false)
		network_world.set_network_active(false, false)
	connection_controller.render_lobby(state)


func _on_match_event(event_type: StringName, server_tick: int, payload: Dictionary) -> void:
	standings_controller.invalidate_context()
	if event_type == &"MATCH_PAUSE_CHANGED":
		match_state.update_fields({"paused": bool(payload.get("paused", false)), "awaiting_reconnect": payload.get("awaiting_reconnect", []) as Array})
		network_world.latest_server_tick = server_tick
		network_world.apply_match_pause(bool(payload.get("paused", false)))
		_update_global_pause_ui()
	elif event_type == &"COMBAT_FEEDBACK":
		network_world.apply_combat_feedback(payload)
	elif event_type == &"MINE_DETONATIONS":
		network_world.apply_mine_detonations(server_tick, payload.get("events", []) as Array)
	elif event_type == &"REQUEST_REJECTED":
		standings_controller.reset_actions()
		connection_controller.show_request_rejection(String(payload.get("message", "Unknown request")))
		standings_controller.show_request_rejection(String(payload.get("message", "Unknown request")))
		draft_controller.recover_rejected_offer()
	elif event_type == &"DRAFT_OFFER":
		draft_controller.show_draft_offer(payload)
	elif event_type == &"MATCH_START_ACCEPTED" and bool(payload.get("fresh_rematch", false)):
		network_world.reset_match_presentation()
		audio_director.reset_match_deduplication()
		standings_controller.reset_rematch_request()
	elif event_type == &"STATE_CHANGED":
		var previous_state := String(latest_match_payload.get("state_name", last_state_name))
		standings_controller.invalidate_rows()
		var entering_match := String(payload.get("state_name", "LOBBY")) != "LOBBY"
		if entering_match:
			network_world.set_network_active(true)
		else:
			network_world.reset_match_presentation()
			network_world.set_network_active(false, false)
		if entering_match:
			connection_controller.hide_screens()
		else:
			connection_controller.show_waiting_lobby()
		network_world.apply_match_state(payload, server_tick)
		if network_world.match_paused:
			network_world.latest_server_tick = server_tick
		audio_director.set_objective_baseline(latest_match_payload.get("objective", {}) as Dictionary)
		_handle_state_presentation(previous_state, String(payload.get("state_name", "LOBBY")), payload)
		_update_match_presentation()
	elif event_type == &"DRAFT_RESOLVED":
		network_world.apply_builds(payload.get("builds", {}) as Dictionary)
		standings_controller.invalidate_rows()
		draft_controller.clear_offer()
	elif event_type == &"PLAYER_ELIMINATED":
		var alive_peer_ids: Array = (latest_match_payload.get("alive_peer_ids", []) as Array).duplicate()
		for peer_value in payload.get("peer_ids", []):
			alive_peer_ids.erase(int(peer_value))
		match_state.update_fields({"alive_peer_ids": alive_peer_ids})
		match_state.update_fields({"respawn_deadlines": (payload.get("respawn_deadlines", {}) as Dictionary).duplicate(true)})
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
			match_state.update_fields({"scores": (payload.scores as Dictionary).duplicate(true)})
			standings_controller.invalidate_rows()
	elif event_type == &"PLAYER_RESPAWNED":
		match_state.update_fields({"alive_peer_ids": (payload.get("alive_peer_ids", []) as Array).duplicate()})
		match_state.update_fields({"respawn_deadlines": (payload.get("respawn_deadlines", {}) as Dictionary).duplicate(true)})
	elif event_type == &"ARENA_EFFECTS_UPDATED":
		if network_world.replicated_visuals.arena != null:
			var previous := network_world.replicated_visuals.arena.effect_state
			if (bool(payload.get("warning", false)) and not bool(previous.get("warning", false))) or (int(payload.get("door_warning_mask", 0)) != 0 and int(previous.get("door_warning_mask", 0)) == 0):
				audio_director.play_sfx(&"countdown")
			network_world.replicated_visuals.arena.set_effect_state(payload)
	elif event_type in [&"OBJECTIVE_UPDATED", &"OBJECTIVE_TRANSITION"]:
		if not network_world.apply_objective_state(payload.get("objective", {}) as Dictionary, server_tick, event_type == &"OBJECTIVE_UPDATED"):
			return
		standings_controller.invalidate_rows()
		audio_director.observe_objective(latest_match_payload.get("objective", {}) as Dictionary, bridge.local_peer_id, latest_match_payload.get("teams", {}) as Dictionary)
	elif event_type == &"CARD_POWERUP_SPAWNED":
		network_world.add_card_powerup(payload)
	elif event_type == &"CARD_POWERUP_REMOVED":
		if network_world.replicated_visuals.powerup_layer != null:
			network_world.replicated_visuals.powerup_layer.remove_powerup(int(payload.get("powerup_id", 0)))
	elif event_type == &"CARD_POWERUP_COLLECTED":
		network_world.apply_builds(payload.get("builds", latest_match_payload.get("builds", {})) as Dictionary)
		standings_controller.invalidate_rows()
		network_world.collect_card_powerup(payload)
		audio_director.play_sfx(&"card_lock", "powerup:%d" % int(payload.get("powerup_id", 0)))


func _process(_delta: float) -> void:
	_update_global_pause_ui()
	if not latest_match_payload.is_empty():
		_update_match_presentation()
	if standings_controller.scoreboard_panel != null:
		if standings_controller.scoreboard_open and not _scoreboard_available():
			standings_controller.scoreboard_open = false
		standings_controller.scoreboard_panel.visible = standings_controller.scoreboard_open
		if standings_controller.scoreboard_panel.visible:
			standings_controller.update_scoreboard()
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
	var interactive_overlay := connection_controller.is_visible() or admin_panel.is_visible() or settings_controller.settings_panel.visible or credits_panel.visible or pause_overlay.visible or draft_controller.draft_panel.visible or standings_controller.win_overlay.visible or (f2_return_confirmation != null and f2_return_confirmation.visible)
	var gameplay_pointer_active := gameplay_visible and not interactive_overlay
	var native_gameplay_cursor: bool = gameplay_pointer_active and not input_profiles.uses_controller() and _uses_native_gameplay_cursor()
	var pointer_position := network_world.gameplay_mouse_position() if network_world.visible else get_viewport().get_mouse_position()
	if gameplay_pointer_active and network_world.hud_camera.competitive_view_policy.active and not input_profiles.uses_controller() and DisplayServer.get_name() != "headless" and not pointer_position.is_equal_approx(get_viewport().get_mouse_position()):
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


func _update_match_presentation() -> void:
	var state_name := String(latest_match_payload.get("state_name", "LOBBY"))
	if state_name == "LOBBY":
		match_panel.visible = false
		heat_intro_panel.visible = false
		network_world.set_match_status("")
		draft_controller.draft_panel.visible = false
		standings_controller.set_win_screen_visible(false)
		if bridge.role == NetworkBridge.Role.CLIENT:
			connection_controller.show_waiting_lobby()
		else:
			connection_controller.hide_screens()
		network_world.set_network_active(false, false)
		return
	connection_controller.hide_screens()
	match_panel.visible = false
	if state_name != "DRAFT":
		draft_controller.draft_panel.visible = false
	standings_controller.set_win_screen_visible(state_name == "MATCH_RESULT")
	var deadline := int(latest_match_payload.get("deadline_tick", -1))
	if state_name == "DRAFT" and draft_controller.active_offer_deadline >= 0:
		deadline = draft_controller.active_offer_deadline
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
		standings_controller.update_results_screen()
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


func _scoreboard_available() -> bool:
	if network_world == null or not network_world.visible or pause_overlay != null and pause_overlay.visible:
		return false
	return String(latest_match_payload.get("state_name", "LOBBY")) in ["DRAFT", "COUNTDOWN", "ACTIVE_HEAT", "HEAT_RESULT", "ROUND_RESULT"]


func _handle_state_presentation(previous_state: String, state_name: String, payload: Dictionary) -> void:
	last_state_name = state_name
	if state_name == "LOBBY":
		standings_controller.reset_actions()
		audio_director.set_context(&"lobby")
		standings_controller.set_win_screen_visible(false)
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
		var source_ship := network_world.replicated_visuals.ships.get(peer_id) as CombatShipView
		if source_ship != null and not details.has("position"):
			details["position"] = source_ship.global_position
	if not details.has("listener_position"):
		var local_ship := network_world.replicated_visuals.ships.get(bridge.local_peer_id) as CombatShipView
		if local_ship != null:
			details["listener_position"] = local_ship.global_position
		elif network_world.hud_camera.camera != null:
			details["listener_position"] = network_world.hud_camera.camera.global_position
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
		connection_controller.focus_password()


func _on_connection_lost(message: String) -> void:
	_log_client_lifecycle("connection_lost")
	_show_connection_screen("CONNECTION LOST\n%s\nYou can reconnect from this screen." % message, true)


func _exit_tree() -> void:
	_log_client_lifecycle("client_scene_exiting")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(connection_controller):
		connection_controller.shutdown()
	# The bridge already sent its leave notice from its own _exit_tree.
	if bridge != null:
		bridge.stop()


func _log_client_lifecycle(event: String) -> void:
	if not is_inside_tree() or get_tree().current_scene != self:
		return
	print(JSON.stringify({"event": event, "timestamp": Time.get_datetime_string_from_system(true),
		"match_state": String(latest_match_payload.get("state_name", "LOBBY")),
		"server_tick": network_world.latest_server_tick if network_world != null else 0}))


func _draft_context() -> Dictionary:
	var builds := latest_match_payload.get("builds", {}) as Dictionary
	var peer_id := bridge.local_peer_id
	return {
		"build": (builds.get(peer_id, builds.get(str(peer_id), {})) as Dictionary).duplicate(),
		"bye": (peer_id != 0 and int(latest_match_payload.get("draft_bye_peer_id", 0)) == peer_id)
			or peer_id in latest_match_payload.get("draft_bye_peer_ids", []),
	}


func _standings_context() -> Dictionary:
	return latest_match_payload.duplicate(true)
