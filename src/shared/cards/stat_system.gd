class_name StatSystem
extends RefCounted

const Metadata = preload("res://src/shared/models/stat_metadata.gd")
static var FLOAT_STATS: Array[StringName] = Metadata.float_names()
static var INTEGER_STATS: Array[StringName] = Metadata.integer_names()
static var LOWER_IS_BETTER: Array[StringName] = Metadata.lower_is_better()
static var SPECIAL_FLAGS: Array[StringName] = Metadata.special_flags()


static func has_effective_benefit(build: Dictionary, card: CardDefinition, catalog: CardCatalog) -> bool:
	var next_build := build.duplicate()
	next_build[card.card_id] = int(next_build.get(card.card_id, 0)) + 1
	var before := derive(build, catalog)
	var after := derive(next_build, catalog)
	for property_name in SPECIAL_FLAGS:
		if bool(after.get(property_name)) and not bool(before.get(property_name)):
			return true
	for property_name in FLOAT_STATS + INTEGER_STATS:
		var change := float(after.get(property_name)) - float(before.get(property_name))
		if is_zero_approx(change):
			continue
		if Metadata.descriptor(property_name).is_beneficial(change):
			return true
	return false


static func derive(build: Dictionary, catalog: CardCatalog, apply_limits: bool = true) -> CombatStats:
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
		var flag: StringName = Metadata.SPECIAL_FLAGS.get(card.special_behavior_id, &"")
		if flag != &"":
			stats.set(flag, true)

	for property_name in FLOAT_STATS:
		var value := (float(stats.get(property_name)) + float(additive_totals[property_name])) * float(multiplier_totals[property_name])
		stats.set(property_name, value)
	for property_name in INTEGER_STATS:
		var value := (float(stats.get(property_name)) + float(additive_totals[property_name])) * float(multiplier_totals[property_name])
		value += int(integer_totals[property_name])
		stats.set(property_name, roundi(value))

	if apply_limits:
		_apply_clamps(stats)
	return stats


## Actual full-build values for one proposed pick, including limits and
## interactions with other cards. Nominal per-stack multipliers are insufficient.
static func compare_pick(build: Dictionary, card: CardDefinition, catalog: CardCatalog) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for change in compare_pick_typed(build, card, catalog):
		result.append(change.to_dictionary())
	return result


static func compare_pick_typed(build: Dictionary, card: CardDefinition, catalog: CardCatalog) -> Array[StatChange]:
	var next_build := build.duplicate()
	next_build[card.card_id] = int(next_build.get(card.card_id, 0)) + 1
	var before := derive(build, catalog)
	var after := derive(next_build, catalog)
	var raw_after := derive(next_build, catalog, false)
	var rows: Array[StatChange] = []
	for property_name in FLOAT_STATS + INTEGER_STATS:
		var previous := float(before.get(property_name))
		var next := float(after.get(property_name))
		var declared := card.additive_modifiers.has(property_name) or card.multiplicative_modifiers.has(property_name) or card.integer_modifiers.has(property_name)
		if not declared and is_equal_approx(previous, next):
			continue
		rows.append(StatChange.new(property_name, previous, next, not is_equal_approx(next, float(raw_after.get(property_name)))))
	return rows


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
	if not card.special_behavior_id.is_empty() and not Metadata.SPECIAL_FLAGS.has(card.special_behavior_id):
		errors.append("Card %s has unsupported special behavior %s." % [card.card_id, card.special_behavior_id])
	return errors


static func _apply_clamps(stats: CombatStats) -> void:
	for descriptor in Metadata.numeric_descriptors():
		var upper := float(stats.get(descriptor.upper_bound_property)) if descriptor.upper_bound_property != &"" else INF
		stats.set(descriptor.property, descriptor.bounded(float(stats.get(descriptor.property)), upper))
