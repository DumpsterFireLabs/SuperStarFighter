class_name ArenaEffectRules
extends RefCounted

const OFF := 0
const SIGNATURE := 1
const CUSTOM := 2
const SOLAR := 1
const CARGO := 2
const DOORS := 4
const DEFAULT := {"mode": OFF, "mask": 7, "frequency": 1, "strength": 1}

static func valid(settings: Dictionary) -> bool:
	if settings.size() != DEFAULT.size(): return false
	for key in DEFAULT:
		if not settings.has(key) or typeof(settings[key]) != TYPE_INT: return false
	return settings.mode >= OFF and settings.mode <= CUSTOM and settings.mask >= 0 and settings.mask <= 7 and settings.frequency >= 0 and settings.frequency <= 2 and settings.strength >= 0 and settings.strength <= 2

static func enabled(settings: Dictionary, map_id: StringName) -> int:
	if int(settings.get("mode", OFF)) == OFF: return 0
	var compatible := 0
	match map_id:
		&"twin_suns": compatible = SOLAR
		&"dead_freight": compatible = CARGO
		&"switchyard": compatible = DOORS
	return compatible & int(settings.get("mask", 7)) if int(settings.mode) == CUSTOM else compatible

static func interval(settings: Dictionary) -> float:
	return [24.0, 18.0, 12.0][int(settings.frequency)]

static func damage(settings: Dictionary) -> float:
	return [8.0, 16.0, 28.0][int(settings.strength)]
