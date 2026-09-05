extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
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
	context.expect_equal(client.draft_controller.draft_panel, client.draft_controller.draft_panel, "legacy draft accessor exposes the owned surface")
	context.expect_equal(client.results_panel, client.standings_controller.results_panel, "legacy results accessor exposes the owned surface")
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
	client._results_rows_dirty = true
	client._update_match_presentation()
	var first_row: Node = client.results_standings_container.get_child(0)
	client.results_rematch_button.grab_focus()
	for unused in 5:
		client._update_match_presentation()
	context.expect_equal(client.get_viewport().gui_get_focus_owner(), client.results_rematch_button, "unchanged results frames preserve keyboard focus on rematch")
	context.expect_equal(client.results_standings_container.get_child(0), first_row, "unchanged results frames retain existing row nodes")
	client._on_results_rematch_pressed()
	context.expect_true(client.standings_controller._rematch_requested, "rematch pending state lives with standings controller")
	client._on_match_event(&"REQUEST_REJECTED", 4, {"message": "Only the current leader may continue"})
	client._update_results_screen()
	context.expect_false(client.standings_controller._rematch_requested, "result action rejection clears controller pending state")
	context.expect_true(client.results_action_note.text.contains("Only the current leader"), "result rejection remains visible in the results surface")
	client.latest_match_payload.state_name = "ACTIVE_HEAT"
	client.network_world.set_network_active(true)
	client._scoreboard_rows_dirty = true
	client._update_scoreboard()
	var scoreboard_row: Node = client.scoreboard_rows_container.get_child(0)
	client._update_scoreboard()
	context.expect_equal(client.scoreboard_rows_container.get_child(0), scoreboard_row, "unchanged scoreboard refresh retains row nodes")
	client._show_connection_screen("Review finished")
	context.expect_equal(client.draft_controller.active_offer_deadline, -1, "session navigation clears owned draft deadline")
	context.expect_false(client.draft_controller.draft_panel.visible or client.results_panel.visible or client.scoreboard_panel.visible, "session navigation closes all owned match screens")
	client.free()


static func _heading_count(canvas: Node, text: String) -> int:
	var count := 0
	for label in canvas.find_children("*", "Label", true, false):
		if (label as Label).text == text:
			count += 1
	return count
