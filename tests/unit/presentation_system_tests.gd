class_name PresentationSystemTests
extends RefCounted

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const PowerupLayerScript = preload("res://src/client/presentation/powerup_layer.gd")
const KillFeedScript = preload("res://src/client/ui/kill_feed.gd")
const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const ShipPatternGeometryScript = preload("res://src/client/presentation/ship_pattern_geometry.gd")

static func run(context: TestContext, tree_parent: Node) -> void:
	_validate_audio_pipeline(context, tree_parent)
	_validate_visual_feedback(context)
	_validate_production_screens(context, tree_parent)


static func _validate_audio_pipeline(context: TestContext, tree_parent: Node) -> void:
	var audio := AudioDirector.new()
	tree_parent.add_child(audio)
	context.expect_equal(audio.sfx_streams.size(), AudioDirector.SFX_NAMES.size(), "audio director provides every required combat cue")
	var authored_sfx_count := 0
	for event_name in AudioDirector.SFX_NAMES:
		if not bool(audio.sfx_generated.get(event_name, true)):
			authored_sfx_count += 1
	context.expect_equal(audio.synthesized_placeholder_count() + authored_sfx_count, AudioDirector.SFX_NAMES.size(), "missing authored SFX receive synthesized placeholders")
	context.expect_true(FileAccess.file_exists("res://assets/audio/sfx/mine_detonated.wav"), "authored mine detonation is bundled")
	context.expect_false(bool(audio.sfx_generated.get(&"mine_detonated", true)), "authored mine detonation replaces its synthesized placeholder")
	context.expect_true(audio.sfx_streams.get(&"mine_detonated") is AudioStreamWAV, "authored mine detonation imports as a WAV stream")
	context.expect_true((audio.sfx_streams.get(&"afterburner") as AudioStreamWAV).get_length() >= 0.5, "Afterburner receives a sustained ignition-and-roar cue instead of a short generic chirp")
	context.expect_equal(audio.sfx_players.size(), AudioDirector.SFX_PLAYER_COUNT, "combat audio reserves the expanded priority-aware polyphony pool")
	var sfx_bus_index := AudioServer.get_bus_index(AudioDirector.SFX_BUS)
	var has_sfx_limiter := false
	for effect_index in AudioServer.get_bus_effect_count(sfx_bus_index):
		if AudioServer.get_bus_effect(sfx_bus_index, effect_index) is AudioEffectLimiter:
			has_sfx_limiter = true
	context.expect_true(has_sfx_limiter, "effects bus limits extreme overlapping weapon transients")
	context.expect_true(FileAccess.file_exists("res://assets/audio/README.md"), "audio drop-in contract is documented beside the asset paths")
	context.expect_equal(audio.resident_music_bytes(), 0, "startup discovers music without retaining its sample buffers")
	if FileAccess.file_exists("res://assets/audio/music/main_menu.mp3.wav"):
		audio.prepare_music_now(&"menu")
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
	audio.prepare_music_now(&"win")
	context.expect_true(audio.win_player.stream != null, "win music loads its authored or generated stream on demand")
	audio.play_sfx(&"card_lock", "same-card")
	audio.play_sfx(&"card_lock", "same-card")
	context.expect_equal(audio._played_keys.size(), 1, "repeated reliable events cannot replay the same sound")
	var catalog := CardCatalog.create_default()
	var base_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(CombatStats.create_base(), {}, catalog)
	var automatic_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"rapid_cycling": 1}, catalog), {&"rapid_cycling": 1}, catalog)
	var heavy_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"siege_cannon": 1}, catalog), {&"siege_cannon": 1}, catalog)
	var rail_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"rail_accelerant": 1}, catalog), {&"rail_accelerant": 1}, catalog)
	var scatter_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"scatter_array": 1}, catalog), {&"scatter_array": 1}, catalog)
	var pulse_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"beam_emitter": 1}, catalog), {&"beam_emitter": 1}, catalog)
	var repeater_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"laser_repeater": 1}, catalog), {&"laser_repeater": 1}, catalog)
	var lance_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"singularity_lance": 1}, catalog), {&"singularity_lance": 1}, catalog)
	var extreme_profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(StatSystem.derive({&"reality_shredder": 1}, catalog), {&"reality_shredder": 1}, catalog)
	context.expect_equal(base_profile.family, WeaponSoundProfile.FAMILY_STANDARD, "base weapon receives the standard kinetic sound family")
	context.expect_equal(base_profile.power_tier, 0, "unmodified base weapon starts at the restrained sound tier")
	context.expect_equal(automatic_profile.family, WeaponSoundProfile.FAMILY_AUTOMATIC, "rapid-fire build receives the automatic sound family")
	context.expect_equal(heavy_profile.family, WeaponSoundProfile.FAMILY_HEAVY, "Siege Cannon receives the heavy sound family")
	context.expect_equal(rail_profile.family, WeaponSoundProfile.FAMILY_RAIL, "Rail Accelerant receives the rail sound family")
	context.expect_equal(scatter_profile.family, WeaponSoundProfile.FAMILY_SCATTER, "multi-projectile build receives one broad scatter-volley sound family")
	context.expect_equal(pulse_profile.family, WeaponSoundProfile.FAMILY_BEAM_PULSE, "Beam Emitter transforms the firing identity into a pulse beam")
	context.expect_equal(repeater_profile.family, WeaponSoundProfile.FAMILY_BEAM_REPEATER, "Laser Repeater receives a distinct rapid beam identity")
	context.expect_equal(lance_profile.family, WeaponSoundProfile.FAMILY_BEAM_LANCE, "Singularity Lance receives the substantive beam-lance identity")
	context.expect_equal(extreme_profile.power_tier, 3, "Reality Shredder reaches the extreme substantive sound tier")
	var automatic_stream := audio._weapon_stream(automatic_profile, 0)
	var heavy_stream := audio._weapon_stream(heavy_profile, 0)
	context.expect_true(automatic_stream != heavy_stream, "weapon families cache distinct generated sound streams")
	context.expect_true(heavy_stream.get_length() > automatic_stream.get_length(), "heavy cannon body lasts longer than an automatic transient")
	var played_before_weapons := audio._played_keys.size()
	audio.play_weapon_shot(base_profile, 1, 10, Vector2.ZERO, Vector2.ZERO, true)
	audio.play_weapon_shot(base_profile, 1, 10, Vector2.ZERO, Vector2.ZERO, true)
	audio.play_weapon_shot(base_profile, 2, 10, Vector2.ZERO, Vector2.ZERO, false)
	context.expect_equal(audio._played_keys.size(), played_before_weapons + 2, "weapon deduplication removes prediction echoes without suppressing another pilot's simultaneous shot")
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
	var catalog := CardCatalog.create_default()
	var projectile_layer := SandboxProjectileLayer.new()
	projectile_layer.set_beam_builds({
		1: {&"laser_repeater": 1},
		2: {&"beam_emitter": 1},
		3: {&"sunbeam_core": 1},
		4: {&"reality_shredder": 1},
		5: {&"beam_emitter": 1, &"sunbeam_core": 1},
		6: {&"supernova_array": 1},
		7: {&"hollow_points": 1},
		8: {&"rail_accelerant": 1},
		9: {&"twin_shot": 1, &"causality_cannon": 1},
		10: {&"transcendent_chassis": 1},
		11: {&"supernova_array": 0},
		12: {&"hollow_points": 1, &"mine_layer": 1},
	}, catalog)
	context.expect_equal(projectile_layer.beam_color_for_owner(1), SandboxProjectileLayer.DEFAULT_BEAM_COLOR, "Epic beam weapons retain the standard beam colour")
	context.expect_equal(projectile_layer.beam_color_for_owner(2), catalog.get_card(&"beam_emitter").rarity_color(), "Legendary beam weapons render in Legendary yellow")
	context.expect_equal(projectile_layer.beam_color_for_owner(3), catalog.get_card(&"sunbeam_core").rarity_color(), "Mythical beam weapons render in the Mythical colour")
	context.expect_equal(projectile_layer.beam_color_for_owner(4), catalog.get_card(&"reality_shredder").rarity_color(), "Unobtanium beam weapons render in the Unobtanium colour")
	context.expect_equal(projectile_layer.beam_color_for_owner(5), catalog.get_card(&"sunbeam_core").rarity_color(), "the highest owned beam-weapon rarity controls the beam colour")
	context.expect_equal(projectile_layer.beam_color_for_owner(6), SandboxProjectileLayer.DEFAULT_BEAM_COLOR, "high-rarity non-beam cards do not recolour beams")
	context.expect_equal(projectile_layer.projectile_color_for_owner(7), catalog.get_card(&"hollow_points").rarity_color(), "Common weapon cards colour ordinary projectiles with their rarity")
	context.expect_equal(projectile_layer.projectile_color_for_owner(8), catalog.get_card(&"rail_accelerant").rarity_color(), "Rare weapon cards colour ordinary projectiles with their rarity")
	context.expect_equal(projectile_layer.projectile_color_for_owner(9), catalog.get_card(&"causality_cannon").rarity_color(), "the highest applied weapon rarity controls ordinary projectile colour")
	context.expect_equal(projectile_layer.projectile_color_for_owner(10), SandboxProjectileLayer.DEFAULT_BEAM_COLOR, "non-weapon cards do not recolour ordinary projectiles")
	context.expect_equal(projectile_layer.projectile_color_for_owner(11), SandboxProjectileLayer.DEFAULT_BEAM_COLOR, "weapon cards with no applied stacks do not recolour ordinary projectiles")
	context.expect_equal(projectile_layer.projectile_color_for_owner(12), catalog.get_card(&"hollow_points").rarity_color(), "special weapons such as Star Mines do not influence ordinary projectile colour")
	projectile_layer.free()

	var ship := SandboxShip.new()
	ship.setup(7, CombatStats.create_base(), Vector2(300.0, 400.0), Color("ff4f78"), true, "Neon Ace")
	context.expect_equal(ship.display_name, "Neon Ace", "ship presentation retains its public nameplate")
	context.expect_equal(ship.identity_pattern, 1, "ship identity includes a stable non-color pattern")
	context.expect_true(ship.thruster_particles != null and ship.thruster_particles.amount <= 10, "ship uses a lightweight bounded thruster particle emitter")
	ship.combatant.velocity = Vector2(240.0, 0.0)
	ship._process(1.0 / 60.0)
	context.expect_true(ship.thruster_particles.emitting and ship.thruster_intensity > 0.0, "ship movement activates speed-responsive thruster particles")
	context.expect_approx(ship.thruster_particles.rotation, 0.0, "the persistent contrail follows actual velocity", 0.001)
	ship.combatant.aim_angle = PI * 0.5
	ship.set_thrust_input(Vector2(1.0, 0.0))
	context.expect_equal(ship.thrust_input, Vector2(1.0, 0.0), "maneuvering jets retain the canonical ship-relative control command independently of velocity")
	ship.flash_afterburner(0.5)
	ship._process(1.0 / 60.0)
	context.expect_true(
		ship.thruster_particles.amount > 10
		and ship.thruster_particles.speed_scale >= 1.7
		and ship.thruster_particles.initial_velocity_max > 160.0
		and ship.thruster_particles.spread < 16.0,
		"Afterburner strengthens and narrows the velocity wake behind its dedicated facing-aligned lance"
	)
	context.expect_true(ship.afterburner_ignition_remaining > 0.0, "Afterburner starts a distinct ignition shock phase")
	ship.global_position += Vector2(18.0, 0.0)
	ship._process(SandboxShip.AFTERBURNER_ECHO_INTERVAL_SECONDS)
	context.expect_true(not ship.afterburner_echoes.is_empty(), "Afterburner leaves a bounded world-space ship echo wake")
	context.expect_true(ship.afterburner_echoes.size() <= SandboxShip.MAX_AFTERBURNER_ECHOES, "Afterburner echo history remains bounded per ship")
	ship.set_ship_color(Color("ff4ea3"))
	context.expect_equal(ship.ship_color.to_html(false), "ff4ea3", "an existing ship accepts a newer authoritative lobby colour")
	context.expect_approx(ship.thruster_particles.color_ramp.colors[1].b, Color("ff4ea3").lightened(0.18).b, "ship colour refresh also updates its thruster presentation")
	ship.set_ship_pattern(ShipAppearanceScript.CHECKERBOARD)
	context.expect_equal(ship.ship_pattern, ShipAppearanceScript.CHECKERBOARD, "an existing ship accepts a newer authoritative hull pattern")
	for pattern in ShipAppearanceScript.PATTERNS:
		context.expect_true(ShipPatternGeometryScript.all_vertices_fit_hull(pattern), "%s pattern geometry is clipped to the gameplay hull" % ShipAppearanceScript.display_name(pattern))
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
	var bridge := NetworkBridge.new()
	bridge.latest_lobby_state = {"players": [{"peer_id": 8, "display_name": "Guest", "ship_color": "42e8ff", "ship_pattern": "solid"}]}
	var identity_view := NetworkWorldView.new()
	identity_view.bridge = bridge
	var guest_ship := identity_view._ensure_ship(8, {"position": Vector2.ZERO})
	context.expect_equal(guest_ship.ship_color.to_html(false), "42e8ff", "guest ship can spawn from the lobby state available with its first snapshot")
	bridge.latest_lobby_state = {"players": [{"peer_id": 8, "display_name": "Guest", "ship_color": "ff4ea3", "ship_pattern": "zebra"}]}
	identity_view._ensure_ship(8, {"position": Vector2.ZERO})
	context.expect_equal(guest_ship.ship_color.to_html(false), "ff4ea3", "the next snapshot applies a later reliable lobby colour to an existing guest ship")
	context.expect_equal(guest_ship.ship_pattern, ShipAppearanceScript.ZEBRA, "the next snapshot applies a later reliable lobby pattern to an existing guest ship")
	identity_view.apply_match_state({"state_name": "ACTIVE_HEAT", "builds": {}, "players": [{"peer_id": 8, "display_name": "Match Guest", "ship_color": "62ff9b", "ship_pattern": "chevron"}]})
	context.expect_equal(guest_ship.ship_pattern, ShipAppearanceScript.CHEVRON, "authoritative match identity applies the selected pattern without waiting for another lobby update")
	context.expect_equal(guest_ship.ship_color.to_html(false), "62ff9b", "authoritative match identity supersedes stale lobby appearance data")
	context.expect_equal(guest_ship.display_name, "Match Guest", "authoritative match identity updates the in-world nameplate")
	identity_view.free()
	bridge.free()

	var effects := CombatEffectsLayer.new()
	effects.spawn_impact(Vector2.ONE)
	effects.spawn_damage(Vector2.ONE, Vector2.RIGHT)
	effects.spawn_elimination(Vector2.ONE, Color.WHITE)
	effects.spawn_rebound(Vector2.ONE)
	effects.spawn_mine_explosion(Vector2.ONE)
	context.expect_equal(effects.effects.size(), 5, "impact, damage direction, elimination, rebound, and mine effects coexist")
	var mine_effect := effects.effects[-1]
	context.expect_equal((mine_effect.sparks as Array).size(), CombatEffectsLayer.MINE_SPARK_COUNT, "mine explosion has a bounded radial spark burst")
	context.expect_equal((mine_effect.smoke as Array).size(), CombatEffectsLayer.MINE_SMOKE_COUNT, "mine explosion has a bounded smoke bloom")
	context.expect_approx(CombatEffectsLayer.MINE_EFFECT_DELAY, 0.1, "mine flash synchronizes with the authored sound delay")
	effects.clear_effects()
	context.expect_empty(effects.effects, "presentation effects clear between heats")
	context.expect_equal(effects.active_mine_effect_count, 0, "clearing presentation effects resets the mine-effect budget")
	effects.free()
	var powerup_layer := PowerupLayerScript.new()
	powerup_layer.add_powerup({"powerup_id": 7, "card_id": &"kinetic_prow", "position": Vector2(500.0, 400.0), "rarity": CardDefinition.Rarity.RARE})
	context.expect_equal(powerup_layer.powerups.size(), 1, "Rare-or-better arena cards have a dedicated world presentation")
	powerup_layer.remove_powerup(7)
	context.expect_empty(powerup_layer.powerups, "collected arena card disappears from the world presentation")
	powerup_layer.free()

	var view := NetworkWorldView.new()
	view.local_peer_id = 1
	view.input_sequence = 40
	view.client_tick = 80
	view._advance_input_clock()
	context.expect_equal(view.input_sequence, 41, "every predicted physics frame advances its replay sequence")
	context.expect_equal(view.client_tick, 81, "prediction input time advances with its replay sequence")
	var local_ship := SandboxShip.new()
	local_ship.setup(1, CombatStats.create_base(), Vector2(100.0, 100.0), Color.WHITE, true, "Local")
	view.ships[1] = local_ship
	var projectile := ProjectileState.create(50, 2, 1, Vector2(900.0, 100.0), PI, CombatStats.create_base())
	view.authoritative_projectiles.add(projectile)
	context.expect_equal(view.nearest_incoming_offscreen_projectile(), projectile, "nearest incoming projectile is selected for a shape indicator")
	view.camera = Camera2D.new()
	view.trigger_camera_shake(5.0, 0.2)
	context.expect_true(view.camera_shake_remaining > 0.0, "local damage can trigger restrained presentation-only camera shake")
	view.trigger_afterburner_feedback(Vector2.RIGHT)
	context.expect_true(view.camera_kick_remaining > 0.0 and view.camera_kick_offset.x < 0.0, "local Afterburner ignition recoils the camera opposite the boost direction")
	var feedback_events: Array[StringName] = []
	var feedback_payloads: Array[Dictionary] = []
	view.presentation_event.connect(func(event_name: StringName, payload: Dictionary) -> void:
		feedback_events.append(event_name)
		feedback_payloads.append(payload)
	)
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
	view.latest_server_tick = 30
	view._handle_snapshot_feedback(2, {"health": 100.0, "shield": 100.0, "shielding": false, "alive": true, "ammunition": 8, "position": remote_ship.global_position, "velocity": Vector2.RIGHT * 200.0, "aim_angle": PI * 0.5, "afterburner_active": false, "breakaway_active": false}, remote_ship)
	view.latest_server_tick = 31
	view._handle_snapshot_feedback(2, {"health": 100.0, "shield": 100.0, "shielding": false, "alive": true, "ammunition": 8, "position": remote_ship.global_position, "velocity": Vector2.RIGHT * 200.0, "aim_angle": PI * 0.5, "afterburner_active": true, "breakaway_active": false}, remote_ship)
	context.expect_equal(feedback_events.back(), &"afterburner", "a remote authoritative activation edge emits one Afterburner presentation event")
	context.expect_true(remote_ship.afterburner_bloom_remaining > 0.0, "remote Afterburner presentation anchors its dedicated lance from authoritative facing")
	remote_ship.afterburner_bloom_remaining = 0.0
	view.latest_server_tick = 32
	view._handle_snapshot_feedback(2, {"health": 100.0, "shield": 100.0, "shielding": false, "alive": true, "ammunition": 8, "position": remote_ship.global_position, "velocity": Vector2.RIGHT * 200.0, "aim_angle": PI * 0.5, "afterburner_active": false, "breakaway_active": false}, remote_ship)
	view.latest_server_tick = 33
	view._handle_snapshot_feedback(2, {"health": 100.0, "shield": 100.0, "shielding": false, "alive": true, "ammunition": 8, "position": remote_ship.global_position, "velocity": Vector2.RIGHT * 200.0, "aim_angle": PI * 0.5, "afterburner_active": false, "breakaway_active": true}, remote_ship)
	context.expect_equal(feedback_events.back(), &"breakaway", "Breakaway retains its own presentation event")
	context.expect_approx(remote_ship.afterburner_bloom_remaining, 0.0, "Breakaway no longer impersonates the facing-aligned Afterburner lance")
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
	context.expect_equal(feedback_events.back(), &"weapon_fire", "predicted local fire emits the profile-driven weapon event")
	context.expect_equal((feedback_payloads.back().profile as WeaponSoundProfile).family, WeaponSoundProfile.FAMILY_SCATTER, "predicted volley carries its derived scatter sound profile")
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
	var weapon_events_before_batch := feedback_events.count(&"weapon_fire")
	view._on_projectile_batch({"spawned": authoritative_scatter, "removed": []})
	context.expect_equal(feedback_events.count(&"weapon_fire"), weapon_events_before_batch + 1, "authoritative multi-projectile volley emits one deduplicatable sound event")
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
	view.local_stats = CombatStats.create_base()
	view.local_weapon.shot_sequence = 18
	view._spawn_predicted_projectile(local_ship, 0.0)
	var recovered_projectile := ProjectileState.create(1800, 1, 18, local_ship.global_position, 0.0, view.local_stats)
	view._on_projectile_correction({"spawned": [recovered_projectile]})
	context.expect_false(view.predicted_projectile_ids.has(18), "a correction promotes a local shot when its unreliable spawn delta was lost")
	context.expect_true(view.authoritative_projectiles.get_projectile(1800) != null, "correction recovery leaves one authoritative local projectile")
	view.authoritative_projectiles.remove(1800)
	view.local_weapon.shot_sequence = 19
	view._spawn_predicted_projectile(local_ship, 0.0)
	context.expect_true(view.predicted_projectile_ids.has(19), "unconfirmed local volley starts under bounded prediction tracking")
	view._expire_unconfirmed_predicted_projectiles(
		Time.get_ticks_msec() / 1000.0 + NetworkWorldView.MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS + 0.1
	)
	context.expect_false(view.predicted_projectile_ids.has(19), "timed-out local volley cannot survive as a client-only ghost")
	context.expect_equal(view.expired_predicted_volleys, 1, "expired local volleys increment network diagnostics")
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
	corrected_projectile.owner_id = 3
	corrected_projectile.has_rebounded = true
	view._on_projectile_correction({"spawned": [corrected_projectile]})
	var synchronized_projectile := view.authoritative_projectiles.get_projectile(400)
	context.expect_true(
		synchronized_projectile.velocity.y > 0.0
		and synchronized_projectile.remaining_ricochets == 0
		and synchronized_projectile.remaining_pierces == 1
		and synchronized_projectile.owner_id == 3
		and synchronized_projectile.has_rebounded
		and is_equal_approx(synchronized_projectile.lifetime_remaining, 0.4),
		"projectile correction synchronizes rebound ownership, presentation, direction, and traversal budget"
	)
	context.expect_true(&"rebound" in feedback_events, "first reflected correction emits distinct rebound feedback")
	var unseen_rebound := ProjectileState.create(401, 4, 13, Vector2(560.0, 510.0), PI, correction_stats)
	unseen_rebound.has_rebounded = true
	var weapon_events_before_rebound := feedback_events.count(&"weapon_fire")
	var rebound_events_before_delta := feedback_events.count(&"rebound")
	view._on_projectile_batch({"spawned": [unseen_rebound], "removed": []})
	context.expect_equal(feedback_events.count(&"rebound"), rebound_events_before_delta + 1, "a rebound delta remains visible when the original spawn packet was lost")
	context.expect_equal(feedback_events.count(&"weapon_fire"), weapon_events_before_rebound, "a rebound update is not misreported as a fresh weapon shot")
	local_ship.free()
	view.camera.free()
	view.free()


static func _validate_production_screens(context: TestContext, tree_parent: Node) -> void:
	var packed_scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := packed_scene.instantiate()
	tree_parent.add_child(client)
	context.expect_true(client.connection_screen != null, "production connection screen exists")
	context.expect_true(client.offline_sandbox.effects_layer is CombatEffectsLayer, "offline combat renders the same mine explosion feedback as network matches")
	var sandbox := client.offline_sandbox as OfflineSandbox
	var common_index := sandbox.catalog.all_ids().find(&"ablative_shell")
	var epic_index := sandbox.catalog.all_ids().find(&"aegis_matrix")
	sandbox.selected_card_index = common_index
	sandbox._update_card_label()
	context.expect_equal(sandbox.card_label.get_theme_color(&"font_color"), sandbox.catalog.get_card(&"ablative_shell").rarity_color(), "offline card selector renders a Common card in its rarity colour")
	sandbox.selected_card_index = epic_index
	sandbox._update_card_label()
	context.expect_equal(sandbox.card_label.get_theme_color(&"font_color"), sandbox.catalog.get_card(&"aegis_matrix").rarity_color(), "cycling the offline card selector refreshes its colour to the selected card rarity")
	context.expect_true(sandbox.kill_feed != null, "offline combat lab owns the shared top-right kill feed")
	sandbox._reset_combatants()
	sandbox._apply_damage_events([{"projectile_id": 700, "attacker_id": 1, "target_id": 2, "damage": 10_000.0}])
	context.expect_equal(sandbox.kill_feed.entries.size(), 1, "offline lethal damage adds one kill-feed entry")
	var offline_kill_entry := sandbox.kill_feed.entries[0].node as PanelContainer
	context.expect_equal(int(offline_kill_entry.get_meta("killer_id")), 1, "offline kill feed preserves the local attacker")
	context.expect_equal(int(offline_kill_entry.get_meta("victim_id")), 2, "offline kill feed preserves the target victim")
	context.expect_true(bool(offline_kill_entry.get_meta("local_involved")), "offline kill feed highlights local-player involvement")
	context.expect_equal((offline_kill_entry.get_child(0).get_child(0) as Label).text, "You", "offline kill feed resolves the local lab pilot identity")
	sandbox._reset_combatants()
	context.expect_empty(sandbox.kill_feed.entries, "resetting the offline heat clears prior kill-feed entries")
	sandbox._apply_damage_events([{"projectile_id": 701, "target_id": 2, "damage": 10_000.0}])
	context.expect_equal(String(sandbox.kill_feed.entries[0].reason), "environment", "offline uncredited damage is presented as an environmental elimination")
	sandbox._reset_combatants()
	context.expect_true(client.interface_theme.has_stylebox(&"focus", &"Button"), "shared interface theme defines a visible keyboard and controller focus state")
	context.expect_true(client.interface_theme.has_stylebox(&"focus", &"LineEdit"), "shared interface theme defines focused text inputs")
	context.expect_true(client.interface_theme.has_stylebox(&"tab_focus", &"TabBar"), "shared interface theme defines focused tab navigation")
	context.expect_equal(client.connection_primary_button.theme_type_variation, &"PrimaryButton", "primary connection action uses the shared semantic action language")
	context.expect_equal(client.lobby_options_button.theme_type_variation, &"SecondaryButton", "secondary lobby action uses the shared semantic action language")
	context.expect_equal(client.version_label.text, "BETA 10  ·  VERSION 0.1.0-beta.10", "main screen displays the canonical Beta 10 version")
	context.expect_equal(client._pointer_mode_for_gameplay(true), Input.MOUSE_MODE_CONFINED_HIDDEN, "active gameplay confines the hidden mouse pointer to the game window")
	context.expect_equal(client._pointer_mode_for_gameplay(true, true), Input.MOUSE_MODE_CONFINED, "native macOS gameplay cursor remains compositor-driven while confined to the game window")
	context.expect_equal(client._pointer_mode_for_gameplay(false), Input.MOUSE_MODE_VISIBLE, "interactive screens release and reveal the mouse pointer")
	context.expect_equal(client.connection_tabs.get_tab_count(), 3, "connection screen separates LAN, direct-connect, and host flows")
	context.expect_true(client.direct_password_field != null and client.direct_password_field.secret, "direct connect requires a masked lobby-password field")
	context.expect_true(client.remember_password_button != null, "direct connect offers client-local remembered passwords by server endpoint")
	context.expect_true(client.host_password_field != null and client.host_password_field.secret, "hosts must set a masked lobby password")
	client.connection_tabs.current_tab = 1
	context.expect_equal(client.host_field.find_next_valid_focus(), client.port_field, "Tab advances from the direct-connect host field to its port field")
	context.expect_equal(client.port_field.find_next_valid_focus(), client.direct_password_field, "Tab advances from the direct-connect port field to its password field")
	context.expect_equal(client.direct_password_field.find_prev_valid_focus(), client.port_field, "Shift+Tab returns from the direct-connect password field to its port field")
	client.connection_tabs.current_tab = 2
	context.expect_equal(client.server_name_field.find_next_valid_focus(), client.host_port_field, "Tab advances from the hosted server name to its port field")
	context.expect_equal(client.host_port_field.find_next_valid_focus(), client.host_password_field, "Tab advances from the hosted server port to its password field")
	client.connection_tabs.current_tab = 0
	context.expect_equal(client._password_settings_key(" EXAMPLE.COM ", 7000), client._password_settings_key("example.com", 7000), "remembered-password keys normalize host casing and whitespace")
	context.expect_equal(client._password_settings_key("[2001:db8::1]", 7000), client._password_settings_key("2001:db8::1", 7000), "remembered-password keys normalize bracketed IPv6 addresses")
	context.expect_false(client._password_settings_key("example.com", 7000) == client._password_settings_key("example.com", 7001), "remembered passwords are isolated by gameplay port")
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
	var host_error: Error = client._start_hosted_server({"port": 17459, "max_players": 32, "rounds_to_win": 3, "server_name": "Embedded Test Arena", "lobby_password": "test-lobby"})
	context.expect_equal(host_error, OK, "one-click host creates a real authoritative server inside an isolated multiplayer subtree")
	context.expect_true(client._hosted_server_bridge.role == NetworkBridge.Role.SERVER and client._hosted_server_multiplayer != client.multiplayer, "hosted server and playable client retain independent MultiplayerAPI instances")
	var f2_event := InputEventKey.new()
	f2_event.physical_keycode = KEY_F2
	f2_event.pressed = true
	client._unhandled_input(f2_event)
	context.expect_true(client.f2_return_confirmation.visible, "F2 asks for confirmation before leaving an active session")
	context.expect_true(client.f2_return_confirmation.dialog_text.contains("disconnect every player"), "F2 explicitly warns a host that returning to the menu will end the game for everyone")
	context.expect_true(client._hosted_server_root != null, "opening the F2 confirmation cannot stop the hosted server")
	client.f2_return_confirmation.hide()
	client._cancel_f2_return_to_menu()
	context.expect_false(client.network_world.input_blocked, "canceling the F2 confirmation restores gameplay input")
	client._stop_hosted_server()
	var reserved_host_error: Error = client._start_hosted_server({"port": LanDiscoveryProtocol.DISCOVERY_PORT, "max_players": 32, "rounds_to_win": 3, "server_name": "Collision Test", "lobby_password": "test-lobby"})
	context.expect_equal(reserved_host_error, ERR_INVALID_PARAMETER, "gameplay server cannot consume the fixed LAN discovery port")
	client._stop_hosted_server()
	context.expect_true(client.lobby_panel != null, "production lobby screen exists")
	context.expect_true(client.lobby_settings_button != null and client.lobby_settings_button.pressed.is_connected(client._show_settings.bind(false)), "waiting lobby Settings button opens the shared player settings screen")
	context.expect_true(client.direct_connect_button != null and client.direct_connect_button.pressed.is_connected(client.connection_controller._connect_online), "Direct Connect button is wired to its connection action")
	context.expect_true(client.host_join_button != null and client.host_join_button.pressed.is_connected(client.connection_controller._host_online), "Host & Join button is wired to its hosting action")
	context.expect_true(client.lobby_disconnect_button != null and client.lobby_disconnect_button.pressed.is_connected(client._disconnect_online), "waiting lobby Disconnect button is wired to the shared disconnect action")
	context.expect_true(client.pause_disconnect_button != null and client.pause_disconnect_button.pressed.is_connected(client._return_from_pause), "pause-menu Disconnect button is wired to the shared menu-return action")
	context.expect_true(client.lobby_options_popup != null and client.powerups_button != null, "lobby exposes a dedicated match options menu")
	context.expect_equal(client.lobby_options_button.text, "MATCH SETUP", "ship colour is no longer presented as a separate lobby option")
	context.expect_false(client.powerups_button.button_pressed, "random spawn powerups are visibly disabled by default")
	context.expect_approx(client.powerup_interval_control.value, 20.0, "random drop interval visibly defaults to twenty seconds")
	context.expect_false(client.powerups_permanent_button.button_pressed, "random drop permanence visibly defaults off")
	context.expect_approx(client.overtime_start_control.value, 45.0, "overtime visibly defaults to forty-five seconds")
	context.expect_equal(client.game_mode_control.item_count, 5, "lobby options expose all five selectable game modes")
	context.expect_equal(client.game_mode_control.get_selected_id(), GameModeRules.Mode.DEATH_MATCH, "Death Match is visibly selected by default")
	context.expect_true(client.team_count_row != null and client.team_count_control != null, "lobby options provide a configurable Team Death Match team count")
	context.expect_false(client.team_count_row.visible, "team count stays hidden outside Team Death Match")
	context.expect_equal(int(client.team_count_control.min_value), 2, "Team Death Match requires at least two teams")
	context.expect_equal(int(client.team_count_control.max_value), 8, "Team Death Match supports up to eight teams")
	context.expect_equal(client.npc_all_difficulty_control.item_count, 5, "lobby provides one bulk dropdown covering every NPC difficulty")
	context.expect_true(client.ship_color_popup != null and client.random_color_button != null and client.ship_color_picker != null and client.ship_pattern_control != null and client.apply_ship_color_button != null, "roster appearance selection owns colour, pattern, Random, and explicit Apply controls")
	context.expect_equal(client.ship_color_picker.picker_shape, ColorPicker.SHAPE_HSV_WHEEL, "roster colour selection opens an HSV wheel")
	context.expect_equal(client.ship_pattern_control.item_count, ShipAppearanceScript.PATTERNS.size(), "ship customization exposes every supported hull pattern")
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
	context.expect_true(client.credits_panel != null and client.credits_button != null, "main menu exposes the dedicated credits screen")
	context.expect_true(client.credits_button.pressed.is_connected(client._show_credits), "Credits button is wired to the credits screen")
	var credits_text := ""
	for credit_label in client.credits_panel.find_children("*", "Label", true, false):
		credits_text += (credit_label as Label).text + "\n"
	context.expect_true(
		"Graphite" in credits_text and "Champ" in credits_text and "Equip" in credits_text
		and "jbohack" in credits_text and "KingRat" in credits_text and "DoomGuy" in credits_text
		and "Adam" in credits_text and "WhackyJacky" in credits_text and "Hipu" in credits_text
		and "Krusty Dave" in credits_text
		and "ChatGPT" in credits_text,
		"credits screen includes every requested contributor"
	)
	context.expect_true(client.input_profiles != null, "production client owns a persistent input profile manager")
	context.expect_true(client.gameplay_cursor != null and client.gameplay_cursor.texture != null, "production client renders the combat crosshair inside the game framebuffer")
	context.expect_true(client.gameplay_cursor_canvas.layer > client.connection_canvas.layer, "software crosshair renders above the combat world and HUD")
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.KEYBOARD_MOUSE, false)
	client.connection_screen.visible = false
	client.offline_sandbox.set_sandbox_active(true)
	client._update_pointer_visibility()
	context.expect_true(client.gameplay_cursor.visible, "keyboard and mouse gameplay displays the software crosshair")
	client._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	context.expect_false(client._application_has_focus, "focus loss releases gameplay pointer ownership")
	context.expect_false(client.gameplay_cursor.visible, "focus loss immediately hides the in-game crosshair")
	client._update_pointer_visibility()
	context.expect_false(client.gameplay_cursor.visible, "unfocused frame updates cannot recapture the gameplay pointer")
	client._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	client._update_pointer_visibility()
	context.expect_true(client._application_has_focus and client.gameplay_cursor.visible, "focus return restores the active gameplay pointer mode")
	client.pause_overlay.visible = true
	client._update_pointer_visibility()
	context.expect_false(client.gameplay_cursor.visible, "interactive menus replace the combat crosshair with the system pointer")
	client.pause_overlay.visible = false
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.CONTROLLER, false)
	client._update_pointer_visibility()
	context.expect_false(client.gameplay_cursor.visible, "controller gameplay hides the stale mouse crosshair")
	client.offline_sandbox.set_sandbox_active(false)
	client.connection_screen.visible = true
	client.input_profiles.set_scheme(InputProfileManagerScript.Scheme.KEYBOARD_MOUSE, false)
	context.expect_equal(client.settings_tabs.get_tab_count(), 3, "settings separates display/audio, controls, and accessibility")
	context.expect_equal(client.control_scheme_control.item_count, 2, "settings can switch between keyboard/mouse and controller profiles")
	context.expect_equal(client.flight_mode_control.item_count, 2, "settings exposes Newtonian and Relative flight modes")
	context.expect_equal(client.flight_mode_control.get_selected_id(), client.InputProfileManagerScript.FlightMode.RELATIVE, "Relative screen-aligned flight is selected by default")
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
	context.expect_equal(client.splash_screen.find_child("StudioQuote", true, false).text, "“Now with 1000% more slop!”", "studio splash includes the requested quote")
	context.expect_approx(client.STUDIO_SPLASH_AUTO_ADVANCE_SECONDS, 4.0, "studio splash declares a four-second automatic advance")
	context.expect_approx(client.SPLASH_AUTO_ADVANCE_SECONDS, 10.0, "splash declares a ten-second automatic advance")
	var start_event := InputEventKey.new()
	start_event.keycode = KEY_ENTER
	start_event.pressed = true
	client._input(start_event)
	context.expect_equal(client.splash_stage, 1, "first input advances from the studio splash to the game splash")
	client._finish_studio_splash()
	client._finish_game_splash_intro()
	client._input(start_event)
	context.expect_true(client.splash_dismissed, "second input advances from the game splash to the main menu")
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
	client.lobby_settings_button.pressed.emit()
	context.expect_true(client.settings_panel.visible and client.settings_return_to_lobby, "lobby players can open their saved display, audio, and control settings")
	client._hide_settings()
	context.expect_true(client.lobby_panel.visible and not client.settings_panel.visible and not client.settings_return_to_lobby, "Back from player settings restores the waiting lobby")
	context.expect_equal(client.lobby_roster.get_child(1).get_child_count(), 5, "leader receives colour identity and an eject control for another human")
	context.expect_true(client.powerups_button.button_pressed and not client.powerups_button.disabled, "lobby leader sees and can edit the authoritative powerup option")
	var local_color_swatch := client.lobby_roster.get_child(0).get_node("ShipColor") as Button
	var remote_color_swatch := client.lobby_roster.get_child(1).get_node("ShipColor") as Button
	context.expect_true(local_color_swatch != null and not local_color_swatch.disabled, "local human roster colour is the active colour-picker control")
	context.expect_true(remote_color_swatch != null and remote_color_swatch.disabled, "another human's roster colour remains visible but cannot be edited locally")
	local_color_swatch.pressed.emit()
	context.expect_true(client.ship_color_popup.visible, "clicking the local roster colour opens the colour wheel")
	context.expect_true(client.ship_color_blocker.visible and not client.lobby_panel.visible, "colour selection behaves as a true modal and blocks the lobby beneath it")
	var prior_color: Color = client.preferred_ship_color
	client._on_ship_color_changed(Color("ff4ea3"))
	client._on_ship_pattern_selected(ShipAppearanceScript.PATTERNS.find(ShipAppearanceScript.LEOPARD))
	context.expect_equal(client.preferred_ship_color, prior_color, "wheel changes remain pending until Apply is pressed")
	context.expect_equal(client.pending_ship_color.to_html(false), "ff4ea3", "wheel tracks the pending custom colour")
	context.expect_equal(client.pending_ship_pattern, ShipAppearanceScript.LEOPARD, "pattern selection remains pending until Apply is pressed")
	client._apply_ship_color()
	context.expect_equal(client.preferred_ship_color.to_html(false), "ff4ea3", "Apply commits the selected ship colour")
	context.expect_equal(client.preferred_ship_pattern, ShipAppearanceScript.LEOPARD, "Apply commits the selected hull pattern")
	context.expect_false(client.ship_color_popup.visible, "Apply closes the roster colour picker")
	context.expect_true(not client.ship_color_blocker.visible and client.lobby_panel.visible, "closing colour selection restores the waiting lobby")
	client._show_ship_color_popup()
	client._on_ship_pattern_selected(ShipAppearanceScript.PATTERNS.find(ShipAppearanceScript.ZEBRA))
	client._on_random_color_pressed()
	context.expect_equal(client.preferred_ship_pattern, ShipAppearanceScript.ZEBRA, "Random Colour applies the pending pattern while randomizing only the colour")
	client._show_lobby_options()
	context.expect_true(client.lobby_options_popup.visible and client.lobby_options_blocker.visible and not client.lobby_panel.visible, "match options behaves as a focused modal surface")
	client._hide_lobby_options()
	context.expect_true(not client.lobby_options_blocker.visible and client.lobby_panel.visible, "closing match options restores the waiting lobby")
	client.bridge.local_peer_id = 3
	client._rebuild_lobby_roster({"players": players, "leader_id": 2, "match_active": false}, false)
	context.expect_true(not (client.lobby_roster.get_child(1).get_node("ShipColor") as Button).disabled, "a non-leader human can edit their own roster colour")
	context.expect_true((client.lobby_roster.get_child(0).get_node("ShipColor") as Button).disabled, "the non-leader still cannot edit the host's colour")
	client.bridge.local_peer_id = 2
	client._rebuild_lobby_roster({"players": players, "leader_id": 2, "match_active": false}, true)
	context.expect_false(client.start_button.disabled, "leader can launch once all humans are ready")
	context.expect_equal(client.start_button.text, "Start Match", "ready multiplayer lobby uses ordinary start wording")
	var configurable_players: Array[Dictionary] = [
		{"peer_id": 2, "display_name": "Pilot 01", "spectator": false, "is_npc": false, "ready": false, "team_id": 1, "team_selection": 0},
		{"peer_id": ServerLobby.NPC_PEER_ID_BASE + 1, "display_name": "NPC 01", "spectator": false, "is_npc": true, "npc_difficulty": NpcPilotController.Difficulty.SKILLED, "ready": true, "team_id": 2, "team_selection": 2},
		{"peer_id": 3, "display_name": "Pilot 02", "spectator": false, "is_npc": false, "ready": false, "team_id": 1, "team_selection": 1},
	]
	client._on_lobby_state({"players": configurable_players, "leader_id": 2, "player_limit": 3, "server_capacity": 32, "npc_count": 1, "ready_human_count": 0, "all_humans_ready": false, "npcs_enabled": true, "default_npc_difficulty": NpcPilotController.Difficulty.INSANE, "game_mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "team_count": 2, "team_setup_valid": true, "team_setup_error": "", "random_spawn_powerups": true, "random_powerup_interval_seconds": 12.0, "random_powerups_permanent": true, "overtime_start_seconds": 75.0, "match_active": false, "rounds_to_win": 3})
	var difficulty_control := client.lobby_roster.get_child(2).get_node("NpcDifficulty") as OptionButton
	context.expect_true(difficulty_control != null, "each waiting NPC renders an individual difficulty dropdown")
	context.expect_equal(difficulty_control.item_count, 5, "NPC dropdown exposes passive through insane")
	context.expect_equal(difficulty_control.get_selected_id(), NpcPilotController.Difficulty.SKILLED, "NPC dropdown reflects authoritative per-NPC difficulty")
	context.expect_false(difficulty_control.disabled, "lobby leader may edit an NPC difficulty before launch")
	context.expect_equal(client.npc_all_difficulty_control.get_selected_id(), NpcPilotController.Difficulty.INSANE, "bulk NPC dropdown reflects the authoritative lobby setting")
	context.expect_false(client.npc_all_difficulty_control.disabled, "bulk NPC difficulty remains editable for the lobby leader")
	context.expect_approx(client.powerup_interval_control.value, 12.0, "lobby renders the authoritative random drop interval")
	context.expect_true(client.powerups_permanent_button.button_pressed, "lobby renders authoritative drop permanence")
	context.expect_approx(client.overtime_start_control.value, 75.0, "lobby renders the authoritative overtime start")
	context.expect_equal(client.game_mode_control.get_selected_id(), GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "lobby renders the authoritative game-mode selection")
	context.expect_true(client.game_mode_note.text.contains("neutral center flag"), "game-mode selection explains its objective")
	context.expect_false(client.team_count_row.visible, "Team Capture the Flag remains a fixed two-team mode")
	context.expect_false((client.lobby_roster.get_child(0).get_node("TeamAssignment") as OptionButton).disabled, "host may assign a human team")
	context.expect_false((client.lobby_roster.get_child(2).get_node("TeamAssignment") as OptionButton).disabled, "host may assign an NPC team")
	client.bridge.local_peer_id = 3
	client._rebuild_lobby_roster({"players": configurable_players, "leader_id": 2, "game_mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "team_count": 2, "match_active": false}, false)
	context.expect_true((client.lobby_roster.get_child(0).get_node("TeamAssignment") as OptionButton).disabled, "non-host cannot change another human's team")
	context.expect_false((client.lobby_roster.get_child(2).get_node("TeamAssignment") as OptionButton).disabled, "non-host may assign an NPC team")
	context.expect_false((client.lobby_roster.get_child(1).get_node("TeamAssignment") as OptionButton).disabled, "non-host may assign their own team")
	client.bridge.local_peer_id = 2
	client._on_lobby_state({"players": configurable_players, "leader_id": 2, "player_limit": 4, "server_capacity": 32, "npc_count": 1, "ready_human_count": 0, "all_humans_ready": false, "npcs_enabled": true, "game_mode": GameModeRules.Mode.TEAM_DEATH_MATCH, "team_count": 4, "team_setup_valid": false, "team_setup_error": "Every configured team needs at least one participant.", "match_active": false, "rounds_to_win": 3})
	context.expect_true(client.team_count_row.visible, "Team Death Match reveals the team-count option")
	context.expect_equal(int(client.team_count_control.value), 4, "team-count option reflects authoritative lobby state")
	context.expect_true(client.start_button.disabled and client.start_button.text == "Configure All Teams", "host cannot launch until every configured team is populated")
	var solo_player: Array[Dictionary] = [{"peer_id": 2, "display_name": "Pilot 01", "spectator": false, "is_npc": false, "ready": true}]
	client._on_lobby_state({"players": solo_player, "leader_id": 2, "player_limit": 4, "server_capacity": 32, "npc_count": 0, "ready_human_count": 1, "all_humans_ready": true, "npcs_enabled": false, "match_active": false, "rounds_to_win": 3})
	context.expect_true(client.start_button.disabled and client.start_button.text == "Enable NPCs to Start Solo", "solo human is directed to enable NPCs")
	client._on_lobby_state({"players": solo_player, "leader_id": 2, "player_limit": 4, "server_capacity": 32, "npc_count": 0, "ready_human_count": 1, "all_humans_ready": true, "npcs_enabled": true, "match_active": false, "rounds_to_win": 3})
	context.expect_false(client.start_button.disabled, "ready solo human may start after enabling NPCs")
	context.expect_equal(client.start_button.text, "Start Match with NPCs", "solo NPC launch uses descriptive wording")
	client._on_match_event(&"STATE_CHANGED", 0, {"state_name": "DRAFT", "round_number": 1, "heat_number": 0, "builds": {2: {}}})
	client._show_draft_offer({"offer_token": "test", "card_ids": [&"phase_thrusters", &"blink_capacitor", &"beam_emitter", &"prismatic_lance", &"zero_point_loader"], "deadline_tick": 1800})
	var first_draft_card := client.draft_buttons[0] as Button
	context.expect_true(first_draft_card.get_node_or_null("CardContent/Details/CardName") != null, "draft choices expose a structured and scannable content hierarchy")
	context.expect_true(first_draft_card.has_theme_stylebox_override(&"focus"), "draft choices expose a dedicated focus treatment")
	context.expect_true(client.network_world.visible and client.network_world.process_mode != Node.PROCESS_MODE_DISABLED, "match start reactivates world rendering and prediction")
	context.expect_equal(client.network_world.local_peer_id, 2, "match start retains local identity for movement and predicted shots")
	client.network_world._on_snapshot({"server_tick": 1, "acknowledged_input": 0, "states": [
		{"peer_id": ServerLobby.NPC_PEER_ID_BASE + 1, "position": Vector2(400.0, 400.0), "velocity": Vector2.ZERO, "aim_angle": 0.0, "health": 0.0, "shield": 0.0, "ammunition": 0, "alive": false, "shielding": false},
	]})
	context.expect_false((client.network_world.ships[ServerLobby.NPC_PEER_ID_BASE + 1] as SandboxShip).visible, "inactive NPC markers remain hidden during the initial draft")
	context.expect_false(client.network_world.arena.show_spawn_anchors, "production arena never exposes internal spawn anchors")
	client._on_match_event(&"OBJECTIVE_UPDATED", 2, {"objective": {"active": true, "mode": GameModeRules.Mode.KING_OF_THE_HILL, "position": Vector2(800.0, 600.0), "zone_radius": GameModeRules.OBJECTIVE_ZONE_RADIUS, "controller_id": 2, "progress": {2: 7.5}, "target_seconds": 20.0}})
	context.expect_equal(int(client.network_world.arena.objective_state.controller_id), 2, "live objective updates reach the arena presentation")
	context.expect_true(client._objective_status_text().contains("7.5/20s"), "combat HUD reports live hill-control progress")
	var overtime_hill := Vector2(800.0, 600.0)
	client.network_world.match_payload["overtime_center"] = overtime_hill
	client.network_world.match_payload["overtime_minimum_radius"] = GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS
	client.network_world.match_payload["overtime_start_tick"] = 0
	client.network_world.controls_enabled = true
	client.network_world.latest_server_tick = roundi(
		GameConstants.OVERTIME_SHRINK_SECONDS * GameConstants.PHYSICS_TICKS_PER_SECOND
	)
	client.network_world._update_overtime_presentation()
	context.expect_equal(client.network_world.arena.overtime_center, overtime_hill, "client overtime rendering follows the authoritative hill center")
	context.expect_approx(client.network_world.arena.overtime_radius, GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS, "client renders the larger minimum KOTH overtime radius")
	client.latest_match_payload["game_mode"] = GameModeRules.Mode.KING_OF_THE_HILL
	client.latest_match_payload["participant_peer_ids"] = [2, 3]
	client.latest_match_payload["scores"] = {2: {"heat_wins": 0, "round_wins": 0, "kills": 0}, 3: {"heat_wins": 0, "round_wins": 0, "kills": 0}}
	client.latest_match_payload["objective"] = {"mode": GameModeRules.Mode.KING_OF_THE_HILL, "controller_id": 0, "progress": {2: 7.5, 3: 3.0}, "target_seconds": 20.0}
	context.expect_true(client._objective_status_text().contains("LEADER") and client._objective_status_text().contains("7.5/20s"), "contested hill HUD preserves and identifies the leading cumulative score")
	client._set_scoreboard_open(true)
	var hill_time := client.scoreboard_rows_container.get_child(0).find_child("HillTime", true, false) as Label
	context.expect_true(client.scoreboard_hill_heading.visible and hill_time != null, "King of the Hill scoreboard exposes a dedicated live hill-time column")
	context.expect_equal(hill_time.text, "7.5s", "King of the Hill scoreboard displays cumulative control time")
	client._set_scoreboard_open(false)
	client.latest_match_payload["respawn_deadlines"] = {2: 302}
	client.network_world.latest_server_tick = 2
	context.expect_equal(client._objective_status_text(), "RESPAWN 5.0s", "combat HUD shows the local five-second objective respawn countdown")
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
	client.latest_match_payload = {"state_name": "ACTIVE_HEAT", "entered_tick": 0, "deadline_tick": 900, "overtime_start_tick": 3600, "alive_peer_ids": [2, 3], "participant_peer_ids": [2, 3], "players": [{"peer_id": 2, "display_name": "Local Ace", "ship_color": "42e8ff"}, {"peer_id": 3, "display_name": "Rival Pilot", "ship_color": "ff5f7f"}], "scores": {2: {"heat_wins": 1, "round_wins": 1, "kills": 4}, 3: {"heat_wins": 0, "round_wins": 0, "kills": 2}}, "builds": {2: {&"heavy_rounds": 2}, 3: {&"glass_reactor": 2}}, "round_number": 2, "heat_number": 3, "map_id": &"riftline", "map_name": "Riftline"}
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
	context.expect_true(client.network_world.match_status_label.text.contains("ACTIVE HEAT") and client.network_world.match_status_label.text.contains("ROUND 2 / HEAT 3"), "compact upper-left HUD carries match state and clearly labeled round details")
	context.expect_equal(client.network_world.arena.map_id, &"riftline", "client rebuilds the arena from the authoritative map ID")
	context.expect_true(client.network_world.match_status_label.text.contains("RIFTLINE"), "combat HUD identifies the active round map")
	var local_ship := client.network_world.ships[2] as SandboxShip
	local_ship.combatant.alive = false
	local_ship.combatant.health = 0.0
	local_ship.combatant.shield.energy = 64.0
	client.network_world._update_spectator_target()
	client.network_world._update_diagnostics()
	context.expect_equal(client.network_world.shield_bar.value, 0.0, "eliminated spectator HUD clears shield energy that remained at death")
	context.expect_equal(client.network_world.resources_label.text, "SHIP ELIMINATED", "eliminated spectator HUD replaces resource totals with the elimination state")
	local_ship.combatant.alive = true
	local_ship.combatant.health = 100.0
	local_ship.combatant.shield.energy = 100.0
	client.network_world._update_spectator_target()
	client.network_world._update_diagnostics()
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
	client._on_match_event(&"PLAYER_ELIMINATED", 302, {"peer_ids": [3], "eliminations": [{"killer_id": 2, "victim_id": 3, "reason": "combat"}], "reason": "combat", "scores": {2: {"heat_wins": 1, "round_wins": 1, "kills": 5}, 3: {"heat_wins": 0, "round_wins": 0, "kills": 2}}})
	context.expect_equal(client.network_world.kill_feed.entries.size(), 1, "reliable elimination event adds one top-right kill-feed entry")
	var kill_feed_entry := client.network_world.kill_feed.entries[0].node as PanelContainer
	context.expect_equal(int(kill_feed_entry.get_meta("killer_id")), 2, "kill-feed entry retains the killer identity")
	context.expect_equal(int(kill_feed_entry.get_meta("victim_id")), 3, "kill-feed entry retains the victim identity")
	context.expect_true(bool(kill_feed_entry.get_meta("local_involved")), "kill-feed highlights an elimination involving the local pilot")
	context.expect_equal((kill_feed_entry.get_child(0).get_child(0) as Label).text, "Local Ace", "kill-feed resolves the killer's immutable match name")
	context.expect_equal((kill_feed_entry.get_child(0).get_child(2) as Label).text, "Rival Pilot", "kill-feed resolves the victim's immutable match name")
	client._on_match_event(&"PLAYER_ELIMINATED", 302, {"peer_ids": [3], "eliminations": [{"killer_id": 2, "victim_id": 3, "reason": "combat"}]})
	context.expect_equal(client.network_world.kill_feed.entries.size(), 1, "kill-feed deduplicates a repeated reliable elimination record")
	client.network_world.kill_feed.set_match_state("HEAT_RESULT")
	context.expect_true(client.network_world.kill_feed.visible and client.network_world.kill_feed.entries.size() == 1, "decisive elimination remains visible through the heat result")
	client.network_world.kill_feed.set_match_state("COUNTDOWN")
	context.expect_false(client.network_world.kill_feed.visible, "kill-feed hides for the next heat countdown")
	context.expect_empty(client.network_world.kill_feed.entries, "new heat countdown clears prior elimination entries")
	client.network_world.kill_feed.set_match_state("ACTIVE_HEAT")
	for feed_index in 7:
		client.network_world.add_kill_feed_entries([{"killer_id": 2, "victim_id": 100 + feed_index, "reason": "combat"}], 400 + feed_index)
	context.expect_equal(client.network_world.kill_feed.entries.size(), KillFeedScript.MAX_ENTRIES, "kill-feed remains bounded during a large elimination burst")
	context.expect_equal(int(client.network_world.kill_feed.entries[0].victim_id), 106, "newest elimination stays at the top of the feed")
	client.network_world.kill_feed.advance(KillFeedScript.ENTRY_LIFETIME_SECONDS + 0.1)
	context.expect_empty(client.network_world.kill_feed.entries, "kill-feed entries expire after their display lifetime")
	client._update_scoreboard()
	live_kills = client.scoreboard_rows_container.get_child(0).find_child("MatchKills", true, false) as Label
	context.expect_equal(live_kills.text, "5", "live elimination score payload refreshes cached scoreboard rows immediately")
	context.expect_equal(client.scoreboard_rows_container.get_child_count(), 2, "scoreboard renders one structured row per match participant")
	context.expect_true(client.scoreboard_rows_container.get_child(0).get_meta("peer_id") in [2, 3], "scoreboard rows retain player identity")
	var scoreboard_build_cards := client.scoreboard_rows_container.find_child("ScoreboardBuildCards", true, false) as HFlowContainer
	context.expect_true(scoreboard_build_cards != null and scoreboard_build_cards.get_child_count() == 1, "scoreboard build renders rarity-styled card hover targets")
	var scoreboard_card_chip := scoreboard_build_cards.get_child(0) as Button
	context.expect_true(scoreboard_card_chip.focus_mode == Control.FOCUS_ALL and scoreboard_card_chip.has_theme_stylebox_override(&"focus"), "scoreboard card details are keyboard and controller discoverable")
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
	client.latest_match_payload = {"state_name": "MATCH_RESULT", "match_winner": 2, "participant_peer_ids": [1, 2], "scores": {1: {"heat_wins": 0, "round_wins": 3}, 2: {"heat_wins": 0, "round_wins": 3}}}
	context.expect_equal(client._result_peer_ids()[0], 2, "declared extension winner leads standings when total round wins are tied")
	client.latest_match_payload = {"state_name": "MATCH_RESULT", "match_winner": 2, "deadline_tick": -1, "participant_peer_ids": [2], "scores": {2: {"heat_wins": 0, "round_wins": 1, "kills": 7}}, "builds": {2: {&"heavy_rounds": 2}}, "round_number": 1, "heat_number": 2, "rounds_to_win": 1, "can_extend_match": true}
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
	context.expect_true(result_card_chip.focus_mode == Control.FOCUS_ALL and result_card_chip.has_theme_stylebox_override(&"focus"), "final-build card details are keyboard and controller discoverable")
	context.expect_true(result_card_chip.tooltip_text.contains("CARD STATS") and result_card_chip.tooltip_text.contains("Projectile Damage") and result_card_chip.tooltip_text.contains("×1.82 total"), "hover popup shows exact per-stack and compounded card statistics")
	var card_preview := result_card_chip._make_custom_tooltip(result_card_chip.tooltip_text) as PanelContainer
	context.expect_true(card_preview != null and card_preview.name == "CardPreview", "card hover builds a dedicated card-shaped preview instead of a generic text box")
	context.expect_equal(card_preview.get_meta("card_id"), &"heavy_rounds", "visual card preview retains the hovered card identity")
	context.expect_true(card_preview.custom_minimum_size.x >= 390.0, "visual card preview reserves a readable card-width composition")
	var preview_style := card_preview.get_theme_stylebox("panel") as StyleBoxFlat
	context.expect_approx(preview_style.border_color.r, client.card_catalog.get_card(&"heavy_rounds").rarity_color().r, "visual card preview border reflects card rarity")
	card_preview.free()
	context.expect_true(client.results_winner_label.text.contains(client._player_name(2).to_upper()), "champion plate names the winner independently of the standings table")
	context.expect_false(client.results_extend_button.disabled, "lobby leader receives an actionable five-more-rounds button")
	context.expect_equal(client.results_extend_button.text, "PLAY 5 MORE ROUNDS", "results screen clearly labels the match extension action")
	context.expect_true(client.results_extend_button.tooltip_text.contains("exactly five more rounds"), "match extension tooltip describes the fixed five-round limit")
	context.expect_equal(client.results_extend_button.action_mode, BaseButton.ACTION_MODE_BUTTON_PRESS, "match extension activates on mouse-down before the results layout can swallow its release action")
	context.expect_false(client.results_return_button.disabled, "lobby leader receives an actionable exit-to-lobby button")
	context.expect_equal(client.results_return_button.text, "EXIT TO LOBBY", "final screen replaces the automatic countdown with an explicit exit")
	client.results_extend_button.pressed.emit()
	context.expect_true(client._extend_match_requested, "five-more-rounds button dispatches the extension request")
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
	var disconnect_host_error: Error = client._start_hosted_server({"port": 17459, "max_players": 32, "rounds_to_win": 3, "server_name": "Disconnect Test Arena", "lobby_password": "test-lobby"})
	context.expect_equal(disconnect_host_error, OK, "host-disconnect acceptance path starts an embedded authority")
	client.bridge.role = NetworkBridge.Role.CLIENT
	client.bridge.latest_lobby_state = {"revision": 500, "match_active": false}
	client.connection_form_panel.visible = false
	client.lobby_panel.visible = true
	client.lobby_disconnect_button.pressed.emit()
	context.expect_true(client.connection_form_panel.visible and not client.lobby_panel.visible, "waiting-lobby Disconnect immediately returns to the connection menu")
	context.expect_equal(client.bridge.role, NetworkBridge.Role.NONE, "waiting-lobby Disconnect fully stops the client transport")
	context.expect_true(client._hosted_server_root == null and client._hosted_server_bridge == null, "waiting-lobby Disconnect stops and releases the embedded host")
	context.expect_empty(client.bridge.latest_lobby_state, "disconnect clears stale lobby revisions before a later reconnect")
	tree_parent.remove_child(client)
	client.free()
