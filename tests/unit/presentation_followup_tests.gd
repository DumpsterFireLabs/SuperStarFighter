extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	var catalog := CardCatalog.create_default()
	context.expect_equal(CardIdentity.summary(catalog.get_card(&"quick_loader")), "Shorten your reload downtime.", "reload headline explains the tactical effect")
	context.expect_equal(CardIdentity.summary(catalog.get_card(&"extended_magazine")), "Fire more shots before reloading.", "magazine headline distinguishes another weapon uptime card")
	context.expect_equal(CardIdentity.summary(catalog.get_card(&"twin_shot")), "Add projectiles to each volley.", "multishot headline describes volley count")
	for viewport in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(5120, 1440)]:
		for preferred in [Vector2(150, 40), Vector2(150, viewport.y - 64), Vector2(viewport.x - 154, 40), Vector2(viewport.x - 154, viewport.y - 64)]:
			var occupied: Array[Rect2] = [Rect2(0, 0, 440, 240), Rect2(viewport - Vector2(300, 36), Vector2(300, 36))]
			for index in 3:
				var point := OffscreenIndicatorLayer.layout_objective_point(preferred, viewport, occupied)
				context.expect_true(point.is_finite(), "objective layout finds a place near crowded viewport corners")
				var bounds := OffscreenIndicatorLayer.objective_bounds(point)
				context.expect_true(Rect2(Vector2.ZERO, viewport).encloses(bounds), "objective icon and caption stay on screen")
				context.expect_false(occupied.any(func(rect: Rect2) -> bool: return rect.intersects(bounds)), "objective labels remain clear of every earlier label and the HUD")
				occupied.append(bounds)
	context.expect_true(OffscreenIndicatorLayer.objective_priority({"label": "RETURN FLAG", "kind": "base"}) < OffscreenIndicatorLayer.objective_priority({"label": "FLAG", "kind": "flag"}), "carrier return route takes placement priority")
	var lab := OfflineSandbox.new()
	parent.add_child(lab)
	lab.set_editor_open(true)
	lab.apply_accessibility_settings({"hud_scale": 1.5})
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var panel = lab.lab_panel
	context.expect_true(panel.cards.get_item_rect(5).end.y <= panel.cards.size.y, "enlarged lab keeps at least six complete card rows visible")
	context.expect_true(panel.get_global_rect().encloses(panel.add_button.get_global_rect()), "stack action stays visible in enlarged editor")
	panel.search.text = "Quick Loader"
	panel.search.text_changed.emit(panel.search.text)
	(panel.find_child("InspectCard", true, false) as Button).pressed.emit()
	await parent.get_tree().process_frame
	var tabs := panel.find_child("LabTabs", true, false) as TabContainer
	context.expect_equal(tabs.current_tab, 3, "details opens selected-card tab without scrolling past the list")
	context.expect_true(panel.card_description.text.contains("Quick Loader"), "details retains the selected card")
	panel.add_button.pressed.emit()
	context.expect_equal(int(lab.build.get(&"quick_loader", 0)), 1, "selected card can be added while inspecting details")
	tabs.current_tab = 0
	context.expect_equal(panel.search.text, "Quick Loader", "returning from details preserves the search")
	context.expect_true(lab.editor_open, "inspecting a card keeps the range paused")
	lab.free()
