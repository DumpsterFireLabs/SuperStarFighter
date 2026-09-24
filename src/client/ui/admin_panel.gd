extends Node

signal access_changed(unlocked: bool)

const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const SETTINGS = [
	"rounds_to_win", "player_limit", "npcs_enabled", "npc_difficulty",
	"game_mode", "team_count", "random_spawn_powerups", "random_powerup_interval",
	"random_powerups_permanent", "competitive_view", "overtime_start",
	"server_name", "auto_start",
]

var bridge: NetworkBridge
var _authenticated: bool = false
var _pending_password: String = ""
var _admin_password: String = ""
var _challenge: String = ""
var _command_sequence: int = 0
var _auth_pending: bool = false
var _pending_command: bool = false
var panel: PanelContainer
var blocker: ColorRect
var password_field: LineEdit
var status_label: Label
var output: TextEdit
var roster: VBoxContainer
var setting_choice: OptionButton
var setting_value: LineEdit
var source_field: LineEdit
var confirmation: ConfirmationDialog
var _confirmation_command: Dictionary = {}
var _last_command: String = ""


func configure(network: NetworkBridge) -> void:
	bridge = network
	bridge.client_admin_response.connect(_on_response)


func create_ui(canvas: CanvasLayer, theme: Theme) -> void:
	if panel != null:
		return
	blocker = ColorRect.new()
	blocker.name = "AdminModalBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.color = Color(0.01, 0.02, 0.06, 0.85)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.visible = false
	canvas.add_child(blocker)
	panel = PanelContainer.new()
	panel.name = "AdminPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-490, -340)
	panel.custom_minimum_size = Vector2(980, 680)
	panel.theme = theme
	panel.add_theme_stylebox_override("panel", DesignTokensScript.panel_style(DesignTokensScript.INTERACTIVE, 0.98))
	panel.visible = false
	canvas.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 940
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	var title := Label.new()
	title.text = "SERVER ADMINISTRATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	body.add_child(title)
	var note := Label.new()
	note.text = "Connected players can unlock server controls with the separate admin password. The server checks every command."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	var connect_row := HBoxContainer.new()
	body.add_child(connect_row)
	password_field = _field("Admin password", "", true)
	password_field.max_length = NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
	password_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_row.add_child(password_field)
	connect_row.add_child(_button("UNLOCK ADMIN", _connect_pressed))
	connect_row.add_child(_button("LOCK ADMIN", _disconnect_pressed))
	connect_row.add_child(_button("CLOSE", hide_panel))
	status_label = Label.new()
	status_label.text = "Disconnected."
	body.add_child(status_label)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	actions.add_child(_button("STATUS", func() -> void: _command({"command": "status"})))
	actions.add_child(_button("REFRESH PLAYERS", func() -> void: _command({"command": "players"})))
	actions.add_child(_button("RESTART MATCH", func() -> void: _confirm({"command": "restart_match"}, "Restart the match from round one? Scores and builds will be reset.")))
	var shutdown_button := _button("SHUT DOWN SERVER", func() -> void: _confirm({"command": "shutdown"}, "Shut down this dedicated server and disconnect everyone?"))
	shutdown_button.theme_type_variation = &"DangerButton"
	actions.add_child(shutdown_button)
	output = TextEdit.new()
	output.editable = false
	output.custom_minimum_size.y = 145
	body.add_child(output)
	var roster_title := Label.new()
	roster_title.text = "CONNECTED PLAYERS"
	body.add_child(roster_title)
	roster = VBoxContainer.new()
	body.add_child(roster)
	var settings_row := HBoxContainer.new()
	body.add_child(settings_row)
	setting_choice = OptionButton.new()
	setting_choice.custom_minimum_size.x = 260
	for setting in SETTINGS:
		setting_choice.add_item(setting)
	settings_row.add_child(setting_choice)
	setting_value = _field("Value (JSON or text)", "", false)
	setting_value.max_length = 128
	setting_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_row.add_child(setting_value)
	settings_row.add_child(_button("APPLY SETTING", _apply_setting))
	var source_row := HBoxContainer.new()
	body.add_child(source_row)
	source_field = _field("Source address", "", false)
	source_field.max_length = 128
	source_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_row.add_child(source_field)
	source_row.add_child(_button("BLOCK", func() -> void: _confirm({"command": "block", "source": source_field.text.strip_edges()}, "Block this source address?")))
	source_row.add_child(_button("UNBLOCK", func() -> void: _command({"command": "unblock", "source": source_field.text.strip_edges()})))
	confirmation = ConfirmationDialog.new()
	confirmation.confirmed.connect(func() -> void: _command(_confirmation_command))
	panel.add_child(confirmation)


func show_panel() -> void:
	if bridge == null or bridge.role != NetworkBridge.Role.CLIENT or bridge.local_peer_id <= 0:
		return
	blocker.visible = true
	panel.visible = true
	blocker.move_to_front()
	panel.move_to_front()
	password_field.grab_focus()


func hide_panel() -> void:
	if _auth_pending or not _pending_password.is_empty():
		_disconnect_pressed()
	blocker.visible = false
	panel.visible = false
	password_field.clear()
	if _authenticated:
		status_label.text = "Admin unlocked for this connection."


func is_visible() -> bool:
	return panel != null and panel.visible


func is_authenticated() -> bool:
	return _authenticated


func reset_session() -> void:
	_disconnect_pressed()
	hide_panel()


func _field(placeholder: String, value: String, secret: bool) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = value
	field.secret = secret
	field.custom_minimum_size.y = 38
	return field


func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	return button


func _connect_pressed() -> void:
	if bridge == null or bridge.role != NetworkBridge.Role.CLIENT or bridge.local_peer_id <= 0:
		status_label.text = "Join a server first."
		return
	if not NetworkProtocol.is_valid_admin_password(password_field.text):
		status_label.text = "Enter the separate admin password (12–64 characters)."
		return
	if _auth_pending or not _pending_password.is_empty():
		status_label.text = "Waiting for the current admin challenge."
		return
	if _authenticated:
		bridge.send_admin_revoke()
		_authenticated = false
		_admin_password = ""
		_challenge = ""
		_command_sequence = 0
		_auth_pending = false
		access_changed.emit(false)
	_pending_password = password_field.text
	password_field.clear()
	bridge.send_admin_challenge_request()
	status_label.text = "Requesting admin challenge…"


func _disconnect_pressed() -> void:
	if bridge != null and bridge.role == NetworkBridge.Role.CLIENT:
		bridge.send_admin_revoke()
	_authenticated = false
	_pending_password = ""
	_admin_password = ""
	_challenge = ""
	_command_sequence = 0
	_auth_pending = false
	_pending_command = false
	password_field.clear()
	output.clear()
	access_changed.emit(false)
	status_label.text = "Admin locked."


func _command(request: Dictionary) -> void:
	if not _authenticated or _pending_command:
		status_label.text = "Unlock admin first, or wait for the current command."
		return
	_pending_command = true
	_command_sequence += 1
	bridge.send_admin_command(request, _command_sequence, NetworkProtocol.admin_command_signature(_challenge, _admin_password, _command_sequence, request))
	_last_command = String(request.get("command", ""))
	status_label.text = "Running %s…" % _last_command


func _confirm(request: Dictionary, message: String) -> void:
	if not _authenticated:
		status_label.text = "Unlock admin first."
		return
	_confirmation_command = request
	confirmation.dialog_text = message
	confirmation.popup_centered()


func _apply_setting() -> void:
	var raw := setting_value.text.strip_edges()
	if raw.is_empty():
		status_label.text = "Enter a setting value."
		return
	var value: Variant = JSON.parse_string(raw)
	if value == null and raw != "null":
		value = raw
	_command({"command": "set", "setting": SETTINGS[setting_choice.selected], "value": value})


func _on_response(response: Dictionary) -> void:
	var event_name := String(response.get("event", ""))
	if event_name == "challenge":
		var challenge := String(response.get("challenge", ""))
		if not NetworkProtocol.is_valid_auth_challenge(challenge) or _pending_password.is_empty():
			status_label.text = "Invalid admin challenge."
			_pending_password = ""
			return
		var proof := NetworkProtocol.admin_password_proof(challenge, _pending_password)
		_admin_password = _pending_password
		_challenge = challenge
		_command_sequence = 0
		_pending_password = ""
		_auth_pending = true
		bridge.send_admin_proof(proof)
		status_label.text = "Checking admin password…"
		return
	if event_name == "authenticated":
		if not _auth_pending:
			bridge.send_admin_revoke()
			return
		_auth_pending = false
		_authenticated = true
		access_changed.emit(true)
		status_label.text = "Admin unlocked for this connection."
		_command({"command": "status"})
		return
	if not _pending_password.is_empty():
		_pending_password = ""
		_admin_password = ""
		_challenge = ""
		status_label.text = String(response.get("error", "Admin authentication failed."))
		return
	if _auth_pending:
		_auth_pending = false
		_admin_password = ""
		_challenge = ""
		status_label.text = String(response.get("error", "Admin authentication failed."))
		return
	_pending_command = false
	if String(response.get("error", "")).contains("signature or sequence"):
		_disconnect_pressed()
		status_label.text = "Admin session expired. Unlock it again."
		return
	status_label.text = "Command succeeded." if bool(response.get("ok", false)) else String(response.get("error", "Command failed."))
	output.text = JSON.stringify(response, "  ")
	if _last_command == "players" and bool(response.get("ok", false)):
		_show_players(response.get("players", []) as Array)


func _show_players(players: Array) -> void:
	for child in roster.get_children():
		child.queue_free()
	if players.is_empty():
		var empty := Label.new()
		empty.text = "No human players connected."
		roster.add_child(empty)
		return
	for player_value in players:
		if not player_value is Dictionary:
			continue
		var player := player_value as Dictionary
		var peer_id := int(player.get("peer_id", 0))
		var row := HBoxContainer.new()
		roster.add_child(row)
		var label := Label.new()
		label.text = "%s  (#%d)  %s" % [String(player.get("display_name", "")), peer_id, String(player.get("source", ""))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_button("KICK", func() -> void: _confirm({"command": "kick", "peer_id": peer_id}, "Kick player #%d?" % peer_id)))
		row.add_child(_button("BAN", func() -> void: _confirm({"command": "ban", "peer_id": peer_id}, "Ban player #%d and block their source address?" % peer_id)))
