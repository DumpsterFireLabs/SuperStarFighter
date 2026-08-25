extends SceneTree

var capture_directory: String = ""
var capture_label: String = "capture"


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
	DirAccess.make_dir_recursive_absolute(capture_directory)
	_capture_sequence.call_deferred()


func _capture_sequence() -> void:
	var packed_scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := packed_scene.instantiate()
	root.add_child(client)
	await process_frame
	await process_frame
	await _capture(client, "splash")
	client._dismiss_splash(true)
	await _capture(client, "menu")
	client._show_settings(false)
	await _capture(client, "settings")
	client._hide_settings()

	var players: Array[Dictionary] = []
	for index in 32:
		players.append({"peer_id": index + 2, "display_name": "Pilot %02d" % (index + 1), "spectator": false, "is_npc": index >= 8})
	client.bridge.local_peer_id = 2
	client.connection_screen.visible = false
	client.lobby_panel.visible = true
	client.network_world.set_network_active(true)
	client._on_lobby_state({"players": players, "leader_id": 2, "player_limit": 32, "server_capacity": 32, "npc_count": 24, "npcs_enabled": true, "match_active": false, "rounds_to_win": 3})
	await _capture(client, "lobby_32")

	client.lobby_panel.visible = false
	client.latest_match_payload = {"state_name": "DRAFT", "round_number": 1, "heat_number": 0, "deadline_tick": 1800, "builds": {2: {}}}
	client.network_world.latest_server_tick = 0
	client._show_draft_offer({"offer_token": "capture", "card_ids": [&"phase_thrusters", &"blink_capacitor", &"beam_emitter", &"prismatic_lance", &"zero_point_loader"], "deadline_tick": 1800})
	await _capture(client, "draft")

	client.draft_panel.visible = false
	client.match_panel.visible = true
	client.network_world.local_peer_id = 2
	client.network_world._on_snapshot({"server_tick": 200, "acknowledged_input": 10, "states": [
		{"peer_id": 2, "position": Vector2(420.0, 340.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 78.0, "shield": 64.0, "ammunition": 5, "alive": true, "shielding": false},
		{"peer_id": 3, "position": Vector2(980.0, 520.0), "velocity": Vector2.ZERO, "aim_angle": PI, "health": 100.0, "shield": 100.0, "ammunition": 8, "alive": true, "shielding": true},
	]})
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "round_number": 2, "heat_number": 3, "deadline_tick": -1, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {2: {"heat_wins": 1, "round_wins": 1}, 3: {"heat_wins": 0, "round_wins": 0}}, "builds": {2: {&"rapid_cycling": 2}, 3: {&"reinforced_hull": 1}}, "overtime_start_tick": 5600}
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	await _capture(client, "combat")

	client.network_world._on_snapshot({"server_tick": 240, "acknowledged_input": 12, "states": [
		{"peer_id": 2, "position": Vector2(420.0, 340.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 0.0, "shield": 0.0, "ammunition": 0, "alive": false, "shielding": false},
		{"peer_id": 3, "position": Vector2(980.0, 520.0), "velocity": Vector2.ZERO, "aim_angle": PI, "health": 100.0, "shield": 80.0, "ammunition": 7, "alive": true, "shielding": false},
	]})
	client.latest_match_payload["alive_peer_ids"] = [3]
	await _capture(client, "spectator")
	client._toggle_pause_overlay()
	await _capture(client, "pause")
	client._hide_pause_overlay()

	client.latest_match_payload = {"state_name": "MATCH_RESULT", "round_number": 3, "heat_number": 2, "deadline_tick": 800, "match_winner": 2, "alive_peer_ids": [2], "participant_peer_ids": [2, 3], "scores": {2: {"heat_wins": 0, "round_wins": 3}, 3: {"heat_wins": 0, "round_wins": 1}}, "builds": {2: {&"rapid_cycling": 2, &"twin_shot": 1}, 3: {&"reinforced_hull": 2}}}
	client.network_world.latest_server_tick = 500
	client._update_match_presentation()
	await _capture(client, "results")

	client._on_rejected(&"SERVER_FULL", "The server is full.")
	await _capture(client, "error")
	print("PRESENTATION_CAPTURE_OK=%s" % capture_label)
	quit(0)


func _capture(_client: Node, screen_name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image := root.get_texture().get_image()
	var path := capture_directory.path_join("%s_%s.png" % [capture_label, screen_name])
	var result := image.save_png(path)
	if result != OK:
		printerr("PRESENTATION_CAPTURE_ERROR=%s:%d" % [screen_name, result])
		quit(3)
