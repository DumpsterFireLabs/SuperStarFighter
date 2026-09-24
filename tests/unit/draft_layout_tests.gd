extends RefCounted

static func run(context: TestContext, parent: Node) -> void:
	var window := parent.get_window()
	var saved := [window.size, window.content_scale_size, window.content_scale_mode, window.content_scale_aspect]
	var client = load("res://scenes/client/client_main.tscn").instantiate()
	parent.add_child(client)
	client._dismiss_splash(true)
	client.bridge.session.local_peer_id = 2
	client.latest_match_payload = {"state_name": "DRAFT", "round_number": 1, "builds": {2: {}}}
	var draft = client.draft_controller
	var offer := {"offer_token": "layout", "deadline_tick": 2000, "card_ids": [&"heavy_rounds", &"quick_loader", &"glass_reactor", &"ramming_shields", &"heavy_rounds"]}
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440), Vector2i(1024, 768)]:
		window.size = resolution
		window.content_scale_size = Vector2i(1920, 1080)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		for cycle in range(2):
			draft._show_draft_bye(2000)
			await _settle(parent)
			draft.show_draft_offer(offer)
			draft.update_countdown(2000, 20.0)
			await _settle(parent)
			var base_size: Vector2 = draft.draft_panel.size
			draft.select_draft_card(0)
			await _settle(parent)
			context.expect_true(draft.draft_panel.size.y <= base_size.y + 100.0, "first and repeated confirmation rows stay compact at %s" % resolution)
			context.expect_true(draft.draft_panel.size.is_equal_approx(draft.draft_panel.get_combined_minimum_size()), "draft drops transient wrapped-text height")
			var visible_rect: Rect2 = draft.draft_panel.get_global_rect()
			context.expect_true(window.get_visible_rect().encloses(visible_rect), "draft confirmation fits inside viewport at %s" % resolution)
			draft.cancel_draft_confirmation()
			await _settle(parent)
			context.expect_equal(draft.draft_panel.size, base_size, "cancelling restores original draft size")
			draft._show_draft_bye(2000)
			await _settle(parent)
			context.expect_true(draft.draft_panel.size.y < 400.0, "bye panel shrinks after a five-card offer")
	client.free()
	window.size = saved[0]
	window.content_scale_size = saved[1]
	window.content_scale_mode = saved[2]
	window.content_scale_aspect = saved[3]
	await _settle(parent)


static func _settle(parent: Node) -> void:
	for frame in range(3):
		await parent.get_tree().process_frame
