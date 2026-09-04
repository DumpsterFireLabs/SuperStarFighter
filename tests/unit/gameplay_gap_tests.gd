extends RefCounted

const RespawnScript = preload("res://src/shared/combat/respawn_placement.gd")
const PowerupsScript = preload("res://src/shared/combat/card_powerup_system.gd")


static func run(context: TestContext, parent: Node) -> void:
	_heat_limits(context)
	_respawn_safety(context)
	_powerup_bounds(context)
	_team_presentation(context, parent)


static func _heat_limits(context: TestContext) -> void:
	for mode in 5:
		for map_id in ArenaLayout.map_ids():
			var fixture := MatchCoordinatorTests._objective_fixture(mode, 4, 777)
			var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
			var world := fixture.world as AuthoritativeWorld
			coordinator.current_map_id = map_id
			world.set_map_id(map_id)
			coordinator._prepare_countdown()
			coordinator.overtime_start_seconds = 30.0
			var deadline := coordinator.heat_end_tick()
			context.expect_equal(deadline - coordinator.machine.state_entered_tick, 90 * 60, "heat deadline follows configured overtime start on %s / %s" % [GameModeRules.mode_name(mode), map_id])
			if GameModeRules.uses_flag(mode):
				for zone in coordinator._capture_zones_cache.values():
					context.expect_true((zone as Vector2).distance_to(coordinator._overtime_center()) + GameModeRules.OBJECTIVE_ZONE_RADIUS <= coordinator._overtime_minimum_radius() + 0.001, "flag return zone stays inside minimum overtime circle on %s" % map_id)
			world.server_tick = deadline - 1
			coordinator.step(0.0)
			context.expect_equal(coordinator.state(), MatchStateMachine.State.ACTIVE_HEAT, "heat remains active until its exact deadline on %s / %s" % [GameModeRules.mode_name(mode), map_id])
			world.server_tick = deadline
			coordinator.step(0.0)
			context.expect_equal(coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "idle heat terminates at deadline on %s / %s" % [GameModeRules.mode_name(mode), map_id])
			context.expect_true(coordinator.machine.tied_heat, "unresolved objective or survival stalemate draws")
			context.expect_empty(coordinator._respawn_deadlines, "time limit clears pending objective respawns")
	var fixture := MatchCoordinatorTests._objective_fixture(GameModeRules.Mode.KING_OF_THE_HILL, 3, 779)
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	var world := fixture.world as AuthoritativeWorld
	coordinator._objective_progress = {1: 10.0, 2: 6.0, 3: 0.0}
	(world.combatants[1] as CombatantState).alive = false
	(coordinator.machine.players[1] as PlayerMatchState).eliminate()
	world.server_tick = coordinator.heat_end_tick()
	coordinator.step(0.0)
	context.expect_equal(coordinator.machine.last_heat_winner, 1, "sole hill control-time leader wins even while waiting to respawn")
	var tied := MatchCoordinatorTests._objective_fixture(GameModeRules.Mode.KING_OF_THE_HILL, 3, 780).coordinator as AuthoritativeMatchCoordinator
	tied.machine.finish_timed_heat(tied.heat_end_tick(), {1: 10.0, 2: 10.0 + 0.000001, 3: 3.0})
	context.expect_true(tied.machine.tied_heat, "equal hill control ticks draw without floating-point or peer-order tiebreaks")
	for mode in [GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG]:
		var dead_fixture := MatchCoordinatorTests._objective_fixture(mode, 4, 790 + mode)
		var dead_coordinator := dead_fixture.coordinator as AuthoritativeMatchCoordinator
		var dead_world := dead_fixture.world as AuthoritativeWorld
		for pilot in dead_world.combatants.values():
			(pilot as CombatantState).alive = false
		dead_world.server_tick = dead_coordinator.heat_end_tick()
		dead_coordinator.step(0.0)
		context.expect_equal(dead_coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "time limit ends an objective heat even when everyone is dead")


static func _respawn_safety(context: TestContext) -> void:
	for map_id in ArenaLayout.map_ids():
		var world := AuthoritativeWorld.new()
		world.set_map_id(map_id)
		world.add_peer(1).alive = false
		var center := GameModeRules.objective_spawn(map_id, 1)
		var spawn := RespawnScript.choose(world, 1, ArenaLayout.spawn_anchors(map_id)[0], center, GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS)
		context.expect_true(spawn.is_finite() and ArenaCollisionSystem.is_ship_position_clear(spawn, map_id), "late overtime respawn finds clear interior geometry on %s" % map_id)
		context.expect_true(spawn.distance_to(center) + GameConstants.SHIP_COLLISION_RADIUS <= GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS, "respawn keeps the full ship inside the late safe zone on %s" % map_id)
	var world := AuthoritativeWorld.new()
	world.add_peer(1).alive = false
	var enemy := world.add_peer(2)
	var preferred := Vector2(400, 400)
	enemy.position = preferred + Vector2(100, 0)
	var center := ArenaLayout.center()
	var radius := OvertimeSystem.initial_radius(center)
	var chosen := RespawnScript.choose(world, 1, preferred, center, radius)
	context.expect_true(chosen.distance_to(enemy.position) > 600.0, "respawn avoids a visible enemy camping the preferred base")
	world.set_team_assignments({1: 1, 2: 1})
	context.expect_equal(RespawnScript.choose(world, 1, preferred, center, radius), preferred, "nearby ally does not count as an enemy camping threat")
	world.set_team_assignments({})
	enemy.alive = false
	var projectile := ProjectileState.create(1, 2, 1, preferred + Vector2(-200, 0), 0.0, CombatStats.create_base())
	world.projectile_registry.add(projectile)
	chosen = RespawnScript.choose(world, 1, preferred, center, radius)
	var closest := Geometry2D.get_closest_point_to_segment(chosen, projectile.position, projectile.position + projectile.velocity * RespawnScript.THREAT_LOOKAHEAD_SECONDS)
	context.expect_true(chosen.distance_to(closest) >= 60.0, "respawn avoids a hostile projectile's approaching path")
	world.clear_projectiles()
	world.projectile_registry.add(ProjectileState.create_mine(2, 2, preferred))
	chosen = RespawnScript.choose(world, 1, preferred, center, radius)
	context.expect_true(chosen.distance_to(preferred) >= GameConstants.MINE_BLAST_RADIUS + GameConstants.SHIP_COLLISION_RADIUS, "respawn avoids hostile mine blast space")
	context.expect_false(RespawnScript.choose(world, 1, preferred, center, 10.0).is_finite(), "no clear space returns a deferred spawn instead of an illegal fallback")
	context.expect_equal(RespawnScript.choose(world, 1, preferred, center, radius), chosen, "respawn choice is deterministic for identical threats")
	var fixture := MatchCoordinatorTests._objective_fixture(GameModeRules.Mode.CAPTURE_THE_FLAG, 4, 791)
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	var respawn_world := fixture.world as AuthoritativeWorld
	for id in [1, 2, 3, 4]:
		(respawn_world.combatants[id] as CombatantState).alive = false
		(coordinator.machine.players[id] as PlayerMatchState).eliminate()
		coordinator._respawn_deadlines[id] = respawn_world.server_tick
	coordinator._step_respawns(respawn_world.server_tick)
	context.expect_equal(coordinator.machine.alive_participant_ids().size(), 2, "simultaneous respawns respect the per-tick work budget")
	respawn_world.server_tick += 1
	coordinator._step_respawns(respawn_world.server_tick)
	context.expect_equal(coordinator.machine.alive_participant_ids().size(), 4, "remaining due respawns complete on the following tick")


static func _powerup_bounds(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	var system := PowerupsScript.new(CardCatalog.create_default(), 781)
	system.begin_heat(0, world.map_id, true, 5.0)
	var peak := 0
	var removals := 0
	for tick in range(300, 60 * 60 * 2, 300):
		for event in system.step(tick, world, {}):
			if event.event_type == &"CARD_POWERUP_REMOVED":
				removals += 1
		peak = maxi(peak, system.active_powerups.size())
	context.expect_true(peak <= PowerupsScript.MAX_ACTIVE_POWERUPS, "uncollected powerup population remains bounded during a long empty heat")
	context.expect_true(removals > 0, "expired pickups are removed even with no collectors")
	system.begin_heat(0, world.map_id, true, 5.0)
	system.step(300, world, {})
	var first := system.snapshot()[0]
	system.next_spawn_tick = -1
	context.expect_empty(system.step(int(first.expires_tick) - 1, world, {}), "pickup remains available until its expiry tick")
	var expiry_events := system.step(int(first.expires_tick), world, {})
	context.expect_equal(expiry_events.size(), 1, "pickup expiry emits one reliable removal event")
	context.expect_equal(expiry_events[0].payload.reason, "expired", "pickup removal identifies expiry")
	system.begin_heat(0, world.map_id, true, 5.0)
	system.step(10000000, world, {})
	context.expect_equal(system.active_powerups.size(), 1, "large tick jump does not spawn a missed-interval backlog")
	var outside := system.snapshot()[0]
	var safe_center := GameModeRules.objective_spawn(world.map_id, 1)
	system.active_powerups[int(outside.powerup_id)]["position"] = Vector2(50, 50)
	var removed := system.step(10000001, world, {}, safe_center, 175.0)
	context.expect_equal(removed[0].payload.reason, "overtime", "overtime removes inaccessible pickups")
	system.next_spawn_tick = 10000002
	system.step(10000002, world, {}, safe_center, 175.0)
	context.expect_equal(system.active_powerups.size(), 1, "late overtime can spawn a pickup in the clear safe interior")
	for pickup in system.snapshot():
		context.expect_true((pickup.position as Vector2).distance_to(safe_center) + PowerupsScript.POWERUP_RADIUS <= 175.0, "new pickup stays fully within the safe circle")
	system.begin_heat(0, world.map_id, true, 5.0)
	context.expect_empty(system.step(300, world, {}, safe_center, 10.0), "impossible safe space skips a spawn without a dangerous fallback")


static func _team_presentation(context: TestContext, parent: Node) -> void:
	var client := (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
	parent.add_child(client)
	var view := client.network_world as NetworkWorldView
	view.local_peer_id = 1
	client.bridge.local_peer_id = 1
	var payload := {"state_name": "ACTIVE_HEAT", "game_mode": GameModeRules.Mode.TEAM_DEATH_MATCH, "teams": {"1": 1, "2": 1, "3": 8}, "builds": {}, "players": []}
	view.apply_match_state(payload)
	var world := AuthoritativeWorld.new()
	for id in [1, 2, 3]:
		world.add_peer(id)
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(1, 0, world.snapshot_states(), (world.combatants[1] as CombatantState).prediction_state())))
	var ally := view.ships[2] as CombatShipView
	var enemy := view.ships[3] as CombatShipView
	context.expect_equal(ally.team_marker_text(), "T1 ALLY", "ally has explicit team identity independent of cosmetic color")
	context.expect_equal(enemy.team_marker_text(), "T8 ENEMY", "eighth team retains an explicit enemy number and label")
	context.expect_true(ally.allied_to_local and not enemy.allied_to_local, "ship marker shape follows authoritative allegiance")
	context.expect_equal(view.projectile_layer.projectile_color_for_owner(3), GameModeRules.team_color(8), "team projectile color follows ownership rather than weapon rarity")
	context.expect_true(view.projectile_layer.is_friendly_owner(2), "friendly ordnance uses the ally marker")
	var local_position := (view.ships[1] as CombatShipView).global_position
	view.authoritative_projectiles.add(ProjectileState.create(1, 2, 1, local_position - Vector2(200, 0), 0.0, CombatStats.create_base()))
	view._refresh_nearest_incoming_projectile()
	context.expect_true(view.nearest_incoming_offscreen_projectile() == null, "friendly projectiles do not produce hostile incoming warnings")
	view.authoritative_projectiles.transfer_owner(1, 3)
	context.expect_true(view.nearest_incoming_offscreen_projectile() != null, "reflected hostile ownership restores incoming threat warning")
	client.latest_match_payload = payload.duplicate(true)
	client.latest_match_payload["overtime_start_tick"] = 1
	client.latest_match_payload["heat_end_tick"] = 601
	context.expect_true(client._combat_hud_status("ACTIVE_HEAT", 0.0).contains("ENDS 10s"), "HUD shows authoritative overtime end countdown")
	view.powerup_layer.add_powerup({"powerup_id": 7, "position": Vector2(400, 400), "card_id": &"twin_shot"})
	client._on_match_event(&"CARD_POWERUP_REMOVED", 2, {"powerup_id": 7, "reason": "expired"})
	context.expect_false(view.powerup_layer.powerups.has(7), "server expiry event removes the pickup marker without awarding a card")
	payload.game_mode = GameModeRules.Mode.DEATH_MATCH
	view.apply_match_state(payload)
	context.expect_equal(ally.team_marker_text(), "", "switching to free-for-all clears stale team labels")
	context.expect_false(view.projectile_layer.has_team_marker(2), "free-for-all restores weapon rarity presentation")
	parent.remove_child(client)
	client.free()
