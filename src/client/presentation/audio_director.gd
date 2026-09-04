class_name AudioDirector
extends Node

const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")

const MixPolicy = preload("res://src/client/presentation/audio_mix_policy.gd")

const MUSIC_DIRECTORY: String = "res://assets/audio/music"
const GAMEPLAY_MUSIC_DIRECTORY: String = "res://assets/audio/music/gameplay"
const SFX_DIRECTORY: String = "res://assets/audio/sfx"
const SETTINGS_PATH: String = "user://super_star_fighter_settings.cfg"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
const MENU_CROSSFADE_SECONDS: float = 3.0
const SFX_PLAYER_COUNT: int = 24
const WEAPON_VARIANT_COUNT: int = 3
const SFX_NAMES: Array[StringName] = [
	&"fire", &"beam_fire", &"reload", &"shield_on", &"shield_block", &"shield_break",
	&"damage", &"elimination", &"card_lock", &"countdown", &"overtime",
	&"round_win", &"match_win", &"projectile_impact", &"ricochet", &"mine_detonated",
	&"missile_launch", &"rebound", &"kinetic_vent", &"breakaway", &"afterburner", &"objective_gain", &"objective_loss", &"objective_neutral",
]

var menu_player: AudioStreamPlayer
var menu_crossfade_player: AudioStreamPlayer
var gameplay_player: AudioStreamPlayer
var win_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_streams: Dictionary = {}
var sfx_generated: Dictionary = {}
var weapon_stream_cache: Dictionary = {}
var gameplay_tracks: Array[AudioStream] = []
var gameplay_track_paths: Array[String] = []
var loaded_music_paths: Dictionary = {}
var current_context: StringName = &"silent"
var current_gameplay_track: int = -1
var master_volume_percent: float = 80.0
var music_volume_percent: float = 72.0
var sfx_volume_percent: float = 82.0
var muted: bool = false
var playback_enabled: bool = true
var music_duck_db: float = 0.0
var music_duck_hold: float = 0.0
var dropped_voices: int = 0
var stolen_voices: int = 0
var peak_active_voices: int = 0
var pending_music: Dictionary = {}
var desired_music_path: String = ""
var previous_objective: Dictionary = {}
var sfx_panners: Dictionary = {}
var _active_menu_player: AudioStreamPlayer
var _menu_crossfade_in_progress: bool = false
var _menu_crossfade_elapsed: float = 0.0
var _menu_crossfade_outgoing: AudioStreamPlayer
var _menu_crossfade_incoming: AudioStreamPlayer
var _played_keys: Dictionary = {}
var _last_played_msec: Dictionary = {}


func _ready() -> void:
	playback_enabled = DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy"
	_ensure_audio_buses()
	_load_settings()
	menu_player = _make_player("MenuMusic", MUSIC_BUS)
	menu_crossfade_player = _make_player("MenuMusicCrossfade", MUSIC_BUS)
	_active_menu_player = menu_player
	gameplay_player = _make_player("GameplayMusic", MUSIC_BUS)
	win_player = _make_player("WinMusic", MUSIC_BUS)
	gameplay_player.finished.connect(_play_next_gameplay_track)
	for index in SFX_PLAYER_COUNT:
		sfx_players.append(_make_player("Sfx%02d" % index, _ensure_voice_bus(index)))
	_load_sfx()
	_load_music()
	_apply_volumes()
	var inventory := authored_music_inventory()
	print("SSF_AUDIO_READY menu=%d gameplay=%d win=%d" % [inventory.menu, inventory.gameplay, inventory.win])


func _exit_tree() -> void:
	_stop_menu_music()
	for player in [menu_player, menu_crossfade_player, gameplay_player, win_player]:
		if player != null:
			player.stop()
			player.stream = null
	for player in sfx_players:
		player.stop()
		player.stream = null
	for path in pending_music:
		ResourceLoader.load_threaded_get(path)
	pending_music.clear()
	gameplay_tracks.clear()
	gameplay_track_paths.clear()
	sfx_streams.clear()
	sfx_generated.clear()
	weapon_stream_cache.clear()


func set_context(context: StringName) -> void:
	if current_context == context:
		return
	if current_context in [&"menu", &"lobby"] and context in [&"menu", &"lobby"]:
		current_context = context
		return
	current_context = context
	_release_music_streams()
	desired_music_path = ""
	match context:
		&"menu", &"lobby":
			gameplay_player.stop()
			win_player.stop()
			_request_music(String(loaded_music_paths.get(&"menu", "")))
		&"gameplay":
			_stop_menu_music()
			win_player.stop()
			if not gameplay_track_paths.is_empty():
				_play_next_gameplay_track()
		&"win":
			_stop_menu_music()
			gameplay_player.stop()
			_request_music(String(loaded_music_paths.get(&"win", "")))
		_:
			_stop_menu_music()
			gameplay_player.stop()
			win_player.stop()


func _process(delta: float) -> void:
	_poll_music_requests()
	music_duck_hold = maxf(music_duck_hold - maxf(delta, 0.0), 0.0)
	var target := MixPolicy.MUSIC_DUCK_DB if music_duck_hold > 0.0 else 0.0
	var next_duck := move_toward(music_duck_db, target, maxf(delta, 0.0) * (175.0 if target < music_duck_db else 20.0))
	if not is_equal_approx(next_duck, music_duck_db):
		music_duck_db = next_duck
		_apply_music_volume()
	if not playback_enabled or current_context not in [&"menu", &"lobby"]:
		return
	if _menu_crossfade_in_progress:
		_step_menu_crossfade(delta)
		return
	if _active_menu_player == null or not _active_menu_player.playing:
		return
	var stream := _active_menu_player.stream
	if stream == null or stream.get_length() <= MENU_CROSSFADE_SECONDS:
		return
	if _active_menu_player.get_playback_position() >= stream.get_length() - MENU_CROSSFADE_SECONDS:
		_begin_menu_crossfade()


func set_master_volume(value: float, save: bool = true) -> void:
	master_volume_percent = clampf(value, 0.0, 100.0)
	_apply_volumes()
	if save:
		_save_settings()


func set_music_volume(value: float, save: bool = true) -> void:
	music_volume_percent = clampf(value, 0.0, 100.0)
	_apply_volumes()
	if save:
		_save_settings()


func set_sfx_volume(value: float, save: bool = true) -> void:
	sfx_volume_percent = clampf(value, 0.0, 100.0)
	_apply_volumes()
	if save:
		_save_settings()


func set_muted(enabled: bool, save: bool = true) -> void:
	muted = enabled
	_apply_volumes()
	if save:
		_save_settings()


func play_sfx(event_name: StringName, unique_key: String = "", volume_db: float = 0.0, details: Dictionary = {}) -> void:
	if not SFX_NAMES.has(event_name) or not sfx_streams.has(event_name):
		return
	if not unique_key.is_empty():
		var full_key := "%s:%s" % [event_name, unique_key]
		if _played_keys.has(full_key):
			return
		_played_keys[full_key] = true
		if _played_keys.size() > 512:
			_played_keys.erase(_played_keys.keys()[0])
	var now := Time.get_ticks_msec()
	var cooldown_scope := String(event_name)
	if event_name in [&"damage", &"shield_on", &"shield_block", &"shield_break", &"elimination", &"reload"] and not unique_key.is_empty():
		cooldown_scope += ":" + unique_key.get_slice(":", 0)
	var cooldown := 35 if event_name in [&"fire", &"beam_fire", &"ricochet", &"rebound"] else 70
	if now - int(_last_played_msec.get(cooldown_scope, -1000)) < cooldown:
		return
	_last_played_msec[cooldown_scope] = now
	_trim_cooldowns()
	if not playback_enabled:
		return
	var local := bool(details.get("local", not details.has("position")))
	var priority: int = MixPolicy.priority(event_name, local)
	if not local and priority < 7 and details.has("position") and details.has("listener_position"):
		if (details.position as Vector2).distance_to(details.listener_position as Vector2) > 2200.0:
			return
	var group: StringName = &"important" if priority >= 7 else &"local" if local else &"remote_effect"
	var player := _acquire_sfx_player(priority, group)
	if player == null:
		return
	var panning := 0.0 if local else MixPolicy.pan(details.get("position", Vector2.ZERO), details.get("listener_position", Vector2.ZERO))
	_play_on_player(player, sfx_streams[event_name], randf_range(0.97, 1.03), volume_db + MixPolicy.gain_db(event_name, local), priority, group, panning)


func world_sfx_volume_db(source_position: Vector2, listener_position: Vector2) -> float:
	var distance_mix := clampf((source_position.distance_to(listener_position) - 120.0) / 1850.0, 0.0, 1.0)
	return lerpf(-1.5, -18.0, distance_mix)


func play_weapon_shot(
	profile,
	owner_id: int,
	shot_sequence: int,
	source_position: Vector2,
	listener_position: Vector2,
	is_local: bool
) -> void:
	if profile == null:
		return
	var full_key := "weapon:%d:%d" % [owner_id, shot_sequence]
	if _played_keys.has(full_key):
		return
	_played_keys[full_key] = true
	_trim_played_keys()
	var now := Time.get_ticks_msec()
	var cooldown_key := "weapon:%d:%s" % [owner_id, profile.family]
	var shots_per_second: float = maxf(WeaponSoundProfileScript.BASE_FIRE_RATE * profile.fire_rate_ratio, 0.25)
	var cooldown := clampi(roundi(450.0 / shots_per_second), 16, 70)
	if now - int(_last_played_msec.get(cooldown_key, -1000)) < cooldown:
		return
	_last_played_msec[cooldown_key] = now
	_trim_cooldowns()
	if not playback_enabled:
		return
	if not is_local and source_position.distance_to(listener_position) > 2200.0:
		return
	var priority := 5 if is_local else 1 + mini(profile.power_tier, 2)
	var group: StringName = &"local" if is_local else &"remote_weapon"
	var player := _acquire_sfx_player(priority, group)
	if player == null:
		return
	var variant := posmod(owner_id * 31 + shot_sequence * 17, WEAPON_VARIANT_COUNT)
	var stream := _weapon_stream(profile, variant)
	var pitch_offsets: Array[float] = [-0.018, 0.0, 0.015]
	var pitch: float = 1.0 - profile.power_amount * 0.035 - profile.modification_amount * 0.018 + pitch_offsets[variant]
	var volume_db: float = 0.5 + profile.power_amount * 0.8 if is_local else _remote_weapon_volume_db(source_position.distance_to(listener_position), profile.power_tier)
	_play_on_player(player, stream, pitch, volume_db - (3.0 if is_local else 7.0), priority, group, 0.0 if is_local else MixPolicy.pan(source_position, listener_position))


func reset_match_deduplication() -> void:
	previous_objective.clear()
	music_duck_hold = 0.0
	_played_keys.clear()
	_last_played_msec.clear()


func synthesized_placeholder_count() -> int:
	var count := 0
	for event_name in SFX_NAMES:
		if bool(sfx_generated.get(event_name, false)):
			count += 1
	return count


func current_gameplay_track_name() -> String:
	if current_context != &"gameplay" or current_gameplay_track < 0 or current_gameplay_track >= gameplay_track_paths.size():
		return ""
	return music_display_name(gameplay_track_paths[current_gameplay_track])


func authored_music_inventory() -> Dictionary:
	return {
		"menu": 1 if loaded_music_paths.has(&"menu") else 0,
		"gameplay": gameplay_tracks.size(),
		"win": 1 if loaded_music_paths.get(&"win", "").begins_with("res://") else 0,
	}


static func music_display_name(path: String) -> String:
	var file_name := path.get_file()
	while file_name.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
		file_name = file_name.get_basename()
	return file_name.replace("_", " ").replace("-", " ").capitalize()


func _ensure_audio_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	var sfx_bus_index := AudioServer.get_bus_index(SFX_BUS)
	var has_limiter := false
	for effect_index in AudioServer.get_bus_effect_count(sfx_bus_index):
		if AudioServer.get_bus_effect(sfx_bus_index, effect_index) is AudioEffectLimiter:
			has_limiter = true
			break
	if not has_limiter:
		AudioServer.add_bus_effect(sfx_bus_index, AudioEffectLimiter.new())
	var master := AudioServer.get_bus_index(&"Master")
	var master_limited := false
	for index in AudioServer.get_bus_effect_count(master):
		master_limited = master_limited or AudioServer.get_bus_effect(master, index) is AudioEffectLimiter
	if not master_limited:
		var output_limiter := AudioEffectLimiter.new()
		output_limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, output_limiter)


func _make_player(node_name: String, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	player.set_meta("sfx_priority", 0)
	player.set_meta("sfx_started_msec", 0)
	add_child(player)
	return player


func _acquire_sfx_player(priority: int, group: StringName = &"local") -> AudioStreamPlayer:
	var group_count := 0
	for voice in sfx_players:
		if voice.playing and voice.get_meta("sfx_group", &"") == group:
			group_count += 1
	if group_count >= MixPolicy.group_limit(group):
		dropped_voices += 1
		return null
	for player in sfx_players:
		if not player.playing:
			return player
	var candidate: AudioStreamPlayer
	var candidate_priority := 999
	var candidate_started := 9223372036854775807
	for player in sfx_players:
		var player_priority := int(player.get_meta("sfx_priority", 0))
		var player_started := int(player.get_meta("sfx_started_msec", 0))
		if player_priority > priority:
			continue
		if player_priority < candidate_priority or (player_priority == candidate_priority and player_started < candidate_started):
			candidate = player
			candidate_priority = player_priority
			candidate_started = player_started
	if candidate != null:
		candidate.stop()
		stolen_voices += 1
	else:
		dropped_voices += 1
	return candidate


func _play_on_player(
	player: AudioStreamPlayer,
	stream: AudioStream,
	pitch: float,
	volume_db: float,
	priority: int,
	group: StringName = &"local",
	pan: float = 0.0
) -> void:
	if player == null or stream == null:
		return
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.72, 1.35)
	player.volume_db = clampf(volume_db, -24.0, 2.0)
	player.set_meta("sfx_priority", priority)
	player.set_meta("sfx_group", group)
	player.set_meta("sfx_started_msec", Time.get_ticks_msec())
	if sfx_panners.has(player.bus):
		(sfx_panners[player.bus] as AudioEffectPanner).pan = clampf(pan, -0.8, 0.8)
	if priority >= 7:
		music_duck_hold = maxf(MixPolicy.DUCK_HOLD_SECONDS, minf(stream.get_length(), 0.8))
	player.play()
	var active := 0
	for voice in sfx_players:
		active += 1 if voice.playing else 0
	peak_active_voices = maxi(peak_active_voices, active)


func _remote_weapon_volume_db(distance: float, power_tier: int) -> float:
	var distance_mix := clampf((distance - 140.0) / 1900.0, 0.0, 1.0)
	return lerpf(-2.5, -17.0, distance_mix) + mini(power_tier, 3) * 0.45


func _trim_played_keys() -> void:
	while _played_keys.size() > 512:
		_played_keys.erase(_played_keys.keys()[0])


func _weapon_stream(profile, variant: int) -> AudioStream:
	var key := "%s:v%d" % [profile.cache_key(), variant]
	if weapon_stream_cache.has(key):
		var cached := weapon_stream_cache[key] as AudioStream
		weapon_stream_cache.erase(key)
		weapon_stream_cache[key] = cached
		return cached
	while weapon_stream_cache.size() >= MixPolicy.WEAPON_CACHE_LIMIT:
		weapon_stream_cache.erase(weapon_stream_cache.keys()[0])
	var override := _load_weapon_override(profile, variant)
	if override != null:
		weapon_stream_cache[key] = override
		return override
	var legacy_event := &"beam_fire" if profile.beam_weapon else &"fire"
	if not bool(sfx_generated.get(legacy_event, true)):
		var legacy_stream := sfx_streams.get(legacy_event) as AudioStream
		weapon_stream_cache[key] = legacy_stream
		return legacy_stream
	var generated := _synthesize_weapon(profile, variant)
	weapon_stream_cache[key] = generated
	return generated


func _load_weapon_override(profile, variant: int) -> AudioStream:
	var tier_names: Array[String] = ["base", "modified", "powerful", "extreme"]
	var stems: Array[String] = [
		"weapon_%s_%s_%02d" % [profile.family, tier_names[profile.power_tier], variant + 1],
		"weapon_%s_%02d" % [profile.family, variant + 1],
		"weapon_%s" % profile.family,
	]
	for stem in stems:
		var stream := _load_audio_override(stem)
		if stream != null:
			return stream
	return null


func _load_sfx() -> void:
	var tone_specs := {
		&"fire": [760.0, 110.0, 0.085], &"beam_fire": [1450.0, 310.0, 0.12], &"reload": [420.0, 850.0, 0.16],
		&"shield_on": [260.0, 620.0, 0.14], &"shield_block": [980.0, 420.0, 0.11],
		&"shield_break": [540.0, 90.0, 0.28], &"damage": [170.0, 80.0, 0.15],
		&"elimination": [360.0, 45.0, 0.42], &"card_lock": [620.0, 1240.0, 0.19],
		&"countdown": [440.0, 660.0, 0.12], &"overtime": [190.0, 380.0, 0.35],
		&"round_win": [520.0, 880.0, 0.34], &"match_win": [440.0, 1320.0, 0.55],
		&"projectile_impact": [310.0, 72.0, 0.13], &"ricochet": [1180.0, 540.0, 0.10],
		&"mine_detonated": [145.0, 42.0, 0.42], &"rebound": [1480.0, 680.0, 0.13],
		&"missile_launch": [185.0, 920.0, 0.32],
		&"kinetic_vent": [210.0, 1050.0, 0.24], &"breakaway": [330.0, 920.0, 0.22],
		&"afterburner": [185.0, 1180.0, 0.48],
		&"objective_gain": [760.0, 1520.0, 0.3], &"objective_loss": [620.0, 260.0, 0.3], &"objective_neutral": [660.0, 660.0, 0.24],
	}
	for event_name in SFX_NAMES:
		var override := _load_audio_override(String(event_name))
		if override != null:
			sfx_streams[event_name] = override
			sfx_generated[event_name] = false
			continue
		if event_name in [&"objective_gain", &"objective_loss"]:
			sfx_streams[event_name] = _synthesize_objective(event_name == &"objective_gain")
			sfx_generated[event_name] = true
			continue
		if event_name == &"afterburner":
			sfx_streams[event_name] = _synthesize_afterburner()
			sfx_generated[event_name] = true
			continue
		var spec := tone_specs[event_name] as Array
		sfx_streams[event_name] = _synthesize_tone(float(spec[0]), float(spec[1]), float(spec[2]))
		sfx_generated[event_name] = true


func _load_audio_override(base_name: String) -> AudioStream:
	for extension in ["wav", "ogg", "mp3"]:
		var path := "%s/%s.%s" % [SFX_DIRECTORY, base_name, extension]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


func _load_music() -> void:
	# Discover paths without loading every compressed PCM buffer at startup.
	var menu_path := _find_named_music("main_menu")
	if not menu_path.is_empty():
		loaded_music_paths[&"menu"] = menu_path
	var win_path := _find_named_music("win")
	loaded_music_paths[&"win"] = win_path if not win_path.is_empty() else "generated:victory_theme"
	var files: Array = Array(ResourceLoader.list_directory(GAMEPLAY_MUSIC_DIRECTORY))
	files.sort_custom(func(left: String, right: String) -> bool: return left.naturalnocasecmp_to(right) < 0)
	for file_name in files:
		if file_name.ends_with("/") or not _is_supported_audio_file(file_name):
			continue
		var path := "%s/%s" % [GAMEPLAY_MUSIC_DIRECTORY, file_name]
		if ResourceLoader.exists(path):
			gameplay_track_paths.append(path)
			gameplay_tracks.append(null)
			loaded_music_paths["gameplay_%02d" % gameplay_tracks.size()] = path


func _release_music_streams() -> void:
	_stop_menu_music()
	for player in [menu_player, menu_crossfade_player, gameplay_player, win_player]:
		player.stop()
		player.stream = null
	gameplay_tracks.fill(null)


func _request_music(path: String) -> void:
	desired_music_path = path
	if path.is_empty() or not playback_enabled:
		return
	if path.begins_with("generated:"):
		_install_music(_synthesize_victory_theme())
	elif not pending_music.has(path):
		var result := ResourceLoader.load_threaded_request(path, "AudioStream", false, ResourceLoader.CACHE_MODE_IGNORE)
		if result == OK:
			pending_music[path] = true


func _poll_music_requests() -> void:
	for path in pending_music.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var stream := ResourceLoader.load_threaded_get(path) as AudioStream
			pending_music.erase(path)
			if path == desired_music_path:
				_install_music(stream)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			pending_music.erase(path)


func _install_music(stream: AudioStream) -> void:
	if stream == null:
		return
	match current_context:
		&"menu", &"lobby":
			_set_stream_looping(stream, false)
			menu_player.stream = stream
			menu_crossfade_player.stream = stream
			_start_menu_music()
		&"gameplay":
			_set_stream_looping(stream, false)
			gameplay_tracks.fill(null)
			if current_gameplay_track >= 0 and current_gameplay_track < gameplay_tracks.size():
				gameplay_tracks[current_gameplay_track] = stream
			gameplay_player.stream = stream
			if playback_enabled:
				gameplay_player.play()
		&"win":
			_set_stream_looping(stream, true)
			win_player.stream = stream
			if playback_enabled:
				win_player.play()


## Synchronous fixture entry point; interactive context changes use the loader thread.
func prepare_music_now(context: StringName) -> void:
	set_context(context)
	if desired_music_path.is_empty():
		return
	var stream: AudioStream = _synthesize_victory_theme() if desired_music_path.begins_with("generated:") else ResourceLoader.load(desired_music_path, "AudioStream", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	_install_music(stream)


func _find_named_music(prefix: String) -> String:
	var files: Array = Array(ResourceLoader.list_directory(MUSIC_DIRECTORY))
	files.sort_custom(func(left: String, right: String) -> bool: return left.naturalnocasecmp_to(right) < 0)
	for file_name in files:
		if file_name.ends_with("/"):
			continue
		if file_name.to_lower().begins_with(prefix.to_lower() + ".") and _is_supported_audio_file(file_name):
			var path := "%s/%s" % [MUSIC_DIRECTORY, file_name]
			if ResourceLoader.exists(path):
				return path
	return ""


func _is_supported_audio_file(file_name: String) -> bool:
	return file_name.get_extension().to_lower() in ["mp3", "ogg", "wav"]


func _set_stream_looping(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = enabled
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = enabled
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if enabled else AudioStreamWAV.LOOP_DISABLED
		if enabled:
			wav.loop_begin = 0
			wav.loop_end = roundi(wav.get_length() * wav.mix_rate)


func _play_next_gameplay_track() -> void:
	if gameplay_track_paths.is_empty() or current_context != &"gameplay":
		return
	current_gameplay_track = (current_gameplay_track + 1) % gameplay_track_paths.size()
	gameplay_player.stop()
	gameplay_player.stream = null
	gameplay_tracks.fill(null)
	_request_music(gameplay_track_paths[current_gameplay_track])


func _start_menu_music() -> void:
	if not playback_enabled or menu_player.stream == null:
		return
	if menu_player.playing or menu_crossfade_player.playing:
		return
	_active_menu_player = menu_player
	_active_menu_player.volume_db = 0.0
	_active_menu_player.play()


func _stop_menu_music() -> void:
	_menu_crossfade_in_progress = false
	_menu_crossfade_elapsed = 0.0
	_menu_crossfade_outgoing = null
	_menu_crossfade_incoming = null
	for player in [menu_player, menu_crossfade_player]:
		if player != null:
			player.stop()
			player.volume_db = 0.0
	_active_menu_player = menu_player


func _begin_menu_crossfade() -> void:
	var outgoing := _active_menu_player
	var incoming := menu_crossfade_player if outgoing == menu_player else menu_player
	if incoming.stream == null:
		return
	_menu_crossfade_in_progress = true
	_menu_crossfade_elapsed = 0.0
	_menu_crossfade_outgoing = outgoing
	_menu_crossfade_incoming = incoming
	incoming.volume_db = linear_to_db(0.0001)
	incoming.play()


func _step_menu_crossfade(delta: float) -> void:
	_menu_crossfade_elapsed += maxf(delta, 0.0)
	var progress := clampf(_menu_crossfade_elapsed / MENU_CROSSFADE_SECONDS, 0.0, 1.0)
	_menu_crossfade_outgoing.volume_db = linear_to_db(maxf(sqrt(1.0 - progress), 0.0001))
	_menu_crossfade_incoming.volume_db = linear_to_db(maxf(sqrt(progress), 0.0001))
	if progress >= 1.0:
		_finish_menu_crossfade()


func _finish_menu_crossfade() -> void:
	_menu_crossfade_outgoing.stop()
	_menu_crossfade_outgoing.volume_db = 0.0
	_active_menu_player = _menu_crossfade_incoming
	_menu_crossfade_in_progress = false
	_menu_crossfade_elapsed = 0.0
	_menu_crossfade_outgoing = null
	_menu_crossfade_incoming = null


func _apply_volumes() -> void:
	_set_bus_percent(&"Master", master_volume_percent, muted)
	_apply_music_volume()
	_set_bus_percent(SFX_BUS, sfx_volume_percent, false)


func _set_bus_percent(bus_name: StringName, percent: float, mute_bus: bool) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var linear := clampf(percent / 100.0, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
	AudioServer.set_bus_mute(bus_index, mute_bus or percent <= 0.0)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume_percent = clampf(float(config.get_value("audio", "master", master_volume_percent)), 0.0, 100.0)
	music_volume_percent = clampf(float(config.get_value("audio", "music", music_volume_percent)), 0.0, 100.0)
	sfx_volume_percent = clampf(float(config.get_value("audio", "sfx", sfx_volume_percent)), 0.0, 100.0)
	muted = bool(config.get_value("audio", "muted", muted))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "master", master_volume_percent)
	config.set_value("audio", "music", music_volume_percent)
	config.set_value("audio", "sfx", sfx_volume_percent)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)


func _synthesize_weapon(profile, variant: int) -> AudioStreamWAV:
	var mix_rate := 22050
	var tier: int = profile.power_tier
	var duration: float = 0.10 + tier * 0.012
	match profile.family:
		WeaponSoundProfileScript.FAMILY_AUTOMATIC:
			duration = 0.064 + tier * 0.008
		WeaponSoundProfileScript.FAMILY_HEAVY:
			duration = 0.17 + tier * 0.026
		WeaponSoundProfileScript.FAMILY_RAIL:
			duration = 0.115 + tier * 0.014
		WeaponSoundProfileScript.FAMILY_SCATTER:
			duration = 0.135 + tier * 0.018
		WeaponSoundProfileScript.FAMILY_BEAM_PULSE:
			duration = 0.14 + tier * 0.015
		WeaponSoundProfileScript.FAMILY_BEAM_REPEATER:
			duration = 0.078 + tier * 0.009
		WeaponSoundProfileScript.FAMILY_BEAM_LANCE:
			duration = 0.21 + tier * 0.028
	var sample_count := maxi(roundi(duration * mix_rate), 1)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var seed := absi(hash("%s:%d" % [profile.cache_key(), variant])) + 1
	var noise_state := seed % 2147483647
	var primary_phase := 0.0
	var secondary_phase := 0.0
	var sub_phase := 0.0
	var peak := 0.001
	for index in sample_count:
		var progress := float(index) / float(sample_count)
		noise_state = int(posmod(noise_state * 1103515245 + 12345, 2147483647))
		var noise := float(noise_state) / 1073741823.5 - 1.0
		var start_hz := 820.0
		var end_hz := 115.0
		if profile.family == WeaponSoundProfileScript.FAMILY_AUTOMATIC:
			start_hz = 1040.0
			end_hz = 190.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_HEAVY:
			start_hz = 310.0
			end_hz = 62.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_RAIL:
			start_hz = 2450.0
			end_hz = 260.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_SCATTER:
			start_hz = 640.0
			end_hz = 82.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_PULSE:
			start_hz = 1720.0
			end_hz = 340.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_REPEATER:
			start_hz = 2260.0
			end_hz = 510.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_LANCE:
			start_hz = 1380.0
			end_hz = 185.0
		var variant_pitch := 1.0 + (variant - 1) * 0.035
		var primary_hz := lerpf(start_hz, end_hz, pow(progress, 0.72)) * variant_pitch
		var secondary_hz: float = primary_hz * (1.48 + profile.modification_amount * 0.18)
		var sub_hz := lerpf(105.0 - tier * 8.0, 48.0, progress)
		primary_phase += TAU * primary_hz / mix_rate
		secondary_phase += TAU * secondary_hz / mix_rate
		sub_phase += TAU * sub_hz / mix_rate
		var attack := minf(progress / (0.025 if profile.family == WeaponSoundProfileScript.FAMILY_BEAM_LANCE else 0.012), 1.0)
		var envelope := attack * pow(1.0 - progress, 1.45 if profile.beam_weapon else 1.9)
		var transient := noise * exp(-progress * (23.0 if profile.family == WeaponSoundProfileScript.FAMILY_SCATTER else 34.0))
		var body: float = sin(primary_phase) * 0.62 + sin(secondary_phase) * (0.10 + profile.modification_amount * 0.08)
		if profile.family == WeaponSoundProfileScript.FAMILY_AUTOMATIC:
			body = sin(primary_phase) * 0.50 + transient * 0.44
		elif profile.family == WeaponSoundProfileScript.FAMILY_HEAVY:
			body = sin(primary_phase) * 0.48 + sin(sub_phase) * (0.34 + tier * 0.035) + transient * 0.32
		elif profile.family == WeaponSoundProfileScript.FAMILY_RAIL:
			body = sin(primary_phase) * 0.50 + sin(secondary_phase) * 0.21 + transient * 0.38
		elif profile.family == WeaponSoundProfileScript.FAMILY_SCATTER:
			body = sin(primary_phase) * 0.38 + sin(secondary_phase * 0.73) * 0.18 + transient * (0.40 + minf(profile.projectile_count, 6) * 0.025)
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_PULSE:
			body = sin(primary_phase) * 0.52 + sin(secondary_phase) * 0.23 + sin(primary_phase * 3.0) * 0.10
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_REPEATER:
			body = sin(primary_phase) * 0.45 + sin(secondary_phase) * 0.26 + transient * 0.18
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_LANCE:
			body = sin(primary_phase) * 0.44 + sin(secondary_phase) * 0.20 + sin(sub_phase) * (0.20 + tier * 0.035) + noise * exp(-progress * 9.0) * 0.10
		var modifier_layer := 0.0
		if profile.pierce_count > 0:
			modifier_layer += sin(TAU * (2650.0 + variant * 110.0) * float(index) / mix_rate) * exp(-progress * 16.0) * minf(profile.pierce_count, 2) * 0.065
		if profile.ricochet_count > 0:
			modifier_layer += sin(TAU * (690.0 + profile.ricochet_count * 55.0) * float(index) / mix_rate) * sqrt(progress) * (1.0 - progress) * 0.18
		if profile.knockback_ratio > 0.05:
			modifier_layer += sin(TAU * 54.0 * float(index) / mix_rate) * pow(1.0 - progress, 2.2) * minf(profile.knockback_ratio, 1.8) * 0.16
		var tier_body := sin(sub_phase) * float(tier) * 0.045 * pow(1.0 - progress, 1.35)
		var sample: float = body * envelope + transient * 0.18 + modifier_layer + tier_body
		samples[index] = sample
		peak = maxf(peak, absf(sample))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var gain := 24500.0 / peak
	for index in sample_count:
		bytes.encode_s16(index * 2, clampi(roundi(samples[index] * gain), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _synthesize_tone(start_hz: float, end_hz: float, duration: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := maxi(roundi(duration * mix_rate), 1)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	for index in sample_count:
		var progress := float(index) / sample_count
		var frequency := lerpf(start_hz, end_hz, progress)
		phase += TAU * frequency / mix_rate
		var envelope := minf(progress / 0.08, 1.0) * pow(1.0 - progress, 1.8)
		bytes.encode_s16(index * 2, clampi(roundi(sin(phase) * envelope * 15000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _synthesize_afterburner() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.52
	var sample_count := roundi(duration * mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var primary_phase := 0.0
	var secondary_phase := 0.0
	var noise_state := 947_231
	var filtered_noise := 0.0
	for index in sample_count:
		var progress := float(index) / float(sample_count)
		var frequency := lerpf(74.0, 142.0, minf(progress / 0.42, 1.0))
		primary_phase += TAU * frequency / mix_rate
		secondary_phase += TAU * frequency * 2.03 / mix_rate
		noise_state = int(posmod(noise_state * 1103515245 + 12345, 2147483647))
		var noise := float(noise_state) / 1073741823.5 - 1.0
		filtered_noise = lerpf(filtered_noise, noise, 0.075)
		var attack := minf(progress / 0.028, 1.0)
		var release := pow(1.0 - progress, 0.72)
		var envelope := attack * release
		var ignition := noise * exp(-progress * 52.0) * 0.62
		var roar := sin(primary_phase) * 0.42 + sin(secondary_phase) * 0.16 + filtered_noise * 0.48
		var sample := (roar * envelope + ignition) * 0.72
		bytes.encode_s16(index * 2, clampi(roundi(sample * 26000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _synthesize_victory_theme() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 4.0
	var sample_count := roundi(duration * mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var notes: Array[float] = [261.63, 329.63, 392.0, 523.25, 659.25, 783.99, 1046.5, 783.99]
	for index in sample_count:
		var time := float(index) / mix_rate
		var note_index := mini(floori(time / 0.5), notes.size() - 1)
		var note_time := fmod(time, 0.5)
		var envelope := minf(note_time / 0.035, 1.0) * minf((0.5 - note_time) / 0.12, 1.0)
		var sample := sin(TAU * notes[note_index] * time) * 0.68 + sin(TAU * notes[note_index] * 1.5 * time) * 0.2
		bytes.encode_s16(index * 2, clampi(roundi(sample * envelope * 11000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	return stream


func _apply_music_volume() -> void:
	_set_bus_percent(MUSIC_BUS, music_volume_percent, false)
	var index := AudioServer.get_bus_index(MUSIC_BUS)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, AudioServer.get_bus_volume_db(index) + music_duck_db)


func _ensure_voice_bus(index: int) -> StringName:
	var bus_name := StringName("SSFVoice%02d" % index)
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, bus_name)
		AudioServer.set_bus_send(bus, SFX_BUS)
		AudioServer.add_bus_effect(bus, AudioEffectPanner.new())
	sfx_panners[bus_name] = AudioServer.get_bus_effect(bus, 0)
	return bus_name


func _trim_cooldowns() -> void:
	while _last_played_msec.size() > 512:
		_last_played_msec.erase(_last_played_msec.keys()[0])


func resident_music_bytes() -> int:
	var seen := {}
	var bytes := 0
	for player in [menu_player, gameplay_player, win_player]:
		if player.stream != null and not seen.has(player.stream):
			seen[player.stream] = true
			bytes += _stream_data_bytes(player.stream)
	return bytes


func _stream_data_bytes(stream: AudioStream) -> int:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).data.size()
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).data.size()
	if stream is AudioStreamOggVorbis:
		var sequence := (stream as AudioStreamOggVorbis).packet_sequence
		if sequence == null:
			return 0
		var bytes := 0
		for page in sequence.packet_data:
			for packet in page:
				bytes += packet.size()
		return bytes
	return 0


func observe_objective(objective: Dictionary, local_peer_id: int, teams: Dictionary = {}) -> void:
	if not bool(objective.get("active", false)):
		previous_objective.clear()
		return
	if previous_objective.is_empty():
		previous_objective = objective.duplicate(true)
		return # Joining or entering a heat establishes a baseline, not a cue.
	var previous_carrier := int(previous_objective.get("flag_carrier_id", 0))
	var carrier := int(objective.get("flag_carrier_id", 0))
	var previous_controller := int(previous_objective.get("controller_id", 0))
	var controller := int(objective.get("controller_id", 0))
	var cue: StringName = &""
	if carrier != previous_carrier:
		var local_team := int(teams.get(local_peer_id, teams.get(str(local_peer_id), 0)))
		var carrier_team := int(teams.get(carrier, teams.get(str(carrier), 0)))
		var friendly_carrier := carrier == local_peer_id or (local_team > 0 and carrier_team == local_team)
		cue = &"objective_neutral" if carrier == 0 else &"objective_gain" if friendly_carrier else &"objective_loss"
	elif controller != previous_controller:
		cue = &"objective_gain" if controller == local_peer_id else &"objective_loss" if previous_controller == local_peer_id else &""
	if cue != &"":
		# No unique key: the same ownership transition can legitimately recur.
		play_sfx(cue, "", -2.0)
	previous_objective = objective.duplicate(true)


func _synthesize_objective(ascending: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	var notes := [660.0, 880.0, 1320.0] if ascending else [880.0, 660.0, 330.0]
	for frequency in notes:
		bytes.append_array(_synthesize_tone(frequency, frequency, 0.12).data)
		var gap := PackedByteArray()
		gap.resize(882 * 2)
		bytes.append_array(gap)
	stream.data = bytes
	return stream


func set_objective_baseline(objective: Dictionary) -> void:
	previous_objective = objective.duplicate(true) if bool(objective.get("active", false)) else {}
