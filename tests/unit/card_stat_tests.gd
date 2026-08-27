class_name CardStatTests
extends RefCounted

const EXPECTED_CARDS := {
	&"reinforced_hull": CardDefinition.Category.SHIP,
	&"overcharged_thrusters": CardDefinition.Category.SHIP,
	&"vector_jets": CardDefinition.Category.SHIP,
	&"auto_repair": CardDefinition.Category.SHIP,
	&"capacitor_bank": CardDefinition.Category.SHIELD,
	&"quick_charge": CardDefinition.Category.SHIELD,
	&"wide_emitter": CardDefinition.Category.SHIELD,
	&"efficient_field": CardDefinition.Category.SHIELD,
	&"heavy_rounds": CardDefinition.Category.WEAPON,
	&"rapid_cycling": CardDefinition.Category.WEAPON,
	&"rail_accelerant": CardDefinition.Category.WEAPON,
	&"extended_magazine": CardDefinition.Category.WEAPON,
	&"quick_loader": CardDefinition.Category.WEAPON,
	&"twin_shot": CardDefinition.Category.WEAPON,
	&"piercing_rounds": CardDefinition.Category.WEAPON,
	&"ricochet_rounds": CardDefinition.Category.WEAPON,
	&"kinetic_plating": CardDefinition.Category.SHIP,
	&"phase_thrusters": CardDefinition.Category.SHIP,
	&"glass_reactor": CardDefinition.Category.SHIP,
	&"emergency_bulkheads": CardDefinition.Category.SHIP,
	&"inertial_dampers": CardDefinition.Category.SHIP,
	&"nanite_reservoir": CardDefinition.Category.SHIP,
	&"flux_reservoir": CardDefinition.Category.SHIELD,
	&"mirror_field": CardDefinition.Category.SHIELD,
	&"fortress_emitter": CardDefinition.Category.SHIELD,
	&"blink_capacitor": CardDefinition.Category.SHIELD,
	&"reactive_barrier": CardDefinition.Category.SHIELD,
	&"omnidirectional_field": CardDefinition.Category.SHIELD,
	&"scatter_array": CardDefinition.Category.WEAPON,
	&"beam_emitter": CardDefinition.Category.WEAPON,
	&"prismatic_lance": CardDefinition.Category.WEAPON,
	&"laser_repeater": CardDefinition.Category.WEAPON,
	&"siege_cannon": CardDefinition.Category.WEAPON,
	&"micro_barrage": CardDefinition.Category.WEAPON,
	&"endless_belt": CardDefinition.Category.WEAPON,
	&"zero_point_loader": CardDefinition.Category.WEAPON,
	&"ablative_shell": CardDefinition.Category.SHIP,
	&"plasma_thrusters": CardDefinition.Category.SHIP,
	&"gyroscopic_core": CardDefinition.Category.SHIP,
	&"phoenix_chassis": CardDefinition.Category.SHIP,
	&"starheart_reactor": CardDefinition.Category.SHIP,
	&"event_horizon_drive": CardDefinition.Category.SHIP,
	&"quantum_reconstruction": CardDefinition.Category.SHIP,
	&"impossible_engine": CardDefinition.Category.SHIP,
	&"reserve_cell": CardDefinition.Category.SHIELD,
	&"regenerative_coils": CardDefinition.Category.SHIELD,
	&"focused_deflector": CardDefinition.Category.SHIELD,
	&"shield_siphon": CardDefinition.Category.SHIELD,
	&"aegis_matrix": CardDefinition.Category.SHIELD,
	&"solar_barrier": CardDefinition.Category.SHIELD,
	&"chronal_shield": CardDefinition.Category.SHIELD,
	&"infinite_refraction": CardDefinition.Category.SHIELD,
	&"hollow_points": CardDefinition.Category.WEAPON,
	&"cycling_servo": CardDefinition.Category.WEAPON,
	&"accelerator_coil": CardDefinition.Category.WEAPON,
	&"trident_array": CardDefinition.Category.WEAPON,
	&"sunbeam_core": CardDefinition.Category.WEAPON,
	&"causality_cannon": CardDefinition.Category.WEAPON,
	&"singularity_lance": CardDefinition.Category.WEAPON,
	&"reality_shredder": CardDefinition.Category.WEAPON,
	&"kinetic_prow": CardDefinition.Category.SHIELD,
	&"impact_capacitor": CardDefinition.Category.SHIELD,
	&"breach_vector": CardDefinition.Category.SHIELD,
	&"sundering_aegis": CardDefinition.Category.SHIELD,
	&"worldbreaker_prow": CardDefinition.Category.SHIELD,
}


static func run(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	context.expect_equal(catalog.size(), 125, "default card catalog contains 125 differentiated cards")
	context.expect_empty(catalog.validate_default_catalog(), "default card catalog validates")
	_validate_catalog_metadata(context, catalog)
	_validate_one_stack_values(context, catalog)
	_validate_expanded_stat_surface(context, catalog)
	_validate_repeated_stack_values(context, catalog)
	_validate_order_independence(context, catalog)
	_validate_runaway_synergy(context, catalog)
	_validate_rarity_and_beams(context, catalog)
	_validate_melee_cards(context, catalog)
	_validate_clamps(context)
	_validate_player_build_rules(context, catalog)
	_validate_shared_models(context)


static func _validate_catalog_metadata(context: TestContext, catalog: CardCatalog) -> void:
	var category_counts := {CardDefinition.Category.SHIP: 0, CardDefinition.Category.SHIELD: 0, CardDefinition.Category.WEAPON: 0}
	var mechanical_signatures: Dictionary = {}
	var mechanical_shapes: Dictionary = {}
	for card_id in catalog.all_ids():
		var card := catalog.get_card(card_id)
		context.expect_true(card != null, "catalog contains %s" % card_id)
		if card == null:
			continue
		if EXPECTED_CARDS.has(card_id):
			context.expect_equal(card.category, EXPECTED_CARDS[card_id], "%s category matches specification" % card_id)
		context.expect_false(card.display_name.is_empty(), "%s has display text" % card_id)
		context.expect_false(card.description.is_empty(), "%s has effect description" % card_id)
		context.expect_true(card.rarity_drop_chance() > 0.0, "%s declares a positive rarity-tier drop chance" % card_id)
		category_counts[card.category] = int(category_counts[card.category]) + 1
		mechanical_signatures[CardCatalog.mechanical_signature(card)] = card_id
		mechanical_shapes[CardCatalog.mechanical_shape_signature(card)] = card_id
	context.expect_equal(category_counts[CardDefinition.Category.SHIP], 38, "catalog contains thirty-eight differentiated ship cards")
	context.expect_equal(category_counts[CardDefinition.Category.SHIELD], 43, "catalog contains forty-three differentiated shield cards")
	context.expect_equal(category_counts[CardDefinition.Category.WEAPON], 44, "weapon-heavy catalog contains forty-four differentiated weapon cards")
	context.expect_equal(mechanical_signatures.size(), catalog.size(), "catalog sanity check finds no mechanically identical cards")
	context.expect_equal(mechanical_shapes.size(), catalog.size(), "catalog sanity check finds no same-shape magnitude swaps")


static func _validate_rarity_and_beams(context: TestContext, catalog: CardCatalog) -> void:
	var rarity_total := 0.0
	for chance in CardDefinition.RARITY_DROP_CHANCES.values():
		rarity_total += float(chance)
	context.expect_approx(rarity_total, 100.0, "rarity tier chances total 100 percent")
	context.expect_equal(CardDefinition.RARITY_DROP_CHANCES.size(), 7, "catalog exposes all seven rarity tiers")
	var expected_chances := [45.0, 27.0, 15.0, 8.0, 3.3, 1.2, 0.5]
	for rarity in expected_chances.size():
		context.expect_approx(float(CardDefinition.RARITY_DROP_CHANCES[rarity]), expected_chances[rarity], "%s has the specified tier chance" % CardDefinition.Rarity.keys()[rarity].capitalize())
		if rarity > 0:
			context.expect_true(expected_chances[rarity] < expected_chances[rarity - 1], "higher rarity %s is scarcer than the tier below" % CardDefinition.Rarity.keys()[rarity].capitalize())
	context.expect_equal(catalog.get_card(&"chronal_shield").rarity_drop_chance_text(), "1.2%", "mythical chance keeps meaningful decimal precision")
	context.expect_equal(catalog.get_card(&"reality_shredder").rarity_drop_chance_text(), "0.50%", "unobtanium chance keeps meaningful decimal precision")
	var audited_rarities := {
		&"endless_belt": CardDefinition.Rarity.UNCOMMON,
		&"scatter_array": CardDefinition.Rarity.EPIC,
		&"ricochet_rounds": CardDefinition.Rarity.RARE,
		&"mobile_bulwark": CardDefinition.Rarity.RARE,
		&"quantum_reconstruction": CardDefinition.Rarity.LEGENDARY,
	}
	for card_id in audited_rarities:
		context.expect_equal(catalog.get_card(card_id).rarity, audited_rarities[card_id], "%s retains its audited power tier" % card_id)
	var expected_beam_rarities := {
		&"laser_repeater": CardDefinition.Rarity.EPIC,
		&"beam_emitter": CardDefinition.Rarity.LEGENDARY,
		&"prismatic_lance": CardDefinition.Rarity.LEGENDARY,
		&"sunbeam_core": CardDefinition.Rarity.MYTHICAL,
		&"singularity_lance": CardDefinition.Rarity.UNOBTANIUM,
		&"reality_shredder": CardDefinition.Rarity.UNOBTANIUM,
	}
	for card_id in expected_beam_rarities:
		context.expect_equal(
			catalog.get_card(card_id).rarity,
			expected_beam_rarities[card_id],
			"%s uses its rebalanced high-tier beam rarity" % card_id
		)
	var beam_stats := StatSystem.derive({&"beam_emitter": 1, &"prismatic_lance": 2}, catalog)
	context.expect_true(beam_stats.beam_weapon, "beam cards transform the authoritative weapon type")
	context.expect_equal(beam_stats.pierce_count, 4, "beam lance stacks add pierces")
	context.expect_true(beam_stats.projectile_damage > CombatStats.create_base().projectile_damage, "beam cards compound damage multiplicatively")
	var unobtanium_stats := StatSystem.derive({&"reality_shredder": 1}, catalog)
	context.expect_true(unobtanium_stats.beam_weapon and unobtanium_stats.projectile_count == 3, "unobtanium weapon applies its authoritative beam and multishot effects")


static func _validate_melee_cards(context: TestContext, catalog: CardCatalog) -> void:
	var melee_rarities := {
		&"kinetic_prow": CardDefinition.Rarity.RARE,
		&"impact_capacitor": CardDefinition.Rarity.EPIC,
		&"breach_vector": CardDefinition.Rarity.LEGENDARY,
		&"sundering_aegis": CardDefinition.Rarity.MYTHICAL,
		&"worldbreaker_prow": CardDefinition.Rarity.UNOBTANIUM,
	}
	for card_id in melee_rarities:
		var card := catalog.get_card(card_id)
		context.expect_equal(card.rarity, melee_rarities[card_id], "%s occupies its intended melee rarity" % card_id)
		var build: Dictionary = {}
		build[card_id] = 1
		context.expect_true(StatSystem.derive(build, catalog).shield_ram_damage > 0.0, "%s independently enables shield-ram damage" % card_id)
	var worldbreaker := StatSystem.derive({&"worldbreaker_prow": 1}, catalog)
	context.expect_true(worldbreaker.shield_ram_damage >= 90.0 and worldbreaker.shield_ram_cooldown < CombatStats.create_base().shield_ram_cooldown, "Worldbreaker Prow combines lethal impact and faster contact recovery")


static func _validate_one_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 1, {"max_health": 125.0, "max_speed": 441.6})
	_expect_build(context, catalog, &"overcharged_thrusters", 1, {"max_health": 100.0, "max_speed": 537.6, "acceleration": 1035.0})
	_expect_build(context, catalog, &"vector_jets", 1, {"acceleration": 1080.0, "drag": 875.0})
	_expect_build(context, catalog, &"auto_repair", 1, {"auto_repair_enabled": true, "auto_repair_delay": 5.0, "auto_repair_rate": 8.0})
	_expect_build(context, catalog, &"capacitor_bank", 1, {"shield_capacity": 130.0, "shield_regeneration": 33.0})
	_expect_build(context, catalog, &"quick_charge", 1, {"shield_capacity": 100.0, "shield_regeneration": 36.6, "shield_block_cost": 23.75})
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


static func _validate_expanded_stat_surface(context: TestContext, catalog: CardCatalog) -> void:
	context.expect_equal(StatSystem.FLOAT_STATS.size() + StatSystem.INTEGER_STATS.size(), 27, "cards can modify twenty-seven authoritative numeric combat stats")
	_expect_build(context, catalog, &"rangefinder", 1, {"projectile_lifetime": 3.125, "projectile_speed": 990.0, "fire_rate": 3.8})
	_expect_build(context, catalog, &"compact_deflector", 1, {"shield_arc_degrees": 132.0, "shield_block_cost": 23.0})
	_expect_build(context, catalog, &"vectored_nozzles", 1, {"acceleration": 1008.0, "shield_acceleration_factor": 0.81})
	_expect_build(context, catalog, &"repair_gel", 1, {"auto_repair_enabled": true, "auto_repair_delay": 4.6, "auto_repair_rate": 8.96})


static func _validate_repeated_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 3, {"max_health": 175.0, "max_speed": 373.77024})
	_expect_build(context, catalog, &"overcharged_thrusters", 3, {"max_health": 100.0, "max_speed": 674.36544, "acceleration": 1368.7875})
	_expect_build(context, catalog, &"vector_jets", 3, {"acceleration": 1555.2, "drag": 1367.1875})
	_expect_build(context, catalog, &"auto_repair", 1, {"auto_repair_enabled": true})
	_expect_build(context, catalog, &"capacitor_bank", 3, {"shield_capacity": 190.0, "shield_regeneration": 39.93})
	_expect_build(context, catalog, &"quick_charge", 3, {"shield_capacity": 100.0, "shield_regeneration": 54.47544, "shield_block_cost": 21.434375})
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
	var repeated_damage := StatSystem.derive({&"heavy_rounds": 8}, catalog)
	context.expect_approx(repeated_damage.projectile_damage, 25.0 * pow(1.35, 8), "one card compounds beyond its former stack cap")
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
		"projectile_lifetime": 100.0,
		"shield_block_cost": 0.001,
		"shield_depletion_threshold": 100.0,
		"shield_acceleration_factor": 100.0,
		"auto_repair_delay": 0.001,
		"auto_repair_rate": 100.0,
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
	context.expect_approx(stats.projectile_lifetime, 12.0, "projectile lifetime entity-budget guardrail applies")
	context.expect_equal(stats.projectile_count, 6, "projectile-count entity-budget guardrail applies")
	context.expect_equal(stats.pierce_count, 12, "pierce entity-budget guardrail applies")
	context.expect_equal(stats.ricochet_count, 12, "ricochet entity-budget guardrail applies")
	context.expect_approx(stats.shield_capacity, 5.0, "shield-capacity transport guardrail applies")
	context.expect_approx(stats.shield_arc_degrees, 360.0, "shield-arc geometry guardrail applies")
	context.expect_approx(stats.shield_block_cost, 1.0, "shield block-cost guardrail applies")
	context.expect_approx(stats.shield_depletion_threshold, stats.shield_capacity, "shield recovery threshold remains inside capacity")
	context.expect_approx(stats.shield_acceleration_factor, 2.0, "shielded acceleration guardrail applies")
	context.expect_approx(stats.auto_repair_delay, 0.1, "auto-repair delay guardrail applies")
	context.expect_approx(stats.auto_repair_rate, 400.0, "auto-repair rate guardrail applies")


static func _validate_player_build_rules(context: TestContext, catalog: CardCatalog) -> void:
	var player := PlayerMatchState.new(7, "Builder", 1)
	var card := catalog.get_card(&"auto_repair")
	for stack in 12:
		context.expect_true(player.add_card(card), "player can add unlimited card stack %d" % (stack + 1))
	context.expect_equal(player.card_stack(card.card_id), 12, "player build retains every repeated card stack")
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
