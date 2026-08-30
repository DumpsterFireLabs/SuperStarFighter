class_name StatSystem
extends RefCounted

const FLOAT_STATS: Array[StringName] = [
	&"max_health",
	&"max_speed",
	&"acceleration",
	&"drag",
	&"projectile_damage",
	&"fire_rate",
	&"reload_duration",
	&"projectile_speed",
	&"projectile_spread_degrees",
	&"projectile_lifetime",
	&"projectile_knockback",
	&"afterburner_impulse",
	&"afterburner_duration",
	&"afterburner_cooldown",
	&"afterburner_speed_multiplier",
	&"afterburner_acceleration_multiplier",
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
	&"shield_damage_heal_fraction",
	&"rebound_damage_factor",
	&"rebound_range_factor",
	&"auto_repair_delay",
	&"auto_repair_rate",
]

const INTEGER_STATS: Array[StringName] = [
	&"magazine_size",
	&"projectile_count",
	&"pierce_count",
	&"ricochet_count",
	&"mine_capacity",
	&"cloak_capacity",
]


static func derive(build: Dictionary, catalog: CardCatalog) -> CombatStats:
	var stats := CombatStats.create_base()
	var additive_totals: Dictionary = {}
	var multiplier_totals: Dictionary = {}
	var integer_totals: Dictionary = {}
	for property_name in FLOAT_STATS + INTEGER_STATS:
		additive_totals[property_name] = 0.0
		multiplier_totals[property_name] = 1.0
	for property_name in INTEGER_STATS:
		integer_totals[property_name] = 0

	for card_id in catalog.all_ids():
		var card := catalog.get_card(card_id)
		var stacks := maxi(int(build.get(card_id, 0)), 0)
		if stacks == 0:
			continue
		for property_name in card.additive_modifiers:
			var normalized_name := StringName(property_name)
			additive_totals[normalized_name] = float(additive_totals.get(normalized_name, 0.0)) + float(card.additive_modifiers[property_name]) * stacks
		for property_name in card.multiplicative_modifiers:
			var normalized_name := StringName(property_name)
			multiplier_totals[normalized_name] = float(multiplier_totals.get(normalized_name, 1.0)) * pow(float(card.multiplicative_modifiers[property_name]), stacks)
		for property_name in card.integer_modifiers:
			var normalized_name := StringName(property_name)
			integer_totals[normalized_name] = int(integer_totals.get(normalized_name, 0)) + int(card.integer_modifiers[property_name]) * stacks
		if card.special_behavior_id == &"auto_repair":
			stats.auto_repair_enabled = true
		elif card.special_behavior_id == &"beam_weapon":
			stats.beam_weapon = true
		elif card.special_behavior_id == &"afterburner":
			stats.afterburner_enabled = true
		elif card.special_behavior_id == &"mine_layer":
			stats.mine_layer_enabled = true
		elif card.special_behavior_id == &"cloak":
			stats.cloak_enabled = true
		elif card.special_behavior_id == &"rebound_shield":
			stats.rebound_shield_enabled = true

	for property_name in FLOAT_STATS:
		var value := (float(stats.get(property_name)) + float(additive_totals[property_name])) * float(multiplier_totals[property_name])
		stats.set(property_name, value)
	for property_name in INTEGER_STATS:
		var value := (float(stats.get(property_name)) + float(additive_totals[property_name])) * float(multiplier_totals[property_name])
		value += int(integer_totals[property_name])
		stats.set(property_name, roundi(value))

	_apply_clamps(stats)
	return stats


static func validate_card(card: CardDefinition) -> PackedStringArray:
	var errors := PackedStringArray()
	var supported_stats := FLOAT_STATS + INTEGER_STATS
	for property_name in card.additive_modifiers:
		if StringName(property_name) not in supported_stats:
			errors.append("Card %s has unsupported additive stat %s." % [card.card_id, property_name])
	for property_name in card.multiplicative_modifiers:
		if StringName(property_name) not in supported_stats:
			errors.append("Card %s has unsupported multiplicative stat %s." % [card.card_id, property_name])
		elif float(card.multiplicative_modifiers[property_name]) <= 0.0:
			errors.append("Card %s has non-positive multiplier for %s." % [card.card_id, property_name])
	for property_name in card.integer_modifiers:
		if StringName(property_name) not in INTEGER_STATS:
			errors.append("Card %s has unsupported integer stat %s." % [card.card_id, property_name])
	if not card.special_behavior_id.is_empty() and card.special_behavior_id not in [&"auto_repair", &"beam_weapon", &"afterburner", &"mine_layer", &"rebound_shield", &"cloak"]:
		errors.append("Card %s has unsupported special behavior %s." % [card.card_id, card.special_behavior_id])
	return errors


static func _apply_clamps(stats: CombatStats) -> void:
	# These are transport/physics guardrails, not balance targets. Legal card builds
	# should have ample room to compound into deliberately excessive results.
	stats.max_health = clampf(stats.max_health, 10.0, 600.0)
	stats.max_speed = clampf(stats.max_speed, 100.0, 2400.0)
	stats.acceleration = clampf(stats.acceleration, 100.0, 6000.0)
	stats.drag = clampf(stats.drag, 100.0, 6000.0)
	stats.projectile_damage = clampf(stats.projectile_damage, 1.0, 600.0)
	stats.fire_rate = clampf(stats.fire_rate, 0.25, 20.0)
	stats.magazine_size = clampi(stats.magazine_size, 1, 128)
	stats.reload_duration = clampf(stats.reload_duration, 0.1, 8.0)
	stats.projectile_speed = clampf(stats.projectile_speed, 200.0, 4000.0)
	stats.projectile_count = clampi(stats.projectile_count, 1, 6)
	stats.projectile_spread_degrees = clampf(stats.projectile_spread_degrees, 0.0, 90.0)
	stats.projectile_lifetime = clampf(stats.projectile_lifetime, 0.1, 12.0)
	stats.projectile_knockback = clampf(stats.projectile_knockback, 0.0, 1800.0)
	stats.afterburner_impulse = clampf(stats.afterburner_impulse, 50.0, 1800.0)
	stats.afterburner_duration = clampf(stats.afterburner_duration, 0.1, 3.0)
	stats.afterburner_cooldown = clampf(stats.afterburner_cooldown, 0.5, 20.0)
	stats.afterburner_speed_multiplier = clampf(stats.afterburner_speed_multiplier, 1.0, 4.0)
	stats.afterburner_acceleration_multiplier = clampf(stats.afterburner_acceleration_multiplier, 1.0, 6.0)
	stats.pierce_count = clampi(stats.pierce_count, 0, 12)
	stats.ricochet_count = clampi(stats.ricochet_count, 0, 12)
	stats.mine_capacity = clampi(stats.mine_capacity, 0, 1000)
	stats.cloak_capacity = clampi(stats.cloak_capacity, 0, 1000)
	stats.shield_capacity = clampf(stats.shield_capacity, 5.0, 600.0)
	stats.shield_regeneration = clampf(stats.shield_regeneration, 1.0, 400.0)
	stats.shield_continuous_drain = clampf(stats.shield_continuous_drain, 0.25, 400.0)
	stats.shield_regeneration_delay = clampf(stats.shield_regeneration_delay, 0.05, 8.0)
	stats.shield_arc_degrees = clampf(stats.shield_arc_degrees, 30.0, 360.0)
	stats.shield_block_cost = clampf(stats.shield_block_cost, 1.0, 200.0)
	stats.shield_depletion_threshold = clampf(stats.shield_depletion_threshold, 1.0, stats.shield_capacity)
	stats.shield_acceleration_factor = clampf(stats.shield_acceleration_factor, 0.1, 2.0)
	stats.shield_ram_damage = clampf(stats.shield_ram_damage, 0.0, 300.0)
	stats.shield_ram_min_speed = clampf(stats.shield_ram_min_speed, 40.0, 1200.0)
	stats.shield_ram_cooldown = clampf(stats.shield_ram_cooldown, 0.15, 4.0)
	stats.shield_damage_heal_fraction = clampf(stats.shield_damage_heal_fraction, 0.0, 1.0)
	stats.rebound_damage_factor = clampf(stats.rebound_damage_factor, 0.1, 1.0)
	stats.rebound_range_factor = clampf(stats.rebound_range_factor, 0.1, 1.0)
	stats.auto_repair_delay = clampf(stats.auto_repair_delay, 0.1, 20.0)
	stats.auto_repair_rate = clampf(stats.auto_repair_rate, 0.1, 400.0)
