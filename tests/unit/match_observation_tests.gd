extends RefCounted

static func run(context: TestContext) -> void:
	var coordinator := _fixture(GameModeRules.Mode.KING_OF_THE_HILL)
	var world := coordinator.world
	var first := world.combatants[2] as CombatantState
	var second := world.combatants[3] as CombatantState
	first.position = coordinator._objective_position
	second.position = Vector2(200, 200)
	coordinator._step_hill(2.0, world.server_tick)
	context.expect_equal(coordinator.observations.contributions[2].hill_control_seconds, 2.0, "hill contribution records sole control")
	second.position = first.position
	coordinator._step_hill(1.0, world.server_tick)
	context.expect_equal(coordinator.observations.contributions[2].hill_control_seconds, 2.0, "contesting does not inflate hill control")
	context.expect_equal(coordinator.observations.contributions[3].hill_contest_seconds, 1.0, "each hill contester earns actual contested time")
	var public := coordinator.current_state_payload()
	public.objective_contributions[2].hill_control_seconds = 900.0
	context.expect_equal(coordinator.observations.contributions[2].hill_control_seconds, 2.0, "public contribution payload is a defensive copy")

	coordinator = _fixture(GameModeRules.Mode.CAPTURE_THE_FLAG)
	world = coordinator.world
	first = world.combatants[2] as CombatantState
	second = world.combatants[3] as CombatantState
	first.position = coordinator._flag_position
	second.position = Vector2(200, 200)
	coordinator._step_flag(1.0 / 60.0, world.server_tick)
	context.expect_equal(coordinator.observations.contributions[2].flag_pickups, 1, "flag pickup credits carrier exactly once")
	coordinator._step_flag(1.0, world.server_tick)
	context.expect_equal(coordinator.observations.contributions[2].flag_carry_seconds, 1.0, "live flag carry time accumulates")
	first.position = coordinator._capture_zones_cache[2]
	coordinator._step_flag(1.0 / 60.0, world.server_tick)
	context.expect_equal(coordinator.observations.contributions[2].flag_captures, 1, "capture is recorded before result payload")
	context.expect_equal(coordinator.current_state_payload().objective_contributions[2].flag_captures, 1, "result exposes authoritative capture")

	coordinator = _fixture(GameModeRules.Mode.DEATH_MATCH)
	world = coordinator.world
	var start := world.server_tick
	world.server_tick += 60
	world._record_shield_feedback(2, 3, "shield")
	coordinator.observations.observe(world.server_tick, coordinator.machine, world)
	(world.combatants[3] as CombatantState).alive = false
	coordinator.observations.observe(world.server_tick, coordinator.machine, world)
	world.server_tick += 120
	coordinator.machine.last_heat_winner = 2
	coordinator.observations.enter_state(MatchStateMachine.State.HEAT_RESULT, world.server_tick, coordinator.machine, world, world.map_id)
	var row: Dictionary = coordinator.observations.heats[0]
	context.expect_equal(row.first_contact_seconds, 1.0, "shield contact counts as first combat contact")
	context.expect_equal(row.eliminated_seconds[3], 2.0, "elimination duration is measured through heat end")
	context.expect_equal(row.duration_seconds, 3.0, "heat duration uses authoritative ticks")
	context.expect_equal(row.start_tick, start, "observation retains actual start tick")
	var logged := preload("res://src/shared/match/match_observations.gd").log_rows(row)
	context.expect_equal(logged.size(), 3, "heat log has one summary and one row per participant")
	context.expect_false(logged[0].has("starting_builds"), "summary avoids deep player dictionaries")
	context.expect_equal(NetworkBridge._bounded_log_value(logged[2]).eliminated_seconds, 2.0, "bounded production logger retains downtime values")
	context.expect_equal(NetworkBridge._bounded_log_value({2: 3}), {"2": 3}, "numeric dictionary keys log without constructor errors")
	context.expect_true(float(row.draft_seconds) > 0.0, "draft duration includes actual pre-countdown time")
	coordinator.observations.record_bye(2)
	coordinator.observations.record_pickup(2, true)
	coordinator.observations.record_pickup(2, false)
	world.server_tick += 120
	coordinator.observations.enter_state(MatchStateMachine.State.ROUND_RESULT, world.server_tick, coordinator.machine, world, world.map_id)
	world.server_tick += 180
	coordinator.observations.enter_state(MatchStateMachine.State.ACTIVE_HEAT, world.server_tick, coordinator.machine, world, world.map_id)
	context.expect_equal(coordinator.observations._heat.turnaround_seconds, 5.0, "turnaround excludes active heat time")
	context.expect_equal(coordinator.observations._heat.round_turnaround_seconds, 5.0, "round turnaround includes preceding heat result panel")
	context.expect_equal(coordinator.observations._heat.draft_byes[2], 1, "heat cohorts retain prior byes")
	context.expect_equal(coordinator.observations._heat.pickups_at_start[2], 2, "collection cohorts include temporary and permanent pickups")
	context.expect_equal(coordinator.observations._heat.permanent_pickups_at_start[2], 1, "temporary pickups cannot contaminate permanent pickup cohorts")
	for index in 130:
		coordinator.observations.enter_state(MatchStateMachine.State.HEAT_RESULT, world.server_tick, coordinator.machine, world, world.map_id)
		coordinator.observations.enter_state(MatchStateMachine.State.ACTIVE_HEAT, world.server_tick, coordinator.machine, world, world.map_id)
	context.expect_equal(coordinator.observations.heats.size(), 128, "long sessions keep bounded heat observations")
	var respawning := _fixture(GameModeRules.Mode.KING_OF_THE_HILL)
	(respawning.world.combatants[3] as CombatantState).alive = false
	respawning.world.step(1.0 / 60.0, false)
	respawning.step(1.0 / 60.0)
	var death_tick := respawning.world.server_tick
	for tick in roundi(GameModeRules.OBJECTIVE_RESPAWN_SECONDS * 60.0):
		respawning.world.step(1.0 / 60.0, false)
		respawning.step(1.0 / 60.0)
	context.expect_true((respawning.world.combatants[3] as CombatantState).alive, "timing fixture reaches actual respawn")
	context.expect_equal(respawning.observations._heat.eliminated_seconds[3], GameModeRules.OBJECTIVE_RESPAWN_SECONDS, "respawn downtime includes no extra observation tick")
	context.expect_equal(respawning.world.server_tick - death_tick, roundi(GameModeRules.OBJECTIVE_RESPAWN_SECONDS * 60.0), "respawn fixture advances exact delay")
	var fresh := _fixture(GameModeRules.Mode.DEATH_MATCH)
	context.expect_true(fresh.observations.contributions.is_empty() and fresh.observations.draft_byes.is_empty(), "fresh coordinator clears contribution and fairness history")


static func _fixture(mode: int) -> AuthoritativeMatchCoordinator:
	var config := MatchConfig.new()
	config.game_mode = mode
	config.draft_duration_seconds = 0.05
	config.countdown_duration_seconds = 0.05
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for id in [2, 3]:
		lobby.admit(id, "Pilot%d" % id)
		world.add_peer(id)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 881)
	coordinator.start(0)
	for tick in 120:
		world.step(1.0 / 60.0, false)
		coordinator.step(1.0 / 60.0)
		if coordinator.controls_enabled():
			break
	return coordinator
