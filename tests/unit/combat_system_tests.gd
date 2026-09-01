class_name CombatSystemTests
extends RefCounted


static func run(context: TestContext) -> void:
	_validate_arena(context)
	_validate_movement_and_aim(context)
	_validate_weapon(context)
	_validate_shield(context)
	_validate_projectiles(context)
	_validate_projectile_limits(context)
	_validate_damage_and_repair(context)
	_validate_overtime(context)
	_validate_sandbox_and_soak(context)
	_validate_overtime_debug_toggle(context)


static func _validate_arena(context: TestContext) -> void:
	var anchors := ArenaLayout.spawn_anchors()
	context.expect_equal(anchors.size(), 32, "arena exposes exactly 32 spawn anchors")
	context.expect_equal(ArenaLayout.map_ids().size(), 10, "arena registry exposes all ten built-in maps")
	context.expect_empty(ArenaLayout.validate(), "every built-in map satisfies layout constraints")
	context.expect_equal(ArenaLayout.cover_rectangles().size(), 4, "arena contains four cover islands")
	context.expect_equal(ArenaLayout.central_octagon().size(), 8, "central obstacle is octagonal")
	var topology_signatures: Dictionary = {}
	for map_id in ArenaLayout.map_ids():
		context.expect_equal(ArenaLayout.spawn_anchors(map_id).size(), 32, "%s provides all 32 authoritative spawns" % map_id)
		context.expect_empty(ArenaLayout.validate_map(map_id), "%s passes its individual geometry validation" % map_id)
		context.expect_false(ArenaLayout.display_name(map_id).is_empty(), "%s has a visible map name" % map_id)
		var signature := "%s|%s" % [ArenaLayout.cover_rectangles(map_id), ArenaLayout.circle_obstacles(map_id)]
		topology_signatures[signature] = map_id
		var objective_margin := GameModeRules.OBJECTIVE_ZONE_RADIUS - GameConstants.SHIP_COLLISION_RADIUS
		context.expect_true(ArenaCollisionSystem.is_ship_position_clear(GameModeRules.objective_spawn(map_id), map_id, objective_margin), "%s provides a clear central objective zone" % map_id)
		context.expect_true(ArenaCollisionSystem.is_ship_position_clear(GameModeRules.capture_zone(GameModeRules.Mode.CAPTURE_THE_FLAG, 0, map_id), map_id, objective_margin), "%s provides a clear neutral flag extraction zone" % map_id)
		context.expect_true(ArenaCollisionSystem.is_ship_position_clear(GameModeRules.capture_zone(GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, 1, map_id), map_id, objective_margin), "%s provides a clear Cyan flag base" % map_id)
		context.expect_true(ArenaCollisionSystem.is_ship_position_clear(GameModeRules.capture_zone(GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, 2, map_id), map_id, objective_margin), "%s provides a clear Magenta flag base" % map_id)
	context.expect_equal(topology_signatures.size(), 10, "all ten maps have mechanically distinct obstacle topologies")
	var twin_collision := ArenaCollisionSystem.move_ship(Vector2(860.0, 900.0), Vector2(100.0, 0.0), 0.2, &"twin_suns")
	context.expect_true((twin_collision.position as Vector2).x <= 865.001, "selected Twin Suns geometry blocks ships at its western reactor")
	context.expect_false(ArenaCollisionSystem.projectile_obstacle_normal(Vector2(1600.0, 300.0), 5.0, &"riftline").is_zero_approx(), "selected Riftline geometry blocks projectiles at its divider")


static func _validate_movement_and_aim(context: TestContext) -> void:
	var diagonal := MovementSystem.sanitize_input(Vector2(1.0, 1.0))
	context.expect_approx(diagonal.length(), 1.0, "diagonal movement input is normalized")
	context.expect_equal(
		MovementSystem.sanitize_input(Vector2(INF, 0.0)),
		Vector2.ZERO,
		"non-finite movement input is rejected to zero"
	)
	context.expect_approx(
		MovementSystem.ship_relative_to_world(Vector2(0.0, -1.0), 0.0).angle(),
		0.0,
		"W moves forward along a right-facing ship"
	)
	context.expect_approx(
		MovementSystem.ship_relative_to_world(Vector2(0.0, -1.0), PI * 0.5).angle(),
		PI * 0.5,
		"W follows the ship aim when it faces down"
	)
	context.expect_approx(
		MovementSystem.ship_relative_to_world(Vector2(-1.0, 0.0), 0.0).angle(),
		-PI * 0.5,
		"A strafes left relative to a right-facing ship"
	)
	context.expect_approx(
		angle_difference(
			PI,
			MovementSystem.ship_relative_to_world(Vector2(1.0, 0.0), PI * 0.5).angle()
		),
		0.0,
		"D strafes right relative to a downward-facing ship"
	)
	context.expect_approx(
		MovementSystem.ship_relative_to_world(Vector2(1.0, -1.0), PI * 0.25).length(),
		1.0,
		"ship-relative diagonal movement remains normalized"
	)
	var screen_up_as_ship_input := MovementSystem.world_to_ship_relative(Vector2.UP, PI * 0.5)
	context.expect_approx(
		MovementSystem.ship_relative_to_world(screen_up_as_ship_input, PI * 0.5).angle(),
		-PI * 0.5,
		"screen-relative movement converts through the canonical ship input without changing direction"
	)
	var stats := CombatStats.create_base()
	var accelerated := MovementSystem.step_velocity(
		Vector2.ZERO, Vector2.RIGHT, stats, 1.0 / 60.0
	)
	context.expect_approx(accelerated.x, 15.0, "movement applies base acceleration per tick")
	var shield_accelerated := MovementSystem.step_velocity(
		Vector2.ZERO, Vector2.RIGHT, stats, 1.0 / 60.0, true
	)
	context.expect_approx(
		shield_accelerated.x,
		11.25,
		"shielding reduces acceleration by 25 percent"
	)
	stats.shield_acceleration_factor = 1.25
	var boosted_shield_acceleration := MovementSystem.step_velocity(
		Vector2.ZERO, Vector2.RIGHT, stats, 1.0 / 60.0, true
	)
	context.expect_approx(
		boosted_shield_acceleration.x,
		18.75,
		"cards can make shielded acceleration stronger than base acceleration"
	)
	var capped := MovementSystem.step_velocity(
		Vector2(479.0, 0.0), Vector2.RIGHT, stats, 1.0
	)
	context.expect_approx(capped.length(), stats.max_speed, "movement does not exceed maximum speed")
	var dragged := MovementSystem.step_velocity(Vector2(100.0, 0.0), Vector2.ZERO, stats, 0.1)
	context.expect_approx(dragged.x, 30.0, "drag moves idle velocity toward zero")
	context.expect_approx(
		MovementSystem.normalize_aim_angle(-PI * 0.5),
		TAU - PI * 0.5,
		"aim angle normalizes into one positive turn"
	)
	context.expect_approx(
		MovementSystem.normalize_aim_angle(NAN, 1.25),
		1.25,
		"non-finite aim preserves the last valid angle"
	)
	var even_spread := MovementSystem.spread_angles(0.0, 2, 10.0)
	context.expect_approx(
		angle_difference(0.0, even_spread[0]),
		deg_to_rad(-5.0),
		"even projectile spread begins left of aim"
	)
	context.expect_approx(
		angle_difference(0.0, even_spread[1]),
		deg_to_rad(5.0),
		"even projectile spread ends right of aim"
	)
	var odd_spread := MovementSystem.spread_angles(1.0, 3, 20.0)
	context.expect_approx(odd_spread[1], 1.0, "odd projectile spread is centered on aim")


static func _validate_weapon(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	var weapon := WeaponState.new()
	weapon.reset(stats)
	context.expect_true(weapon.try_fire(stats, false), "ready weapon fires immediately")
	context.expect_equal(weapon.ammunition, 7, "firing consumes one magazine round")
	context.expect_false(weapon.try_fire(stats, false), "fire cadence blocks an immediate second shot")
	weapon.step(stats, 0.249)
	context.expect_false(weapon.try_fire(stats, false), "weapon remains blocked before cadence elapses")
	weapon.step(stats, 0.001)
	context.expect_true(weapon.try_fire(stats, false), "weapon fires exactly when cadence elapses")
	context.expect_false(weapon.try_fire(stats, true), "shielding disables firing")
	while weapon.ammunition > 0:
		weapon.step(stats, 1.0 / stats.fire_rate)
		context.expect_true(weapon.try_fire(stats, false), "automatic fire consumes remaining ammunition")
	context.expect_true(weapon.reloading, "empty magazine begins automatic reload")
	context.expect_false(weapon.try_fire(stats, false), "reloading disables firing")
	weapon.step(stats, stats.reload_duration - 0.001)
	context.expect_true(weapon.reloading, "reload remains active before its duration")
	weapon.step(stats, 0.001)
	context.expect_false(weapon.reloading, "reload completes at its duration")
	context.expect_equal(weapon.ammunition, stats.magazine_size, "reload restores a full derived magazine")
	context.expect_true(weapon.try_fire(stats, false), "weapon can fire after its automatic reload")
	weapon.step(stats, 1.0 / stats.fire_rate)
	context.expect_true(weapon.request_reload(stats), "manual reload starts with a partially used magazine")
	context.expect_false(weapon.request_reload(stats), "manual reload cannot restart while already active")
	weapon.step(stats, stats.reload_duration)
	context.expect_equal(weapon.ammunition, stats.magazine_size, "manual reload restores the magazine")
	context.expect_false(weapon.request_reload(stats), "manual reload ignores an already full magazine")


static func _validate_shield(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	var shield := ShieldState.new()
	shield.reset(stats)
	shield.step(true, stats, 0.0)
	context.expect_true(shield.active, "held shield activates when energy is available")
	context.expect_true(
		shield.can_block(0.0, Vector2.from_angle(deg_to_rad(60.0)), 120.0),
		"shield includes its positive arc boundary"
	)
	context.expect_true(
		shield.can_block(0.0, Vector2.from_angle(deg_to_rad(-60.0)), 120.0),
		"shield includes its negative arc boundary"
	)
	context.expect_false(
		shield.can_block(0.0, Vector2.from_angle(deg_to_rad(60.1)), 120.0),
		"shield excludes impacts outside its arc"
	)
	shield.step(true, stats, 0.5)
	context.expect_approx(shield.energy, 90.0, "active shield drains continuously")
	context.expect_true(shield.try_block(0.0, Vector2.RIGHT, stats), "front impact is blocked")
	context.expect_approx(shield.energy, 65.0, "block subtracts projectile energy cost")
	context.expect_false(
		shield.try_block(0.0, Vector2.LEFT, stats),
		"rear impact continues to the hull"
	)
	shield.energy = 25.0
	context.expect_true(shield.try_block(0.0, Vector2.RIGHT, stats), "depleting hit is still blocked")
	context.expect_true(shield.depletion_locked, "empty shield enters depletion lock")
	shield.step(true, stats, 2.0)
	context.expect_false(shield.active, "held depleted shield cannot reactivate")
	context.expect_approx(shield.energy, 22.5, "regeneration only uses time beyond its delay")
	shield.step(false, stats, 0.05)
	context.expect_true(shield.depletion_locked, "shield stays locked below reactivation threshold")
	shield.step(false, stats, 0.05)
	context.expect_false(shield.depletion_locked, "shield unlocks after regenerating to threshold")
	var tuned_stats := CombatStats.create_base()
	tuned_stats.shield_block_cost = 10.0
	tuned_stats.shield_depletion_threshold = 40.0
	var tuned_shield := ShieldState.new()
	tuned_shield.reset(tuned_stats)
	tuned_shield.step(true, tuned_stats, 0.0)
	context.expect_true(
		tuned_shield.try_block(0.0, Vector2.RIGHT, tuned_stats),
		"custom block-cost shield blocks a frontal hit"
	)
	context.expect_approx(tuned_shield.energy, 98.0, "Perfect Guard discounts the first authoritative block cost")
	context.expect_true(tuned_shield.has_perfect_guard_feedback(), "a successful Perfect Guard exposes feedback state")
	context.expect_true(
		tuned_shield.try_block(0.0, Vector2.RIGHT, tuned_stats),
		"a second immediate frontal hit remains blockable"
	)
	context.expect_approx(tuned_shield.energy, 88.0, "Perfect Guard is consumed by the first projectile")
	tuned_shield.active = false
	tuned_shield.depletion_locked = true
	tuned_shield.energy = 39.0
	tuned_shield.time_since_activity = tuned_stats.shield_regeneration_delay
	tuned_shield.step(false, tuned_stats, 0.02)
	context.expect_true(
		tuned_shield.depletion_locked,
		"custom shield recovery threshold remains locked below its value"
	)
	tuned_shield.step(false, tuned_stats, 0.02)
	context.expect_false(
		tuned_shield.depletion_locked,
		"custom shield recovery threshold unlocks once crossed"
	)


static func _validate_projectiles(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	stats.pierce_count = 1
	stats.ricochet_count = 1
	var projectile := ProjectileState.create(10, 1, 3, Vector2.ZERO, 0.0, stats)
	context.expect_false(projectile.can_hit(1), "projectile ignores its owner")
	context.expect_true(projectile.can_hit(2), "projectile can hit an opponent")
	context.expect_true(projectile.register_hull_hit(2), "piercing projectile survives its first hull hit")
	context.expect_false(projectile.can_hit(2), "projectile cannot damage the same ship twice")
	context.expect_false(projectile.register_hull_hit(3), "projectile expires after pierce allowance is spent")
	var speed_before := projectile.velocity.length()
	context.expect_true(projectile.ricochet(Vector2.LEFT), "projectile uses an available ricochet")
	context.expect_true(projectile.velocity.x < 0.0, "ricochet reflects projectile velocity")
	context.expect_approx(projectile.velocity.length(), speed_before, "ricochet preserves projectile speed")
	context.expect_false(projectile.ricochet(Vector2.RIGHT), "projectile expires on wall after ricochets are spent")
	var rebound_damage := projectile.damage
	var rebound_lifetime := projectile.lifetime_remaining
	context.expect_true(projectile.rebound_toward(2, Vector2(-100.0, 0.0)), "projectile can rebound toward its original source")
	context.expect_equal(projectile.owner_id, 2, "rebound transfers projectile allegiance to the shield owner")
	context.expect_true(projectile.velocity.x < 0.0, "rebound points back toward the source")
	context.expect_approx(projectile.damage, rebound_damage * 0.5, "rebound halves projectile damage")
	context.expect_approx(projectile.lifetime_remaining, rebound_lifetime * 0.5, "rebound halves remaining range")
	context.expect_false(projectile.rebound_toward(3, Vector2.RIGHT), "a projectile can rebound only once")
	var tangent_start := ArenaLayout.center() + Vector2(-35.0, ArenaLayout.CENTRAL_RADIUS + projectile.radius - 2.0)
	var tangent_end := tangent_start + Vector2(70.0, 0.0)
	var tangent_hit := ArenaCollisionSystem.projectile_obstacle_sweep(
		tangent_start,
		tangent_end,
		projectile.radius,
		ArenaLayout.DEFAULT_MAP_ID
	)
	context.expect_true(bool(tangent_hit.get("hit", false)), "swept projectile collision catches a near-tangent obstacle crossing with clear endpoints")
	context.expect_true((tangent_hit.normal as Vector2).y > 0.9, "near-tangent circle collision returns the outward rebound normal")
	stats.projectile_lifetime = 4.0
	var lifetime_projectile := ProjectileState.create(11, 1, 4, Vector2.ZERO, 0.0, stats)
	context.expect_true(
		lifetime_projectile.step(3.999),
		"projectile lives until its configured lifetime"
	)
	context.expect_false(lifetime_projectile.step(0.001), "projectile expires at its lifetime")
	stats.beam_weapon = true
	var beam := ProjectileState.create(12, 1, 5, Vector2.ZERO, 0.0, stats)
	context.expect_approx(
		beam.lifetime_remaining,
		0.288,
		"beam persistence scales with the projectile lifetime stat"
	)


static func _validate_projectile_limits(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	var registry := ProjectileRegistry.new()
	registry.maximum_per_owner = 2
	registry.maximum_global = 3
	registry.add(ProjectileState.create(1, 10, 1, Vector2.ZERO, 0.0, stats))
	registry.add(ProjectileState.create(2, 10, 2, Vector2.ZERO, 0.0, stats))
	var owner_removed := registry.add(
		ProjectileState.create(3, 10, 3, Vector2.ZERO, 0.0, stats)
	)
	context.expect_equal(owner_removed, [1], "owner limit removes the shooter's oldest projectile")
	registry.add(ProjectileState.create(4, 20, 1, Vector2.ZERO, 0.0, stats))
	var global_removed := registry.add(
		ProjectileState.create(5, 30, 1, Vector2.ZERO, 0.0, stats)
	)
	context.expect_equal(global_removed, [2], "global limit removes the globally oldest projectile")
	var mine_registry := ProjectileRegistry.new()
	context.expect_false(mine_registry.has_mines(), "ordinary projectile registries skip mine-specific scans")
	var tracked_mine := ProjectileState.create_mine(6, 30, Vector2.ZERO)
	mine_registry.add(tracked_mine)
	context.expect_true(mine_registry.has_mines(), "projectile registry tracks active mines without a full scan")
	mine_registry.remove(tracked_mine.projectile_id)
	context.expect_false(mine_registry.has_mines(), "removing the final mine restores the no-mine fast path")
	registry.schedule_owner_cleanup(10)
	context.expect_empty(registry.step_cleanup(0.499), "dead-owner projectiles remain for the grace period")
	context.expect_equal(registry.step_cleanup(0.001), [3], "dead-owner projectiles despawn after 0.5 seconds")
	var transfer_registry := ProjectileRegistry.new()
	var transferred := ProjectileState.create(20, 40, 1, Vector2.ZERO, 0.0, stats)
	transfer_registry.add(transferred)
	transfer_registry.transfer_owner(20, 41)
	context.expect_equal(transfer_registry.count_for_owner(40), 0, "rebound removes the shot from its original owner's budget")
	context.expect_equal(transfer_registry.count_for_owner(41), 1, "rebound counts the shot against its new owner")
	transfer_registry.schedule_owner_cleanup(40)
	context.expect_empty(transfer_registry.step_cleanup(GameConstants.DEAD_OWNER_PROJECTILE_LIFETIME), "original-owner death cleanup preserves a transferred rebound")
	context.expect_true(transfer_registry.get_projectile(20) != null, "transferred rebound remains registered after original-owner cleanup")


static func _validate_damage_and_repair(context: TestContext) -> void:
	var repair_stats := CombatStats.create_base()
	repair_stats.auto_repair_enabled = true
	var repair_ship := CombatantState.create(1, repair_stats)
	repair_ship.apply_damage(40.0)
	repair_ship.step(Vector2.ZERO, 0.0, false, 4.99)
	context.expect_approx(repair_ship.health, 60.0, "auto-repair waits for its full grace period")
	repair_ship.step(Vector2.ZERO, 0.0, false, 0.02)
	context.expect_approx(repair_ship.health, 60.08, "auto-repair heals only after grace expires")
	repair_ship.apply_damage(5.0)
	repair_ship.step(Vector2.ZERO, 0.0, false, 1.0)
	context.expect_approx(repair_ship.health, 55.08, "damage interrupts auto-repair")
	var tuned_repair_stats := CombatStats.create_base()
	tuned_repair_stats.auto_repair_enabled = true
	tuned_repair_stats.auto_repair_delay = 1.0
	tuned_repair_stats.auto_repair_rate = 20.0
	var tuned_repair_ship := CombatantState.create(3, tuned_repair_stats)
	tuned_repair_ship.apply_damage(50.0)
	tuned_repair_ship.step(Vector2.ZERO, 0.0, false, 1.5)
	context.expect_approx(
		tuned_repair_ship.health,
		60.0,
		"custom auto-repair delay and rate change the healed amount"
	)
	var first := CombatantState.create(1, CombatStats.create_base())
	var second := CombatantState.create(2, CombatStats.create_base())
	first.health = 10.0
	second.health = 10.0
	var combatants := {1: first, 2: second}
	var deaths := DamageResolver.resolve_tick(combatants, [
		{"projectile_id": 9, "target_id": 1, "damage": 10.0},
		{"projectile_id": 8, "target_id": 2, "damage": 10.0},
	])
	context.expect_equal(deaths, [2, 1], "simultaneous lethal hits resolve in stable projectile-ID order")
	context.expect_false(first.alive, "first simultaneous target dies")
	context.expect_false(second.alive, "second simultaneous target dies")
	first.step(Vector2.RIGHT, 1.0, false, 1.0)
	context.expect_equal(first.velocity, Vector2.ZERO, "dead combatant loses input authority")


static func _validate_overtime(context: TestContext) -> void:
	var overtime_start := GameConstants.OVERTIME_START_SECONDS
	var shrink_end := overtime_start + GameConstants.OVERTIME_SHRINK_SECONDS
	context.expect_false(OvertimeSystem.is_active(overtime_start - 0.001), "overtime is inactive before its configured start")
	context.expect_true(OvertimeSystem.is_warning(overtime_start - GameConstants.OVERTIME_WARNING_SECONDS), "overtime warning begins five seconds early")
	context.expect_true(OvertimeSystem.is_active(overtime_start), "overtime activates at the default start time")
	context.expect_approx(
		OvertimeSystem.radius_at(shrink_end),
		GameConstants.OVERTIME_MINIMUM_RADIUS,
		"overtime boundary reaches minimum radius after 45 seconds"
	)
	var hill_center := ArenaLayout.center() + Vector2(330.0, 0.0)
	context.expect_true(
		OvertimeSystem.initial_radius(hill_center) > OvertimeSystem.initial_radius(),
		"an off-center overtime ring initially covers the full arena"
	)
	context.expect_approx(
		OvertimeSystem.radius_at(
			shrink_end,
			hill_center,
			GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS
		),
		GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS,
		"King of the Hill overtime retains its larger minimum radius"
	)
	context.expect_approx(
		OvertimeSystem.damage_for_position(
			hill_center + Vector2(GameModeRules.OBJECTIVE_ZONE_RADIUS + 25.0, 0.0),
			shrink_end,
			1.0,
			hill_center,
			GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS
		),
		0.0,
		"the complete hill and its radial buffer remain safe at minimum size"
	)
	context.expect_approx(OvertimeSystem.damage_rate_at(overtime_start), 30.0, "overtime starts at base damage")
	context.expect_approx(OvertimeSystem.damage_rate_at(shrink_end + 10.0), 40.0, "overtime damage increases every ten seconds")
	context.expect_approx(OvertimeSystem.damage_rate_at(999.0), 100.0, "overtime damage is capped")
	context.expect_approx(
		OvertimeSystem.damage_for_position(Vector2.ZERO, shrink_end, 0.5),
		15.0,
		"ship outside overtime radius takes continuous damage"
	)
	context.expect_approx(
		OvertimeSystem.damage_for_position(ArenaLayout.center(), 200.0, 1.0),
		0.0,
		"ship inside overtime radius takes no boundary damage"
	)


static func _validate_sandbox_and_soak(context: TestContext) -> void:
	var sandbox_path := "res://scenes/gameplay/offline_sandbox.tscn"
	context.expect_true(ResourceLoader.exists(sandbox_path), "offline combat sandbox scene is loadable")
	var sandbox_scene := load(sandbox_path) as PackedScene
	context.expect_true(sandbox_scene != null, "offline combat sandbox is a packed scene")
	if sandbox_scene != null:
		var sandbox := sandbox_scene.instantiate()
		context.expect_true(sandbox is OfflineSandbox, "offline combat sandbox uses its gameplay controller")
		sandbox.free()

	var stats := CombatStats.create_base()
	var registry := ProjectileRegistry.new()
	var next_id := 1
	var peak_count := 0
	var delta := 1.0 / 60.0
	for tick in 54_000:
		if tick % 15 == 0:
			registry.add(ProjectileState.create(next_id, 1, next_id, Vector2.ZERO, 0.0, stats))
			next_id += 1
		for projectile in registry.all_projectiles():
			if not projectile.step(delta):
				registry.remove(projectile.projectile_id)
		peak_count = maxi(peak_count, registry.size())
	for cleanup_tick in 151:
		for projectile in registry.all_projectiles():
			if not projectile.step(delta):
				registry.remove(projectile.projectile_id)
	context.expect_true(peak_count <= 11, "15-minute projectile soak keeps bounded active entities")
	context.expect_equal(registry.size(), 0, "15-minute projectile soak returns entity count to baseline")
	context.expect_equal(registry.retained_owner_slot_count(), 0, "15-minute projectile soak releases historical owner-order slots")


static func _validate_overtime_debug_toggle(context: TestContext) -> void:
	context.expect_approx(
		OfflineSandbox.next_overtime_toggle_time(20.0),
		GameConstants.OVERTIME_START_SECONDS,
		"overtime debug control starts overtime from normal play"
	)
	context.expect_approx(
		OfflineSandbox.next_overtime_toggle_time(GameConstants.OVERTIME_START_SECONDS - GameConstants.OVERTIME_WARNING_SECONDS),
		0.0,
		"overtime debug reset restores the full heat clock during warning"
	)
	context.expect_approx(
		OfflineSandbox.next_overtime_toggle_time(120.0),
		0.0,
		"overtime debug reset restores the full heat clock while active"
	)
