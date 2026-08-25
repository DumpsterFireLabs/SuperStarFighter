class_name CardStatTests
extends RefCounted

const EXPECTED_CARDS := {
	&"reinforced_hull": [CardDefinition.Category.SHIP, 3],
	&"overcharged_thrusters": [CardDefinition.Category.SHIP, 3],
	&"vector_jets": [CardDefinition.Category.SHIP, 3],
	&"auto_repair": [CardDefinition.Category.SHIP, 1],
	&"capacitor_bank": [CardDefinition.Category.SHIELD, 3],
	&"quick_charge": [CardDefinition.Category.SHIELD, 3],
	&"wide_emitter": [CardDefinition.Category.SHIELD, 3],
	&"efficient_field": [CardDefinition.Category.SHIELD, 3],
	&"heavy_rounds": [CardDefinition.Category.WEAPON, 3],
	&"rapid_cycling": [CardDefinition.Category.WEAPON, 3],
	&"rail_accelerant": [CardDefinition.Category.WEAPON, 3],
	&"extended_magazine": [CardDefinition.Category.WEAPON, 3],
	&"quick_loader": [CardDefinition.Category.WEAPON, 3],
	&"twin_shot": [CardDefinition.Category.WEAPON, 2],
	&"piercing_rounds": [CardDefinition.Category.WEAPON, 3],
	&"ricochet_rounds": [CardDefinition.Category.WEAPON, 3],
	&"kinetic_plating": [CardDefinition.Category.SHIP, 4],
	&"phase_thrusters": [CardDefinition.Category.SHIP, 4],
	&"glass_reactor": [CardDefinition.Category.SHIP, 3],
	&"emergency_bulkheads": [CardDefinition.Category.SHIP, 2],
	&"inertial_dampers": [CardDefinition.Category.SHIP, 3],
	&"nanite_reservoir": [CardDefinition.Category.SHIP, 2],
	&"flux_reservoir": [CardDefinition.Category.SHIELD, 4],
	&"mirror_field": [CardDefinition.Category.SHIELD, 3],
	&"fortress_emitter": [CardDefinition.Category.SHIELD, 2],
	&"blink_capacitor": [CardDefinition.Category.SHIELD, 2],
	&"reactive_barrier": [CardDefinition.Category.SHIELD, 3],
	&"omnidirectional_field": [CardDefinition.Category.SHIELD, 1],
	&"scatter_array": [CardDefinition.Category.WEAPON, 2],
	&"beam_emitter": [CardDefinition.Category.WEAPON, 1],
	&"prismatic_lance": [CardDefinition.Category.WEAPON, 3],
	&"laser_repeater": [CardDefinition.Category.WEAPON, 3],
	&"siege_cannon": [CardDefinition.Category.WEAPON, 3],
	&"micro_barrage": [CardDefinition.Category.WEAPON, 2],
	&"endless_belt": [CardDefinition.Category.WEAPON, 4],
	&"zero_point_loader": [CardDefinition.Category.WEAPON, 2],
}


static func run(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	context.expect_equal(catalog.size(), 36, "default card catalog contains all 36 cards")
	context.expect_empty(catalog.validate_default_catalog(), "default card catalog validates")
	_validate_catalog_metadata(context, catalog)
	_validate_one_stack_values(context, catalog)
	_validate_max_stack_values(context, catalog)
	_validate_order_independence(context, catalog)
	_validate_runaway_synergy(context, catalog)
	_validate_rarity_and_beams(context, catalog)
	_validate_clamps(context)
	_validate_player_build_rules(context, catalog)
	_validate_shared_models(context)


static func _validate_catalog_metadata(context: TestContext, catalog: CardCatalog) -> void:
	for card_id in EXPECTED_CARDS:
		var card := catalog.get_card(card_id)
		context.expect_true(card != null, "catalog contains %s" % card_id)
		if card == null:
			continue
		context.expect_equal(card.category, EXPECTED_CARDS[card_id][0], "%s category matches specification" % card_id)
		context.expect_equal(card.max_stacks, EXPECTED_CARDS[card_id][1], "%s stack cap matches specification" % card_id)
		context.expect_false(card.display_name.is_empty(), "%s has display text" % card_id)
		context.expect_false(card.description.is_empty(), "%s has effect description" % card_id)
		context.expect_true(card.rarity_drop_chance() > 0.0, "%s declares a positive rarity-tier drop chance" % card_id)


static func _validate_rarity_and_beams(context: TestContext, catalog: CardCatalog) -> void:
	var rarity_total := 0.0
	for chance in CardDefinition.RARITY_DROP_CHANCES.values():
		rarity_total += float(chance)
	context.expect_approx(rarity_total, 100.0, "rarity tier chances total 100 percent")
	var beam_stats := StatSystem.derive({&"beam_emitter": 1, &"prismatic_lance": 2}, catalog)
	context.expect_true(beam_stats.beam_weapon, "beam cards transform the authoritative weapon type")
	context.expect_equal(beam_stats.pierce_count, 4, "beam lance stacks add pierces")
	context.expect_true(beam_stats.projectile_damage > CombatStats.create_base().projectile_damage, "beam cards compound damage multiplicatively")


static func _validate_one_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 1, {"max_health": 125.0, "max_speed": 441.6})
	_expect_build(context, catalog, &"overcharged_thrusters", 1, {"max_health": 100.0, "max_speed": 537.6, "acceleration": 1035.0})
	_expect_build(context, catalog, &"vector_jets", 1, {"acceleration": 1080.0, "drag": 875.0})
	_expect_build(context, catalog, &"auto_repair", 1, {"auto_repair_enabled": true, "auto_repair_delay": 5.0, "auto_repair_rate": 8.0})
	_expect_build(context, catalog, &"capacitor_bank", 1, {"shield_capacity": 130.0, "shield_regeneration": 33.0})
	_expect_build(context, catalog, &"quick_charge", 1, {"shield_capacity": 100.0, "shield_regeneration": 37.5})
	_expect_build(context, catalog, &"wide_emitter", 1, {"shield_arc_degrees": 140.0, "shield_continuous_drain": 23.0})
	_expect_build(context, catalog, &"efficient_field", 1, {"shield_continuous_drain": 16.0, "shield_regeneration_delay": 1.25})
	_expect_build(context, catalog, &"heavy_rounds", 1, {"projectile_damage": 33.75, "fire_rate": 3.2})
	_expect_build(context, catalog, &"rapid_cycling", 1, {"projectile_damage": 25.0, "fire_rate": 5.2})
	_expect_build(context, catalog, &"rail_accelerant", 1, {"projectile_damage": 27.5, "projectile_speed": 1215.0})
	_expect_build(context, catalog, &"extended_magazine", 1, {"magazine_size": 12, "reload_duration": 1.5})
	_expect_build(context, catalog, &"quick_loader", 1, {"magazine_size": 6, "reload_duration": 1.125})
	_expect_build(context, catalog, &"twin_shot", 1, {"projectile_count": 2, "projectile_spread_degrees": 10.0, "projectile_damage": 17.5})
	_expect_build(context, catalog, &"piercing_rounds", 1, {"pierce_count": 1, "projectile_damage": 27.0})
	_expect_build(context, catalog, &"ricochet_rounds", 1, {"ricochet_count": 1, "projectile_speed": 972.0})


static func _validate_max_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 3, {"max_health": 175.0, "max_speed": 373.77024})
	_expect_build(context, catalog, &"overcharged_thrusters", 3, {"max_health": 100.0, "max_speed": 674.36544, "acceleration": 1368.7875})
	_expect_build(context, catalog, &"vector_jets", 3, {"acceleration": 1555.2, "drag": 1367.1875})
	_expect_build(context, catalog, &"auto_repair", 1, {"auto_repair_enabled": true})
	_expect_build(context, catalog, &"capacitor_bank", 3, {"shield_capacity": 190.0, "shield_regeneration": 39.93})
	_expect_build(context, catalog, &"quick_charge", 3, {"shield_capacity": 100.0, "shield_regeneration": 58.59375})
	_expect_build(context, catalog, &"wide_emitter", 3, {"shield_arc_degrees": 180.0, "shield_continuous_drain": 30.4175})
	_expect_build(context, catalog, &"efficient_field", 3, {"shield_continuous_drain": 10.24, "shield_regeneration_delay": 1.25})
	_expect_build(context, catalog, &"heavy_rounds", 3, {"projectile_damage": 61.509375, "fire_rate": 2.048})
	_expect_build(context, catalog, &"rapid_cycling", 3, {"projectile_damage": 25.0, "fire_rate": 8.788})
	_expect_build(context, catalog, &"rail_accelerant", 3, {"projectile_damage": 33.275, "projectile_speed": 2214.3375})
	_expect_build(context, catalog, &"extended_magazine", 3, {"magazine_size": 20, "reload_duration": 1.5})
	_expect_build(context, catalog, &"quick_loader", 3, {"magazine_size": 2, "reload_duration": 0.6328125})
	_expect_build(context, catalog, &"twin_shot", 2, {"projectile_count": 3, "projectile_spread_degrees": 20.0, "projectile_damage": 12.25})
	_expect_build(context, catalog, &"piercing_rounds", 3, {"pierce_count": 3, "projectile_damage": 31.4928})
	_expect_build(context, catalog, &"ricochet_rounds", 3, {"ricochet_count": 3, "projectile_speed": 1133.7408})


static func _validate_order_independence(context: TestContext, catalog: CardCatalog) -> void:
	var forward_build: Dictionary = {}
	var reverse_build: Dictionary = {}
	var ids: Array[StringName] = [
		&"reinforced_hull",
		&"overcharged_thrusters",
		&"heavy_rounds",
		&"rapid_cycling",
		&"extended_magazine",
		&"quick_loader",
	]
	for card_id in ids:
		forward_build[card_id] = 2
	ids.reverse()
	for card_id in ids:
		reverse_build[card_id] = 2
	var forward_stats := StatSystem.derive(forward_build, catalog)
	var reverse_stats := StatSystem.derive(reverse_build, catalog)
	for property_name in CombatStats.get_stat_property_names():
		var actual: Variant = forward_stats.get(property_name)
		var expected: Variant = reverse_stats.get(property_name)
		if actual is float:
			context.expect_approx(float(actual), float(expected), "stat %s is acquisition-order independent" % property_name)
		else:
			context.expect_equal(actual, expected, "stat %s is acquisition-order independent" % property_name)


static func _validate_runaway_synergy(context: TestContext, catalog: CardCatalog) -> void:
	var build := {
		&"overcharged_thrusters": 3,
		&"vector_jets": 3,
		&"heavy_rounds": 3,
		&"rail_accelerant": 3,
		&"piercing_rounds": 3,
		&"ricochet_rounds": 3,
	}
	var stats := StatSystem.derive(build, catalog)
	context.expect_approx(
		stats.acceleration,
		900.0 * pow(1.15, 3) * pow(1.2, 3),
		"positive acceleration cards multiply into a runaway combined build"
	)
	context.expect_approx(
		stats.projectile_damage,
		25.0 * pow(1.35, 3) * pow(1.1, 3) * pow(1.08, 3),
		"damage cards compound past the former balance ceiling"
	)
	context.expect_true(stats.projectile_damage > 100.0, "legal builds can exceed former balance clamps")
	context.expect_approx(
		stats.projectile_speed,
		900.0 * pow(1.35, 3) * pow(1.08, 3),
		"projectile-speed synergies multiply across different cards"
	)


static func _validate_clamps(context: TestContext) -> void:
	var extreme := CardDefinition.new()
	extreme.card_id = &"extreme_test"
	extreme.display_name = "Extreme Test"
	extreme.description = "Exercises every stat clamp."
	extreme.max_stacks = 1
	extreme.additive_modifiers = {
		"max_health": 1000.0,
		"magazine_size": 1000.0,
		"shield_capacity": -1000.0,
		"shield_arc_degrees": 1000.0,
	}
	extreme.multiplicative_modifiers = {
		"max_speed": 0.01,
		"acceleration": 100.0,
		"projectile_damage": 100.0,
		"fire_rate": 100.0,
		"reload_duration": 0.001,
		"projectile_speed": 100.0,
	}
	extreme.integer_modifiers = {
		"projectile_count": 100,
		"pierce_count": 100,
		"ricochet_count": 100,
	}
	var catalog := CardCatalog.new()
	context.expect_true(catalog.add_card(extreme), "synthetic clamp card validates")
	var stats := StatSystem.derive({&"extreme_test": 1}, catalog)
	context.expect_approx(stats.max_health, 600.0, "maximum health transport guardrail applies")
	context.expect_approx(stats.max_speed, 100.0, "maximum speed physics guardrail applies")
	context.expect_approx(stats.acceleration, 6000.0, "acceleration physics guardrail applies")
	context.expect_approx(stats.projectile_damage, 600.0, "damage transport guardrail applies")
	context.expect_approx(stats.fire_rate, 20.0, "fire-rate entity-budget guardrail applies")
	context.expect_equal(stats.magazine_size, 128, "magazine transport guardrail applies")
	context.expect_approx(stats.reload_duration, 0.1, "reload timing guardrail applies")
	context.expect_approx(stats.projectile_speed, 4000.0, "projectile velocity transport guardrail applies")
	context.expect_equal(stats.projectile_count, 6, "projectile-count entity-budget guardrail applies")
	context.expect_equal(stats.pierce_count, 12, "pierce entity-budget guardrail applies")
	context.expect_equal(stats.ricochet_count, 12, "ricochet entity-budget guardrail applies")
	context.expect_approx(stats.shield_capacity, 5.0, "shield-capacity transport guardrail applies")
	context.expect_approx(stats.shield_arc_degrees, 360.0, "shield-arc geometry guardrail applies")


static func _validate_player_build_rules(context: TestContext, catalog: CardCatalog) -> void:
	var player := PlayerMatchState.new(7, "Builder", 1)
	var card := catalog.get_card(&"auto_repair")
	context.expect_true(player.add_card(card), "player can add an eligible card")
	context.expect_false(player.add_card(card), "player cannot exceed a card stack cap")
	var stats := StatSystem.derive(player.card_stacks, catalog)
	player.reset_for_heat(stats)
	context.expect_true(player.alive, "heat reset marks a connected participant alive")
	context.expect_approx(player.health, stats.max_health, "heat reset restores derived health")
	context.expect_approx(player.shield_energy, stats.shield_capacity, "heat reset restores derived shield")
	context.expect_equal(player.ammunition, stats.magazine_size, "heat reset restores derived magazine")


static func _validate_shared_models(context: TestContext) -> void:
	var config := MatchConfig.new()
	context.expect_empty(config.validate(), "default match configuration validates")
	config.rounds_to_win = 0
	context.expect_false(config.validate().is_empty(), "invalid match configuration is rejected")
	var input := PlayerInputFrame.new(1, 10, Vector2(0.5, -0.5), -PI, true, false)
	context.expect_true(input.is_valid(), "bounded finite player input validates")
	context.expect_approx(input.normalized_aim_angle(), PI, "aim angle normalizes into one turn")
	input.movement = Vector2(1.0, 1.0)
	context.expect_false(input.is_valid(), "oversized movement input is rejected")


static func _expect_build(
	context: TestContext,
	catalog: CardCatalog,
	card_id: StringName,
	stacks: int,
	expected_values: Dictionary
) -> void:
	var stats := StatSystem.derive({card_id: stacks}, catalog)
	for property_name in expected_values:
		var actual: Variant = stats.get(StringName(property_name))
		var expected: Variant = expected_values[property_name]
		var description := "%s stack %d produces %s" % [card_id, stacks, property_name]
		if expected is float:
			context.expect_approx(float(actual), expected, description)
		else:
			context.expect_equal(actual, expected, description)
