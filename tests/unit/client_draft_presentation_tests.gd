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
	context.expect_true(client.connection_controller.lobby_panel.custom_minimum_size.x >= 640.0, "online lobby uses the enlarged interface width")
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
		var card_name_label := button.get_node("CardContent/Details/CardName") as Label
		context.expect_true(rarity_label.get_theme_font_size("font_size") < card_name_label.get_theme_font_size("font_size"), "draft card %d rarity uses smaller print" % (index + 1))
		context.expect_equal(button.get_meta("card_id"), card_ids[index], "draft card %d keeps its selectable card identity" % (index + 1))
		context.expect_true(button.get_theme_stylebox("normal") is StyleBoxFlat, "draft card %d renders a category panel" % (index + 1))
		var normal_style := button.get_theme_stylebox("normal") as StyleBoxFlat
		context.expect_true(normal_style.bg_color.a >= 0.85, "draft card %d uses a readable opaque background" % (index + 1))
		var card: CardDefinition = client.card_catalog.get_card(card_ids[index])
		context.expect_approx(normal_style.border_color.r, card.rarity_color().r, "draft card %d border reflects rarity" % (index + 1))
	var draft_hover := client.draft_buttons[0] as CardHoverButton
	context.expect_true(draft_hover != null and draft_hover.card_definition.card_id == card_ids[0], "draft choices use the same graphical hover-card component as build inspection")
	context.expect_true(draft_hover.tooltip_text.contains("STACKS AFTER PICK"), "draft hover details describe the projected stack count")
	var draft_preview := draft_hover._make_custom_tooltip(draft_hover.tooltip_text) as PanelContainer
	context.expect_true(draft_preview != null and draft_preview.name == "CardPreview", "draft hover opens the rarity-styled graphical card preview")
	draft_preview.free()
	client._select_draft_card(0)
	context.expect_equal(client.pending_draft_index, 0, "clicking a draft card stages it for confirmation")
	context.expect_true(client.draft_confirmation_row.visible, "staged card displays explicit confirmation controls")
	context.expect_true(client.draft_confirmation_label.text.contains("OVERCHARGED THRUSTERS"), "confirmation names the card about to be locked")
	for button_value in client.draft_buttons:
		context.expect_false((button_value as Button).disabled, "staging a card keeps the draw changeable")
	client._cancel_draft_confirmation()
	context.expect_equal(client.pending_draft_index, -1, "choose another clears the staged card")
	context.expect_false(client.draft_confirmation_row.visible, "choose another dismisses confirmation controls")
	client._select_draft_card(0)
	client._confirm_draft_card()
	context.expect_equal(client.pending_draft_index, -1, "confirming clears the pending choice")
	context.expect_true((client.draft_buttons[0] as Button).text.contains("SELECTED"), "confirmed draft card renders its locked selection")
	for button_value in client.draft_buttons:
		context.expect_true((button_value as Button).disabled, "all draft choices lock only after confirmation")
	client._show_draft_offer({
		"offer_token": "rarity-precision-token",
		"card_ids": [&"reality_shredder", &"chronal_shield", &"sunbeam_core", &"aegis_matrix", &"hollow_points"],
		"deadline_tick": 1800,
	})
	context.expect_true(client.draft_rarity_labels[0].text.contains("0.50%"), "unobtanium card badge renders the rebalanced fractional chance")
	context.expect_true(client.draft_rarity_labels[1].text.contains("1.2%"), "mythical card badge renders fractional chance precision")
	client.bridge.session.local_peer_id = 7
	client.latest_match_payload["draft_bye_peer_id"] = 7
	client._update_match_presentation()
	context.expect_true(client.draft_title.text.contains("SKIPS THIS DRAFT"), "round winner sees a plain explanation of the draft bye")
	client.latest_match_payload.erase("draft_bye_peer_id")
	client.latest_match_payload["builds"] = {"7": {&"twin_shot": 5, &"heavy_rounds": 2}}
	client._show_draft_offer({"offer_token": "cap-feedback", "card_ids": [&"twin_shot"], "deadline_tick": 1800})
	var capped := client.draft_buttons[0] as CardHoverButton
	context.expect_true(capped.has_limited_effect(), "sixth Twin Shot detects the projectile count limit")
	context.expect_true((capped.get_node("CardContent/Details/Stack") as Label).text.contains("NO BENEFIT"), "draft exposes drawback-only pick without requiring hover")
	context.expect_true(capped.tooltip_text.contains("ACTUAL BUILD: BEFORE → AFTER"), "draft accessible details include actual derived build comparison")
	var before := StatSystem.derive({&"twin_shot": 5, &"heavy_rounds": 2}, client.card_catalog)
	var after := StatSystem.derive({&"twin_shot": 6, &"heavy_rounds": 2}, client.card_catalog)
	var rows: Dictionary = {}
	for row in capped.comparison_rows:
		rows[row.property] = row
	context.expect_equal(rows[&"projectile_count"].before, 6.0, "cap comparison starts at actual six-projectile limit")
	context.expect_equal(rows[&"projectile_count"].after, 6.0, "cap comparison does not promise an unavailable projectile")
	context.expect_approx(rows[&"projectile_damage"].before, before.projectile_damage, "comparison includes other owned cards in current damage")
	context.expect_approx(rows[&"projectile_damage"].after, after.projectile_damage, "comparison exposes actual damage drawback after the capped pick")
	context.expect_true(float(rows[&"projectile_damage"].after) < float(rows[&"projectile_damage"].before), "capped Twin Shot still visibly shows its damage penalty")
	client._select_draft_card(0)
	context.expect_true(client.draft_confirmation_label.text.contains("NO EFFECTIVE BENEFIT"), "confirmation retains the drawback-only warning")
	client._cancel_draft_confirmation()
	client.latest_match_payload["builds"] = {7: {}}
	client._show_draft_offer({"offer_token": "new-feedback", "card_ids": [&"twin_shot"], "deadline_tick": 1800})
	context.expect_false(capped.has_limited_effect(), "a reused offer button clears the previous build's cap warning")
	_validate_weapon_correction(context, client)
	tree_parent.remove_child(client)
	client.free()


static func _validate_weapon_correction(context: TestContext, client: Node) -> void:
	var world := AuthoritativeWorld.new()
	var pilot := world.add_peer(7)
	var view := client.network_world as NetworkWorldView
	view.local_peer_id = 7
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(1, 0, world.snapshot_states(), pilot.prediction_state())))
	pilot.weapon.ammunition = 2
	pilot.weapon.shot_sequence = 9
	pilot.weapon.request_reload(pilot.stats)
	pilot.weapon.step(pilot.stats, 0.3)
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(2, 0, world.snapshot_states(), pilot.prediction_state())))
	context.expect_true(view.local_weapon.reloading, "production client adopts authoritative mid-reload state")
	context.expect_approx(view.local_weapon.reload_remaining, pilot.weapon.reload_remaining, "production client corrects reload progress", 0.001)
	context.expect_equal(view.local_weapon.shot_sequence, 9, "production client corrects shot identity")
	view.prediction.predict(PlayerInputFrame.new(1, 1, Vector2.UP), pilot.stats, 1.0 / 60.0)
	pilot.alive = false
	world.respawn_peer(7, pilot.stats, Vector2(420, 340))
	# Deliberately skip the dead snapshot, as can happen on the unreliable channel.
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(3, 0, world.snapshot_states(), pilot.prediction_state())))
	context.expect_empty(view.prediction.buffered_inputs, "life generation clears old replay even when the death snapshot was lost")
	context.expect_false(view.local_weapon.reloading, "respawn clears stale reload in the production client")
	context.expect_equal(view.local_weapon.ammunition, pilot.stats.magazine_size, "respawn restores production client ammo immediately")
	context.expect_equal(view.local_weapon.shot_sequence, 0, "respawn resets production client shot identity")
