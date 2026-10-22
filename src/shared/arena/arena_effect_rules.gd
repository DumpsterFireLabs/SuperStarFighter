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
	# Intrinsic hazards define their map, including in otherwise static matches.
	var intrinsic := ArenaLayout.intrinsic_effects(map_id)
	if intrinsic != 0: return intrinsic
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


## The actual rules for one selected map, including mechanics outside the
## optional event switch. Shared by lobby disclosure and regression coverage.
static func mechanics_summary(settings: Dictionary, map_id: StringName) -> String:
	var mechanics := PackedStringArray()
	var has_gravity := false
	var has_current := false
	var has_horizon := false
	for field in ArenaLayout.movement_fields(map_id):
		has_gravity = has_gravity or field.gravity_acceleration > 0.0
		has_current = has_current or (not field.is_gravity() and (field.flow_input_strength > 0.0 or field.maximum_speed_multiplier > 1.0))
		has_horizon = has_horizon or field.event_horizon_radius > 0.0
	if has_current: mechanics.append("current (intrinsic)")
	if has_gravity: mechanics.append("gravity (intrinsic)")
	if has_horizon: mechanics.append("lethal horizons (intrinsic)")
	if ArenaLayout.contact_damage(map_id) > 0.0: mechanics.append("surface burns (intrinsic)")
	var effects := enabled(settings, map_id)
	if effects & SOLAR:
		mechanics.append("solar flares (intrinsic)" if ArenaLayout.intrinsic_effects(map_id) & SOLAR else "solar pulses")
	if effects & CARGO: mechanics.append("destructible cargo")
	if effects & DOORS: mechanics.append("alternating doors")
	return ", ".join(mechanics) if not mechanics.is_empty() else "Static arena; no map hazards."
