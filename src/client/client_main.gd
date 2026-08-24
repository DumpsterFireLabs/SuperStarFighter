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
var match_panel: PanelContainer
var match_label: Label
var draft_panel: PanelContainer
var draft_title: Label
var draft_buttons: Array[Button] = []
var scoreboard_panel: PanelContainer
var scoreboard_label: Label
var card_catalog := CardCatalog.create_default()
var active_offer_token: String = ""
var active_offer_deadline: int = -1
var latest_match_payload: Dictionary = {}
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
	_create_match_ui()
	print("SSF_MODE_READY=client port=%d sandbox=offline_combat network=enet" % configuration.get("port", GameConstants.DEFAULT_PORT))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		_show_connection_screen("Choose online play or the offline combat lab.")
	if event is InputEventKey and event.pressed and not event.echo and draft_panel != null and draft_panel.visible:
		for index in draft_buttons.size():
			if event.is_action_pressed("draft_%d" % (index + 1)):
				_select_draft_card(index)
				get_viewport().set_input_as_handled()
				break


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


func _create_match_ui() -> void:
	match_panel = PanelContainer.new()
	match_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	match_panel.position = Vector2(-270.0, 18.0)
	match_panel.custom_minimum_size = Vector2(540.0, 88.0)
	match_panel.visible = false
	connection_canvas.add_child(match_panel)
	match_label = Label.new()
	match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_label.add_theme_font_size_override("font_size", 18)
	match_label.add_theme_color_override("font_color", Color("73f7ff"))
	match_panel.add_child(match_label)

	draft_panel = PanelContainer.new()
	draft_panel.set_anchors_preset(Control.PRESET_CENTER)
	draft_panel.position = Vector2(-510.0, -230.0)
	draft_panel.custom_minimum_size = Vector2(1020.0, 460.0)
	draft_panel.visible = false
	connection_canvas.add_child(draft_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	draft_panel.add_child(content)
	draft_title = Label.new()
	draft_title.text = "CHOOSE YOUR UPGRADE"
	draft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_title.add_theme_font_size_override("font_size", 28)
	draft_title.add_theme_color_override("font_color", Color("d39cff"))
	content.add_child(draft_title)
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	content.add_child(cards)
	for index in GameConstants.CARD_OFFER_SIZE:
		var button := Button.new()
		button.custom_minimum_size = Vector2(190.0, 320.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", Color("e8f5ff"))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.pressed.connect(_select_draft_card.bind(index))
		cards.add_child(button)
		draft_buttons.append(button)

	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.position = Vector2(-360.0, -260.0)
	scoreboard_panel.custom_minimum_size = Vector2(720.0, 520.0)
	scoreboard_panel.visible = false
	connection_canvas.add_child(scoreboard_panel)
	scoreboard_label = Label.new()
	scoreboard_label.add_theme_font_size_override("font_size", 18)
	scoreboard_label.add_theme_color_override("font_color", Color("e8f5ff"))
	scoreboard_panel.add_child(scoreboard_label)


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
	latest_match_payload.clear()
	network_world.set_network_active(false)
	connection_screen.visible = false
	lobby_panel.visible = false
	match_panel.visible = false
	draft_panel.visible = false
	scoreboard_panel.visible = false
	offline_sandbox.set_sandbox_active(true)


func _disconnect_online() -> void:
	bridge.stop()
	_show_connection_screen("Disconnected. Ready to reconnect.")


func _show_connection_screen(message: String) -> void:
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
	elif event_type == &"DRAFT_OFFER":
		_show_draft_offer(payload)
	elif event_type == &"STATE_CHANGED":
		latest_match_payload = payload.duplicate(true)
		network_world.apply_match_state(payload)
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
		button.text = "%d\n\n%s\n%s\n\n%s\n\nSTACK %d → %d / %d" % [
			index + 1,
			card.display_name,
			card.category_name().to_upper(),
			card.description,
			current_stacks,
			current_stacks + 1,
			card.max_stacks,
		] if card != null else String(card_ids[index])
		if card != null:
			var category_color := _draft_category_color(card.category)
			button.add_theme_color_override("font_color", category_color.lightened(0.42))
			button.add_theme_stylebox_override("normal", _draft_card_style(category_color, false))
			button.add_theme_stylebox_override("hover", _draft_card_style(category_color.lightened(0.18), true))
			button.add_theme_stylebox_override("pressed", _draft_card_style(category_color.lightened(0.28), true))
			button.add_theme_stylebox_override("focus", _draft_card_style(category_color.lightened(0.3), true))
			button.add_theme_stylebox_override("disabled", _draft_card_style(category_color.darkened(0.35), false))
			button.tooltip_text = "%s — %s" % [card.display_name, card.description]
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
		return
	match_panel.visible = true
	if state_name != "DRAFT":
		draft_panel.visible = false
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
		status = "★ %s WINS THE MATCH ★ · returning to lobby in %.1fs" % [_player_name(int(latest_match_payload.get("match_winner", 0))), seconds_left]
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
	style.bg_color = Color(color, 0.24 if emphasized else 0.12)
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
	var lines := PackedStringArray(["SCOREBOARD", "", "PILOT                         HEATS  ROUNDS  BUILD"])
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
	scoreboard_label.text = "\n".join(lines)


func _on_rejected(_reason: StringName, message: String) -> void:
	_show_connection_screen(message)


func _on_connection_lost(message: String) -> void:
	_show_connection_screen(message)


func _exit_tree() -> void:
	if bridge != null:
		bridge.stop()
