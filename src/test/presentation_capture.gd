extends SceneTree

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
var capture_directory: String = ""
var capture_label: String = "capture"
var capture_resolution: Vector2i = Vector2i(1280, 720)
const SHIP_PATTERNS: Array[String] = ["solid", "zebra", "leopard", "checkerboard", "racing", "chevron"]


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--capture-label="):
			capture_label = argument.trim_prefix("--capture-label=")
	if capture_directory.is_empty():
		printerr("PRESENTATION_CAPTURE_ERROR=missing_capture_directory")
		quit(2)
		return
	var dimensions := capture_label.split("x")
	if dimensions.size() != 2 or not dimensions[0].is_valid_int() or not dimensions[1].is_valid_int():
		printerr("PRESENTATION_CAPTURE_ERROR=invalid_capture_resolution:%s" % capture_label)
		quit(2)
		return
	capture_resolution = Vector2i(int(dimensions[0]), int(dimensions[1]))
	DirAccess.make_dir_recursive_absolute(capture_directory)
	_capture_sequence.call_deferred()


func _capture_sequence() -> void:
	root.set_meta("ssf_presentation_capture_resolution", capture_resolution)
	var packed_scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := packed_scene.instantiate()
	root.add_child(client)
	root.size = capture_resolution
	client.current_resolution = capture_resolution
	client.resolution_control.select(client.RESOLUTION_OPTIONS.find(capture_resolution))
	await process_frame
	await process_frame
	await _capture(client, "splash")
	client.splash_auto_timer.stop()
	client.splash_stage = 1
	client.studio_splash.visible = false
	client.splash_neon_backdrop.visible = true
	client.game_splash.visible = true
	client.game_splash.modulate = Color.WHITE
	await _capture(client, "game_splash")
	client._dismiss_splash(true)
	var local_servers: Array[Dictionary] = [
		{"server_name": "Graphite's Arena", "address": "192.168.1.42", "game_port": 7000, "protocol_version": GameConstants.PROTOCOL_VERSION, "human_count": 3, "npc_count": 5, "player_limit": 12, "match_active": false, "ping_ms": 3},
		{"server_name": "Battle in Progress", "address": "192.168.1.77", "game_port": 7010, "protocol_version": GameConstants.PROTOCOL_VERSION, "human_count": 6, "npc_count": 2, "player_limit": 16, "match_active": true, "ping_ms": 7},
	]
	client._on_lan_servers_updated(local_servers)
	await _capture(client, "menu")
	client._show_credits()
	await _capture(client, "credits")
	client._hide_credits()
	client.connection_tabs.current_tab = 2
	await _capture(client, "host_menu")
	client.connection_tabs.current_tab = 0
	client._show_settings(false)
	await _capture(client, "settings")
	client.current_window_mode = client.WindowModeOption.EXCLUSIVE_FULLSCREEN
	client.window_mode_control.select(client.WindowModeOption.EXCLUSIVE_FULLSCREEN)
	client.current_resolution = Vector2i(5120, 1440)
	client.resolution_control.select(client.RESOLUTION_OPTIONS.find(client.current_resolution))
	client._update_resolution_control_state()
	await _capture(client, "fullscreen_settings")
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.CONTROLLER, false)
	client.settings_tabs.current_tab = 1
	client._refresh_input_settings_ui()
	await _capture(client, "controls")
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.KEYBOARD_MOUSE, false)
	client.settings_tabs.current_tab = 0
	client.current_window_mode = client.WindowModeOption.WINDOWED
	client.current_resolution = capture_resolution
	client._update_resolution_control_state()
	client._hide_settings()

	var players: Array[Dictionary] = []
	for index in 32:
		players.append({"peer_id": index + 2, "display_name": "Pilot %02d" % (index + 1), "ship_color": ServerLobby.RANDOM_SHIP_COLORS[index % ServerLobby.RANDOM_SHIP_COLORS.size()], "ship_pattern": SHIP_PATTERNS[(index + 3) % SHIP_PATTERNS.size()], "spectator": false, "is_npc": index >= 8, "npc_difficulty": index % NpcPilotController.DIFFICULTY_NAMES.size(), "ready": index != 5, "team_id": 1 + index % 4, "team_selection": 0})
	client.bridge.local_peer_id = 2
	client._on_lobby_state({"players": players, "leader_id": 2, "player_limit": 32, "server_capacity": 32, "npc_count": 24, "ready_human_count": 7, "all_humans_ready": false, "npcs_enabled": true, "random_spawn_powerups": true, "match_active": false, "rounds_to_win": 3, "game_mode": GameModeRules.Mode.TEAM_DEATH_MATCH, "team_count": 4, "team_setup_valid": true, "team_setup_error": ""})
	await _capture(client, "lobby_32")
	client.lobby_settings_button.pressed.emit()
	await _capture(client, "lobby_settings")
	client._hide_settings()
	var local_color_swatch := client.lobby_roster.get_child(0).get_node("ShipColor") as Button
	local_color_swatch.pressed.emit()
	client.ship_color_picker.color = Color("ff4ea3")
	client.ship_pattern_control.select(3)
	client._on_ship_pattern_selected(3)
	await _capture(client, "lobby_color_picker")
	client._hide_ship_color(false)
	client._show_lobby_options()
	await _capture(client, "lobby_options")
	client._hide_lobby_options(false)
	var roster_scroll := client.lobby_roster.get_parent() as ScrollContainer
	roster_scroll.scroll_vertical = 100000
	await _capture(client, "lobby_npc_difficulties")
	roster_scroll.scroll_vertical = 0

	client.lobby_panel.visible = false
	client.connection_screen.visible = false
	client.network_world.set_network_active(true)
	client.latest_match_payload = {"state_name": "DRAFT", "round_number": 1, "heat_number": 0, "deadline_tick": 1800, "builds": {2: {}}}
	client.network_world.latest_server_tick = 0
	client._show_draft_offer({"offer_token": "capture", "card_ids": [&"phase_thrusters", &"blink_capacitor", &"beam_emitter", &"prismatic_lance", &"zero_point_loader"], "deadline_tick": 1800})
	await _capture(client, "draft")
	await _capture_card_hover(client, client.draft_buttons[1] as Button, "draft_card_hover")
	client.latest_match_payload["draft_bye_peer_id"] = 2
	client._show_draft_bye(1800)
	client._update_match_presentation()
	await _capture(client, "draft_bye")
	client.draft_panel.visible = false
	client.draft_bye_label.visible = false
	client.latest_match_payload = {"state_name": "COUNTDOWN", "entered_tick": 100, "deadline_tick": 280, "round_number": 1, "heat_number": 1, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {}, "builds": {2: {}, 3: {}}}
	client.network_world.latest_server_tick = 160
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	await _capture(client, "heat_ready")
	client.network_world.latest_server_tick = 274
	client._update_match_presentation()
	await _capture(client, "heat_begin")

	client.match_panel.visible = true
	client.network_world.local_peer_id = 2
	client.network_world._on_snapshot({"server_tick": 200, "acknowledged_input": 10, "states": [
		{"peer_id": 2, "position": Vector2(420.0, 340.0), "velocity": Vector2(280.0, 0.0), "aim_angle": 0.0, "health": 78.0, "shield": 64.0, "ammunition": 5, "alive": true, "shielding": false},
		{"peer_id": 3, "position": Vector2(980.0, 520.0), "velocity": Vector2(-210.0, 70.0), "aim_angle": PI, "health": 125.0, "shield": 100.0, "ammunition": 8, "alive": true, "shielding": true},
	]})
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "entered_tick": 100, "round_number": 2, "heat_number": 3, "deadline_tick": -1, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {2: {"heat_wins": 1, "round_wins": 1}, 3: {"heat_wins": 0, "round_wins": 0}}, "builds": {2: {&"rapid_cycling": 2}, 3: {&"reinforced_hull": 1}}, "powerups": [{"powerup_id": 1, "card_id": &"kinetic_prow", "position": Vector2(700.0, 430.0), "rarity": CardDefinition.Rarity.RARE}], "random_spawn_powerups": true, "overtime_start_tick": 5600, "game_mode": GameModeRules.Mode.KING_OF_THE_HILL, "teams": {2: 1, 3: 2}, "objective": {"active": true, "mode": GameModeRules.Mode.KING_OF_THE_HILL, "position": Vector2(700.0, 430.0), "zone_radius": GameModeRules.OBJECTIVE_ZONE_RADIUS, "controller_id": 2, "progress": {2: 12.5}, "target_seconds": GameModeRules.HILL_HOLD_SECONDS}}
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	await _capture(client, "combat")
	for map_id in ArenaLayout.map_ids():
		client.latest_match_payload["map_id"] = map_id
		client.latest_match_payload["map_name"] = ArenaLayout.display_name(map_id)
		client.network_world.apply_match_state(client.latest_match_payload)
		client._update_match_presentation()
		await _capture(client, "map_%s" % map_id)
	client.latest_match_payload["participant_peer_ids"] = [2, 3, 4, 5]
	client.latest_match_payload["scores"] = {
		2: {"heat_wins": 1, "round_wins": 1},
		3: {"heat_wins": 1, "round_wins": 0},
		4: {"heat_wins": 0, "round_wins": 1},
		5: {"heat_wins": 0, "round_wins": 0},
	}
	client.latest_match_payload["builds"] = {
		2: {&"rapid_cycling": 7, &"twin_shot": 4},
		3: {&"reinforced_hull": 5, &"beam_emitter": 3},
		4: {&"flux_reservoir": 6, &"endless_belt": 8},
		5: {&"inertial_dampers": 2, &"hollow_points": 9},
	}
	client.audio_director.gameplay_track_paths.clear()
	client.audio_director.gameplay_track_paths.append("res://assets/audio/music/gameplay/Heavy Electronic Edge Main.wav")
	client.audio_director.current_gameplay_track = 0
	client.audio_director.current_context = &"gameplay"
	client._set_scoreboard_open(true)
	await _capture(client, "scoreboard")
	var scoreboard_cards := client.scoreboard_rows_container.find_child("ScoreboardBuildCards", true, false) as HFlowContainer
	await _capture_card_hover(client, scoreboard_cards.get_child(1) as Button, "scoreboard_card_hover")
	client._set_scoreboard_open(false)

	client.network_world._on_snapshot({"server_tick": 240, "acknowledged_input": 12, "states": [
		{"peer_id": 2, "position": Vector2(420.0, 340.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 0.0, "shield": 0.0, "ammunition": 0, "alive": false, "shielding": false},
		{"peer_id": 3, "position": Vector2(980.0, 520.0), "velocity": Vector2.ZERO, "aim_angle": PI, "health": 100.0, "shield": 80.0, "ammunition": 7, "alive": true, "shielding": false},
	]})
	client.latest_match_payload["alive_peer_ids"] = [3]
	await _capture(client, "spectator")
	client._toggle_pause_overlay()
	await _capture(client, "pause")
	client._hide_pause_overlay()

	client.latest_match_payload = {
		"state_name": "MATCH_RESULT", "round_number": 3, "heat_number": 2,
		"deadline_tick": -1, "match_winner": 2, "match_winner_team": 1, "alive_peer_ids": [2, 4],
		"map_id": &"relay_zero", "map_name": "Relay Zero",
		"game_mode": GameModeRules.Mode.TEAM_DEATH_MATCH,
		"teams": {2: 1, 3: 2, 4: 1, 5: 2},
		"participant_peer_ids": [2, 3, 4, 5],
		"scores": {
			2: {"heat_wins": 0, "round_wins": 3},
			3: {"heat_wins": 1, "round_wins": 1},
			4: {"heat_wins": 0, "round_wins": 1},
			5: {"heat_wins": 1, "round_wins": 0},
		},
		"builds": {
			2: {&"rapid_cycling": 2, &"twin_shot": 1, &"sunbeam_core": 1},
			3: {&"reinforced_hull": 2, &"ablative_shell": 1, &"scatter_array": 1},
			4: {&"flux_reservoir": 1, &"endless_belt": 2},
			5: {&"inertial_dampers": 1, &"hollow_points": 1, &"cycling_servo": 1},
		},
	}
	client.network_world.latest_server_tick = 500
	client._update_match_presentation()
	await _capture(client, "results")
	var result_cards := client.results_standings_container.find_child("FinalBuildCards", true, false) as HFlowContainer
	await _capture_card_hover(client, result_cards.get_child(1) as Button, "results_card_hover")

	client._on_rejected(&"SERVER_FULL", "The server is full.")
	await _capture(client, "error")
	root.remove_meta("ssf_presentation_capture_resolution")
	print("PRESENTATION_CAPTURE_OK=%s" % capture_label)
	quit(0)


func _capture(_client: Node, screen_name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image := root.get_texture().get_image()
	if image.get_size() != capture_resolution:
		printerr("PRESENTATION_CAPTURE_ERROR=%s:expected_%s:actual_%s" % [screen_name, capture_resolution, image.get_size()])
		quit(4)
		return
	var path := capture_directory.path_join("%s_%s.png" % [capture_label, screen_name])
	var result := image.save_png(path)
	if result != OK:
		printerr("PRESENTATION_CAPTURE_ERROR=%s:%d" % [screen_name, result])
		quit(3)


func _capture_card_hover(client: Node, button: Button, screen_name: String) -> void:
	var preview := button._make_custom_tooltip(button.tooltip_text) as Control
	client.connection_canvas.add_child(preview)
	var canvas_width := float(capture_resolution.x) * 1080.0 / float(capture_resolution.y)
	preview.position = Vector2(canvas_width * 0.5 - 195.0, 120.0)
	await _capture(client, screen_name)
	client.connection_canvas.remove_child(preview)
	preview.free()
