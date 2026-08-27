class_name PresentationSystemTests
extends RefCounted

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const PowerupLayerScript = preload("res://src/client/presentation/powerup_layer.gd")

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
	context.expect_equal(audio.authored_music_inventory().gameplay, expected_gameplay_tracks, "export diagnostics report the discovered gameplay inventory")
	context.expect_equal(audio.gameplay_track_paths.size(), audio.gameplay_tracks.size(), "every gameplay stream retains its display-name source path")
	context.expect_equal(AudioDirector.music_display_name("res://music/heavy_electronic-edge_main.mp3.wav"), "Heavy Electronic Edge Main", "compound gameplay filenames become readable song titles")
	context.expect_true(audio.win_player.stream != null, "win music always has an authored or generated stream")
	audio.play_sfx(&"card_lock", "same-card")
	audio.play_sfx(&"card_lock", "same-card")
	context.expect_equal(audio._played_keys.size(), 1, "repeated reliable events cannot replay the same sound")
	audio.set_context(&"menu")
	context.expect_equal(audio.current_context, &"menu", "menu music context selects the authored stream")
	audio.set_context(&"gameplay")
	context.expect_equal(audio.current_context, &"gameplay", "gameplay playlist context works when optional tracks are absent")
	audio.gameplay_track_paths.clear()
	audio.gameplay_track_paths.append("res://music/heavy_electronic-edge_main.mp3.wav")
	audio.current_gameplay_track = 0
	context.expect_equal(audio.current_gameplay_track_name(), "Heavy Electronic Edge Main", "active gameplay track exposes a readable song name")
	audio.current_context = &"win"
	context.expect_equal(audio.current_gameplay_track_name(), "", "victory context never reports a gameplay song")
	tree_parent.remove_child(audio)
	audio.free()


static func _supported_audio_file_count(directory_path: String) -> int:
	var count := 0
	for file_name in ResourceLoader.list_directory(directory_path):
		if file_name.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			count += 1
	return count


static func _validate_visual_feedback(context: TestContext) -> void:
	var ship := SandboxShip.new()
	ship.setup(7, CombatStats.create_base(), Vector2(300.0, 400.0), Color("ff4f78"), true, "Neon Ace")
	context.expect_equal(ship.display_name, "Neon Ace", "ship presentation retains its public nameplate")
	context.expect_equal(ship.identity_pattern, 1, "ship identity includes a stable non-color pattern")
	context.expect_true(ship.thruster_particles != null and ship.thruster_particles.amount <= 10, "ship uses a lightweight bounded thruster particle emitter")
	ship.combatant.velocity = Vector2(240.0, 0.0)
	ship._process(1.0 / 60.0)
	context.expect_true(ship.thruster_particles.emitting and ship.thruster_intensity > 0.0, "ship movement activates speed-responsive thruster particles")
	ship.flash_afterburner(0.5)
	ship._process(1.0 / 60.0)
	context.expect_true(ship.thruster_particles.amount > 10 and ship.thruster_particles.speed_scale >= 2.0, "Afterburner produces a visibly larger exhaust bloom")
	ship.flash_damage()
	ship.flash_shield_block()
	context.expect_true(ship.damage_flash_remaining > 0.0, "damage has a distinct ship flash")
	context.expect_true(ship.shield_flash_remaining > 0.0, "shield block has a distinct ship flash")
	context.expect_equal(ship.ammo_indicator_text(), "AMMO 8/8", "local ship exposes its ammunition directly above the model")
	ship.combatant.weapon.ammunition = 4
	ship.combatant.weapon.request_reload(ship.combatant.stats)
	context.expect_true(ship.ammo_indicator_text().begins_with("RELOAD "), "in-world ammo indicator clearly switches to reload timing")
	ship.set_eliminated()
	context.expect_true(ship.elimination_pulse_remaining > 0.0, "elimination has a distinct pulse")
	context.expect_false(ship.thruster_particles.emitting, "eliminated ships stop emitting thruster particles")
	ship.free()

	var effects := CombatEffectsLayer.new()
	effects.spawn_impact(Vector2.ONE)
	effects.spawn_damage(Vector2.ONE, Vector2.RIGHT)
	effects.spawn_elimination(Vector2.ONE, Color.WHITE)
	context.expect_equal(effects.effects.size(), 3, "impact, damage direction, and elimination effects coexist")
	effects.clear_effects()
	context.expect_empty(effects.effects, "presentation effects clear between heats")
	effects.free()
	var powerup_layer := PowerupLayerScript.new()
	powerup_layer.add_powerup({"powerup_id": 7, "card_id": &"kinetic_prow", "position": Vector2(500.0, 400.0), "rarity": CardDefinition.Rarity.RARE})
	context.expect_equal(powerup_layer.powerups.size(), 1, "Rare-or-better arena cards have a dedicated world presentation")
	powerup_layer.remove_powerup(7)
	context.expect_empty(powerup_layer.powerups, "collected arena card disappears from the world presentation")
	powerup_layer.free()

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
	local_ship.combatant.alive = false
	local_ship.set_eliminated()
	view._apply_snapshot_resources(local_ship, {"position": Vector2(160.0, 120.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 100.0, "shield": 100.0, "shielding": false, "ammunition": 8, "alive": true})
	context.expect_true(local_ship.combatant.alive and local_ship.collision_layer == 2, "a respawn snapshot fully revives an eliminated ship visual for the next heat")
	context.expect_true(local_ship.z_index > 0, "ships render above arena geometry")
	var remote_ship := SandboxShip.new()
	remote_ship.setup(2, CombatStats.create_base(), Vector2(112.0, 120.0), Color.CYAN, false, "Remote")
	remote_ship.global_position = Vector2(112.0, 120.0)
	view.ships[2] = remote_ship
	view.prediction_initialized = true
	view.prediction.predicted_position = Vector2(100.0, 120.0)
	view.prediction.predicted_velocity = Vector2(240.0, 0.0)
	local_ship.global_position = view.prediction.predicted_position
	view._separate_local_visual_from_remote(local_ship)
	context.expect_true(local_ship.global_position.distance_to(remote_ship.global_position) >= GameConstants.SHIP_COLLISION_RADIUS * 2.0, "client prediction immediately separates a local ship from an overlapping remote ship")
	context.expect_true(view.prediction.smoothing_remaining <= 0.0, "contact escape clears smoothing that could visually glue ships together")
	view.ships.erase(2)
	remote_ship.free()
	view.authoritative_projectiles.remove(projectile.projectile_id)
	view.local_stats = StatSystem.derive({&"scatter_array": 1}, CardCatalog.create_default())
	view.local_weapon.shot_sequence = 9
	view._spawn_predicted_projectile(local_ship, 0.0)
	context.expect_equal(
		view.authoritative_projectiles.size(),
		view.local_stats.projectile_count,
		"Scatter Array predicts every projectile in the local multi-shot"
	)
	var authoritative_scatter: Array[ProjectileState] = []
	for projectile_index in view.local_stats.projectile_count:
		authoritative_scatter.append(ProjectileState.create(
			projectile_index + 1,
			view.local_peer_id,
			view.local_weapon.shot_sequence,
			local_ship.global_position,
			0.0,
			view.local_stats
		))
	view._on_projectile_batch({"spawned": authoritative_scatter, "removed": []})
	context.expect_equal(
		view.authoritative_projectiles.size(),
		authoritative_scatter.size(),
		"authoritative multi-shot reconciliation removes every collisionless predicted visual"
	)
	var only_authoritative_projectiles := true
	for scatter_projectile in view.authoritative_projectiles.all_projectiles():
		if scatter_projectile.projectile_id <= 0:
			only_authoritative_projectiles = false
	context.expect_true(
		only_authoritative_projectiles,
		"only authoritative barrier-colliding projectiles remain after multi-shot reconciliation"
	)
	for scatter_projectile in view.authoritative_projectiles.all_projectiles():
		view.authoritative_projectiles.remove(scatter_projectile.projectile_id)
	var beam_volley_stats := CombatStats.create_base()
	beam_volley_stats.beam_weapon = true
	beam_volley_stats.projectile_count = 3
	beam_volley_stats.projectile_spread_degrees = 18.0
	beam_volley_stats.ricochet_count = 1
	view.local_stats = beam_volley_stats
	view.local_weapon.shot_sequence = 10
	local_ship.global_position = Vector2(100.0, 900.0)
	view._spawn_predicted_projectile(local_ship, PI)
	view._step_projectile_visuals(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_equal(view.authoritative_projectiles.size(), 3, "client retains every reflected beam in the predicted multi-shot volley")
	var every_beam_visually_rebounded := true
	for beam_projectile in view.authoritative_projectiles.all_projectiles():
		if beam_projectile.velocity.x <= 0.0 or beam_projectile.remaining_ricochets != 0:
			every_beam_visually_rebounded = false
	context.expect_true(every_beam_visually_rebounded, "client immediately renders rebound behavior for every beam instead of waiting for correction")
	for beam_projectile in view.authoritative_projectiles.all_projectiles():
		view.authoritative_projectiles.remove(beam_projectile.projectile_id)
	var correction_stats := CombatStats.create_base()
	correction_stats.ricochet_count = 2
	var stale_projectile := ProjectileState.create(400, 2, 12, Vector2(500.0, 500.0), 0.0, correction_stats)
	view.authoritative_projectiles.add(stale_projectile)
	var corrected_projectile := ProjectileState.create(400, 2, 12, Vector2(540.0, 510.0), PI * 0.5, correction_stats)
	corrected_projectile.remaining_ricochets = 0
	corrected_projectile.remaining_pierces = 1
	corrected_projectile.lifetime_remaining = 0.4
	view._on_projectile_correction({"spawned": [corrected_projectile]})
	var synchronized_projectile := view.authoritative_projectiles.get_projectile(400)
	context.expect_true(
		synchronized_projectile.velocity.y > 0.0
		and synchronized_projectile.remaining_ricochets == 0
		and synchronized_projectile.remaining_pierces == 1
		and is_equal_approx(synchronized_projectile.lifetime_remaining, 0.4),
		"projectile correction synchronizes rebound direction and every remaining traversal budget"
	)
	local_ship.free()
	view.camera.free()
	view.free()


static func _validate_production_screens(context: TestContext, tree_parent: Node) -> void:
	var packed_scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := packed_scene.instantiate()
	tree_parent.add_child(client)
	context.expect_true(client.connection_screen != null, "production connection screen exists")
	context.expect_equal(client.version_label.text, "BETA 3  ·  VERSION 0.1.0-beta.3", "main screen displays the canonical Beta 3 version")
	context.expect_equal(client.connection_tabs.get_tab_count(), 3, "connection screen separates LAN, direct-connect, and host flows")
	context.expect_true(client.lan_browser != null and client.lan_browser.mode == LanDiscoveryService.Mode.BROWSER, "connection screen actively browses for LAN servers")
	var discovered_servers: Array[Dictionary] = [
		{"server_name": "Local Test Arena", "address": "192.168.1.50", "game_port": 7000, "protocol_version": GameConstants.PROTOCOL_VERSION, "human_count": 2, "npc_count": 1, "player_limit": 8, "match_active": false, "ping_ms": 4},
		{"server_name": "Old Version", "address": "192.168.1.60", "game_port": 7000, "protocol_version": GameConstants.PROTOCOL_VERSION - 1, "human_count": 1, "npc_count": 0, "player_limit": 4, "match_active": false, "ping_ms": 8},
	]
	client._on_lan_servers_updated(discovered_servers)
	context.expect_equal(client.lan_servers_container.get_child_count(), 2, "LAN browser renders one structured row per discovered server")
	var compatible_join := client.lan_servers_container.get_child(0).get_child(0).get_child(1) as Button
	var incompatible_join := client.lan_servers_container.get_child(1).get_child(0).get_child(1) as Button
	context.expect_false(compatible_join.disabled, "compatible LAN server is directly joinable")
	context.expect_true(incompatible_join.disabled, "protocol-mismatched LAN server remains visible but cannot be joined")
	var host_error: Error = client._start_hosted_server({"port": 17459, "max_players": 32, "rounds_to_win": 3, "server_name": "Embedded Test Arena"})
	context.expect_equal(host_error, OK, "one-click host creates a real authoritative server inside an isolated multiplayer subtree")
	context.expect_true(client._hosted_server_bridge.role == NetworkBridge.Role.SERVER and client._hosted_server_multiplayer != client.multiplayer, "hosted server and playable client retain independent MultiplayerAPI instances")
	client._stop_hosted_server()
	var reserved_host_error: Error = client._start_hosted_server({"port": LanDiscoveryProtocol.DISCOVERY_PORT, "max_players": 32, "rounds_to_win": 3, "server_name": "Collision Test"})
	context.expect_equal(reserved_host_error, ERR_INVALID_PARAMETER, "gameplay server cannot consume the fixed LAN discovery port")
	client._stop_hosted_server()
	context.expect_true(client.lobby_panel != null, "production lobby screen exists")
	context.expect_true(client.lobby_options_popup != null and client.powerups_button != null, "lobby exposes a dedicated match options menu")
	context.expect_equal(client.lobby_options_button.text, "MATCH OPTIONS", "ship colour is no longer presented as a separate lobby option")
	context.expect_false(client.powerups_button.button_pressed, "random spawn powerups are visibly disabled by default")
	context.expect_approx(client.powerup_interval_control.value, 20.0, "random drop interval visibly defaults to twenty seconds")
	context.expect_false(client.powerups_permanent_button.button_pressed, "random drop permanence visibly defaults off")
	context.expect_approx(client.overtime_start_control.value, 90.0, "overtime visibly defaults to ninety seconds")
	context.expect_equal(client.npc_all_difficulty_control.item_count, 5, "lobby provides one bulk dropdown covering every NPC difficulty")
	context.expect_true(client.ship_color_popup != null and client.random_color_button != null and client.ship_color_picker != null and client.apply_ship_color_button != null, "roster colour selection owns a wheel with Random and explicit Apply actions")
	context.expect_equal(client.ship_color_picker.picker_shape, ColorPicker.SHAPE_HSV_WHEEL, "roster colour selection opens an HSV wheel")
	context.expect_true(client.draft_panel != null, "production draft screen exists")
	context.expect_true(client.network_world.hud_panel != null, "production combat HUD exists")
	context.expect_true(client.heat_intro_panel != null, "each heat has a centered READY and BEGIN presentation")
	context.expect_true(client.network_world.match_status_label != null, "match timing and state integrate into the combat HUD")
	context.expect_true(client.network_world.hud_panel.custom_minimum_size.x < 520.0 and client.network_world.hud_panel.custom_minimum_size.y < 190.0, "upper-left combat HUD uses the compact footprint")
	context.expect_true(client.network_world.spectator_label != null, "production spectator banner exists")
	context.expect_false(client.offline_sandbox.camera.enabled, "inactive offline camera cannot steal the online viewport")
	context.expect_true(client.scoreboard_panel != null, "production scoreboard exists")
	context.expect_true(client.results_panel != null, "production results screen exists")
	context.expect_true(client.results_winner_label != null and client.results_standings_container != null, "victory screen uses a structured champion and standings composition")
	context.expect_true(client.pause_overlay != null, "non-pausing online pilot menu exists")
	context.expect_true(client.settings_panel != null, "shared display and audio settings screen exists")
	context.expect_true(client.input_profiles != null, "production client owns a persistent input profile manager")
	context.expect_equal(client.settings_tabs.get_tab_count(), 2, "settings separates display and audio from controls")
	context.expect_equal(client.control_scheme_control.item_count, 2, "settings can switch between keyboard/mouse and controller profiles")
	context.expect_equal(client.flight_mode_control.item_count, 2, "settings exposes Newtonian and Relative flight modes")
	context.expect_equal(client.flight_mode_control.get_item_id(0), client.InputProfileManagerScript.FlightMode.NEWTONIAN, "Newtonian ship-facing flight remains selected by default")
	context.expect_equal(client.input_profiles.binding_text(&"manual_reload"), "R", "controls screen reserves R for manual reload by default")
	context.expect_equal(client.binding_rows.get_child_count(), client.input_profiles.rebind_actions().size() * 2, "controls tab exposes every active-profile binding")
	context.expect_equal(client.window_mode_control.item_count, 3, "settings exposes windowed, borderless fullscreen, and exclusive fullscreen")
	context.expect_equal(client.window_mode_control.get_item_id(0), client.WindowModeOption.WINDOWED, "windowed remains the default display mode")
	context.expect_equal(client.resolution_control.item_count, client.RESOLUTION_OPTIONS.size(), "settings exposes every supported resolution")
	context.expect_true(Vector2i(3840, 2160) in client.RESOLUTION_OPTIONS and Vector2i(5120, 2160) in client.RESOLUTION_OPTIONS, "settings includes common 4K and 5K2K resolutions")
	context.expect_true(Vector2i(2560, 1080) in client.RESOLUTION_OPTIONS and Vector2i(3440, 1440) in client.RESOLUTION_OPTIONS, "settings preserves common ultrawide resolutions")
	context.expect_true(Vector2i(3840, 1080) in client.RESOLUTION_OPTIONS and Vector2i(5120, 1440) in client.RESOLUTION_OPTIONS, "settings includes 32:9 super-ultrawide resolutions")
	context.expect_true(Vector2i(2880, 1920) in client.RESOLUTION_OPTIONS, "settings includes the requested 2880x1920 resolution")
	client.current_window_mode = client.WindowModeOption.BORDERLESS_FULLSCREEN
	client._update_resolution_control_state()
	context.expect_true(client.resolution_control.disabled, "borderless fullscreen clearly defers resolution selection to the desktop")
	client.current_window_mode = client.WindowModeOption.WINDOWED
	client._update_resolution_control_state()
	context.expect_false(client.resolution_control.disabled, "windowed mode restores explicit resolution selection")
	context.expect_equal(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand", "ultrawide windows reveal space without nonuniform stretching")
	context.expect_true(client.splash_screen != null, "animated splash screen exists")
	context.expect_approx(client.SPLASH_AUTO_ADVANCE_SECONDS, 10.0, "splash declares a ten-second automatic advance")
	var start_event := InputEventKey.new()
	start_event.keycode = KEY_ENTER
	start_event.pressed = true
	client._input(start_event)
	context.expect_true(client.splash_dismissed, "any key advances the splash immediately")
	var controller_start := InputEventJoypadButton.new()
	controller_start.button_index = JOY_BUTTON_A
	controller_start.pressed = true
	context.expect_true(client._is_start_input(controller_start), "controller buttons can advance the splash immediately")
	client.splash_screen.visible = false
	context.expect_true(client.win_overlay != null, "dedicated victory screen exists")
	context.expect_true(client.draft_panel.custom_minimum_size.x <= 1280.0 and client.draft_panel.custom_minimum_size.y <= 720.0, "five-card draft fits the 1280x720 acceptance viewport")
	context.expect_true(client.results_panel.custom_minimum_size.x <= 1280.0 and client.results_panel.custom_minimum_size.y <= 720.0, "results screen fits the 1280x720 acceptance viewport")
	var players: Array[Dictionary] = []
	for index in 32:
		players.append({"peer_id": index + 2, "display_name": "Pilot %02d" % (index + 1), "ship_color": ServerLobby.RANDOM_SHIP_COLORS[index % ServerLobby.RANDOM_SHIP_COLORS.size()], "spectator": false, "is_npc": false, "ready": true})
	client.bridge.local_peer_id = 2
	client._on_connected(2)
	client.network_world._on_connected(2)
	client._on_lobby_state({"players": players, "leader_id": 2, "player_limit": 32, "server_capacity": 32, "npc_count": 0, "ready_human_count": 32, "all_humans_ready": true, "npcs_enabled": false, "random_spawn_powerups": true, "match_active": false, "rounds_to_win": 3})
	context.expect_equal(client.lobby_roster.get_child_count(), 32, "scrollable lobby roster renders all 32 participants")
	context.expect_true(client.lobby_roster.get_parent() is ScrollContainer, "32-player lobby roster is scrollable")
	context.expect_true(client.connection_screen.visible and not client.connection_form_panel.visible, "waiting lobby uses the centered menu backdrop instead of the connect form")
	context.expect_false(client.network_world.visible, "arena remains hidden while players wait in the lobby")
	context.expect_equal(client.network_world.local_peer_id, 2, "hidden lobby preserves the connected renderer's local identity")
	context.expect_equal(client.lobby_roster.get_child(1).get_child_count(), 5, "leader receives colour identity and an eject control for another human")
	context.expect_true(client.powerups_button.button_pressed and not client.powerups_button.disabled, "lobby leader sees and can edit the authoritative powerup option")
	var local_color_swatch := client.lobby_roster.get_child(0).get_node("ShipColor") as Button
	var remote_color_swatch := client.lobby_roster.get_child(1).get_node("ShipColor") as Button
	context.expect_true(local_color_swatch != null and not local_color_swatch.disabled, "local human roster colour is the active colour-picker control")
	context.expect_true(remote_color_swatch != null and remote_color_swatch.disabled, "another human's roster colour remains visible but cannot be edited locally")
	local_color_swatch.pressed.emit()
	context.expect_true(client.ship_color_popup.visible, "clicking the local roster colour opens the colour wheel")
	var prior_color: Color = client.preferred_ship_color
	client._on_ship_color_changed(Color("ff4ea3"))
	context.expect_equal(client.preferred_ship_color, prior_color, "wheel changes remain pending until Apply is pressed")
	context.expect_equal(client.pending_ship_color.to_html(false), "ff4ea3", "wheel tracks the pending custom colour")
	client._apply_ship_color()
	context.expect_equal(client.preferred_ship_color.to_html(false), "ff4ea3", "Apply commits the selected ship colour")
	context.expect_false(client.ship_color_popup.visible, "Apply closes the roster colour picker")
	client.bridge.local_peer_id = 3
	client._rebuild_lobby_roster({"players": players, "leader_id": 2, "match_active": false}, false)
	context.expect_true(not (client.lobby_roster.get_child(1).get_node("ShipColor") as Button).disabled, "a non-leader human can edit their own roster colour")
	context.expect_true((client.lobby_roster.get_child(0).get_node("ShipColor") as Button).disabled, "the non-leader still cannot edit the host's colour")
	client.bridge.local_peer_id = 2
	client._rebuild_lobby_roster({"players": players, "leader_id": 2, "match_active": false}, true)
	context.expect_false(client.start_button.disabled, "leader can launch once all humans are ready")
	context.expect_equal(client.start_button.text, "Start Match", "ready multiplayer lobby uses ordinary start wording")
	var configurable_players: Array[Dictionary] = [
		{"peer_id": 2, "display_name": "Pilot 01", "spectator": false, "is_npc": false, "ready": false},
		{"peer_id": ServerLobby.NPC_PEER_ID_BASE + 1, "display_name": "NPC 01", "spectator": false, "is_npc": true, "npc_difficulty": NpcPilotController.Difficulty.SKILLED, "ready": true},
	]
	client._on_lobby_state({"players": configurable_players, "leader_id": 2, "player_limit": 2, "server_capacity": 32, "npc_count": 1, "ready_human_count": 0, "all_humans_ready": false, "npcs_enabled": true, "default_npc_difficulty": NpcPilotController.Difficulty.INSANE, "random_spawn_powerups": true, "random_powerup_interval_seconds": 12.0, "random_powerups_permanent": true, "overtime_start_seconds": 75.0, "match_active": false, "rounds_to_win": 3})
	var difficulty_control := client.lobby_roster.get_child(1).get_node("NpcDifficulty") as OptionButton
	context.expect_true(difficulty_control != null, "each waiting NPC renders an individual difficulty dropdown")
	context.expect_equal(difficulty_control.item_count, 5, "NPC dropdown exposes passive through insane")
	context.expect_equal(difficulty_control.get_selected_id(), NpcPilotController.Difficulty.SKILLED, "NPC dropdown reflects authoritative per-NPC difficulty")
	context.expect_false(difficulty_control.disabled, "lobby leader may edit an NPC difficulty before launch")
	context.expect_equal(client.npc_all_difficulty_control.get_selected_id(), NpcPilotController.Difficulty.INSANE, "bulk NPC dropdown reflects the authoritative lobby setting")
	context.expect_false(client.npc_all_difficulty_control.disabled, "bulk NPC difficulty remains editable for the lobby leader")
	context.expect_approx(client.powerup_interval_control.value, 12.0, "lobby renders the authoritative random drop interval")
	context.expect_true(client.powerups_permanent_button.button_pressed, "lobby renders authoritative drop permanence")
	context.expect_approx(client.overtime_start_control.value, 75.0, "lobby renders the authoritative overtime start")
	var solo_player: Array[Dictionary] = [{"peer_id": 2, "display_name": "Pilot 01", "spectator": false, "is_npc": false, "ready": true}]
	client._on_lobby_state({"players": solo_player, "leader_id": 2, "player_limit": 4, "server_capacity": 32, "npc_count": 0, "ready_human_count": 1, "all_humans_ready": true, "npcs_enabled": false, "match_active": false, "rounds_to_win": 3})
	context.expect_true(client.start_button.disabled and client.start_button.text == "Enable NPCs to Start Solo", "solo human is directed to enable NPCs")
	client._on_lobby_state({"players": solo_player, "leader_id": 2, "player_limit": 4, "server_capacity": 32, "npc_count": 0, "ready_human_count": 1, "all_humans_ready": true, "npcs_enabled": true, "match_active": false, "rounds_to_win": 3})
	context.expect_false(client.start_button.disabled, "ready solo human may start after enabling NPCs")
	context.expect_equal(client.start_button.text, "Start Match with NPCs", "solo NPC launch uses descriptive wording")
	client._on_match_event(&"STATE_CHANGED", 0, {"state_name": "DRAFT", "round_number": 1, "heat_number": 0, "builds": {2: {}}})
	context.expect_true(client.network_world.visible and client.network_world.process_mode != Node.PROCESS_MODE_DISABLED, "match start reactivates world rendering and prediction")
	context.expect_equal(client.network_world.local_peer_id, 2, "match start retains local identity for movement and predicted shots")
	client.network_world._on_snapshot({"server_tick": 1, "acknowledged_input": 0, "states": [
		{"peer_id": ServerLobby.NPC_PEER_ID_BASE + 1, "position": Vector2(400.0, 400.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 0.0, "shield": 0.0, "ammunition": 0, "alive": false, "shielding": false},
	]})
	context.expect_false((client.network_world.ships[ServerLobby.NPC_PEER_ID_BASE + 1] as SandboxShip).visible, "inactive NPC markers remain hidden during the initial draft")
	context.expect_false(client.network_world.arena.show_spawn_anchors, "production arena never exposes internal spawn anchors")
	client.latest_match_payload = {"state_name": "COUNTDOWN", "entered_tick": 120, "deadline_tick": 300, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {}, "builds": {}, "round_number": 2, "heat_number": 3}
	client.network_world.latest_server_tick = 180
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	context.expect_true(client.heat_intro_panel.visible and client.heat_intro_title.text == "READY", "heat countdown opens the READY banner")
	client.network_world.latest_server_tick = 294
	client._update_match_presentation()
	context.expect_true(client.heat_intro_title.text == "BEGIN", "BEGIN replaces READY with exactly 0.10 seconds left")
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "entered_tick": 300, "deadline_tick": -1, "overtime_start_tick": 3600, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {}, "builds": {}, "round_number": 2, "heat_number": 3}
	client.network_world.latest_server_tick = 300
	client.network_world.apply_match_state(client.latest_match_payload)
	client._update_match_presentation()
	context.expect_true(client.heat_intro_panel.visible and client.heat_intro_title.text == "BEGIN", "active heat briefly opens the BEGIN banner")
	client.network_world.latest_server_tick = 303
	client._update_match_presentation()
	context.expect_true(client.heat_intro_panel.visible and client.heat_intro_panel.modulate.a > 0.0 and client.heat_intro_panel.modulate.a < 1.0, "BEGIN rapidly fades during its 0.10-second post-roll")
	client.network_world.latest_server_tick = 306
	client._update_match_presentation()
	context.expect_false(client.heat_intro_panel.visible, "BEGIN clears after its 0.10-second post-roll")
	client._on_match_event(&"CARD_POWERUP_SPAWNED", 307, {"powerup_id": 9, "card_id": &"kinetic_prow", "position": Vector2(700.0, 500.0), "rarity": CardDefinition.Rarity.RARE})
	context.expect_true(client.network_world.powerup_layer.powerups.has(9), "reliable spawn event adds the arena card visual")
	client._on_match_event(&"CARD_POWERUP_COLLECTED", 308, {"powerup_id": 9, "card_id": &"kinetic_prow", "peer_id": 2, "position": Vector2(700.0, 500.0), "builds": {2: {&"kinetic_prow": 1}}})
	context.expect_false(client.network_world.powerup_layer.powerups.has(9), "reliable collection event removes the arena card visual")
	context.expect_true(client.network_world.local_stats.shield_ram_damage > 0.0, "local prediction adopts a collected card build immediately")
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "entered_tick": 0, "deadline_tick": 900, "overtime_start_tick": 3600, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "scores": {2: {"heat_wins": 1, "round_wins": 1, "kills": 4}, 3: {"heat_wins": 0, "round_wins": 0, "kills": 2}}, "builds": {2: {&"heavy_rounds": 2}, 3: {&"glass_reactor": 2}}, "round_number": 2, "heat_number": 3, "map_id": &"riftline", "map_name": "Riftline"}
	client.network_world.latest_server_tick = 300
	client.network_world.apply_match_state(client.latest_match_payload)
	var npc_max_health := StatSystem.derive({&"glass_reactor": 2}, client.card_catalog).max_health
	client.network_world._on_snapshot({"server_tick": 301, "acknowledged_input": 0, "states": [
		{"peer_id": 2, "position": Vector2(500.0, 500.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 100.0, "shield": 100.0, "ammunition": 8, "alive": true, "shielding": false},
		{"peer_id": 3, "position": Vector2(800.0, 500.0), "velocity": Vector2.ZERO, "aim_angle": PI, "health": npc_max_health, "shield": 100.0, "ammunition": 8, "alive": true, "shielding": false},
	]})
	var npc_ship := client.network_world.ships[3] as SandboxShip
	context.expect_approx(npc_ship.combatant.stats.max_health, npc_max_health, "remote NPC presentation derives its own card-modified maximum health")
	context.expect_approx(npc_ship.combatant.health_fraction(), 1.0, "a full-health NPC renders a full health ring even when its build changes maximum hull")
	client._update_match_presentation()
	context.expect_false(client.match_panel.visible, "former top-center match banner stays hidden during combat")
	context.expect_true(client.network_world.match_status_label.text.contains("ACTIVE HEAT") and client.network_world.match_status_label.text.contains("R2 H3"), "compact upper-left HUD carries match state and round details")
	context.expect_equal(client.network_world.arena.map_id, &"riftline", "client rebuilds the arena from the authoritative map ID")
	context.expect_true(client.network_world.match_status_label.text.contains("RIFTLINE"), "combat HUD identifies the active round map")
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.physical_keycode = KEY_TAB
	tab_event.pressed = true
	client.audio_director.gameplay_track_paths.clear()
	client.audio_director.gameplay_track_paths.append("res://assets/audio/music/gameplay/Heavy Electronic Edge Main.wav")
	client.audio_director.current_gameplay_track = 0
	client.audio_director.current_context = &"gameplay"
	client._input(tab_event)
	context.expect_true(client.scoreboard_panel.visible, "holding Tab opens the live scoreboard without relying on UI focus")
	context.expect_true(client.scoreboard_media_label.text.contains("MAP  ·  RIFTLINE"), "scoreboard explicitly identifies the active map")
	context.expect_true(client.scoreboard_media_label.text.contains("NOW PLAYING  ·  HEAVY ELECTRONIC EDGE MAIN"), "scoreboard identifies the active gameplay song")
	var live_kills := client.scoreboard_rows_container.get_child(0).find_child("MatchKills", true, false) as Label
	context.expect_equal(live_kills.text, "4", "live scoreboard displays the pilot's match-total kills")
	context.expect_equal(client.scoreboard_rows_container.get_child_count(), 2, "scoreboard renders one structured row per match participant")
	context.expect_true(client.scoreboard_rows_container.get_child(0).get_meta("peer_id") in [2, 3], "scoreboard rows retain player identity")
	var scoreboard_build_cards := client.scoreboard_rows_container.find_child("ScoreboardBuildCards", true, false) as HFlowContainer
	context.expect_true(scoreboard_build_cards != null and scoreboard_build_cards.get_child_count() == 1, "scoreboard build renders rarity-styled card hover targets")
	tab_event.pressed = false
	client._input(tab_event)
	context.expect_false(client.scoreboard_panel.visible, "releasing Tab immediately returns to combat")
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.CONTROLLER, false)
	context.expect_true(client.input_profiles.uses_controller(), "production client switches to the controller profile without changing the network path")
	var controller_scoreboard := InputEventJoypadButton.new()
	controller_scoreboard.button_index = JOY_BUTTON_BACK
	controller_scoreboard.pressed = true
	client._input(controller_scoreboard)
	context.expect_true(client.scoreboard_panel.visible, "configured controller button opens the momentary scoreboard")
	controller_scoreboard.pressed = false
	client._input(controller_scoreboard)
	context.expect_false(client.scoreboard_panel.visible, "releasing the configured controller button closes the scoreboard")
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.KEYBOARD_MOUSE, false)
	client.latest_match_payload = {"state_name": "MATCH_RESULT", "match_winner": 2, "deadline_tick": -1, "participant_peer_ids": [2], "scores": {2: {"heat_wins": 0, "round_wins": 1, "kills": 7}}, "builds": {2: {&"heavy_rounds": 2}}, "round_number": 1, "heat_number": 2}
	client.network_world.latest_server_tick = 300
	client._update_match_presentation()
	context.expect_true(client.win_overlay.visible and client.results_panel.visible, "match result opens the dedicated final standings screen")
	context.expect_true(client.results_label.text.contains("VICTORY"), "results screen clearly identifies the winner")
	context.expect_equal(client.results_standings_container.get_child_count(), 1, "structured standings renders one row per participant")
	context.expect_equal(client.results_standings_container.get_child(0).get_meta("peer_id"), 2, "winner occupies the first highlighted standings row")
	var round_wins_label := client.results_standings_container.get_child(0).find_child("RoundWins", true, false) as Label
	context.expect_equal(round_wins_label.text, "1", "victory standings retain round wins without the always-reset heat-win value")
	context.expect_false(round_wins_label.text.contains("HEAT"), "victory standings omit the unnecessary heat-wins column")
	var result_kills_label := client.results_standings_container.get_child(0).find_child("MatchKills", true, false) as Label
	context.expect_equal(result_kills_label.text, "7", "victory standings retain the pilot's full-match kill total")
	var final_build_cards := client.results_standings_container.get_child(0).find_child("FinalBuildCards", true, false) as HFlowContainer
	context.expect_true(final_build_cards != null and final_build_cards.get_child_count() == 1, "final build renders each owned card as an individual hover target")
	var result_card_chip := final_build_cards.get_child(0) as Button
	context.expect_equal(result_card_chip.get_meta("card_id"), &"heavy_rounds", "final-build hover target retains its authoritative card identity")
	context.expect_true(result_card_chip.tooltip_text.contains("CARD STATS") and result_card_chip.tooltip_text.contains("Projectile Damage") and result_card_chip.tooltip_text.contains("×1.82 total"), "hover popup shows exact per-stack and compounded card statistics")
	var card_preview := result_card_chip._make_custom_tooltip(result_card_chip.tooltip_text) as PanelContainer
	context.expect_true(card_preview != null and card_preview.name == "CardPreview", "card hover builds a dedicated card-shaped preview instead of a generic text box")
	context.expect_equal(card_preview.get_meta("card_id"), &"heavy_rounds", "visual card preview retains the hovered card identity")
	context.expect_true(card_preview.custom_minimum_size.x >= 390.0, "visual card preview reserves a readable card-width composition")
	var preview_style := card_preview.get_theme_stylebox("panel") as StyleBoxFlat
	context.expect_approx(preview_style.border_color.r, client.card_catalog.get_card(&"heavy_rounds").rarity_color().r, "visual card preview border reflects card rarity")
	card_preview.free()
	context.expect_true(client.results_winner_label.text.contains(client._player_name(2).to_upper()), "champion plate names the winner independently of the standings table")
	context.expect_false(client.results_return_button.disabled, "lobby leader receives an actionable exit-to-lobby button")
	context.expect_equal(client.results_return_button.text, "EXIT TO LOBBY", "final screen replaces the automatic countdown with an explicit exit")
	context.expect_false(client.lobby_panel.visible, "lobby menu remains hidden throughout the game loop")
	client.network_world._on_snapshot({"server_tick": 400, "acknowledged_input": 20, "states": [
		{"peer_id": 2, "position": Vector2(500.0, 400.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 100.0, "shield": 100.0, "ammunition": 8, "alive": true, "shielding": false},
	]})
	context.expect_true(client.network_world.ships.has(2), "first match renderer owns the local ship before lobby reset")
	client.network_world.input_sequence = 782
	client.network_world.client_tick = 940
	client._on_match_event(&"STATE_CHANGED", 420, {"state_name": "LOBBY", "round_number": 0, "heat_number": 0, "builds": {}})
	context.expect_equal(client.network_world.local_peer_id, 2, "lobby return preserves the connected local peer identity")
	context.expect_equal(client.network_world.input_sequence, 782, "lobby return preserves the monotonic input sequence expected by the server")
	context.expect_equal(client.network_world.client_tick, 940, "lobby return preserves the connected client tick")
	context.expect_empty(client.network_world.ships, "lobby return clears first-match ship visuals")
	client._on_match_event(&"STATE_CHANGED", 440, {"state_name": "DRAFT", "round_number": 1, "heat_number": 0, "builds": {2: {}}})
	client._on_match_event(&"STATE_CHANGED", 500, {"state_name": "COUNTDOWN", "entered_tick": 500, "deadline_tick": 680, "round_number": 1, "heat_number": 1, "participant_peer_ids": [2], "alive_peer_ids": [2], "builds": {2: {}}})
	client.network_world._on_snapshot({"server_tick": 520, "acknowledged_input": 0, "states": [
		{"peer_id": 2, "position": Vector2(640.0, 440.0), "velocity": Vector2(120.0, 0.0), "aim_angle": 0.0, "health": 100.0, "shield": 100.0, "ammunition": 8, "alive": true, "shielding": false},
	]})
	context.expect_true(client.network_world.visible and client.network_world.prediction_initialized, "second match initializes local rendering and prediction from its first snapshot")
	context.expect_true((client.network_world.ships[2] as SandboxShip).local_control, "second-match ship is recognized as the local controllable ship")
	client.connection_screen.visible = false
	client._toggle_pause_overlay()
	context.expect_true(client.pause_overlay.visible and client.network_world.input_blocked, "Escape overlay blocks local combat input without pausing the server")
	client._hide_pause_overlay()
	client._on_rejected(&"SERVER_FULL", "The server is full.")
	context.expect_true(client.connection_screen.visible and client.connection_status.text.contains("try again"), "connection rejection returns to a usable recovery screen")
	tree_parent.remove_child(client)
	client.free()
