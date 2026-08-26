class_name AudioDirector
extends Node

const MUSIC_DIRECTORY: String = "res://assets/audio/music"
const GAMEPLAY_MUSIC_DIRECTORY: String = "res://assets/audio/music/gameplay"
const SFX_DIRECTORY: String = "res://assets/audio/sfx"
const SETTINGS_PATH: String = "user://super_star_fighter_settings.cfg"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
const MENU_CROSSFADE_SECONDS: float = 3.0
const SFX_NAMES: Array[StringName] = [
	&"fire", &"beam_fire", &"reload", &"shield_on", &"shield_block", &"shield_break",
	&"damage", &"elimination", &"card_lock", &"countdown", &"overtime",
	&"round_win", &"match_win",
]

var menu_player: AudioStreamPlayer
var menu_crossfade_player: AudioStreamPlayer
var gameplay_player: AudioStreamPlayer
var win_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_streams: Dictionary = {}
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
	for index in 12:
		sfx_players.append(_make_player("Sfx%02d" % index, SFX_BUS))
	_load_sfx()
	_load_music()
	_apply_volumes()


func _exit_tree() -> void:
	_stop_menu_music()
	for player in [menu_player, menu_crossfade_player, gameplay_player, win_player]:
		if player != null:
			player.stop()
			player.stream = null
	for player in sfx_players:
		player.stop()
		player.stream = null
	gameplay_tracks.clear()
	gameplay_track_paths.clear()
	sfx_streams.clear()


func set_context(context: StringName) -> void:
	if current_context == context:
		return
	current_context = context
	match context:
		&"menu", &"lobby":
			gameplay_player.stop()
			win_player.stop()
			_start_menu_music()
		&"gameplay":
			_stop_menu_music()
			win_player.stop()
			if playback_enabled and not gameplay_tracks.is_empty() and not gameplay_player.playing:
				_play_next_gameplay_track()
		&"win":
			_stop_menu_music()
			gameplay_player.stop()
			if playback_enabled and win_player.stream != null and not win_player.playing:
				win_player.play()
		_:
			_stop_menu_music()
			gameplay_player.stop()
			win_player.stop()


func _process(delta: float) -> void:
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


func play_sfx(event_name: StringName, unique_key: String = "") -> void:
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
	var cooldown := 35 if event_name in [&"fire", &"beam_fire"] else 70
	if now - int(_last_played_msec.get(event_name, -1000)) < cooldown:
		return
	_last_played_msec[event_name] = now
	if not playback_enabled:
		return
	for player in sfx_players:
		if not player.playing:
			player.stream = sfx_streams[event_name]
			player.pitch_scale = randf_range(0.97, 1.03)
			player.play()
			return


func reset_match_deduplication() -> void:
	_played_keys.clear()
	_last_played_msec.clear()


func synthesized_placeholder_count() -> int:
	var count := 0
	for event_name in SFX_NAMES:
		if sfx_streams.get(event_name) is AudioStreamWAV:
			count += 1
	return count


func current_gameplay_track_name() -> String:
	if current_context != &"gameplay" or current_gameplay_track < 0 or current_gameplay_track >= gameplay_track_paths.size():
		return ""
	return music_display_name(gameplay_track_paths[current_gameplay_track])


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


func _make_player(node_name: String, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	add_child(player)
	return player


func _load_sfx() -> void:
	var tone_specs := {
		&"fire": [760.0, 110.0, 0.085], &"beam_fire": [1450.0, 310.0, 0.12], &"reload": [420.0, 850.0, 0.16],
		&"shield_on": [260.0, 620.0, 0.14], &"shield_block": [980.0, 420.0, 0.11],
		&"shield_break": [540.0, 90.0, 0.28], &"damage": [170.0, 80.0, 0.15],
		&"elimination": [360.0, 45.0, 0.42], &"card_lock": [620.0, 1240.0, 0.19],
		&"countdown": [440.0, 660.0, 0.12], &"overtime": [190.0, 380.0, 0.35],
		&"round_win": [520.0, 880.0, 0.34], &"match_win": [440.0, 1320.0, 0.55],
	}
	for event_name in SFX_NAMES:
		var override := _load_audio_override(String(event_name))
		if override != null:
			sfx_streams[event_name] = override
			continue
		var spec := tone_specs[event_name] as Array
		sfx_streams[event_name] = _synthesize_tone(float(spec[0]), float(spec[1]), float(spec[2]))


func _load_audio_override(base_name: String) -> AudioStream:
	for extension in ["wav", "ogg", "mp3"]:
		var path := "%s/%s.%s" % [SFX_DIRECTORY, base_name, extension]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


func _load_music() -> void:
	var menu_path := _find_named_music("main_menu")
	if not menu_path.is_empty():
		menu_player.stream = load(menu_path) as AudioStream
		_set_stream_looping(menu_player.stream, false)
		menu_crossfade_player.stream = menu_player.stream
		loaded_music_paths[&"menu"] = menu_path
	var win_path := _find_named_music("win")
	if not win_path.is_empty():
		win_player.stream = load(win_path) as AudioStream
		_set_stream_looping(win_player.stream, true)
		loaded_music_paths[&"win"] = win_path
	else:
		win_player.stream = _synthesize_victory_theme()
		loaded_music_paths[&"win"] = "generated:victory_theme"
	var directory := DirAccess.open(GAMEPLAY_MUSIC_DIRECTORY)
	if directory == null:
		return
	var files: Array = Array(directory.get_files())
	files.sort_custom(func(left: String, right: String) -> bool: return left.naturalnocasecmp_to(right) < 0)
	for file_name in files:
		if not _is_supported_audio_file(file_name):
			continue
		var path := "%s/%s" % [GAMEPLAY_MUSIC_DIRECTORY, file_name]
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream != null:
			_set_stream_looping(stream, false)
			gameplay_tracks.append(stream)
			gameplay_track_paths.append(path)
			loaded_music_paths["gameplay_%02d" % gameplay_tracks.size()] = path


func _find_named_music(prefix: String) -> String:
	var directory := DirAccess.open(MUSIC_DIRECTORY)
	if directory == null:
		return ""
	var files: Array = Array(directory.get_files())
	files.sort_custom(func(left: String, right: String) -> bool: return left.naturalnocasecmp_to(right) < 0)
	for file_name in files:
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
	if not playback_enabled or gameplay_tracks.is_empty() or current_context != &"gameplay":
		return
	current_gameplay_track = (current_gameplay_track + 1) % gameplay_tracks.size()
	gameplay_player.stream = gameplay_tracks[current_gameplay_track]
	gameplay_player.play()


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
	_set_bus_percent(MUSIC_BUS, music_volume_percent, false)
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
