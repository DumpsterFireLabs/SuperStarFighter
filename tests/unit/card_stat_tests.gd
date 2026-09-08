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
	&"afterburner": CardDefinition.Category.SHIP,
	&"cloak": CardDefinition.Category.SHIP,
	&"ramming_shields": CardDefinition.Category.SHIELD,
	&"concussion_rounds": CardDefinition.Category.WEAPON,
	&"repulsor_payload": CardDefinition.Category.WEAPON,
	&"nosferatu_shield": CardDefinition.Category.SHIELD,
	&"rebound_shields": CardDefinition.Category.SHIELD,
	&"mine_layer": CardDefinition.Category.WEAPON,
	&"hunter_missiles": CardDefinition.Category.WEAPON,
	&"kinetic_vent": CardDefinition.Category.SHIELD,
	&"breakaway_thrusters": CardDefinition.Category.SHIP,
}


static func run(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	context.expect_equal(catalog.size(), 136, "default card catalog contains 136 differentiated cards")
	context.expect_empty(catalog.validate_default_catalog(), "default card catalog validates")
	_validate_catalog_metadata(context, catalog)
	_validate_one_stack_values(context, catalog)
	_validate_expanded_stat_surface(context, catalog)
	_validate_repeated_stack_values(context, catalog)
	_validate_order_independence(context, catalog)
	_validate_runaway_synergy(context, catalog)
	_validate_rarity_and_beams(context, catalog)
	_validate_melee_cards(context, catalog)
	_validate_rebalanced_outliers(context, catalog)
	_validate_balance_pass_behavior(context, catalog)
	_validate_second_balance_pass(context, catalog)
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
		context.expect_true(card.description.length() <= 105, "%s keeps its effect description concise" % card_id)
		context.expect_false(card.description.contains("×") or card.description.contains("multiplied by"), "%s uses readable percentage language" % card_id)
		var has_stackable_effects := not card.additive_modifiers.is_empty() or not card.multiplicative_modifiers.is_empty() or not card.integer_modifiers.is_empty()
		if has_stackable_effects:
			context.expect_true(card.description.contains("Per stack:"), "%s labels its stackable effects" % card_id)
		context.expect_true(card.rarity_drop_chance() > 0.0, "%s declares a positive rarity-tier drop chance" % card_id)
		category_counts[card.category] = int(category_counts[card.category]) + 1
		mechanical_signatures[CardCatalog.mechanical_signature(card)] = card_id
		mechanical_shapes[CardCatalog.mechanical_shape_signature(card)] = card_id
	context.expect_equal(category_counts[CardDefinition.Category.SHIP], 41, "catalog contains forty-one differentiated ship cards")
	context.expect_equal(category_counts[CardDefinition.Category.SHIELD], 47, "catalog contains forty-seven differentiated shield cards")
	context.expect_equal(category_counts[CardDefinition.Category.WEAPON], 48, "weapon-heavy catalog contains forty-eight differentiated weapon cards")
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
		&"fortress_emitter": CardDefinition.Rarity.RARE,
		&"adaptive_chassis": CardDefinition.Rarity.UNCOMMON,
		&"vectored_nozzles": CardDefinition.Rarity.COMMON,
		&"pursuit_screen": CardDefinition.Rarity.UNCOMMON,
		&"twin_shot": CardDefinition.Rarity.EPIC,
		&"vector_jets": CardDefinition.Rarity.UNCOMMON,
		&"endless_belt": CardDefinition.Rarity.UNCOMMON,
		&"scatter_array": CardDefinition.Rarity.EPIC,
		&"ricochet_rounds": CardDefinition.Rarity.RARE,
		&"mobile_bulwark": CardDefinition.Rarity.UNCOMMON,
		&"quantum_reconstruction": CardDefinition.Rarity.LEGENDARY,
		&"nanite_reservoir": CardDefinition.Rarity.EPIC,
		&"starheart_reactor": CardDefinition.Rarity.MYTHICAL,
		&"perpetual_field": CardDefinition.Rarity.MYTHICAL,
		&"instant_recovery": CardDefinition.Rarity.UNOBTANIUM,
		&"rebound_shields": CardDefinition.Rarity.LEGENDARY,
		&"cloak": CardDefinition.Rarity.LEGENDARY,
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
	var rebound_stats := StatSystem.derive({&"rebound_shields": 1}, catalog)
	context.expect_true(rebound_stats.rebound_shield_enabled, "Legendary Rebound Shields enable projectile reflection")


static func _validate_melee_cards(context: TestContext, catalog: CardCatalog) -> void:
	var melee_rarities := {
		&"kinetic_prow": CardDefinition.Rarity.RARE,
		&"impact_capacitor": CardDefinition.Rarity.EPIC,
		&"breach_vector": CardDefinition.Rarity.LEGENDARY,
		&"sundering_aegis": CardDefinition.Rarity.MYTHICAL,
		&"worldbreaker_prow": CardDefinition.Rarity.UNOBTANIUM,
		&"ramming_shields": CardDefinition.Rarity.EPIC,
	}
	for card_id in melee_rarities:
		var card := catalog.get_card(card_id)
		context.expect_equal(card.rarity, melee_rarities[card_id], "%s occupies its intended melee rarity" % card_id)
		var build: Dictionary = {}
		build[card_id] = 1
		context.expect_true(StatSystem.derive(build, catalog).shield_ram_damage > 0.0, "%s independently enables shield-ram damage" % card_id)
	var worldbreaker := StatSystem.derive({&"worldbreaker_prow": 1}, catalog)
	context.expect_true(worldbreaker.shield_ram_damage >= 90.0 and worldbreaker.shield_ram_cooldown < CombatStats.create_base().shield_ram_cooldown, "Worldbreaker Prow combines lethal impact and faster contact recovery")
	var ramming_shields := StatSystem.derive({&"ramming_shields": 1}, catalog)
	context.expect_true(ramming_shields.shield_ram_min_speed < CombatStats.create_base().shield_ram_min_speed, "Ramming Shields lowers the practical impact-speed threshold")


static func _validate_one_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 1, {"max_health": 125.0, "max_speed": 441.6})
	_expect_build(context, catalog, &"overcharged_thrusters", 1, {"max_health": 100.0, "max_speed": 537.6, "acceleration": 1035.0})
	_expect_build(context, catalog, &"vector_jets", 1, {"acceleration": 1080.0, "drag": 875.0})
	_expect_build(context, catalog, &"auto_repair", 1, {"auto_repair_enabled": true, "auto_repair_delay": 5.0, "auto_repair_rate": 10.0})
	_expect_build(context, catalog, &"nanite_reservoir", 1, {"auto_repair_enabled": true, "max_health": 135.0, "max_speed": 432.0})
	_expect_build(context, catalog, &"capacitor_bank", 1, {"shield_capacity": 130.0, "shield_regeneration": 33.0})
	_expect_build(context, catalog, &"quick_charge", 1, {"shield_capacity": 100.0, "shield_regeneration": 36.6, "shield_block_cost": 23.75})
	_expect_build(context, catalog, &"wide_emitter", 1, {"shield_arc_degrees": 160.0, "shield_continuous_drain": 23.0})
	_expect_build(context, catalog, &"efficient_field", 1, {"shield_continuous_drain": 17.0, "shield_regeneration_delay": 1.25})
	_expect_build(context, catalog, &"heavy_rounds", 1, {"projectile_damage": 33.75, "fire_rate": 3.2})
	_expect_build(context, catalog, &"rapid_cycling", 1, {"projectile_damage": 25.0, "fire_rate": 5.2})
	_expect_build(context, catalog, &"rail_accelerant", 1, {"projectile_damage": 27.5, "projectile_speed": 1215.0})
	_expect_build(context, catalog, &"extended_magazine", 1, {"magazine_size": 12, "reload_duration": 1.5})
	_expect_build(context, catalog, &"quick_loader", 1, {"magazine_size": 7, "reload_duration": 1.125})
	_expect_build(context, catalog, &"twin_shot", 1, {"projectile_count": 2, "projectile_spread_degrees": 10.0, "projectile_damage": 17.5})
	_expect_build(context, catalog, &"piercing_rounds", 1, {"pierce_count": 1, "projectile_damage": 27.0})
	_expect_build(context, catalog, &"ricochet_rounds", 1, {"ricochet_count": 1, "projectile_speed": 972.0})


static func _validate_expanded_stat_surface(context: TestContext, catalog: CardCatalog) -> void:
	context.expect_equal(StatSystem.FLOAT_STATS.size() + StatSystem.INTEGER_STATS.size(), 41, "cards can modify forty-one authoritative numeric combat stats")
	_expect_build(context, catalog, &"mine_layer", 1, {"mine_layer_enabled": true, "mine_capacity": 10})
	_expect_build(context, catalog, &"mine_layer", 2, {"mine_layer_enabled": true, "mine_capacity": 20})
	_expect_build(context, catalog, &"hunter_missiles", 1, {"missile_launcher_enabled": true, "missile_capacity": 20})
	_expect_build(context, catalog, &"hunter_missiles", 2, {"missile_launcher_enabled": true, "missile_capacity": 40})
	_expect_build(context, catalog, &"cloak", 1, {"cloak_enabled": true, "cloak_capacity": 1})
	_expect_build(context, catalog, &"cloak", 2, {"cloak_enabled": true, "cloak_capacity": 2})
	_expect_build(context, catalog, &"rangefinder", 1, {"projectile_lifetime": 3.125, "projectile_speed": 990.0, "fire_rate": 3.8})
	_expect_build(context, catalog, &"compact_deflector", 1, {"shield_arc_degrees": 132.0, "shield_block_cost": 23.0})
	_expect_build(context, catalog, &"vectored_nozzles", 1, {"acceleration": 972.0, "shield_acceleration_factor": 0.78})
	_expect_build(context, catalog, &"storm_of_one", 1, {"magazine_size": 5, "fire_rate": 8.0, "reload_duration": 0.75, "projectile_damage": 20.0})
	_expect_build(context, catalog, &"repair_gel", 1, {"auto_repair_enabled": true, "auto_repair_delay": 4.6, "auto_repair_rate": 8.96})
	_expect_build(context, catalog, &"rebound_shields", 1, {"rebound_shield_enabled": true, "rebound_damage_factor": 0.5, "rebound_range_factor": 0.5})
	_expect_build(context, catalog, &"rebound_shields", 2, {"rebound_shield_enabled": true, "rebound_damage_factor": 0.625, "rebound_range_factor": 0.625})
	_expect_build(context, catalog, &"kinetic_vent", 1, {"kinetic_vent_enabled": true, "kinetic_vent_impulse": 432.0})
	_expect_build(context, catalog, &"kinetic_vent", 2, {"kinetic_vent_enabled": true, "kinetic_vent_impulse": 518.4})
	_expect_build(context, catalog, &"breakaway_thrusters", 1, {"breakaway_thrusters_enabled": true, "breakaway_cooldown": 6.8})
	_expect_build(context, catalog, &"breakaway_thrusters", 2, {"breakaway_thrusters_enabled": true, "breakaway_cooldown": 5.78})


static func _validate_repeated_stack_values(context: TestContext, catalog: CardCatalog) -> void:
	_expect_build(context, catalog, &"reinforced_hull", 3, {"max_health": 175.0, "max_speed": 373.77024})
	_expect_build(context, catalog, &"overcharged_thrusters", 3, {"max_health": 100.0, "max_speed": 674.36544, "acceleration": 1368.7875})
	_expect_build(context, catalog, &"vector_jets", 3, {"acceleration": 1555.2, "drag": 1367.1875})
	_expect_build(context, catalog, &"auto_repair", 3, {"auto_repair_enabled": true, "auto_repair_rate": 15.625})
	_expect_build(context, catalog, &"capacitor_bank", 3, {"shield_capacity": 190.0, "shield_regeneration": 39.93})
	_expect_build(context, catalog, &"quick_charge", 3, {"shield_capacity": 100.0, "shield_regeneration": 54.47544, "shield_block_cost": 21.434375})
	_expect_build(context, catalog, &"wide_emitter", 3, {"shield_arc_degrees": 240.0, "shield_continuous_drain": 30.4175})
	_expect_build(context, catalog, &"efficient_field", 3, {"shield_continuous_drain": 12.2825, "shield_regeneration_delay": 1.25})
	_expect_build(context, catalog, &"heavy_rounds", 3, {"projectile_damage": 61.509375, "fire_rate": 2.048})
	_expect_build(context, catalog, &"rapid_cycling", 3, {"projectile_damage": 25.0, "fire_rate": 8.788})
	_expect_build(context, catalog, &"rail_accelerant", 3, {"projectile_damage": 33.275, "projectile_speed": 2214.3375})
	_expect_build(context, catalog, &"extended_magazine", 3, {"magazine_size": 20, "reload_duration": 1.5})
	_expect_build(context, catalog, &"quick_loader", 3, {"magazine_size": 5, "reload_duration": 0.6328125})
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


static func _validate_rebalanced_outliers(context: TestContext, catalog: CardCatalog) -> void:
	var cascade := StatSystem.derive({&"cascade_barrier": 1}, catalog)
	context.expect_approx(cascade.shield_capacity, 120.0, "Cascade Barrier keeps its capacity identity")
	context.expect_approx(cascade.shield_block_cost, 17.5, "Cascade Barrier no longer halves block cost per stack")
	var siphon := StatSystem.derive({&"shield_siphon": 1}, catalog)
	context.expect_approx(siphon.shield_continuous_drain, 15.0, "Shield Siphon uses its contained Rare-tier drain reduction")
	context.expect_approx(siphon.shield_regeneration, 36.0, "Shield Siphon retains its regeneration identity")

	var trident := StatSystem.derive({&"trident_array": 1}, catalog)
	var micro := StatSystem.derive({&"micro_barrage": 1}, catalog)
	context.expect_approx(trident.projectile_damage, 16.25, "Trident Array pays its increased per-projectile damage cost")
	context.expect_true(trident.projectile_damage * trident.projectile_count < micro.projectile_damage * micro.projectile_count, "Micro Barrage now wins raw volley damage")
	context.expect_true(trident.pierce_count > micro.pierce_count and trident.projectile_speed > micro.projectile_speed, "Trident Array retains precision and piercing advantages")

	var drum := StatSystem.derive({&"drum_spring": 1}, catalog)
	var extended := StatSystem.derive({&"extended_magazine": 1}, catalog)
	context.expect_true(drum.magazine_size < extended.magazine_size and drum.fire_rate > extended.fire_rate, "Drum Spring trades magazine depth for a firing-cadence bonus")
	var foils := StatSystem.derive({&"braking_foils": 1}, catalog)
	var dampers := StatSystem.derive({&"inertial_dampers": 1}, catalog)
	context.expect_true(foils.drag > dampers.drag and foils.max_speed < dampers.max_speed, "Braking Foils own the strongest Uncommon braking at a speed cost")
	var wide := StatSystem.derive({&"wide_emitter": 1}, catalog)
	var broadside := StatSystem.derive({&"broadside_field": 1}, catalog)
	context.expect_true(wide.shield_arc_degrees > broadside.shield_arc_degrees and wide.shield_continuous_drain > broadside.shield_continuous_drain, "Wide Emitter trades efficiency for the widest immediate arc")
	var hot := StatSystem.derive({&"hot_load": 1}, catalog)
	var rapid := StatSystem.derive({&"rapid_cycling": 1}, catalog)
	context.expect_true(hot.fire_rate > rapid.fire_rate and hot.magazine_size < rapid.magazine_size, "Hot Load trades magazine depth for the higher cadence")

	var automatic := StatSystem.derive({&"auto_repair": 1}, catalog)
	var gel := StatSystem.derive({&"repair_gel": 1}, catalog)
	context.expect_true(automatic.auto_repair_rate > gel.auto_repair_rate and automatic.auto_repair_delay > gel.auto_repair_delay, "Auto-Repair favors throughput while Repair Gel starts sooner")
	var singularity := StatSystem.derive({&"singularity_lance": 1}, catalog)
	var shredder := StatSystem.derive({&"reality_shredder": 1}, catalog)
	context.expect_true(singularity.projectile_damage > shredder.projectile_damage, "Singularity Lance owns focused per-projectile damage")
	context.expect_true(singularity.pierce_count > shredder.pierce_count and singularity.ricochet_count > shredder.ricochet_count, "Singularity Lance owns the deepest single-beam traversal")
	context.expect_true(shredder.projectile_count > singularity.projectile_count and shredder.fire_rate > singularity.fire_rate, "Reality Shredder retains the multibeam fire-rate identity")


static func _validate_balance_pass_behavior(context: TestContext, catalog: CardCatalog) -> void:
	var base := CombatStats.create_base()
	var nozzles := StatSystem.derive({&"vectored_nozzles": 1}, catalog)
	var pursuit := StatSystem.derive({&"pursuit_screen": 1}, catalog)
	var base_step := MovementSystem.step_velocity(Vector2.ZERO, Vector2.RIGHT, base, 0.1, true)
	var nozzle_step := MovementSystem.step_velocity(Vector2.ZERO, Vector2.RIGHT, nozzles, 0.1, true)
	var pursuit_step := MovementSystem.step_velocity(Vector2.ZERO, Vector2.RIGHT, pursuit, 0.1, true)
	context.expect_approx(nozzle_step.x / base_step.x, 1.1232, "Nozzles combines both bonuses into 12.32 percent shielded acceleration")
	context.expect_approx(pursuit_step.x / base_step.x, 1.3, "Pursuit Screen delivers its larger shielded movement benefit")
	context.expect_true(pursuit.shield_arc_degrees < nozzles.shield_arc_degrees, "Pursuit Screen retains its coverage tradeoff")
	var gyros := StatSystem.derive({&"combat_gyros": 1}, catalog)
	var velocity := Vector2(200.0, 0.0)
	context.expect_true(MovementSystem.step_velocity(velocity, Vector2.ZERO, gyros, 0.1).length() < MovementSystem.step_velocity(velocity, Vector2.ZERO, base, 0.1).length(), "Combat Gyros improves stopping after input release")
	context.expect_equal(MovementSystem.step_velocity(velocity, Vector2.LEFT, gyros, 0.1), MovementSystem.step_velocity(velocity, Vector2.LEFT, base, 0.1), "Passive braking does not change powered direction reversals")
	# Test created projectiles: derived speed alone hid the former dead bonus.
	var laser := StatSystem.derive({&"laser_repeater": 1}, catalog)
	var reference := ProjectileState.create(1, 1, 1, Vector2.ZERO, 0.0, laser)
	for stacks in [1, 3]:
		for existing_beam in [false, true]:
			var build := {&"beam_emitter": stacks}
			if existing_beam:
				build[&"laser_repeater"] = 1
			var stats := StatSystem.derive(build, catalog)
			var beam := ProjectileState.create(2, 1, 2, Vector2.ZERO, 0.0, stats)
			context.expect_true(beam.is_beam, "Beam Emitter creates a beam independently or in a mixed build")
			context.expect_approx(beam.velocity.length(), reference.velocity.length(), "Beam Emitter retains fixed beam travel speed")
			context.expect_approx(beam.velocity.length() * beam.lifetime_remaining, 720.0 * pow(1.5, stacks), "Beam Emitter lifetime bonus extends actual beam reach at each stack")
			context.expect_approx(beam.damage, (laser.projectile_damage if existing_beam else base.projectile_damage) * pow(1.05, stacks), "Beam Emitter keeps its stacking damage benefit")


static func _validate_second_balance_pass(context: TestContext, catalog: CardCatalog) -> void:
	for support in [{}, {&"extended_magazine": 1}]:
		var before := StatSystem.derive(support, catalog)
		var build: Dictionary = support.duplicate()
		build[&"storm_of_one"] = 1
		var after := StatSystem.derive(build, catalog)
		context.expect_true(_continuous_fire_damage(after) > _continuous_fire_damage(before), "Storm of One improves sustained output standalone and with magazine support")
		context.expect_true(after.projectile_damage * after.fire_rate > before.projectile_damage * before.fire_rate, "Storm of One retains its burst pressure")
		var estimated := float(StatSystem.weapon_output(after).sustained)
		context.expect_true(absf(_continuous_fire_damage(after) / estimated - 1.0) < 0.03, "Potential sustained output agrees with firing simulation within tick and opening-magazine effects")
	var single := CombatStats.create_base()
	single.magazine_size = 1
	single.reload_duration = 0.1
	single.fire_rate = 0.25
	context.expect_approx(float(StatSystem.weapon_output(single).sustained), 6.25, "Reload estimate respects a longer shot cooldown for a one-shot magazine")
	for hull_build in [{}, {&"ablative_shell": 3}]:
		var before := StatSystem.derive(hull_build, catalog)
		var build: Dictionary = hull_build.duplicate()
		build[&"adaptive_chassis"] = 1
		var after := StatSystem.derive(build, catalog)
		context.expect_approx(after.max_health / before.max_health, 1.15, "Uncommon Adaptive Chassis preserves proportional hull scaling on base and hull builds")
		context.expect_approx(after.acceleration / before.acceleration, 1.1, "Adaptive Chassis retains its acceleration benefit")
	var fortress := StatSystem.derive({&"fortress_emitter": 1}, catalog)
	context.expect_approx(fortress.shield_capacity, 160.0, "Rare Fortress Emitter retains its hit-buffer identity")
	context.expect_true(fortress.max_speed < CombatStats.create_base().max_speed and fortress.shield_continuous_drain > CombatStats.create_base().shield_continuous_drain, "Fortress Emitter retains both compensating drawbacks")


static func _continuous_fire_damage(stats: CombatStats) -> float:
	var weapon := WeaponState.new()
	weapon.reset(stats)
	var shots := 0
	var duration := 120.0
	var delta := 1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND
	for tick in roundi(duration / delta):
		weapon.step(stats, delta)
		if weapon.try_fire(stats, false):
			shots += 1
	return shots * stats.projectile_damage * stats.projectile_count / duration


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
		"rebound_damage_factor": 100.0,
		"rebound_range_factor": 100.0,
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
	context.expect_approx(stats.rebound_damage_factor, 1.0, "rebound damage guardrail applies")
	context.expect_approx(stats.rebound_range_factor, 1.0, "rebound range guardrail applies")
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
