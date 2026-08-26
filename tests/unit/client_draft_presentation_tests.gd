class_name ClientDraftPresentationTests
extends RefCounted


static func run(context: TestContext, tree_parent: Node) -> void:
	var packed_scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := packed_scene.instantiate()
	tree_parent.add_child(client)
	client.latest_match_payload = {
		"state_name": "DRAFT",
		"round_number": 1,
		"heat_number": 0,
		"deadline_tick": 1200,
		"builds": {},
	}
	var card_ids: Array[StringName] = [
		&"overcharged_thrusters",
		&"capacitor_bank",
		&"rapid_cycling",
		&"rail_accelerant",
		&"piercing_rounds",
	]
	client._show_draft_offer({
		"offer_token": "render-test-token",
		"card_ids": card_ids,
		"deadline_tick": 1800,
	})
	context.expect_true(client.lobby_panel.custom_minimum_size.x >= 640.0, "online lobby uses the enlarged interface width")
	context.expect_true(client.draft_panel.custom_minimum_size.x >= 1200.0, "draft interface uses the enlarged readable width")
	context.expect_true(client.draft_panel.visible, "human draft panel renders when a private offer arrives")
	context.expect_true(client.draft_title.text.contains("30.0s"), "rendered draft countdown begins from the authoritative 30-second deadline")
	context.expect_equal(client.draft_buttons.size(), 5, "human draft renders all five offered cards")
	for index in client.draft_buttons.size():
		var button := client.draft_buttons[index] as Button
		context.expect_true(button.visible, "draft card %d is visible" % (index + 1))
		context.expect_true(button.custom_minimum_size.y >= 400.0, "draft card %d uses the enlarged card layout" % (index + 1))
		context.expect_true(button.text.contains("STACK 0 → 1"), "draft card %d renders its stack change" % (index + 1))
		context.expect_false(button.text.contains("NO LIMIT"), "draft card %d avoids repeating the global unlimited-stack rule" % (index + 1))
		context.expect_false(button.text.contains("% DROP"), "draft card %d keeps rarity out of the main body" % (index + 1))
		var rarity_label := client.draft_rarity_labels[index] as Label
		context.expect_true(rarity_label.visible and rarity_label.text.contains("TIER DROP"), "draft card %d renders rarity in a bottom badge" % (index + 1))
		context.expect_true(rarity_label.get_theme_font_size("font_size") < button.get_theme_font_size("font_size"), "draft card %d rarity uses smaller print" % (index + 1))
		context.expect_equal(button.get_meta("card_id"), card_ids[index], "draft card %d keeps its selectable card identity" % (index + 1))
		context.expect_true(button.get_theme_stylebox("normal") is StyleBoxFlat, "draft card %d renders a category panel" % (index + 1))
		var normal_style := button.get_theme_stylebox("normal") as StyleBoxFlat
		context.expect_true(normal_style.bg_color.a >= 0.85, "draft card %d uses a readable opaque background" % (index + 1))
		var card: CardDefinition = client.card_catalog.get_card(card_ids[index])
		context.expect_approx(normal_style.border_color.r, card.rarity_color().r, "draft card %d border reflects rarity" % (index + 1))
	client._select_draft_card(0)
	context.expect_true((client.draft_buttons[0] as Button).text.contains("SELECTED"), "chosen draft card renders its locked selection")
	for button_value in client.draft_buttons:
		context.expect_true((button_value as Button).disabled, "all draft choices lock after selection")
	client._show_draft_offer({
		"offer_token": "rarity-precision-token",
		"card_ids": [&"reality_shredder", &"chronal_shield", &"sunbeam_core", &"aegis_matrix", &"hollow_points"],
		"deadline_tick": 1800,
	})
	context.expect_true(client.draft_rarity_labels[0].text.contains("0.50%"), "unobtanium card badge renders the rebalanced fractional chance")
	context.expect_true(client.draft_rarity_labels[1].text.contains("1.2%"), "mythical card badge renders fractional chance precision")
	tree_parent.remove_child(client)
	client.free()
