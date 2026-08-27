class_name CombatStats
extends RefCounted

var max_health: float = 100.0
var max_speed: float = 480.0
var acceleration: float = 900.0
var drag: float = 700.0

var projectile_damage: float = 25.0
var fire_rate: float = 4.0
var magazine_size: int = 8
var reload_duration: float = 1.5
var projectile_speed: float = 900.0
var projectile_count: int = 1
var projectile_spread_degrees: float = 0.0
var projectile_lifetime: float = GameConstants.PROJECTILE_LIFETIME_SECONDS
var pierce_count: int = 0
var ricochet_count: int = 0
var beam_weapon: bool = false

var shield_capacity: float = 100.0
var shield_regeneration: float = 30.0
var shield_continuous_drain: float = 20.0
var shield_regeneration_delay: float = 1.25
var shield_arc_degrees: float = 120.0
var shield_block_cost: float = GameConstants.SHIELD_BLOCK_COST
var shield_depletion_threshold: float = GameConstants.SHIELD_DEPLETION_THRESHOLD
var shield_acceleration_factor: float = GameConstants.SHIELD_ACCELERATION_FACTOR
var shield_ram_damage: float = 0.0
var shield_ram_min_speed: float = 180.0
var shield_ram_cooldown: float = 0.85

var auto_repair_enabled: bool = false
var auto_repair_delay: float = 5.0
var auto_repair_rate: float = 8.0


static func create_base() -> CombatStats:
	return CombatStats.new()


func duplicate_stats() -> CombatStats:
	var copy := CombatStats.new()
	for property_name in get_stat_property_names():
		copy.set(property_name, get(property_name))
	copy.auto_repair_enabled = auto_repair_enabled
	copy.beam_weapon = beam_weapon
	return copy


static func get_stat_property_names() -> Array[StringName]:
	return [
		&"max_health",
		&"max_speed",
		&"acceleration",
		&"drag",
		&"projectile_damage",
		&"fire_rate",
		&"magazine_size",
		&"reload_duration",
		&"projectile_speed",
		&"projectile_count",
		&"projectile_spread_degrees",
		&"projectile_lifetime",
		&"pierce_count",
		&"ricochet_count",
		&"shield_capacity",
		&"shield_regeneration",
		&"shield_continuous_drain",
		&"shield_regeneration_delay",
		&"shield_arc_degrees",
		&"shield_block_cost",
		&"shield_depletion_threshold",
		&"shield_acceleration_factor",
		&"shield_ram_damage",
		&"shield_ram_min_speed",
		&"shield_ram_cooldown",
		&"auto_repair_delay",
		&"auto_repair_rate",
	]
