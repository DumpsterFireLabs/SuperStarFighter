extends Node

## Owns connection forms and discovery; composes lobby UI and hosted-session lifetime.
## The client coordinates navigation between gameplay and these screens.

const PreferencesScript = preload("res://src/client/ui/connection_preferences.gd")
var preferences := PreferencesScript.new()

const PresetControls = preload("res://src/client/ui/match_preset_controls.gd")

const NavigationScript = preload("res://src/client/ui/screen_navigation.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const LobbyScreenScript = preload("res://src/client/ui/lobby_screen_controller.gd")
const HostedSessionScript = preload("res://src/client/network/hosted_session.gd")

signal tutorial_requested
signal offline_requested
signal settings_requested
signal credits_requested
signal disconnect_requested
signal connection_requested
var bridge: NetworkBridge
var interface_theme: Theme
var credits_button: Button
var lobby := LobbyScreenScript.new()
var hosted_session := HostedSessionScript.new()

var connection_canvas: CanvasLayer
var connection_screen: Control
var connection_form_panel: PanelContainer
var connection_tabs: TabContainer
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
var host_preset_control: OptionButton
var host_preset_note: Label
var version_label: Label
var connection_primary_button: Button
var direct_connect_button: Button
var host_join_button: Button


func _init() -> void:
	lobby.name = "LobbyScreenController"
	lobby.settings_requested.connect(settings_requested.emit)
	lobby.disconnect_requested.connect(disconnect_requested.emit)
	add_child(lobby)
	hosted_session.name = "HostedSession"
	add_child(hosted_session)


func configure(network: NetworkBridge, theme: Theme) -> void:
	bridge = network
	interface_theme = theme


func create_ui(configuration: Dictionary) -> void:
	if connection_canvas != null:
		return
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
	connection_form_panel.add_theme_stylebox_override("panel", DesignTokensScript.panel_style(DesignTokensScript.INTERACTIVE, 0.96))
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
	lesson_button.pressed.connect(tutorial_requested.emit)
	buttons.add_child(lesson_button)
	var offline_button := Button.new()
	offline_button.text = "Combat Lab"
	offline_button.tooltip_text = "Offline combat lab: freely experiment with builds and targets."
	offline_button.theme_type_variation = &"PrimaryButton"
	offline_button.custom_minimum_size.y = 54.0
	offline_button.pressed.connect(offline_requested.emit)
	buttons.add_child(offline_button)
	connection_primary_button = offline_button
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.theme_type_variation = &"QuietButton"
	settings_button.custom_minimum_size.y = 54.0
	settings_button.pressed.connect(settings_requested.emit)
	buttons.add_child(settings_button)
	credits_button = Button.new()
	credits_button.name = "CreditsButton"
	credits_button.text = "Credits"
	credits_button.theme_type_variation = &"QuietButton"
	credits_button.custom_minimum_size.y = 54.0
	credits_button.pressed.connect(credits_requested.emit)
	buttons.add_child(credits_button)
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
	lobby.configure(bridge, interface_theme, connection_canvas, preferences)
	lobby.create_ui()


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
	host_scroll.follow_focus = true
	host_scroll.custom_minimum_size.y = 260.0
	host_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(host_scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 8)
	host_scroll.add_child(fields)
	host_preset_control = PresetControls.create_picker(fields)
	host_preset_note = PresetControls.create_note(fields)
	host_preset_control.item_selected.connect(func(index: int) -> void:
		host_preset_note.text = PresetControls.description(index)
	)
	server_name_field = _add_compact_labeled_field(fields, "Server name", "Super Star Arena")
	server_name_field.max_length = LanDiscoveryProtocol.MAX_SERVER_NAME_LENGTH
	host_port_field = _add_compact_labeled_field(fields, "Gameplay UDP port", str(configuration.get("port", GameConstants.DEFAULT_PORT)))
	host_password_field = _add_compact_labeled_field(fields, "Required lobby password", "")
	host_password_field.secret = true
	host_password_field.max_length = NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
	var host_center := CenterContainer.new()
	tab.add_child(host_center)
	host_join_button = Button.new()
	host_join_button.name = "HostJoinButton"
	host_join_button.text = "HOST & JOIN"
	host_join_button.theme_type_variation = &"PrimaryButton"
	host_join_button.custom_minimum_size = Vector2(280.0, 48.0)
	host_join_button.pressed.connect(_host_online)
	host_center.add_child(host_join_button)


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


func _on_direct_host_changed(address: String) -> void:
	_apply_remembered_password(address, _remembered_password_port())


func _on_direct_port_changed(_port_text: String) -> void:
	_apply_remembered_password(host_field.text, _remembered_password_port())


func _apply_remembered_password(address: String, port: int) -> void:
	if direct_password_field == null or remember_password_button == null:
		return
	var remembered := preferences.password_for_endpoint(address, port)
	direct_password_field.text = remembered
	remember_password_button.button_pressed = not remembered.is_empty()


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
	connection_requested.emit()
	preferences.begin_attempt(address, port, lobby_password, remember_password_button.button_pressed)
	connection_status.text = "Authenticating with %s:%d…" % [address, port]
	var error: Error = bridge.start_client(address, port, display_name, GameConstants.PROTOCOL_VERSION, lobby_password)
	if error != OK:
		preferences.discard_attempt()
		connection_status.text = bridge.last_error


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
	bridge.stop()
	hosted_session.stop()
	var error := hosted_session.start({
		"port": port,
		"max_players": GameConstants.DEFAULT_MAX_PLAYERS,
		"rounds_to_win": GameConstants.DEFAULT_ROUNDS_TO_WIN,
		"server_name": server_name,
		"lobby_password": lobby_password,
		"match_preset": String(host_preset_control.get_item_metadata(host_preset_control.selected)),
	})
	if error != OK:
		connection_status.text = hosted_session.last_error
		hosted_session.stop()
		return
	connection_requested.emit()
	connection_status.text = "Hosting %s on UDP %d and joining locally…" % [server_name, port]
	preferences.discard_attempt()
	error = bridge.start_client("127.0.0.1", port, display_name, GameConstants.PROTOCOL_VERSION, lobby_password)
	if error != OK:
		connection_status.text = bridge.last_error
		hosted_session.stop()


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
	var remembered_password := preferences.password_for_endpoint(
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
	preferences.confirm_connected()
	connection_screen.visible = true
	connection_form_panel.visible = false
	lobby.set_presented(true)
	connection_status.text = "Connected as peer %d." % peer_id
	connection_status.add_theme_color_override("font_color", Color("62ff9b"))
	lobby.submit_appearance()
	lobby.focus_ready()


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
	if is_instance_valid(lan_browser):
		return
	lan_browser = LanDiscoveryService.new()
	lan_browser.name = "LanServerBrowser"
	add_child(lan_browser)
	lan_browser.servers_updated.connect(_on_lan_servers_updated)
	var discovery_error := lan_browser.start_browser()
	if discovery_error != OK:
		connection_status.text = lan_browser.last_error


func shutdown() -> void:
	if is_instance_valid(lan_browser):
		lan_browser.stop()
	hosted_session.stop()
	preferences.discard_attempt()


func _exit_tree() -> void:
	shutdown()


func is_hosting() -> bool:
	return hosted_session.is_hosting()


func reset_connection(message: String, is_error: bool = false) -> void:
	preferences.discard_attempt()
	hosted_session.stop()
	connection_screen.show()
	connection_form_panel.show()
	lobby.reset_session()
	connection_status.text = message
	connection_status.add_theme_color_override("font_color", Color("ff7994") if is_error else Color("aebbd4"))


func render_lobby(state: Dictionary) -> void:
	if not bool(state.get("match_active", false)):
		connection_screen.show()
		connection_form_panel.hide()
	lobby.render_lobby(state)


func dismiss_modal() -> bool:
	return lobby.dismiss_modal()


func show_request_rejection(message: String) -> void:
	lobby.show_request_rejection(message)


func show_waiting_lobby() -> void:
	connection_screen.show()
	connection_form_panel.hide()
	lobby.set_presented(true)


func hide_screens() -> void:
	connection_screen.hide()
	lobby.set_presented(false)


func is_visible() -> bool:
	return connection_screen.visible


func is_lobby_visible() -> bool:
	return lobby.is_presented()


func focus_settings() -> void:
	lobby.focus_settings()


func focus_menu() -> void:
	connection_primary_button.grab_focus()


func focus_credits() -> void:
	credits_button.grab_focus()


func focus_password() -> void:
	connection_tabs.current_tab = 1
	direct_password_field.grab_focus()


func stop_hosting() -> void:
	hosted_session.stop()
