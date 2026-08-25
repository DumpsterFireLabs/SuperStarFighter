class_name PresentationSystemTests
extends RefCounted


static func run(context: TestContext, tree_parent: Node) -> void:
	_validate_audio_pipeline(context, tree_parent)
	_validate_visual_feedback(context)
	_validate_production_screens(context, tree_parent)


static func _validate_audio_pipeline(context: TestContext, tree_parent: Node) -> void:
	var audio := AudioDirector.new()
	tree_parent.add_child(audio)
	context.expect_equal(audio.sfx_streams.size(), AudioDirector.SFX_NAMES.size(), "audio director provides every required combat cue")
	context.expect_equal(audio.synthesized_placeholder_count(), AudioDirector.SFX_NAMES.size(), "missing authored SFX receive synthesized placeholders")
	context.expect_true(FileAccess.file_exists("res://assets/audio/README.md"), "audio drop-in contract is documented beside the asset paths")
	if FileAccess.file_exists("res://assets/audio/music/main_menu.mp3.wav"):
		context.expect_true(audio.menu_player.stream != null, "authored menu music with a compound filename is discovered")
		context.expect_equal(audio.menu_crossfade_player.stream, audio.menu_player.stream, "menu music is prepared on two players for a seamless crossfade")
		if audio.menu_player.stream is AudioStreamWAV:
			context.expect_equal((audio.menu_player.stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED, "menu WAV avoids an abrupt literal end-to-start loop")
		audio._begin_menu_crossfade()
		audio._step_menu_crossfade(AudioDirector.MENU_CROSSFADE_SECONDS * 0.5)
		context.expect_approx(audio.menu_player.volume_db, -3.0103, "menu fade tail uses an equal-power outgoing curve", 0.001)
		context.expect_approx(audio.menu_crossfade_player.volume_db, -3.0103, "menu restart uses an equal-power incoming curve", 0.001)
		audio._stop_menu_music()
	var expected_gameplay_tracks := _supported_audio_file_count(AudioDirector.GAMEPLAY_MUSIC_DIRECTORY)
	context.expect_equal(audio.gameplay_tracks.size(), expected_gameplay_tracks, "all authored gameplay tracks are discovered")
	context.expect_true(audio.win_player.stream != null, "win music always has an authored or generated stream")
	audio.play_sfx(&"card_lock", "same-card")
	audio.play_sfx(&"card_lock", "same-card")
	context.expect_equal(audio._played_keys.size(), 1, "repeated reliable events cannot replay the same sound")
	audio.set_context(&"menu")
	context.expect_equal(audio.current_context, &"menu", "menu music context selects the authored stream")
	audio.set_context(&"gameplay")
	context.expect_equal(audio.current_context, &"gameplay", "gameplay playlist context works when optional tracks are absent")
	tree_parent.remove_child(audio)
	audio.free()


static func _supported_audio_file_count(directory_path: String) -> int:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return 0
	var count := 0
	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			count += 1
	return count


static func _validate_visual_feedback(context: TestContext) -> void:
	var ship := SandboxShip.new()
	ship.setup(7, CombatStats.create_base(), Vector2(300.0, 400.0), Color("ff4f78"), true, "Neon Ace")
	context.expect_equal(ship.display_name, "Neon Ace", "ship presentation retains its public nameplate")
	context.expect_equal(ship.identity_pattern, 1, "ship identity includes a stable non-color pattern")
	ship.flash_damage()
	ship.flash_shield_block()
	context.expect_true(ship.damage_flash_remaining > 0.0, "damage has a distinct ship flash")
	context.expect_true(ship.shield_flash_remaining > 0.0, "shield block has a distinct ship flash")
	ship.set_eliminated()
	context.expect_true(ship.elimination_pulse_remaining > 0.0, "elimination has a distinct pulse")
	ship.free()

	var effects := CombatEffectsLayer.new()
	effects.spawn_impact(Vector2.ONE)
	effects.spawn_damage(Vector2.ONE, Vector2.RIGHT)
	effects.spawn_elimination(Vector2.ONE, Color.WHITE)
	context.expect_equal(effects.effects.size(), 3, "impact, damage direction, and elimination effects coexist")
	effects.clear_effects()
	context.expect_empty(effects.effects, "presentation effects clear between heats")
	effects.free()

	var view := NetworkWorldView.new()
	view.local_peer_id = 1
	var local_ship := SandboxShip.new()
	local_ship.setup(1, CombatStats.create_base(), Vector2(100.0, 100.0), Color.WHITE, true, "Local")
	view.ships[1] = local_ship
	var projectile := ProjectileState.create(50, 2, 1, Vector2(900.0, 100.0), PI, CombatStats.create_base())
	view.authoritative_projectiles.add(projectile)
	context.expect_equal(view.nearest_incoming_offscreen_projectile(), projectile, "nearest incoming projectile is selected for a shape indicator")
	view.camera = Camera2D.new()
	view.trigger_camera_shake(5.0, 0.2)
	context.expect_true(view.camera_shake_remaining > 0.0, "local damage can trigger restrained presentation-only camera shake")
	var feedback_events: Array[StringName] = []
	view.presentation_event.connect(func(event_name: StringName, _payload: Dictionary) -> void: feedback_events.append(event_name))
	view.latest_server_tick = 20
	view._handle_snapshot_feedback(1, {"health": 100.0, "shield": 100.0, "shielding": true, "alive": true, "ammunition": 2, "position": Vector2(100.0, 100.0), "velocity": Vector2.ZERO, "aim_angle": 0.0}, local_ship)
	view.latest_server_tick = 21
	view._handle_snapshot_feedback(1, {"health": 75.0, "shield": 20.0, "shielding": false, "alive": true, "ammunition": 8, "position": Vector2(100.0, 100.0), "velocity": Vector2.ZERO, "aim_angle": 0.0}, local_ship)
	context.expect_true(&"damage" in feedback_events, "snapshot deltas emit damage feedback once")
	context.expect_true(&"shield_break" in feedback_events, "snapshot deltas distinguish shield breaks")
	context.expect_true(&"reload" in feedback_events, "snapshot deltas distinguish reload completion")
	context.expect_true(local_ship.z_index > 0, "ships render above arena geometry")
	local_ship.free()
	view.camera.free()
	view.free()


static func _validate_production_screens(context: TestContext, tree_parent: Node) -> void:
	var packed_scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := packed_scene.instantiate()
	tree_parent.add_child(client)
	context.expect_true(client.connection_screen != null, "production connection screen exists")
	context.expect_true(client.lobby_panel != null, "production lobby screen exists")
	context.expect_true(client.draft_panel != null, "production draft screen exists")
	context.expect_true(client.network_world.hud_panel != null, "production combat HUD exists")
	context.expect_true(client.network_world.match_status_label != null, "match timing and state integrate into the combat HUD")
	context.expect_true(client.network_world.hud_panel.custom_minimum_size.x < 520.0 and client.network_world.hud_panel.custom_minimum_size.y < 190.0, "upper-left combat HUD uses the compact footprint")
	context.expect_true(client.network_world.spectator_label != null, "production spectator banner exists")
	context.expect_false(client.offline_sandbox.camera.enabled, "inactive offline camera cannot steal the online viewport")
	context.expect_true(client.scoreboard_panel != null, "production scoreboard exists")
	context.expect_true(client.results_panel != null, "production results screen exists")
	context.expect_true(client.results_winner_label != null and client.results_standings_container != null, "victory screen uses a structured champion and standings composition")
	context.expect_true(client.pause_overlay != null, "non-pausing online pilot menu exists")
	context.expect_true(client.settings_panel != null, "shared display and audio settings screen exists")
	context.expect_equal(client.resolution_control.item_count, client.RESOLUTION_OPTIONS.size(), "settings exposes every supported resolution")
	context.expect_true(Vector2i(2560, 1080) in client.RESOLUTION_OPTIONS and Vector2i(3440, 1440) in client.RESOLUTION_OPTIONS, "settings includes both ultrawide resolutions")
	context.expect_equal(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand", "ultrawide windows reveal space without nonuniform stretching")
	context.expect_true(client.splash_screen != null, "animated splash screen exists")
	context.expect_approx(client.SPLASH_AUTO_ADVANCE_SECONDS, 10.0, "splash declares a ten-second automatic advance")
	var start_event := InputEventKey.new()
	start_event.keycode = KEY_ENTER
	start_event.pressed = true
	client._input(start_event)
	context.expect_true(client.splash_dismissed, "any key advances the splash immediately")
	client.splash_screen.visible = false
	context.expect_true(client.win_overlay != null, "dedicated victory screen exists")
	context.expect_true(client.draft_panel.custom_minimum_size.x <= 1280.0 and client.draft_panel.custom_minimum_size.y <= 720.0, "five-card draft fits the 1280x720 acceptance viewport")
	context.expect_true(client.results_panel.custom_minimum_size.x <= 1280.0 and client.results_panel.custom_minimum_size.y <= 720.0, "results screen fits the 1280x720 acceptance viewport")
	var players: Array[Dictionary] = []
	for index in 32:
		players.append({"peer_id": index + 2, "display_name": "Pilot %02d" % (index + 1), "spectator": false, "is_npc": false, "ready": true})
	client.bridge.local_peer_id = 2
	client._on_connected(2)
	client.network_world._on_connected(2)
	client._on_lobby_state({"players": players, "leader_id": 2, "player_limit": 32, "server_capacity": 32, "npc_count": 0, "ready_human_count": 32, "all_humans_ready": true, "npcs_enabled": false, "match_active": false, "rounds_to_win": 3})
	context.expect_equal(client.lobby_roster.get_child_count(), 32, "scrollable lobby roster renders all 32 participants")
	context.expect_true(client.lobby_roster.get_parent() is ScrollContainer, "32-player lobby roster is scrollable")
	context.expect_true(client.connection_screen.visible and not client.connection_form_panel.visible, "waiting lobby uses the centered menu backdrop instead of the connect form")
	context.expect_false(client.network_world.visible, "arena remains hidden while players wait in the lobby")
	context.expect_equal(client.network_world.local_peer_id, 2, "hidden lobby preserves the connected renderer's local identity")
	context.expect_equal(client.lobby_roster.get_child(1).get_child_count(), 4, "leader receives an eject control for another human")
	context.expect_false(client.start_button.disabled, "leader can launch once all humans are ready")
	context.expect_equal(client.start_button.text, "Start Match", "ready multiplayer lobby uses ordinary start wording")
	var solo_player: Array[Dictionary] = [{"peer_id": 2, "display_name": "Pilot 01", "spectator": false, "is_npc": false, "ready": true}]
	client._on_lobby_state({"players": solo_player, "leader_id": 2, "player_limit": 4, "server_capacity": 32, "npc_count": 0, "ready_human_count": 1, "all_humans_ready": true, "npcs_enabled": false, "match_active": false, "rounds_to_win": 3})
	context.expect_true(client.start_button.disabled and client.start_button.text == "Enable NPCs to Start Solo", "solo human is directed to enable NPCs")
	client._on_lobby_state({"players": solo_player, "leader_id": 2, "player_limit": 4, "server_capacity": 32, "npc_count": 0, "ready_human_count": 1, "all_humans_ready": true, "npcs_enabled": true, "match_active": false, "rounds_to_win": 3})
	context.expect_false(client.start_button.disabled, "ready solo human may start after enabling NPCs")
	context.expect_equal(client.start_button.text, "Start Match with NPCs", "solo NPC launch uses descriptive wording")
	client._on_match_event(&"STATE_CHANGED", 0, {"state_name": "DRAFT", "round_number": 1, "heat_number": 0, "builds": {2: {}}})
	context.expect_true(client.network_world.visible and client.network_world.process_mode != Node.PROCESS_MODE_DISABLED, "match start reactivates world rendering and prediction")
	context.expect_equal(client.network_world.local_peer_id, 2, "match start retains local identity for movement and predicted shots")
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "deadline_tick": 900, "overtime_start_tick": 3600, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {}, "builds": {}, "round_number": 2, "heat_number": 3}
	client.network_world.latest_server_tick = 300
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	context.expect_false(client.match_panel.visible, "former top-center match banner stays hidden during combat")
	context.expect_true(client.network_world.match_status_label.text.contains("ACTIVE HEAT") and client.network_world.match_status_label.text.contains("R2 H3"), "compact upper-left HUD carries match state and round details")
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.physical_keycode = KEY_TAB
	tab_event.pressed = true
	client._input(tab_event)
	context.expect_true(client.scoreboard_panel.visible, "Tab opens the live scoreboard without relying on UI focus")
	context.expect_equal(client.scoreboard_rows_container.get_child_count(), 2, "scoreboard renders one structured row per match participant")
	context.expect_true(client.scoreboard_rows_container.get_child(0).get_meta("peer_id") in [2, 3], "scoreboard rows retain player identity")
	client._input(tab_event)
	context.expect_false(client.scoreboard_panel.visible, "pressing Tab again returns to combat")
	client.latest_match_payload = {"state_name": "MATCH_RESULT", "match_winner": 2, "deadline_tick": 600, "participant_peer_ids": [2], "scores": {2: {"heat_wins": 0, "round_wins": 1}}, "builds": {2: {}}, "round_number": 1, "heat_number": 2}
	client.network_world.latest_server_tick = 300
	client._update_match_presentation()
	context.expect_true(client.win_overlay.visible and client.results_panel.visible, "match result opens the dedicated final standings screen")
	context.expect_true(client.results_label.text.contains("VICTORY"), "results screen clearly identifies the winner")
	context.expect_equal(client.results_standings_container.get_child_count(), 1, "structured standings renders one row per participant")
	context.expect_equal(client.results_standings_container.get_child(0).get_meta("peer_id"), 2, "winner occupies the first highlighted standings row")
	context.expect_true(client.results_winner_label.text.contains(client._player_name(2).to_upper()), "champion plate names the winner independently of the standings table")
	context.expect_false(client.lobby_panel.visible, "lobby menu remains hidden throughout the game loop")
	client.connection_screen.visible = false
	client._toggle_pause_overlay()
	context.expect_true(client.pause_overlay.visible and client.network_world.input_blocked, "Escape overlay blocks local combat input without pausing the server")
	client._hide_pause_overlay()
	client._on_rejected(&"SERVER_FULL", "The server is full.")
	context.expect_true(client.connection_screen.visible and client.connection_status.text.contains("try again"), "connection rejection returns to a usable recovery screen")
	tree_parent.remove_child(client)
	client.free()
