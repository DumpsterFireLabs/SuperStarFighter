extends Node

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const CardHoverButtonScript = preload("res://src/client/ui/card_hover_button.gd")
const SPLASH_AUTO_ADVANCE_SECONDS: float = 10.0
const HEAT_BEGIN_LEAD_SECONDS: float = 0.10
const HEAT_BEGIN_FADE_SECONDS: float = 0.10
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
	Vector2i(3440, 1440),
	Vector2i(3840, 1080),
	Vector2i(3840, 1600),
	Vector2i(3840, 2160),
	Vector2i(5120, 1440),
	Vector2i(5120, 2160),
]

var bridge: NetworkBridge
var network_world: NetworkWorldView
var offline_sandbox: OfflineSandbox
var audio_director: AudioDirector
var input_profiles: Node
var connection_canvas: CanvasLayer
var connection_screen: Control
var connection_form_panel: PanelContainer
var connection_tabs: TabContainer
var lobby_panel: PanelContainer
var host_field: LineEdit
var port_field: LineEdit
var host_port_field: LineEdit
var name_field: LineEdit
var server_name_field: LineEdit
var connection_status: Label
var lan_servers_container: VBoxContainer
var lan_refresh_button: Button
var lan_browser: LanDiscoveryService
var _lan_servers: Array[Dictionary] = []
var _hosted_server_root: Node
var _hosted_server_bridge: NetworkBridge
var _hosted_server_multiplayer: MultiplayerAPI
var lobby_label: Label
var lobby_roster: VBoxContainer
var ready_button: CheckButton
var rounds_control: SpinBox
var player_limit_control: SpinBox
var npcs_button: CheckButton
var start_button: Button
var match_panel: PanelContainer
var match_label: Label
var heat_intro_panel: PanelContainer
var heat_intro_kicker: Label
var heat_intro_title: Label
var heat_intro_subtitle: Label
var draft_panel: PanelContainer
var draft_title: Label
var draft_buttons: Array[Button] = []
var draft_rarity_labels: Array[Label] = []
var draft_bye_label: Label
var scoreboard_panel: PanelContainer
var scoreboard_label: Label
var scoreboard_context_label: Label
var scoreboard_rows_container: VBoxContainer
var scoreboard_hint_label: Label
var scoreboard_open: bool = false
var _scoreboard_signature: String = ""
var results_panel: PanelContainer
var results_label: Label
var results_winner_label: Label
var results_standings_container: VBoxContainer
var results_return_button: Button
var _results_signature: String = ""
var _return_to_lobby_requested: bool = false
var win_overlay: Control
var pause_overlay: PanelContainer
var pause_title: Label
var settings_panel: Control
var settings_tabs: TabContainer
var window_mode_control: OptionButton
var resolution_control: OptionButton
var display_mode_note: Label
var control_scheme_control: OptionButton
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
var connection_primary_button: Button
var pause_resume_button: Button


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	offline_sandbox = $OfflineSandbox as OfflineSandbox
	offline_sandbox.set_sandbox_active(false)
	input_profiles = InputProfileManagerScript.new()
	input_profiles.name = "InputProfileManager"
	input_profiles.scheme_changed.connect(_on_control_scheme_changed)
	input_profiles.bindings_changed.connect(_on_control_bindings_changed)
	input_profiles.controller_connections_changed.connect(_update_controller_status)
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
	_load_video_settings()
	network_world = NetworkWorldView.new()
	network_world.name = "NetworkWorld"
	add_child(network_world)
	network_world.setup(bridge, input_profiles)
	network_world.presentation_event.connect(_on_world_presentation_event)
	_create_connection_ui(configuration)
	lan_browser = LanDiscoveryService.new()
	lan_browser.name = "LanServerBrowser"
	add_child(lan_browser)
	lan_browser.servers_updated.connect(_on_lan_servers_updated)
	var discovery_error := lan_browser.start_browser()
	if discovery_error != OK:
		connection_status.text = lan_browser.last_error
	_create_match_ui()
	_create_pause_overlay()
	_create_settings_overlay()
	_create_splash_screen()
	audio_director.set_context(&"menu")
	print("SSF_MODE_READY=client port=%d sandbox=offline_combat network=enet" % configuration.get("port", GameConstants.DEFAULT_PORT))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_overlay") and not (event is InputEventKey and event.echo):
		if settings_panel != null and settings_panel.visible:
			_hide_settings()
		else:
			_toggle_pause_overlay()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel") and not (event is InputEventKey and event.echo):
		if settings_panel != null and settings_panel.visible:
			_hide_settings()
			get_viewport().set_input_as_handled()
			return
		if pause_overlay != null and pause_overlay.visible:
			_hide_pause_overlay()
			get_viewport().set_input_as_handled()
			return
	if pause_overlay != null and pause_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		_show_connection_screen("Choose online play or the offline combat lab.")
	if draft_panel != null and draft_panel.visible:
		for index in draft_buttons.size():
			if event.is_action_pressed("draft_%d" % (index + 1)):
				_select_draft_card(index)
				get_viewport().set_input_as_handled()
				break


func _input(event: InputEvent) -> void:
	if not binding_capture_action.is_empty():
		if input_profiles.accepts_rebind_event(event):
			_complete_binding_capture(event)
			get_viewport().set_input_as_handled()
		return
	if splash_screen != null and splash_screen.visible and _is_start_input(event):
		_dismiss_splash()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"scoreboard") and not (event is InputEventKey and event.echo):
		_set_scoreboard_open(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"scoreboard"):
		_set_scoreboard_open(false)
		get_viewport().set_input_as_handled()


func _is_start_input(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65)


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
	connection_form_panel = PanelContainer.new()
	connection_form_panel.custom_minimum_size = Vector2(780.0, 690.0)
	connection_form_panel.add_theme_stylebox_override("panel", _panel_style(Color("42e8ff"), 0.96))
	center.add_child(connection_form_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	connection_form_panel.add_child(content)
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
	name_field = _add_labeled_field(content, "Display name", "Pilot")
	name_field.max_length = 16
	connection_tabs = TabContainer.new()
	connection_tabs.custom_minimum_size = Vector2(720.0, 285.0)
	connection_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(connection_tabs)
	_create_lan_join_tab()
	_create_direct_join_tab(configuration)
	_create_host_tab(configuration)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	var offline_button := Button.new()
	offline_button.text = "Offline Combat Lab"
	offline_button.custom_minimum_size.y = 54.0
	offline_button.pressed.connect(_play_offline)
	buttons.add_child(offline_button)
	connection_primary_button = offline_button
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
	connection_status.text = "Browse local servers, host instantly, or connect directly by address."
	connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connection_status.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(connection_status)
	_create_lobby_panel()


func _create_lan_join_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "LAN SERVERS"
	tab.add_theme_constant_override("separation", 8)
	connection_tabs.add_child(tab)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	tab.add_child(controls)
	var hint := Label.new()
	hint.text = "Servers on your local network"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", Color("aebbd4"))
	controls.add_child(hint)
	lan_refresh_button = Button.new()
	lan_refresh_button.text = "REFRESH"
	lan_refresh_button.custom_minimum_size = Vector2(145.0, 42.0)
	lan_refresh_button.pressed.connect(_refresh_lan_servers)
	controls.add_child(lan_refresh_button)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 185.0
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	lan_servers_container = VBoxContainer.new()
	lan_servers_container.name = "LanServerRows"
	lan_servers_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_servers_container.add_theme_constant_override("separation", 6)
	scroll.add_child(lan_servers_container)
	_rebuild_lan_server_list()


func _create_direct_join_tab(configuration: Dictionary) -> void:
	var tab := VBoxContainer.new()
	tab.name = "DIRECT CONNECT"
	tab.add_theme_constant_override("separation", 10)
	connection_tabs.add_child(tab)
	host_field = _add_labeled_field(tab, "Server host or IP", configuration.get("host", "127.0.0.1"))
	port_field = _add_labeled_field(tab, "Gameplay UDP port", str(configuration.get("port", GameConstants.DEFAULT_PORT)))
	var connect_center := CenterContainer.new()
	tab.add_child(connect_center)
	var connect_button := Button.new()
	connect_button.text = "CONNECT TO SERVER"
	connect_button.custom_minimum_size = Vector2(280.0, 48.0)
	connect_button.pressed.connect(_connect_online)
	connect_center.add_child(connect_button)


func _create_host_tab(configuration: Dictionary) -> void:
	var tab := VBoxContainer.new()
	tab.name = "HOST GAME"
	tab.add_theme_constant_override("separation", 10)
	connection_tabs.add_child(tab)
	server_name_field = _add_labeled_field(tab, "Server name", "Super Star Arena")
	server_name_field.max_length = LanDiscoveryProtocol.MAX_SERVER_NAME_LENGTH
	host_port_field = _add_labeled_field(tab, "Gameplay UDP port", str(configuration.get("port", GameConstants.DEFAULT_PORT)))
	var host_center := CenterContainer.new()
	tab.add_child(host_center)
	var host_button := Button.new()
	host_button.text = "HOST & JOIN"
	host_button.custom_minimum_size = Vector2(280.0, 48.0)
	host_button.pressed.connect(_host_online)
	host_center.add_child(host_button)


func _create_lobby_panel() -> void:
	lobby_panel = PanelContainer.new()
	lobby_panel.set_anchors_preset(Control.PRESET_CENTER)
	lobby_panel.position = Vector2(-390.0, -345.0)
	lobby_panel.custom_minimum_size = Vector2(780.0, 690.0)
	lobby_panel.theme = interface_theme
	lobby_panel.add_theme_stylebox_override("panel", _panel_style(Color("42e8ff"), 0.96))
	lobby_panel.visible = false
	connection_canvas.add_child(lobby_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	lobby_panel.add_child(content)
	var title := Label.new()
	title.text = "✦  ONLINE LOBBY  ✦"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)
	lobby_label = Label.new()
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_label.add_theme_font_size_override("font_size", 20)
	lobby_label.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(lobby_label)
	var player_scroll := ScrollContainer.new()
	player_scroll.custom_minimum_size = Vector2(740.0, 220.0)
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(player_scroll)
	lobby_roster = VBoxContainer.new()
	lobby_roster.add_theme_constant_override("separation", 7)
	lobby_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_scroll.add_child(lobby_roster)
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
	npcs_button.text = "Enable NPCs · add configurable pilots to empty seats"
	npcs_button.custom_minimum_size.y = 48.0
	npcs_button.toggled.connect(_on_npcs_toggled)
	content.add_child(npcs_button)
	ready_button = CheckButton.new()
	ready_button.text = "READY FOR LAUNCH"
	ready_button.custom_minimum_size.y = 52.0
	ready_button.toggled.connect(_on_ready_toggled)
	content.add_child(ready_button)
	start_button = Button.new()
	start_button.text = "Start Match"
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

	heat_intro_panel = PanelContainer.new()
	heat_intro_panel.name = "HeatIntro"
	heat_intro_panel.set_anchors_preset(Control.PRESET_CENTER)
	heat_intro_panel.position = Vector2(-300.0, -125.0)
	heat_intro_panel.custom_minimum_size = Vector2(600.0, 250.0)
	heat_intro_panel.theme = interface_theme
	heat_intro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_intro_panel.add_theme_stylebox_override("panel", _heat_intro_style())
	heat_intro_panel.visible = false
	connection_canvas.add_child(heat_intro_panel)
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
		var rarity_label := Label.new()
		rarity_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		rarity_label.offset_left = 10.0
		rarity_label.offset_top = -38.0
		rarity_label.offset_right = -10.0
		rarity_label.offset_bottom = -10.0
		rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rarity_label.add_theme_font_size_override("font_size", 14)
		rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(rarity_label)
		draft_rarity_labels.append(rarity_label)
	draft_bye_label = Label.new()
	draft_bye_label.text = "ROUND WINNER\n\nYou keep the build that won the round.\nEveryone else gets an upgrade this time.\n\nHold the lead."
	draft_bye_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_bye_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	draft_bye_label.add_theme_font_size_override("font_size", 28)
	draft_bye_label.add_theme_color_override("font_color", Color("fff36a"))
	draft_bye_label.custom_minimum_size.y = 390.0
	draft_bye_label.visible = false
	content.add_child(draft_bye_label)

	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.position = Vector2(-550.0, -330.0)
	scoreboard_panel.custom_minimum_size = Vector2(1100.0, 660.0)
	scoreboard_panel.theme = interface_theme
	scoreboard_panel.add_theme_stylebox_override("panel", _panel_style(Color("42e8ff"), 0.985))
	scoreboard_panel.visible = false
	connection_canvas.add_child(scoreboard_panel)
	var scoreboard_content := VBoxContainer.new()
	scoreboard_content.add_theme_constant_override("separation", 10)
	scoreboard_panel.add_child(scoreboard_content)
	var scoreboard_kicker := Label.new()
	scoreboard_kicker.text = "✦  LIVE MATCH  ✦"
	scoreboard_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_kicker.add_theme_font_size_override("font_size", 16)
	scoreboard_kicker.add_theme_color_override("font_color", Color("ff8ee8"))
	scoreboard_content.add_child(scoreboard_kicker)
	scoreboard_label = Label.new()
	scoreboard_label.text = "SCOREBOARD"
	scoreboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_label.add_theme_font_size_override("font_size", 38)
	scoreboard_label.add_theme_color_override("font_color", Color("73f7ff"))
	scoreboard_content.add_child(scoreboard_label)
	scoreboard_context_label = Label.new()
	scoreboard_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_context_label.add_theme_font_size_override("font_size", 17)
	scoreboard_context_label.add_theme_color_override("font_color", Color("aebbd4"))
	scoreboard_content.add_child(scoreboard_context_label)
	var scoreboard_heading := HBoxContainer.new()
	scoreboard_heading.add_theme_constant_override("separation", 12)
	scoreboard_content.add_child(scoreboard_heading)
	_add_results_column_heading(scoreboard_heading, "RANK / PILOT", 300.0)
	_add_results_column_heading(scoreboard_heading, "HEATS", 90.0)
	_add_results_column_heading(scoreboard_heading, "ROUNDS", 100.0)
	_add_results_column_heading(scoreboard_heading, "CURRENT BUILD", 0.0, true)
	var scoreboard_scroll := ScrollContainer.new()
	scoreboard_scroll.custom_minimum_size = Vector2(1060.0, 430.0)
	scoreboard_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scoreboard_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scoreboard_content.add_child(scoreboard_scroll)
	scoreboard_rows_container = VBoxContainer.new()
	scoreboard_rows_container.add_theme_constant_override("separation", 7)
	scoreboard_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scoreboard_scroll.add_child(scoreboard_rows_container)
	scoreboard_hint_label = Label.new()
	scoreboard_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_hint_label.add_theme_font_size_override("font_size", 15)
	scoreboard_hint_label.add_theme_color_override("font_color", Color("fff36a"))
	scoreboard_content.add_child(scoreboard_hint_label)
	_refresh_control_prompts()

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
	results_panel.position = Vector2(-560.0, -340.0)
	results_panel.custom_minimum_size = Vector2(1120.0, 680.0)
	results_panel.theme = interface_theme
	results_panel.add_theme_stylebox_override("panel", _panel_style(Color("fff36a"), 0.96))
	results_panel.visible = true
	win_overlay.add_child(results_panel)
	var results_content := VBoxContainer.new()
	results_content.add_theme_constant_override("separation", 10)
	results_panel.add_child(results_content)
	var results_kicker := Label.new()
	results_kicker.text = "✦  MATCH COMPLETE  ✦"
	results_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_kicker.add_theme_font_size_override("font_size", 18)
	results_kicker.add_theme_color_override("font_color", Color("ff8ee8"))
	results_content.add_child(results_kicker)
	results_label = Label.new()
	results_label.text = "VICTORY"
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.add_theme_font_size_override("font_size", 52)
	results_label.add_theme_color_override("font_color", Color("fff36a"))
	results_content.add_child(results_label)
	var champion_panel := PanelContainer.new()
	champion_panel.custom_minimum_size.y = 92.0
	champion_panel.add_theme_stylebox_override("panel", _results_row_style(Color("fff36a"), true))
	results_content.add_child(champion_panel)
	var champion_content := VBoxContainer.new()
	champion_content.alignment = BoxContainer.ALIGNMENT_CENTER
	champion_content.add_theme_constant_override("separation", 2)
	champion_panel.add_child(champion_content)
	var champion_kicker := Label.new()
	champion_kicker.text = "SUPER STAR CHAMPION"
	champion_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	champion_kicker.add_theme_font_size_override("font_size", 17)
	champion_kicker.add_theme_color_override("font_color", Color("d6e2f2"))
	champion_content.add_child(champion_kicker)
	results_winner_label = Label.new()
	results_winner_label.text = "PILOT"
	results_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_winner_label.add_theme_font_size_override("font_size", 34)
	results_winner_label.add_theme_color_override("font_color", Color("fff36a"))
	champion_content.add_child(results_winner_label)
	var standings_heading := HBoxContainer.new()
	standings_heading.add_theme_constant_override("separation", 12)
	results_content.add_child(standings_heading)
	_add_results_column_heading(standings_heading, "RANK", 72.0)
	_add_results_column_heading(standings_heading, "PILOT", 230.0)
	_add_results_column_heading(standings_heading, "RESULT", 190.0)
	_add_results_column_heading(standings_heading, "FINAL BUILD", 0.0, true)
	var results_scroll := ScrollContainer.new()
	results_scroll.custom_minimum_size = Vector2(1060.0, 300.0)
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	results_content.add_child(results_scroll)
	results_standings_container = VBoxContainer.new()
	results_standings_container.add_theme_constant_override("separation", 7)
	results_standings_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.add_child(results_standings_container)
	var results_action_center := CenterContainer.new()
	results_content.add_child(results_action_center)
	results_return_button = Button.new()
	results_return_button.text = "EXIT TO LOBBY"
	results_return_button.custom_minimum_size = Vector2(340.0, 52.0)
	results_return_button.add_theme_font_size_override("font_size", 19)
	results_return_button.pressed.connect(_on_results_return_pressed)
	results_action_center.add_child(results_return_button)


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
	pause_resume_button = Button.new()
	pause_resume_button.text = "Resume"
	pause_resume_button.custom_minimum_size.y = 58.0
	pause_resume_button.pressed.connect(_hide_pause_overlay)
	content.add_child(pause_resume_button)
	var settings_button := Button.new()
	settings_button.text = "Settings"
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
	panel.custom_minimum_size = Vector2(920.0, 690.0)
	panel.theme = interface_theme
	panel.add_theme_stylebox_override("panel", _panel_style(Color("d39cff"), 0.98))
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
	settings_tabs.custom_minimum_size = Vector2(860.0, 500.0)
	settings_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(settings_tabs)
	_create_display_audio_settings_tab()
	_create_controls_settings_tab()
	var saved_note := Label.new()
	saved_note.text = "Settings and both control profiles save automatically."
	saved_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	saved_note.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(saved_note)
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size.y = 52.0
	back_button.pressed.connect(_hide_settings)
	content.add_child(back_button)


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
	_add_volume_setting(tab, "Master Volume", &"master", audio_director.master_volume_percent)
	_add_volume_setting(tab, "Music Volume", &"music", audio_director.music_volume_percent)
	_add_volume_setting(tab, "Effects Volume", &"sfx", audio_director.sfx_volume_percent)
	var mute_button := CheckButton.new()
	mute_button.text = "Mute all audio"
	mute_button.button_pressed = audio_director.muted
	mute_button.custom_minimum_size.y = 48.0
	mute_button.toggled.connect(audio_director.set_muted)
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
	control_scheme_control.select(int(input_profiles.active_scheme))
	control_scheme_control.item_selected.connect(_on_control_scheme_selected)
	scheme_row.add_child(control_scheme_control)
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
	controller_deadzone_slider.value = input_profiles.controller_deadzone
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
	scroll.custom_minimum_size = Vector2(820.0, 300.0)
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
	reset_button.custom_minimum_size.y = 42.0
	reset_button.pressed.connect(_on_restore_control_defaults)
	tab.add_child(reset_button)
	_refresh_input_settings_ui()


func _refresh_input_settings_ui() -> void:
	if control_scheme_control == null:
		return
	control_scheme_control.select(int(input_profiles.active_scheme))
	controller_deadzone_row.visible = input_profiles.uses_controller()
	controller_deadzone_slider.set_value_no_signal(input_profiles.controller_deadzone)
	controller_deadzone_value.text = "%d%%" % roundi(input_profiles.controller_deadzone * 100.0)
	_update_controller_status()
	_rebuild_binding_rows()


func _rebuild_binding_rows() -> void:
	if binding_rows == null:
		return
	for child in binding_rows.get_children():
		binding_rows.remove_child(child)
		child.queue_free()
	binding_buttons.clear()
	for action in input_profiles.rebind_actions():
		var label := Label.new()
		label.text = input_profiles.action_label(action)
		label.custom_minimum_size = Vector2(360.0, 40.0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		binding_rows.add_child(label)
		var button := Button.new()
		button.text = input_profiles.binding_text(action)
		button.custom_minimum_size = Vector2(390.0, 40.0)
		button.pressed.connect(_begin_binding_capture.bind(action))
		binding_rows.add_child(button)
		binding_buttons[action] = button


func _on_control_scheme_selected(index: int) -> void:
	_cancel_binding_capture()
	input_profiles.set_scheme(control_scheme_control.get_item_id(index))
	_refresh_input_settings_ui()


func _on_controller_deadzone_changed(value: float) -> void:
	input_profiles.set_controller_deadzone(value)
	controller_deadzone_value.text = "%d%%" % roundi(input_profiles.controller_deadzone * 100.0)


func _begin_binding_capture(action: StringName) -> void:
	binding_capture_action = action
	binding_capture_seconds = 8.0
	var prompt := "Press a controller button or move one axis fully" if input_profiles.uses_controller() else "Press a keyboard key or mouse button"
	binding_capture_status.text = "%s for %s…" % [prompt, input_profiles.action_label(action)]
	if binding_buttons.has(action):
		(binding_buttons[action] as Button).text = "PRESS INPUT…"


func _complete_binding_capture(event: InputEvent) -> void:
	var action := binding_capture_action
	var rebound: bool = input_profiles.rebind(action, event)
	if rebound:
		binding_capture_status.text = "%s is now %s." % [input_profiles.action_label(action), input_profiles.binding_text(action)]
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
	input_profiles.restore_active_defaults()
	binding_capture_status.text = "Restored the selected profile's default bindings."
	_refresh_input_settings_ui()


func _on_control_scheme_changed(_scheme: int) -> void:
	_refresh_input_settings_ui()
	_refresh_control_prompts()


func _on_control_bindings_changed() -> void:
	_rebuild_binding_rows()
	_refresh_control_prompts()


func _refresh_control_prompts() -> void:
	if scoreboard_hint_label != null:
		scoreboard_hint_label.text = "RELEASE %s TO RETURN TO COMBAT  ·  THE MATCH CONTINUES" % input_profiles.binding_text(&"scoreboard").to_upper()


func _update_controller_status() -> void:
	if controller_status_label == null:
		return
	controller_status_label.text = input_profiles.controller_status_text() if input_profiles.uses_controller() else "Keyboard and mouse is the default profile. Controller settings remain saved separately."


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


func _show_settings(return_to_pause: bool) -> void:
	settings_return_to_pause = return_to_pause
	if pause_overlay != null:
		pause_overlay.visible = false
	settings_panel.visible = true
	_refresh_input_settings_ui()
	if network_world != null:
		network_world.input_blocked = return_to_pause
	if settings_tabs.current_tab == 1:
		control_scheme_control.grab_focus()
	else:
		resolution_control.grab_focus()


func _hide_settings() -> void:
	_cancel_binding_capture()
	settings_panel.visible = false
	if settings_return_to_pause and not connection_screen.visible:
		pause_overlay.visible = true
		network_world.input_blocked = true
		pause_resume_button.grab_focus()
	else:
		network_world.input_blocked = false
		if connection_screen.visible and connection_primary_button != null:
			connection_primary_button.grab_focus()
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
	skip.text = "PRESS ANY INPUT TO START"
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
	get_tree().create_timer(SPLASH_AUTO_ADVANCE_SECONDS).timeout.connect(_on_splash_auto_advance)


func _on_splash_auto_advance() -> void:
	_dismiss_splash()


func _dismiss_splash(immediate: bool = false) -> void:
	if splash_dismissed or splash_screen == null:
		return
	splash_dismissed = true
	if immediate:
		splash_screen.visible = false
		_focus_connection_menu()
		return
	var fade := create_tween()
	fade.tween_property(splash_screen, "modulate", Color(1, 1, 1, 0), 0.35)
	fade.finished.connect(_finish_splash_dismissal)


func _finish_splash_dismissal() -> void:
	splash_screen.visible = false
	_focus_connection_menu()


func _focus_connection_menu() -> void:
	if input_profiles != null and input_profiles.uses_controller() and connection_primary_button != null:
		connection_primary_button.grab_focus()


func _toggle_pause_overlay() -> void:
	if connection_screen.visible:
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
	bridge.stop()
	_stop_hosted_server()
	_show_connection_screen("Returned to the main menu.")


func _connect_online() -> void:
	var port := _validated_port(port_field)
	if port == 0:
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


func _host_online() -> void:
	var port := _validated_port(host_port_field, true)
	if port == 0:
		return
	var display_name := name_field.text.strip_edges()
	if not ServerLobby.is_valid_display_name(display_name):
		connection_status.text = NetworkProtocol.rejection_message(NetworkProtocol.REJECT_INVALID_NAME)
		return
	var server_name := server_name_field.text.strip_edges()
	if not LanDiscoveryProtocol.is_valid_server_name(server_name):
		connection_status.text = "Server name must contain 1–%d printable characters." % LanDiscoveryProtocol.MAX_SERVER_NAME_LENGTH
		return
	bridge.stop()
	_stop_hosted_server()
	var error := _start_hosted_server({
		"port": port,
		"max_players": GameConstants.DEFAULT_MAX_PLAYERS,
		"rounds_to_win": GameConstants.DEFAULT_ROUNDS_TO_WIN,
		"server_name": server_name,
	})
	if error != OK:
		connection_status.text = _hosted_server_bridge.last_error if _hosted_server_bridge != null else "Could not start the local server."
		_stop_hosted_server()
		return
	offline_sandbox.set_sandbox_active(false)
	network_world.set_network_active(false)
	connection_status.text = "Hosting %s on UDP %d and joining locally…" % [server_name, port]
	error = bridge.start_client("127.0.0.1", port, display_name)
	if error != OK:
		connection_status.text = bridge.last_error
		_stop_hosted_server()


func _start_hosted_server(configuration: Dictionary) -> Error:
	_hosted_server_root = Node.new()
	_hosted_server_root.name = "HostedServerRuntime"
	add_child(_hosted_server_root)
	_hosted_server_multiplayer = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(_hosted_server_multiplayer, _hosted_server_root.get_path())
	var server_main := Node.new()
	server_main.name = "Main"
	_hosted_server_root.add_child(server_main)
	_hosted_server_bridge = NetworkBridge.new()
	_hosted_server_bridge.name = "NetworkBridge"
	server_main.add_child(_hosted_server_bridge)
	return _hosted_server_bridge.start_server(configuration)


func _stop_hosted_server() -> void:
	if _hosted_server_bridge != null and is_instance_valid(_hosted_server_bridge):
		_hosted_server_bridge.stop()
	if _hosted_server_root != null and is_instance_valid(_hosted_server_root):
		_hosted_server_root.free()
	_hosted_server_bridge = null
	_hosted_server_root = null
	_hosted_server_multiplayer = null


func _validated_port(field: LineEdit, reserve_discovery_port: bool = false) -> int:
	var port_text := field.text.strip_edges()
	if not port_text.is_valid_int():
		connection_status.text = "Port must be an integer from %d through %d." % [GameConstants.MIN_PORT, GameConstants.MAX_PORT]
		return 0
	var port := int(port_text)
	if port < GameConstants.MIN_PORT or port > GameConstants.MAX_PORT:
		connection_status.text = "Port must be from %d through %d." % [GameConstants.MIN_PORT, GameConstants.MAX_PORT]
		return 0
	if reserve_discovery_port and port == LanDiscoveryProtocol.DISCOVERY_PORT:
		connection_status.text = "Port %d is reserved for LAN server discovery. Choose another gameplay port." % port
		return 0
	return port


func _refresh_lan_servers() -> void:
	if lan_browser != null:
		lan_browser.refresh_now()
	connection_status.text = "Scanning the local network for Super Star Fighter servers…"


func _on_lan_servers_updated(servers: Array[Dictionary]) -> void:
	_lan_servers = servers.duplicate(true)
	_rebuild_lan_server_list()
	if connection_form_panel.visible and connection_tabs.current_tab == 0:
		connection_status.text = "%d local server%s found." % [servers.size(), "" if servers.size() == 1 else "s"]


func _rebuild_lan_server_list() -> void:
	if lan_servers_container == null:
		return
	for child in lan_servers_container.get_children():
		lan_servers_container.remove_child(child)
		child.free()
	if _lan_servers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "SEARCHING…\nStart a server on this network or use Direct Connect."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color("8ba1c7"))
		lan_servers_container.add_child(empty_label)
		return
	for server in _lan_servers:
		_add_lan_server_row(server)


func _add_lan_server_row(server: Dictionary) -> void:
	var compatible := int(server.get("protocol_version", 0)) == GameConstants.PROTOCOL_VERSION
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 62.0
	panel.set_meta("address", String(server.get("address", "")))
	panel.set_meta("game_port", int(server.get("game_port", 0)))
	panel.add_theme_stylebox_override("panel", _lan_server_row_style(compatible))
	lan_servers_container.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	var name_label := Label.new()
	name_label.text = String(server.get("server_name", "LOCAL SERVER"))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color("42e8ff") if compatible else Color("ff7994"))
	identity.add_child(name_label)
	var detail_label := Label.new()
	var state_text := "IN MATCH" if bool(server.get("match_active", false)) else "LOBBY"
	detail_label.text = "%s:%d  ·  %d HUMAN + %d NPC / %d  ·  %s  ·  %d ms" % [
		server.get("address", ""), server.get("game_port", 0), server.get("human_count", 0),
		server.get("npc_count", 0), server.get("player_limit", 0), state_text, server.get("ping_ms", 0),
	]
	detail_label.add_theme_font_size_override("font_size", 14)
	detail_label.add_theme_color_override("font_color", Color("aebbd4"))
	identity.add_child(detail_label)
	var join_button := Button.new()
	join_button.text = "JOIN" if compatible else "VERSION %d" % int(server.get("protocol_version", 0))
	join_button.disabled = not compatible
	join_button.custom_minimum_size = Vector2(140.0, 46.0)
	join_button.pressed.connect(_join_lan_server.bind(String(server.get("address", "")), int(server.get("game_port", 0))))
	row.add_child(join_button)


func _join_lan_server(address: String, port: int) -> void:
	host_field.text = address
	port_field.text = str(port)
	_connect_online()


func _play_offline() -> void:
	bridge.stop()
	_stop_hosted_server()
	_set_scoreboard_open(false)
	latest_match_payload.clear()
	network_world.set_network_active(false)
	connection_screen.visible = false
	lobby_panel.visible = false
	match_panel.visible = false
	heat_intro_panel.visible = false
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
	_stop_hosted_server()
	_show_connection_screen("Disconnected. Ready to reconnect.")


func _show_connection_screen(message: String, is_error: bool = false) -> void:
	if bridge.role == NetworkBridge.Role.CLIENT:
		bridge.stop()
	_stop_hosted_server()
	network_world.set_network_active(false)
	_set_scoreboard_open(false)
	offline_sandbox.set_sandbox_active(false)
	latest_match_payload.clear()
	active_offer_token = ""
	active_offer_deadline = -1
	connection_screen.visible = true
	connection_form_panel.visible = true
	lobby_panel.visible = false
	match_panel.visible = false
	heat_intro_panel.visible = false
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
	_focus_connection_menu()


func _on_connected(peer_id: int) -> void:
	connection_screen.visible = true
	connection_form_panel.visible = false
	lobby_panel.visible = true
	network_world.set_network_active(false, false)
	connection_status.text = "Connected as peer %d." % peer_id
	connection_status.add_theme_color_override("font_color", Color("62ff9b"))
	audio_director.set_context(&"lobby")
	if input_profiles.uses_controller():
		ready_button.grab_focus()


func _on_lobby_state(state: Dictionary) -> void:
	bridge.latest_lobby_state = state.duplicate(true)
	var npc_count := int(state.get("npc_count", 0))
	var total_count := (state.get("players", []) as Array).size()
	var match_active := bool(state.get("match_active", false))
	if not match_active:
		_set_scoreboard_open(false)
		connection_screen.visible = true
		connection_form_panel.visible = false
		network_world.set_network_active(false, false)
	lobby_panel.visible = not match_active
	lobby_label.text = "PLAYERS  %d / %d    ·    READY  %d / %d    ·    NPCS  %d" % [
		total_count,
		state.get("player_limit", 32),
		state.get("ready_human_count", 0),
		total_count - npc_count,
		npc_count,
	]
	var is_leader := int(state.get("leader_id", 0)) == bridge.local_peer_id
	_rebuild_lobby_roster(state, is_leader)
	var local_ready := false
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == bridge.local_peer_id:
			local_ready = bool(player.get("ready", false))
			break
	_applying_lobby_state = true
	rounds_control.value = int(state.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN))
	player_limit_control.max_value = int(state.get("server_capacity", GameConstants.MAX_PLAYERS))
	player_limit_control.value = int(state.get("player_limit", GameConstants.DEFAULT_MAX_PLAYERS))
	npcs_button.button_pressed = bool(state.get("npcs_enabled", false))
	ready_button.button_pressed = local_ready
	_applying_lobby_state = false
	ready_button.disabled = match_active
	ready_button.text = "READY ✓" if local_ready else "READY FOR LAUNCH"
	var settings_editable := is_leader and not match_active
	rounds_control.editable = settings_editable
	player_limit_control.editable = settings_editable
	npcs_button.disabled = not settings_editable
	var can_supply_opponent := total_count >= GameConstants.MIN_PLAYERS or bool(state.get("npcs_enabled", false))
	start_button.disabled = not settings_editable or not can_supply_opponent or not bool(state.get("all_humans_ready", false))
	var human_count := total_count - npc_count
	if not is_leader:
		start_button.text = "Waiting for Lobby Leader"
	elif not bool(state.get("all_humans_ready", false)):
		start_button.text = "Waiting for Players to Ready"
	elif human_count == 1 and not bool(state.get("npcs_enabled", false)):
		start_button.text = "Enable NPCs to Start Solo"
	elif human_count == 1:
		start_button.text = "Start Match with NPCs"
	else:
		start_button.text = "Start Match"
	start_button.tooltip_text = "Every connected human must ready up first." if not bool(state.get("all_humans_ready", false)) else "NPCs fill open seats before launch." if bool(state.get("npcs_enabled", false)) else "Launch the configured match."
	if input_profiles.uses_controller() and get_viewport().gui_get_focus_owner() == null:
		ready_button.grab_focus()


func _rebuild_lobby_roster(state: Dictionary, is_leader: bool) -> void:
	for child in lobby_roster.get_children():
		lobby_roster.remove_child(child)
		child.queue_free()
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		var peer_id := int(player.get("peer_id", 0))
		var is_npc := bool(player.get("is_npc", false))
		var is_ready := bool(player.get("ready", false))
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 42.0
		row.add_theme_constant_override("separation", 10)
		lobby_roster.add_child(row)
		var name_label := Label.new()
		name_label.text = String(player.get("display_name", "Pilot"))
		name_label.custom_minimum_size.x = 300.0
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Color("fff36a") if peer_id == int(state.get("leader_id", 0)) else Color("e8f5ff"))
		row.add_child(name_label)
		var role_label := Label.new()
		role_label.text = "HOST" if peer_id == int(state.get("leader_id", 0)) else "NPC" if is_npc else "PILOT"
		role_label.custom_minimum_size.x = 90.0
		role_label.add_theme_color_override("font_color", Color("d39cff"))
		row.add_child(role_label)
		if is_npc:
			var difficulty_control := OptionButton.new()
			difficulty_control.name = "NpcDifficulty"
			difficulty_control.custom_minimum_size = Vector2(170.0, 38.0)
			for difficulty in NpcPilotController.DIFFICULTY_NAMES.size():
				difficulty_control.add_item(NpcPilotController.difficulty_name(difficulty), difficulty)
			difficulty_control.select(clampi(int(player.get("npc_difficulty", NpcPilotController.Difficulty.NEUTRAL)), NpcPilotController.Difficulty.PASSIVE, NpcPilotController.Difficulty.INSANE))
			difficulty_control.disabled = not is_leader or bool(state.get("match_active", false))
			difficulty_control.tooltip_text = "NPC difficulty changes reaction speed, aim, movement, firing, shields, and awareness."
			difficulty_control.item_selected.connect(_on_npc_difficulty_selected.bind(peer_id))
			row.add_child(difficulty_control)
		else:
			var status_label := Label.new()
			status_label.text = "READY" if is_ready else "NOT READY"
			status_label.custom_minimum_size.x = 125.0
			status_label.add_theme_color_override("font_color", Color("62ff9b") if is_ready else Color("ff7994"))
			row.add_child(status_label)
		if is_leader and peer_id != bridge.local_peer_id and not is_npc and not bool(state.get("match_active", false)):
			var eject_button := Button.new()
			eject_button.text = "EJECT"
			eject_button.custom_minimum_size = Vector2(100.0, 38.0)
			eject_button.tooltip_text = "Remove this player from the lobby."
			eject_button.pressed.connect(_on_eject_pressed.bind(peer_id))
			row.add_child(eject_button)


func _on_rounds_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_lobby_config(roundi(value))


func _on_player_limit_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_player_limit(roundi(value))


func _on_npcs_toggled(enabled: bool) -> void:
	if not _applying_lobby_state:
		bridge.send_npcs_enabled(enabled)


func _on_npc_difficulty_selected(index: int, npc_peer_id: int) -> void:
	bridge.send_npc_difficulty(npc_peer_id, index)


func _on_ready_toggled(ready: bool) -> void:
	if not _applying_lobby_state:
		bridge.send_ready_state(ready)


func _on_eject_pressed(peer_id: int) -> void:
	bridge.send_eject_player(peer_id)


func _on_match_event(event_type: StringName, _server_tick: int, payload: Dictionary) -> void:
	if event_type == &"REQUEST_REJECTED":
		_return_to_lobby_requested = false
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
		var entering_match := String(payload.get("state_name", "LOBBY")) != "LOBBY"
		if entering_match:
			network_world.set_network_active(true)
		else:
			network_world.reset_match_presentation()
			network_world.set_network_active(false, false)
		connection_screen.visible = not entering_match
		if not entering_match:
			connection_form_panel.visible = false
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


func _process(delta: float) -> void:
	if not binding_capture_action.is_empty():
		binding_capture_seconds = maxf(binding_capture_seconds - delta, 0.0)
		if binding_capture_seconds <= 0.0:
			_cancel_binding_capture()
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
	if DisplayServer.get_name() == "headless" or input_profiles == null:
		return
	var gameplay_visible := offline_sandbox.visible or network_world.visible
	var interactive_overlay := connection_screen.visible or settings_panel.visible or pause_overlay.visible or draft_panel.visible or win_overlay.visible
	var desired_mode := Input.MOUSE_MODE_HIDDEN if input_profiles.uses_controller() and gameplay_visible and not interactive_overlay else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != desired_mode:
		Input.mouse_mode = desired_mode


func _show_draft_offer(payload: Dictionary) -> void:
	active_offer_token = String(payload.get("offer_token", ""))
	active_offer_deadline = int(payload.get("deadline_tick", -1))
	draft_bye_label.visible = false
	var card_ids := payload.get("card_ids", []) as Array
	for index in draft_buttons.size():
		var button := draft_buttons[index]
		button.visible = index < card_ids.size()
		draft_rarity_labels[index].visible = button.visible
		button.disabled = false
		button.set_meta("card_id", StringName(card_ids[index]) if index < card_ids.size() else &"")
		if index >= card_ids.size():
			continue
		var card := card_catalog.get_card(StringName(card_ids[index]))
		var current_stacks := _local_build_stack(card.card_id) if card != null else 0
		button.text = "%d\n\n%s\n%s\n\n%s\n\nSTACK %d → %d" % [
			index + 1,
			card.display_name,
			card.category_name().to_upper(),
			card.description,
			current_stacks,
			current_stacks + 1,
		] if card != null else String(card_ids[index])
		if card != null:
			var rarity_color := card.rarity_color()
			button.set_meta("rarity_color", rarity_color)
			button.add_theme_color_override("font_color", Color("f4fbff"))
			button.add_theme_stylebox_override("normal", _draft_card_style(rarity_color, false))
			button.add_theme_stylebox_override("hover", _draft_card_style(rarity_color.lightened(0.12), true))
			button.add_theme_stylebox_override("pressed", _draft_card_style(rarity_color.lightened(0.22), true))
			button.add_theme_stylebox_override("focus", _draft_card_style(rarity_color.lightened(0.24), true))
			button.add_theme_stylebox_override("disabled", _draft_card_style(rarity_color.darkened(0.25), false))
			var rarity_label := draft_rarity_labels[index]
			rarity_label.text = "%s  ·  %s TIER DROP" % [card.rarity_name().to_upper(), card.rarity_drop_chance_text()]
			rarity_label.add_theme_color_override("font_color", rarity_color.lightened(0.12))
			button.tooltip_text = "%s — %s (%s rarity-tier chance) — %s" % [card.display_name, card.rarity_name(), card.rarity_drop_chance_text(), card.description]
	draft_panel.visible = true
	for button in draft_buttons:
		if button.visible and not button.disabled:
			button.grab_focus()
			break
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
	var selected_color: Color = button.get_meta("rarity_color", Color("42e8ff"))
	button.add_theme_stylebox_override("disabled", _draft_card_style(selected_color, true))


func _show_draft_bye(deadline_tick: int) -> void:
	active_offer_token = ""
	active_offer_deadline = deadline_tick
	for index in draft_buttons.size():
		draft_buttons[index].visible = false
		draft_rarity_labels[index].visible = false
	draft_bye_label.visible = true
	draft_panel.visible = true


func _update_match_presentation() -> void:
	var state_name := String(latest_match_payload.get("state_name", "LOBBY"))
	if state_name == "LOBBY":
		match_panel.visible = false
		heat_intro_panel.visible = false
		network_world.set_match_status("")
		draft_panel.visible = false
		_set_win_screen_visible(false)
		lobby_panel.visible = bridge.role == NetworkBridge.Role.CLIENT
		connection_screen.visible = bridge.role == NetworkBridge.Role.CLIENT
		if connection_screen.visible:
			connection_form_panel.visible = false
		network_world.set_network_active(false, false)
		return
	lobby_panel.visible = false
	match_panel.visible = false
	if state_name != "DRAFT":
		draft_panel.visible = false
	_set_win_screen_visible(state_name == "MATCH_RESULT")
	var deadline := int(latest_match_payload.get("deadline_tick", -1))
	if state_name == "DRAFT" and active_offer_deadline >= 0:
		deadline = active_offer_deadline
	var seconds_left := maxf(float(deadline - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0) if deadline >= 0 else 0.0
	_update_heat_intro(state_name, seconds_left)
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
		status = "★ VICTORY · %s ★" % _player_name(int(latest_match_payload.get("match_winner", 0)))
		_update_results_screen()
	match_label.text = status
	network_world.set_match_status(_combat_hud_status(state_name, seconds_left))
	if state_name == "DRAFT":
		var bye_peer_id := int(latest_match_payload.get("draft_bye_peer_id", 0))
		if bye_peer_id != 0 and bye_peer_id == bridge.local_peer_id:
			if not draft_bye_label.visible or not draft_panel.visible:
				_show_draft_bye(deadline)
			draft_title.text = "ROUND WINNER BYE · OTHERS DRAFTING · %.1fs" % seconds_left
		elif not draft_bye_label.visible:
			draft_title.text = "CHOOSE 1 OF 5 UPGRADES · %.1fs · CLICK OR PRESS 1–5" % seconds_left


func _update_heat_intro(state_name: String, seconds_left: float) -> void:
	if heat_intro_panel == null:
		return
	if state_name == "COUNTDOWN":
		heat_intro_panel.visible = true
		heat_intro_panel.modulate.a = 1.0
		heat_intro_kicker.text = "ROUND %d  //  HEAT %d" % [
			int(latest_match_payload.get("round_number", 0)),
			int(latest_match_payload.get("heat_number", 0)),
		]
		var beginning := seconds_left <= HEAT_BEGIN_LEAD_SECONDS + 0.0001
		heat_intro_title.text = "BEGIN" if beginning else "READY"
		heat_intro_subtitle.text = "WEAPONS ENGAGING" if beginning else "WEAPONS LOCKED  ·  BEGIN IN %.1f" % seconds_left
		return
	if state_name == "ACTIVE_HEAT":
		var entered_tick := int(latest_match_payload.get("entered_tick", network_world.latest_server_tick))
		var elapsed := maxf(float(network_world.latest_server_tick - entered_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0)
		if elapsed < HEAT_BEGIN_FADE_SECONDS:
			heat_intro_panel.visible = true
			heat_intro_panel.modulate.a = 1.0 - clampf(elapsed / HEAT_BEGIN_FADE_SECONDS, 0.0, 1.0)
			heat_intro_kicker.text = "ROUND %d  //  HEAT %d" % [
				int(latest_match_payload.get("round_number", 0)),
				int(latest_match_payload.get("heat_number", 0)),
			]
			heat_intro_title.text = "BEGIN"
			heat_intro_subtitle.text = "WEAPONS HOT  ·  LAST SHIP STANDING"
			return
	heat_intro_panel.visible = false
	heat_intro_panel.modulate.a = 1.0


func _combat_hud_status(state_name: String, seconds_left: float) -> String:
	var parts := PackedStringArray([
		state_name.replace("_", " ").to_upper(),
		"R%d H%d" % [int(latest_match_payload.get("round_number", 0)), int(latest_match_payload.get("heat_number", 0))],
	])
	if state_name == "ACTIVE_HEAT":
		parts.append("%d ALIVE" % (latest_match_payload.get("alive_peer_ids", []) as Array).size())
		var overtime_tick := int(latest_match_payload.get("overtime_start_tick", -1))
		if overtime_tick >= 0:
			parts.append("OVERTIME" if network_world.latest_server_tick >= overtime_tick else "OT %.0fs" % maxf(float(overtime_tick - network_world.latest_server_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND, 0.0))
	elif state_name in ["COUNTDOWN", "HEAT_RESULT", "ROUND_RESULT"]:
		parts.append("%.1fs" % seconds_left)
	return " · ".join(parts)


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
	var state_name := String(latest_match_payload.get("state_name", "LOBBY")).replace("_", " ").capitalize()
	scoreboard_context_label.text = "%s  ·  ROUND %d  ·  HEAT %d  ·  %d PILOTS" % [
		state_name,
		int(latest_match_payload.get("round_number", 0)),
		int(latest_match_payload.get("heat_number", 0)),
		_result_peer_ids().size(),
	]
	var signature := "%s|%s|%s|%s" % [
		latest_match_payload.get("participant_peer_ids", []),
		latest_match_payload.get("scores", {}),
		latest_match_payload.get("builds", {}),
		bridge.local_peer_id,
	]
	if signature == _scoreboard_signature:
		return
	_scoreboard_signature = signature
	for child in scoreboard_rows_container.get_children():
		scoreboard_rows_container.remove_child(child)
		child.free()
	var peer_ids := _result_peer_ids()
	for index in peer_ids.size():
		_add_scoreboard_row(index + 1, peer_ids[index])


func _set_scoreboard_open(open: bool) -> void:
	scoreboard_open = open and _scoreboard_available()
	if scoreboard_panel != null:
		scoreboard_panel.visible = scoreboard_open
	if scoreboard_open:
		_scoreboard_signature = ""
		_update_scoreboard()


func _scoreboard_available() -> bool:
	if network_world == null or not network_world.visible or pause_overlay != null and pause_overlay.visible:
		return false
	return String(latest_match_payload.get("state_name", "LOBBY")) in ["DRAFT", "COUNTDOWN", "ACTIVE_HEAT", "HEAT_RESULT", "ROUND_RESULT"]


func _add_scoreboard_row(rank: int, peer_id: int) -> void:
	var is_local := peer_id == bridge.local_peer_id
	var accent := Color("fff36a") if is_local else (Color("42e8ff") if rank % 2 == 0 else Color("d39cff"))
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 58.0
	row_panel.set_meta("peer_id", peer_id)
	row_panel.set_meta("rank", rank)
	row_panel.add_theme_stylebox_override("panel", _results_row_style(accent, is_local))
	scoreboard_rows_container.add_child(row_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)
	var player_label := Label.new()
	player_label.text = "#%02d   %s%s" % [rank, _player_name(peer_id), "  ★ YOU" if is_local else ""]
	player_label.custom_minimum_size.x = 300.0
	player_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_label.add_theme_font_size_override("font_size", 19 if is_local else 17)
	player_label.add_theme_color_override("font_color", accent if is_local else Color("f4fbff"))
	row.add_child(player_label)
	var score := _result_score(peer_id)
	var heats_label := Label.new()
	heats_label.text = str(score.get("heat_wins", 0))
	heats_label.custom_minimum_size.x = 90.0
	heats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heats_label.add_theme_color_override("font_color", Color("73f7ff"))
	row.add_child(heats_label)
	var rounds_label := Label.new()
	rounds_label.text = str(score.get("round_wins", 0))
	rounds_label.custom_minimum_size.x = 100.0
	rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rounds_label.add_theme_color_override("font_color", Color("ff8ee8"))
	row.add_child(rounds_label)
	_add_result_build(row, peer_id, "ScoreboardBuildCards")


func _update_results_screen() -> void:
	var winner_id := int(latest_match_payload.get("match_winner", 0))
	results_winner_label.text = "★  %s  ★" % _player_name(winner_id).to_upper()
	var is_leader := bridge.local_peer_id != 0 and bridge.local_peer_id == int(bridge.latest_lobby_state.get("leader_id", 0))
	results_return_button.disabled = not is_leader or _return_to_lobby_requested
	if _return_to_lobby_requested:
		results_return_button.text = "RETURNING EVERYONE TO LOBBY…"
		results_return_button.tooltip_text = "Waiting for server confirmation."
	elif is_leader:
		results_return_button.text = "EXIT TO LOBBY"
		results_return_button.tooltip_text = "Close the final standings and return every connected player to the lobby."
	else:
		results_return_button.text = "WAITING FOR LOBBY LEADER"
		results_return_button.tooltip_text = "The lobby leader controls when everyone leaves the final standings."
	var signature := "%d|%s|%s" % [winner_id, latest_match_payload.get("scores", {}), latest_match_payload.get("builds", {})]
	if signature == _results_signature:
		return
	_results_signature = signature
	for child in results_standings_container.get_children():
		results_standings_container.remove_child(child)
		child.free()
	var peer_ids := _result_peer_ids()
	for index in peer_ids.size():
		_add_result_row(index + 1, peer_ids[index], peer_ids[index] == winner_id)


func _on_results_return_pressed() -> void:
	if results_return_button.disabled:
		return
	_return_to_lobby_requested = true
	_update_results_screen()
	bridge.send_return_to_lobby()


func _result_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_value in latest_match_payload.get("participant_peer_ids", []):
		var peer_id := int(peer_value)
		if peer_id != 0 and peer_id not in result:
			result.append(peer_id)
	var scores := latest_match_payload.get("scores", {}) as Dictionary
	for peer_value in scores.keys():
		var peer_id := int(peer_value)
		if peer_id != 0 and peer_id not in result:
			result.append(peer_id)
	var winner_id := int(latest_match_payload.get("match_winner", 0))
	if winner_id != 0 and winner_id not in result:
		result.append(winner_id)
	result.sort_custom(func(first: int, second: int) -> bool:
		var first_score := _result_score(first)
		var second_score := _result_score(second)
		var first_rounds := int(first_score.get("round_wins", 0))
		var second_rounds := int(second_score.get("round_wins", 0))
		if first_rounds != second_rounds:
			return first_rounds > second_rounds
		var first_heats := int(first_score.get("heat_wins", 0))
		var second_heats := int(second_score.get("heat_wins", 0))
		if first_heats != second_heats:
			return first_heats > second_heats
		return first < second
	)
	return result


func _result_score(peer_id: int) -> Dictionary:
	var scores := latest_match_payload.get("scores", {}) as Dictionary
	return scores.get(peer_id, scores.get(str(peer_id), {})) as Dictionary


func _result_build(peer_id: int) -> Dictionary:
	var builds := latest_match_payload.get("builds", {}) as Dictionary
	return builds.get(peer_id, builds.get(str(peer_id), {})) as Dictionary


func _add_result_build(parent: HBoxContainer, peer_id: int, container_name: String = "FinalBuildCards") -> void:
	var build := _result_build(peer_id)
	var build_flow := HFlowContainer.new()
	build_flow.name = container_name
	build_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_flow.add_theme_constant_override("h_separation", 6)
	build_flow.add_theme_constant_override("v_separation", 5)
	parent.add_child(build_flow)
	if build.is_empty():
		var base_label := Label.new()
		base_label.text = "BASE LOADOUT"
		base_label.add_theme_font_size_override("font_size", 15)
		base_label.add_theme_color_override("font_color", Color("8ba1c7"))
		build_flow.add_child(base_label)
		return
	var card_ids := build.keys()
	card_ids.sort_custom(func(first: Variant, second: Variant) -> bool:
		var first_card := card_catalog.get_card(StringName(first))
		var second_card := card_catalog.get_card(StringName(second))
		var first_name := first_card.display_name if first_card != null else String(first)
		var second_name := second_card.display_name if second_card != null else String(second)
		return first_name < second_name
	)
	for card_value in card_ids:
		var card_id := StringName(card_value)
		var card := card_catalog.get_card(card_id)
		var stacks := int(build[card_value])
		var chip := CardHoverButtonScript.new()
		chip.focus_mode = Control.FOCUS_NONE
		chip.mouse_default_cursor_shape = Control.CURSOR_HELP
		chip.text = "%s ×%d" % [card.display_name if card != null else String(card_id), stacks]
		chip.set_meta("card_id", card_id)
		chip.set_meta("stack_count", stacks)
		chip.add_theme_font_size_override("font_size", 14)
		if card != null:
			var rarity_color := card.rarity_color()
			chip.configure(card, stacks, _result_card_tooltip(card, stacks))
			chip.add_theme_color_override("font_color", rarity_color.lightened(0.2))
			chip.add_theme_color_override("font_hover_color", Color.WHITE)
			chip.add_theme_stylebox_override("normal", _result_card_chip_style(rarity_color, false))
			chip.add_theme_stylebox_override("hover", _result_card_chip_style(rarity_color, true))
			chip.add_theme_stylebox_override("pressed", _result_card_chip_style(rarity_color, true))
		build_flow.add_child(chip)


func _result_card_tooltip(card: CardDefinition, stacks: int) -> String:
	var lines := PackedStringArray([
		card.display_name.to_upper(),
		"%s · %s · %s TIER DROP" % [card.rarity_name().to_upper(), card.category_name().to_upper(), card.rarity_drop_chance_text()],
		"",
		card.description,
		"",
		"OWNED STACKS: %d" % stacks,
		"CARD STATS",
	])
	var stat_lines := PackedStringArray()
	var additive_names := card.additive_modifiers.keys()
	additive_names.sort()
	for property_value in additive_names:
		var property_name := String(property_value)
		var per_stack := float(card.additive_modifiers[property_value])
		stat_lines.append("%s  %+.2f each · %+.2f total" % [_card_stat_name(property_name), per_stack, per_stack * stacks])
	var multiplier_names := card.multiplicative_modifiers.keys()
	multiplier_names.sort()
	for property_value in multiplier_names:
		var property_name := String(property_value)
		var per_stack := float(card.multiplicative_modifiers[property_value])
		stat_lines.append("%s  ×%.2f each · ×%.2f total" % [_card_stat_name(property_name), per_stack, pow(per_stack, stacks)])
	var integer_names := card.integer_modifiers.keys()
	integer_names.sort()
	for property_value in integer_names:
		var property_name := String(property_value)
		var per_stack := int(card.integer_modifiers[property_value])
		stat_lines.append("%s  %+d each · %+d total" % [_card_stat_name(property_name), per_stack, per_stack * stacks])
	if card.special_behavior_id == &"beam_weapon":
		stat_lines.append("Weapon Form  Pulse beam")
	elif card.special_behavior_id == &"auto_repair":
		stat_lines.append("Special  Automatic hull repair")
	if stat_lines.is_empty():
		stat_lines.append("Special behavior described above")
	lines.append_array(stat_lines)
	return "\n".join(lines)


func _card_stat_name(property_name: String) -> String:
	return property_name.replace("_", " ").capitalize()


func _add_result_row(rank: int, peer_id: int, winner: bool) -> void:
	var accent := Color("fff36a") if winner else (Color("42e8ff") if rank % 2 == 0 else Color("d39cff"))
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 58.0
	row_panel.set_meta("peer_id", peer_id)
	row_panel.set_meta("rank", rank)
	row_panel.set_meta("winner", winner)
	row_panel.add_theme_stylebox_override("panel", _results_row_style(accent, winner))
	results_standings_container.add_child(row_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)
	var rank_label := Label.new()
	rank_label.text = "#%02d" % rank
	rank_label.custom_minimum_size.x = 60.0
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 19)
	rank_label.add_theme_color_override("font_color", accent)
	row.add_child(rank_label)
	var player_label := Label.new()
	player_label.text = "%s%s" % [_player_name(peer_id), "  ★" if winner else ""]
	player_label.custom_minimum_size.x = 230.0
	player_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_label.add_theme_font_size_override("font_size", 20 if winner else 18)
	player_label.add_theme_color_override("font_color", Color("fff36a") if winner else Color("f4fbff"))
	row.add_child(player_label)
	var score := _result_score(peer_id)
	var score_label := Label.new()
	score_label.text = "%d ROUNDS  ·  %d HEATS" % [int(score.get("round_wins", 0)), int(score.get("heat_wins", 0))]
	score_label.custom_minimum_size.x = 190.0
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color("73f7ff"))
	row.add_child(score_label)
	_add_result_build(row, peer_id)


func _add_results_column_heading(parent: HBoxContainer, text_value: String, width: float, expand: bool = false) -> void:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = width
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("8ba1c7"))
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)


func _results_row_style(accent: Color, winner: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.darkened(0.82), 0.9 if winner else 0.7)
	style.border_color = Color(accent, 0.92 if winner else 0.38)
	style.set_border_width_all(2 if winner else 1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _result_card_chip_style(color: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.76), 0.92 if hovered else 0.72)
	style.border_color = Color(color, 0.9 if hovered else 0.46)
	style.set_border_width_all(2 if hovered else 1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _handle_state_presentation(previous_state: String, state_name: String, payload: Dictionary) -> void:
	last_state_name = state_name
	if state_name == "LOBBY":
		_return_to_lobby_requested = false
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
		_return_to_lobby_requested = false
		audio_director.play_sfx(&"match_win", str(payload.get("entered_tick", 0)))


func _set_win_screen_visible(visible: bool) -> void:
	if win_overlay != null:
		win_overlay.visible = visible
	if results_panel != null:
		results_panel.visible = visible
	if not visible:
		_results_signature = ""
	elif results_return_button != null and not results_return_button.disabled:
		results_return_button.grab_focus()


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


func _lan_server_row_style(compatible: bool) -> StyleBoxFlat:
	var accent := Color("42e8ff") if compatible else Color("ff7994")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.darkened(0.82), 0.74)
	style.border_color = Color(accent, 0.52)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
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
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if lan_browser != null:
		lan_browser.stop()
	if bridge != null:
		bridge.stop()
	_stop_hosted_server()
