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
	&"shield_capacity",
	&"shield_regeneration",
	&"shield_continuous_drain",
	&"shield_regeneration_delay",
	&"shield_arc_degrees",
]

const INTEGER_STATS: Array[StringName] = [
	&"magazine_size",
	&"projectile_count",
	&"pierce_count",
	&"ricochet_count",
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
	if not card.special_behavior_id.is_empty() and card.special_behavior_id not in [&"auto_repair", &"beam_weapon"]:
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
	stats.pierce_count = clampi(stats.pierce_count, 0, 12)
	stats.ricochet_count = clampi(stats.ricochet_count, 0, 12)
	stats.shield_capacity = clampf(stats.shield_capacity, 5.0, 600.0)
	stats.shield_regeneration = clampf(stats.shield_regeneration, 1.0, 400.0)
	stats.shield_continuous_drain = clampf(stats.shield_continuous_drain, 0.25, 400.0)
	stats.shield_regeneration_delay = clampf(stats.shield_regeneration_delay, 0.05, 8.0)
	stats.shield_arc_degrees = clampf(stats.shield_arc_degrees, 30.0, 360.0)
