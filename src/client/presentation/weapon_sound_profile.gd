class_name WeaponSoundProfile
extends RefCounted

const FAMILY_STANDARD: StringName = &"standard"
const FAMILY_AUTOMATIC: StringName = &"automatic"
const FAMILY_HEAVY: StringName = &"heavy"
const FAMILY_RAIL: StringName = &"rail"
const FAMILY_SCATTER: StringName = &"scatter"
const FAMILY_BEAM_PULSE: StringName = &"beam_pulse"
const FAMILY_BEAM_REPEATER: StringName = &"beam_repeater"
const FAMILY_BEAM_LANCE: StringName = &"beam_lance"

const BASE_DAMAGE: float = 25.0
const BASE_FIRE_RATE: float = 4.0
const BASE_PROJECTILE_SPEED: float = 900.0

var family: StringName = FAMILY_STANDARD
var power_tier: int = 0
var power_amount: float = 0.0
var modification_amount: float = 0.0
var damage_ratio: float = 1.0
var fire_rate_ratio: float = 1.0
var speed_ratio: float = 1.0
var projectile_count: int = 1
var pierce_count: int = 0
var ricochet_count: int = 0
var knockback_ratio: float = 0.0
var beam_weapon: bool = false
var weapon_stack_count: int = 0
var highest_weapon_rarity: int = CardDefinition.Rarity.COMMON


static func from_stats(
	stats: CombatStats,
	build: Dictionary = {},
	catalog: CardCatalog = null
):
	var profile = new()
	profile.damage_ratio = maxf(stats.projectile_damage / BASE_DAMAGE, 0.04)
	profile.fire_rate_ratio = maxf(stats.fire_rate / BASE_FIRE_RATE, 0.0625)
	profile.speed_ratio = maxf(stats.projectile_speed / BASE_PROJECTILE_SPEED, 0.2)
	profile.projectile_count = maxi(stats.projectile_count, 1)
	profile.pierce_count = maxi(stats.pierce_count, 0)
	profile.ricochet_count = maxi(stats.ricochet_count, 0)
	profile.knockback_ratio = clampf(stats.projectile_knockback / 600.0, 0.0, 3.0)
	profile.beam_weapon = stats.beam_weapon
	profile._read_weapon_build(build, catalog)
	profile.family = profile._classify_family(build)
	profile._derive_power()
	return profile


func cache_key() -> String:
	return "%s:%d:%d:%d:%d:%d" % [
		family,
		power_tier,
		mini(pierce_count, 2),
		mini(ricochet_count, 2),
		1 if knockback_ratio > 0.05 else 0,
		mini(projectile_count, 3),
	]


func display_name() -> String:
	return String(family).replace("_", " ").capitalize()


func power_tier_name() -> String:
	return ["Base", "Modified", "Powerful", "Extreme"][clampi(power_tier, 0, 3)]


func _read_weapon_build(build: Dictionary, catalog: CardCatalog) -> void:
	if catalog == null:
		return
	for card_key in build:
		var stacks := maxi(int(build.get(card_key, 0)), 0)
		if stacks == 0:
			continue
		var card := catalog.get_card(StringName(card_key))
		if card == null or card.category != CardDefinition.Category.WEAPON:
			continue
		weapon_stack_count += stacks
		highest_weapon_rarity = maxi(highest_weapon_rarity, card.rarity)


func _classify_family(build: Dictionary) -> StringName:
	if beam_weapon:
		if _has_any_card(build, [&"reality_shredder", &"singularity_lance", &"prismatic_lance"]):
			return FAMILY_BEAM_LANCE
		if _has_any_card(build, [&"laser_repeater", &"sunbeam_core"]) or fire_rate_ratio >= 1.18:
			return FAMILY_BEAM_REPEATER
		if damage_ratio >= 1.45 or pierce_count >= 2:
			return FAMILY_BEAM_LANCE
		return FAMILY_BEAM_PULSE
	if projectile_count >= 2:
		return FAMILY_SCATTER
	if damage_ratio >= 1.30 and fire_rate_ratio <= 0.95:
		return FAMILY_HEAVY
	if speed_ratio >= 1.24 or pierce_count >= 1:
		return FAMILY_RAIL
	if fire_rate_ratio >= 1.24:
		return FAMILY_AUTOMATIC
	return FAMILY_STANDARD


func _derive_power() -> void:
	var volley_ratio := maxf(damage_ratio * projectile_count, 0.05)
	var sustained_ratio := maxf(volley_ratio * fire_rate_ratio, 0.05)
	var traversal_bonus := (
		maxf(speed_ratio - 1.0, 0.0) * 0.24
		+ minf(float(pierce_count), 4.0) * 0.10
		+ minf(float(ricochet_count), 4.0) * 0.07
		+ minf(knockback_ratio, 2.0) * 0.09
	)
	var performance_octaves := maxf(
		log(volley_ratio) / log(2.0) * 0.62,
		log(sustained_ratio) / log(2.0) * 0.48
	)
	var rarity_detail := float(highest_weapon_rarity) / float(CardDefinition.Rarity.UNOBTANIUM) * 0.18
	var stack_detail := minf(float(weapon_stack_count) * 0.055, 0.34)
	var raw_power := maxf(performance_octaves, 0.0) + traversal_bonus + rarity_detail + stack_detail
	power_amount = clampf(raw_power / 2.4, 0.0, 1.0)
	modification_amount = clampf(
		maxf(absf(log(damage_ratio) / log(2.0)), absf(log(fire_rate_ratio) / log(2.0))) * 0.34
		+ maxf(absf(log(speed_ratio) / log(2.0)), 0.0) * 0.18
		+ minf(float(weapon_stack_count) * 0.08, 0.52),
		0.0,
		1.0
	)
	if raw_power >= 2.15:
		power_tier = 3
	elif raw_power >= 1.20:
		power_tier = 2
	elif raw_power >= 0.35 or weapon_stack_count > 0:
		power_tier = 1
	else:
		power_tier = 0


static func _has_any_card(build: Dictionary, ids: Array[StringName]) -> bool:
	for card_id in ids:
		if int(build.get(card_id, build.get(String(card_id), 0))) > 0:
			return true
	return false
