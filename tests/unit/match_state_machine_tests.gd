class_name MatchStateMachineTests
extends RefCounted


static func run(context: TestContext) -> void:
	_validate_entry_and_timers(context)
	_validate_multiplayer_round_beyond_three_heats(context)
	_validate_tied_heat_replay(context)
	_validate_match_victory_and_lobby_reset(context)
	_validate_forfeit_and_late_spectator(context)
	_validate_empty_session_return(context)
	_validate_team_death_match_scoring(context)
	_validate_team_forfeit(context)


static func _validate_entry_and_timers(context: TestContext) -> void:
	var config := MatchConfig.new()
	var machine := MatchStateMachine.new(config, CardCatalog.create_default())
	machine.add_player(1, "Solo", 1)
	context.expect_false(machine.start_match(0), "match cannot start with one participant")
	machine.add_player(2, "Second", 2)
	context.expect_true(machine.start_match(0), "match starts with two participants")
	context.expect_equal(machine.state, MatchStateMachine.State.DRAFT, "match begins in draft")
	context.expect_equal(machine.state_deadline_tick, 1800, "draft deadline uses shared 30-second duration")
	context.expect_false(machine.is_draft_timed_out(1799), "draft is live before deadline")
	context.expect_true(machine.is_draft_timed_out(1800), "draft times out at server deadline")
	context.expect_false(machine.finish_heat(1, 0), "heat cannot resolve during draft")
	context.expect_true(machine.draft_completed(10), "completed draft enters countdown")
	context.expect_equal(machine.state, MatchStateMachine.State.COUNTDOWN, "draft transitions to countdown")
	context.expect_equal(machine.state_deadline_tick, 190, "countdown deadline uses shared three-second duration")
	context.expect_equal(machine.alive_participant_ids(), [1, 2], "participants spawn at countdown entry")
	machine.advance_time(189)
	context.expect_equal(machine.state, MatchStateMachine.State.COUNTDOWN, "countdown remains locked before deadline")
	machine.advance_time(190)
	context.expect_equal(machine.state, MatchStateMachine.State.ACTIVE_HEAT, "countdown unlocks active heat on deadline")
	context.expect_equal(machine.state_deadline_tick, -1, "active heat has no fixed end deadline")


static func _validate_multiplayer_round_beyond_three_heats(context: TestContext) -> void:
	var machine := _create_started_machine(4, 2)
	var active_tick := _complete_draft_and_enter_heat(machine, 0)
	var first_winners: Array[int] = [1, 2, 3, 4]
	for winner in first_winners:
		context.expect_true(machine.finish_heat(winner, active_tick), "player %d can win its heat" % winner)
		context.expect_equal(machine.scores.get_score(winner).heat_wins, 1, "player %d holds one heat win" % winner)
		active_tick = _advance_heat_result_to_active(machine)
	context.expect_equal(machine.heat_number, 5, "round continues to a fifth heat after four different winners")
	context.expect_true(machine.finish_heat(4, active_tick), "player 4 wins a second heat")
	var heat_result_deadline := machine.state_deadline_tick
	machine.advance_time(heat_result_deadline)
	context.expect_equal(machine.state, MatchStateMachine.State.ROUND_RESULT, "second heat win resolves the round")
	context.expect_equal(machine.state_deadline_tick - heat_result_deadline, 120, "round result intermission uses the shared two-second duration")
	context.expect_equal(machine.last_round_winner, 4, "round winner is the first player with two heat wins")
	context.expect_equal(machine.scores.get_score(4).round_wins, 1, "round winner gains one round win")
	for peer_id in machine.participant_ids():
		context.expect_equal(machine.scores.get_score(peer_id).heat_wins, 0, "all heat wins clear after round resolution")
	var round_result_deadline := machine.state_deadline_tick
	machine.advance_time(round_result_deadline)
	context.expect_equal(machine.state, MatchStateMachine.State.DRAFT, "non-final round returns to draft")
	context.expect_equal(machine.round_number, 2, "next draft belongs to round two")
	context.expect_equal(machine.heat_number, 0, "next round has not started a heat before draft completion")


static func _validate_tied_heat_replay(context: TestContext) -> void:
	var machine := _create_started_machine(2, 2)
	var active_tick := _complete_draft_and_enter_heat(machine, 0)
	context.expect_true(machine.eliminate_players([1, 2], active_tick), "simultaneous elimination batch resolves")
	context.expect_equal(machine.state, MatchStateMachine.State.HEAT_RESULT, "zero survivors enters heat result")
	context.expect_true(machine.tied_heat, "zero survivors marks a tied heat")
	context.expect_equal(machine.last_heat_winner, 0, "tied heat has no winner")
	context.expect_equal(machine.scores.get_score(1).heat_wins, 0, "tie awards no heat win to player 1")
	context.expect_equal(machine.scores.get_score(2).heat_wins, 0, "tie awards no heat win to player 2")
	machine.advance_time(machine.state_deadline_tick)
	context.expect_equal(machine.state, MatchStateMachine.State.COUNTDOWN, "tied heat replays after result")
	context.expect_equal(machine.heat_number, 2, "replayed heat receives the next heat number")
	context.expect_equal(machine.alive_participant_ids(), [1, 2], "all participants respawn for replay")
	machine.advance_time(machine.state_deadline_tick)
	context.expect_equal(machine.state, MatchStateMachine.State.ACTIVE_HEAT, "replayed heat becomes active")


static func _validate_match_victory_and_lobby_reset(context: TestContext) -> void:
	var machine := _create_started_machine(2, 1)
	(machine.players[1] as PlayerMatchState).card_stacks[&"heavy_rounds"] = 1
	var active_tick := _complete_draft_and_enter_heat(machine, 0)
	context.expect_true(machine.finish_heat(1, active_tick), "match winner earns first heat")
	active_tick = _advance_heat_result_to_active(machine)
	context.expect_true(machine.finish_heat(1, active_tick), "match winner earns second heat")
	var final_heat_result_deadline := machine.state_deadline_tick
	machine.advance_time(final_heat_result_deadline)
	context.expect_equal(machine.state, MatchStateMachine.State.MATCH_RESULT, "final heat result enters match result without a round-result cooldown")
	context.expect_equal(machine.state_entered_tick, final_heat_result_deadline, "victory begins on the final heat-result deadline")
	context.expect_equal(machine.last_round_winner, 1, "decisive round winner remains available on the immediate victory payload")
	context.expect_equal(machine.match_winner, 1, "match winner is recorded")
	context.expect_equal(machine.scores.get_score(1).round_wins, 1, "winning score remains visible during results")
	context.expect_equal((machine.players[1] as PlayerMatchState).card_stack(&"heavy_rounds"), 1, "build remains visible during match results")
	context.expect_equal(machine.state_deadline_tick, -1, "match result remains open without an automatic deadline")
	machine.advance_time(machine.state_entered_tick + 60000)
	context.expect_equal(machine.state, MatchStateMachine.State.MATCH_RESULT, "elapsed time cannot close the final results")
	context.expect_true(machine.return_to_lobby(machine.state_entered_tick + 60001), "an explicit results action returns the match to lobby")
	context.expect_equal(machine.state, MatchStateMachine.State.LOBBY, "explicit results action enters the lobby")
	context.expect_equal(machine.round_number, 0, "lobby reset clears round number")
	context.expect_equal(machine.scores.get_score(1).round_wins, 0, "lobby reset clears round score")
	context.expect_empty((machine.players[1] as PlayerMatchState).card_stacks, "lobby reset clears card build")


static func _validate_forfeit_and_late_spectator(context: TestContext) -> void:
	var machine := _create_started_machine(2, 3)
	_complete_draft_and_enter_heat(machine, 0)
	var late_player := machine.add_player(3, "Late", 3)
	context.expect_false(late_player.participant, "mid-match join becomes a spectator")
	context.expect_true(late_player.spectator, "late join is placed in spectator state")
	context.expect_true(machine.disconnect_player(2, 200), "active participant disconnect is accepted")
	context.expect_equal(machine.state, MatchStateMachine.State.MATCH_RESULT, "sole remaining participant wins by forfeit")
	context.expect_equal(machine.match_winner, 1, "forfeit records the connected participant as winner")
	context.expect_equal(machine.scores.get_score(1).round_wins, 3, "forfeit score reaches configured match target")
	context.expect_true(machine.return_to_lobby(201), "forfeit results accept the explicit lobby return")
	context.expect_equal(machine.state, MatchStateMachine.State.LOBBY, "forfeit result returns to lobby on request")
	context.expect_true((machine.players[3] as PlayerMatchState).participant, "late spectator is promoted in the next lobby")
	context.expect_equal(machine.participant_ids(), [1, 3], "next lobby contains all connected clients")


static func _validate_empty_session_return(context: TestContext) -> void:
	var machine := _create_started_machine(2, 3)
	context.expect_true(machine.disconnect_player(1, 10), "first participant disconnect starts forfeit result")
	context.expect_true(machine.disconnect_player(2, 11), "last participant disconnect is accepted")
	context.expect_equal(machine.state, MatchStateMachine.State.LOBBY, "zero connected participants returns immediately to lobby")
	context.expect_empty(machine.players, "disconnected participants are removed from empty lobby")


static func _validate_team_death_match_scoring(context: TestContext) -> void:
	var config := MatchConfig.new()
	config.game_mode = GameModeRules.Mode.TEAM_DEATH_MATCH
	config.rounds_to_win = 1
	var machine := MatchStateMachine.new(config, CardCatalog.create_default())
	for peer_id in range(1, 5):
		var player := machine.add_player(peer_id, "TeamPilot%d" % peer_id, peer_id)
		player.team_id = 1 if peer_id % 2 == 1 else 2
	context.expect_true(machine.start_match(0), "team death match starts with two populated teams")
	var active_tick := _complete_draft_and_enter_heat(machine, 0)
	context.expect_true(machine.eliminate_players([2, 4], active_tick), "eliminating the final enemy resolves a team heat")
	context.expect_equal(machine.last_heat_winner_team, 1, "the surviving team owns the heat result")
	context.expect_equal((machine.score_snapshot()[1] as Dictionary).heat_wins, 1, "team heat score is published for its first member")
	context.expect_equal((machine.score_snapshot()[3] as Dictionary).heat_wins, 1, "team heat score is published for every teammate")
	active_tick = _advance_heat_result_to_active(machine)
	machine.eliminate_players([2, 4], active_tick)
	machine.advance_time(machine.state_deadline_tick)
	context.expect_equal(machine.state, MatchStateMachine.State.MATCH_RESULT, "two team heat wins complete a one-round team match")
	context.expect_equal(machine.match_winner_team, 1, "team match result preserves the winning team")
	context.expect_equal((machine.score_snapshot()[1] as Dictionary).round_wins, 1, "winning team members share the published round score")
	context.expect_equal((machine.score_snapshot()[3] as Dictionary).round_wins, 1, "all winning teammates share the published final round score")


static func _validate_team_forfeit(context: TestContext) -> void:
	var config := MatchConfig.new()
	config.game_mode = GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG
	config.rounds_to_win = 3
	var machine := MatchStateMachine.new(config, CardCatalog.create_default())
	for peer_id in range(1, 5):
		var player := machine.add_player(peer_id, "FlagPilot%d" % peer_id, peer_id)
		player.team_id = 1 if peer_id % 2 == 1 else 2
	machine.start_match(0)
	_complete_draft_and_enter_heat(machine, 0)
	context.expect_true(machine.disconnect_player(2, 200), "first opposing-team disconnect is accepted")
	context.expect_equal(machine.state, MatchStateMachine.State.ACTIVE_HEAT, "team match continues while both teams remain")
	context.expect_true(machine.disconnect_player(4, 201), "final opposing-team disconnect is accepted")
	context.expect_equal(machine.state, MatchStateMachine.State.MATCH_RESULT, "one remaining team wins the match by forfeit")
	context.expect_equal(machine.match_winner_team, 1, "team forfeit records the remaining team")
	context.expect_equal((machine.score_snapshot()[1] as Dictionary).round_wins, 3, "team forfeit publishes the round target for the first teammate")
	context.expect_equal((machine.score_snapshot()[3] as Dictionary).round_wins, 3, "team forfeit publishes the round target for every winning teammate")


static func _create_started_machine(player_count: int, rounds_to_win: int) -> MatchStateMachine:
	var config := MatchConfig.new()
	config.rounds_to_win = rounds_to_win
	var machine := MatchStateMachine.new(config, CardCatalog.create_default())
	for peer_id in range(1, player_count + 1):
		machine.add_player(peer_id, "Player%d" % peer_id, peer_id)
	machine.start_match(0)
	return machine


static func _complete_draft_and_enter_heat(machine: MatchStateMachine, draft_completed_tick: int) -> int:
	machine.draft_completed(draft_completed_tick)
	var active_tick := machine.state_deadline_tick
	machine.advance_time(active_tick)
	return active_tick


static func _advance_heat_result_to_active(machine: MatchStateMachine) -> int:
	machine.advance_time(machine.state_deadline_tick)
	var active_tick := machine.state_deadline_tick
	machine.advance_time(active_tick)
	return active_tick
