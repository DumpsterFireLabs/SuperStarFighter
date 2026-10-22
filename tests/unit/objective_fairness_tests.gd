extends RefCounted

static func run(context: TestContext) -> void:
	for map_id in ArenaLayout.map_ids():
		var flag := GameModeRules.objective_spawn(map_id)
		var left := GameModeRules.capture_zone(GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, 1, map_id)
		var right := GameModeRules.capture_zone(GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, 2, map_id)
		var masks: Array[int] = [0]
		if map_id == &"switchyard": masks.assign([0, 17, 34, 51])
		if map_id == &"dead_freight": masks.assign(range(64))
		for mask in masks:
			var left_distance := _route_length(left, flag, map_id, mask)
			var right_distance := _route_length(right, flag, map_id, mask)
			context.expect_true(left_distance > 0 and right_distance > 0, "%s mask %d has routes from both bases to the flag" % [map_id, mask])
			context.expect_true(absf(left_distance - right_distance) <= 1.0, "%s mask %d flag routes are equal within one pixel (%.1f / %.1f)" % [map_id, mask, left_distance, right_distance])
			context.expect_true(ArenaCollisionSystem.is_ship_position_clear(flag, map_id, GameModeRules.OBJECTIVE_ZONE_RADIUS - GameConstants.SHIP_COLLISION_RADIUS, mask), "%s keeps the entire flag zone clear" % map_id)
		context.expect_true(ArenaLayout.is_clear_of_hazards(flag, GameModeRules.OBJECTIVE_ZONE_RADIUS + GameModeRules.OBJECTIVE_HAZARD_CLEARANCE, map_id), "%s flag zone stays clear of lethal horizons" % map_id)
		for anchor in ArenaLayout.spawn_anchors(map_id):
			context.expect_true(_route_length(anchor, flag, map_id, 0) >= 0, "%s spawn retains a route to the flag" % map_id)
		for mode in [GameModeRules.Mode.CAPTURE_THE_FLAG, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG]:
			_countdown_and_reset(context, map_id, mode, flag)
	_authored_validation(context)

static func _countdown_and_reset(context: TestContext, map_id: StringName, mode: int, flag: Vector2) -> void:
	var config := MatchCoordinatorTests._fast_config()
	config.game_mode = mode
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in [1, 2]:
		lobby.admit(peer_id, "Flag%d" % peer_id)
		world.add_peer(peer_id)
	MatchCoordinatorTests._ready_all(lobby)
	lobby.request_start(1)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 22)
	coordinator._map_rotation.assign([map_id])
	coordinator.start(0)
	MatchCoordinatorTests._advance_until_state(world, coordinator, MatchStateMachine.State.COUNTDOWN)
	context.expect_equal(coordinator.current_state_payload().objective.flag_position, flag, "%s countdown publishes the fair flag location in mode %d" % [map_id, mode])
	MatchCoordinatorTests._advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	var pilot := world.combatants[1] as CombatantState
	pilot.position = flag
	coordinator._step_flag(1.0 / 60.0, world.server_tick)
	context.expect_equal(coordinator._flag.state.flag_carrier_id, 1, "authored flag remains pickable")
	pilot.position = flag + Vector2(0, 150)
	pilot.alive = false
	coordinator._sync_combat_and_resolve(world.server_tick)
	coordinator._step_flag(1.0 / 60.0, world.server_tick)
	coordinator._step_flag(GameModeRules.FLAG_RESET_SECONDS, world.server_tick)
	context.expect_equal(coordinator.current_state_payload().objective.flag_position, flag, "dropped flag resets to the same fair location")

static func _authored_validation(context: TestContext) -> void:
	for point in [Vector2.INF, Vector2(NAN, 900), Vector2(40, 900), Vector2(1600, 900), Vector2(950, 550)]:
		var invalid := MapRegistry.definition(&"core_arena")
		invalid.flag_spawn = point
		context.expect_false(invalid.validation_errors().is_empty(), "invalid, out-of-bounds, or obstructed authored flag zone is rejected")
	var horizon := MapRegistry.definition(&"wormhole")
	horizon.flag_spawn = Vector2(1600, 600)
	context.expect_false(horizon.validation_errors().is_empty(), "flag validation includes the event-horizon safety margin")
	var editable := MapRegistry.definition(&"core_arena")
	var original := editable.flag_spawn
	editable.flag_spawn = Vector2.ZERO
	context.expect_equal(ArenaLayout.flag_spawn(&"core_arena"), original, "authoring copies cannot move the live flag location")
	var tide := ArenaLayout.flag_spawn(&"solar_tide")
	var field := ArenaLayout.movement_fields(&"solar_tide")[0]
	context.expect_true(tide.distance_to(field.center) >= field.outer_radius + GameModeRules.OBJECTIVE_ZONE_RADIUS, "Solar Tide's entire flag zone is outside the directional current")

static func _route_length(start: Vector2, destination: Vector2, map_id: StringName, mask: int) -> float:
	var route := NpcObjectiveNavigation.plan_route(start, destination, map_id, mask)
	if route.is_empty(): return -1.0
	var length := 0.0
	var previous := start
	for point in route:
		length += previous.distance_to(point)
		previous = point
	return length
