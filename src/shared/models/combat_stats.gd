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
var projectile_knockback: float = 0.0

var mine_capacity: int = 0
var mine_layer_enabled: bool = false

var missile_capacity: int = 0
var missile_launcher_enabled: bool = false

# Card stack count; retained under this name for build/stat compatibility.
var cloak_capacity: int = 0
var cloak_enabled: bool = false

var afterburner_enabled: bool = false
var afterburner_impulse: float = 360.0
var afterburner_duration: float = 0.55
var afterburner_cooldown: float = 5.0
var afterburner_speed_multiplier: float = 1.65
var afterburner_acceleration_multiplier: float = 2.4

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
var shield_damage_heal_fraction: float = 0.0
var rebound_shield_enabled: bool = false
var rebound_damage_factor: float = 0.4
var rebound_range_factor: float = 0.4
var kinetic_vent_enabled: bool = false
var kinetic_vent_impulse: float = 360.0

var breakaway_thrusters_enabled: bool = false
var breakaway_cooldown: float = GameConstants.BREAKAWAY_COOLDOWN_SECONDS

var auto_repair_enabled: bool = false
var auto_repair_delay: float = 5.0
var auto_repair_rate: float = 8.0


func cloak_duration_seconds() -> float:
	return GameConstants.CLOAK_DURATION_SECONDS + maxi(cloak_capacity - 1, 0) * GameConstants.CLOAK_DURATION_PER_EXTRA_CARD_SECONDS


func cloak_cooldown_seconds() -> float:
	return GameConstants.CLOAK_COOLDOWN_SECONDS * pow(GameConstants.CLOAK_COOLDOWN_PER_EXTRA_CARD, maxi(cloak_capacity - 1, 0))


static func create_base() -> CombatStats:
	return CombatStats.new()


func duplicate_stats() -> CombatStats:
	var copy := CombatStats.new()
	for property_name in get_stat_property_names():
		copy.set(property_name, get(property_name))
	for flag in preload("res://src/shared/models/stat_metadata.gd").special_flags():
		copy.set(flag, get(flag))
	return copy


static func get_stat_property_names() -> Array[StringName]:
	var metadata = preload("res://src/shared/models/stat_metadata.gd")
	return metadata.float_names() + metadata.integer_names()
