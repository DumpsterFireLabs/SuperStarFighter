extends RefCounted


static func run(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	var baseline: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/stat_derivation_baseline.json"))
	for row in baseline:
		var stats := StatSystem.derive({StringName(row.id): int(row.stacks)}, catalog)
		var values := {}
		for key in CombatStats.get_stat_property_names() + StatSystem.SPECIAL_FLAGS:
			values[key] = stats.get(key)
		context.expect_equal(JSON.stringify(values, "", true, true).sha256_text(), row.hash, "every card at 1/3/20 stacks preserves authoritative derived values: %s/%s" % [row.id, row.stacks])
	context.expect_equal(StatMetadata.numeric_descriptors().size(), 41, "all numeric stats have one descriptor")
	for descriptor in StatMetadata.numeric_descriptors():
		context.expect_true(not descriptor.label.is_empty() and not descriptor.short_label.is_empty(), "stat names are explicit")
		context.expect_true(descriptor.minimum <= descriptor.maximum, "descriptor bounds are ordered")
		context.expect_equal(descriptor.bounded(-10000), int(descriptor.minimum) if descriptor.integer else descriptor.minimum, "descriptor applies canonical lower bound")
	context.expect_equal(StatMetadata.format_value(&"shield_damage_heal_fraction", 0.125), "12.50%", "fractional healing displays as a percentage")
	context.expect_equal(StatMetadata.format_value(&"reload_duration", 1.5), "1.50s", "time stats display their unit")
	context.expect_equal(StatMetadata.format_value(&"shield_arc_degrees", 120), "120°", "angles display degrees")
	context.expect_equal(StatMetadata.format_value(&"magazine_size", 8), "8", "integer counts remain exact")
	context.expect_equal(StatMetadata.change_kind(&"reload_duration", -0.2), &"benefit", "shorter cooldown is beneficial")
	context.expect_equal(StatMetadata.change_kind(&"projectile_damage", -5), &"drawback", "lower damage remains a drawback")
	context.expect_equal(StatMetadata.change_kind(&"drag", -5), &"neutral", "handling preference stays contextual")
	var capped := CombatStats.create_base()
	capped.shield_capacity = 5
	capped.shield_depletion_threshold = 100
	StatSystem._apply_clamps(capped)
	context.expect_equal(capped.shield_depletion_threshold, 5.0, "dynamic depletion ceiling follows final shield capacity")
	var card := CardDefinition.new()
	card.additive_modifiers = {&"shield_damage_heal_fraction": 0.05, &"reload_duration": -0.2}
	var rows := preload("res://src/client/ui/card_details_text.gd").modifier_rows(card, 2)
	var fraction_row: Dictionary = {}
	for row in rows:
		if row.name == StatMetadata.label(&"shield_damage_heal_fraction"):
			fraction_row = row
	context.expect_equal(fraction_row.get("each"), "+5% each", "shared modifier rows use the same fraction formatter")
	context.expect_equal(fraction_row.get("total"), "+10% total", "shared formatter scales stacks in display units")
	context.expect_true(preload("res://src/client/ui/card_details_text.gd").tooltip(card, 2).contains("+10% total"), "accessible tooltip consumes shared modifier rows")

	var typed := StatSystem.compare_pick_typed({}, catalog.get_card(&"quick_loader"), catalog)
	var legacy := StatSystem.compare_pick({}, catalog.get_card(&"quick_loader"), catalog)
	context.expect_true(typed[0] is StatChange, "production comparison uses typed stat change")
	for index in typed.size():
		context.expect_equal(typed[index].to_dictionary(), legacy[index], "legacy comparison serialization matches typed values")
	var identity = preload("res://src/client/ui/card_identity.gd")
	context.expect_equal(identity.summarize_typed({}, catalog.get_card(&"quick_loader"), catalog, typed), identity.summarize({}, catalog.get_card(&"quick_loader"), catalog, legacy), "typed card UI and compatibility summary agree")
