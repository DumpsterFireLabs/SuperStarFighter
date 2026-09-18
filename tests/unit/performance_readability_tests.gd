extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_frame_cadence(context)
	_recovery_tail_summary(context)
	_shot_profile_reuse(context)
	_sweep_parity(context)
	_effect_pressure(context, parent)


static func _frame_cadence(context: TestContext) -> void:
	var intervals: Array[int] = [17241, 17242, 20000, 28000, 17241, 20000]
	var summary := preload("res://src/test/frame_timing_summary.gd").summarize(intervals, 58.0)
	context.expect_approx(summary.budget_usec, 1000000.0 / 58.0, "frame diagnostics honor an external 58 FPS cap")
	context.expect_equal(summary.late_frames, 3, "normal capped intervals are not reported as late frames")
	context.expect_equal(summary.severe_frames, 1, "frame diagnostics distinguish severe stalls from smaller overruns")
	context.expect_equal(summary.longest_late_streak, 2, "late streaks use chronological frames before percentile sorting")
	context.expect_equal(intervals[0], 17241, "summarizing frame intervals leaves caller data unchanged")


static func _shot_profile_reuse(context: TestContext) -> void:
	var view := NetworkWorldFixture.new()
	view.local_peer_id = 1
	var builds := {1: {&"heavy_rounds": 2}, 2: {&"rapid_cycling": 2, &"twin_shot": 1}, 3: {&"heavy_rounds": 1}}
	view.match_payload = {"builds": builds}
	view.local_prediction.local_stats = StatSystem.derive(builds[1], view.card_catalog)
	var ship := view.replicated_visuals._ensure_ship(2, {"position": Vector2.ZERO})
	var profiles: Array = []
	view.presentation_event.connect(func(event: StringName, payload: Dictionary) -> void:
		if event == &"weapon_fire": profiles.append(payload.profile)
	)
	for peer in [1, 2, 3]:
		var expected = WeaponSoundProfile.from_stats(StatSystem.derive(builds[peer], view.card_catalog), builds[peer], view.card_catalog)
		view.replicated_visuals._emit_weapon_shot(peer, 1, Vector2.ZERO)
		context.expect_equal(profiles.back().cache_key(), expected.cache_key(), "local, existing remote and pre-snapshot shots retain their sound family")
		context.expect_approx(profiles.back().power_amount, expected.power_amount, "reused shooter stats preserve sound power")
	builds[2] = {&"heavy_rounds": 3}
	view.apply_builds(builds)
	view.replicated_visuals._emit_weapon_shot(2, 2, Vector2.ZERO)
	var expected_updated = WeaponSoundProfile.from_stats(StatSystem.derive(builds[2], view.card_catalog), builds[2], view.card_catalog)
	context.expect_equal(profiles.back().cache_key(), expected_updated.cache_key(), "a changed build immediately updates the reused sound profile")
	var original_damage := ship.combatant.stats.projectile_damage
	var projectile := ProjectileState.create(1, 2, 3, Vector2.ZERO, 0.0, CombatStats.create_base())
	projectile.damage = 12.0
	projectile.velocity = Vector2(1300, 0)
	view.replicated_visuals._emit_weapon_shot(2, 3, Vector2.ZERO, projectile)
	context.expect_approx(profiles.back().damage_ratio, 12.0 / 25.0, "authoritative projectile damage still overrides current build for its sound")
	context.expect_approx(profiles.back().speed_ratio, 1300.0 / 900.0, "authoritative projectile velocity still overrides current build for its sound")
	context.expect_approx(ship.combatant.stats.projectile_damage, original_damage, "sound overrides cannot modify the ship's live combat stats")
	view.free()


static func _sweep_parity(context: TestContext) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 518621
	var world := AuthoritativeWorld.new()
	var ids: Array[int] = []
	for peer in range(1, 33):
		var pilot := world.add_peer(peer)
		pilot.position = Vector2(random.randf_range(50, 3150), random.randf_range(50, 1750))
		ids.append(peer)
	# Two equidistant hits and a ship whose collision circle crosses a cell edge.
	world.combatants[1].position = Vector2(200, 200)
	world.combatants[2].position = Vector2(200, 200)
	world.spatial_index.rebuild_ships(world.combatants, ids)
	var confirmed_hits := 0
	for radius in [3.0, 7.0, 70.0]:
		var mismatches := 0
		for sample in 240:
			var start := Vector2(random.randf_range(0, 3200), random.randf_range(0, 1800))
			var finish := Vector2(random.randf_range(0, 3200), random.randf_range(0, 1800))
			if sample == 0:
				start = Vector2(150, 190)
				finish = Vector2(220, 190)
			elif sample % 2 == 0:
				finish = start + Vector2(20, -15)
			var shot := ProjectileState.create(1, 99, 1, start, 0, CombatStats.create_base())
			shot.radius = radius
			var expected_id := 0
			var expected_fraction := INF
			for peer in ids:
				var fraction := world._segment_circle_hit_fraction(start, finish, world.combatants[peer].position, GameConstants.SHIP_COLLISION_RADIUS + radius)
				if fraction >= 0 and fraction < expected_fraction:
					expected_fraction = fraction
					expected_id = peer
			var actual: Variant = world._nearest_projectile_ship_hit(shot, start, finish, ids)
			if expected_id > 0:
				confirmed_hits += 1
			if (0 if actual == null else int(actual.peer_id)) != expected_id:
				mismatches += 1
			elif actual != null and absf(actual.fraction - expected_fraction) > 0.00001:
				mismatches += 1
		context.expect_equal(mismatches, 0, "expanded ship index matches exhaustive short/long sweeps, cell edges and ties at radius %.0f" % radius)
	context.expect_true(confirmed_hits > 100, "sweep equivalence fixture exercises real hits, not only empty cells")
	world.spatial_index.rebuild_ships({}, [])
	context.expect_true(world.spatial_index.query_ships_along_segment(Vector2.ZERO, Vector2(500, 500), 50).is_empty(), "rebuilding empty ship index removes prior candidates")


static func _effect_pressure(context: TestContext, parent: Node) -> void:
	var effects := CombatEffectsLayer.new()
	parent.add_child(effects)
	for index in 1000:
		effects.spawn_impact(Vector2(500, 500))
	context.expect_true(effects.effects.size() <= effects.DECORATIVE_EFFECT_LIMIT, "decorative contact flood leaves capacity for gameplay feedback")
	effects.spawn_damage(Vector2(600, 500), Vector2.RIGHT, true)
	for index in 200:
		effects.spawn_kinetic_vent(Vector2(500, 500))
		effects.spawn_elimination(Vector2(500, 500), Color.WHITE)
		effects.spawn_impact(Vector2(500, 500))
	var local_survives := false
	for effect in effects.effects:
		local_survives = local_survives or (effect.kind == &"damage" and effect.position == Vector2(600, 500))
	context.expect_true(local_survives, "local hull damage survives lower-priority effect pressure")
	context.expect_true(effects.effects.size() <= effects.MAX_ACTIVE_EFFECTS, "mixed burst memory is bounded")
	context.expect_true(effects.dropped_effect_count > 0, "suppressed decoration is measurable")
	effects.clear_effects()
	for index in 100:
		effects.spawn_mine_explosion(Vector2(500, 500))
	effects._process(1.0)
	context.expect_equal(effects.active_mine_effect_count, 0, "mine reservation is released after effects expire")
	context.expect_true(effects.effects.is_empty(), "effect flood drains fully after expiry")
	effects.visible_world_rect = Rect2(0, 0, 100, 100)
	effects.spawn_impact(Vector2(3000, 1700))
	context.expect_true(effects.effects.is_empty(), "distant decoration does not occupy the visible feedback budget")
	parent.remove_child(effects)
	effects.free()


static func _recovery_tail_summary(context: TestContext) -> void:
	var samples: Array[int] = []
	samples.resize(360)
	samples.fill(10000)
	var recovery: Array[int] = []
	for index in 6:
		samples[index * 60] = 18000
		recovery.append(18000)
	var timing = preload("res://src/test/combined_performance_benchmark.gd")
	var all_ticks: Dictionary = timing.summarize(samples)
	var recoveries: Dictionary = timing.summarize(recovery)
	context.expect_equal(all_ticks.p95_usec, 10000, "overall p95 can miss periodic recovery stalls")
	context.expect_equal(all_ticks.over_physics_budget, 6, "combined gate counts every physics-budget overrun")
	context.expect_equal(recoveries.p95_usec, 18000, "recovery tail reports stalls hidden below overall p95")
	context.expect_equal(recoveries.max_usec, 18000, "recovery maximum is explicitly retained")
	context.expect_equal(timing.summarize([]).samples, 0, "empty benchmark samples cannot masquerade as coverage")
	var pacing := preload("res://src/test/frame_timing_summary.gd").summarize([17241, 17242, 20000, 28000], 58.0)
	context.expect_equal(pacing.samples, 4, "cap-aware summaries retain sample counts for control comparisons")
	context.expect_equal(pacing.p99_usec, 28000, "cap-aware summaries expose tail intervals")
