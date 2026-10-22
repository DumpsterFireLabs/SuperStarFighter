extends RefCounted

const DT := 1.0 / 60.0

static func run(context: TestContext) -> void:
	_boost_and_prediction(context)
	_sweeps_and_sliding(context)
	_terrain_and_recovery(context)

static func _boost_and_prediction(context: TestContext) -> void:
	var stats := StatSystem.derive({&"impossible_engine": 3, &"afterburner": 1}, CardCatalog.create_default())
	var world := AuthoritativeWorld.new()
	world.set_map_id(&"broken_orbit")
	var pilot := world.add_peer(1)
	pilot.reset_for_heat(stats, Vector2(1300, 659))
	pilot.afterburner_remaining = 0.5
	pilot.velocity = Vector2.DOWN * stats.max_speed * stats.afterburner_speed_multiplier
	var prediction := ClientPredictionBuffer.new()
	var initial := pilot.prediction_state()
	initial.merge({"position": pilot.position, "velocity": pilot.velocity})
	prediction.reset_to_snapshot(initial, stats)
	var correction: Dictionary = {}
	for tick in 8:
		var frame := PlayerInputFrame.new(tick + 1, tick + 1, Vector2(0, -1), PI / 2.0)
		world.submit_input(1, frame)
		world.step(DT)
		prediction.predict(frame, stats, DT, world.map_id)
		if tick == 3:
			correction = pilot.prediction_state()
			correction.merge({"position": pilot.position, "velocity": pilot.velocity})
		context.expect_true(pilot.position.y <= 660.001, "legal boosted build stays on its entry side of Broken Orbit cover")
		context.expect_true(pilot.position.distance_to(prediction.predicted_position) < 0.001, "client prediction and authority agree through repeated boosted contact")
		context.expect_true(pilot.velocity.distance_to(prediction.predicted_velocity) < 0.001, "prediction preserves authoritative contact velocity")
	prediction.reconcile(correction.position, correction.velocity, 4, stats, world.map_id, false, correction)
	context.expect_true(pilot.position.distance_to(prediction.predicted_position) < 0.001, "delayed correction replays wall contact without tunneling")

static func _sweeps_and_sliding(context: TestContext) -> void:
	for speed in [3960.0, 9600.0, 20000.0]:
		for direction in [-1.0, 1.0]:
			var start := Vector2(1300, 659 if direction > 0 else 781)
			var result := ArenaCollisionSystem.move_ship(start, Vector2(0, speed * direction), DT, &"broken_orbit")
			context.expect_true(result.position.y <= 660.001 if direction > 0 else result.position.y >= 779.999, "sweep blocks partial and complete wall crossings in both directions")
			context.expect_approx(result.velocity.y, 0.0, "wall contact removes inward boost or knockback velocity")
	var slide := ArenaCollisionSystem.move_ship(Vector2(1300, 659), Vector2(120, 3960), DT, &"broken_orbit")
	context.expect_approx(slide.position.x, 1302, "wall slide spends remaining tick on tangential motion", 0.001)
	context.expect_approx(slide.velocity.x, 120, "wall slide retains tangential speed")
	var circle := ArenaCollisionSystem.move_ship(Vector2(1300, 900), Vector2(1000, 0), 1.0, &"core_arena")
	context.expect_true(circle.position.x <= 1400.001, "long sweep cannot cross a circular obstacle")
	context.expect_approx(circle.velocity.x, 0.0, "circle contact removes inward velocity")
	var circle_slide := ArenaCollisionSystem.move_ship(Vector2(1390, 900), Vector2(1000, 250), 0.1, &"core_arena")
	context.expect_true(circle_slide.position.distance_to(Vector2(1600, 900)) >= 199.999, "circle slide remains outside the reactor")
	context.expect_true(circle_slide.position.y > 900, "circle contact permits tangential travel")
	var away := ArenaCollisionSystem.move_ship(Vector2(1400, 900), Vector2(-120, 0), DT, &"core_arena")
	context.expect_approx(away.position.x, 1398, "ship can leave an exact circle contact")
	var corner := ArenaCollisionSystem.move_ship(Vector2(30, 30), Vector2(-1200, -600), 0.1)
	context.expect_true(corner.position.distance_to(Vector2(20, 20)) < 0.001, "remaining movement resolves both faces of an arena corner")
	context.expect_equal(corner.velocity, Vector2.ZERO, "corner removes both inward velocity components")
	var wall_slide := ArenaCollisionSystem.move_ship(Vector2(20, 100), Vector2(0, 120), DT)
	context.expect_equal(wall_slide.position, Vector2(20, 102), "exact boundary contact does not block tangential travel")
	var free_motion := ArenaCollisionSystem.move_ship(Vector2(400, 200), Vector2(120, 60), DT)
	context.expect_equal(free_motion.position, Vector2(402, 201), "unobstructed movement is unchanged")
	var grazing := ArenaCollisionSystem.move_ship(Vector2(1140, 660), Vector2(120, -120), DT, &"broken_orbit")
	context.expect_equal(grazing.position, Vector2(1142, 658), "leaving a rectangle corner does not lose free motion")
	var tangent := ArenaCollisionSystem.move_ship(Vector2(1130, 660), Vector2(1200, 0), 0.1, &"broken_orbit")
	context.expect_equal(tangent.position, Vector2(1250, 660), "grazing a rectangle face does not catch its corner")
	for surface in [Vector3(1300, 660, 0), Vector3(1300, 780, PI), Vector3(1140, 720, -PI / 2), Vector3(1460, 720, PI / 2)]:
		var start := Vector2(surface.x, surface.y)
		var inward := Vector2.DOWN.rotated(surface.z) * 120.0
		var blocked := ArenaCollisionSystem.move_ship(start, inward, DT, &"broken_orbit")
		context.expect_true(blocked.position.distance_to(start) < 0.002, "exact rectangle face blocks inward movement")
		context.expect_true(blocked.velocity.length() < 0.001, "exact face removes inward velocity")
		var departing := ArenaCollisionSystem.move_ship(start, -inward, DT, &"broken_orbit")
		context.expect_true(departing.position.distance_to(start - inward * DT) < 0.001, "exact rectangle face permits departure")

static func _terrain_and_recovery(context: TestContext) -> void:
	for mask in [0, ArenaEffectState.DOOR_MASK]:
		var result := ArenaCollisionSystem.move_ship(Vector2(1000, 480), Vector2(0, 1200), 0.2, &"switchyard", mask)
		context.expect_true(result.position.y <= 490.001 if mask == 0 else result.position.y > 630, "ship sweep uses the current open or closed door mask")
	var recovered := ArenaCollisionSystem.move_ship(Vector2(1300, 700), Vector2(100, 0), 0.0, &"broken_orbit")
	context.expect_true(recovered.position.y <= 660.001, "zero-delta overlap recovery remains available for separation and terrain changes")
	context.expect_approx(recovered.velocity.x, 100, "overlap recovery preserves tangent velocity")
