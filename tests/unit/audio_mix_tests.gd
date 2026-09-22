extends RefCounted

const Policy = preload("res://src/client/presentation/audio_mix_policy.gd")


static func run(context: TestContext, parent: Node) -> void:
	var audio := AudioDirector.new()
	parent.add_child(audio)
	audio.playback_enabled = false
	context.expect_equal(audio.resident_music_bytes(), 0, "startup keeps music as paths rather than resident sample buffers")
	audio.prepare_music_now(&"menu")
	var menu := audio.menu_player.stream
	context.expect_true(audio.resident_music_bytes() > 0, "menu music becomes resident when requested")
	context.expect_equal(audio.menu_crossfade_player.stream, menu, "crossfade shares one menu buffer")
	audio.set_context(&"lobby")
	context.expect_equal(audio.menu_player.stream, menu, "entering lobby does not restart or reload menu music")
	audio.prepare_music_now(&"gameplay")
	context.expect_true(audio.menu_player.stream == null and audio.win_player.stream == null, "gameplay releases unrelated music buffers")
	var loaded_tracks := 0
	for stream in audio.gameplay_tracks:
		loaded_tracks += 1 if stream != null else 0
	context.expect_equal(loaded_tracks, 1, "only the current gameplay track is resident")
	audio.prepare_music_now(&"win")
	context.expect_true(audio.gameplay_player.stream == null and audio.win_player.stream != null, "victory exchanges the gameplay buffer for victory music")
	audio.set_context(&"silent")
	context.expect_equal(audio.resident_music_bytes(), 0, "silent context releases music")
	context.expect_approx(Policy.pan(Vector2(-450, 0), Vector2.ZERO), -0.5, "left-side source pans left")
	context.expect_approx(Policy.pan(Vector2(450, 0), Vector2.ZERO), 0.5, "right-side source pans right")
	context.expect_approx(Policy.pan(Vector2(4000, 0), Vector2.ZERO), 0.8, "direction keeps some signal in both ears")
	context.expect_true(Policy.priority(&"shield_block", true) > Policy.priority(&"mine_detonated", false), "local shield confirmation outranks distant explosions")
	context.expect_true(Policy.priority(&"damage", true) > Policy.priority(&"projectile_impact", false), "local hull damage outranks decorative impacts")
	var initial := {"active": true, "flag_carrier_id": 2}
	audio.observe_objective(initial, 2)
	context.expect_true(not audio._last_played_msec.has("objective_gain"), "initial objective snapshot does not replay an ownership cue")
	audio.observe_objective({"active": true, "flag_carrier_id": 3}, 2, {2: 1, 3: 2})
	context.expect_true(audio._last_played_msec.has("objective_loss"), "enemy flag pickup uses the loss warning")
	audio._last_played_msec.clear()
	audio.observe_objective({"active": true, "flag_carrier_id": 4}, 2, {2: 1, 4: 1})
	context.expect_true(audio._last_played_msec.has("objective_gain"), "teammate flag pickup uses the friendly gain cue")
	audio._last_played_msec.clear()
	audio.observe_objective({"active": true, "flag_carrier_id": 0}, 2, {2: 1, 4: 1})
	context.expect_true(audio._last_played_msec.has("objective_neutral"), "flag drop uses a neutral cue rather than claiming a team loss")
	audio.set_objective_baseline({"active": true, "flag_carrier_id": 0})
	audio._last_played_msec.clear()
	audio.observe_objective({"active": true, "flag_carrier_id": 2}, 2)
	context.expect_true(audio._last_played_msec.has("objective_gain"), "active-heat baseline preserves the first real flag pickup cue")
	audio.reset_match_deduplication()
	context.expect_true(audio.previous_objective.is_empty(), "rematch clears objective audio baseline")
	var profile: WeaponSoundProfile = WeaponSoundProfile.from_stats(CombatStats.create_base())
	var cached := audio._weapon_stream(profile, 0)
	context.expect_equal(cached, audio.sfx_streams[&"fire"], "cold weapon uses an already prepared audible fallback")
	context.expect_true(audio.weapon_stream_cache.is_empty(), "shot callback does not synthesize cold weapons")
	for repeat in 20:
		audio._weapon_stream(profile, 0)
	context.expect_equal(audio._weapon_requests.size(), 1, "cold requests are deduplicated")
	_finish_weapon_requests(audio)
	cached = audio._weapon_stream(profile, 0)
	context.expect_true(cached != audio.sfx_streams[&"fire"], "worker installs the generated weapon voice")
	for index in range(Policy.WEAPON_CACHE_LIMIT - 1):
		audio.weapon_stream_cache["fixture:%d" % index] = cached
	audio._weapon_stream(profile, 0)
	audio._weapon_stream(profile, 1)
	_finish_weapon_requests(audio)
	context.expect_equal(audio.weapon_stream_cache.size(), Policy.WEAPON_CACHE_LIMIT, "generated weapon cache remains bounded")
	context.expect_true(audio.weapon_stream_cache.has(profile.cache_key() + ":v0"), "recently used weapon survives cache eviction")
	context.expect_true(not audio.weapon_stream_cache.has("fixture:0"), "least-recently used weapon is evicted first")
	for index in Policy.REMOTE_WEAPON_VOICES:
		var voice := audio._acquire_sfx_player(1, &"remote_weapon")
		context.expect_true(voice != null, "remote weapon budget admits its configured voices")
		audio._play_on_player(voice, cached, 1.0, -24.0, 1, &"remote_weapon", -0.5)
	context.expect_true(audio._acquire_sfx_player(1, &"remote_weapon") == null, "remote volley overflow cannot consume protected feedback capacity")
	var important := audio._acquire_sfx_player(7, &"important")
	context.expect_true(important != null, "local feedback remains admissible under remote gunfire")
	audio._play_on_player(important, audio.sfx_streams[&"damage"], 1.0, -24.0, 7, &"important")
	context.expect_true(audio.music_duck_hold > 0.0, "local hit feedback requests a bounded music duck")
	audio._process(0.04)
	context.expect_true(audio.music_duck_db < -1.0, "music duck attacks promptly")
	audio._process(2.0)
	context.expect_approx(audio.music_duck_db, 0.0, "music returns to configured level after feedback")
	for player in audio.sfx_players:
		player.stop()
	audio.free()


static func _finish_weapon_requests(audio: AudioDirector) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (not audio._weapon_requests.is_empty() or audio._weapon_thread.is_started()) and Time.get_ticks_msec() < deadline:
		audio._poll_weapon_requests()
		OS.delay_msec(1)
