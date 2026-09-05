extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_combat_priority_contract(context)
	var client = load("res://scenes/client/client_main.tscn").instantiate()
	parent.add_child(client)
	client.input_profiles.set_scheme(InputProfileManager.Scheme.KEYBOARD_MOUSE, false)
	client.input_profiles.restore_active_defaults(false)
	client._dismiss_splash(true)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var connection = client.connection_controller
	connection.connection_tabs.current_tab = 2
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	context.expect_true(connection.connection_tabs.get_global_rect().encloses(connection.host_join_button.get_global_rect()), "host action is fully visible outside the scrolling fields")
	connection.host_password_field.grab_focus()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var host_scroll := connection.connection_tabs.get_child(2).get_child(0) as ScrollContainer
	context.expect_true(host_scroll.get_global_rect().encloses(connection.host_password_field.get_global_rect()), "keyboard focus scrolls the required hosting password into view")

	client.bridge.session.local_peer_id = 2
	client.bridge.session.latest_lobby_state = {"leader_id": 2}
	connection.connection_form_panel.hide()
	connection.lobby_panel.show()
	connection.lobby_options_button.grab_focus()
	connection._show_lobby_options()
	_press_key(client.get_viewport(), KEY_ESCAPE)
	await parent.get_tree().process_frame
	context.expect_false(connection.lobby_options_popup.visible, "Escape closes Match Setup instead of taking the pause path")
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), connection.lobby_options_button, "Match Setup restores focus to its opener")
	connection._show_ship_color_popup()
	_press_key(client.get_viewport(), KEY_ESCAPE)
	context.expect_false(connection.ship_color_popup.visible, "Escape closes ship appearance")
	client.input_profiles.set_scheme(InputProfileManager.Scheme.CONTROLLER, false)
	client.input_profiles.restore_active_defaults(false)
	connection._show_ship_color_popup()
	_press_pad(client.get_viewport(), JOY_BUTTON_B)
	context.expect_false(connection.ship_color_popup.visible, "controller Back shares the appearance close path")
	client.input_profiles.set_scheme(InputProfileManager.Scheme.KEYBOARD_MOUSE, false)

	connection.connection_screen.hide()
	client.latest_match_payload = {"state_name": "DRAFT", "round_number": 1, "builds": {2: {&"twin_shot": 5}}, "deadline_tick": 1800}
	client.draft_controller._show_draft_offer({"offer_token": "review", "deadline_tick": 1800, "card_ids": [&"twin_shot", &"reinforced_hull", &"beam_emitter", &"prismatic_lance", &"zero_point_loader"]})
	await parent.get_tree().process_frame
	var card := client.draft_controller.draft_buttons[0] as CardHoverButton
	card.grab_focus()
	_press_key(client.get_viewport(), KEY_I)
	await parent.get_tree().process_frame
	context.expect_true(client.card_inspector.visible, "keyboard Inspect opens real draft details")
	context.expect_equal(client.card_inspector.preview.get_meta("card_id"), &"twin_shot", "inspector presents the focused card's actual data")
	context.expect_true(client.network_world.input_blocked, "inspection blocks combat input")
	_press_key(client.get_viewport(), KEY_2)
	context.expect_equal(client.draft_controller.pending_draft_index, -1, "modal inspection cannot accidentally select a draft choice")
	_press_key(client.get_viewport(), KEY_ESCAPE)
	context.expect_false(client.card_inspector.visible, "Escape closes card inspection")
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), card, "closing inspection restores the source card")
	client.input_profiles.set_scheme(InputProfileManager.Scheme.CONTROLLER, false)
	_press_pad(client.get_viewport(), JOY_BUTTON_Y)
	context.expect_true(client.card_inspector.visible, "controller Y inspects the focused draft card")
	_press_pad(client.get_viewport(), JOY_BUTTON_B)
	context.expect_false(client.card_inspector.visible, "controller Back closes inspection")
	context.expect_false(client.network_world.input_blocked, "closing inspection releases its gameplay block")
	client.input_profiles.set_scheme(InputProfileManager.Scheme.KEYBOARD_MOUSE, false)
	client.draft_controller._select_draft_card(0)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var state := card.get_node("CardContent/Details/State") as Label
	context.expect_true(card.get_global_rect().encloses(state.get_global_rect()), "capped-card confirmation stays inside its card")
	var rarity := client.draft_controller.draft_rarity_labels[0] as Label
	context.expect_true(state.get_global_rect().end.y <= rarity.get_global_rect().position.y, "card selection and rarity footer do not overlap")
	for card_id in client.card_catalog.all_ids():
		client.latest_match_payload["builds"] = {2: {card_id: 20}}
		client.draft_controller._show_draft_offer({"offer_token": "fit", "deadline_tick": 1800, "card_ids": [card_id]})
		client.draft_controller._select_draft_card(0)
		await parent.get_tree().process_frame
		await parent.get_tree().process_frame
		var margin := card.get_node("CardContent") as MarginContainer
		var details := card.get_node("CardContent/Details") as VBoxContainer
		context.expect_true(details.get_combined_minimum_size().y <= margin.size.y - 96.0, "stacked %s decision content fits above its rarity footer" % card_id)

	client.latest_match_payload = {"state_name": "MATCH_RESULT", "match_winner": 2, "participant_peer_ids": [2], "scores": {2: {"round_wins": 3}}, "builds": {2: {&"beam_emitter": 1}}}
	client._update_match_presentation()
	await parent.get_tree().process_frame
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.results_rematch_button, "results focus starts on the recommended rematch action")
	var flow: Node = client.results_standings_container.find_child("FinalBuildCards", true, false)
	var chip := flow.get_child(0) as CardHoverButton
	chip.grab_focus()
	_press_key(client.get_viewport(), KEY_ENTER)
	context.expect_true(client.card_inspector.visible, "activating a result chip opens its details")
	_press_key(client.get_viewport(), KEY_ESCAPE)
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), chip, "result inspection restores the result chip")
	var feed := client.network_world.kill_feed as KillFeed
	feed.clear()
	feed.add_eliminations([{"killer_id": 2, "victim_id": 3, "reason": "combat"}, {"killer_id": 0, "victim_id": 3, "reason": "combat"}, {"killer_id": 0, "victim_id": 3, "reason": "disconnect"}], 42, 2, [{"peer_id": 2, "display_name": "A deliberately long pilot name"}, {"peer_id": 3, "display_name": "Another deliberately long pilot"}])
	feed.set_match_state("ACTIVE_HEAT")
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	for entry in feed.entries:
		var meaning := entry.node.find_child("EventMeaning", true, false) as Label
		context.expect_true(meaning.size.x >= meaning.get_theme_font("font").get_string_size(meaning.text, HORIZONTAL_ALIGNMENT_LEFT, -1, meaning.get_theme_font_size("font_size")).x, "kill-feed event meaning fits even beside long names")
	client.free()


static func _combat_priority_contract(context: TestContext) -> void:
	var layer := ProjectileLayer.new()
	layer.registry = ProjectileRegistry.new()
	layer.set_team_identity({2: 1, 3: 2}, 1, true)
	var stats := CombatStats.create_base()
	for index in ProjectileLayer.SIMPLIFY_PROJECTILE_THRESHOLD:
		layer.registry.add(ProjectileState.create(index + 1, 2 + index / 32, index, Vector2.ZERO, 0.0, stats))
	context.expect_true(layer.uses_compact_friendly_style(2), "dense friendly ordnance uses the compact body without decorative team outlines")
	context.expect_false(layer.uses_compact_friendly_style(3), "hostile ordnance retains full threat geometry under identical density")
	layer.set_team_identity({2: 1, 3: 2}, 0, true)
	context.expect_false(layer.uses_compact_friendly_style(2), "neutral spectators do not attenuate an arbitrary team")
	layer.registry = ProjectileRegistry.new()
	context.expect_false(layer.uses_compact_friendly_style(2), "low-density scenes restore normal projectile detail")
	layer.free()
	var ship := CombatShipView.new()
	ship.position = Vector2(900, 0)
	ship.set_combat_focus(Vector2.ZERO, true)
	context.expect_false(ship.show_combat_details, "distant ships suppress names and build decoration in crowded combat")
	ship.set_combat_focus(Vector2(800, 0), true)
	context.expect_true(ship.show_combat_details, "nearby threats retain their identity and build details")
	ship.local_control = true
	ship.set_combat_focus(Vector2.ZERO, true)
	context.expect_true(ship.show_combat_details, "local identity remains visible regardless of crowd or camera distance")
	ship.local_control = false
	ship.set_combat_focus(Vector2.ZERO, false)
	context.expect_true(ship.show_combat_details, "normal scenes restore distant ship detail")
	ship.free()


static func _press_key(viewport: Viewport, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event)


static func _press_pad(viewport: Viewport, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	viewport.push_input(event)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event)
