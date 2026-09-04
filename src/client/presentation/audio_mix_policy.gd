extends RefCounted

const REMOTE_WEAPON_VOICES: int = 8
const REMOTE_EFFECT_VOICES: int = 6
const WEAPON_CACHE_LIMIT: int = 96
const MUSIC_DUCK_DB: float = -7.0
const DUCK_HOLD_SECONDS: float = 0.24


static func pan(source: Vector2, listener: Vector2) -> float:
	return clampf((source.x - listener.x) / 900.0, -0.8, 0.8)


static func priority(event: StringName, local: bool) -> int:
	if event in [&"objective_gain", &"objective_loss", &"objective_neutral", &"countdown", &"overtime", &"round_win", &"match_win", &"card_lock"]:
		return 8
	if local and event in [&"damage", &"shield_block", &"shield_break", &"elimination"]:
		return 7
	if local:
		return 5
	return 3 if event in [&"mine_detonated", &"elimination", &"shield_break"] else 2


static func gain_db(event: StringName, local: bool) -> float:
	if event in [&"projectile_impact", &"ricochet", &"rebound"]:
		return -7.0
	if event == &"mine_detonated":
		return -6.0 # Authored two-second explosion must not bury local feedback.
	if local and event in [&"shield_block", &"shield_break", &"damage"]:
		return -1.0
	return -3.0


static func group_limit(group: StringName) -> int:
	return REMOTE_WEAPON_VOICES if group == &"remote_weapon" else REMOTE_EFFECT_VOICES if group == &"remote_effect" else 24
