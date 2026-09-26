class_name MatchCoordinatorTests
extends RefCounted

const CardPowerupSystemScript = preload("res://src/shared/combat/card_powerup_system.gd")


static func run(context: TestContext) -> void:
	_validate_incremental_draft(context)
	_validate_global_pause(context)
	_validate_complete_match_and_rematch(context)
	_validate_elimination_attribution_payload(context)
	_validate_match_extension(context)
	_validate_last_survivor_resolution(context)
	_validate_round_winner_draft_bye(context)
	_validate_npc_draft(context)
	_validate_forfeit(context)
	_validate_reconnect_keeps_seat(context)
	_validate_reconnect_holds_forfeit(context)
	_validate_reconnect_expiry_forfeits(context)
	_validate_reconnect_during_draft(context)
	_validate_reconnect_during_countdown(context)
	_validate_reconnect_deadline_owned_by_coordinator(context)
	_validate_reconnect_names_stay_consistent(context)
	_validate_reconnect_hold_does_not_freeze_results(context)
	_validate_powerup_match_integration(context)
	_validate_objective_modes(context)
	_validate_objective_respawns(context)
	_validate_hill_round_rotation(context)
	_validate_free_for_all_spawn_spread(context)
	_validate_multi_team_spawns(context)
	_validate_team_npc_spawn_resets(context)


static func _validate_global_pause(context: TestContext) -> void:
	var lobby := ServerLobby.new(_fast_config())
	var world := AuthoritativeWorld.new()
	for peer_id in [2, 3, 4]:
		lobby.admit(peer_id, "Pilot%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(2)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 5150)
	coordinator.start(0)
	context.expect_false(coordinator.request_pause(3, true), "guest cannot pause the global match")
	context.expect_false(coordinator.request_pause(0, true), "missing sender cannot pause the match")
	for phase in [MatchStateMachine.State.DRAFT, MatchStateMachine.State.COUNTDOWN, MatchStateMachine.State.ACTIVE_HEAT]:
		_advance_until_state(world, coordinator, phase)
		context.expect_equal(coordinator.state(), phase, "pause fixture reaches requested phase")
		var tick := world.server_tick
		var deadline := coordinator.machine.state_deadline_tick
		var pilot := world.combatants[2] as CombatantState
		var position := pilot.position
		pilot.weapon.cooldown_remaining = 0.5
		world.submit_input(2, PlayerInputFrame.new(50 + phase, tick, Vector2.RIGHT, 0.0, true))
		coordinator.drain_events()
		context.expect_true(coordinator.request_pause(2, true), "host can pause drafts, countdowns and combat")
		context.expect_true(coordinator.request_pause(2, true), "repeated pause is idempotent")
		context.expect_equal(coordinator.drain_events().size(), 1, "pause broadcasts exactly one reliable event")
		context.expect_true(coordinator.current_state_payload().paused, "late spectator state includes global pause")
		context.expect_false(coordinator.controls_enabled(), "pause disables NPC and human combat")
		context.expect_false(world.submit_input(2, PlayerInputFrame.new(1000, tick, Vector2.RIGHT, 0.0, true)), "pause rejects queued combat input")
		_advance(world, coordinator, 600)
		context.expect_equal(world.server_tick, tick, "ten-second break freezes the authoritative clock")
		context.expect_equal(coordinator.state(), phase, "pause prevents timed phase transitions")
		context.expect_equal(coordinator.machine.state_deadline_tick, deadline, "pause preserves remaining deadline")
		context.expect_equal(pilot.position, position, "pause freezes moving ships")
		context.expect_approx(pilot.weapon.cooldown_remaining, 0.5, "pause freezes weapon cooldowns")
		context.expect_false(coordinator.request_pause(3, false), "guest cannot resume a host pause")
		context.expect_true(coordinator.request_pause(2, false), "host can resume the match")
		context.expect_false((world.latest_inputs[2] as PlayerInputFrame).firing, "resume discards held fire")
		context.expect_equal((world.latest_inputs[2] as PlayerInputFrame).movement, Vector2.ZERO, "resume discards held movement")
		_advance(world, coordinator, 1)
		context.expect_equal(world.server_tick, tick + 1, "resume advances exactly one tick without catch-up")
	coordinator.request_pause(2, true)
	coordinator.disconnect_peer(2)
	lobby.remove(2)
	context.expect_true(world.simulation_paused, "leader departure preserves the break for remaining pilots")
	context.expect_true(coordinator.request_pause(lobby.leader_id, false), "replacement host can resume after leadership transfer")


static func _validate_elimination_attribution_payload(context: TestContext) -> void:
	var lobby := ServerLobby.new(_fast_config())
	for peer_id in [2, 3]:
		lobby.admit(peer_id, "Pilot%d" % peer_id)
	_ready_all(lobby)
	lobby.request_start(2)
	var world := AuthoritativeWorld.new()
	for peer_id in [2, 3]:
		world.add_peer(peer_id)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 5150)
	coordinator.start(0)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	coordinator.drain_events()
	var victim := world.combatants[3] as CombatantState
	victim.health = 0.0
	victim.alive = false
	world._kills_since_drain.append({"killer_id": 2, "target_id": 3})
	coordinator.step(1.0 / 60.0)
	var elimination_payload: Dictionary = {}
	for event_value in coordinator.drain_events():
		var event := event_value as Dictionary
		if event.event_type == &"PLAYER_ELIMINATED":
			elimination_payload = event.payload as Dictionary
	var records := elimination_payload.get("eliminations", []) as Array
	context.expect_equal(records.size(), 1, "combat elimination publishes one kill-feed record per victim")
	if not records.is_empty():
		context.expect_equal(int(records[0].killer_id), 2, "kill-feed record preserves the authoritative killer")
		context.expect_equal(int(records[0].victim_id), 3, "kill-feed record preserves the authoritative victim")
		context.expect_equal(String(records[0].reason), "combat", "credited kill-feed record identifies combat attribution")
	var uncredited := coordinator._elimination_records([3], [])
	context.expect_equal(int(uncredited[0].killer_id), 0, "uncredited elimination does not invent a killer")
	context.expect_equal(String(uncredited[0].reason), "environment", "uncredited elimination is labeled as environmental")


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
	var match_players := coordinator.current_state_payload().players as Array
	context.expect_equal(match_players.size(), 3, "match state carries every participant's immutable presentation identity")
	context.expect_true((match_players[0] as Dictionary).has("ship_pattern"), "match state carries ship patterns into gameplay independently of lobby updates")
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
	context.expect_equal((coordinator.machine.players[5] as PlayerMatchState).ship_pattern, (late_result.player as PlayerMatchState).ship_pattern, "late spectator retains lobby appearance identity in match state")
	context.expect_equal(
		coordinator.current_state_payload().get("state_name"),
		"ACTIVE_HEAT",
		"late spectator can synchronize the current match state"
	)

	_finish_heat(world, coordinator, 0)
	var observed_elimination_event := false
	var elimination_scores: Dictionary = {}
	for event_value in coordinator.drain_events():
		var event := event_value as Dictionary
		if event.event_type == &"PLAYER_ELIMINATED":
			observed_elimination_event = true
			elimination_scores = (event.payload as Dictionary).get("scores", {}) as Dictionary
	context.expect_true(observed_elimination_event, "combat elimination emits a reliable match event")
	context.expect_true(elimination_scores.has(2) and elimination_scores.has(3) and elimination_scores.has(4), "combat elimination publishes current scores for live scoreboard refresh")
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


static func _validate_match_extension(context: TestContext) -> void:
	var config := _fast_config()
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in [20, 21]:
		lobby.admit(peer_id, "Pilot%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(20)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 2026)
	coordinator.start(world.server_tick)
	coordinator.drain_private_offers()
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	_finish_heat(world, coordinator, 20)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	_finish_heat(world, coordinator, 20)
	_advance_until_state(world, coordinator, MatchStateMachine.State.MATCH_RESULT)
	var retained_build := (coordinator.machine.players[21] as PlayerMatchState).card_stacks.duplicate(true)
	context.expect_true(coordinator.extend_match(), "coordinator accepts an extension from final results")
	context.expect_equal(coordinator.state(), MatchStateMachine.State.ROUND_RESULT, "coordinator broadcasts a resumed round intermission")
	context.expect_equal(coordinator.current_state_payload().extension_end_round_number, 6, "extension payload publishes the fixed ending round")
	context.expect_equal(coordinator.current_state_payload().rounds_to_win, 1, "extension payload retains the original score target")
	context.expect_equal((coordinator.machine.players[21] as PlayerMatchState).card_stacks, retained_build, "coordinator preserves drafted builds across extension")
	_advance_until_state(world, coordinator, MatchStateMachine.State.DRAFT)
	context.expect_equal(coordinator.current_state_payload().draft_bye_peer_id, 20, "decisive-round winner keeps the normal next-draft bye after extension")
	context.expect_true(coordinator.draft.get_offer(20).skipped, "extended draft skips the prior round winner")
	context.expect_equal(coordinator.drain_private_offers().size(), 1, "only the non-winner receives a new card offer after extension")


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


static func _reconnect_fixture(peer_ids: Array[int], seed: int) -> Dictionary:
	var lobby := ServerLobby.new(_fast_config())
	var world := AuthoritativeWorld.new()
	for peer_id in peer_ids:
		lobby.admit(peer_id, "Pilot%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(peer_ids[0])
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, seed)
	coordinator.start(0)
	return {"lobby": lobby, "world": world, "coordinator": coordinator}


## Mirrors the bridge: the departed lobby record is replaced by one under the new peer id.
static func _rejoin(fixture: Dictionary, previous_peer_id: int, peer_id: int) -> bool:
	var lobby := fixture.lobby as ServerLobby
	var world := fixture.world as AuthoritativeWorld
	var departed := lobby.remove(previous_peer_id)
	lobby.admit(peer_id, "Ignored", departed)
	world.remove_peer(previous_peer_id)
	world.add_peer(peer_id)
	return (fixture.coordinator as AuthoritativeMatchCoordinator).reconnect_peer(previous_peer_id, peer_id)


static func _validate_reconnect_keeps_seat(context: TestContext) -> void:
	var fixture := _reconnect_fixture([2, 3, 4], 4242)
	var world := fixture.world as AuthoritativeWorld
	var lobby := fixture.lobby as ServerLobby
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	var player := coordinator.machine.players[3] as PlayerMatchState
	var cards := player.card_stacks.duplicate()
	context.expect_false(cards.is_empty(), "reconnect fixture drafted a card before the drop")
	coordinator.machine.scores.award_kill(3)
	var color := (lobby.players[3] as PlayerMatchState).ship_color
	context.expect_true(coordinator.disconnect_peer(3, true), "a departing human participant keeps a held seat")
	context.expect_false(world.simulation_paused, "two remaining pilots keep playing while the seat is held")
	context.expect_true(coordinator.can_reconnect(3), "the held seat can be reclaimed")
	context.expect_true(_rejoin(fixture, 3, 9), "the returning pilot reclaims the seat under a new peer id")
	context.expect_false(coordinator.can_reconnect(3), "a seat can be reclaimed only once")
	context.expect_false(coordinator.machine.players.has(3), "the previous peer id no longer owns match state")
	var restored := coordinator.machine.players[9] as PlayerMatchState
	context.expect_equal(restored.card_stacks, cards, "reconnect keeps drafted cards")
	context.expect_equal(coordinator.machine.scores.get_score(9).kills, 1, "reconnect keeps the score")
	context.expect_equal(restored.display_name, "Pilot3", "reconnect keeps the original pilot name")
	context.expect_equal((lobby.players[9] as PlayerMatchState).ship_color, color, "reconnect keeps the ship colour")
	context.expect_true(restored.participant and restored.connected, "the returning pilot is a participant again")
	context.expect_false((world.combatants[9] as CombatantState).alive, "the returning pilot sits out the heat in progress")
	context.expect_true(9 in (coordinator.current_state_payload().participant_peer_ids as Array), "clients see the returning pilot as a participant")
	_finish_heat(world, coordinator, 2)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	context.expect_true((world.combatants[9] as CombatantState).alive, "the returning pilot flies again from the next heat")


static func _validate_reconnect_holds_forfeit(context: TestContext) -> void:
	var fixture := _reconnect_fixture([10, 11], 777)
	var world := fixture.world as AuthoritativeWorld
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	coordinator.drain_events()
	context.expect_true(coordinator.disconnect_peer(11, true), "a 1v1 departure holds the seat")
	context.expect_equal(coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "the interrupted heat goes to the remaining pilot, not the match")
	context.expect_equal(coordinator.machine.last_heat_winner, 10, "the remaining pilot wins the interrupted heat")
	context.expect_true(world.simulation_paused, "the match pauses while waiting for the pilot")
	var pause_events := coordinator.drain_events().filter(func(event: Dictionary) -> bool: return StringName(event.event_type) == &"MATCH_PAUSE_CHANGED")
	context.expect_equal(pause_events.size(), 1, "one pause event announces the wait")
	context.expect_equal(pause_events[0].payload.awaiting_reconnect, ["Pilot11"], "the pause names the missing pilot")
	context.expect_true(coordinator.request_pause(10, false), "host resume during the wait is accepted as intent")
	context.expect_true(world.simulation_paused, "host cannot resume while the match is waiting on a pilot")
	_advance(world, coordinator, 600)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "the wait freezes the match")
	context.expect_true(_rejoin(fixture, 11, 12), "the pilot reclaims the 1v1 seat")
	context.expect_false(world.simulation_paused, "the match resumes once the pilot is back")
	context.expect_equal(coordinator.current_state_payload().awaiting_reconnect, [], "nobody is awaited after the return")
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	context.expect_equal(coordinator.machine.alive_participant_ids(), [10, 12] as Array[int], "both pilots fly the next heat")


static func _validate_reconnect_expiry_forfeits(context: TestContext) -> void:
	var fixture := _reconnect_fixture([10, 11], 778)
	var world := fixture.world as AuthoritativeWorld
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	_advance_until_state(world, coordinator, MatchStateMachine.State.COUNTDOWN)
	coordinator.disconnect_peer(11, true)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.COUNTDOWN, "a held departure does not end the match yet")
	coordinator.release_reconnect(11)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.MATCH_RESULT, "an expired seat forfeits the match")
	context.expect_equal(coordinator.machine.match_winner, 10, "the remaining pilot wins by forfeit after the wait")
	context.expect_false(world.simulation_paused, "the forfeit result is not left paused")
	context.expect_false(coordinator.can_reconnect(11), "an expired seat cannot be reclaimed")
	var npc_fixture := _reconnect_fixture([20, 21], 779)
	(npc_fixture.coordinator as AuthoritativeMatchCoordinator).machine.players[21].is_npc = true
	context.expect_false((npc_fixture.coordinator as AuthoritativeMatchCoordinator).disconnect_peer(21, true), "NPC seats are never held")


static func _validate_reconnect_hold_does_not_freeze_results(context: TestContext) -> void:
	var fixture := _reconnect_fixture([10, 11], 781)
	var world := fixture.world as AuthoritativeWorld
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	context.expect_true(coordinator.request_pause(10, true), "the host pauses before anyone drops")
	coordinator.disconnect_peer(11, true)
	context.expect_true(world.simulation_paused, "the match stays paused while waiting for the pilot")
	coordinator.disconnect_peer(10)
	context.expect_true(coordinator.is_finished(), "the last pilot leaving ends the match")
	context.expect_false(world.simulation_paused, "a host pause from before the hold does not freeze the lobby")
	var resumed := _reconnect_fixture([10, 11], 782)
	var resumed_world := resumed.world as AuthoritativeWorld
	var resumed_coordinator := resumed.coordinator as AuthoritativeMatchCoordinator
	_advance_until_state(resumed_world, resumed_coordinator, MatchStateMachine.State.COUNTDOWN)
	resumed_coordinator.disconnect_peer(11, true)
	resumed_world.latest_inputs[10] = PlayerInputFrame.new(1, resumed_world.server_tick, Vector2.RIGHT, 0.0)
	context.expect_true(_rejoin(resumed, 11, 12), "the pilot reclaims the seat")
	context.expect_false(resumed_world.simulation_paused, "the match resumes after the rejoin")
	context.expect_equal((resumed_world.latest_inputs[10] as PlayerInputFrame).movement, Vector2.ZERO, "input held through the wait is discarded on resume")


static func _validate_reconnect_during_countdown(context: TestContext) -> void:
	var fixture := _reconnect_fixture([10, 11], 780)
	var world := fixture.world as AuthoritativeWorld
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	_advance_until_state(world, coordinator, MatchStateMachine.State.COUNTDOWN)
	coordinator.disconnect_peer(11, true)
	context.expect_true(world.simulation_paused, "a 1v1 countdown waits for the missing pilot")
	context.expect_true(_rejoin(fixture, 11, 12), "the pilot reclaims the seat during the countdown")
	context.expect_true((world.combatants[12] as CombatantState).alive, "a pilot back during the countdown joins the coming heat")
	var spawn := (world.combatants[12] as CombatantState).position
	context.expect_true(spawn.distance_to((world.combatants[10] as CombatantState).position) > GameConstants.SHIP_COLLISION_RADIUS * 2.0, "the returning pilot spawns clear of the opponent")
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	context.expect_equal(coordinator.machine.alive_participant_ids(), [10, 12] as Array[int], "both pilots fly the heat after a countdown rejoin")
	_finish_heat(world, coordinator, 10)
	context.expect_equal(coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "the heat resolves normally once a pilot is eliminated")


static func _validate_reconnect_deadline_owned_by_coordinator(context: TestContext) -> void:
	var fixture := _reconnect_fixture([10, 11], 781)
	var world := fixture.world as AuthoritativeWorld
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	var now := [1000.0]
	coordinator.clock = func() -> float: return now[0]
	_advance_until_state(world, coordinator, MatchStateMachine.State.COUNTDOWN)
	coordinator.disconnect_peer(11, true)
	now[0] += GameConstants.RECONNECT_GRACE_SECONDS - 1.0
	context.expect_empty(coordinator.expire_reconnects(), "a held seat survives inside its grace period")
	context.expect_true(world.simulation_paused, "the match still waits inside the grace period")
	now[0] += 1.0
	context.expect_equal(coordinator.expire_reconnects(), [11] as Array[int], "the coordinator releases a seat when its own deadline passes")
	context.expect_equal(coordinator.state(), MatchStateMachine.State.MATCH_RESULT, "an expired 1v1 seat forfeits without any caller bookkeeping")
	context.expect_false(world.simulation_paused, "the forfeit is not left paused")
	context.expect_empty(coordinator.expire_reconnects(), "a released seat expires only once")


static func _validate_reconnect_names_stay_consistent(context: TestContext) -> void:
	var lobby := ServerLobby.new(_fast_config())
	lobby.admit(1, "Pilot3")
	lobby.reserved_names = PackedStringArray(["Ace"])
	var newcomer := lobby.admit(2, "Ace").player as PlayerMatchState
	context.expect_equal(newcomer.display_name, "Ace#2", "a newcomer cannot take a held seat's name")
	# Without a reservation the lobby may rename the returning pilot; the
	# scoreboard must then show the same name.
	var fixture := _reconnect_fixture([3, 4, 5], 782)
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	var fixture_lobby := fixture.lobby as ServerLobby
	coordinator.disconnect_peer(4, true)
	var departed := fixture_lobby.remove(4)
	fixture_lobby.admit(8, "Pilot4")
	fixture_lobby.admit(9, "Ignored", departed)
	(fixture.world as AuthoritativeWorld).add_peer(9)
	context.expect_true(coordinator.reconnect_peer(4, 9), "the pilot reclaims the seat despite the name clash")
	var lobby_name := (fixture_lobby.players[9] as PlayerMatchState).display_name
	context.expect_equal((coordinator.machine.players[9] as PlayerMatchState).display_name, lobby_name, "lobby and scoreboard show the same returning name")


static func _validate_reconnect_during_draft(context: TestContext) -> void:
	var fixture := _reconnect_fixture([30, 31, 32], 31337)
	var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
	context.expect_equal(coordinator.state(), MatchStateMachine.State.DRAFT, "draft fixture starts in the draft")
	var cards := coordinator.draft.get_offer(31).card_ids.duplicate()
	coordinator.drain_private_offers()
	coordinator.disconnect_peer(31, true)
	context.expect_true(coordinator.draft.get_offer(31).locked, "a departed pilot does not block the draft")
	context.expect_true(_rejoin(fixture, 31, 40), "the pilot reclaims the seat during the draft")
	var offer := coordinator.draft.get_offer(40)
	context.expect_true(offer != null and not offer.locked, "the returning pilot gets their draft pick back")
	context.expect_equal(offer.card_ids, cards, "the reopened offer has the same cards")
	var offers := coordinator.drain_private_offers()
	context.expect_equal(offers.size(), 1, "the reopened offer is sent to the returning pilot")
	context.expect_equal(int(offers[0].peer_id), 40, "the offer goes to the new peer id")
	context.expect_equal(coordinator.select_card(40, offer.token, cards[0]), DraftManager.SelectionResult.ACCEPTED, "the returning pilot can pick a card")


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
	_advance(hill_world, hill_coordinator, 5 * GameConstants.PHYSICS_TICKS_PER_SECOND)
	(hill_world.combatants[1] as CombatantState).position = hill_position + Vector2(GameModeRules.OBJECTIVE_ZONE_RADIUS + 300.0, 0.0)
	_advance(hill_world, hill_coordinator, 1)
	var paused_hill_progress := float(((hill_coordinator.current_state_payload().objective as Dictionary).progress as Dictionary).get(1, 0.0))
	context.expect_true(paused_hill_progress >= 4.9, "leaving the hill pauses rather than erases earned control time")
	(hill_world.combatants[1] as CombatantState).position = hill_position
	_advance(
		hill_world,
		hill_coordinator,
		ceili((GameModeRules.HILL_HOLD_SECONDS - paused_hill_progress) * GameConstants.PHYSICS_TICKS_PER_SECOND) + 1
	)
	context.expect_equal(hill_coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "cumulative uncontested hill time resolves the heat at twenty seconds")
	context.expect_equal(hill_coordinator.machine.last_heat_winner, 1, "the surviving hill controller wins the objective heat")

	var overtime_fixture := _objective_fixture(GameModeRules.Mode.KING_OF_THE_HILL, 3, 6061)
	var overtime_world := overtime_fixture.world as AuthoritativeWorld
	var overtime_coordinator := overtime_fixture.coordinator as AuthoritativeMatchCoordinator
	var overtime_payload := overtime_coordinator.current_state_payload()
	var overtime_hill := (overtime_payload.objective as Dictionary).position as Vector2
	context.expect_equal(overtime_payload.overtime_center, overtime_hill, "King of the Hill publishes the hill as the overtime center")
	context.expect_approx(
		float(overtime_payload.overtime_minimum_radius),
		GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS,
		"King of the Hill publishes the larger overtime minimum"
	)
	var hill_pilot := overtime_world.combatants[1] as CombatantState
	var buffered_pilot := overtime_world.combatants[2] as CombatantState
	var outside_pilot := overtime_world.combatants[3] as CombatantState
	hill_pilot.position = overtime_hill
	buffered_pilot.position = overtime_hill + Vector2(GameModeRules.OBJECTIVE_ZONE_RADIUS + 25.0, 0.0)
	outside_pilot.position = overtime_hill + Vector2(GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS + 25.0, 0.0)
	overtime_coordinator.overtime_start_seconds = 0.0
	overtime_world.server_tick = (
		overtime_coordinator.machine.state_entered_tick +
		roundi(GameConstants.OVERTIME_SHRINK_SECONDS * GameConstants.PHYSICS_TICKS_PER_SECOND)
	)
	overtime_coordinator.step(0.1)
	context.expect_approx(hill_pilot.health, hill_pilot.stats.max_health, "the relocated hill center remains safe in overtime")
	context.expect_approx(buffered_pilot.health, buffered_pilot.stats.max_health, "the larger KOTH overtime ring protects the hill buffer")
	context.expect_true(outside_pilot.health < outside_pilot.stats.max_health, "a pilot outside the KOTH overtime ring still takes damage")

	var flag_fixture := _objective_fixture(GameModeRules.Mode.CAPTURE_THE_FLAG, 2, 7070)
	var flag_world := flag_fixture.world as AuthoritativeWorld
	var flag_coordinator := flag_fixture.coordinator as AuthoritativeMatchCoordinator
	var flag_objective := flag_coordinator.current_state_payload().objective as Dictionary
	(flag_world.combatants[1] as CombatantState).position = flag_objective.flag_position as Vector2
	_advance(flag_world, flag_coordinator, 1)
	context.expect_equal(int((flag_coordinator.current_state_payload().objective as Dictionary).flag_carrier_id), 1, "touching the neutral flag assigns its carrier authoritatively")
	flag_objective = flag_coordinator.current_state_payload().objective as Dictionary
	var neutral_zones := flag_objective.capture_zones as Dictionary
	context.expect_true(neutral_zones.has(1) and neutral_zones.has(2), "solo flag mode publishes a separate return base for every pilot")
	(flag_world.combatants[1] as CombatantState).position = neutral_zones[2] as Vector2
	_advance(flag_world, flag_coordinator, 1)
	context.expect_equal(flag_coordinator.state(), MatchStateMachine.State.ACTIVE_HEAT, "a flag carrier cannot score at another pilot's base")
	(flag_world.combatants[1] as CombatantState).position = neutral_zones[1] as Vector2
	_advance(flag_world, flag_coordinator, 1)
	context.expect_equal(flag_coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "solo capture the flag resolves only at the carrier's launch base")
	context.expect_equal(flag_coordinator.machine.last_heat_winner, 1, "the neutral flag carrier wins the capture heat")

	var team_flag_fixture := _objective_fixture(GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, 4, 8081)
	var team_flag_world := team_flag_fixture.world as AuthoritativeWorld
	var team_flag_coordinator := team_flag_fixture.coordinator as AuthoritativeMatchCoordinator
	var team_flag_objective := team_flag_coordinator.current_state_payload().objective as Dictionary
	(team_flag_world.combatants[1] as CombatantState).position = team_flag_objective.flag_position as Vector2
	_advance(team_flag_world, team_flag_coordinator, 1)
	team_flag_objective = team_flag_coordinator.current_state_payload().objective as Dictionary
	var team_zones := team_flag_objective.capture_zones as Dictionary
	(team_flag_world.combatants[1] as CombatantState).position = team_zones[2] as Vector2
	_advance(team_flag_world, team_flag_coordinator, 1)
	context.expect_equal(team_flag_coordinator.state(), MatchStateMachine.State.ACTIVE_HEAT, "team flag carrier cannot score at the opposing team's base")
	(team_flag_world.combatants[1] as CombatantState).position = team_zones[1] as Vector2
	_advance(team_flag_world, team_flag_coordinator, 1)
	context.expect_equal(team_flag_coordinator.state(), MatchStateMachine.State.HEAT_RESULT, "team flag capture resolves when the carrier reaches its own base")
	context.expect_equal(team_flag_coordinator.machine.last_heat_winner_team, 1, "team capture credits the carrier's full team")


static func _validate_objective_respawns(context: TestContext) -> void:
	for mode in [GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG]:
		var player_count := 4 if mode == GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG else 2
		var fixture := _objective_fixture(mode, player_count, 9000 + mode)
		var world := fixture.world as AuthoritativeWorld
		var coordinator := fixture.coordinator as AuthoritativeMatchCoordinator
		var victim := world.combatants[1] as CombatantState
		victim.health = 0.0
		victim.alive = false
		_advance(world, coordinator, 1)
		context.expect_equal(coordinator.state(), MatchStateMachine.State.ACTIVE_HEAT, "%s deaths do not resolve the objective heat" % GameModeRules.mode_name(mode))
		context.expect_false((coordinator.machine.players[1] as PlayerMatchState).alive, "%s victim waits in the authoritative respawn queue" % GameModeRules.mode_name(mode))
		var deadlines := coordinator.current_state_payload().respawn_deadlines as Dictionary
		var deadline := int(deadlines.get(1, -1))
		context.expect_equal(deadline - world.server_tick, roundi(GameModeRules.OBJECTIVE_RESPAWN_SECONDS * GameConstants.PHYSICS_TICKS_PER_SECOND), "%s respawn timer is exactly five seconds" % GameModeRules.mode_name(mode))
		_advance(world, coordinator, maxi(deadline - world.server_tick - 1, 0))
		context.expect_false(victim.alive, "%s victim remains eliminated before the five-second deadline" % GameModeRules.mode_name(mode))
		_advance(world, coordinator, 1)
		context.expect_true(victim.alive and (coordinator.machine.players[1] as PlayerMatchState).alive, "%s victim respawns when the five-second timer expires" % GameModeRules.mode_name(mode))


static func _validate_hill_round_rotation(context: TestContext) -> void:
	var config := _fast_config()
	config.game_mode = GameModeRules.Mode.KING_OF_THE_HILL
	config.rounds_to_win = 2
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in [1, 2]:
		lobby.admit(peer_id, "HillRound%d" % peer_id)
		world.add_peer(peer_id)
	_ready_all(lobby)
	lobby.request_start(1)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 9191)
	coordinator.start(0)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	var first_hill := (coordinator.current_state_payload().objective as Dictionary).position as Vector2
	coordinator.machine.finish_heat(1, world.server_tick)
	coordinator._capture_transitions()
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	coordinator.machine.finish_heat(1, world.server_tick)
	coordinator._capture_transitions()
	_advance_until_state(world, coordinator, MatchStateMachine.State.DRAFT)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	var second_hill := (coordinator.current_state_payload().objective as Dictionary).position as Vector2
	context.expect_true(first_hill.distance_to(second_hill) > GameModeRules.OBJECTIVE_ZONE_RADIUS, "King of the Hill moves its control point to a distinct location for the next round")


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


static func _validate_multi_team_spawns(context: TestContext) -> void:
	var config := _fast_config()
	config.max_players = 6
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in range(1, 7):
		lobby.admit(peer_id, "SpawnPilot%d" % peer_id)
		world.add_peer(peer_id)
	lobby.request_game_mode(1, GameModeRules.Mode.TEAM_DEATH_MATCH)
	lobby.request_team_count(1, 3)
	_ready_all(lobby)
	context.expect_true(lobby.request_start(1).ok, "three-team spawn fixture passes lobby validation")
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 8181)
	context.expect_true(coordinator.start(0), "three-team coordinator starts")
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	var occupied_positions: Dictionary = {}
	var represented_teams: Dictionary = {}
	for peer_id in coordinator.machine.participant_ids():
		var player := coordinator.machine.players[peer_id] as PlayerMatchState
		var combatant := world.combatants[peer_id] as CombatantState
		represented_teams[player.team_id] = true
		occupied_positions[combatant.position] = true
	context.expect_equal(represented_teams.size(), 3, "coordinator preserves all configured teams")
	context.expect_equal(occupied_positions.size(), 6, "multi-team heat preparation gives every participant a unique spawn anchor")


static func _validate_free_for_all_spawn_spread(context: TestContext) -> void:
	var coordinator := AuthoritativeMatchCoordinator.new(
		ServerLobby.new(_fast_config()),
		AuthoritativeWorld.new(),
		8383
	)
	var clustered_anchors: Array[Vector2] = [
		Vector2(100.0, 100.0),
		Vector2(120.0, 100.0),
		Vector2(140.0, 100.0),
		Vector2(900.0, 100.0),
		Vector2(100.0, 900.0),
		Vector2(900.0, 900.0),
	]
	var assignments := coordinator._spread_spawn_assignments([1, 2, 3, 4], clustered_anchors)
	var positions := assignments.values()
	var minimum_separation := INF
	for index in positions.size():
		for other_index in range(index + 1, positions.size()):
			minimum_separation = minf(
				minimum_separation,
				(positions[index] as Vector2).distance_to(positions[other_index] as Vector2)
			)
	context.expect_equal(assignments.size(), 4, "free-for-all spawn selection assigns every participant")
	context.expect_true(minimum_separation >= 800.0, "free-for-all spawn selection rejects a shuffled cluster when distant anchors remain")


static func _validate_team_npc_spawn_resets(context: TestContext) -> void:
	var config := _fast_config()
	config.max_players = 6
	config.rounds_to_win = 2
	var lobby := ServerLobby.new(config)
	lobby.admit(10, "NpcTeamHost")
	lobby.request_player_limit(10, 6)
	lobby.request_npcs_enabled(10, true)
	lobby.request_game_mode(10, GameModeRules.Mode.TEAM_DEATH_MATCH)
	lobby.request_team_count(10, 3)
	_ready_all(lobby)
	context.expect_true(lobby.request_start(10).ok, "team NPC reset fixture passes lobby validation")
	var world := AuthoritativeWorld.new()
	for player_value in lobby.players.values():
		var peer_id := (player_value as PlayerMatchState).peer_id
		var combatant := world.add_peer(peer_id)
		combatant.position = Vector2(900.0 + peer_id, 700.0)
		world.latest_inputs[peer_id] = PlayerInputFrame.new(
			int(world.acknowledged_inputs.get(peer_id, 0)),
			world.server_tick,
			Vector2.ONE.normalized(),
			0.0,
			true,
			true
		)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 8282)
	coordinator.start(0)
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	var npc_ids := lobby.npc_peer_ids()
	context.expect_equal(npc_ids.size(), 5, "team spawn reset fixture contains five server-owned NPCs")
	for npc_id in npc_ids:
		var npc := world.combatants[npc_id] as CombatantState
		var expected_spawn := coordinator._spawn_assignments_cache[npc_id] as Vector2
		context.expect_equal(npc.position, expected_spawn, "NPC %d starts the team game at its assigned spawn" % npc_id)
		context.expect_true((world.latest_inputs[npc_id] as PlayerInputFrame).movement.is_zero_approx(), "NPC %d starts the team game with neutral movement" % npc_id)
	var moved_npc_id := npc_ids[0]
	(world.combatants[moved_npc_id] as CombatantState).position = Vector2(1111.0, 777.0)
	world.latest_inputs[moved_npc_id] = PlayerInputFrame.new(
		int(world.acknowledged_inputs.get(moved_npc_id, 0)),
		world.server_tick,
		Vector2.RIGHT,
		0.0,
		true
	)
	coordinator.machine.finish_team_heat(1, world.server_tick)
	coordinator._capture_transitions()
	_advance_until_state(world, coordinator, MatchStateMachine.State.ACTIVE_HEAT)
	var moved_npc := world.combatants[moved_npc_id] as CombatantState
	context.expect_equal(moved_npc.position, coordinator._spawn_assignments_cache[moved_npc_id], "team NPC returns to its newly assigned spawn for the next heat")
	context.expect_true((world.latest_inputs[moved_npc_id] as PlayerInputFrame).movement.is_zero_approx(), "team NPC cannot carry movement input into the next heat")


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


static func _validate_incremental_draft(context: TestContext) -> void:
	var lobby := ServerLobby.new()
	var world := AuthoritativeWorld.new()
	for peer in range(1, 33):
		lobby.admit(peer, "Pilot%d" % peer)
		world.add_peer(peer)
	var match_owner := AuthoritativeMatchCoordinator.new(lobby, world, 84)
	match_owner.incremental_drafts = true
	match_owner.start(0)
	context.expect_empty(match_owner.drain_private_offers(), "preparation publishes no partial offers")
	for tick in range(1, 65):
		world.server_tick = tick
		match_owner.step(1.0 / 60.0)
		if not match_owner.draft.is_preparing(): break
	var offers := match_owner.drain_private_offers()
	context.expect_equal(offers.size(), 32, "prepared offers publish together")
	context.expect_true(match_owner.machine.state_deadline_tick > lobby.config.duration_to_ticks(lobby.config.draft_duration_seconds), "decision deadline excludes preparation")
