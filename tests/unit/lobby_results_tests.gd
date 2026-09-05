extends RefCounted

const Presets = preload("res://src/shared/lobby/match_presets.gd")
const Connection = preload("res://src/client/ui/connection_controller.gd")
const Contributions = preload("res://src/client/ui/objective_contribution_text.gd")


static func run(context: TestContext, parent: Node) -> void:
	for preset in Presets.PRESETS:
		var lobby := ServerLobby.new()
		lobby.admit(2, "Host")
		context.expect_true(Presets.apply(lobby, 2, String(preset.id)).ok, "%s preset applies for a solo host" % preset.id)
		context.expect_equal(lobby.player_limit, int(preset.players), "preset sets intended seat count")
		context.expect_equal(lobby.participant_count(), int(preset.players), "preset fills unused seats with NPCs")
		context.expect_equal(lobby.config.game_mode, int(preset.mode), "preset sets intended mode")
		context.expect_false(lobby.config.random_powerups_permanent, "quick setups do not silently enable permanent pickups")
		context.expect_true(lobby.team_setup_error().is_empty(), "preset supplies valid teams")
		context.expect_true(lobby.request_rounds_to_win(2, 5).ok, "preset leaves advanced rules editable")
	var lobby := ServerLobby.new()
	for peer_id in [2, 3, 4]:
		lobby.admit(peer_id, "Pilot%d" % peer_id)
	var before := lobby.serialize()
	context.expect_false(Presets.apply(lobby, 3, "chaos").ok, "guest cannot apply a host preset")
	context.expect_false(Presets.apply(lobby, 2, "duel").ok, "preset never ejects humans to fit smaller lobby")
	context.expect_false(Presets.apply(lobby, 2, "unknown").ok, "unknown preset is rejected")
	context.expect_equal(lobby.serialize(), before, "rejected presets leave all lobby settings unchanged")
	context.expect_true(Presets.apply(lobby, 2, "team_objective").ok, "team preset applies before manual assignment fixture")
	for peer_id in lobby.players:
		lobby.request_team_assignment(2, int(peer_id), 1)
	context.expect_false(lobby.team_setup_error().is_empty(), "manual one-team fixture is invalid")
	context.expect_true(Presets.apply(lobby, 2, "team_objective").ok and lobby.team_setup_error().is_empty(), "reapplying team preset restores automatic balanced teams")
	lobby.request_game_mode(2, GameModeRules.Mode.TEAM_DEATH_MATCH)
	lobby.request_team_count(2, 8)
	lobby.request_npcs_enabled(2, true)
	context.expect_true(Presets.apply(lobby, 2, "skirmish").ok, "smaller FFA preset clears previous eight-team sizing constraint")
	context.expect_equal(lobby.player_limit, 4, "eight-team lobby shrinks to four-seat preset without partial failure")
	var small_config := MatchConfig.new()
	small_config.max_players = 4
	var small_lobby := ServerLobby.new(small_config)
	small_lobby.admit(2, "SmallHost")
	before = small_lobby.serialize()
	context.expect_false(Presets.apply(small_lobby, 2, "chaos").ok, "preset cannot exceed server transport capacity")
	context.expect_equal(small_lobby.serialize(), before, "capacity rejection leaves lobby unchanged")
	var roster := {"players": [{"peer_id": 2, "display_name": "Ready", "ready": true}, {"peer_id": 3, "display_name": "NPC", "is_npc": true, "ready": true}, {"peer_id": 4, "display_name": "Waiting", "ready": false}]}
	context.expect_equal(Connection.ordered_roster(roster)[0].peer_id, 4, "unready humans appear above ready players and NPCs")
	context.expect_true(Connection.readiness_summary(roster).contains("Waiting for: Waiting"), "readiness summary names the human blocking launch")
	context.expect_true(Connection.readiness_summary(roster).contains("scroll roster"), "full roster scrolling is explained")
	var payload := {"game_mode": GameModeRules.Mode.KING_OF_THE_HILL, "objective_contributions": {"2": {"hill_control_seconds": 12.5, "hill_contest_seconds": 4.0, "flag_captures": 9}}}
	context.expect_equal(Contributions.summary(payload, 2), "HILL  12.5s controlled · 4.0s contested", "hill contribution text separates control and contest without irrelevant flag totals")
	payload = {"game_mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "objective_contributions": {2: {"flag_captures": 2, "carrier_stops": 3, "flag_carry_seconds": 15.0, "flag_pickups": 4}}}
	context.expect_true(Contributions.summary(payload, 2).contains("2 captures · 3 carrier stops · 15.0s carrying · 4 pickups"), "flag contribution text includes non-kill objective work")
	context.expect_equal(Contributions.summary({"game_mode": GameModeRules.Mode.DEATH_MATCH}, 2), "", "death match omits irrelevant objective statistics")
	_validate_rematch(context)
	var client = (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
	parent.add_child(client)
	context.expect_true(client.connection_controller.lobby_roster_scroll.follow_focus, "keyboard traversal scrolls the roster into view")
	context.expect_equal(client.connection_controller.lobby_roster_scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_ALWAYS, "roster makes scrolling visible")
	context.expect_true(client.connection_controller.lobby_options_popup.is_ancestor_of(client.connection_controller.rounds_control), "host round configuration lives in the separate setup panel")
	context.expect_true(client.standings_controller.results_action_note.text.contains("resets cards, scores and objectives"), "fresh rematch visibly explains resets")
	client.network_world.local_peer_id = 2
	client.network_world.input_sequence = 50
	client.network_world.match_payload = {"state_name": "MATCH_RESULT"}
	client._on_match_event(&"MATCH_START_ACCEPTED", 100, {"fresh_rematch": true})
	context.expect_true(client.network_world.match_payload.is_empty(), "fresh rematch clears previous client match presentation")
	context.expect_equal(client.network_world.local_peer_id, 2, "fresh rematch presentation reset keeps connected identity")
	context.expect_equal(client.network_world.input_sequence, 50, "fresh rematch presentation reset preserves network input sequence")
	client.free()


static func _validate_rematch(context: TestContext) -> void:
	var bridge := NetworkBridge.new()
	bridge.lobby = ServerLobby.new()
	bridge.world = AuthoritativeWorld.new()
	for peer_id in [2, 3]:
		bridge.lobby.admit(peer_id, "Pilot%d" % peer_id)
		bridge.lobby.request_ready(peer_id, true)
		bridge.world.add_peer(peer_id)
	bridge.lobby.request_start(2)
	bridge.match_coordinator = AuthoritativeMatchCoordinator.new(bridge.lobby, bridge.world, 913)
	bridge.match_coordinator.start(0)
	var previous := bridge.match_coordinator
	context.expect_false(bridge._prepare_fresh_rematch(2).ok, "host cannot restart an active draft as a rematch")
	previous.machine.state = MatchStateMachine.State.MATCH_RESULT
	previous.machine.players[2].card_stacks = {&"twin_shot": 3}
	previous.machine.players[2].score.kills = 7
	previous.observations.add_contribution(2, "flag_captures", 3)
	context.expect_false(bridge._prepare_fresh_rematch(3).ok, "guest cannot start fresh rematch")
	context.expect_equal(bridge.match_coordinator, previous, "unauthorized rematch preserves finished coordinator")
	var rules := bridge.lobby.config.duplicate_config()
	context.expect_true(bridge._prepare_fresh_rematch(2).ok, "host can start fresh rematch from results")
	context.expect_true(bridge.match_coordinator != previous, "fresh rematch creates new coordinator and contribution counters")
	context.expect_true(bridge.match_coordinator.observations.contributions.is_empty(), "fresh rematch clears objective contribution totals")
	context.expect_equal(bridge.match_coordinator.machine.state, MatchStateMachine.State.DRAFT, "fresh rematch returns directly to first draft")
	context.expect_true(bridge.match_coordinator.machine.players[2].card_stacks.is_empty(), "fresh rematch clears build")
	context.expect_equal(bridge.match_coordinator.machine.players[2].score.kills, 0, "fresh rematch clears scores")
	context.expect_equal(bridge.match_coordinator.machine.round_number, 1, "fresh rematch starts round one")
	context.expect_equal(bridge.lobby.config.game_mode, rules.game_mode, "fresh rematch preserves mode")
	context.expect_equal(bridge.lobby.config.rounds_to_win, rules.rounds_to_win, "fresh rematch preserves rounds to win")
	context.expect_equal(bridge.match_coordinator.machine.players[2].display_name, "Pilot2", "fresh rematch preserves pilot identity")
	bridge.free()
