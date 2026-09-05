extends RefCounted

const Identity = preload("res://src/client/ui/card_identity.gd")
const Hover = preload("res://src/client/ui/card_hover_button.gd")


static func run(context: TestContext, parent: Node) -> void:
	var catalog := CardCatalog.create_default()
	for id in catalog.all_ids():
		var card := catalog.get_card(id)
		context.expect_true(Identity.ROLES.has(Identity.family(card)), "%s maps to a supported mechanic icon and role" % id)
		var summary := Identity.summarize({}, card, catalog, StatSystem.compare_pick({}, card, catalog))
		context.expect_true(not summary.rows.is_empty() and summary.rows.size() <= 3, "%s has one to three effective highlights" % id)
	for pair in [[&"beam_emitter", &"beam"], [&"mine_layer", &"mine"], [&"cloak", &"cloak"], [&"hunter_missiles", &"missile"], [&"piercing_rounds", &"pierce"], [&"ricochet_rounds", &"ricochet"], [&"twin_shot", &"scatter"], [&"reinforced_hull", &"hull"], [&"glass_reactor", &"mobility"]]:
		context.expect_equal(Identity.family(catalog.get_card(pair[0])), pair[1], "mechanic identity follows actual definition for %s" % pair[0])
	var glass := catalog.get_card(&"glass_reactor")
	var summary := Identity.summarize({}, glass, catalog, StatSystem.compare_pick({}, glass, catalog))
	context.expect_true(summary.rows.any(func(row: Dictionary) -> bool: return row.kind == &"drawback" and row.property == &"max_health" and row.text.contains("100 → 85")), "effective preview prominently retains hull tradeoff")
	var reload_card := catalog.get_card(&"quick_loader")
	summary = Identity.summarize({}, reload_card, catalog, StatSystem.compare_pick({}, reload_card, catalog))
	context.expect_true(summary.rows.any(func(row: Dictionary) -> bool: return row.kind == &"benefit" and row.property == &"reload_duration"), "shorter reload is a benefit, not a red numerical decrease")
	var beam := catalog.get_card(&"beam_emitter")
	summary = Identity.summarize({}, beam, catalog, StatSystem.compare_pick({}, beam, catalog))
	context.expect_true(String(summary.rows[0].text).begins_with("Unlock:"), "first beam pick advertises weapon transformation")
	summary = Identity.summarize({&"beam_emitter": 1}, beam, catalog, StatSystem.compare_pick({&"beam_emitter": 1}, beam, catalog))
	context.expect_false(summary.rows.any(func(row: Dictionary) -> bool: return String(row.text).begins_with("Unlock:")), "repeat special pick never advertises a second unlock")
	var saturated := {&"twin_shot": 50}
	var twin := catalog.get_card(&"twin_shot")
	summary = Identity.summarize(saturated, twin, catalog, StatSystem.compare_pick(saturated, twin, catalog))
	context.expect_true(String(summary.note).contains("At limit"), "saturated stat previews label limits")
	context.expect_true(summary.rows.any(func(row: Dictionary) -> bool: return row.property == &"projectile_count" and row.text.contains("6 → 6")), "capped projectile preview reports effective unchanged values")
	var broad := CardDefinition.new()
	broad.card_id = &"test_tradeoff"
	broad.multiplicative_modifiers = {&"max_speed": 1.2, &"acceleration": 1.3, &"max_health": 0.8, &"projectile_damage": 0.7, &"reload_duration": 2.0}
	# compare_pick requires the proposed definition in the catalog.
	var explicit_rows: Array[Dictionary] = [
		{"property": &"max_speed", "before": 100.0, "after": 120.0, "unchanged": false, "limited": false},
		{"property": &"acceleration", "before": 100.0, "after": 130.0, "unchanged": false, "limited": false},
		{"property": &"max_health", "before": 100.0, "after": 80.0, "unchanged": false, "limited": false},
		{"property": &"projectile_damage", "before": 100.0, "after": 70.0, "unchanged": false, "limited": false},
		{"property": &"reload_duration", "before": 1.0, "after": 2.0, "unchanged": false, "limited": false},
	]
	summary = Identity.summarize({}, broad, catalog, explicit_rows)
	context.expect_equal(summary.rows.size(), 3, "many effects retain compact headline count")
	context.expect_true(String(summary.note).contains("2 more tradeoffs"), "unshown negative effects explicitly counted")
	context.expect_equal(summary.omitted, 2, "summary offers complete omitted change count")
	var client := (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
	parent.add_child(client)
	client.draft_controller._show_draft_offer({"card_ids": ["glass_reactor", "beam_emitter", "twin_shot"]})
	var button := client.draft_controller.draft_buttons[0] as Button
	context.expect_true(button.get_node_or_null("CardContent/Details/MechanicIcon") != null, "actual draft displays vector family icon")
	context.expect_equal((button.get_node("CardContent/Details/Category") as Label).text, "FLIGHT CONTROL", "actual draft displays build role")
	context.expect_true(button.get_node("CardContent/Details/EffectiveSummary").get_child_count() >= 3, "actual draft displays effective highlights")
	context.expect_true(button.tooltip_text.contains(glass.description), "full description remains available in details")
	client.queue_free()
