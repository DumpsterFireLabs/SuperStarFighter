extends RefCounted


static func run(context: TestContext) -> void:
	_shipped_maps(context)
	_blocked_routes(context)
	_spawn_exits(context)
	_authored_validation(context)
	_overtime(context)


static func _shipped_maps(context: TestContext) -> void:
	for map_id in ArenaLayout.map_ids():
		context.expect_empty(ArenaLayout.validate_map(map_id), "%s validates through the shared authoring contract" % map_id)
		var definition := MapRegistry.definition(map_id)
		var masks: Array[int] = [0]
		if map_id == &"switchyard": masks.assign([0, 17, 34, 51])
		if map_id == &"dead_freight": masks.assign(range(64))
		for mask in masks:
			var navigation := _navigation(definition, mask)
			for index in definition.spawns.size():
				var anchor := definition.spawns[index]
				context.expect_true(navigation.reaches_destination(anchor), "%s mask %d spawn %d reaches flag" % [map_id, mask, index])
				context.expect_true(navigation.has_spawn_exits(anchor), "%s mask %d spawn %d has two wide exits" % [map_id, mask, index])
			context.expect_true(navigation.reaches_overtime(ArenaLayout.overtime_minimum_radius(map_id)), "%s mask %d reaches final overtime disk" % [map_id, mask])
	context.expect_false(ArenaLayout.validate_map(&"unknown").is_empty(), "unknown maps cannot validate via registry fallback")


static func _blocked_routes(context: TestContext) -> void:
	var start := Vector2(500, 900)
	var destination := Vector2(1500, 900)
	var wall: Array[Rect2] = [Rect2(1000, 0, 40, 1800)]
	var navigation := MapNavigationValidation.new(wall, [], destination)
	context.expect_false(navigation.reaches_destination(start), "clear endpoints cannot cross an arena-spanning wall")
	for gap: float in [39.0, 42.0]:
		var split_wall: Array[Rect2] = [Rect2(1000, 0, 40, 900 - gap / 2), Rect2(1000, 900 + gap / 2, 40, 900 - gap / 2)]
		navigation = MapNavigationValidation.new(split_wall, [], destination)
		context.expect_equal(navigation.reaches_destination(start), gap > 40, "passage %.0f respects the full 40px ship diameter" % gap)
	var island: Array[Rect2] = [Rect2(1000, 500, 40, 800)]
	navigation = MapNavigationValidation.new(island, [], destination)
	context.expect_false(navigation.segment_clear(start, destination), "island blocks the direct route")
	context.expect_true(navigation.reaches_destination(start), "valid detour around an island is accepted")
	for radius: float in [850.0, 900.0]:
		var circles: Array[Vector3] = [Vector3(1600, 900, radius)]
		navigation = MapNavigationValidation.new([], circles, Vector2(2700, 900))
		context.expect_equal(navigation.reaches_destination(start), radius < 900, "circle %.0f leaves a ship-clear route only when it clears arena edges" % radius)
	context.expect_false(navigation.segment_clear(Vector2(0, 900), start), "routes include arena boundary clearance")


static func _spawn_exits(context: TestContext) -> void:
	var anchor := Vector2(500, 900)
	var destination := Vector2(1500, 900)
	var cul_de_sac: Array[Rect2] = [Rect2(370, 770, 370, 20), Rect2(370, 1010, 370, 20), Rect2(370, 790, 20, 220)]
	var navigation := MapNavigationValidation.new(cul_de_sac, [], destination)
	context.expect_true(navigation.segment_clear(anchor, anchor, 96), "dead end keeps the old 96px spawn disk clear")
	context.expect_true(navigation.reaches_destination(anchor), "one-mouth dead end still connects to the objective")
	context.expect_false(navigation.has_spawn_exits(anchor), "adjacent rays through one narrow mouth do not count as two exits")
	cul_de_sac.remove_at(1)
	navigation = MapNavigationValidation.new(cul_de_sac, [], destination)
	context.expect_true(navigation.has_spawn_exits(anchor), "removing a side creates a second heading")
	var narrow_lane: Array[Rect2] = [Rect2(700, 0, 40, 860), Rect2(700, 940, 40, 860)]
	navigation = MapNavigationValidation.new(narrow_lane, [], destination)
	context.expect_true(navigation.segment_clear(Vector2(650, 900), Vector2(830, 900)), "80px gap admits a ship")
	context.expect_false(navigation.segment_clear(Vector2(650, 900), Vector2(830, 900), 48), "80px gap cannot qualify as a 96px exit corridor")
	for gap: float in [80.0, 100.0]:
		var two_mouths: Array[Rect2] = [Rect2(370, 770, 130 - gap / 2, 20), Rect2(500 + gap / 2, 770, 240 - gap / 2, 20), Rect2(370, 1010, 370, 20), Rect2(370, 790, 20, 220)]
		navigation = MapNavigationValidation.new(two_mouths, [], destination)
		context.expect_equal(navigation.has_spawn_exits(anchor), gap >= 96, "second mouth %.0f counts only when it fits the full exit width" % gap)
	context.expect_true(MapNavigationValidation.new([], [], destination).has_spawn_exits(Vector2(96, 96)), "arena corner can supply two inward exits")


static func _authored_validation(context: TestContext) -> void:
	# Prime live NPC/registry caches before editing a resource with the same ID.
	var original := MapRegistry.definition(&"wormhole")
	context.expect_false(NpcObjectiveNavigation.plan_route(original.spawns[0], original.flag_spawn, original.map_id).is_empty(), "live map route is cached before authoring regression")
	var enclosed := original.duplicate(true) as MapDefinition
	enclosed.cover.assign([Rect2(500, 40, 10, 200), Rect2(290, 30, 220, 10), Rect2(290, 240, 220, 10), Rect2(290, 40, 10, 200)])
	var errors := enclosed.validation_errors()
	context.expect_true(_contains(errors, "spawn 0 has no ship-clear route"), "closed room outside spawn disk is rejected despite cached live route")
	context.expect_true(_contains(errors, "spawn 0 needs two"), "closed room also fails spawn exits")
	context.expect_false(_contains(errors, "overlaps"), "enclosed fixture passes the old point-clearance tests")
	context.expect_empty(original.validation_errors(), "valid authoring copy remains unaffected")
	var registry_errors := MapRegistry.validation_errors([MapRegistry.definition(&"core_arena"), enclosed])
	context.expect_true(_contains(registry_errors, "spawn 0 has no ship-clear route"), "registry rejects disconnected definitions before publication")
	# Index zero is a Switchyard door bit. Removing it reconnects the room, but
	# production authoring validation must always include that closed door.
	enclosed.map_id = &"switchyard"
	context.expect_true(_navigation(enclosed, 1).reaches_destination(enclosed.spawns[0]), "opening the fixture door restores its route")
	context.expect_false(_navigation(enclosed, 0).reaches_destination(enclosed.spawns[0]), "closing the fixture door traps the spawn")
	context.expect_true(_contains(enclosed.validation_errors(), "spawn 0 has no ship-clear route"), "a map that relies on an open door is rejected")
	enclosed.cover.remove_at(0)
	context.expect_false(_contains(enclosed.validation_errors(), "spawn 0 has no ship-clear route"), "authoring edits rebuild connectivity without stale cache")
	context.expect_true(_contains(enclosed.validation_errors(), "spawn 0 needs two"), "opening one mouth still fails the authoring exit contract")
	var hazardous := original.duplicate(true) as MapDefinition
	hazardous.spawns[0] = Vector2(1600, 1090)
	context.expect_true(_contains(hazardous.validation_errors(), "overlaps an event horizon"), "spawn disks must clear lethal horizons")
	var horizon_wall := original.duplicate(true) as MapDefinition
	var field := horizon_wall.movement_fields[0] as ArenaMovementFieldDefinition
	field.outer_radius = 900
	field.event_horizon_radius = 880
	horizon_wall.flag_spawn = Vector2(2700, 900)
	context.expect_false(_navigation(horizon_wall).reaches_destination(Vector2(500, 900)), "event horizons participate in route blocking, not just solid circles")


static func _overtime(context: TestContext) -> void:
	for map_id in [&"core_arena", &"solar_tide"]:
		var definition := MapRegistry.definition(map_id)
		var navigation := _navigation(definition)
		context.expect_false(navigation.reaches_overtime(120), "%s old overtime disk lies inside the central obstacle" % map_id)
		context.expect_true(navigation.reaches_overtime(ArenaLayout.overtime_minimum_radius(map_id)), "%s final overtime now has reachable ship space" % map_id)
		definition.overtime_minimum_radius = 120
		context.expect_true(_contains(definition.validation_errors(), "final overtime disk"), "authoring validation rejects an inaccessible final disk")
		var coordinator := AuthoritativeMatchCoordinator.new(ServerLobby.new(MatchCoordinatorTests._fast_config()), AuthoritativeWorld.new(), 22)
		coordinator.current_map_id = map_id
		context.expect_approx(coordinator._overtime_minimum_radius(), 340, "%s authority uses the corrected final radius" % map_id)
	var isolated := MapRegistry.definition(&"wormhole")
	isolated.movement_fields.clear()
	isolated.overtime_minimum_radius = 120
	isolated.cover.assign([Rect2(1300, 650, 600, 20), Rect2(1300, 1130, 600, 20), Rect2(1300, 670, 20, 460), Rect2(1880, 670, 20, 460)])
	context.expect_true(_contains(isolated.validation_errors(), "final overtime disk"), "a clear overtime disk enclosed by walls is still unreachable")
	context.expect_false(_contains(isolated.validation_errors(), "spawn"), "overtime isolation fixture leaves all spawns and flag connected")


static func _navigation(definition: MapDefinition, hidden_cover: int = 0) -> MapNavigationValidation:
	var cover: Array[Rect2] = []
	for index in definition.cover.size():
		if hidden_cover & (1 << index) == 0:
			cover.append(definition.cover[index])
	var circles: Array[Vector3] = definition.circles.duplicate()
	for field: ArenaMovementFieldDefinition in definition.movement_fields:
		if field.event_horizon_radius > 0:
			circles.append(Vector3(field.center.x, field.center.y, field.event_horizon_radius))
	return MapNavigationValidation.new(cover, circles, definition.flag_spawn)


static func _contains(errors: PackedStringArray, fragment: String) -> bool:
	for error in errors:
		if fragment in error: return true
	return false
