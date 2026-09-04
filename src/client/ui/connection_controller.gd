extends Node

## Owns connection forms, LAN discovery, hosted runtime, lobby options and appearance.
## The client coordinates navigation between gameplay and these screens.

const MatchPresetsScript = preload("res://src/shared/lobby/match_presets.gd")

const NavigationScript = preload("res://src/client/ui/screen_navigation.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const ShipPatternPreviewScript = preload("res://src/client/ui/ship_pattern_preview.gd")

var client: Node
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
var direct_password_field: LineEdit
var remember_password_button: CheckButton
var host_password_field: LineEdit
var connection_status: Label
var lan_servers_container: VBoxContainer
var lan_refresh_button: Button
var lan_browser: LanDiscoveryService
var _lan_servers: Array[Dictionary] = []
var _hosted_server_root: Node
var _hosted_server_bridge: NetworkBridge
var _hosted_server_multiplayer: MultiplayerAPI
var host_preset_control: OptionButton
var host_preset_note: Label
var lobby_preset_control: OptionButton
var lobby_preset_note: Label
var lobby_readiness_label: Label
var lobby_rules_label: Label
var lobby_roster_scroll: ScrollContainer
var lobby_host_controls: VBoxContainer
var lobby_label: Label
var version_label: Label
var lobby_roster: VBoxContainer
var ready_button: CheckButton
var rounds_control: SpinBox
var player_limit_control: SpinBox
var npc_all_difficulty_control: OptionButton
var npcs_button: CheckButton
var lobby_options_button: Button
var lobby_options_blocker: ColorRect
var lobby_options_popup: PanelContainer
var lobby_options_focus_return: Control
var powerups_button: CheckButton
var powerup_interval_control: SpinBox
var powerups_permanent_button: CheckButton
var overtime_start_control: SpinBox
var game_mode_control: OptionButton
var game_mode_note: Label
var team_count_row: HBoxContainer
var team_count_control: SpinBox
var ship_color_popup: PanelContainer
var ship_color_blocker: ColorRect
var ship_color_focus_return: Control
var random_color_button: Button
var ship_color_picker: ColorPicker
var ship_pattern_control: OptionButton
var ship_pattern_preview
var apply_ship_color_button: Button
var start_button: Button
var preferred_ship_color: Color = Color("42e8ff")
var pending_ship_color: Color = Color("42e8ff")
var preferred_ship_pattern: StringName = ShipAppearanceScript.SOLID
var pending_ship_pattern: StringName = ShipAppearanceScript.SOLID
var random_ship_color: bool = true
var connection_primary_button: Button
var direct_connect_button: Button
var host_join_button: Button
var lobby_settings_button: Button
var lobby_disconnect_button: Button
var _applying_lobby_state: bool = false
var _pending_password_host: String = ""
var _pending_password_port: int = 0
var _pending_password_value: String = ""
var _pending_remember_password: bool = false


func initialize(client_root: Node) -> void:
	client = client_root


func _create_connection_ui(configuration: Dictionary) -> void:
	client.interface_theme = DesignTokensScript.create_interface_theme()
	connection_canvas = CanvasLayer.new()
	connection_canvas.layer = 20
	connection_canvas.name = "ConnectionUI"
	client.add_child(connection_canvas)
	connection_screen = Control.new()
	connection_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_screen.theme = client.interface_theme
	connection_canvas.add_child(connection_screen)
	var background := NeonBackdrop.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_screen.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_screen.add_child(center)
	connection_form_panel = PanelContainer.new()
	connection_form_panel.custom_minimum_size = Vector2(780.0, 690.0)
	connection_form_panel.add_theme_stylebox_override("panel", client._panel_style(DesignTokensScript.INTERACTIVE, 0.96))
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
	version_label = Label.new()
	version_label.name = "VersionLabel"
	version_label.text = "%s  ·  VERSION %s" % [GameConstants.RELEASE_LABEL, GameConstants.GAME_VERSION]
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_color_override("font_color", Color("73f7ff"))
	version_label.add_theme_font_size_override("font_size", 15)
	content.add_child(version_label)
	name_field = _add_labeled_field(content, "Display name", "Pilot")
	name_field.max_length = 16
	connection_tabs = TabContainer.new()
	connection_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	connection_tabs.get_tab_bar().gui_input.connect(NavigationScript.handle_tab_bar_input.bind(connection_tabs))
	connection_tabs.custom_minimum_size = Vector2(720.0, 285.0)
	connection_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(connection_tabs)
	_create_lan_join_tab()
	_create_direct_join_tab(configuration)
	_create_host_tab(configuration)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	content.add_child(buttons)
	var lesson_button := Button.new()
	lesson_button.name = "GuidedIntroductionButton"
	lesson_button.text = "Learn to play"
	lesson_button.theme_type_variation = &"SecondaryButton"
	lesson_button.custom_minimum_size.y = 54.0
	lesson_button.pressed.connect(client._play_tutorial)
	buttons.add_child(lesson_button)
	var offline_button := Button.new()
	offline_button.text = "Combat Lab"
	offline_button.tooltip_text = "Offline combat lab: freely experiment with builds and targets."
	offline_button.theme_type_variation = &"PrimaryButton"
	offline_button.custom_minimum_size.y = 54.0
	offline_button.pressed.connect(client._play_offline)
	buttons.add_child(offline_button)
	connection_primary_button = offline_button
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.theme_type_variation = &"QuietButton"
	settings_button.custom_minimum_size.y = 54.0
	settings_button.pressed.connect(client._show_settings.bind(false))
	buttons.add_child(settings_button)
	client.credits_button = Button.new()
	client.credits_button.name = "CreditsButton"
	client.credits_button.text = "Credits"
	client.credits_button.theme_type_variation = &"QuietButton"
	client.credits_button.custom_minimum_size.y = 54.0
	client.credits_button.pressed.connect(client._show_credits)
	buttons.add_child(client.credits_button)
	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.theme_type_variation = &"DangerButton"
	quit_button.custom_minimum_size = Vector2(80.0, 54.0)
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
	lan_refresh_button.theme_type_variation = &"QuietButton"
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
	host_field = _add_compact_labeled_field(tab, "Server host or IP", configuration.get("host", "127.0.0.1"))
	port_field = _add_compact_labeled_field(tab, "Gameplay UDP port", str(configuration.get("port", GameConstants.DEFAULT_PORT)))
	direct_password_field = _add_compact_labeled_field(tab, "Lobby password", "")
	direct_password_field.secret = true
	direct_password_field.max_length = NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
	remember_password_button = CheckButton.new()
	remember_password_button.text = "Remember password for this server"
	remember_password_button.tooltip_text = "Saved only in this client's local settings after this server accepts the connection."
	tab.add_child(remember_password_button)
	host_field.text_changed.connect(_on_direct_host_changed)
	port_field.text_changed.connect(_on_direct_port_changed)
	_apply_remembered_password(host_field.text, int(port_field.text))
	var connect_center := CenterContainer.new()
	tab.add_child(connect_center)
	direct_connect_button = Button.new()
	direct_connect_button.name = "DirectConnectButton"
	direct_connect_button.text = "CONNECT TO SERVER"
	direct_connect_button.theme_type_variation = &"PrimaryButton"
	direct_connect_button.custom_minimum_size = Vector2(280.0, 48.0)
	direct_connect_button.pressed.connect(_connect_online)
	connect_center.add_child(direct_connect_button)


func _create_host_tab(configuration: Dictionary) -> void:
	var tab := VBoxContainer.new()
	tab.name = "HOST GAME"
	tab.add_theme_constant_override("separation", 10)
	connection_tabs.add_child(tab)
	var host_scroll := ScrollContainer.new()
	host_scroll.custom_minimum_size.y = 260.0
	host_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(host_scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 8)
	host_scroll.add_child(fields)
	host_preset_control = _create_preset_picker(fields)
	host_preset_note = _create_preset_note(fields)
	host_preset_control.item_selected.connect(func(index: int) -> void:
		host_preset_note.text = _preset_description(index)
	)
	server_name_field = _add_compact_labeled_field(fields, "Server name", "Super Star Arena")
	server_name_field.max_length = LanDiscoveryProtocol.MAX_SERVER_NAME_LENGTH
	host_port_field = _add_compact_labeled_field(fields, "Gameplay UDP port", str(configuration.get("port", GameConstants.DEFAULT_PORT)))
	host_password_field = _add_compact_labeled_field(fields, "Required lobby password", "")
	host_password_field.secret = true
	host_password_field.max_length = NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
	var host_center := CenterContainer.new()
	fields.add_child(host_center)
	host_join_button = Button.new()
	host_join_button.name = "HostJoinButton"
	host_join_button.text = "HOST & JOIN"
	host_join_button.theme_type_variation = &"PrimaryButton"
	host_join_button.custom_minimum_size = Vector2(280.0, 48.0)
	host_join_button.pressed.connect(_host_online)
	host_center.add_child(host_join_button)


func _create_modal_blocker(blocker_name: String) -> ColorRect:
	var blocker := ColorRect.new()
	blocker.name = blocker_name
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.color = Color(DesignTokensScript.BACKGROUND, 0.78)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.focus_mode = Control.FOCUS_NONE
	blocker.visible = false
	return blocker


func _create_lobby_panel() -> void:
	lobby_panel = PanelContainer.new()
	lobby_panel.set_anchors_preset(Control.PRESET_CENTER)
	lobby_panel.position = Vector2(-550.0, -340.0)
	lobby_panel.custom_minimum_size = Vector2(1100.0, 680.0)
	lobby_panel.theme = client.interface_theme
	lobby_panel.add_theme_stylebox_override("panel", client._panel_style(DesignTokensScript.INTERACTIVE, 0.96))
	lobby_panel.visible = false
	connection_canvas.add_child(lobby_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	lobby_panel.add_child(content)
	var title := Label.new()
	title.text = "✦  ONLINE LOBBY  ✦"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)
	lobby_label = Label.new()
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_label.add_theme_font_size_override("font_size", 20)
	lobby_label.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(lobby_label)
	lobby_rules_label = Label.new()
	lobby_rules_label.name = "LobbyRulesSummary"
	lobby_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_rules_label.add_theme_font_size_override("font_size", 16)
	content.add_child(lobby_rules_label)
	lobby_readiness_label = Label.new()
	lobby_readiness_label.name = "LobbyReadinessSummary"
	lobby_readiness_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_readiness_label.custom_minimum_size.x = 1040.0
	lobby_readiness_label.add_theme_font_size_override("font_size", 16)
	content.add_child(lobby_readiness_label)
	var player_scroll := ScrollContainer.new()
	lobby_roster_scroll = player_scroll
	player_scroll.name = "LobbyRosterScroll"
	player_scroll.follow_focus = true
	player_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	player_scroll.custom_minimum_size = Vector2(1040.0, 260.0)
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(player_scroll)
	lobby_roster = VBoxContainer.new()
	lobby_roster.add_theme_constant_override("separation", 7)
	lobby_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_scroll.add_child(lobby_roster)
	lobby_host_controls = VBoxContainer.new()
	lobby_host_controls.name = "HostConfiguration"
	lobby_host_controls.add_theme_constant_override("separation", 10)
	var rounds_row := HBoxContainer.new()
	lobby_host_controls.add_child(rounds_row)
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
	lobby_host_controls.add_child(limit_row)
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
	npcs_button.theme_type_variation = &"SettingToggle"
	npcs_button.custom_minimum_size.y = 48.0
	npcs_button.toggled.connect(_on_npcs_toggled)
	lobby_host_controls.add_child(npcs_button)
	var npc_difficulty_row := HBoxContainer.new()
	npc_difficulty_row.add_theme_constant_override("separation", 14)
	lobby_host_controls.add_child(npc_difficulty_row)
	var npc_difficulty_label := Label.new()
	npc_difficulty_label.text = "Set all NPC difficulties"
	npc_difficulty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_difficulty_row.add_child(npc_difficulty_label)
	npc_all_difficulty_control = OptionButton.new()
	npc_all_difficulty_control.custom_minimum_size = Vector2(190.0, 42.0)
	for difficulty in NpcPilotController.DIFFICULTY_NAMES.size():
		npc_all_difficulty_control.add_item(NpcPilotController.difficulty_name(difficulty), difficulty)
	npc_all_difficulty_control.select(NpcPilotController.Difficulty.NEUTRAL)
	npc_all_difficulty_control.item_selected.connect(_on_all_npc_difficulty_selected)
	npc_difficulty_row.add_child(npc_all_difficulty_control)
	lobby_options_button = Button.new()
	lobby_options_button.text = "MATCH SETUP"
	lobby_options_button.theme_type_variation = &"SecondaryButton"
	lobby_options_button.custom_minimum_size.y = 48.0
	lobby_options_button.pressed.connect(_show_lobby_options)

	_create_lobby_options_popup()
	_create_ship_color_popup()
	var launch_actions := HBoxContainer.new()
	launch_actions.add_theme_constant_override("separation", 12)
	content.add_child(launch_actions)
	ready_button = CheckButton.new()
	ready_button.text = "READY FOR LAUNCH"
	ready_button.theme_type_variation = &"SuccessToggle"
	ready_button.custom_minimum_size.y = 52.0
	ready_button.toggled.connect(_on_ready_toggled)
	ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_actions.add_child(ready_button)
	start_button = Button.new()
	start_button.text = "Start Match"
	start_button.theme_type_variation = &"PrimaryButton"
	start_button.custom_minimum_size.y = 54.0
	start_button.pressed.connect(client.bridge.send_start_match)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_actions.add_child(start_button)
	var lobby_actions := HBoxContainer.new()
	lobby_actions.add_theme_constant_override("separation", 12)
	content.add_child(lobby_actions)
	lobby_options_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_actions.add_child(lobby_options_button)
	lobby_settings_button = Button.new()
	lobby_settings_button.name = "LobbySettingsButton"
	lobby_settings_button.text = "Settings"
	lobby_settings_button.theme_type_variation = &"SecondaryButton"
	lobby_settings_button.custom_minimum_size.y = 54.0
	lobby_settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_settings_button.tooltip_text = "Configure your display, audio, and controls without leaving the lobby."
	lobby_settings_button.pressed.connect(client._show_settings.bind(false))
	lobby_actions.add_child(lobby_settings_button)
	lobby_disconnect_button = Button.new()
	lobby_disconnect_button.name = "LobbyDisconnectButton"
	lobby_disconnect_button.text = "Disconnect"
	lobby_disconnect_button.theme_type_variation = &"DangerButton"
	lobby_disconnect_button.custom_minimum_size.y = 54.0
	lobby_disconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_disconnect_button.pressed.connect(client._disconnect_online)
	lobby_actions.add_child(lobby_disconnect_button)


func _create_lobby_options_popup() -> void:
	lobby_options_blocker = _create_modal_blocker("LobbyOptionsBlocker")
	connection_canvas.add_child(lobby_options_blocker)
	lobby_options_popup = PanelContainer.new()
	lobby_options_popup.name = "LobbyOptions"
	lobby_options_popup.set_anchors_preset(Control.PRESET_CENTER)
	lobby_options_popup.position = Vector2(-400.0, -330.0)
	lobby_options_popup.custom_minimum_size = Vector2(800.0, 660.0)
	lobby_options_popup.theme = client.interface_theme
	lobby_options_popup.add_theme_stylebox_override("panel", client._panel_style(DesignTokensScript.BRAND_MAGENTA, 0.98))
	lobby_options_popup.visible = false
	connection_canvas.add_child(lobby_options_popup)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	lobby_options_popup.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(750.0, 550.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	outer.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	lobby_preset_control = _create_preset_picker(content)
	lobby_preset_note = _create_preset_note(content)
	lobby_preset_control.item_selected.connect(_on_lobby_preset_selected)
	content.add_child(lobby_host_controls)
	var title := Label.new()
	title.text = "MATCH OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("d39cff"))
	content.add_child(title)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 14)
	content.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "Game mode"
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(mode_label)
	game_mode_control = OptionButton.new()
	game_mode_control.custom_minimum_size = Vector2(300.0, 44.0)
	for mode in GameModeRules.MODE_NAMES.size():
		game_mode_control.add_item(GameModeRules.mode_name(mode), mode)
	game_mode_control.select(GameModeRules.Mode.DEATH_MATCH)
	game_mode_control.item_selected.connect(_on_game_mode_selected)
	mode_row.add_child(game_mode_control)
	game_mode_note = Label.new()
	game_mode_note.text = GameModeRules.mode_description(GameModeRules.Mode.DEATH_MATCH)
	game_mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_mode_note.add_theme_color_override("font_color", Color("73f7ff"))
	content.add_child(game_mode_note)
	team_count_row = HBoxContainer.new()
	team_count_row.name = "TeamCountRow"
	team_count_row.add_theme_constant_override("separation", 14)
	team_count_row.visible = false
	content.add_child(team_count_row)
	var team_count_label := Label.new()
	team_count_label.text = "Number of teams"
	team_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_count_row.add_child(team_count_label)
	team_count_control = SpinBox.new()
	team_count_control.min_value = GameModeRules.MIN_TEAM_COUNT
	team_count_control.max_value = GameModeRules.MAX_TEAM_COUNT
	team_count_control.value = GameModeRules.DEFAULT_TEAM_COUNT
	team_count_control.step = 1.0
	team_count_control.custom_minimum_size = Vector2(150.0, 44.0)
	team_count_control.tooltip_text = "Team Death Match supports two through eight teams. Every configured team needs at least one participant."
	team_count_control.value_changed.connect(_on_team_count_changed)
	team_count_row.add_child(team_count_control)
	powerups_button = CheckButton.new()
	powerups_button.text = "Random spawn powerups"
	powerups_button.theme_type_variation = &"SettingToggle"
	powerups_button.tooltip_text = "King of the Hill enables temporary drops by default. When enabled, a server-owned Rare-or-better card appears during active combat at the configured interval."
	powerups_button.custom_minimum_size.y = 48.0
	powerups_button.toggled.connect(_on_powerups_toggled)
	var powerup_row := HBoxContainer.new()
	powerup_row.add_theme_constant_override("separation", 14)
	powerup_row.add_child(powerups_button)
	powerups_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var interval_label := Label.new()
	interval_label.text = "Every"
	powerup_row.add_child(interval_label)
	powerup_interval_control = SpinBox.new()
	powerup_interval_control.min_value = 5.0
	powerup_interval_control.max_value = 90.0
	powerup_interval_control.step = 1.0
	powerup_interval_control.value = 20.0
	powerup_interval_control.suffix = " sec"
	powerup_interval_control.custom_minimum_size = Vector2(130.0, 44.0)
	powerup_interval_control.value_changed.connect(_on_powerup_interval_changed)
	powerup_row.add_child(powerup_interval_control)
	content.add_child(powerup_row)
	powerups_permanent_button = CheckButton.new()
	powerups_permanent_button.text = "Powerup cards persist for the full match"
	powerups_permanent_button.theme_type_variation = &"SettingToggle"
	powerups_permanent_button.tooltip_text = "Off by default. When off, arena-drop cards are removed after the heat."
	powerups_permanent_button.toggled.connect(_on_powerups_permanent_toggled)
	content.add_child(powerups_permanent_button)
	var overtime_row := HBoxContainer.new()
	overtime_row.add_theme_constant_override("separation", 14)
	content.add_child(overtime_row)
	var overtime_label := Label.new()
	overtime_label.text = "Overtime begins"
	overtime_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overtime_row.add_child(overtime_label)
	overtime_start_control = SpinBox.new()
	overtime_start_control.min_value = 30.0
	overtime_start_control.max_value = 120.0
	overtime_start_control.step = 1.0
	overtime_start_control.value = GameConstants.OVERTIME_START_SECONDS
	overtime_start_control.suffix = " sec"
	overtime_start_control.custom_minimum_size = Vector2(150.0, 44.0)
	overtime_start_control.value_changed.connect(_on_overtime_start_changed)
	overtime_row.add_child(overtime_start_control)
	var powerup_note := Label.new()
	powerup_note.text = "Rare-or-better drops appear at safe map positions. Temporary drops leave your inventory after each heat unless permanence is enabled."
	powerup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	powerup_note.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(powerup_note)
	var close_button := Button.new()
	close_button.text = "DONE"
	close_button.theme_type_variation = &"PrimaryButton"
	close_button.custom_minimum_size.y = 48.0
	close_button.pressed.connect(_hide_lobby_options)
	outer.add_child(close_button)


func _create_ship_color_popup() -> void:
	ship_color_blocker = _create_modal_blocker("ShipColorBlocker")
	connection_canvas.add_child(ship_color_blocker)
	ship_color_popup = PanelContainer.new()
	ship_color_popup.name = "ShipColorPicker"
	ship_color_popup.set_anchors_preset(Control.PRESET_CENTER)
	ship_color_popup.position = Vector2(-350.0, -330.0)
	ship_color_popup.custom_minimum_size = Vector2(700.0, 660.0)
	ship_color_popup.theme = client.interface_theme
	ship_color_popup.add_theme_stylebox_override("panel", client._panel_style(DesignTokensScript.INTERACTIVE, 0.99))
	ship_color_popup.visible = false
	connection_canvas.add_child(ship_color_popup)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	ship_color_popup.add_child(content)
	var title := Label.new()
	title.text = "CUSTOMIZE YOUR SHIP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("73f7ff"))
	content.add_child(title)
	var note := Label.new()
	note.text = "Combine any colour with a hull pattern, then apply your appearance."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(note)
	var appearance_row := HBoxContainer.new()
	appearance_row.add_theme_constant_override("separation", 18)
	content.add_child(appearance_row)
	ship_pattern_preview = ShipPatternPreviewScript.new()
	ship_pattern_preview.set_appearance(preferred_ship_color, preferred_ship_pattern)
	appearance_row.add_child(ship_pattern_preview)
	var pattern_column := VBoxContainer.new()
	pattern_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_row.add_child(pattern_column)
	var pattern_label := Label.new()
	pattern_label.text = "HULL PATTERN"
	pattern_label.add_theme_color_override("font_color", Color("e8f5ff"))
	pattern_column.add_child(pattern_label)
	ship_pattern_control = OptionButton.new()
	ship_pattern_control.custom_minimum_size.y = 48.0
	for pattern in ShipAppearanceScript.PATTERNS:
		ship_pattern_control.add_item(ShipAppearanceScript.display_name(pattern))
	ship_pattern_control.select(ShipAppearanceScript.PATTERNS.find(preferred_ship_pattern))
	ship_pattern_control.item_selected.connect(_on_ship_pattern_selected)
	pattern_column.add_child(ship_pattern_control)
	ship_color_picker = ColorPicker.new()
	ship_color_picker.color = preferred_ship_color
	ship_color_picker.edit_alpha = false
	ship_color_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	ship_color_picker.sliders_visible = false
	ship_color_picker.presets_visible = false
	ship_color_picker.sampler_visible = false
	ship_color_picker.custom_minimum_size = Vector2(640.0, 300.0)
	ship_color_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ship_color_picker.color_changed.connect(_on_ship_color_changed)
	content.add_child(ship_color_picker)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	random_color_button = Button.new()
	random_color_button.text = "RANDOM COLOUR"
	random_color_button.theme_type_variation = &"SecondaryButton"
	random_color_button.custom_minimum_size = Vector2(180.0, 48.0)
	random_color_button.tooltip_text = "Ask the server for a high-contrast random ship colour."
	random_color_button.pressed.connect(_on_random_color_pressed)
	actions.add_child(random_color_button)
	var cancel_button := Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.theme_type_variation = &"QuietButton"
	cancel_button.custom_minimum_size = Vector2(160.0, 48.0)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(_cancel_ship_color)
	actions.add_child(cancel_button)
	apply_ship_color_button = Button.new()
	apply_ship_color_button.text = "APPLY APPEARANCE"
	apply_ship_color_button.theme_type_variation = &"PrimaryButton"
	apply_ship_color_button.custom_minimum_size = Vector2(210.0, 48.0)
	apply_ship_color_button.pressed.connect(_apply_ship_color)
	actions.add_child(apply_ship_color_button)


func _add_labeled_field(parent: VBoxContainer, label_text: String, initial_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var field := LineEdit.new()
	field.text = initial_text
	field.custom_minimum_size.y = 48.0
	parent.add_child(field)
	return field


func _add_compact_labeled_field(parent: VBoxContainer, label_text: String, initial_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 210.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var field := LineEdit.new()
	field.text = initial_text
	field.custom_minimum_size.y = 48.0
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field


func _load_appearance_settings() -> void:
	var config := ConfigFile.new()
	if config.load(AudioDirector.SETTINGS_PATH) != OK:
		return
	random_ship_color = bool(config.get_value("appearance", "random_ship_color", true))
	var saved_color := String(config.get_value("appearance", "ship_color", preferred_ship_color.to_html(false)))
	if not ServerLobby._normalized_ship_color(saved_color).is_empty():
		preferred_ship_color = Color.from_string("#%s" % saved_color.trim_prefix("#"), preferred_ship_color)
	var saved_pattern := ShipAppearanceScript.normalized_pattern(String(config.get_value("appearance", "ship_pattern", ShipAppearanceScript.SOLID)))
	if not saved_pattern.is_empty():
		preferred_ship_pattern = saved_pattern


func _save_appearance_settings() -> void:
	var config := ConfigFile.new()
	config.load(AudioDirector.SETTINGS_PATH)
	config.set_value("appearance", "random_ship_color", random_ship_color)
	config.set_value("appearance", "ship_color", preferred_ship_color.to_html(false))
	config.set_value("appearance", "ship_pattern", String(preferred_ship_pattern))
	config.save(AudioDirector.SETTINGS_PATH)


func _on_direct_host_changed(address: String) -> void:
	_apply_remembered_password(address, _remembered_password_port())


func _on_direct_port_changed(_port_text: String) -> void:
	_apply_remembered_password(host_field.text, _remembered_password_port())


func _apply_remembered_password(address: String, port: int) -> void:
	if direct_password_field == null or remember_password_button == null:
		return
	var remembered := _remembered_password_for_endpoint(address, port)
	direct_password_field.text = remembered
	remember_password_button.button_pressed = not remembered.is_empty()


func _remembered_password_for_endpoint(address: String, port: int) -> String:
	var key := _password_settings_key(address, port)
	if key.is_empty():
		return ""
	var config := ConfigFile.new()
	if config.load(AudioDirector.SETTINGS_PATH) != OK:
		return ""
	var remembered := String(config.get_value("lobby_passwords", key, ""))
	return remembered if NetworkProtocol.is_valid_lobby_password(remembered) else ""


func _commit_pending_password_preference() -> void:
	var key := _password_settings_key(_pending_password_host, _pending_password_port)
	if key.is_empty():
		return
	var config := ConfigFile.new()
	config.load(AudioDirector.SETTINGS_PATH)
	if _pending_remember_password and NetworkProtocol.is_valid_lobby_password(_pending_password_value):
		config.set_value("lobby_passwords", key, _pending_password_value)
	elif config.has_section_key("lobby_passwords", key):
		config.erase_section_key("lobby_passwords", key)
	config.save(AudioDirector.SETTINGS_PATH)
	_pending_password_host = ""
	_pending_password_port = 0
	_pending_password_value = ""
	_pending_remember_password = false


static func _password_settings_key(address: String, port: int) -> String:
	var normalized := address.strip_edges().to_lower()
	if normalized.begins_with("[") and normalized.ends_with("]"):
		normalized = normalized.substr(1, normalized.length() - 2)
	if normalized.is_empty() or port < GameConstants.MIN_PORT or port > GameConstants.MAX_PORT:
		return ""
	return ("%s:%d" % [normalized, port]).sha256_text()


func _remembered_password_port() -> int:
	if port_field == null or not port_field.text.strip_edges().is_valid_int():
		return 0
	return int(port_field.text.strip_edges())


func _connect_online() -> void:
	var port := _validated_port(port_field)
	if port == 0:
		return
	var display_name := ServerLobby.sanitize_display_name(name_field.text)
	if display_name.is_empty():
		connection_status.text = NetworkProtocol.rejection_message(NetworkProtocol.REJECT_INVALID_NAME)
		return
	name_field.text = display_name
	var lobby_password := direct_password_field.text
	if not NetworkProtocol.is_valid_lobby_password(lobby_password):
		connection_status.text = "Enter the lobby password (1–%d printable characters)." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
		direct_password_field.grab_focus()
		return
	var address := host_field.text.strip_edges()
	client.offline_sandbox.set_sandbox_active(false)
	client.network_world.set_network_active(false)
	_pending_password_host = address
	_pending_password_port = port
	_pending_password_value = lobby_password
	_pending_remember_password = remember_password_button.button_pressed
	connection_status.text = "Authenticating with %s:%d…" % [address, port]
	var error: Error = client.bridge.start_client(address, port, display_name, GameConstants.PROTOCOL_VERSION, lobby_password)
	if error != OK:
		connection_status.text = client.bridge.last_error


func _host_online() -> void:
	var port := _validated_port(host_port_field, true)
	if port == 0:
		return
	var display_name := ServerLobby.sanitize_display_name(name_field.text)
	if display_name.is_empty():
		connection_status.text = NetworkProtocol.rejection_message(NetworkProtocol.REJECT_INVALID_NAME)
		return
	name_field.text = display_name
	var server_name := server_name_field.text.strip_edges()
	if not LanDiscoveryProtocol.is_valid_server_name(server_name):
		connection_status.text = "Server name must contain 1–%d printable characters." % LanDiscoveryProtocol.MAX_SERVER_NAME_LENGTH
		return
	var lobby_password := host_password_field.text
	if not NetworkProtocol.is_valid_lobby_password(lobby_password):
		connection_status.text = "Set a required lobby password containing 1–%d printable characters." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
		host_password_field.grab_focus()
		return
	client.bridge.stop()
	_stop_hosted_server()
	var error := _start_hosted_server({
		"port": port,
		"max_players": GameConstants.DEFAULT_MAX_PLAYERS,
		"rounds_to_win": GameConstants.DEFAULT_ROUNDS_TO_WIN,
		"server_name": server_name,
		"lobby_password": lobby_password,
		"match_preset": String(host_preset_control.get_item_metadata(host_preset_control.selected)),
	})
	if error != OK:
		connection_status.text = _hosted_server_bridge.last_error if _hosted_server_bridge != null else "Could not start the local server."
		_stop_hosted_server()
		return
	client.offline_sandbox.set_sandbox_active(false)
	client.network_world.set_network_active(false)
	connection_status.text = "Hosting %s on UDP %d and joining locally…" % [server_name, port]
	_pending_password_host = ""
	_pending_password_port = 0
	_pending_password_value = ""
	_pending_remember_password = false
	error = client.bridge.start_client("127.0.0.1", port, display_name, GameConstants.PROTOCOL_VERSION, lobby_password)
	if error != OK:
		connection_status.text = client.bridge.last_error
		_stop_hosted_server()


func _start_hosted_server(configuration: Dictionary) -> Error:
	_hosted_server_root = Node.new()
	_hosted_server_root.name = "HostedServerRuntime"
	client.add_child(_hosted_server_root)
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
	var remembered_password := _remembered_password_for_endpoint(
		String(server.get("address", "")),
		int(server.get("game_port", 0))
	)
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
	detail_label.text = "%s:%d  ·  LOCKED  ·  %d HUMAN + %d NPC / %d  ·  %s  ·  %d ms" % [
		server.get("address", ""), server.get("game_port", 0), server.get("human_count", 0),
		server.get("npc_count", 0), server.get("player_limit", 0), state_text, server.get("ping_ms", 0),
	]
	detail_label.add_theme_font_size_override("font_size", 16)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_color_override("font_color", Color("aebbd4"))
	identity.add_child(detail_label)
	var join_button := Button.new()
	join_button.text = ("JOIN" if not remembered_password.is_empty() else "JOIN LOCKED…") if compatible else "VERSION %d" % int(server.get("protocol_version", 0))
	join_button.tooltip_text = "Join using the saved password." if not remembered_password.is_empty() else "Enter this locked server's password on the next screen, then connect."
	join_button.theme_type_variation = &"PrimaryButton" if compatible else &"QuietButton"
	join_button.disabled = not compatible
	join_button.custom_minimum_size = Vector2(175.0, 46.0)
	join_button.pressed.connect(_join_lan_server.bind(String(server.get("address", "")), int(server.get("game_port", 0))))
	row.add_child(join_button)


func _join_lan_server(address: String, port: int) -> void:
	host_field.text = address
	port_field.text = str(port)
	_apply_remembered_password(address, port)
	if direct_password_field.text.is_empty():
		connection_tabs.current_tab = 1
		connection_status.text = "Enter the password for %s, then connect." % address
		direct_password_field.grab_focus()
		return
	_connect_online()


func show_connected(peer_id: int) -> void:
	_commit_pending_password_preference()
	connection_screen.visible = true
	connection_form_panel.visible = false
	lobby_panel.visible = true
	connection_status.text = "Connected as peer %d." % peer_id
	connection_status.add_theme_color_override("font_color", Color("62ff9b"))
	client.bridge.send_player_appearance(random_ship_color, preferred_ship_color, preferred_ship_pattern)
	ready_button.grab_focus()


func render_lobby(state: Dictionary) -> void:
	var npc_count := int(state.get("npc_count", 0))
	var total_count := (state.get("players", []) as Array).size()
	var match_active := bool(state.get("match_active", false))
	if match_active:
		if lobby_options_popup != null:
			_hide_lobby_options(false)
		if ship_color_popup != null:
			_hide_ship_color(false)
	if not match_active:
		connection_screen.visible = true
		connection_form_panel.visible = false
	lobby_panel.visible = not match_active
	lobby_label.text = "PLAYERS  %d / %d    ·    READY  %d / %d    ·    NPCS  %d" % [
		total_count,
		state.get("player_limit", 32),
		state.get("ready_human_count", 0),
		total_count - npc_count,
		npc_count,
	]
	var is_leader: bool = int(state.get("leader_id", 0)) == client.bridge.local_peer_id
	lobby_rules_label.text = "%s  ·  First to %d rounds  ·  %s" % [GameModeRules.mode_name(int(state.get("game_mode", 0))), int(state.get("rounds_to_win", 3)), "NPC fill enabled" if bool(state.get("npcs_enabled", false)) else "Human pilots only"]
	lobby_readiness_label.text = readiness_summary(state)
	lobby_options_button.text = "MATCH SETUP" if is_leader else "VIEW MATCH SETUP"
	lobby_options_button.tooltip_text = "Choose a solo or party preset, or configure advanced rules." if is_leader else "View current rules. Only the host may edit match setup."
	_rebuild_lobby_roster(state, is_leader)
	var local_ready := false
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == client.bridge.local_peer_id:
			local_ready = bool(player.get("ready", false))
			break
	_applying_lobby_state = true
	var selected_game_mode := clampi(int(state.get("game_mode", GameModeRules.Mode.DEATH_MATCH)), GameModeRules.Mode.DEATH_MATCH, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG)
	game_mode_control.select(selected_game_mode)
	game_mode_note.text = GameModeRules.mode_description(selected_game_mode)
	team_count_row.visible = selected_game_mode == GameModeRules.Mode.TEAM_DEATH_MATCH
	team_count_control.max_value = mini(GameModeRules.MAX_TEAM_COUNT, int(state.get("player_limit", GameConstants.DEFAULT_MAX_PLAYERS)))
	team_count_control.value = clampi(int(state.get("team_count", GameModeRules.DEFAULT_TEAM_COUNT)), GameModeRules.MIN_TEAM_COUNT, GameModeRules.MAX_TEAM_COUNT)
	rounds_control.value = int(state.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN))
	player_limit_control.max_value = int(state.get("server_capacity", GameConstants.MAX_PLAYERS))
	player_limit_control.value = int(state.get("player_limit", GameConstants.DEFAULT_MAX_PLAYERS))
	npcs_button.button_pressed = bool(state.get("npcs_enabled", false))
	npc_all_difficulty_control.select(clampi(int(state.get("default_npc_difficulty", NpcPilotController.Difficulty.NEUTRAL)), NpcPilotController.Difficulty.PASSIVE, NpcPilotController.Difficulty.INSANE))
	powerups_button.button_pressed = bool(state.get("random_spawn_powerups", false))
	powerup_interval_control.value = float(state.get("random_powerup_interval_seconds", 20.0))
	powerups_permanent_button.button_pressed = bool(state.get("random_powerups_permanent", false))
	overtime_start_control.value = float(state.get("overtime_start_seconds", GameConstants.OVERTIME_START_SECONDS))
	ready_button.button_pressed = local_ready
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == client.bridge.local_peer_id:
			preferred_ship_color = Color.from_string("#%s" % String(player.get("ship_color", "42e8ff")), preferred_ship_color)
			preferred_ship_pattern = ShipAppearanceScript.normalized_pattern(String(player.get("ship_pattern", ShipAppearanceScript.SOLID)))
			if preferred_ship_pattern.is_empty():
				preferred_ship_pattern = ShipAppearanceScript.SOLID
			if not ship_color_popup.visible:
				pending_ship_color = preferred_ship_color
				pending_ship_pattern = preferred_ship_pattern
				ship_color_picker.color = preferred_ship_color
				ship_pattern_control.select(ShipAppearanceScript.PATTERNS.find(preferred_ship_pattern))
				ship_pattern_preview.set_appearance(preferred_ship_color, preferred_ship_pattern)
			break
	_applying_lobby_state = false
	ready_button.disabled = match_active
	ready_button.text = "READY ✓" if local_ready else "READY FOR LAUNCH"
	var settings_editable: bool = is_leader and not match_active
	lobby_preset_control.disabled = not settings_editable
	game_mode_control.disabled = not settings_editable
	team_count_control.editable = settings_editable and selected_game_mode == GameModeRules.Mode.TEAM_DEATH_MATCH
	rounds_control.editable = settings_editable
	player_limit_control.editable = settings_editable
	npcs_button.disabled = not settings_editable
	npc_all_difficulty_control.disabled = not settings_editable or not bool(state.get("npcs_enabled", false))
	powerups_button.disabled = not settings_editable
	powerup_interval_control.editable = settings_editable and bool(state.get("random_spawn_powerups", false))
	powerups_permanent_button.disabled = not settings_editable or not bool(state.get("random_spawn_powerups", false))
	overtime_start_control.editable = settings_editable
	var can_supply_opponent := total_count >= GameConstants.MIN_PLAYERS or bool(state.get("npcs_enabled", false))
	var team_setup_valid := bool(state.get("team_setup_valid", true))
	var team_setup_error := String(state.get("team_setup_error", ""))
	start_button.disabled = not settings_editable or not can_supply_opponent or not bool(state.get("all_humans_ready", false)) or not team_setup_valid
	var human_count := total_count - npc_count
	if not is_leader:
		start_button.text = "Waiting for Lobby Leader"
	elif not team_setup_valid:
		start_button.text = "Configure All Teams"
	elif not bool(state.get("all_humans_ready", false)):
		start_button.text = "Waiting for Players to Ready"
	elif human_count == 1 and not bool(state.get("npcs_enabled", false)):
		start_button.text = "Enable NPCs to Start Solo"
	elif human_count == 1:
		start_button.text = "Start Match with NPCs"
	else:
		start_button.text = "Start Match"
	start_button.tooltip_text = team_setup_error if not team_setup_valid else "Every connected human must ready up first." if not bool(state.get("all_humans_ready", false)) else "NPCs fill open seats before launch." if bool(state.get("npcs_enabled", false)) else "Launch the configured match."
	if get_viewport().gui_get_focus_owner() == null:
		ready_button.grab_focus()


func _rebuild_lobby_roster(state: Dictionary, is_leader: bool) -> void:
	for child in lobby_roster.get_children():
		lobby_roster.remove_child(child)
		child.queue_free()
	var game_mode := int(state.get("game_mode", GameModeRules.Mode.DEATH_MATCH))
	var team_mode := GameModeRules.is_team_mode(game_mode)
	var team_count := GameModeRules.team_count_for_mode(game_mode, int(state.get("team_count", GameModeRules.DEFAULT_TEAM_COUNT)))
	var match_active := bool(state.get("match_active", false))
	for player_value in ordered_roster(state):
		var player := player_value as Dictionary
		var peer_id := int(player.get("peer_id", 0))
		var is_npc := bool(player.get("is_npc", false))
		var is_ready := bool(player.get("ready", false))
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 42.0
		row.add_theme_constant_override("separation", 10)
		lobby_roster.add_child(row)
		var color_swatch := Button.new()
		color_swatch.name = "ShipColor"
		var swatch_color := Color.from_string("#%s" % String(player.get("ship_color", "42e8ff")), Color("42e8ff"))
		var swatch_pattern := ShipAppearanceScript.normalized_pattern(String(player.get("ship_pattern", ShipAppearanceScript.SOLID)))
		if swatch_pattern.is_empty():
			swatch_pattern = ShipAppearanceScript.SOLID
		color_swatch.text = ShipAppearanceScript.swatch_symbol(swatch_pattern)
		color_swatch.add_theme_color_override("font_color", Color.WHITE)
		color_swatch.add_theme_font_size_override("font_size", 16)
		color_swatch.custom_minimum_size = Vector2(34.0, 34.0)
		color_swatch.add_theme_stylebox_override("normal", _ship_color_swatch_style(swatch_color, false))
		color_swatch.add_theme_stylebox_override("hover", _ship_color_swatch_style(swatch_color, true))
		color_swatch.add_theme_stylebox_override("pressed", _ship_color_swatch_style(swatch_color.lightened(0.12), true))
		color_swatch.add_theme_stylebox_override("focus", _ship_color_swatch_style(swatch_color, true))
		color_swatch.add_theme_stylebox_override("disabled", _ship_color_swatch_style(swatch_color, false))
		var can_choose_color: bool = peer_id == client.bridge.local_peer_id and not is_npc and not bool(state.get("match_active", false))
		color_swatch.disabled = not can_choose_color
		color_swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_choose_color else Control.CURSOR_ARROW
		color_swatch.tooltip_text = "Click to customize your ship" if can_choose_color else "%s hull pattern" % ShipAppearanceScript.display_name(swatch_pattern)
		if can_choose_color:
			color_swatch.pressed.connect(_show_ship_color_popup)
		row.add_child(color_swatch)
		var name_label := Label.new()
		name_label.text = String(player.get("display_name", "Pilot"))
		name_label.custom_minimum_size.x = 180.0 if team_mode else 280.0
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Color("fff36a") if peer_id == int(state.get("leader_id", 0)) else Color("e8f5ff"))
		row.add_child(name_label)
		var role_label := Label.new()
		var team_id := int(player.get("team_id", 0))
		var role_name := "HOST" if peer_id == int(state.get("leader_id", 0)) else "NPC" if is_npc else "PILOT"
		role_label.text = role_name if team_mode else "%s · %s" % [role_name, GameModeRules.team_name(team_id)] if team_id > 0 else role_name
		role_label.custom_minimum_size.x = 80.0 if team_mode else 170.0 if team_id > 0 else 90.0
		role_label.add_theme_color_override("font_color", GameModeRules.team_color(team_id) if team_id > 0 else Color("d39cff"))
		row.add_child(role_label)
		if team_mode:
			var team_control := OptionButton.new()
			team_control.name = "TeamAssignment"
			team_control.custom_minimum_size = Vector2(160.0, 38.0)
			var team_selection := clampi(int(player.get("team_selection", 0)), 0, team_count)
			team_control.add_item("AUTO · %s" % GameModeRules.team_name(team_id).trim_suffix(" TEAM"), 0)
			for selectable_team_id in range(1, team_count + 1):
				team_control.add_item(GameModeRules.team_name(selectable_team_id), selectable_team_id)
			team_control.select(team_selection)
			team_control.add_theme_color_override("font_color", GameModeRules.team_color(team_id))
			var can_assign_team: bool = not match_active and (is_leader or peer_id == client.bridge.local_peer_id or is_npc)
			team_control.disabled = not can_assign_team
			team_control.tooltip_text = "Choose a specific team or keep automatic balancing." if can_assign_team else "Only the host or this player may change this team."
			team_control.item_selected.connect(_on_team_assignment_selected.bind(peer_id))
			row.add_child(team_control)
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
		if is_leader and peer_id != client.bridge.local_peer_id and not is_npc and not bool(state.get("match_active", false)):
			var eject_button := Button.new()
			eject_button.text = "EJECT"
			eject_button.custom_minimum_size = Vector2(100.0, 38.0)
			eject_button.tooltip_text = "Remove this player from the lobby."
			eject_button.pressed.connect(_on_eject_pressed.bind(peer_id))
			row.add_child(eject_button)


func _on_rounds_changed(value: float) -> void:
	if not _applying_lobby_state:
		client.bridge.send_lobby_config(roundi(value))


func _on_player_limit_changed(value: float) -> void:
	if not _applying_lobby_state:
		client.bridge.send_player_limit(roundi(value))


func _on_npcs_toggled(enabled: bool) -> void:
	if not _applying_lobby_state:
		client.bridge.send_npcs_enabled(enabled)


func _on_game_mode_selected(index: int) -> void:
	var mode := game_mode_control.get_item_id(index)
	game_mode_note.text = GameModeRules.mode_description(mode)
	team_count_row.visible = mode == GameModeRules.Mode.TEAM_DEATH_MATCH
	if not _applying_lobby_state:
		client.bridge.send_game_mode(mode)


func _on_team_count_changed(value: float) -> void:
	if not _applying_lobby_state:
		client.bridge.send_team_count(roundi(value))


func _on_team_assignment_selected(index: int, peer_id: int) -> void:
	client.bridge.send_team_assignment(peer_id, index)


func _show_lobby_options() -> void:
	if lobby_options_popup != null and lobby_panel.visible:
		lobby_options_focus_return = get_viewport().gui_get_focus_owner()
		if ship_color_popup != null:
			_hide_ship_color(false)
		lobby_options_blocker.show()
		lobby_panel.hide()
		lobby_options_popup.show()
		game_mode_control.grab_focus()


func _hide_lobby_options(restore_focus: bool = true) -> void:
	if lobby_options_popup != null:
		lobby_options_popup.hide()
	if lobby_options_blocker != null:
		lobby_options_blocker.hide()
	_restore_lobby_after_modal()
	if restore_focus:
		_restore_modal_focus(lobby_options_focus_return, lobby_options_button)
	lobby_options_focus_return = null


func _on_powerups_toggled(enabled: bool) -> void:
	if not _applying_lobby_state:
		client.bridge.send_random_spawn_powerups(enabled)


func _show_ship_color_popup() -> void:
	if ship_color_popup == null or not lobby_panel.visible or bool(client.bridge.latest_lobby_state.get("match_active", false)):
		return
	ship_color_focus_return = get_viewport().gui_get_focus_owner()
	if lobby_options_popup != null:
		_hide_lobby_options(false)
	pending_ship_color = preferred_ship_color
	pending_ship_pattern = preferred_ship_pattern
	ship_color_picker.color = pending_ship_color
	ship_pattern_control.select(ShipAppearanceScript.PATTERNS.find(pending_ship_pattern))
	ship_pattern_preview.set_appearance(pending_ship_color, pending_ship_pattern)
	ship_color_blocker.show()
	lobby_panel.hide()
	ship_color_popup.show()
	apply_ship_color_button.grab_focus()


func _hide_ship_color(restore_focus: bool = true) -> void:
	if ship_color_popup != null:
		ship_color_popup.hide()
	if ship_color_blocker != null:
		ship_color_blocker.hide()
	_restore_lobby_after_modal()
	if restore_focus:
		_restore_modal_focus(ship_color_focus_return, ready_button)
	ship_color_focus_return = null


func _restore_modal_focus(preferred: Control, fallback: Control) -> void:
	var target := preferred if is_instance_valid(preferred) and preferred.is_visible_in_tree() else fallback
	if is_instance_valid(target) and target.is_visible_in_tree() and target.focus_mode != Control.FOCUS_NONE:
		target.call_deferred("grab_focus")


func _restore_lobby_after_modal() -> void:
	if (
		lobby_panel != null
		and (client.bridge.role == NetworkBridge.Role.CLIENT or client.bridge.local_peer_id != 0)
		and connection_screen.visible
		and not bool(client.bridge.latest_lobby_state.get("match_active", false))
	):
		lobby_panel.show()


func _on_ship_color_changed(color: Color) -> void:
	if _applying_lobby_state:
		return
	pending_ship_color = Color(color.r, color.g, color.b, 1.0)
	ship_pattern_preview.set_appearance(pending_ship_color, pending_ship_pattern)


func _on_ship_pattern_selected(index: int) -> void:
	if _applying_lobby_state or index < 0 or index >= ShipAppearanceScript.PATTERNS.size():
		return
	pending_ship_pattern = ShipAppearanceScript.PATTERNS[index]
	ship_pattern_preview.set_appearance(pending_ship_color, pending_ship_pattern)


func _apply_ship_color() -> void:
	preferred_ship_color = pending_ship_color
	preferred_ship_pattern = pending_ship_pattern
	random_ship_color = false
	_save_appearance_settings()
	client.bridge.send_player_appearance(false, preferred_ship_color, preferred_ship_pattern)
	_hide_ship_color()


func _on_random_color_pressed() -> void:
	preferred_ship_pattern = pending_ship_pattern
	random_ship_color = true
	_save_appearance_settings()
	client.bridge.send_player_appearance(true, preferred_ship_color, preferred_ship_pattern)
	_hide_ship_color()


func _cancel_ship_color() -> void:
	pending_ship_color = preferred_ship_color
	pending_ship_pattern = preferred_ship_pattern
	ship_color_picker.color = preferred_ship_color
	ship_pattern_control.select(ShipAppearanceScript.PATTERNS.find(preferred_ship_pattern))
	ship_pattern_preview.set_appearance(preferred_ship_color, preferred_ship_pattern)
	_hide_ship_color()


func _on_npc_difficulty_selected(index: int, npc_peer_id: int) -> void:
	client.bridge.send_npc_difficulty(npc_peer_id, index)


func _on_all_npc_difficulty_selected(index: int) -> void:
	if not _applying_lobby_state:
		client.bridge.send_all_npc_difficulty(index)


func _on_powerup_interval_changed(value: float) -> void:
	if not _applying_lobby_state:
		client.bridge.send_random_powerup_interval(value)


func _on_powerups_permanent_toggled(permanent: bool) -> void:
	if not _applying_lobby_state:
		client.bridge.send_random_powerups_permanent(permanent)


func _on_overtime_start_changed(value: float) -> void:
	if not _applying_lobby_state:
		client.bridge.send_overtime_start(value)


func _on_ready_toggled(ready: bool) -> void:
	if not _applying_lobby_state:
		client.bridge.send_ready_state(ready)


func _on_eject_pressed(peer_id: int) -> void:
	client.bridge.send_eject_player(peer_id)


func _ship_color_swatch_style(ship_color: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ship_color, 1.0)
	style.border_color = Color.WHITE if hovered else Color(ship_color.lightened(0.38), 0.95)
	style.set_border_width_all(3 if hovered else 2)
	style.set_corner_radius_all(9)
	style.shadow_color = Color(ship_color, 0.58 if hovered else 0.28)
	style.shadow_size = 8 if hovered else 4
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _lan_server_row_style(compatible: bool) -> StyleBoxFlat:
	var accent := DesignTokensScript.INTERACTIVE if compatible else DesignTokensScript.DANGER
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



func start_discovery() -> void:
	lan_browser = LanDiscoveryService.new()
	lan_browser.name = "LanServerBrowser"
	client.add_child(lan_browser)
	lan_browser.servers_updated.connect(_on_lan_servers_updated)
	var discovery_error := lan_browser.start_browser()
	if discovery_error != OK:
		connection_status.text = lan_browser.last_error


func shutdown() -> void:
	if is_instance_valid(lan_browser):
		lan_browser.stop()
	_stop_hosted_server()


func _create_preset_picker(parent: VBoxContainer) -> OptionButton:
	var label := Label.new()
	label.text = "SOLO OR PARTY PRESET"
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)
	var picker := OptionButton.new()
	picker.name = "MatchPreset"
	picker.custom_minimum_size.y = 42.0
	picker.add_item("Custom · configure in the lobby")
	picker.set_item_metadata(0, "")
	for preset in MatchPresetsScript.PRESETS:
		picker.add_item(String(preset.name))
		picker.set_item_metadata(picker.item_count - 1, String(preset.id))
	parent.add_child(picker)
	return picker


func _create_preset_note(parent: VBoxContainer) -> Label:
	var note := Label.new()
	note.text = _preset_description(0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	parent.add_child(note)
	return note


func _preset_description(index: int) -> String:
	return "Choose a quick setup or adjust every rule in Advanced settings. All presets can be edited before launch." if index == 0 else String(MatchPresetsScript.PRESETS[index - 1].description)


func _on_lobby_preset_selected(index: int) -> void:
	lobby_preset_note.text = _preset_description(index)
	lobby_preset_note.remove_theme_color_override("font_color")
	if index > 0 and not _applying_lobby_state:
		client.bridge.send_match_preset(String(lobby_preset_control.get_item_metadata(index)))


func show_request_rejection(message: String) -> void:
	if lobby_options_popup.visible:
		lobby_preset_note.text = "Could not apply: %s" % message
		lobby_preset_note.add_theme_color_override("font_color", Color("ffadb9"))


static func ordered_roster(state: Dictionary) -> Array:
	var roster: Array = state.get("players", []).duplicate(true)
	# Unready humans first so blockers are visible even in a full 32-pilot lobby.
	roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_group := 2 if bool(a.get("is_npc", false)) else 1 if bool(a.get("ready", false)) else 0
		var b_group := 2 if bool(b.get("is_npc", false)) else 1 if bool(b.get("ready", false)) else 0
		return a_group < b_group if a_group != b_group else int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
	)
	return roster


static func readiness_summary(state: Dictionary) -> String:
	var missing := PackedStringArray()
	var missing_count := 0
	for player in state.get("players", []):
		if not bool(player.get("is_npc", false)) and not bool(player.get("ready", false)):
			missing_count += 1
			if missing.size() < 3:
				missing.append(String(player.get("display_name", "Pilot")))
	var status := "All human pilots ready." if missing_count == 0 else "Waiting for: %s%s." % [", ".join(missing), " +%d more" % (missing_count - missing.size()) if missing_count > missing.size() else ""]
	return "%s  Unready pilots appear first · scroll roster for all %d pilots." % [status, (state.get("players", []) as Array).size()]
