extends SceneTree

## Render the real ship draw path and sample the outer shield, not a colour helper.
var capture_path: String = "res://reports/shield-colours.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
	root.content_scale_size = Vector2i.ZERO
	RenderingServer.set_default_clear_color(Color("080e20"))
	var catalog := CardCatalog.create_default()
	var builds: Array[Dictionary] = [{}]
	var labels := ["BASE", "EPIC", "LEGENDARY", "MYTHICAL"]
	for rarity in [CardDefinition.Rarity.EPIC, CardDefinition.Rarity.LEGENDARY, CardDefinition.Rarity.MYTHICAL]:
		for card_id in catalog.all_ids():
			var card := catalog.get_card(card_id)
			if card.category == CardDefinition.Category.SHIELD and card.rarity == rarity:
				builds.append({card_id: 1})
				break
	if builds.size() != 4:
		push_error("Shield rarity fixtures missing from catalog")
		quit(1)
		return
	var samples: Array[Dictionary] = []
	for column in 3:
		_label(["NORMAL", "GUARD WINDOW", "GUARD CONFIRMED"][column], Vector2(230 + column * 340, 12))
	for row in builds.size():
		_label(labels[row], Vector2(16, 100 + row * 150))
		for column in 3:
			var ship := CombatShipView.new()
			ship.setup(samples.size() + 1, CombatStats.create_base(), Vector2(240 + column * 340, 100 + row * 150), Color("42e8ff"))
			ship.set_shield_build(builds[row], catalog)
			ship.show_combat_details = false
			ship.scale = Vector2.ONE * 2.0
			ship.combatant.shield.active = true
			ship.combatant.shield.perfect_guard_window_remaining = 0.2 if column == 1 else 0.0
			ship.combatant.shield.perfect_guard_feedback_remaining = 0.2 if column == 2 else 0.0
			ship.set_process(false)
			root.add_child(ship)
			samples.append({"ship": ship, "label": labels[row], "guard": column != 0})
	await process_frame
	await RenderingServer.frame_post_draw
	var failures := 0
	for reduced in [false, true]:
		for sample in samples:
			sample.ship.reduced_flashes = reduced
			sample.ship.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		for sample in samples:
			var ship := sample.ship as CombatShipView
			var outer := Vector2i(ship.global_position + Vector2(66, 0))
			var colour := frame.get_pixelv(outer)
			if not _near(colour, ship.shield_color):
				printerr("SHIELD_COLOUR_ERROR rarity=%s guard=%s reduced=%s actual=%s expected=%s" % [sample.label, sample.guard, reduced, colour, ship.shield_color])
				failures += 1
			var inner := frame.get_pixelv(Vector2i(ship.global_position + Vector2(44, 0)))
			if sample.guard and not _near(inner, Color.WHITE):
				printerr("SHIELD_COLOUR_ERROR missing guard indicator")
				failures += 1
		if not reduced and frame.save_png(capture_path) != OK:
			failures += 1
	if failures == 0:
		print("SHIELD_COLOURS_OK samples=24 guard_indicators=16")
	quit(0 if failures == 0 else 1)


func _near(actual: Color, expected: Color) -> bool:
	return absf(actual.r - expected.r) < 0.025 and absf(actual.g - expected.g) < 0.025 and absf(actual.b - expected.b) < 0.025


func _label(text: String, position: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	root.add_child(label)
