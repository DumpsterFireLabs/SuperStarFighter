extends Node

var bridge: NetworkBridge
var network_world: NetworkWorldView
var offline_sandbox: OfflineSandbox
var connection_canvas: CanvasLayer
var connection_screen: Control
var lobby_panel: PanelContainer
var host_field: LineEdit
var port_field: LineEdit
var name_field: LineEdit
var connection_status: Label
var lobby_label: Label
var rounds_control: SpinBox
var start_button: Button
var _applying_lobby_state: bool = false


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
	network_world = NetworkWorldView.new()
	network_world.name = "NetworkWorld"
	add_child(network_world)
	network_world.setup(bridge)
	_create_connection_ui(configuration)
	print("SSF_MODE_READY=client port=%d sandbox=offline_combat network=enet" % configuration.get("port", GameConstants.DEFAULT_PORT))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		_show_connection_screen("Choose online play or the offline combat lab.")


func _create_connection_ui(configuration: Dictionary) -> void:
	connection_canvas = CanvasLayer.new()
	connection_canvas.layer = 20
	connection_canvas.name = "ConnectionUI"
	add_child(connection_canvas)
	connection_screen = Control.new()
	connection_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_canvas.add_child(connection_screen)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("071024")
	connection_screen.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connection_screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 470.0)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	var title := Label.new()
	title.text = "SUPER STAR FIGHTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 36)
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Authoritative Multiplayer Lab"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("d39cff"))
	subtitle.add_theme_font_size_override("font_size", 20)
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
	connect_button.pressed.connect(_connect_online)
	buttons.add_child(connect_button)
	var offline_button := Button.new()
	offline_button.text = "Offline Combat Lab"
	offline_button.pressed.connect(_play_offline)
	buttons.add_child(offline_button)
	connection_status = Label.new()
	connection_status.text = "Direct IP uses UDP. Press F2 at any time to return here."
	connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connection_status.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(connection_status)
	_create_lobby_panel()


func _create_lobby_panel() -> void:
	lobby_panel = PanelContainer.new()
	lobby_panel.position = Vector2(1380.0, 20.0)
	lobby_panel.custom_minimum_size = Vector2(500.0, 300.0)
	lobby_panel.visible = false
	connection_canvas.add_child(lobby_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	lobby_panel.add_child(content)
	var title := Label.new()
	title.text = "ONLINE LOBBY"
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)
	lobby_label = Label.new()
	lobby_label.add_theme_font_size_override("font_size", 16)
	content.add_child(lobby_label)
	var rounds_row := HBoxContainer.new()
	content.add_child(rounds_row)
	var rounds_label := Label.new()
	rounds_label.text = "Rounds to win"
	rounds_row.add_child(rounds_label)
	rounds_control = SpinBox.new()
	rounds_control.min_value = GameConstants.MIN_ROUNDS_TO_WIN
	rounds_control.max_value = GameConstants.MAX_ROUNDS_TO_WIN
	rounds_control.value = GameConstants.DEFAULT_ROUNDS_TO_WIN
	rounds_control.value_changed.connect(_on_rounds_changed)
	rounds_row.add_child(rounds_control)
	start_button = Button.new()
	start_button.text = "Start Match"
	start_button.pressed.connect(bridge.send_start_match)
	content.add_child(start_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnect"
	disconnect_button.pressed.connect(_disconnect_online)
	content.add_child(disconnect_button)


func _add_labeled_field(parent: VBoxContainer, label_text: String, initial_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var field := LineEdit.new()
	field.text = initial_text
	parent.add_child(field)
	return field


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
	network_world.set_network_active(false)
	connection_screen.visible = false
	lobby_panel.visible = false
	offline_sandbox.set_sandbox_active(true)


func _disconnect_online() -> void:
	bridge.stop()
	_show_connection_screen("Disconnected. Ready to reconnect.")


func _show_connection_screen(message: String) -> void:
	if bridge.role == NetworkBridge.Role.CLIENT:
		bridge.stop()
	network_world.set_network_active(false)
	offline_sandbox.set_sandbox_active(false)
	connection_screen.visible = true
	lobby_panel.visible = false
	connection_status.text = message


func _on_connected(peer_id: int) -> void:
	connection_screen.visible = false
	lobby_panel.visible = true
	network_world.set_network_active(true)
	connection_status.text = "Connected as peer %d." % peer_id


func _on_lobby_state(state: Dictionary) -> void:
	var lines: PackedStringArray = []
	for player_value in state.get("players", []):
		var player := player_value as Dictionary
		var badges: PackedStringArray = []
		if int(player.peer_id) == int(state.leader_id):
			badges.append("leader")
		if bool(player.spectator):
			badges.append("spectator")
		var suffix := " [%s]" % ", ".join(badges) if not badges.is_empty() else ""
		lines.append("%s%s" % [player.display_name, suffix])
	lobby_label.text = "Players %d/%d\n%s\n%s" % [(state.get("players", []) as Array).size(), state.get("max_players", 32), "\n".join(lines), "Match active" if state.get("match_active", false) else "Waiting in lobby"]
	var is_leader := int(state.get("leader_id", 0)) == bridge.local_peer_id
	_applying_lobby_state = true
	rounds_control.value = int(state.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN))
	_applying_lobby_state = false
	rounds_control.editable = is_leader and not bool(state.get("match_active", false))
	start_button.disabled = not is_leader or bool(state.get("match_active", false)) or (state.get("players", []) as Array).size() < GameConstants.MIN_PLAYERS


func _on_rounds_changed(value: float) -> void:
	if not _applying_lobby_state:
		bridge.send_lobby_config(roundi(value))


func _on_match_event(event_type: StringName, _server_tick: int, payload: Dictionary) -> void:
	if event_type == &"REQUEST_REJECTED":
		lobby_label.text += "\nRejected: %s" % payload.get("message", "Unknown request")


func _on_rejected(_reason: StringName, message: String) -> void:
	_show_connection_screen(message)


func _on_connection_lost(message: String) -> void:
	_show_connection_screen(message)


func _exit_tree() -> void:
	if bridge != null:
		bridge.stop()
