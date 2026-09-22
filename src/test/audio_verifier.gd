extends SceneTree

var output_directory: String = "res://reports/audio-verification"
var record_auditions: bool = false
var audio: AudioDirector
var recorder: AudioEffectRecord
var phase: int = 0
var elapsed: float = 0.0
var phase_started_usec: int = 0
var emitted: int = -1
var cue_index: int = 0
var profiles: Array[WeaponSoundProfile] = []
var result: Dictionary = {}
var cue_events: Array[StringName] = [&"shield_on", &"shield_block", &"shield_break", &"damage", &"objective_gain", &"objective_loss", &"objective_neutral"]


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-output="):
			output_directory = argument.trim_prefix("--audio-output=")
		elif argument == "--record-audio":
			record_auditions = true
	measure.call_deferred()


func measure() -> void:
	DirAccess.make_dir_recursive_absolute(output_directory)
	var baseline := OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	audio = AudioDirector.new()
	root.add_child(audio)
	result = {"startup_usec": Time.get_ticks_usec() - started, "startup_static_delta": OS.get_static_memory_usage() - baseline, "startup_music_bytes": audio.resident_music_bytes(), "contexts": []}
	audio.playback_enabled = false
	for context in [&"menu", &"gameplay", &"win", &"silent"]:
		started = Time.get_ticks_usec()
		audio.prepare_music_now(context)
		result.contexts.append({"context": context, "fixture_load_usec": Time.get_ticks_usec() - started, "resident_music_bytes": audio.resident_music_bytes(), "static_delta": OS.get_static_memory_usage() - baseline})
	_write_json("memory.json", result)
	print("SSF_AUDIO_MEASURE=" + JSON.stringify(result))
	if not record_auditions:
		audio.free()
		quit()
		return
	seed(44104)
	Engine.max_fps = 60
	audio.set_master_volume(80, false)
	audio.set_music_volume(72, false)
	audio.set_sfx_volume(82, false)
	audio.set_muted(false, false)
	var catalog := CardCatalog.create_default()
	for card in [&"rapid_cycling", &"siege_cannon", &"rail_accelerant", &"scatter_array", &"beam_emitter", &"laser_repeater", &"singularity_lance", &"reality_shredder"]:
		profiles.append(WeaponSoundProfile.from_stats(StatSystem.derive({card: 1}, catalog), {card: 1}, catalog))
		for variant in 3:
			audio._weapon_stream(profiles.back(), variant)
	for cue in cue_events:
		(audio.sfx_streams[cue] as AudioStreamWAV).save_to_wav(output_directory.path_join(str(cue) + ".wav"))
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Master"), recorder)
	audio.playback_enabled = true
	phase = 1
	phase_started_usec = Time.get_ticks_usec()
	recorder.set_recording_active(true)
	print("SSF_AUDIO_RECORDING=cue_audition")


func _process(_delta: float) -> bool:
	if phase == 0:
		return false
	elapsed = (Time.get_ticks_usec() - phase_started_usec) / 1000000.0
	if phase == 1:
		var index := int(elapsed)
		if index != emitted and index < cue_events.size() + 2:
			emitted = index
			if index < cue_events.size():
				audio.play_sfx(cue_events[index], "audition:%d" % index, 0.0, {"local": true})
			else:
				var position := Vector2(-600 if index == cue_events.size() else 600, 0)
				audio.play_weapon_shot(profiles[0], index + 1, index + 1, position, Vector2.ZERO, false)
		if elapsed >= cue_events.size() + 2.8:
			_finish_recording("cue_audition.wav")
			audio.playback_enabled = false
			audio.prepare_music_now(&"gameplay")
			audio.playback_enabled = true
			audio.gameplay_player.play()
			audio.reset_match_deduplication()
			elapsed = 0.0
			emitted = -1
			cue_index = 0
			phase = 2
			phase_started_usec = Time.get_ticks_usec()
			recorder.set_recording_active(true)
			print("SSF_AUDIO_RECORDING=crowded_mix")
	elif phase == 2:
		var volley := int(elapsed * 8.0)
		if elapsed < 10.0 and volley != emitted:
			emitted = volley
			for owner in range(1, 33):
				var position := Vector2((owner % 8 - 4) * 190, (owner / 8 - 2) * 180)
				audio.play_weapon_shot(profiles[owner % profiles.size()], owner, volley + 100, position, Vector2.ZERO, owner == 1)
			if volley % 4 == 0:
				audio.play_sfx(&"mine_detonated", "mine:%d" % volley, -5, {"local": false, "position": Vector2(500, 0), "listener_position": Vector2.ZERO})
		if cue_index < cue_events.size() and elapsed >= 2.0 + cue_index * 1.3:
			audio.play_sfx(cue_events[cue_index], "priority:%d" % cue_index, 0, {"local": true})
			cue_index += 1
		if elapsed >= 12.0:
			_finish_recording("crowded_mix.wav")
			result["mix"] = {"peak_voices": audio.peak_active_voices, "dropped_voices": audio.dropped_voices, "stolen_voices": audio.stolen_voices, "weapon_cache_entries": audio.weapon_preparation.stats().cached, "final_duck_db": audio.music_duck_db}
			_write_json("memory.json", result)
			print("SSF_AUDIO_VERIFY_OK=" + JSON.stringify(result.mix))
			phase = 0
			AudioServer.remove_bus_effect(AudioServer.get_bus_index(&"Master"), AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"Master")) - 1)
			recorder = null
			profiles.clear()
			audio.free()
			audio = null
			_quit_after_mixer_drain()
	return false


func _finish_recording(name: String) -> void:
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	if recording == null or recording.data.is_empty():
		push_error("Audio bus recorder returned no samples")
		quit(1)
		return
	var error := recording.save_to_wav(output_directory.path_join(name))
	if error != OK:
		push_error("Could not save recorded audition: %s" % error)
		quit(1)


func _write_json(name: String, value: Dictionary) -> void:
	var file := FileAccess.open(output_directory.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))


func _quit_after_mixer_drain() -> void:
	# AudioStreamPlayer.stop queues work for the mixing thread. Let it retire
	# active playback instances after this frame before destroying AudioServer.
	await create_timer(0.15).timeout
	quit()
