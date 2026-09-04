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
	client.connection_controller.host_preset_control.select(2)
	client.connection_controller.host_preset_control.item_selected.emit(2)
	await _capture(client, "host_preset")
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
	client.settings_tabs.current_tab = 2
	await _capture(client, "accessibility_settings")
	client.accessibility_preferences.set_values({"high_contrast": true, "toggle_fire": true, "toggle_shield": true})
	client._apply_accessibility_settings()
	client.settings_controller.high_contrast_control.set_pressed_no_signal(true)
	client.settings_controller.toggle_fire_control.set_pressed_no_signal(true)
	client.settings_controller.toggle_shield_control.set_pressed_no_signal(true)
	client.settings_controller.toggle_shield_control.grab_focus()
	await process_frame
	await _capture(client, "accessibility_contrast")
	client.accessibility_preferences.set_values({"high_contrast": false, "toggle_fire": false, "toggle_shield": false})
	client._apply_accessibility_settings()
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.KEYBOARD_MOUSE, false)
	client.settings_tabs.current_tab = 0
	client.current_window_mode = client.WindowModeOption.WINDOWED
	client.current_resolution = capture_resolution
	client._update_resolution_control_state()
	client._hide_settings()
	client._play_offline()
	await _capture(client, "build_lab")
	var lab_tabs := client.offline_sandbox.lab_panel.find_child("LabTabs", true, false) as TabContainer
	lab_tabs.current_tab = 1
	await _capture(client, "build_lab_targets")
	lab_tabs.current_tab = 0
	client.offline_sandbox.apply_accessibility_settings({"hud_scale": 1.5, "reduced_shake": true, "reduced_flashes": true, "constrain_hud": true})
	await _capture(client, "build_lab_scaled")
	client.offline_sandbox.apply_accessibility_settings({"hud_scale": 1.0, "reduced_shake": false, "reduced_flashes": false, "constrain_hud": true})
	client._play_tutorial()
	await _capture(client, "tutorial_movement")
	client.offline_sandbox.tutorial._enter_step(4)
	await _capture(client, "tutorial_guard")
	client.offline_sandbox.apply_accessibility_settings({"hud_scale": 1.5, "reduced_shake": true, "reduced_flashes": true, "constrain_hud": true})
	await _capture(client, "tutorial_scaled")
	client.offline_sandbox.tutorial._enter_step(6)
	await _capture(client, "tutorial_draft")
	client.offline_sandbox.stop_tutorial()
	client.offline_sandbox.apply_accessibility_settings({"hud_scale": 1.0, "reduced_shake": false, "reduced_flashes": false, "constrain_hud": true})
	client.offline_sandbox.set_target_settings(5, 100, 420, false, false, false)
	client.offline_sandbox.set_editor_open(false)
	var offline_damage_events: Array[Dictionary] = [
		{"projectile_id": 701, "attacker_id": 1, "target_id": 2, "damage": 10_000.0},
		{"projectile_id": 702, "attacker_id": 1, "target_id": 3, "damage": 10_000.0},
		{"projectile_id": 703, "target_id": 4, "damage": 10_000.0},
	]
	client.offline_sandbox._apply_damage_events(offline_damage_events)
	await _capture(client, "offline_combat")
	client.offline_sandbox._reset_combatants()
	client._show_connection_screen("Ready to connect.")

	var players: Array[Dictionary] = []
	for index in 32:
		players.append({"peer_id": index + 2, "display_name": "Pilot %02d" % (index + 1), "ship_color": ServerLobby.RANDOM_SHIP_COLORS[index % ServerLobby.RANDOM_SHIP_COLORS.size()], "ship_pattern": SHIP_PATTERNS[(index + 3) % SHIP_PATTERNS.size()], "spectator": false, "is_npc": index >= 8, "npc_difficulty": index % NpcPilotController.DIFFICULTY_NAMES.size(), "ready": index != 5, "team_id": 1 + index % 4, "team_selection": 0})
	client.bridge.local_peer_id = 2
	client._on_lobby_state({"players": players, "leader_id": 2, "player_limit": 32, "server_capacity": 32, "npc_count": 24, "ready_human_count": 7, "all_humans_ready": false, "npcs_enabled": true, "random_spawn_powerups": true, "match_active": false, "rounds_to_win": 3, "game_mode": GameModeRules.Mode.TEAM_DEATH_MATCH, "team_count": 4, "team_setup_valid": true, "team_setup_error": ""})
	await _capture(client, "lobby_32")
	client.lobby_settings_button.pressed.emit()
	await _capture(client, "lobby_settings")
	client._hide_settings()
	var local_color_swatch: Button
	for row in client.lobby_roster.get_children():
		var candidate := row.get_node_or_null("ShipColor") as Button
		if candidate != null and not candidate.disabled:
			local_color_swatch = candidate
			break
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
	client.latest_match_payload["builds"] = {2: {&"twin_shot": 5, &"heavy_rounds": 2}}
	client._show_draft_offer({"offer_token": "capture-cap", "card_ids": [&"twin_shot", &"phase_thrusters", &"beam_emitter", &"prismatic_lance", &"zero_point_loader"], "deadline_tick": 1800})
	await _capture(client, "draft_capped")
	await _capture_card_hover(client, client.draft_buttons[0] as Button, "draft_capped_hover")
	client._select_draft_card(0)
	await _capture(client, "draft_confirmation")
	client._cancel_draft_confirmation()
	client.latest_match_payload["draft_bye_peer_id"] = 2
	client._show_draft_bye(1800)
	client._update_match_presentation()
	await _capture(client, "draft_bye")
	client.draft_panel.visible = false
	client.draft_bye_label.visible = false
	client.latest_match_payload = {"state_name": "COUNTDOWN", "entered_tick": 100, "deadline_tick": 280, "round_number": 1, "heat_number": 1, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {}, "builds": {2: {}, 3: {}}, "map_id": &"solar_tide", "map_name": "Solar Tide"}
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
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "entered_tick": 100, "round_number": 2, "heat_number": 3, "deadline_tick": -1, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "players": [{"peer_id": 2, "display_name": "Pilot 01", "ship_color": ServerLobby.RANDOM_SHIP_COLORS[0], "ship_pattern": "chevron"}, {"peer_id": 3, "display_name": "Pilot 02", "ship_color": ServerLobby.RANDOM_SHIP_COLORS[1], "ship_pattern": "racing"}, {"peer_id": 4, "display_name": "Star Hunter", "ship_color": ServerLobby.RANDOM_SHIP_COLORS[2], "ship_pattern": "zebra"}, {"peer_id": 5, "display_name": "Void Runner", "ship_color": ServerLobby.RANDOM_SHIP_COLORS[3], "ship_pattern": "checkerboard"}], "scores": {2: {"heat_wins": 1, "round_wins": 1}, 3: {"heat_wins": 0, "round_wins": 0}}, "builds": {2: {&"rapid_cycling": 2}, 3: {&"reinforced_hull": 1}}, "powerups": [{"powerup_id": 1, "card_id": &"kinetic_prow", "position": Vector2(700.0, 430.0), "rarity": CardDefinition.Rarity.RARE}], "random_spawn_powerups": true, "overtime_start_tick": 5600, "game_mode": GameModeRules.Mode.KING_OF_THE_HILL, "teams": {2: 1, 3: 2}, "objective": {"active": true, "mode": GameModeRules.Mode.KING_OF_THE_HILL, "position": Vector2(700.0, 430.0), "zone_radius": GameModeRules.OBJECTIVE_ZONE_RADIUS, "controller_id": 2, "progress": {2: 12.5}, "target_seconds": GameModeRules.HILL_HOLD_SECONDS}}
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	client.network_world.add_kill_feed_entries([
		{"killer_id": 2, "victim_id": 3, "reason": "combat"},
		{"killer_id": 0, "victim_id": 4, "reason": "environment"},
		{"killer_id": 0, "victim_id": 5, "reason": "disconnect"},
	], 201)
	await _capture(client, "combat")
	var expanded_size := root.get_visible_rect().size
	client.latest_match_payload["competitive_view"] = true
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	await process_frame
	await process_frame
	var competitive_size := root.get_visible_rect().size
	if not competitive_size.is_equal_approx(Vector2(1920, 1080)):
		printerr("PRESENTATION_CAPTURE_ERROR=competitive_world_extent:%s" % competitive_size)
		quit(5)
		return
	print("COMPETITIVE_VIEW_EVIDENCE physical=%s expanded=%s competitive=%s" % [capture_resolution, expanded_size, competitive_size])
	await _capture(client, "competitive_combat")
	client.latest_match_payload["competitive_view"] = false
	client.network_world.apply_match_state(client.latest_match_payload)
	await process_frame
	if not root.get_visible_rect().size.is_equal_approx(expanded_size):
		printerr("PRESENTATION_CAPTURE_ERROR=competitive_restore")
		quit(5)
		return
	client._update_match_presentation()
	var previous_combat_payload := client.latest_match_payload.duplicate(true) as Dictionary
	client.network_world.set_physics_process(false)
	client.latest_match_payload["game_mode"] = GameModeRules.Mode.TEAM_DEATH_MATCH
	client.latest_match_payload["game_mode_name"] = "Team Death Match"
	client.latest_match_payload["teams"] = {2: 1, 3: 2, 4: 1, 5: 8}
	client.latest_match_payload["objective"] = {}
	client.latest_match_payload["overtime_start_tick"] = 150
	client.latest_match_payload["heat_end_tick"] = 2000
	client.latest_match_payload["alive_peer_ids"] = [2, 3, 4, 5]
	for player in client.latest_match_payload["players"]:
		player["ship_color"] = "42e8ff"
	client.network_world.apply_match_state(client.latest_match_payload)
	var team_states: Array[Dictionary] = []
	var positions := {2: Vector2(420, 340), 3: Vector2(730, 350), 4: Vector2(560, 570), 5: Vector2(520, 1120)}
	for peer in [2, 3, 4, 5]:
		team_states.append({"peer_id": peer, "position": positions[peer], "velocity": Vector2.ZERO, "aim_angle": 0.0 if peer in [2, 4] else PI, "health": 100.0, "shield": 100.0, "ammunition": 8, "alive": true, "shielding": true})
	client.network_world._on_snapshot({"server_tick": 200, "acknowledged_input": 10, "states": team_states})
	for state in team_states:
		(client.network_world.ships[int(state.peer_id)] as CombatShipView).global_position = state.position
	var team_registry := client.network_world.authoritative_projectiles as ProjectileRegistry
	for id in range(1, 9):
		var owner := 4 if id % 2 == 0 else 3
		team_registry.add(ProjectileState.create(9000 + id, owner, id, Vector2(550 + id * 24, 420), 0.0, CombatStats.create_base()))
	team_registry.add(ProjectileState.create_mine(9010, 4, Vector2(570, 250)))
	team_registry.add(ProjectileState.create_mine(9011, 3, Vector2(750, 550)))
	client.network_world.projectile_layer.queue_redraw()
	client.network_world.indicator_layer.queue_redraw()
	client._update_match_presentation()
	await _capture(client, "team_combat")
	client.network_world.apply_builds({2: {&"afterburner": 1, &"mine_layer": 1, &"hunter_missiles": 1, &"cloak": 1}})
	client.network_world.selected_special_slot = 2
	client.network_world.local_mine_charges_remaining = 8
	client.network_world.local_missile_charges_remaining = 18
	client.network_world.local_cloak_charges_remaining = 1
	client.network_world._update_diagnostics()
	await _capture(client, "ability_selection")
	client.network_world.apply_accessibility_settings({"hud_scale": 1.5, "reduced_shake": true, "reduced_flashes": true, "constrain_hud": true})
	await _capture(client, "combat_accessibility")
	client.accessibility_preferences.set_values({"hud_scale": 1.5, "high_contrast": true, "reduced_flashes": true, "toggle_fire": true, "toggle_shield": true})
	client._apply_accessibility_settings()
	client.network_world.action_latch.active = {&"fire": true, &"shield": false}
	client.network_world._update_diagnostics()
	await _capture(client, "combat_contrast")
	client.accessibility_preferences.set_values({"hud_scale": 1.0, "high_contrast": false, "reduced_flashes": false, "toggle_fire": false, "toggle_shield": false})
	client._apply_accessibility_settings()
	client.network_world.apply_accessibility_settings({"hud_scale": 1.0, "reduced_shake": false, "reduced_flashes": false, "constrain_hud": true})
	client._on_match_event(&"COMBAT_FEEDBACK", 201, {"hit_count": 3, "hit_damage": 68, "blocked_count": 1, "last_block_reason": "perfect_guard"})
	await _capture(client, "hit_confirmation")
	client._on_match_event(&"COMBAT_FEEDBACK", 202, {"death": {"killer_id": 3, "source": "missile", "mechanic": "outside_shield_arc", "damage": 34, "life_generation": 1}})
	await _capture(client, "death_recap")
	client.network_world.apply_accessibility_settings({"hud_scale": 1.5, "reduced_shake": true, "reduced_flashes": true, "constrain_hud": true})
	await _capture(client, "death_recap_scaled")
	client.network_world.apply_accessibility_settings({"hud_scale": 1.0, "reduced_shake": false, "reduced_flashes": false, "constrain_hud": true})
	client.network_world.combat_feedback_panel.clear_feedback()
	client.network_world.apply_builds(client.latest_match_payload.get("builds", {}))
	client.latest_match_payload["game_mode"] = GameModeRules.Mode.CAPTURE_THE_FLAG
	client.latest_match_payload["game_mode_name"] = "Capture the Flag"
	client.latest_match_payload["objective"] = {"active": true, "mode": GameModeRules.Mode.CAPTURE_THE_FLAG, "flag_position": Vector2(3000, 1600), "flag_carrier_id": 3, "capture_zones": {2: Vector2(2800, 1600), 3: Vector2(180, 300)}}
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	await _capture(client, "flag_navigation")
	client.latest_match_payload["objective"]["flag_carrier_id"] = 2
	client.network_world.apply_match_state(client.latest_match_payload)
	await _capture(client, "flag_return")
	client.latest_match_payload["game_mode"] = GameModeRules.Mode.KING_OF_THE_HILL
	client.latest_match_payload["game_mode_name"] = "King of the Hill"
	client.latest_match_payload["objective"] = {"active": true, "mode": GameModeRules.Mode.KING_OF_THE_HILL, "position": Vector2(700, 430), "controller_id": 3, "progress": {3: 12.5}, "target_seconds": 20.0}
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	await _capture(client, "hill_enemy")
	client.latest_match_payload["objective"]["controller_id"] = 0
	client.latest_match_payload["objective"]["contested"] = true
	client.network_world.apply_match_state(client.latest_match_payload)
	await _capture(client, "hill_contested")
	client.latest_match_payload = previous_combat_payload
	client.network_world.apply_match_state(previous_combat_payload)
	team_states.resize(2)
	team_states[1]["position"] = Vector2(980, 520)
	client.network_world._on_snapshot({"server_tick": 200, "acknowledged_input": 10, "states": team_states})
	for state in team_states:
		(client.network_world.ships[int(state.peer_id)] as CombatShipView).global_position = state.position
	for id in range(9001, 9012):
		team_registry.remove(id)
	client.network_world.projectile_layer.queue_redraw()
	client.network_world.set_physics_process(false)
	var afterburner_ship := client.network_world.ships[2] as CombatShipView
	var before_afterburner_position := afterburner_ship.global_position
	afterburner_ship.combatant.aim_angle = -0.18
	afterburner_ship.combatant.velocity = Vector2(360.0, 190.0)
	afterburner_ship.set_thrust_input(MovementSystem.world_to_ship_relative(Vector2.UP, afterburner_ship.combatant.aim_angle))
	afterburner_ship.flash_afterburner(0.55)
	for echo_index in 4:
		afterburner_ship.global_position += Vector2(11.0, 6.0)
		afterburner_ship._process(CombatShipView.AFTERBURNER_ECHO_INTERVAL_SECONDS)
	await _capture(client, "afterburner")
	afterburner_ship.global_position = before_afterburner_position
	afterburner_ship.afterburner_bloom_remaining = 0.0
	afterburner_ship.afterburner_ignition_remaining = 0.0
	afterburner_ship.afterburner_echoes.clear()
	afterburner_ship.set_thrust_input(Vector2.ZERO)
	client.network_world.set_physics_process(true)
	client.network_world.effects_layer.spawn_mine_explosion(Vector2(760.0, 300.0))
	client.network_world.effects_layer._process(CombatEffectsLayer.MINE_EFFECT_DELAY + 0.08)
	await _capture(client, "mine_explosion")
	client.network_world.effects_layer.clear_effects()
	for map_id in ArenaLayout.map_ids():
		client.latest_match_payload["map_id"] = map_id
		client.latest_match_payload["map_name"] = ArenaLayout.display_name(map_id)
		client.network_world.apply_match_state(client.latest_match_payload)
		client._update_match_presentation()
		await _capture(client, "map_%s" % map_id)
	client.latest_match_payload["map_id"] = &"solar_tide"
	client.latest_match_payload["map_name"] = ArenaLayout.display_name(&"solar_tide")
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	client.network_world.set_physics_process(false)
	client.network_world.camera.position = ArenaLayout.center(&"solar_tide")
	client.accessibility_preferences.set_values({"high_contrast": true})
	client._apply_accessibility_settings()
	await _capture(client, "map_solar_tide_contrast")
	client.accessibility_preferences.set_values({"high_contrast": false})
	client._apply_accessibility_settings()
	client.network_world.set_physics_process(true)
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
	client.audio_director.gameplay_track_paths.append("res://assets/audio/music/gameplay/Edge.ogg")
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

	client.latest_match_payload["game_mode"] = GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG
	client._results_rows_dirty = true
	client.latest_match_payload["objective_contributions"] = {2: {"flag_captures": 3, "carrier_stops": 2, "flag_carry_seconds": 46.5}, 3: {"flag_captures": 1, "carrier_stops": 1, "flag_carry_seconds": 28.0}, 4: {"flag_captures": 0, "carrier_stops": 4, "flag_carry_seconds": 19.0}}
	client._update_match_presentation()
	await _capture(client, "objective_results")
	await _capture_crowded_combat(client)
	await _capture_ship_families(client)
	client._on_rejected(&"SERVER_FULL", "The server is full.")
	await _capture(client, "error")
	root.remove_meta("ssf_presentation_capture_resolution")
	print("PRESENTATION_CAPTURE_OK=%s" % capture_label)
	quit(0)


func _capture_crowded_combat(client: Node) -> void:
	client._show_connection_screen("Stress capture")
	client.connection_screen.hide()
	client.bridge.local_peer_id = 2
	client.network_world.set_network_active(true)
	client.network_world.set_physics_process(false)
	var view := client.network_world as NetworkWorldView
	view.local_peer_id = 2
	var states: Array[Dictionary] = []
	var players: Array[Dictionary] = []
	var ids: Array[int] = []
	var teams: Dictionary = {}
	var builds: Dictionary = {}
	for index in 32:
		var peer := index + 2
		ids.append(peer)
		teams[peer] = 1 + index % 2
		builds[peer] = {&"afterburner": 1, &"mine_layer": 1, &"hunter_missiles": 1, &"rebound_shields": 1}
		players.append({"peer_id": peer, "display_name": "Pilot %02d" % peer, "ship_color": ServerLobby.RANDOM_SHIP_COLORS[index % ServerLobby.RANDOM_SHIP_COLORS.size()], "ship_pattern": SHIP_PATTERNS[index % SHIP_PATTERNS.size()]})
		var position := Vector2(930 + (index % 8) * 190, 550 + (index / 8) * 210)
		if index == 0:
			position = Vector2(1600, 900)
		states.append({"peer_id": peer, "position": position, "velocity": Vector2.ZERO, "aim_angle": index * 0.6, "health": 100, "shield": 100, "ammunition": 8, "alive": true, "shielding": index % 2 == 0, "afterburner_active": index % 3 == 0})
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "entered_tick": 0, "round_number": 1, "heat_number": 1, "deadline_tick": -1, "alive_peer_ids": ids, "participant_peer_ids": ids, "players": players, "scores": {}, "builds": builds, "teams": teams, "game_mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "game_mode_name": "Team Capture the Flag", "map_id": &"prism_array", "map_name": "Prism Array", "overtime_start_tick": 4000, "objective": {"active": true, "mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "flag_position": Vector2(1850, 950), "flag_carrier_id": 0, "capture_zones": {1: Vector2(1000, 500), 2: Vector2(2500, 1400)}}}
	view.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	view._on_snapshot({"server_tick": 300, "acknowledged_input": 0, "states": states})
	view._update_diagnostics()
	view.camera.position = Vector2(1600, 900)
	view.camera.reset_smoothing()
	view.authoritative_projectiles = ProjectileRegistry.new()
	view.projectile_layer.registry = view.authoritative_projectiles
	var stats := CombatStats.create_base()
	for index in 1024:
		var position := Vector2(720 + (index % 48) * 36, 470 + (index / 48) * 38)
		var owner := 2 + index / 32
		var projectile: ProjectileState
		if index % 16 == 0:
			projectile = ProjectileState.create_mine(index + 1, owner, position)
			projectile.mine_activation_remaining = 0.0
		elif index % 16 == 1:
			projectile = ProjectileState.create_missile(index + 1, owner, position, index * 0.3)
		else:
			projectile = ProjectileState.create(index + 1, owner, index, position, index * 0.3, stats)
			projectile.is_beam = index % 7 == 0
		view.authoritative_projectiles.add(projectile)
	view.projectile_layer.visible_world_rect = view._visible_world_rect()
	view.effects_layer.visible_world_rect = view._visible_world_rect()
	view.effects_layer.clear_effects()
	view.effects_layer.set_process(false)
	for index in 128:
		var position := Vector2(950 + index % 8 * 190, 600 + index % 4 * 160)
		view.effects_layer.spawn_impact(position)
		if index < 16:
			view.effects_layer.spawn_mine_explosion(position)
		if index < 32:
			view.effects_layer.spawn_rebound(position)
	view.effects_layer.spawn_damage(Vector2(1600, 900), Vector2.RIGHT, true)
	view.apply_combat_feedback({"hit_count": 3, "hit_damage": 60, "guard_count": 1, "last_guard_reason": "perfect_guard"})
	view.projectile_layer.queue_redraw()
	await _capture(client, "crowded_combat")
	var samples: Array[int] = []
	for sample in 36:
		await process_frame
		view.projectile_layer.queue_redraw()
		view.effects_layer.queue_redraw()
		var started := Time.get_ticks_usec()
		RenderingServer.force_draw(false)
		if sample >= 6:
			samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	print("SSF_CROWD_RENDER_RESULT resolution=%s draw_submit_p95_usec=%d active_projectiles=%d drawn_projectiles=%d effects=%d suppressed=%d" % [capture_label, samples[ceili(samples.size() * 0.95) - 1], view.authoritative_projectiles.size(), view.projectile_layer.last_drawn_projectiles, view.effects_layer.effects.size(), view.effects_layer.dropped_effect_count])
	view.apply_accessibility_settings({"hud_scale": 1.5, "reduced_shake": true, "reduced_flashes": true, "constrain_hud": true})
	await _capture(client, "crowded_combat_reduced")
	view.effects_layer.set_process(true)


func _capture(_client: Node, screen_name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image := root.get_texture().get_image()
	# KEEP renders only the fitted content; native window bars are outside this texture.
	var expected_size := Vector2i(preload("res://src/client/presentation/competitive_view_policy.gd").physical_content_rect(Vector2(capture_resolution)).size) if screen_name == "competitive_combat" else capture_resolution
	if image.get_size() != expected_size:
		printerr("PRESENTATION_CAPTURE_ERROR=%s:expected_%s:actual_%s" % [screen_name, expected_size, image.get_size()])
		quit(4)
		return
	var path := capture_directory.path_join("%s_%s.png" % [capture_label, screen_name])
	var result := image.save_png(path)
	if result != OK:
		printerr("PRESENTATION_CAPTURE_ERROR=%s:%d" % [screen_name, result])
		quit(3)


func _capture_card_hover(client: Node, button: Button, screen_name: String) -> void:
	button.grab_focus()
	var inspection_focus := root.gui_get_focus_owner()
	var inspect := InputEventKey.new()
	inspect.keycode = KEY_I
	inspect.physical_keycode = KEY_I
	inspect.pressed = true
	root.push_input(inspect)
	var opened_on_press: bool = client.card_inspector.visible
	inspect = inspect.duplicate()
	inspect.pressed = false
	root.push_input(inspect)
	await process_frame
	if not client.card_inspector.visible:
		printerr("PRESENTATION_CAPTURE_ERROR=card_inspection_not_open:%s focused=%s expected=%s opened_on_press=%s source_visible=%s" % [screen_name, inspection_focus, button, opened_on_press, button.is_visible_in_tree()])
		quit(5)
		return
	await _capture(client, screen_name)
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.physical_keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel)
	cancel = cancel.duplicate()
	cancel.pressed = false
	root.push_input(cancel)


func _capture_ship_families(client: Node) -> void:
	client.network_world.set_network_active(false)
	var canvas := CanvasLayer.new()
	canvas.layer = 200
	root.add_child(canvas)
	var backdrop := ColorRect.new()
	backdrop.color = Color("05091b")
	backdrop.size = root.get_visible_rect().size
	canvas.add_child(backdrop)
	var title := Label.new()
	title.text = "BUILD SILHOUETTES · SHARED HULL & HIT CIRCLE"
	title.position = Vector2(90, 65)
	title.add_theme_font_size_override("font_size", 36)
	canvas.add_child(title)
	var names := ["BASE", "BEAM", "SPREAD", "CANNON", "SHIELD", "DRIVE", "ORDNANCE", "REPAIR"]
	for index in names.size():
		var stats := CombatStats.create_base()
		match index:
			1: stats.beam_weapon = true
			2: stats.projectile_count = 3
			3: stats.projectile_damage = 50.0
			4: stats.shield_ram_damage = 20.0
			5: stats.afterburner_enabled = true
			6: stats.mine_layer_enabled = true
			7: stats.auto_repair_enabled = true
		var position := Vector2(280 + index % 4 * 450, 350 + index / 4 * 430)
		var ship := CombatShipView.new()
		canvas.add_child(ship)
		ship.setup(index + 2, stats, position, Color("42e8ff"), false, names[index])
		ship.scale = Vector2.ONE * 2.4
		ship.combatant.aim_angle = -PI * 0.5
		ship.set_process(false)
		ship.queue_redraw()
	await _capture(client, "ship_families")
	canvas.free()
