extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	var fields := ArenaLayout.movement_fields(&"solar_tide")
	context.expect_equal(fields.size(), 1, "Solar Tide publishes one signature movement field")
	context.expect_true(fields.is_read_only(), "shared movement-field roster is immutable")
	context.expect_true(ArenaLayout.movement_fields(&"core_arena").is_empty(), "other arenas preserve static movement")
	var field := fields[0] as ArenaMovementFieldDefinition
	context.expect_true(field != null, "map resource exposes a typed movement field")
	if field == null:
		return
	context.expect_equal(field.field_id, &"solar_current", "signature field has stable identity")
	context.expect_equal(field.mechanic_prompt(), "SOLAR CURRENT · CLOCKWISE", "field teaches its direction in text")
	var middle := field.center + Vector2.UP * ((field.inner_radius + field.outer_radius) * 0.5)
	context.expect_approx(field.influence_at(middle), 1.0, "middle of current receives full influence")
	context.expect_approx(field.influence_at(field.center), 0.0, "protected central obstacle is outside the current")
	context.expect_approx(field.influence_at(field.center + Vector2.UP * (field.outer_radius + 1.0)), 0.0, "outside route is unaffected")
	context.expect_equal(field.flow_direction_at(middle), Vector2.RIGHT, "clockwise current points right across the top arc")
	context.expect_true(ArenaLayout.mechanic_prompt(&"solar_tide").contains("CLOCKWISE"), "map intro exposes mechanic direction without relying on color")

	var stats := CombatStats.create_base()
	var with_current := CombatantState.create(61, stats, middle)
	var forward_frame := PlayerInputFrame.new(1, 1, Vector2(0.0, -1.0), 0.0)
	for index in 90:
		ArenaMovementSystem.step_input(with_current, forward_frame, 1.0 / 60.0, &"solar_tide")
	context.expect_true(with_current.velocity.x > stats.max_speed * 1.15, "travelling with the current sustains a meaningful route-speed advantage")
	context.expect_true(with_current.velocity.length() <= stats.max_speed * field.maximum_speed_multiplier + 0.001, "current enforces its authored speed ceiling")
	var against_current := CombatantState.create(62, stats, middle)
	var reverse_frame := PlayerInputFrame.new(1, 1, Vector2(0.0, 1.0), 0.0)
	for index in 60:
		ArenaMovementSystem.step_input(against_current, reverse_frame, 1.0 / 60.0, &"solar_tide")
	context.expect_true(against_current.velocity.x < -stats.max_speed * 0.7, "normal thrust can oppose the current and preserve player control")
	var escape_world := AuthoritativeWorld.new()
	escape_world.set_map_id(&"solar_tide")
	var escaping := escape_world.add_peer(66, stats)
	escaping.position = middle
	escape_world.submit_input(66, PlayerInputFrame.new(1, 1, Vector2(-1.0, 0.0), 0.0))
	var escape_ticks := 0
	while escaping.position.distance_to(field.center) <= field.outer_radius and escape_ticks < 180:
		escape_world.step(1.0 / 60.0)
		escape_ticks += 1
	context.expect_true(escape_ticks < 180, "outward thrust exits the current without trapping a pilot")
	var afterburner_speed := stats.max_speed * stats.afterburner_speed_multiplier
	var afterburner := CombatantState.create(63, stats, middle)
	afterburner.velocity = Vector2.RIGHT * afterburner_speed
	afterburner.afterburner_remaining = 1.0
	ArenaMovementSystem.step_input(afterburner, forward_frame, 0.25, &"solar_tide")
	context.expect_true(afterburner.velocity.length() >= afterburner_speed, "current does not suppress an existing faster ability velocity")
	var baseline := CombatantState.create(64, stats, Vector2(500, 500))
	var static_map := CombatantState.create(65, stats, Vector2(500, 500))
	baseline.velocity = Vector2(80, 10)
	static_map.velocity = baseline.velocity
	baseline.step_input(forward_frame, 0.25)
	ArenaMovementSystem.step_input(static_map, forward_frame, 0.25, &"core_arena")
	context.expect_equal(static_map.velocity, baseline.velocity, "maps without fields retain exact movement simulation")

	var initial_state := {
		"peer_id": 71,
		"position": middle,
		"velocity": Vector2.RIGHT * 120.0,
		"aim_angle": 0.0,
		"health": stats.max_health,
		"shield": stats.shield_capacity,
		"ammunition": stats.magazine_size,
		"alive": true,
	}
	var frame := PlayerInputFrame.new(1, 1, Vector2(0.0, -1.0), 0.0)
	var prediction := ClientPredictionBuffer.new()
	prediction.reset_to_snapshot(initial_state, stats)
	prediction.predict(frame, stats, 1.0 / 60.0, &"solar_tide")
	var world := AuthoritativeWorld.new()
	world.set_map_id(&"solar_tide")
	var combatant := world.add_peer(71, stats)
	combatant.restore_prediction_state(initial_state, stats)
	world.submit_input(71, frame)
	world.step(1.0 / 60.0)
	context.expect_approx(prediction.predicted_position.distance_to(combatant.position), 0.0, "authority and client replay share Solar Current position")
	context.expect_approx(prediction.predicted_velocity.distance_to(combatant.velocity), 0.0, "authority and client replay share Solar Current velocity")

	var invalid := (MapRegistry.definition(&"solar_tide") as MapDefinition).duplicate(true) as MapDefinition
	var invalid_field := field.duplicate(true) as ArenaMovementFieldDefinition
	invalid_field.outer_radius = 2000.0
	invalid.movement_fields = [invalid_field]
	context.expect_false(invalid.validation_errors().is_empty(), "map validation rejects fields extending beyond the arena")

	var arena := ArenaView.new()
	parent.add_child(arena)
	arena.set_map_id(&"solar_tide")
	context.expect_true(arena.movement_field_layer != null and arena.movement_field_layer.is_processing(), "Solar Current owns a live animated presentation layer")
	arena.set_high_contrast(true)
	context.expect_true(arena.static_layer.high_contrast and arena.movement_field_layer.high_contrast, "high contrast applies to terrain and movement field together")
	arena.set_map_id(&"core_arena")
	context.expect_false(arena.movement_field_layer.is_processing(), "animation work stops on maps without movement fields")
	arena.free()
