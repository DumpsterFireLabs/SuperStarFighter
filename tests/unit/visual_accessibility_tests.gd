extends RefCounted

const Latch = preload("res://src/client/input/combat_action_latch.gd")
const Geometry = preload("res://src/client/presentation/ship_build_geometry.gd")
const Interface = preload("res://src/client/presentation/accessible_interface.gd")
const Preferences = preload("res://src/client/presentation/accessibility_preferences.gd")


static func run(context: TestContext, parent: Node) -> void:
	var latch = Latch.new()
	context.expect_true(latch.sample(&"fire", true, false, true), "hold fire retains original immediate behavior")
	context.expect_true(not latch.sample(&"fire", false, false, true), "hold fire stops on release")
	context.expect_true(latch.sample(&"fire", true, true, true), "toggle fire begins on press")
	context.expect_true(latch.sample(&"fire", true, true, true), "holding does not retrigger toggle")
	context.expect_true(latch.sample(&"fire", false, true, true), "toggle fire remains on after release")
	context.expect_true(not latch.sample(&"fire", true, true, true), "second press stops toggle")
	latch.sample(&"fire", false, true, true)
	latch.sample(&"fire", true, true, true)
	context.expect_true(not latch.sample(&"fire", true, true, false), "blocked gameplay clears active firing")
	context.expect_true(not latch.sample(&"fire", true, true, true), "held click cannot rearm after a menu")
	latch.sample(&"fire", false, true, true)
	context.expect_true(latch.sample(&"fire", true, true, true), "new press rearms after release")
	latch.reset()
	context.expect_true(not latch.sample(&"fire", true, true, true), "session/death reset requires release")
	latch.sample(&"shield", false, true, true)
	context.expect_true(latch.sample(&"shield", true, true, true), "shield toggle is independent of fire")
	context.expect_true(not latch.sample(&"fire", false, true, true), "shield cannot enable firing")
	var stats := CombatStats.create_base()
	context.expect_true(Geometry.families(stats).is_empty(), "baseline hull has no misleading equipment")
	stats.beam_weapon = true
	stats.projectile_count = 6
	stats.shield_ram_damage = 10.0
	stats.afterburner_enabled = true
	stats.mine_layer_enabled = true
	var families: Array[StringName] = Geometry.families(stats)
	context.expect_equal(families, [&"beam", &"shield", &"drive"], "mixed builds stay bounded to three distinctive modules")
	for family in [&"beam", &"spread", &"cannon", &"shield", &"drive", &"ordnance", &"repair"]:
		for polygon in Geometry.polygons(family):
			for point in polygon:
				context.expect_true(point.length() <= 30.0, "equipment stays within the established 30-unit hull envelope")
	var materials := {}
	for map_id in ArenaLayout.map_ids():
		materials[ArenaStaticLayer.material_for_map(map_id)] = true
	context.expect_equal(materials.size(), 5, "maps use five recognizable material families")
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("53769a", 0.5))
	parent.add_child(label)
	Interface.apply(label, true)
	context.expect_equal(label.get_theme_font_size("font_size"), 21, "secondary interface text gains a readable minimum size")
	context.expect_approx(label.get_theme_color("font_color").a, 1.0, "high contrast text is opaque")
	Interface.apply(label, false)
	context.expect_equal(label.get_theme_color("font_color"), Color("53769a", 0.5), "contrast switch restores original semantic color")
	label.free()
	var preferences = Preferences.new()
	preferences.set_values({"high_contrast": true, "toggle_fire": true, "toggle_shield": true})
	context.expect_true(preferences.values.high_contrast and preferences.values.toggle_fire and preferences.values.toggle_shield, "all three accessibility controls are accepted preferences")
