extends RefCounted

## Main-thread queue/cache; worker owns its copied profile and newly created stream.
## Playback, buses and scene nodes never cross into this owner.
const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")
const MixPolicy = preload("res://src/client/presentation/audio_mix_policy.gd")
const Synthesis = preload("res://src/client/presentation/procedural_audio.gd")
const SFX_DIRECTORY = "res://assets/audio/sfx"
var _cache: Dictionary = {}
var _requests: Dictionary = {}
var _thread := Thread.new()
var _job_key := ""

func stats() -> Dictionary:
	return {"cached": _cache.size(), "queued": _requests.size(), "working": _thread.is_started()}

func is_pending() -> bool:
	return not _requests.is_empty() or _thread.is_started()

func close() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
	_requests.clear()
	_cache.clear()
	_job_key = ""

func request(profile: WeaponSoundProfile, variant: int, fallback: AudioStream, authored: bool) -> AudioStream:
	var key := "%s:v%d" % [profile.cache_key(), variant]
	if _cache.has(key):
		var cached := _cache[key] as AudioStream
		_cache.erase(key)
		_cache[key] = cached
		return cached
	if key != _job_key and not _requests.has(key) and _requests.size() < MixPolicy.WEAPON_CACHE_LIMIT:
		var owned_profile := WeaponSoundProfileScript.new()
		for property in profile.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				owned_profile.set(property.name, profile.get(property.name))
		_requests[key] = [owned_profile, variant, fallback if authored else null]
	# Cold builds and pickups remain audible immediately. No filesystem access or
	# synthesis runs in the shot callback, including during cache churn.
	return fallback


func poll() -> void:
	if _thread.is_started():
		if _thread.is_alive():
			return
		var prepared := _thread.wait_to_finish() as AudioStream
		while _cache.size() >= MixPolicy.WEAPON_CACHE_LIMIT:
			_cache.erase(_cache.keys()[0])
		_cache[_job_key] = prepared
		_job_key = ""
	if _requests.is_empty():
		return
	_job_key = String(_requests.keys()[0])
	var request: Array = _requests[_job_key]
	_requests.erase(_job_key)
	if _thread.start(_prepare_weapon_stream.bind(request[0], request[1], request[2])) != OK:
		_job_key = ""


static func _prepare_weapon_stream(profile, variant: int, legacy: AudioStream) -> AudioStream:
	var override := _load_weapon_override(profile, variant)
	if override != null:
		return override
	return legacy if legacy != null else Synthesis._synthesize_weapon(profile, variant)


static func _load_weapon_override(profile, variant: int) -> AudioStream:
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


static func _load_audio_override(base_name: String) -> AudioStream:
	for extension in ["wav", "ogg", "mp3"]:
		var path := "%s/%s.%s" % [SFX_DIRECTORY, base_name, extension]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null
