extends RefCounted

const ConnectionScreen = preload("res://src/client/ui/connection_controller.gd")
const Preferences = preload("res://src/client/ui/connection_preferences.gd")

class MemoryPreferences extends Preferences:
	func load_appearance() -> Error:
		return OK
	func save_appearance(random_value: bool, color: Color, pattern: StringName) -> Error:
		random_color = random_value
		ship_color = color
		ship_pattern = pattern
		return OK
	func password_for_endpoint(_address: String, _port: int) -> String:
		return ""

class RecordingBridge extends NetworkBridge:
	var requests: Array[Dictionary] = []
	func send_ready_state(ready: bool) -> void:
		requests.append({"ready": ready})
	func send_lobby_config(rounds: int) -> void:
		requests.append({"rounds": rounds})
	func send_player_appearance(random_color: bool, color: Color, pattern: StringName = &"solid") -> void:
		requests.append({"random_color": random_color, "color": color, "pattern": pattern})
	func start_client(host: String, port: int, display_name: String, protocol_version: int = GameConstants.PROTOCOL_VERSION, password: String = "") -> Error:
		requests.append({"host": host, "port": port, "display_name": display_name, "protocol": protocol_version, "password": password})
		session.last_error = "Fixture transport unavailable"
		return ERR_CANT_CONNECT


static func run(context: TestContext, parent: Node) -> void:
	var fixture := Node.new()
	parent.add_child(fixture)
	var bridge := RecordingBridge.new()
	fixture.add_child(bridge)
	bridge.session.local_peer_id = 2
	var screen := ConnectionScreen.new()
	fixture.add_child(screen)
	screen.preferences = MemoryPreferences.new()
	screen.configure(bridge, preload("res://src/client/ui/design_tokens.gd").create_interface_theme())
	screen.create_ui({})
	var child_count := screen.connection_canvas.get_child_count()
	screen.create_ui({})
	context.expect_equal(screen.connection_canvas.get_child_count(), child_count, "connection construction is idempotent without a client root")
	var events := {"offline": 0, "settings": 0, "credits": 0, "disconnect": 0, "connecting": 0}
	screen.offline_requested.connect(func() -> void: events.offline += 1)
	screen.settings_requested.connect(func() -> void: events.settings += 1)
	screen.credits_requested.connect(func() -> void: events.credits += 1)
	screen.disconnect_requested.connect(func() -> void: events.disconnect += 1)
	screen.connection_requested.connect(func() -> void: events.connecting += 1)
	screen.connection_primary_button.pressed.emit()
	screen.credits_button.pressed.emit()
	screen.lobby.lobby_settings_button.pressed.emit()
	screen.lobby.lobby_disconnect_button.pressed.emit()
	context.expect_equal(events.offline, 1, "standalone menu publishes combat lab navigation")
	context.expect_equal(events.credits, 1, "standalone menu publishes credits navigation")
	context.expect_equal(events.settings, 1, "standalone lobby publishes settings navigation")
	context.expect_equal(events.disconnect, 1, "standalone lobby publishes disconnect navigation")
	var state := {"leader_id": 2, "player_limit": 4, "rounds_to_win": 5, "players": [
		{"peer_id": 2, "display_name": "Host", "ready": false, "ship_color": "42e8ff"},
		{"peer_id": 3, "display_name": "Guest", "ready": true},
	]}
	screen.render_lobby(state)
	context.expect_equal(bridge.requests.size(), 0, "authoritative lobby observation does not echo ready or rule requests")
	context.expect_true(screen.is_lobby_visible() and not screen.connection_form_panel.visible, "lobby observation presents the waiting room")
	screen.lobby.ready_button.button_pressed = true
	context.expect_equal(bridge.requests.back(), {"ready": true}, "ready interaction reaches the injected bridge")
	screen.lobby.rounds_control.value = 4
	context.expect_equal(bridge.requests.back(), {"rounds": 4}, "host rule interaction reaches the injected bridge")
	screen.lobby._show_ship_color_popup()
	screen.lobby._on_ship_color_changed(Color("ff4ea3"))
	screen.render_lobby(state)
	context.expect_true(screen.lobby.ship_color_popup.visible and not screen.lobby.lobby_panel.visible, "live roster updates preserve appearance modal exclusivity")
	context.expect_equal(screen.lobby.pending_ship_color.to_html(false), "ff4ea3", "live roster updates preserve pending appearance")
	screen.lobby._apply_ship_color()
	context.expect_equal(bridge.requests.back().color.to_html(false), "ff4ea3", "appearance Apply submits the pending colour")
	context.expect_true(screen.lobby.lobby_panel.visible, "applying appearance restores the waiting room")
	screen.lobby._show_lobby_options()
	screen.render_lobby(state)
	context.expect_true(screen.lobby.lobby_options_popup.visible and not screen.lobby.lobby_panel.visible, "live roster updates preserve options modal exclusivity")
	screen.show_request_rejection("Only the host may edit")
	context.expect_true(screen.lobby.lobby_preset_note.text.contains("Only the host may edit"), "lobby rejection appears in the active options modal")
	screen.hide_screens()
	context.expect_false(screen.is_visible() or screen.lobby.lobby_panel.visible or screen.lobby.lobby_options_popup.visible or screen.lobby.lobby_options_blocker.visible, "match navigation hides every connection surface")
	screen.render_lobby(state)
	screen.lobby._show_ship_color_popup()
	screen.reset_connection("Connection lost", true)
	context.expect_true(screen.connection_form_panel.visible and not screen.lobby.lobby_panel.visible and not screen.lobby.ship_color_popup.visible, "disconnect closes modals without resurrecting the lobby")
	screen.render_lobby(state)
	screen.lobby._show_lobby_options()
	state.match_active = true
	screen.render_lobby(state)
	context.expect_false(screen.is_lobby_visible() or screen.lobby.lobby_options_popup.visible, "active match observation closes lobby options")
	screen.reset_connection("Retry")
	screen.host_field.text = "203.0.113.10"
	screen.port_field.text = "bad"
	screen.direct_password_field.text = "test-lobby"
	screen.name_field.text = "Pilot"
	screen._connect_online()
	context.expect_equal(events.connecting, 0, "invalid direct input cannot change gameplay navigation")
	screen.port_field.text = "17660"
	screen._connect_online()
	context.expect_equal(events.connecting, 1, "valid direct input publishes connection navigation")
	context.expect_equal(bridge.requests.back().host, "203.0.113.10", "direct internet address passes unchanged to transport")
	context.expect_equal(bridge.requests.back().port, 17660, "direct port passes unchanged to transport")
	context.expect_true(screen.connection_status.text.contains("Fixture transport unavailable"), "immediate transport failure remains visible for retry")
	screen.shutdown()
	screen.shutdown()
	fixture.free()
	var hosted := preload("res://src/client/network/hosted_session.gd").new()
	parent.add_child(hosted)
	var config := {"port": 17661, "max_players": 4, "server_name": "Lifecycle fixture", "lobby_password": "test-lobby"}
	context.expect_equal(hosted.start(config), OK, "standalone hosted session starts without UI")
	var runtime_path := hosted.runtime_root.get_path()
	context.expect_true(parent.get_tree().get_multiplayer(runtime_path) != parent.multiplayer, "standalone host registers an isolated transport")
	hosted.free()
	context.expect_equal(parent.get_tree().get_multiplayer(runtime_path), parent.multiplayer, "freeing a live host unregisters its multiplayer branch")
	hosted = preload("res://src/client/network/hosted_session.gd").new()
	parent.add_child(hosted)
	context.expect_equal(hosted.start(config), OK, "teardown releases the gameplay port for a new host")
	hosted.stop()
	hosted.stop()
	context.expect_false(hosted.is_hosting(), "repeated host teardown is safe")
	hosted.free()
