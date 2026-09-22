extends Node

## Owns lobby controls and modals. Receives state observations and a bridge;
## navigation is published as intent, with no client-root dependency.
const PreferencesScript = preload("res://src/client/ui/connection_preferences.gd")
const PresetControls = preload("res://src/client/ui/match_preset_controls.gd")
const NavigationScript = preload("res://src/client/ui/screen_navigation.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const ShipPatternPreviewScript = preload("res://src/client/ui/ship_pattern_preview.gd")

signal settings_requested
signal disconnect_requested
var bridge: NetworkBridge
var interface_theme: Theme
var connection_canvas: CanvasLayer
var preferences: PreferencesScript
var _presented: bool = false
var _lobby_state: Dictionary = {}
var lobby_panel: PanelContainer
var lobby_preset_control: OptionButton
var lobby_preset_note: Label
var lobby_readiness_label: Label
var lobby_rules_label: Label
var lobby_roster_scroll: ScrollContainer
var lobby_host_controls: VBoxContainer
var lobby_label: Label
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
var lobby_options_tabs: TabContainer
var lobby_options_status: Label
var lobby_options_close: Button
var arena_effect_controls: ArenaEffectControls
var powerups_button: CheckButton
var powerup_interval_control: SpinBox
var powerups_permanent_button: CheckButton
var competitive_view_control: CheckButton
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
var lobby_settings_button: Button
var lobby_disconnect_button: Button
var _applying_lobby_state: bool = false


func configure(network: NetworkBridge, theme: Theme, canvas: CanvasLayer, saved_preferences: PreferencesScript) -> void:
	bridge = network
	interface_theme = theme
	connection_canvas = canvas
	preferences = saved_preferences
	_load_appearance_settings()


func create_ui() -> void:
	if lobby_panel == null:
		_create_lobby_panel()


func set_presented(presented: bool) -> void:
	_presented = presented
	if not presented:
		_hide_lobby_options(false)
		_hide_ship_color(false)
	lobby_panel.visible = presented and not lobby_options_popup.visible and not ship_color_popup.visible


func is_presented() -> bool:
	return _presented


func reset_session() -> void:
	set_presented(false)
	_lobby_state.clear()


func submit_appearance() -> void:
	bridge.send_player_appearance(random_ship_color, preferred_ship_color, preferred_ship_pattern)


func focus_ready() -> void:
	ready_button.grab_focus()


func focus_settings() -> void:
	lobby_settings_button.grab_focus()


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
	lobby_panel.theme = interface_theme
	lobby_panel.add_theme_stylebox_override("panel", DesignTokensScript.panel_style(DesignTokensScript.INTERACTIVE, 0.96))
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
	start_button.pressed.connect(bridge.send_start_match)
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
	lobby_settings_button.pressed.connect(settings_requested.emit)
	lobby_actions.add_child(lobby_settings_button)
	lobby_disconnect_button = Button.new()
	lobby_disconnect_button.name = "LobbyDisconnectButton"
	lobby_disconnect_button.text = "Disconnect"
	lobby_disconnect_button.theme_type_variation = &"DangerButton"
	lobby_disconnect_button.custom_minimum_size.y = 54.0
	lobby_disconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_disconnect_button.pressed.connect(disconnect_requested.emit)
	lobby_actions.add_child(lobby_disconnect_button)


func _create_lobby_options_popup() -> void:
	lobby_options_blocker = _create_modal_blocker("LobbyOptionsBlocker")
	connection_canvas.add_child(lobby_options_blocker)
	lobby_options_popup = PanelContainer.new()
	lobby_options_popup.name = "LobbyOptions"
	lobby_options_popup.set_anchors_preset(Control.PRESET_CENTER)
	lobby_options_popup.position = Vector2(-460.0, -430.0)
	lobby_options_popup.custom_minimum_size = Vector2(920.0, 860.0)
	lobby_options_popup.theme = interface_theme
	lobby_options_popup.add_theme_stylebox_override("panel", DesignTokensScript.panel_style(DesignTokensScript.BRAND_MAGENTA, 0.98))
	lobby_options_popup.visible = false
	connection_canvas.add_child(lobby_options_popup)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	lobby_options_popup.add_child(outer)
	var title := Label.new()
	title.text = "MATCH SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_TITLE_SIZE)
	title.add_theme_color_override("font_color", DesignTokensScript.BRAND_MAGENTA)
	outer.add_child(title)
	lobby_options_status = _setup_note(outer, "Changes apply immediately. Pilots must ready up again after rule changes.")
	lobby_options_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_options_tabs = TabContainer.new()
	lobby_options_tabs.name = "MatchSetupTabs"
	lobby_options_tabs.custom_minimum_size = Vector2(860.0, 630.0)
	lobby_options_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_options_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	lobby_options_tabs.get_tab_bar().gui_input.connect(NavigationScript.handle_tab_bar_input.bind(lobby_options_tabs))
	outer.add_child(lobby_options_tabs)
	var match_content := _setup_tab("MATCH")
	lobby_preset_control = PresetControls.create_picker(match_content)
	lobby_preset_control.set_item_text(0, "Custom · choose your own rules")
	lobby_preset_note = PresetControls.create_note(match_content)
	lobby_preset_note.text = "Start with a preset, then adjust Match, Pilots, and Arena Rules."
	lobby_preset_note.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
	lobby_preset_control.item_selected.connect(_on_lobby_preset_selected)
	_setup_heading(match_content, "Mode & victory")
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 14)
	match_content.add_child(mode_row)
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
	game_mode_note.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
	match_content.add_child(game_mode_note)
	team_count_row = HBoxContainer.new()
	team_count_row.name = "TeamCountRow"
	team_count_row.add_theme_constant_override("separation", 14)
	team_count_row.visible = false
	match_content.add_child(team_count_row)
	var team_count_label := Label.new()
	team_count_label.text = "Number of teams"
	team_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_count_row.add_child(team_count_label)
	team_count_control = SpinBox.new()
	team_count_control.min_value = GameModeRules.MIN_TEAM_COUNT
	team_count_control.max_value = GameModeRules.MAX_TEAM_COUNT
	team_count_control.value = GameModeRules.DEFAULT_TEAM_COUNT
	team_count_control.step = 1.0
	team_count_control.custom_minimum_size = Vector2(190.0, 48.0)
	team_count_control.tooltip_text = "Team Death Match supports two through eight teams. Every configured team needs at least one participant."
	team_count_control.value_changed.connect(_on_team_count_changed)
	team_count_row.add_child(team_count_control)
	var rounds_row := HBoxContainer.new()
	match_content.add_child(rounds_row)
	var rounds_label := Label.new()
	rounds_label.text = "Rounds to win"
	rounds_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rounds_row.add_child(rounds_label)
	rounds_control = SpinBox.new()
	rounds_control.min_value = GameConstants.MIN_ROUNDS_TO_WIN
	rounds_control.max_value = GameConstants.MAX_ROUNDS_TO_WIN
	rounds_control.value = GameConstants.DEFAULT_ROUNDS_TO_WIN
	rounds_control.custom_minimum_size = Vector2(190.0, 48.0)
	rounds_control.value_changed.connect(_on_rounds_changed)
	rounds_row.add_child(rounds_control)
	lobby_host_controls = _setup_tab("PILOTS")
	_setup_heading(lobby_host_controls, "Lobby size")
	_setup_note(lobby_host_controls, "The player limit includes human pilots and NPCs.")
	var limit_row := HBoxContainer.new()
	lobby_host_controls.add_child(limit_row)
	var limit_label := Label.new()
	limit_label.text = "Player limit"
	limit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	limit_row.add_child(limit_label)
	player_limit_control = SpinBox.new()
	player_limit_control.min_value = GameConstants.MIN_PLAYERS
	player_limit_control.max_value = GameConstants.MAX_PLAYERS
	player_limit_control.value = GameConstants.DEFAULT_MAX_PLAYERS
	player_limit_control.custom_minimum_size = Vector2(190.0, 48.0)
	player_limit_control.value_changed.connect(_on_player_limit_changed)
	limit_row.add_child(player_limit_control)
	npcs_button = CheckButton.new()
	npcs_button.text = "Fill empty seats with NPCs"
	npcs_button.theme_type_variation = &"SettingToggle"
	npcs_button.custom_minimum_size.y = 48.0
	npcs_button.toggled.connect(_on_npcs_toggled)
	lobby_host_controls.add_child(npcs_button)
	var npc_difficulty_row := HBoxContainer.new()
	npc_difficulty_row.add_theme_constant_override("separation", 14)
	lobby_host_controls.add_child(npc_difficulty_row)
	var npc_difficulty_label := Label.new()
	npc_difficulty_label.text = "Difficulty for all NPCs"
	npc_difficulty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_difficulty_row.add_child(npc_difficulty_label)
	npc_all_difficulty_control = OptionButton.new()
	npc_all_difficulty_control.custom_minimum_size = Vector2(190.0, 42.0)
	for difficulty in NpcPilotController.DIFFICULTY_NAMES.size():
		npc_all_difficulty_control.add_item(NpcPilotController.difficulty_name(difficulty), difficulty)
	npc_all_difficulty_control.select(NpcPilotController.Difficulty.NEUTRAL)
	npc_all_difficulty_control.item_selected.connect(_on_all_npc_difficulty_selected)
	npc_difficulty_row.add_child(npc_all_difficulty_control)
	_setup_note(lobby_host_controls, "You can adjust individual NPC difficulties and team assignments in the lobby roster.")
	var rules_content := _setup_tab("ARENA RULES")
	_setup_heading(rules_content, "Round pacing")
	var overtime_row := HBoxContainer.new()
	overtime_row.add_theme_constant_override("separation", 14)
	rules_content.add_child(overtime_row)
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
	overtime_start_control.custom_minimum_size = Vector2(190.0, 48.0)
	overtime_start_control.value_changed.connect(_on_overtime_start_changed)
	overtime_row.add_child(overtime_start_control)
	_setup_heading(rules_content, "Arena effects")
	arena_effect_controls = ArenaEffectControls.new()
	rules_content.add_child(arena_effect_controls)
	arena_effect_controls.settings_changed.connect(bridge.send_arena_effects)
	_setup_heading(rules_content, "Powerups")
	powerups_button = CheckButton.new()
	powerups_button.text = "Enable powerup drops"
	powerups_button.theme_type_variation = &"SettingToggle"
	powerups_button.tooltip_text = "King of the Hill enables temporary drops by default. When enabled, a server-owned Rare-or-better card appears during active combat at the configured interval."
	powerups_button.custom_minimum_size.y = 48.0
	powerups_button.toggled.connect(_on_powerups_toggled)
	rules_content.add_child(powerups_button)
	var powerup_row := HBoxContainer.new()
	powerup_row.add_theme_constant_override("separation", 14)
	var interval_label := Label.new()
	interval_label.text = "Time between drops"
	interval_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	powerup_row.add_child(interval_label)
	powerup_interval_control = SpinBox.new()
	powerup_interval_control.min_value = 5.0
	powerup_interval_control.max_value = 90.0
	powerup_interval_control.step = 1.0
	powerup_interval_control.value = 20.0
	powerup_interval_control.suffix = " sec"
	powerup_interval_control.custom_minimum_size = Vector2(190.0, 48.0)
	powerup_interval_control.value_changed.connect(_on_powerup_interval_changed)
	powerup_row.add_child(powerup_interval_control)
	rules_content.add_child(powerup_row)
	powerups_permanent_button = CheckButton.new()
	powerups_permanent_button.text = "Keep collected powerups for the full match"
	powerups_permanent_button.theme_type_variation = &"SettingToggle"
	powerups_permanent_button.tooltip_text = "Off by default. When off, arena-drop cards are removed after the heat."
	powerups_permanent_button.toggled.connect(_on_powerups_permanent_toggled)
	rules_content.add_child(powerups_permanent_button)
	_setup_note(rules_content, "Drops grant Rare-or-better cards. By default, collected cards last until the heat ends.")
	_setup_heading(rules_content, "Competitive view")
	competitive_view_control = CheckButton.new()
	competitive_view_control.name = "CompetitiveView"
	competitive_view_control.theme_type_variation = &"SettingToggle"
	competitive_view_control.custom_minimum_size.y = 48.0
	competitive_view_control.text = "Use equal 16:9 combat space"
	competitive_view_control.tooltip_text = "Equal 16:9 combat space for everyone. Eliminated team players can follow visible teammates only; no teammate means a waiting screen. Neutral spectators remain unrestricted."
	competitive_view_control.toggled.connect(_on_competitive_view_changed)
	rules_content.add_child(competitive_view_control)
	_setup_note(rules_content, "Applies to all pilots and spectators. Wider or taller screens show bars during combat.")
	lobby_options_tabs.tab_changed.connect(_on_setup_tab_changed)
	lobby_options_close = Button.new()
	lobby_options_close.text = "BACK TO LOBBY"
	lobby_options_close.theme_type_variation = &"PrimaryButton"
	lobby_options_close.custom_minimum_size.y = 48.0
	lobby_options_close.pressed.connect(_hide_lobby_options)
	outer.add_child(lobby_options_close)
	_on_setup_tab_changed(0)


func _setup_tab(tab_title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	lobby_options_tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	return content


func _setup_heading(parent: VBoxContainer, heading: String) -> void:
	parent.add_child(HSeparator.new())
	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_SECTION_SIZE)
	label.add_theme_color_override("font_color", DesignTokensScript.BRAND_MAGENTA)
	parent.add_child(label)


func _setup_note(parent: VBoxContainer, message: String) -> Label:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
	parent.add_child(label)
	return label


func _on_setup_tab_changed(index: int) -> void:
	var first_control: Control = [lobby_preset_control, player_limit_control.get_line_edit(), overtime_start_control.get_line_edit()][index]
	var tab_bar := lobby_options_tabs.get_tab_bar()
	tab_bar.focus_next = tab_bar.get_path_to(first_control)
	tab_bar.focus_neighbor_bottom = tab_bar.focus_next
	first_control.focus_previous = first_control.get_path_to(tab_bar)
	if lobby_options_popup.visible and get_viewport().gui_get_focus_owner() != tab_bar:
		if lobby_preset_control.disabled:
			tab_bar.grab_focus()
		else:
			first_control.grab_focus()


func _create_ship_color_popup() -> void:
	ship_color_blocker = _create_modal_blocker("ShipColorBlocker")
	connection_canvas.add_child(ship_color_blocker)
	ship_color_popup = PanelContainer.new()
	ship_color_popup.name = "ShipColorPicker"
	ship_color_popup.set_anchors_preset(Control.PRESET_CENTER)
	ship_color_popup.position = Vector2(-350.0, -330.0)
	ship_color_popup.custom_minimum_size = Vector2(700.0, 660.0)
	ship_color_popup.theme = interface_theme
	ship_color_popup.add_theme_stylebox_override("panel", DesignTokensScript.panel_style(DesignTokensScript.INTERACTIVE, 0.99))
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


func _load_appearance_settings() -> void:
	preferences.load_appearance()
	random_ship_color = preferences.random_color
	preferred_ship_color = preferences.ship_color
	preferred_ship_pattern = preferences.ship_pattern


func _save_appearance_settings() -> void:
	preferences.save_appearance(random_ship_color, preferred_ship_color, preferred_ship_pattern)


func render_lobby(state: Dictionary) -> void:
	_lobby_state = state.duplicate(true)
	var npc_count := int(state.get("npc_count", 0))
	var total_count := (state.get("players", []) as Array).size()
	var match_active := bool(state.get("match_active", false))
	if match_active:
		if lobby_options_popup != null:
			_hide_lobby_options(false)
		if ship_color_popup != null:
			_hide_ship_color(false)
	set_presented(not match_active)
	lobby_label.text = "PLAYERS  %d / %d    ·    READY  %d / %d    ·    NPCS  %d" % [
		total_count,
		state.get("player_limit", 32),
		state.get("ready_human_count", 0),
		total_count - npc_count,
		npc_count,
	]
	var is_leader: bool = int(state.get("leader_id", 0)) == bridge.local_peer_id
	lobby_rules_label.text = "%s  ·  First to %d rounds  ·  %s" % [GameModeRules.mode_name(int(state.get("game_mode", 0))), int(state.get("rounds_to_win", 3)), "NPC fill enabled" if bool(state.get("npcs_enabled", false)) else "Human pilots only"]
	lobby_rules_label.text += "  ·  Competitive 16:9" if bool(state.get("competitive_view", false)) else "  ·  Expanded view"
	lobby_readiness_label.text = readiness_summary(state)
	lobby_options_button.text = "MATCH SETUP" if is_leader else "VIEW MATCH SETUP"
	lobby_options_button.tooltip_text = "Choose a preset, configure pilots, and adjust arena rules." if is_leader else "View current rules. Only the host may edit match setup."
	_rebuild_lobby_roster(state, is_leader)
	var local_ready := false
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == bridge.local_peer_id:
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
	competitive_view_control.set_pressed_no_signal(bool(state.get("competitive_view", false)))
	overtime_start_control.value = float(state.get("overtime_start_seconds", GameConstants.OVERTIME_START_SECONDS))
	ready_button.button_pressed = local_ready
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == bridge.local_peer_id:
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
	lobby_options_status.text = "Changes apply immediately. Pilots must ready up again after rule changes." if is_leader else "Only the host can change these rules. You can browse all three tabs."
	lobby_options_status.remove_theme_color_override("font_color")
	var settings_editable: bool = is_leader and not match_active
	lobby_preset_control.disabled = not settings_editable
	game_mode_control.disabled = not settings_editable
	team_count_control.editable = settings_editable and selected_game_mode == GameModeRules.Mode.TEAM_DEATH_MATCH
	rounds_control.editable = settings_editable
	player_limit_control.editable = settings_editable
	npcs_button.disabled = not settings_editable
	npc_all_difficulty_control.disabled = not settings_editable or not bool(state.get("npcs_enabled", false))
	powerups_button.disabled = not settings_editable
	arena_effect_controls.refresh(state.get("arena_effects", ArenaEffectRules.DEFAULT) as Dictionary, settings_editable)
	powerup_interval_control.editable = settings_editable and bool(state.get("random_spawn_powerups", false))
	powerups_permanent_button.disabled = not settings_editable or not bool(state.get("random_spawn_powerups", false))
	overtime_start_control.editable = settings_editable
	competitive_view_control.disabled = not settings_editable
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
		var can_choose_color: bool = peer_id == bridge.local_peer_id and not is_npc and not bool(state.get("match_active", false))
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
			var can_assign_team: bool = not match_active and (is_leader or peer_id == bridge.local_peer_id or is_npc)
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
		if is_leader and peer_id != bridge.local_peer_id and not is_npc and not bool(state.get("match_active", false)):
			var eject_button := Button.new()
			eject_button.text = "EJECT"
			eject_button.theme_type_variation = &"DangerButton"
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


func _on_game_mode_selected(index: int) -> void:
	var mode := game_mode_control.get_item_id(index)
	game_mode_note.text = GameModeRules.mode_description(mode)
	team_count_row.visible = mode == GameModeRules.Mode.TEAM_DEATH_MATCH
	if not _applying_lobby_state:
		bridge.send_game_mode(mode)


func _on_team_count_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_team_count(roundi(value))


func _on_team_assignment_selected(index: int, peer_id: int) -> void:
	bridge.send_team_assignment(peer_id, index)


func _show_lobby_options() -> void:
	if lobby_options_popup != null and lobby_panel.visible:
		lobby_options_focus_return = get_viewport().gui_get_focus_owner()
		if ship_color_popup != null:
			_hide_ship_color(false)
		lobby_options_blocker.show()
		lobby_panel.hide()
		lobby_options_tabs.current_tab = 0
		for tab in lobby_options_tabs.get_children():
			(tab as ScrollContainer).scroll_vertical = 0
		lobby_options_popup.show()
		_on_setup_tab_changed(0)
		if lobby_preset_control.disabled:
			lobby_options_tabs.get_tab_bar().grab_focus()
		else:
			lobby_preset_control.grab_focus()


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
		bridge.send_random_spawn_powerups(enabled)


func _show_ship_color_popup() -> void:
	if ship_color_popup == null or not lobby_panel.visible or bool(_lobby_state.get("match_active", false)):
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
		and _presented
		and not bool(_lobby_state.get("match_active", false))
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
	bridge.send_player_appearance(false, preferred_ship_color, preferred_ship_pattern)
	_hide_ship_color()


func _on_random_color_pressed() -> void:
	preferred_ship_pattern = pending_ship_pattern
	random_ship_color = true
	_save_appearance_settings()
	bridge.send_player_appearance(true, preferred_ship_color, preferred_ship_pattern)
	_hide_ship_color()


func _cancel_ship_color() -> void:
	pending_ship_color = preferred_ship_color
	pending_ship_pattern = preferred_ship_pattern
	ship_color_picker.color = preferred_ship_color
	ship_pattern_control.select(ShipAppearanceScript.PATTERNS.find(preferred_ship_pattern))
	ship_pattern_preview.set_appearance(preferred_ship_color, preferred_ship_pattern)
	_hide_ship_color()


func _on_npc_difficulty_selected(index: int, npc_peer_id: int) -> void:
	bridge.send_npc_difficulty(npc_peer_id, index)


func _on_all_npc_difficulty_selected(index: int) -> void:
	if not _applying_lobby_state:
		bridge.send_all_npc_difficulty(index)


func _on_powerup_interval_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_random_powerup_interval(value)


func _on_powerups_permanent_toggled(permanent: bool) -> void:
	if not _applying_lobby_state:
		bridge.send_random_powerups_permanent(permanent)


func _on_competitive_view_changed(enabled: bool) -> void:
	if not _applying_lobby_state:
		bridge.send_competitive_view(enabled)


func _on_overtime_start_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_overtime_start(value)


func _on_ready_toggled(ready: bool) -> void:
	if not _applying_lobby_state:
		bridge.send_ready_state(ready)


func _on_eject_pressed(peer_id: int) -> void:
	bridge.send_eject_player(peer_id)


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


func _on_lobby_preset_selected(index: int) -> void:
	lobby_preset_note.text = "Start with a preset, then adjust Match, Pilots, and Arena Rules." if index == 0 else PresetControls.description(index)
	lobby_preset_note.remove_theme_color_override("font_color")
	if index > 0 and not _applying_lobby_state:
		bridge.send_match_preset(String(lobby_preset_control.get_item_metadata(index)))


func show_request_rejection(message: String) -> void:
	lobby_label.text += "\nRejected: %s" % message
	if lobby_options_popup.visible:
		lobby_options_status.text = "Could not apply: %s" % message
		lobby_options_status.add_theme_color_override("font_color", DesignTokensScript.DANGER)


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


func dismiss_modal() -> bool:
	if ship_color_popup != null and ship_color_popup.visible:
		_hide_ship_color()
		return true
	if lobby_options_popup != null and lobby_options_popup.visible:
		_hide_lobby_options()
		return true
	return false
