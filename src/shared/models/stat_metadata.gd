class_name StatMetadata
extends RefCounted

## One authoritative descriptor per numeric combat stat. Limits are guardrails,
## not balance targets. Dynamic depletion ceiling follows effective shield capacity.
const Descriptor = preload("res://src/shared/models/combat_stat_descriptor.gd")
const SPECIAL_FLAGS := {
	&"auto_repair": &"auto_repair_enabled", &"beam_weapon": &"beam_weapon",
	&"afterburner": &"afterburner_enabled", &"mine_layer": &"mine_layer_enabled",
	&"missile_launcher": &"missile_launcher_enabled", &"cloak": &"cloak_enabled",
	&"rebound_shield": &"rebound_shield_enabled", &"kinetic_vent": &"kinetic_vent_enabled",
	&"breakaway_thrusters": &"breakaway_thrusters_enabled",
}
const DEFINITIONS := {
	&"max_health": ["Max Health", "Hull", "", 10.0, 600.0, false, 1],
	&"max_speed": ["Max Speed", "Speed", "px/s", 100.0, 2400.0, false, 1],
	&"acceleration": ["Acceleration", "Acceleration", "px/s²", 100.0, 6000.0, false, 1],
	&"drag": ["Drag", "Drag", "px/s²", 100.0, 6000.0, false, 0],
	&"projectile_damage": ["Projectile Damage", "Damage", "", 1.0, 600.0, false, 1],
	&"fire_rate": ["Fire Rate", "Fire rate", "shots/s", 0.25, 20.0, false, 1],
	&"reload_duration": ["Reload Duration", "Reload", "s", 0.1, 8.0, false, -1],
	&"projectile_speed": ["Projectile Speed", "Shot speed", "px/s", 200.0, 4000.0, false, 1],
	&"projectile_spread_degrees": ["Projectile Spread Degrees", "Spread", "°", 0.0, 90.0, false, -1],
	&"projectile_lifetime": ["Projectile Lifetime", "Lifetime", "s", 0.1, 12.0, false, 1],
	&"projectile_knockback": ["Projectile Knockback", "Knockback", "px/s", 0.0, 1800.0, false, 1],
	&"afterburner_impulse": ["Afterburner Impulse", "Boost impulse", "px/s", 50.0, 1800.0, false, 1],
	&"afterburner_duration": ["Afterburner Duration", "Boost duration", "s", 0.1, 3.0, false, 1],
	&"afterburner_cooldown": ["Afterburner Cooldown", "Boost cooldown", "s", 0.5, 20.0, false, -1],
	&"afterburner_speed_multiplier": ["Afterburner Speed Multiplier", "Boost speed", "×", 1.0, 4.0, false, 1],
	&"afterburner_acceleration_multiplier": ["Afterburner Acceleration Multiplier", "Boost acceleration", "×", 1.0, 6.0, false, 1],
	&"shield_capacity": ["Shield Capacity", "Shield", "", 5.0, 600.0, false, 1],
	&"shield_regeneration": ["Shield Regeneration", "Shield regen", "/s", 1.0, 400.0, false, 1],
	&"shield_continuous_drain": ["Shield Continuous Drain", "Shield drain", "/s", 0.25, 400.0, false, -1],
	&"shield_regeneration_delay": ["Shield Regeneration Delay", "Regen delay", "s", 0.05, 8.0, false, -1],
	&"shield_arc_degrees": ["Shield Arc Degrees", "Shield arc", "°", 30.0, 360.0, false, 1],
	&"shield_block_cost": ["Shield Block Cost", "Block cost", "", 1.0, 200.0, false, -1],
	&"shield_depletion_threshold": ["Shield Depletion Threshold", "Break threshold", "", 1.0, 600.0, false, -1, &"shield_capacity"],
	&"shield_acceleration_factor": ["Shield Acceleration Factor", "Shield thrust", "×", 0.1, 2.0, false, 1],
	&"shield_ram_damage": ["Shield Ram Damage", "Shield Ram Damage", "", 0.0, 300.0, false, 1],
	&"shield_ram_min_speed": ["Ram Speed Threshold", "Ram threshold", "px/s", 40.0, 1200.0, false, -1],
	&"shield_ram_cooldown": ["Shield Ram Cooldown", "Ram cooldown", "s", 0.15, 4.0, false, -1],
	&"shield_damage_heal_fraction": ["Blocked Damage Healing", "Block healing", "%", 0.0, 1.0, false, 1],
	&"rebound_damage_factor": ["Returned Damage", "Return damage", "%", 0.1, 1.0, false, 1],
	&"rebound_range_factor": ["Return Range", "Return range", "%", 0.1, 1.0, false, 1],
	&"kinetic_vent_impulse": ["Kinetic Vent Impulse", "Vent impulse", "px/s", 60.0, 1800.0, false, 1],
	&"breakaway_cooldown": ["Breakaway Cooldown", "Escape cooldown", "s", 1.0, 30.0, false, -1],
	&"auto_repair_delay": ["Auto Repair Delay", "Repair delay", "s", 0.1, 20.0, false, -1],
	&"auto_repair_rate": ["Auto Repair Rate", "Repair", "/s", 0.1, 400.0, false, 1],
	&"magazine_size": ["Magazine Size", "Magazine", "", 1, 128, true, 1],
	&"projectile_count": ["Projectile Count", "Projectiles", "", 1, 6, true, 1],
	&"pierce_count": ["Pierce Count", "Pierces", "", 0, 12, true, 1],
	&"ricochet_count": ["Ricochet Count", "Bounces", "", 0, 12, true, 1],
	&"mine_capacity": ["Mine Capacity", "Mine charges", "", 0, 1000, true, 1],
	&"missile_capacity": ["Missile Capacity", "Missile charges", "", 0, 1000, true, 1],
	&"cloak_capacity": ["Cloak Capacity", "Cloak charges", "", 0, 1000, true, 1],
}
static var _descriptors: Dictionary = {}
static var _numeric: Array[CombatStatDescriptor] = []
static var _floats: Array[StringName] = []
static var _integers: Array[StringName] = []
static var _lower: Array[StringName] = []
static var _flags: Array[StringName] = []


static func _ensure_loaded() -> void:
	if not _numeric.is_empty():
		return
	for property in DEFINITIONS:
		var descriptor := Descriptor.new(property, DEFINITIONS[property])
		_descriptors[property] = descriptor
		_numeric.append(descriptor)
		if descriptor.integer: _integers.append(property)
		else: _floats.append(property)
		if descriptor.polarity == Descriptor.Polarity.LOWER: _lower.append(property)
	for property in SPECIAL_FLAGS.values(): _flags.append(property)
	for list in [_numeric, _floats, _integers, _lower, _flags]: list.make_read_only()
	_descriptors.make_read_only()


static func descriptor(property: StringName) -> CombatStatDescriptor:
	_ensure_loaded()
	return _descriptors.get(property) as CombatStatDescriptor


static func numeric_descriptors() -> Array[CombatStatDescriptor]:
	_ensure_loaded()
	return _numeric


static func float_names() -> Array[StringName]:
	_ensure_loaded()
	return _floats


static func integer_names() -> Array[StringName]:
	_ensure_loaded()
	return _integers


static func lower_is_better() -> Array[StringName]:
	_ensure_loaded()
	return _lower


static func special_flags() -> Array[StringName]:
	_ensure_loaded()
	return _flags


static func label(property: StringName, compact: bool = false) -> String:
	var entry := descriptor(property)
	return String(property).replace("_", " ").capitalize() if entry == null else entry.short_label if compact else entry.label


static func format_value(property: StringName, value: float, signed: bool = false) -> String:
	var entry := descriptor(property)
	if entry != null:
		return entry.format_value(value, signed)
	return ("+" if signed and value >= 0.0 else "") + (str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.2f" % value)


static func change_kind(property: StringName, change: float) -> StringName:
	var entry := descriptor(property)
	if entry == null or entry.polarity == Descriptor.Polarity.CONTEXTUAL or is_zero_approx(change):
		return &"neutral"
	return &"benefit" if entry.is_beneficial(change) else &"drawback"
