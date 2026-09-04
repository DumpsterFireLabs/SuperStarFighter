extends RefCounted


static func run(context: TestContext) -> void:
	var baseline: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/map_layout_baseline.json"))
	context.expect_true(MapRegistry.validation_errors().is_empty(), "all authored map resources validate before registry publication")
	context.expect_equal(ArenaLayout.map_ids().size(), baseline.size(), "resource registry preserves map roster size")
	for row in baseline:
		var id := StringName(row.id)
		context.expect_equal(ArenaLayout.display_name(id), row.name, "map display identity preserved")
		context.expect_equal(ArenaLayout.material_family(id), StringName(row.material), "map material identity preserved")
		context.expect_equal(ArenaLayout.central_radius(id), float(row.central_radius), "central decoration radius preserved")
		var rectangles := ArenaLayout.cover_rectangles(id)
		context.expect_true(rectangles.is_read_only(), "shared cover cache is immutable")
		context.expect_equal(rectangles.size(), row.rectangles.size(), "cover count preserved")
		for index in rectangles.size():
			var values: Array = row.rectangles[index]
			context.expect_equal(rectangles[index], Rect2(values[0], values[1], values[2], values[3]), "cover coordinates preserve pre-refactor geometry")
		var circles := ArenaLayout.circle_obstacles(id)
		context.expect_true(circles.is_read_only(), "shared circle list is immutable")
		context.expect_equal(circles.size(), row.circles.size(), "circle count preserved")
		for index in circles.size():
			var values: Array = row.circles[index]
			context.expect_true(circles[index].is_read_only(), "circle entries cannot poison shared collision geometry")
			context.expect_equal(circles[index].center, Vector2(values[0], values[1]), "circle center preserved")
			context.expect_equal(circles[index].radius, float(values[2]), "circle radius preserved")
		var anchors := ArenaLayout.spawn_anchors(id)
		for index in anchors.size():
			context.expect_equal(anchors[index], Vector2(row.anchors[index][0], row.anchors[index][1]), "all 320 spawn positions preserve original precision")
		anchors[0] = Vector2.ZERO
		context.expect_false(ArenaLayout.spawn_anchors(id)[0] == Vector2.ZERO, "caller spawn edits do not mutate the registry")
		for key in row.palette:
			context.expect_equal(ArenaLayout.theme(id)[key].to_html(), row.palette[key], "map palette preserved")
	context.expect_equal(ArenaLayout.normalized_map_id(&"missing_map"), &"core_arena", "unknown map retains established safe default")
	var editable := MapRegistry.definition(&"solar_tide")
	var original_name := editable.display_name
	var original_spawn := editable.spawns[0]
	var original_field := editable.movement_fields[0] as ArenaMovementFieldDefinition
	var original_multiplier := original_field.maximum_speed_multiplier
	editable.display_name = "Caller edit"
	editable.spawns[0] = Vector2.ZERO
	editable.cover.clear()
	editable.floor_color = Color.MAGENTA
	original_field.maximum_speed_multiplier = 1.99
	original_field.center = Vector2.ZERO
	var next := MapRegistry.definition(&"solar_tide")
	context.expect_equal(next.display_name, original_name, "editing a returned definition cannot rename the cached map")
	context.expect_equal(next.spawns[0], original_spawn, "nested spawn edits cannot change launch positions")
	context.expect_false(next.cover.is_empty(), "clearing editable cover cannot remove collision geometry")
	context.expect_false(next.floor_color == Color.MAGENTA, "editable palette fields do not change shared presentation")
	context.expect_approx((next.movement_fields[0] as ArenaMovementFieldDefinition).maximum_speed_multiplier, original_multiplier, "nested Resource edits cannot poison later definition lookups")
	context.expect_approx(ArenaLayout.movement_fields(&"solar_tide")[0].maximum_speed_multiplier, original_multiplier, "editable Resources never change published simulation fields")
	context.expect_equal(ArenaLayout.display_name(&"solar_tide"), original_name, "allocation-free identity queries retain the cached value")
	context.expect_equal(MapRegistry.definition(&"missing_map").map_id, &"core_arena", "editable definition lookup preserves unknown-map fallback")
	var source := MapRegistry.DEFINITIONS[0] as MapDefinition
	var invalid := source.duplicate(true) as MapDefinition
	invalid.cover.append(Rect2(Vector2.ZERO, Vector2(-1, 20)))
	context.expect_false(invalid.validation_errors().is_empty(), "negative obstacle dimensions rejected")
	invalid = source.duplicate(true) as MapDefinition
	invalid.circles.append(Vector3(NAN, 20, 50))
	context.expect_false(invalid.validation_errors().is_empty(), "non-finite obstacle coordinates rejected")
	invalid = source.duplicate(true) as MapDefinition
	invalid.spawns[1] = invalid.spawns[0]
	context.expect_false(invalid.validation_errors().is_empty(), "overlapping spawn anchors rejected")
	invalid = source.duplicate(true) as MapDefinition
	invalid.material_family = &"unimplemented"
	context.expect_false(invalid.validation_errors().is_empty(), "unknown material rejected")
	var duplicates: Array[Resource] = [source, source.duplicate(true)]
	context.expect_false(MapRegistry.validation_errors(duplicates).is_empty(), "duplicate map identity rejected")
