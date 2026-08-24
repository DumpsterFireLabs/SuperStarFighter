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
}


static func run(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	context.expect_equal(catalog.size(), 16, "default card catalog contains all 16 cards")
	context.expect_empty(catalog.validate_default_catalog(), "default card catalog validates")
	_validate_catalog_metadata(context, catalog)
	_validate_one_stack_values(context, catalog)
	_validate_max_stack_values(context, catalog)
	_validate_order_independence(context, catalog)
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


static func _validate_one_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 1, {"max_health": 125.0, "max_speed": 441.6})
	_expect_build(context, catalog, &"overcharged_thrusters", 1, {"max_health": 90.0, "max_speed": 537.6, "acceleration": 1035.0})
	_expect_build(context, catalog, &"vector_jets", 1, {"acceleration": 1080.0, "drag": 875.0})
	_expect_build(context, catalog, &"auto_repair", 1, {"auto_repair_enabled": true, "auto_repair_delay": 5.0, "auto_repair_rate": 8.0})
	_expect_build(context, catalog, &"capacitor_bank", 1, {"shield_capacity": 130.0, "shield_regeneration": 27.0})
	_expect_build(context, catalog, &"quick_charge", 1, {"shield_capacity": 90.0, "shield_regeneration": 37.5})
	_expect_build(context, catalog, &"wide_emitter", 1, {"shield_arc_degrees": 140.0, "shield_continuous_drain": 23.0})
	_expect_build(context, catalog, &"efficient_field", 1, {"shield_continuous_drain": 16.0, "shield_regeneration_delay": 1.5})
	_expect_build(context, catalog, &"heavy_rounds", 1, {"projectile_damage": 33.75, "fire_rate": 3.2})
	_expect_build(context, catalog, &"rapid_cycling", 1, {"projectile_damage": 20.0, "fire_rate": 5.2})
	_expect_build(context, catalog, &"rail_accelerant", 1, {"projectile_damage": 22.5, "projectile_speed": 1215.0})
	_expect_build(context, catalog, &"extended_magazine", 1, {"magazine_size": 12, "reload_duration": 1.8})
	_expect_build(context, catalog, &"quick_loader", 1, {"magazine_size": 6, "reload_duration": 1.125})
	_expect_build(context, catalog, &"twin_shot", 1, {"projectile_count": 2, "projectile_spread_degrees": 10.0, "projectile_damage": 17.5})
	_expect_build(context, catalog, &"piercing_rounds", 1, {"pierce_count": 1, "projectile_damage": 21.25})
	_expect_build(context, catalog, &"ricochet_rounds", 1, {"ricochet_count": 1, "projectile_speed": 810.0})


static func _validate_max_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 3, {"max_health": 175.0, "max_speed": 373.77024})
	_expect_build(context, catalog, &"overcharged_thrusters", 3, {"max_health": 70.0, "max_speed": 674.36544, "acceleration": 1368.7875})
	_expect_build(context, catalog, &"vector_jets", 3, {"acceleration": 1555.2, "drag": 1367.1875})
	_expect_build(context, catalog, &"auto_repair", 1, {"auto_repair_enabled": true})
	_expect_build(context, catalog, &"capacitor_bank", 3, {"shield_capacity": 190.0, "shield_regeneration": 21.87})
	_expect_build(context, catalog, &"quick_charge", 3, {"shield_capacity": 70.0, "shield_regeneration": 58.59375})
	_expect_build(context, catalog, &"wide_emitter", 3, {"shield_arc_degrees": 180.0, "shield_continuous_drain": 30.4175})
	_expect_build(context, catalog, &"efficient_field", 3, {"shield_continuous_drain": 10.24, "shield_regeneration_delay": 2.0})
	_expect_build(context, catalog, &"heavy_rounds", 3, {"projectile_damage": 61.509375, "fire_rate": 2.048})
	_expect_build(context, catalog, &"rapid_cycling", 3, {"projectile_damage": 12.8, "fire_rate": 8.788})
	_expect_build(context, catalog, &"rail_accelerant", 3, {"projectile_damage": 18.225, "projectile_speed": 1800.0})
	_expect_build(context, catalog, &"extended_magazine", 3, {"magazine_size": 20, "reload_duration": 2.592})
	_expect_build(context, catalog, &"quick_loader", 3, {"magazine_size": 2, "reload_duration": 0.6328125})
	_expect_build(context, catalog, &"twin_shot", 2, {"projectile_count": 3, "projectile_spread_degrees": 20.0, "projectile_damage": 12.25})
	_expect_build(context, catalog, &"piercing_rounds", 3, {"pierce_count": 3, "projectile_damage": 15.353125})
	_expect_build(context, catalog, &"ricochet_rounds", 3, {"ricochet_count": 3, "projectile_speed": 656.1})


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


static func _validate_clamps(context: TestContext) -> void:
	var extreme := CardDefinition.new()
	extreme.card_id = &"extreme_test"
	extreme.display_name = "Extreme Test"
	extreme.description = "Exercises every stat clamp."
	extreme.max_stacks = 1
	extreme.additive_modifiers = {
		"max_health": 1000.0,
		"magazine_size": 100.0,
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
	context.expect_approx(stats.max_health, 250.0, "maximum health upper clamp applies")
	context.expect_approx(stats.max_speed, 200.0, "maximum speed lower clamp applies")
	context.expect_approx(stats.acceleration, 2000.0, "acceleration upper clamp applies")
	context.expect_approx(stats.projectile_damage, 100.0, "damage upper clamp applies")
	context.expect_approx(stats.fire_rate, 12.0, "fire-rate upper clamp applies")
	context.expect_equal(stats.magazine_size, 30, "magazine upper clamp applies")
	context.expect_approx(stats.reload_duration, 0.35, "reload lower clamp applies")
	context.expect_approx(stats.projectile_speed, 1800.0, "projectile-speed upper clamp applies")
	context.expect_equal(stats.projectile_count, 3, "projectile-count upper clamp applies")
	context.expect_equal(stats.pierce_count, 3, "pierce upper clamp applies")
	context.expect_equal(stats.ricochet_count, 3, "ricochet upper clamp applies")
	context.expect_approx(stats.shield_capacity, 20.0, "shield-capacity lower clamp applies")
	context.expect_approx(stats.shield_arc_degrees, 240.0, "shield-arc upper clamp applies")


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
