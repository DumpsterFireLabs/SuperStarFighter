extends RefCounted

class RecordingBridge extends NetworkBridge:
	var rematches: int = 0
	func send_rematch() -> void:
		rematches += 1

class MemoryPreferences extends "res://src/client/presentation/accessibility_preferences.gd":
	func save_settings() -> Error:
		return OK


static func run(context: TestContext, parent: Node) -> void:
	preload("res://tests/unit/connection_screen_tests.gd").run(context, parent)
	_independent_controllers(context, parent)
	preload("res://tests/unit/connection_preferences_tests.gd").run(context)
	var client = (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
	parent.add_child(client)
	client._dismiss_splash(true)
	context.expect_equal(_heading_count(client.connection_controller.connection_canvas, "SCOREBOARD"), 1, "five draft cards construct only one scoreboard surface")
	context.expect_equal(_heading_count(client.connection_controller.connection_canvas, "✦  MATCH COMPLETE  ✦"), 1, "five draft cards construct only one results overlay")
	var canvas_children: int = client.connection_controller.connection_canvas.get_child_count()
	client.draft_controller.create_ui()
	client.standings_controller.create_ui()
	context.expect_equal(client.connection_controller.connection_canvas.get_child_count(), canvas_children, "controller construction is idempotent")
	context.expect_equal(client.draft_controller.draft_buttons.size(), 5, "draft controller owns exactly five offer controls")
	client.bridge.session.local_peer_id = 2
	client.bridge.session.latest_lobby_state = {"leader_id": 2, "players": [{"peer_id": 2, "display_name": "Host"}, {"peer_id": 3, "display_name": "Guest"}]}
	client.latest_match_payload = {"state_name": "DRAFT", "round_number": 1, "builds": {2: {}}}
	client.draft_controller._show_draft_offer({"offer_token": "owned-offer", "deadline_tick": 1800, "card_ids": [&"heavy_rounds", &"quick_loader"]})
	client.draft_controller._select_draft_card(0)
	context.expect_equal(client.draft_controller.pending_draft_index, 0, "draft selection state lives with its controller")
	client.draft_controller._confirm_draft_card()
	context.expect_true(client.draft_controller.draft_buttons[0].disabled, "confirmed selection remains locked pending authority")
	client._on_match_event(&"REQUEST_REJECTED", 2, {"message": "Try another card"})
	context.expect_false(client.draft_controller.draft_buttons[0].disabled, "server rejection restores actionable draft controls")
	context.expect_equal(client.draft_controller.active_offer_token, "owned-offer", "rejection preserves the live server offer token")
	client.draft_controller._select_draft_card(1)
	client._on_match_event(&"DRAFT_RESOLVED", 3, {"builds": {2: {&"heavy_rounds": 1}}})
	context.expect_equal(client.draft_controller.active_offer_token, "", "draft resolution clears controller offer state")
	context.expect_equal(client.draft_controller.pending_draft_index, -1, "draft resolution clears pending confirmation")
	context.expect_false(client.draft_controller.draft_panel.visible, "draft resolution closes owned surface")
	client.latest_match_payload = {"state_name": "MATCH_RESULT", "match_winner": 2, "participant_peer_ids": [2, 3], "scores": {2: {"round_wins": 3, "kills": 4}, 3: {"round_wins": 1, "kills": 2}}, "builds": {2: {&"heavy_rounds": 1}}, "can_extend_match": true}
	client.standings_controller._results_rows_dirty = true
	client._update_match_presentation()
	var first_row: Node = client.standings_controller.results_standings_container.get_child(0)
	client.standings_controller.results_rematch_button.grab_focus()
	for unused in 5:
		client._update_match_presentation()
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.standings_controller.results_rematch_button, "unchanged results frames preserve keyboard focus on rematch")
	context.expect_equal(client.standings_controller.results_standings_container.get_child(0), first_row, "unchanged results frames retain existing row nodes")
	client.standings_controller._on_results_rematch_pressed()
	context.expect_true(client.standings_controller._rematch_requested, "rematch pending state lives with standings controller")
	client._on_match_event(&"REQUEST_REJECTED", 4, {"message": "Only the current leader may continue"})
	client.standings_controller._update_results_screen()
	context.expect_false(client.standings_controller._rematch_requested, "result action rejection clears controller pending state")
	context.expect_true(client.standings_controller.results_action_note.text.contains("Only the current leader"), "result rejection remains visible in the results surface")
	client.latest_match_payload.state_name = "ACTIVE_HEAT"
	client.network_world.set_network_active(true)
	client.standings_controller._scoreboard_rows_dirty = true
	client.standings_controller._update_scoreboard()
	var scoreboard_row: Node = client.standings_controller.scoreboard_rows_container.get_child(0)
	client.standings_controller._update_scoreboard()
	context.expect_equal(client.standings_controller.scoreboard_rows_container.get_child(0), scoreboard_row, "unchanged scoreboard refresh retains row nodes")
	client._show_connection_screen("Review finished")
	context.expect_equal(client.draft_controller.active_offer_deadline, -1, "session navigation clears owned draft deadline")
	context.expect_false(client.draft_controller.draft_panel.visible or client.standings_controller.results_panel.visible or client.standings_controller.scoreboard_panel.visible, "session navigation closes all owned match screens")
	client.free()


static func _independent_controllers(context: TestContext, parent: Node) -> void:
	var fixture := Node.new()
	parent.add_child(fixture)
	var canvas := CanvasLayer.new()
	fixture.add_child(canvas)
	var audio := AudioDirector.new()
	fixture.add_child(audio)
	var profiles := InputProfileManager.new()
	fixture.add_child(profiles)
	var theme := preload("res://src/client/ui/design_tokens.gd").create_interface_theme()
	var settings := preload("res://src/client/ui/settings_controller.gd").new()
	fixture.add_child(settings)
	settings.accessibility_preferences = MemoryPreferences.new()
	settings.configure(audio, profiles, theme)
	settings.register_interface_scope(canvas)
	settings._create_settings_overlay(canvas)
	var events := {"closed": 0, "accessibility": 0, "inspected": 0, "inspection_closed": 0, "observations": 0}
	settings.close_requested.connect(func() -> void: events.closed += 1)
	settings.accessibility_changed.connect(func() -> void: events.accessibility += 1)
	settings.settings_back_button.pressed.emit()
	context.expect_equal(events.closed, 1, "standalone settings emits navigation intent without a client root")
	settings._change_accessibility_setting("high_contrast", true)
	settings.apply_accessible_theme()
	context.expect_equal(events.accessibility, 1, "standalone settings publishes changed accessibility preferences")
	var label := Label.new()
	label.add_theme_color_override("font_color", Color("224466"))
	canvas.add_child(label)
	settings._refresh_accessible_nodes()
	context.expect_true(label.has_meta("accessible_original_font_color"), "registered settings scope applies contrast to dynamically added UI")
	var outside := Label.new()
	fixture.add_child(outside)
	settings._refresh_accessible_nodes()
	context.expect_false(outside.has_meta("accessible_original_font_color"), "settings does not restyle unrelated interface trees")
	settings.accessibility_preferences.set_values({"high_contrast": false})
	settings.apply_accessible_theme()
	context.expect_equal(label.get_theme_color("font_color"), Color("224466"), "registered scope restores semantic colour when contrast is disabled")
	var transient := Control.new()
	fixture.add_child(transient)
	settings.register_interface_scope(transient)
	transient.free()
	settings.apply_accessible_theme()
	var bridge := RecordingBridge.new()
	fixture.add_child(bridge)
	bridge.session.local_peer_id = 2
	bridge.session.latest_lobby_state = {"leader_id": 2, "players": [{"peer_id": 2, "display_name": "Host", "team_id": 1}]}
	var payload := {"state_name": "MATCH_RESULT", "match_winner": 2, "participant_peer_ids": [2], "teams": {"2": 2}, "scores": {2: {"round_wins": 3}}, "builds": {2: {&"heavy_rounds": 1}}}
	var standings := preload("res://src/client/ui/standings_screen_controller.gd").new()
	fixture.add_child(standings)
	standings.configure(bridge, audio, CardCatalog.create_default(), theme, canvas, func() -> Dictionary:
		events.observations += 1
		return payload.duplicate(true)
	, func() -> bool: return true)
	standings.inspection_requested.connect(func(_button: CardHoverButton) -> void: events.inspected += 1)
	standings.inspection_close_requested.connect(func() -> void: events.inspection_closed += 1)
	standings.create_ui()
	standings._update_results_screen()
	context.expect_equal(events.observations, 1, "standings takes one match observation for the whole refresh")
	standings._update_results_screen()
	context.expect_equal(events.observations, 1, "unchanged standings frames do not copy match state again")
	context.expect_equal(standings._player_team(2), 2, "standings resolves string-keyed match teams before lobby teams")
	bridge.session.latest_lobby_state = {"leader_id": 3, "players": []}
	payload.scores[2].round_wins = 9
	context.expect_equal(standings._player_name(2), "Host", "standings rows share a stable roster observation")
	context.expect_equal(standings._result_score(2).round_wins, 3, "standings holds a detached nested match observation")
	var flow := standings.results_standings_container.find_child("FinalBuildCards", true, false)
	(flow.get_child(0) as CardHoverButton).request_inspection()
	context.expect_equal(events.inspected, 1, "standalone standings emits card inspection intent")
	standings.invalidate_context()
	standings._update_results_screen()
	context.expect_true(standings.results_rematch_button.disabled, "standings refresh revokes actions after leadership changes")
	standings._on_results_rematch_pressed()
	context.expect_equal(bridge.rematches, 0, "guest cannot submit a disabled result action")
	bridge.session.latest_lobby_state = {"leader_id": 2, "players": []}
	standings.invalidate_context()
	standings._update_results_screen()
	standings._on_results_rematch_pressed()
	standings._on_results_rematch_pressed()
	context.expect_equal(bridge.rematches, 1, "leader rematch is submitted once while awaiting authority")
	standings.reset_session()
	context.expect_equal(events.inspection_closed, 1, "session reset requests inspection closure")
	fixture.free()


static func _heading_count(canvas: Node, text: String) -> int:
	var count := 0
	for label in canvas.find_children("*", "Label", true, false):
		if (label as Label).text == text:
			count += 1
	return count
