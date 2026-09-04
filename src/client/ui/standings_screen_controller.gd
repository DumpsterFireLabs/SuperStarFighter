extends Node

## Owns live standings and final results, shared build rows, and result actions.

const CardHoverButtonScript = preload("res://src/client/ui/card_hover_button.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const CardDetailsText = preload("res://src/client/ui/card_details_text.gd")
const StandingsModelScript = preload("res://src/client/presentation/standings_model.gd")
const RESULTS_ACTION_EXPLANATION: String = "Fresh rematch resets cards, scores and objectives; keeps rules, teams and pilots.\nFive more rounds keeps all builds and scores. Lobby lets everyone change rules and ready up."

var client: Node
var bridge: NetworkBridge:
	get: return client.bridge
var audio_director: AudioDirector:
	get: return client.audio_director
var card_catalog: CardCatalog:
	get: return client.card_catalog
var latest_match_payload: Dictionary:
	get: return client.latest_match_payload
var interface_theme: Theme:
	get: return client.interface_theme


var scoreboard_panel: PanelContainer
var scoreboard_label: Label
var scoreboard_context_label: Label
var scoreboard_media_label: Label
var scoreboard_hill_heading: Label
var scoreboard_rows_container: VBoxContainer
var scoreboard_hint_label: Label
var scoreboard_open: bool = false
var _scoreboard_rows_dirty: bool = true
var results_panel: PanelContainer
var results_label: Label
var results_winner_label: Label
var results_standings_container: VBoxContainer
var results_rematch_button: Button
var results_action_note: Label
var _rematch_requested: bool = false
var results_extend_button: Button
var results_return_button: Button
var _results_rows_dirty: bool = true
var _extend_match_requested: bool = false
var _return_to_lobby_requested: bool = false
var win_overlay: Control


func initialize(client_root: Node) -> void:
	client = client_root


func create_ui() -> void:
	if is_instance_valid(scoreboard_panel):
		return
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.name = "ScoreboardScreen"
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.position = Vector2(-550.0, -330.0)
	scoreboard_panel.custom_minimum_size = Vector2(1100.0, 660.0)
	scoreboard_panel.theme = interface_theme
	scoreboard_panel.add_theme_stylebox_override("panel", _panel_style(DesignTokensScript.INTERACTIVE, 0.985))
	scoreboard_panel.visible = false
	client.connection_controller.connection_canvas.add_child(scoreboard_panel)
	var scoreboard_content := VBoxContainer.new()
	scoreboard_content.add_theme_constant_override("separation", 10)
	scoreboard_panel.add_child(scoreboard_content)
	var scoreboard_kicker := Label.new()
	scoreboard_kicker.text = "✦  LIVE MATCH  ✦"
	scoreboard_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_kicker.add_theme_font_size_override("font_size", 16)
	scoreboard_kicker.add_theme_color_override("font_color", Color("ff8ee8"))
	scoreboard_content.add_child(scoreboard_kicker)
	scoreboard_label = Label.new()
	scoreboard_label.text = "SCOREBOARD"
	scoreboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_label.add_theme_font_size_override("font_size", 38)
	scoreboard_label.add_theme_color_override("font_color", Color("73f7ff"))
	scoreboard_content.add_child(scoreboard_label)
	scoreboard_context_label = Label.new()
	scoreboard_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_context_label.add_theme_font_size_override("font_size", 17)
	scoreboard_context_label.add_theme_color_override("font_color", Color("aebbd4"))
	scoreboard_content.add_child(scoreboard_context_label)
	scoreboard_media_label = Label.new()
	scoreboard_media_label.name = "ScoreboardMedia"
	scoreboard_media_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_media_label.add_theme_font_size_override("font_size", 16)
	scoreboard_media_label.add_theme_color_override("font_color", Color("73f7ff"))
	scoreboard_content.add_child(scoreboard_media_label)
	var scoreboard_heading := HBoxContainer.new()
	scoreboard_heading.add_theme_constant_override("separation", 12)
	scoreboard_content.add_child(scoreboard_heading)
	_add_results_column_heading(scoreboard_heading, "RANK / PILOT", 300.0)
	_add_results_column_heading(scoreboard_heading, "HEATS", 90.0)
	_add_results_column_heading(scoreboard_heading, "ROUNDS", 100.0)
	_add_results_column_heading(scoreboard_heading, "KILLS", 80.0)
	scoreboard_hill_heading = _add_results_column_heading(scoreboard_heading, "HILL TIME", 100.0)
	scoreboard_hill_heading.visible = false
	_add_results_column_heading(scoreboard_heading, "CURRENT BUILD", 0.0, true)
	var scoreboard_scroll := ScrollContainer.new()
	scoreboard_scroll.custom_minimum_size = Vector2(1060.0, 400.0)
	scoreboard_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scoreboard_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scoreboard_content.add_child(scoreboard_scroll)
	scoreboard_rows_container = VBoxContainer.new()
	scoreboard_rows_container.add_theme_constant_override("separation", 7)
	scoreboard_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scoreboard_scroll.add_child(scoreboard_rows_container)
	scoreboard_hint_label = Label.new()
	scoreboard_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_hint_label.add_theme_font_size_override("font_size", 15)
	scoreboard_hint_label.add_theme_color_override("font_color", Color("fff36a"))
	scoreboard_content.add_child(scoreboard_hint_label)
	client._refresh_control_prompts()

	win_overlay = Control.new()
	win_overlay.name = "WinScreen"
	win_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_overlay.visible = false
	client.connection_controller.connection_canvas.add_child(win_overlay)
	var win_background := NeonBackdrop.new()
	win_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_overlay.add_child(win_background)
	var win_tint := ColorRect.new()
	win_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_tint.color = Color("170b2f", 0.72)
	win_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_overlay.add_child(win_tint)
	results_panel = PanelContainer.new()
	results_panel.name = "ResultsScreen"
	results_panel.set_anchors_preset(Control.PRESET_CENTER)
	results_panel.position = Vector2(-560.0, -340.0)
	results_panel.custom_minimum_size = Vector2(1120.0, 680.0)
	results_panel.theme = interface_theme
	results_panel.add_theme_stylebox_override("panel", _panel_style(DesignTokensScript.FOCUS, 0.96))
	results_panel.visible = true
	win_overlay.add_child(results_panel)
	var results_content := VBoxContainer.new()
	results_content.add_theme_constant_override("separation", 10)
	results_panel.add_child(results_content)
	var results_kicker := Label.new()
	results_kicker.text = "✦  MATCH COMPLETE  ✦"
	results_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_kicker.add_theme_font_size_override("font_size", 18)
	results_kicker.add_theme_color_override("font_color", Color("ff8ee8"))
	results_content.add_child(results_kicker)
	results_label = Label.new()
	results_label.text = "VICTORY"
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_label.add_theme_font_size_override("font_size", 52)
	results_label.add_theme_color_override("font_color", Color("fff36a"))
	results_content.add_child(results_label)
	var champion_panel := PanelContainer.new()
	champion_panel.custom_minimum_size.y = 92.0
	champion_panel.add_theme_stylebox_override("panel", _results_row_style(Color("fff36a"), true))
	results_content.add_child(champion_panel)
	var champion_content := VBoxContainer.new()
	champion_content.alignment = BoxContainer.ALIGNMENT_CENTER
	champion_content.add_theme_constant_override("separation", 2)
	champion_panel.add_child(champion_content)
	var champion_kicker := Label.new()
	champion_kicker.text = "SUPER STAR CHAMPION"
	champion_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	champion_kicker.add_theme_font_size_override("font_size", 17)
	champion_kicker.add_theme_color_override("font_color", Color("d6e2f2"))
	champion_content.add_child(champion_kicker)
	results_winner_label = Label.new()
	results_winner_label.text = "PILOT"
	results_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_winner_label.add_theme_font_size_override("font_size", 34)
	results_winner_label.add_theme_color_override("font_color", Color("fff36a"))
	champion_content.add_child(results_winner_label)
	var standings_heading := HBoxContainer.new()
	standings_heading.add_theme_constant_override("separation", 12)
	results_content.add_child(standings_heading)
	_add_results_column_heading(standings_heading, "RANK", 72.0)
	_add_results_column_heading(standings_heading, "PILOT", 230.0)
	_add_results_column_heading(standings_heading, "ROUNDS WON", 150.0)
	_add_results_column_heading(standings_heading, "KILLS", 100.0)
	_add_results_column_heading(standings_heading, "FINAL BUILD", 0.0, true)
	var results_scroll := ScrollContainer.new()
	results_scroll.custom_minimum_size = Vector2(1060.0, 230.0)
	results_scroll.follow_focus = true
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	results_content.add_child(results_scroll)
	results_standings_container = VBoxContainer.new()
	results_standings_container.add_theme_constant_override("separation", 7)
	results_standings_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.add_child(results_standings_container)
	results_action_note = Label.new()
	results_action_note.name = "ResultsActionExplanation"
	results_action_note.text = RESULTS_ACTION_EXPLANATION
	results_action_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_action_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_action_note.add_theme_font_size_override("font_size", 16)
	results_content.add_child(results_action_note)
	var results_actions := HBoxContainer.new()
	results_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	results_actions.add_theme_constant_override("separation", 16)
	results_content.add_child(results_actions)
	results_rematch_button = Button.new()
	results_rematch_button.name = "FreshRematchButton"
	results_rematch_button.text = "FRESH REMATCH · SAME RULES"
	results_rematch_button.theme_type_variation = &"PrimaryButton"
	results_rematch_button.custom_minimum_size = Vector2(330.0, 52.0)
	results_rematch_button.add_theme_font_size_override("font_size", 17)
	results_rematch_button.pressed.connect(_on_results_rematch_pressed)
	results_actions.add_child(results_rematch_button)
	results_extend_button = Button.new()
	results_extend_button.text = "PLAY 5 MORE ROUNDS"
	results_extend_button.theme_type_variation = &"PrimaryButton"
	results_extend_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	results_extend_button.custom_minimum_size = Vector2(300.0, 52.0)
	results_extend_button.add_theme_font_size_override("font_size", 19)
	results_extend_button.pressed.connect(_on_results_extend_pressed)
	results_actions.add_child(results_extend_button)
	results_return_button = Button.new()
	results_return_button.text = "EXIT TO LOBBY"
	results_return_button.custom_minimum_size = Vector2(300.0, 52.0)
	results_return_button.add_theme_font_size_override("font_size", 19)
	results_return_button.pressed.connect(_on_results_return_pressed)
	results_actions.add_child(results_return_button)


func _update_scoreboard() -> void:
	var state_name := String(latest_match_payload.get("state_name", "LOBBY")).replace("_", " ").capitalize()
	scoreboard_context_label.text = "%s  ·  ROUND %d  ·  HEAT %d  ·  %d PILOTS" % [
		state_name,
		int(latest_match_payload.get("round_number", 0)),
		int(latest_match_payload.get("heat_number", 0)),
		_result_peer_ids().size(),
	]
	var track_name := audio_director.current_gameplay_track_name()
	if track_name.is_empty():
		track_name = "No Gameplay Music"
	scoreboard_media_label.text = "MAP  ·  %s     ♫     NOW PLAYING  ·  %s" % [
		String(latest_match_payload.get("map_name", ArenaLayout.display_name())).to_upper(),
		track_name.to_upper(),
	]
	scoreboard_hill_heading.visible = int(latest_match_payload.get("game_mode", GameModeRules.Mode.DEATH_MATCH)) == GameModeRules.Mode.KING_OF_THE_HILL
	if not _scoreboard_rows_dirty:
		return
	_scoreboard_rows_dirty = false
	for child in scoreboard_rows_container.get_children():
		scoreboard_rows_container.remove_child(child)
		child.free()
	var peer_ids := _result_peer_ids()
	for index in peer_ids.size():
		_add_scoreboard_row(index + 1, peer_ids[index])


func _set_scoreboard_open(open: bool) -> void:
	scoreboard_open = open and _scoreboard_available()
	if scoreboard_panel != null:
		scoreboard_panel.visible = scoreboard_open
	if scoreboard_open:
		_scoreboard_rows_dirty = true
		_update_scoreboard()


func _add_scoreboard_row(rank: int, peer_id: int) -> void:
	var is_local := peer_id == bridge.local_peer_id
	var team_id := _player_team(peer_id)
	var accent := Color("fff36a") if is_local else GameModeRules.team_color(team_id) if team_id > 0 else (Color("42e8ff") if rank % 2 == 0 else Color("d39cff"))
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 58.0
	row_panel.set_meta("peer_id", peer_id)
	row_panel.set_meta("rank", rank)
	row_panel.add_theme_stylebox_override("panel", _results_row_style(accent, is_local))
	scoreboard_rows_container.add_child(row_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)
	var player_label := Label.new()
	player_label.text = "#%02d   %s%s%s" % [rank, _player_name(peer_id), "  ·  %s" % GameModeRules.team_name(team_id) if team_id > 0 else "", "  ★ YOU" if is_local else ""]
	player_label.custom_minimum_size.x = 300.0
	player_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_label.add_theme_font_size_override("font_size", 19 if is_local else 17)
	player_label.add_theme_color_override("font_color", accent if is_local else Color("f4fbff"))
	row.add_child(player_label)
	var score := _result_score(peer_id)
	var heats_label := Label.new()
	heats_label.text = str(score.get("heat_wins", 0))
	heats_label.custom_minimum_size.x = 90.0
	heats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heats_label.add_theme_color_override("font_color", Color("73f7ff"))
	row.add_child(heats_label)
	var rounds_label := Label.new()
	rounds_label.text = str(score.get("round_wins", 0))
	rounds_label.custom_minimum_size.x = 100.0
	rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rounds_label.add_theme_color_override("font_color", Color("ff8ee8"))
	row.add_child(rounds_label)
	var kills_label := Label.new()
	kills_label.name = "MatchKills"
	kills_label.text = str(score.get("kills", 0))
	kills_label.custom_minimum_size.x = 80.0
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_color_override("font_color", Color("fff36a"))
	row.add_child(kills_label)
	if int(latest_match_payload.get("game_mode", GameModeRules.Mode.DEATH_MATCH)) == GameModeRules.Mode.KING_OF_THE_HILL:
		var hill_label := Label.new()
		hill_label.name = "HillTime"
		hill_label.text = "%.1fs" % _hill_score(peer_id)
		hill_label.custom_minimum_size.x = 100.0
		hill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hill_label.add_theme_color_override("font_color", Color("ffb45f"))
		row.add_child(hill_label)
	_add_result_build(row, peer_id, "ScoreboardBuildCards")


func _hill_score(peer_id: int) -> float:
	var objective := latest_match_payload.get("objective", {}) as Dictionary
	var progress := objective.get("progress", {}) as Dictionary
	return float(progress.get(peer_id, progress.get(str(peer_id), 0.0)))


func _update_results_screen() -> void:
	var winner_id := int(latest_match_payload.get("match_winner", 0))
	var winner_team := int(latest_match_payload.get("match_winner_team", 0))
	results_winner_label.text = "★  %s  ★" % (GameModeRules.team_name(winner_team) if winner_team > 0 else _player_name(winner_id).to_upper())
	var is_leader := bridge.local_peer_id != 0 and bridge.local_peer_id == int(bridge.latest_lobby_state.get("leader_id", 0))
	var action_requested := _extend_match_requested or _return_to_lobby_requested or _rematch_requested
	var can_extend := bool(latest_match_payload.get("can_extend_match", true))
	results_rematch_button.disabled = not is_leader or not can_extend or action_requested
	results_rematch_button.text = "STARTING FRESH REMATCH…" if _rematch_requested else "FRESH REMATCH · SAME RULES"
	results_rematch_button.tooltip_text = "The host starts a new match with the same rules and teams. Every build, score and objective total resets."
	results_extend_button.disabled = not is_leader or not can_extend or action_requested
	results_return_button.disabled = not is_leader or action_requested
	if _extend_match_requested:
		results_extend_button.text = "EXTENDING MATCH…"
		results_extend_button.tooltip_text = "Waiting for server confirmation."
	else:
		results_extend_button.text = "PLAY 5 MORE ROUNDS"
		results_extend_button.tooltip_text = "Continue this match for exactly five more rounds while keeping every player's cards and scores."
	if _return_to_lobby_requested:
		results_return_button.text = "RETURNING EVERYONE TO LOBBY…"
		results_return_button.tooltip_text = "Waiting for server confirmation."
	elif is_leader:
		results_return_button.text = "EXIT TO LOBBY"
		results_return_button.tooltip_text = "Close the final standings and return every connected player to the lobby."
	else:
		results_return_button.text = "WAITING FOR LOBBY LEADER"
		results_return_button.tooltip_text = "The lobby leader controls when everyone leaves the final standings."
	if not _results_rows_dirty:
		return
	_results_rows_dirty = false
	for child in results_standings_container.get_children():
		results_standings_container.remove_child(child)
		child.free()
	var peer_ids := _result_peer_ids()
	for index in peer_ids.size():
		var peer_team := _player_team(peer_ids[index])
		_add_result_row(index + 1, peer_ids[index], peer_team == winner_team if winner_team > 0 else peer_ids[index] == winner_id)


func _on_results_rematch_pressed() -> void:
	if results_rematch_button.disabled:
		return
	_rematch_requested = true
	_update_results_screen()
	bridge.send_rematch()


func _on_results_extend_pressed() -> void:
	if results_extend_button.disabled:
		return
	_extend_match_requested = true
	_update_results_screen()
	bridge.send_extend_match()


func _on_results_return_pressed() -> void:
	if results_return_button.disabled:
		return
	_return_to_lobby_requested = true
	_update_results_screen()
	bridge.send_return_to_lobby()


func _result_peer_ids() -> Array[int]:
	return StandingsModelScript.peer_ids(latest_match_payload)


func _result_score(peer_id: int) -> Dictionary:
	return StandingsModelScript.score(latest_match_payload, peer_id)


func _result_build(peer_id: int) -> Dictionary:
	return StandingsModelScript.build(latest_match_payload, peer_id)


func _add_result_build(parent: HBoxContainer, peer_id: int, container_name: String = "FinalBuildCards") -> void:
	var build := _result_build(peer_id)
	var build_flow := HFlowContainer.new()
	build_flow.name = container_name
	build_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_flow.add_theme_constant_override("h_separation", 6)
	build_flow.add_theme_constant_override("v_separation", 5)
	parent.add_child(build_flow)
	if build.is_empty():
		var base_label := Label.new()
		base_label.text = "BASE LOADOUT"
		base_label.add_theme_font_size_override("font_size", 15)
		base_label.add_theme_color_override("font_color", Color("8ba1c7"))
		build_flow.add_child(base_label)
		return
	var card_ids := build.keys()
	card_ids.sort_custom(func(first: Variant, second: Variant) -> bool:
		var first_card := card_catalog.get_card(StringName(first))
		var second_card := card_catalog.get_card(StringName(second))
		var first_name := first_card.display_name if first_card != null else String(first)
		var second_name := second_card.display_name if second_card != null else String(second)
		return first_name < second_name
	)
	for card_value in card_ids:
		var card_id := StringName(card_value)
		var card := card_catalog.get_card(card_id)
		var stacks := int(build[card_value])
		var chip := CardHoverButtonScript.new()
		chip.focus_mode = Control.FOCUS_ALL
		chip.mouse_default_cursor_shape = Control.CURSOR_HELP
		chip.text = "%s ×%d" % [card.display_name if card != null else String(card_id), stacks]
		chip.set_meta("card_id", card_id)
		chip.set_meta("stack_count", stacks)
		chip.add_theme_font_size_override("font_size", 14)
		if card != null:
			var rarity_color := card.rarity_color()
			chip.configure(card, stacks, CardDetailsText.tooltip(card, stacks))
			chip.add_theme_color_override("font_color", rarity_color.lightened(0.2))
			chip.add_theme_color_override("font_hover_color", Color.WHITE)
			chip.add_theme_stylebox_override("normal", _result_card_chip_style(rarity_color, false))
			chip.add_theme_stylebox_override("hover", _result_card_chip_style(rarity_color, true))
			chip.add_theme_stylebox_override("focus", _result_card_chip_focus_style(rarity_color))
			chip.add_theme_stylebox_override("pressed", _result_card_chip_style(rarity_color, true))
		build_flow.add_child(chip)


func _add_result_row(rank: int, peer_id: int, winner: bool) -> void:
	var team_id := _player_team(peer_id)
	var accent := Color("fff36a") if winner else GameModeRules.team_color(team_id) if team_id > 0 else (Color("42e8ff") if rank % 2 == 0 else Color("d39cff"))
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 58.0
	row_panel.set_meta("peer_id", peer_id)
	row_panel.set_meta("rank", rank)
	row_panel.set_meta("winner", winner)
	row_panel.add_theme_stylebox_override("panel", _results_row_style(accent, winner))
	results_standings_container.add_child(row_panel)
	var row_content := VBoxContainer.new()
	row_content.add_theme_constant_override("separation", 6)
	row_panel.add_child(row_content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_content.add_child(row)
	var rank_label := Label.new()
	rank_label.text = "#%02d" % rank
	rank_label.custom_minimum_size.x = 60.0
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 19)
	rank_label.add_theme_color_override("font_color", accent)
	row.add_child(rank_label)
	var player_label := Label.new()
	player_label.text = "%s%s%s" % [_player_name(peer_id), "  ·  %s" % GameModeRules.team_name(team_id) if team_id > 0 else "", "  ★" if winner else ""]
	player_label.custom_minimum_size.x = 230.0
	player_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_label.add_theme_font_size_override("font_size", 20 if winner else 18)
	player_label.add_theme_color_override("font_color", Color("fff36a") if winner else Color("f4fbff"))
	row.add_child(player_label)
	var score := _result_score(peer_id)
	var score_label := Label.new()
	score_label.name = "RoundWins"
	score_label.text = str(int(score.get("round_wins", 0)))
	score_label.custom_minimum_size.x = 150.0
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color("73f7ff"))
	row.add_child(score_label)
	var kills_label := Label.new()
	kills_label.name = "MatchKills"
	kills_label.text = str(int(score.get("kills", 0)))
	kills_label.custom_minimum_size.x = 100.0
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_font_size_override("font_size", 16)
	kills_label.add_theme_color_override("font_color", Color("fff36a"))
	row.add_child(kills_label)
	_add_result_build(row, peer_id)
	var contribution := preload("res://src/client/ui/objective_contribution_text.gd").summary(latest_match_payload, peer_id)
	if not contribution.is_empty():
		var contribution_label := Label.new()
		contribution_label.name = "ObjectiveContribution"
		contribution_label.text = contribution
		contribution_label.add_theme_font_size_override("font_size", 16)
		contribution_label.add_theme_color_override("font_color", Color("bdefff"))
		contribution_label.tooltip_text = "Server-recorded contribution over the whole match. Contested time is separate from scoring control; carrier stops count enemy flag carriers eliminated."
		row_content.add_child(contribution_label)


func _add_results_column_heading(parent: HBoxContainer, text_value: String, width: float, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = width
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("8ba1c7"))
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _results_row_style(accent: Color, winner: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.darkened(0.82), 0.9 if winner else 0.7)
	style.border_color = Color(accent, 0.92 if winner else 0.38)
	style.set_border_width_all(2 if winner else 1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _result_card_chip_style(color: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.76), 0.92 if hovered else 0.72)
	style.border_color = Color(color, 0.9 if hovered else 0.46)
	style.set_border_width_all(2 if hovered else 1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _result_card_chip_focus_style(rarity_color: Color) -> StyleBoxFlat:
	var style := _result_card_chip_style(rarity_color, true)
	style.border_color = DesignTokensScript.FOCUS
	style.set_border_width_all(3)
	style.shadow_color = Color(DesignTokensScript.FOCUS, 0.26)
	style.shadow_size = 8
	return style


func _set_win_screen_visible(visible: bool) -> void:
	var was_visible := win_overlay != null and win_overlay.visible
	if win_overlay != null:
		win_overlay.visible = visible
	if results_panel != null:
		results_panel.visible = visible
	if not visible:
		_results_rows_dirty = true
	elif not was_visible and results_return_button != null and not results_return_button.disabled:
		results_return_button.grab_focus()


func _panel_style(accent: Color, opacity: float) -> StyleBoxFlat:
	return client._panel_style(accent, opacity)


func _player_name(peer_id: int) -> String:
	return client._player_name(peer_id)


func _player_team(peer_id: int) -> int:
	return client._player_team(peer_id)


func _scoreboard_available() -> bool:
	return client._scoreboard_available()


func reset_actions(reset_explanation: bool = false) -> void:
	_extend_match_requested = false
	_return_to_lobby_requested = false
	_rematch_requested = false
	if reset_explanation:
		results_action_note.text = RESULTS_ACTION_EXPLANATION


func reset_session() -> void:
	_set_scoreboard_open(false)
	_set_win_screen_visible(false)
	reset_actions(true)
	_scoreboard_rows_dirty = true


func show_request_rejection(message: String) -> void:
	reset_actions()
	if win_overlay.visible:
		results_action_note.text = "Could not continue: %s\nChoose another action or return to the lobby." % message
