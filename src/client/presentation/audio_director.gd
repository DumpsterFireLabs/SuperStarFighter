class_name AudioDirector
extends Node

const MENU_MUSIC_PATH: String = "res://assets/audio/music/main_menu.mp3"
const GAMEPLAY_MUSIC_DIRECTORY: String = "res://assets/audio/music/gameplay"
const SFX_DIRECTORY: String = "res://assets/audio/sfx"
const SFX_NAMES: Array[StringName] = [
	&"fire", &"reload", &"shield_on", &"shield_block", &"shield_break",
	&"damage", &"elimination", &"card_lock", &"countdown", &"overtime",
	&"round_win", &"match_win",
]

var menu_player: AudioStreamPlayer
var gameplay_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_streams: Dictionary = {}
var gameplay_tracks: Array[AudioStream] = []
var current_context: StringName = &"silent"
var current_gameplay_track: int = -1
var _played_keys: Dictionary = {}
var _last_played_msec: Dictionary = {}


func _ready() -> void:
	menu_player = _make_player("MenuMusic", -10.0)
	gameplay_player = _make_player("GameplayMusic", -11.0)
	gameplay_player.finished.connect(_play_next_gameplay_track)
	for index in 12:
		sfx_players.append(_make_player("Sfx%02d" % index, -7.0))
	_load_sfx()
	_load_music()


func set_context(context: StringName) -> void:
	if current_context == context:
		return
	current_context = context
	match context:
		&"menu", &"lobby":
			gameplay_player.stop()
			if menu_player.stream != null and not menu_player.playing:
				menu_player.play()
		&"gameplay":
			menu_player.stop()
			if not gameplay_tracks.is_empty() and not gameplay_player.playing:
				_play_next_gameplay_track()
		_:
			menu_player.stop()
			gameplay_player.stop()


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
	var cooldown := 35 if event_name == &"fire" else 70
	if now - int(_last_played_msec.get(event_name, -1000)) < cooldown:
		return
	_last_played_msec[event_name] = now
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


func _make_player(node_name: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.volume_db = volume_db
	add_child(player)
	return player


func _load_sfx() -> void:
	var tone_specs := {
		&"fire": [760.0, 110.0, 0.085],
		&"reload": [420.0, 850.0, 0.16],
		&"shield_on": [260.0, 620.0, 0.14],
		&"shield_block": [980.0, 420.0, 0.11],
		&"shield_break": [540.0, 90.0, 0.28],
		&"damage": [170.0, 80.0, 0.15],
		&"elimination": [360.0, 45.0, 0.42],
		&"card_lock": [620.0, 1240.0, 0.19],
		&"countdown": [440.0, 660.0, 0.12],
		&"overtime": [190.0, 380.0, 0.35],
		&"round_win": [520.0, 880.0, 0.34],
		&"match_win": [440.0, 1320.0, 0.55],
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
	if ResourceLoader.exists(MENU_MUSIC_PATH):
		menu_player.stream = load(MENU_MUSIC_PATH) as AudioStream
		_set_stream_looping(menu_player.stream, true)
	var directory := DirAccess.open(GAMEPLAY_MUSIC_DIRECTORY)
	if directory == null:
		return
	var files := directory.get_files()
	files.sort()
	for file_name in files:
		if file_name.get_extension().to_lower() not in ["mp3", "ogg", "wav"]:
			continue
		var stream := load("%s/%s" % [GAMEPLAY_MUSIC_DIRECTORY, file_name]) as AudioStream
		if stream != null:
			_set_stream_looping(stream, false)
			gameplay_tracks.append(stream)


func _set_stream_looping(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = enabled
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = enabled
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if enabled else AudioStreamWAV.LOOP_DISABLED


func _play_next_gameplay_track() -> void:
	if gameplay_tracks.is_empty() or current_context != &"gameplay":
		return
	current_gameplay_track = (current_gameplay_track + 1) % gameplay_tracks.size()
	gameplay_player.stream = gameplay_tracks[current_gameplay_track]
	gameplay_player.play()


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
		var sample := clampi(roundi(sin(phase) * envelope * 15000.0), -32768, 32767)
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream
