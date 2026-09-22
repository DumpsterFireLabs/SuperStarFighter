class_name AudioDirector
extends Node

const SettingsStore = preload("res://src/client/settings_store.gd")

const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")

const MixPolicy = preload("res://src/client/presentation/audio_mix_policy.gd")

const MUSIC_DIRECTORY: String = "res://assets/audio/music"
const GAMEPLAY_MUSIC_DIRECTORY: String = "res://assets/audio/music/gameplay"
const SFX_DIRECTORY: String = "res://assets/audio/sfx"
const SETTINGS_PATH: String = SettingsStore.PATH
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
const Preparation = preload("res://src/client/presentation/weapon_audio_preparation.gd")
const Synthesis = preload("res://src/client/presentation/procedural_audio.gd")
var weapon_preparation := Preparation.new()
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
	weapon_preparation.close()
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
	weapon_preparation.poll()
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
		var override := Preparation._load_audio_override(String(event_name))
		if override != null:
			sfx_streams[event_name] = override
			sfx_generated[event_name] = false
			continue
		if event_name in [&"objective_gain", &"objective_loss"]:
			sfx_streams[event_name] = Synthesis._synthesize_objective(event_name == &"objective_gain")
			sfx_generated[event_name] = true
			continue
		if event_name == &"afterburner":
			sfx_streams[event_name] = Synthesis._synthesize_afterburner()
			sfx_generated[event_name] = true
			continue
		var spec := tone_specs[event_name] as Array
		sfx_streams[event_name] = Synthesis._synthesize_tone(float(spec[0]), float(spec[1]), float(spec[2]))
		sfx_generated[event_name] = true


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
		_install_music(Synthesis._synthesize_victory_theme())
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
	var stream: AudioStream = Synthesis._synthesize_victory_theme() if desired_music_path.begins_with("generated:") else ResourceLoader.load(desired_music_path, "AudioStream", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
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


func _save_settings() -> Error:
	return SettingsStore.update(func(config: ConfigFile) -> void:
		config.set_value("audio", "master", master_volume_percent)
		config.set_value("audio", "music", music_volume_percent)
		config.set_value("audio", "sfx", sfx_volume_percent)
		config.set_value("audio", "muted", muted)
	, SETTINGS_PATH)



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


func set_objective_baseline(objective: Dictionary) -> void:
	previous_objective = objective.duplicate(true) if bool(objective.get("active", false)) else {}


func _weapon_stream(profile: WeaponSoundProfile, variant: int) -> AudioStream:
	var event := &"beam_fire" if profile.beam_weapon else &"fire"
	return weapon_preparation.request(profile, variant, sfx_streams.get(event) as AudioStream, not bool(sfx_generated.get(event, true)))
