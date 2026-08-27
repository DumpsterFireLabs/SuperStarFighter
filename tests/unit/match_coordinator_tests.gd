class_name MatchCoordinatorTests
extends RefCounted

const CardPowerupSystemScript = preload("res://src/shared/combat/card_powerup_system.gd")


static func run(context: TestContext) -> void:
	_validate_complete_match_and_rematch(context)
	_validate_last_survivor_resolution(context)
	_validate_round_winner_draft_bye(context)
	_validate_npc_draft(context)
	_validate_forfeit(context)
	_validate_powerup_match_integration(context)
	_validate_objective_modes(context)


static func _validate_complete_match_and_rematch(context: TestContext) -> void:
	var config := _fast_config()
	var lobby := ServerLobby.new(config)
	for peer_id in [2, 3, 4]:
		context.expect_true(lobby.admit(peer_id, "Pilot%d" % peer_id).ok, "coordinator fixture admits peer %d" % peer_id)
	_ready_all(lobby)
	context.expect_true(lobby.request_start(2).ok, "coordinator fixture authorizes match start")
	var world := AuthoritativeWorld.new()
	for peer_id in [2, 3, 4]:
		world.add_peer(peer_id)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 12345)
	context.expect_true(coordinator.start(world.server_tick), "coordinator starts authoritative match")
	context.expect_equal(coordinator.state(), MatchStateMachine.State.DRAFT, "match begins in draft")
	var offers := coordinator.drain_private_offers()
	context.expect_equal(offers.size(), 3, "draft creates one private offer per participant")
	for offer_value in offers:
		var offer := offer_value as Dictionary
		context.expect_equal((offer.card_ids as Array).size(), 5, "initial coordinator offer contains five cards")
		context.expect_equal(
			coordinator.select_card(int(offer.peer_id), String(offer.offer_token), offer.card_ids[0]),
			DraftManager.SelectionResult.ACCEPTED,
			"coordinator accepts offered card with current token"
		)
	_advance(world, coordinator, 1)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.COUNTDOWN, "all-ready draft completes early")
	for player_value in coordinator.machine.players.values():
		var player := player_value as PlayerMatchState
		context.expect_equal(player.card_stacks.size(), 1, "draft selections apply simultaneously to every build")
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)

	var late_result := lobby.admit(5, "LatePilot")
	context.expect_true(late_result.ok, "mid-match late peer is admitted")
	world.add_peer(5)
	coordinator.add_late_spectator(late_result.player)
	context.expect_false((coordinator.machine.players[5] as PlayerMatchState).participant, "mid-match late peer remains spectator")
	context.expect_false((world.combatants[5] as CombatantState).alive, "late spectator has no authoritative ship authority")
	context.expect_equal(
		coordinator.current_state_payload().get("state_name"),
		"ACTIVE_HEAT",
		"late spectator can synchronize the current match state"
	)

	_finish_heat(world, coordinator, 0)
	var observed_elimination_event := false
	for event_value in coordinator.drain_events():
		if (event_value as Dictionary).event_type == &"PLAYER_ELIMINATED":
			observed_elimination_event = true
	context.expect_true(observed_elimination_event, "combat elimination emits a reliable match event")
	context.expect_true(coordinator.machine.tied_heat, "simultaneous death produces tied heat")
	context.expect_equal(coordinator.machine.scores.get_score(2).heat_wins, 0, "tied heat awards no score")
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	_finish_heat(world, coordinator, 2)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	_finish_heat(world, coordinator, 3)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	_finish_heat(world, coordinator, 2)
	context.expect_equal(coordinator.machine.heat_number, 4, "round can continue beyond three heats")
	_advance_until_state(world, coordinator, MatchStateMachine.State.MATCH_RESULT)
	context.expect_equal(coordinator.machine.last_round_winner, 2, "first player to two heat wins takes the decisive round")
	context.expect_equal(coordinator.machine.match_winner, 2, "round target one resolves match winner")
	_advance(world, coordinator, 120)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.MATCH_RESULT, "match coordinator keeps final standings open indefinitely")
	context.expect_true(coordinator.return_to_lobby(), "match coordinator accepts an explicit results exit")
	context.expect_true(coordinator.is_finished(), "match coordinator finishes after the explicit results exit")
	context.expect_false(lobby.match_active, "explicit results exit returns server lobby to idle")
	context.expect_true((lobby.players[5] as PlayerMatchState).participant, "late spectator promotes on lobby return")
	for player_value in coordinator.machine.players.values():
		var player := player_value as PlayerMatchState
		if player.connected:
			context.expect_empty(player.card_stacks, "lobby return clears final card builds")
			context.expect_equal(player.score.round_wins, 0, "lobby return clears final round score")

	_ready_all(lobby)
	context.expect_true(lobby.request_start(2).ok, "same lobby can start a second match")
	var second := AuthoritativeMatchCoordinator.new(lobby, world, 54321)
	context.expect_true(second.start(world.server_tick), "second match starts with fresh coordinator")
	context.expect_equal(second.state(), MatchStateMachine.State.DRAFT, "second match begins with fresh draft")
	var second_offers := second.drain_private_offers()
	context.expect_equal(second_offers.size(), 4, "promoted spectator drafts in second match")
	_advance_until_state(world, second, MatchStateMachine.State.COUNTDOWN)
	for player_value in second.machine.players.values():
		var player := player_value as PlayerMatchState
		context.expect_equal(player.card_stacks.size(), 1, "draft timeout auto-selects for second match")


static func _validate_forfeit(context: TestContext) -> void:
	var lobby := ServerLobby.new(_fast_config())
	lobby.admit(10, "First")
	lobby.admit(11, "Second")
	_ready_all(lobby)
	lobby.request_start(10)
	var world := AuthoritativeWorld.new()
	world.add_peer(10)
	world.add_peer(11)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 77)
	coordinator.start(0)
	coordinator.disconnect_peer(11)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.MATCH_RESULT, "single remaining participant wins by forfeit")
	context.expect_equal(coordinator.machine.match_winner, 10, "forfeit records remaining participant as match winner")


static func _validate_powerup_match_integration(context: TestContext) -> void:
	var config := _fast_config()
	config.random_spawn_powerups = true
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in [70, 71]:
		lobby.admit(peer_id, "Powerup%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(70)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 9090)
	coordinator.start(0)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	coordinator.drain_events()
	_advance(world, coordinator, roundi(CardPowerupSystemScript.SPAWN_INTERVAL_SECONDS * GameConstants.PHYSICS_TICKS_PER_SECOND))
	var spawned: Dictionary = {}
	for event_value in coordinator.drain_events():
		var event := event_value as Dictionary
		if StringName(event.event_type) == &"CARD_POWERUP_SPAWNED":
			spawned = event.payload as Dictionary
			break
	context.expect_false(spawned.is_empty(), "enabled lobby option reaches the coordinator and emits a reliable timed spawn")
	if spawned.is_empty():
		return
	(world.combatants[70] as CombatantState).position = spawned.position
	_advance(world, coordinator, 1)
	var collected := false
	for event_value in coordinator.drain_events():
		var event := event_value as Dictionary
		if StringName(event.event_type) == &"CARD_POWERUP_COLLECTED" and int((event.payload as Dictionary).peer_id) == 70:
			collected = (event.payload as Dictionary).has("builds")
	context.expect_true(collected, "coordinator publishes collected inventory builds for immediate client prediction")
	var collector := coordinator.machine.players[70] as PlayerMatchState
	context.expect_equal(int(collector.temporary_card_stacks.get(StringName(spawned.card_id), 0)), 1, "default coordinator pickup is retained for the current heat")
	context.expect_equal(int((coordinator.current_state_payload().builds as Dictionary)[70].get(StringName(spawned.card_id), 0)), 1, "temporary pickup is included in the authoritative effective build")
	var target := world.combatants[71] as CombatantState
	target.health = 10.0
	var lethal := ProjectileState.create(900, 70, 1, target.position - Vector2(30.0, 0.0), 0.0, CombatStats.create_base())
	world.projectile_registry.add(lethal)
	world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	coordinator.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_equal(int((coordinator.current_state_payload().scores as Dictionary)[70].kills), 1, "coordinator publishes a match-total kill credited to the attacker")
	context.expect_empty(collector.temporary_card_stacks, "non-permanent arena pickup is removed when its heat ends")


static func _validate_objective_modes(context: TestContext) -> void:
	var hill_fixture := _objective_fixture(GameModeRules.Mode.KING_OF_THE_HILL, 2, 6060)
	var hill_world := hill_fixture.world as AuthoritativeWorld
	var hill_coordinator := hill_fixture.coordinator as AuthoritativeMatchCoordinator
	var hill_position := (hill_coordinator.current_state_payload().objective as Dictionary).position as Vector2
	(hill_world.combatants[1] as CombatantState).position = hill_position
	(hill_world.combatants[2] as CombatantState).position = hill_position + Vector2(GameModeRules.OBJECTIVE_ZONE_RADIUS + 200.0, 0.0)
	_advance(hill_world, hill_coordinator, ceili(GameModeRules.HILL_HOLD_SECONDS * GameConstants.PHYSICS_TICKS_PER_SECOND) + 1)
	context.expect_equal(hill_coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "uncontested hill control for twenty seconds resolves the heat")
	context.expect_equal(hill_coordinator.machine.last_heat_winner, 1, "the surviving hill controller wins the objective heat")

	var flag_fixture := _objective_fixture(GameModeRules.Mode.CAPTURE_THE_FLAG, 2, 7070)
	var flag_world := flag_fixture.world as AuthoritativeWorld
	var flag_coordinator := flag_fixture.coordinator as AuthoritativeMatchCoordinator
	var flag_objective := flag_coordinator.current_state_payload().objective as Dictionary
	(flag_world.combatants[1] as CombatantState).position = flag_objective.flag_position as Vector2
	_advance(flag_world, flag_coordinator, 1)
	context.expect_equal(int((flag_coordinator.current_state_payload().objective as Dictionary).flag_carrier_id), 1, "touching the neutral flag assigns its carrier authoritatively")
	flag_objective = flag_coordinator.current_state_payload().objective as Dictionary
	var neutral_zones := flag_objective.capture_zones as Dictionary
	(flag_world.combatants[1] as CombatantState).position = neutral_zones[0] as Vector2
	_advance(flag_world, flag_coordinator, 1)
	context.expect_equal(flag_coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "solo capture the flag resolves at the neutral extraction zone")
	context.expect_equal(flag_coordinator.machine.last_heat_winner, 1, "the neutral flag carrier wins the capture heat")

	var team_flag_fixture := _objective_fixture(GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, 4, 8081)
	var team_flag_world := team_flag_fixture.world as AuthoritativeWorld
	var team_flag_coordinator := team_flag_fixture.coordinator as AuthoritativeMatchCoordinator
	var team_flag_objective := team_flag_coordinator.current_state_payload().objective as Dictionary
	(team_flag_world.combatants[1] as CombatantState).position = team_flag_objective.flag_position as Vector2
	_advance(team_flag_world, team_flag_coordinator, 1)
	team_flag_objective = team_flag_coordinator.current_state_payload().objective as Dictionary
	var team_zones := team_flag_objective.capture_zones as Dictionary
	(team_flag_world.combatants[1] as CombatantState).position = team_zones[1] as Vector2
	_advance(team_flag_world, team_flag_coordinator, 1)
	context.expect_equal(team_flag_coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "team flag capture resolves when the carrier reaches its own base")
	context.expect_equal(team_flag_coordinator.machine.last_heat_winner_team, 1, "team capture credits the carrier's full team")


static func _objective_fixture(mode: int, player_count: int, seed: int) -> Dictionary:
	var config := _fast_config()
	config.game_mode = mode
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in range(1, player_count + 1):
		lobby.admit(peer_id, "Objective%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(1)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, seed)
	coordinator.start(0)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	return {"world": world, "coordinator": coordinator}


static func _validate_last_survivor_resolution(context: TestContext) -> void:
	var lobby := ServerLobby.new(_fast_config())
	var world := AuthoritativeWorld.new()
	for peer_id in [20, 21, 22]:
		lobby.admit(peer_id, "Survivor%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(20)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 8080)
	coordinator.start(0)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	(world.combatants[21] as CombatantState).alive = false
	(world.combatants[21] as CombatantState).health = 0.0
	(world.combatants[22] as CombatantState).alive = false
	(world.combatants[22] as CombatantState).health = 0.0
	_advance(world, coordinator, 1)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "one remaining ship ends the heat immediately")
	context.expect_equal(coordinator.machine.last_heat_winner, 20, "the last living ship receives the heat win")
	context.expect_equal(coordinator.machine.scores.get_score(20).heat_wins, 1, "first survival awards one of two required heat wins")

	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	(world.combatants[21] as CombatantState).alive = false
	(world.combatants[21] as CombatantState).health = 0.0
	(world.combatants[22] as CombatantState).alive = false
	(world.combatants[22] as CombatantState).health = 0.0
	_advance(world, coordinator, 1)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "second last-survivor result closes combat")
	_advance_until_state(world, coordinator, MatchStateMachine.State.MATCH_RESULT)
	context.expect_equal(coordinator.machine.last_round_winner, 20, "two last-survivor heat wins end the match without a final round cooldown")


static func _validate_npc_draft(context: TestContext) -> void:
	var lobby := ServerLobby.new(_fast_config())
	lobby.admit(30, "HumanDrafter")
	lobby.request_player_limit(30, 2)
	lobby.request_npcs_enabled(30, true)
	var npc_id := lobby.npc_peer_ids()[0]
	lobby.request_npc_difficulty(30, npc_id, NpcPilotController.Difficulty.INSANE)
	_ready_all(lobby)
	lobby.request_start(30)
	var world := AuthoritativeWorld.new()
	for player_value in lobby.players.values():
		world.add_peer((player_value as PlayerMatchState).peer_id)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 3030)
	coordinator.start(0)
	var human_offers := coordinator.drain_private_offers()
	context.expect_equal(human_offers.size(), 1, "only the human receives a private rendered draft offer")
	context.expect_true(coordinator.draft.get_offer(npc_id).locked, "NPC locks a deterministic server-owned draft choice")
	context.expect_equal((coordinator.machine.players[npc_id] as PlayerMatchState).npc_difficulty, NpcPilotController.Difficulty.INSANE, "active match snapshots the NPC difficulty selected before coordinator creation")
	var human_offer := human_offers[0] as Dictionary
	coordinator.select_card(30, String(human_offer.offer_token), human_offer.card_ids[0])
	_advance(world, coordinator, 1)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.COUNTDOWN, "human and NPC choices complete the draft together")
	context.expect_equal((coordinator.machine.players[npc_id] as PlayerMatchState).card_stacks.size(), 1, "NPC selected card applies to its persistent build")


static func _validate_round_winner_draft_bye(context: TestContext) -> void:
	var config := _fast_config()
	config.rounds_to_win = 2
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in [40, 41, 42]:
		lobby.admit(peer_id, "Balance%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(40)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 4040)
	coordinator.start(0)
	var first_round_map := StringName(coordinator.current_state_payload().map_id)
	context.expect_true(ArenaLayout.has_map(first_round_map), "first round resolves to a registered map")
	context.expect_equal(world.map_id, first_round_map, "authoritative world receives the first-round map")
	context.expect_equal(coordinator.current_state_payload().map_name, ArenaLayout.display_name(first_round_map), "round payload publishes the selected map name")
	coordinator.drain_private_offers()
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	context.expect_equal(StringName(coordinator.current_state_payload().map_id), first_round_map, "countdown and first heat retain the round map")
	_finish_heat(world, coordinator, 40)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	context.expect_equal(StringName(coordinator.current_state_payload().map_id), first_round_map, "second heat remains on the same map")
	_finish_heat(world, coordinator, 40)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ROUND_RESULT)
	context.expect_equal(StringName(coordinator.current_state_payload().map_id), first_round_map, "round result remains on the completed round map")
	_advance_until_state(world, coordinator, MatchStateMachine.State.DRAFT)
	var second_round_map := StringName(coordinator.current_state_payload().map_id)
	context.expect_true(second_round_map != first_round_map, "winning the round advances to a new map")
	context.expect_equal(world.map_id, second_round_map, "authoritative world switches geometry exactly at the next round")
	context.expect_equal(coordinator.current_state_payload().draft_bye_peer_id, 40, "next draft publishes the previous round winner's bye")
	context.expect_true(coordinator.draft.get_offer(40).skipped, "coordinator excludes the round winner from the next draft")
	context.expect_empty(coordinator.draft.get_offer(40).card_ids, "round winner receives no private card draw")
	var comeback_offers := coordinator.drain_private_offers()
	context.expect_equal(comeback_offers.size(), 2, "only players who lost the round receive private draws")
	for offer_value in comeback_offers:
		var offer := offer_value as Dictionary
		context.expect_true(int(offer.peer_id) in [41, 42], "comeback offer belongs to a non-winner")


static func _ready_all(lobby: ServerLobby) -> void:
	for peer_id in lobby.human_peer_ids():
		lobby.request_ready(peer_id, true)


static func _fast_config() -> MatchConfig:
	var config := MatchConfig.new()
	config.rounds_to_win = 1
	config.draft_duration_seconds = 0.05
	config.countdown_duration_seconds = 0.05
	config.heat_result_duration_seconds = 0.05
	config.round_result_duration_seconds = 0.05
	return config


static func _advance(
	world: AuthoritativeWorld,
	coordinator: AuthoritativeMatchCoordinator,
	ticks: int
) -> void:
	for tick in ticks:
		world.step(1.0 / 60.0, coordinator.controls_enabled())
		coordinator.step(1.0 / 60.0)


static func _advance_until_state(
	world: AuthoritativeWorld,
	coordinator: AuthoritativeMatchCoordinator,
	target_state: int,
	maximum_ticks: int = 120
) -> void:
	for tick in maximum_ticks:
		if coordinator.state() == target_state:
			return
		_advance(world, coordinator, 1)


static func _finish_heat(
	world: AuthoritativeWorld,
	coordinator: AuthoritativeMatchCoordinator,
	winner_peer_id: int
) -> void:
	for peer_id in coordinator.machine.participant_ids():
		var combatant := world.combatants[peer_id] as CombatantState
		if peer_id != winner_peer_id:
			combatant.health = 0.0
			combatant.alive = false
	_advance(world, coordinator, 1)
