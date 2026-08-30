class_name AuthoritativeMatchCoordinator
extends RefCounted

const CardPowerupSystemScript = preload("res://src/shared/combat/card_powerup_system.gd")

var lobby: ServerLobby
var world: AuthoritativeWorld
var machine: MatchStateMachine
var draft: DraftManager
var catalog: CardCatalog
var powerups: RefCounted
var match_seed: int
var overtime_start_seconds: float = GameConstants.OVERTIME_START_SECONDS
var current_map_id: StringName = ArenaLayout.DEFAULT_MAP_ID

var _rng := RandomNumberGenerator.new()
var _emitted_history_count: int = 0
var _events: Array[Dictionary] = []
var _private_offers: Array[Dictionary] = []
var _finished: bool = false
var _next_draft_bye_peer_id: int = 0
var _next_draft_bye_peer_ids: Array[int] = []
var _map_rotation: Array[StringName] = []
var _map_round_number: int = 0
var _objective_position: Vector2 = Vector2.ZERO
var _objective_progress: Dictionary = {}
var _objective_controller_id: int = 0
var _flag_position: Vector2 = Vector2.ZERO
var _flag_carrier_id: int = 0
var _flag_dropped_seconds: float = 0.0
var _last_objective_broadcast_tick: int = -1
var _team_assignments_cache: Dictionary = {}
var _capture_zones_cache: Dictionary = {}
var _objective_view_cache: Dictionary = {}
var _spawn_assignments_cache: Dictionary = {}
var _respawn_deadlines: Dictionary = {}


func _init(
	server_lobby: ServerLobby,
	authoritative_world: AuthoritativeWorld,
	seed_value: int,
	overtime_start_override: float = -1.0
) -> void:
	lobby = server_lobby
	world = authoritative_world
	catalog = CardCatalog.create_default()
	powerups = CardPowerupSystemScript.new(catalog, seed_value)
	match_seed = seed_value
	overtime_start_seconds = overtime_start_override if overtime_start_override >= 0.0 else lobby.config.overtime_start_seconds
	_rng.seed = match_seed
	_map_rotation = ArenaLayout.map_ids()
	var map_rng := RandomNumberGenerator.new()
	map_rng.seed = match_seed ^ 0x5A17_2026
	for index in range(_map_rotation.size() - 1, 0, -1):
		var swap_index := map_rng.randi_range(0, index)
		var temporary := _map_rotation[index]
		_map_rotation[index] = _map_rotation[swap_index]
		_map_rotation[swap_index] = temporary
	machine = MatchStateMachine.new(lobby.config, catalog)
	for player_value in lobby.players.values():
		var lobby_player := player_value as PlayerMatchState
		var player := machine.add_player(
			lobby_player.peer_id,
			lobby_player.display_name,
			lobby_player.join_sequence
		)
		player.participant = lobby_player.participant
		player.is_npc = lobby_player.is_npc
		player.npc_difficulty = lobby_player.npc_difficulty
		player.ship_color = lobby_player.ship_color
		player.team_id = lobby_player.team_id
		player.team_selection = lobby_player.team_selection
	_rebuild_team_assignments_cache()
	_rebuild_objective_static_cache()
	draft = DraftManager.new(catalog, match_seed)
	world.set_team_assignments(_team_assignments_cache)


func start(at_tick: int) -> bool:
	if not machine.start_match(at_tick):
		return false
	_capture_transitions()
	return true


func step(delta: float) -> void:
	if _finished:
		return
	var tick := world.server_tick
	match machine.state:
		MatchStateMachine.State.DRAFT:
			if draft.all_locked() or machine.is_draft_timed_out(tick):
				if not draft.all_locked():
					draft.resolve_timeout()
				var applied := draft.apply_locked_selections(machine.players)
				_events.append({
					"event_type": &"DRAFT_RESOLVED",
					"server_tick": tick,
					"payload": {
						"selections": applied,
						"builds": _public_builds(),
					},
				})
				machine.draft_completed(tick)
				_capture_transitions()
		MatchStateMachine.State.ACTIVE_HEAT:
			var heat_elapsed := maxf(
				float(tick - machine.state_entered_tick) /
				GameConstants.PHYSICS_TICKS_PER_SECOND,
				0.0
			)
			if heat_elapsed >= overtime_start_seconds:
				var overtime_elapsed := (
					GameConstants.OVERTIME_START_SECONDS +
					heat_elapsed - overtime_start_seconds
				)
				world.apply_overtime(overtime_elapsed, delta)
			for powerup_event in powerups.step(tick, world, machine.players):
				var payload := (powerup_event.payload as Dictionary).duplicate(true)
				if StringName(powerup_event.event_type) == &"CARD_POWERUP_COLLECTED":
					payload["builds"] = _public_builds()
				_events.append({
					"event_type": powerup_event.event_type,
					"server_tick": tick,
					"payload": payload,
				})
			_sync_combat_and_resolve(tick)
			if machine.state == MatchStateMachine.State.ACTIVE_HEAT:
				_step_respawns(tick)
				_step_game_mode(delta, tick)
		_:
			machine.advance_time(tick)
			_capture_transitions()


func select_card(peer_id: int, offer_token: String, card_id: StringName) -> int:
	if machine.state != MatchStateMachine.State.DRAFT:
		return DraftManager.SelectionResult.NO_ACTIVE_DRAFT
	var result := draft.select_card(peer_id, offer_token, card_id)
	if result == DraftManager.SelectionResult.ACCEPTED:
		_events.append({
			"event_type": &"DRAFT_READY",
			"server_tick": world.server_tick,
			"payload": {"ready_peer_ids": _ready_peer_ids()},
		})
	return result


func add_late_spectator(player: PlayerMatchState) -> void:
	var added := machine.add_player(player.peer_id, player.display_name, player.join_sequence)
	added.is_npc = player.is_npc
	added.participant = false
	added.spectator = true
	world.set_spectator(player.peer_id)


func disconnect_peer(peer_id: int) -> void:
	var was_active_participant := (
		machine.state == MatchStateMachine.State.ACTIVE_HEAT and
		peer_id in machine.participant_ids()
	)
	if draft != null and draft.is_active():
		draft.withdraw_player(peer_id)
	machine.disconnect_player(peer_id, world.server_tick)
	if was_active_participant:
		_events.append({
			"event_type": &"PLAYER_ELIMINATED",
			"server_tick": world.server_tick,
			"payload": {
				"peer_ids": [peer_id],
				"reason": "disconnect",
				"scores": machine.score_snapshot(),
			},
		})
	_capture_transitions()


func state() -> int:
	return machine.state


func controls_enabled() -> bool:
	return machine.state == MatchStateMachine.State.ACTIVE_HEAT


func npc_overtime_elapsed() -> float:
	if machine.state != MatchStateMachine.State.ACTIVE_HEAT:
		return -1.0
	var heat_elapsed := maxf(
		float(world.server_tick - machine.state_entered_tick) /
		GameConstants.PHYSICS_TICKS_PER_SECOND,
		0.0
	)
	return (
		GameConstants.OVERTIME_START_SECONDS +
		heat_elapsed - overtime_start_seconds
	)


func npc_objective_state() -> Dictionary:
	return _objective_state_view()


func is_finished() -> bool:
	return _finished


func return_to_lobby() -> bool:
	if _finished or not machine.return_to_lobby(world.server_tick):
		return false
	_capture_transitions()
	return true


func extend_match() -> bool:
	if _finished or not machine.extend_match(GameConstants.MATCH_EXTENSION_ROUNDS, world.server_tick):
		return false
	_capture_transitions()
	return true


func drain_events() -> Array[Dictionary]:
	var result := _events.duplicate(true)
	_events.clear()
	return result


func drain_private_offers() -> Array[Dictionary]:
	var result := _private_offers.duplicate(true)
	_private_offers.clear()
	return result


func current_state_payload() -> Dictionary:
	return _state_payload()


func _capture_transitions() -> void:
	while _emitted_history_count < machine.event_history.size():
		var transition := machine.event_history[_emitted_history_count] as Dictionary
		_emitted_history_count += 1
		if int(transition.state) == MatchStateMachine.State.HEAT_RESULT and not lobby.config.random_powerups_permanent:
			for player_value in machine.players.values():
				(player_value as PlayerMatchState).clear_temporary_cards()
		if int(transition.state) == MatchStateMachine.State.DRAFT:
			_select_map_for_round(int(transition.round_number))
		if int(transition.state) == MatchStateMachine.State.COUNTDOWN:
			_reset_objective_for_heat()
		_events.append({
			"event_type": &"STATE_CHANGED",
			"server_tick": int(transition.entered_tick),
			"payload": _state_payload(),
		})
		_handle_state_entry(int(transition.state))


func _handle_state_entry(new_state: int) -> void:
	match new_state:
		MatchStateMachine.State.DRAFT:
			_start_draft()
		MatchStateMachine.State.COUNTDOWN:
			powerups.clear()
			_prepare_world_heat()
		MatchStateMachine.State.ACTIVE_HEAT:
			powerups.begin_heat(
				world.server_tick,
				current_map_id,
				lobby.config.random_spawn_powerups,
				lobby.config.random_powerup_interval_seconds,
				lobby.config.random_powerups_permanent
			)
		MatchStateMachine.State.HEAT_RESULT:
			_respawn_deadlines.clear()
			powerups.clear()
			world.clear_projectiles()
		MatchStateMachine.State.ROUND_RESULT:
			_next_draft_bye_peer_id = machine.last_round_winner
			_next_draft_bye_peer_ids.clear()
			if machine.last_round_winner_team > 0:
				for peer_id in machine.participant_ids():
					if (machine.players[peer_id] as PlayerMatchState).team_id == machine.last_round_winner_team:
						_next_draft_bye_peer_ids.append(peer_id)
			else:
				_next_draft_bye_peer_ids.append(machine.last_round_winner)
		MatchStateMachine.State.MATCH_RESULT:
			powerups.clear()
			world.clear_projectiles()
		MatchStateMachine.State.LOBBY:
			lobby.return_to_lobby()
			world.clear_projectiles()
			for peer_value in world.combatants.keys():
				world.set_spectator(int(peer_value))
			_finished = true


func _start_draft() -> void:
	var skipped_peer_ids: Array[int] = []
	if machine.round_number > 1:
		for peer_id in _next_draft_bye_peer_ids:
			if peer_id != 0:
				skipped_peer_ids.append(peer_id)
	var offers := draft.start_draft(machine.players, machine.round_number, skipped_peer_ids)
	var peer_ids := offers.keys()
	peer_ids.sort()
	for peer_value in peer_ids:
		var peer_id := int(peer_value)
		var offer := offers[peer_id] as DraftOffer
		var player := machine.players[peer_id] as PlayerMatchState
		if offer.skipped:
			continue
		if player.is_npc:
			if not offer.locked and not offer.card_ids.is_empty():
				var chosen_id := offer.card_ids[_rng.randi_range(0, offer.card_ids.size() - 1)]
				draft.select_card(peer_id, offer.token, chosen_id)
			continue
		_private_offers.append({
			"peer_id": peer_id,
			"offer_token": offer.token,
			"card_ids": offer.card_ids.duplicate(),
			"deadline_tick": machine.state_deadline_tick,
			"build_complete": offer.build_complete,
		})
	_events.append({
		"event_type": &"DRAFT_READY",
		"server_tick": world.server_tick,
		"payload": {"ready_peer_ids": _ready_peer_ids()},
	})


func _prepare_world_heat() -> void:
	var participant_stats: Dictionary = {}
	var anchors := ArenaLayout.spawn_anchors(current_map_id)
	_shuffle_anchors(anchors)
	var participant_ids := machine.participant_ids()
	var spawn_assignments := (
		_team_spawn_assignments(participant_ids, anchors)
		if GameModeRules.is_team_mode(lobby.config.game_mode) else
		{}
	)
	for index in participant_ids.size():
		var peer_id := participant_ids[index]
		var player := machine.players[peer_id] as PlayerMatchState
		participant_stats[peer_id] = StatSystem.derive(player.effective_card_stacks(), catalog)
		if not spawn_assignments.has(peer_id):
			spawn_assignments[peer_id] = anchors[index]
	world.set_team_assignments(_team_assignments_cache)
	_spawn_assignments_cache = spawn_assignments.duplicate(true)
	if lobby.config.game_mode == GameModeRules.Mode.CAPTURE_THE_FLAG:
		_rebuild_objective_static_cache()
	world.prepare_heat(participant_stats, spawn_assignments)


func _team_spawn_assignments(participant_ids: Array[int], anchors: Array[Vector2]) -> Dictionary:
	var result: Dictionary = {}
	var available := anchors.duplicate()
	var team_count := GameModeRules.team_count_for_mode(lobby.config.game_mode, lobby.config.team_count)
	var center := ArenaLayout.center(current_map_id)
	for team_id in range(1, team_count + 1):
		var members: Array[int] = []
		for peer_id in participant_ids:
			if (machine.players[peer_id] as PlayerMatchState).team_id == team_id:
				members.append(peer_id)
		members.sort()
		var team_angle := PI + TAU * float(team_id - 1) / float(team_count)
		for member_index in members.size():
			if available.is_empty():
				break
			var member_offset := (float(member_index) - float(members.size() - 1) * 0.5) * 0.12
			var desired_angle := team_angle + member_offset
			var best_index := 0
			var best_difference := INF
			for anchor_index in available.size():
				var anchor := available[anchor_index] as Vector2
				var difference := absf(angle_difference((anchor - center).angle(), desired_angle))
				if difference < best_difference:
					best_difference = difference
					best_index = anchor_index
			result[members[member_index]] = available.pop_at(best_index)
	return result


func _select_map_for_round(round_number: int) -> void:
	if round_number <= 0 or round_number == _map_round_number or _map_rotation.is_empty():
		return
	_map_round_number = round_number
	current_map_id = _map_rotation[posmod(round_number - 1, _map_rotation.size())]
	world.set_map_id(current_map_id)
	_rebuild_objective_static_cache()


func _sync_combat_and_resolve(tick: int) -> void:
	for kill_event in world.drain_kill_events():
		machine.scores.award_kill(int(kill_event.killer_id))
	var newly_eliminated: Array[int] = []
	for peer_id in machine.participant_ids():
		var player := machine.players[peer_id] as PlayerMatchState
		var combatant := world.combatants.get(peer_id) as CombatantState
		if combatant == null:
			continue
		player.health = combatant.health
		player.shield_energy = combatant.shield.energy
		player.ammunition = combatant.weapon.ammunition
		if player.alive and not combatant.alive:
			newly_eliminated.append(peer_id)
	if not newly_eliminated.is_empty():
		if GameModeRules.uses_respawns(lobby.config.game_mode):
			var respawn_ticks := lobby.config.duration_to_ticks(GameModeRules.OBJECTIVE_RESPAWN_SECONDS)
			for peer_id in newly_eliminated:
				_respawn_deadlines[peer_id] = tick + respawn_ticks
		_events.append({
			"event_type": &"PLAYER_ELIMINATED",
			"server_tick": tick,
			"payload": {
				"peer_ids": newly_eliminated,
				"reason": "combat",
				"scores": machine.score_snapshot(),
				"respawn_deadlines": _respawn_deadlines.duplicate(true),
			},
		})
		machine.eliminate_players(newly_eliminated, tick)
		_capture_transitions()


func _step_respawns(tick: int) -> void:
	if not GameModeRules.uses_respawns(lobby.config.game_mode) or _respawn_deadlines.is_empty():
		return
	var due_peer_ids: Array[int] = []
	for peer_value in _respawn_deadlines.keys():
		var peer_id := int(peer_value)
		if tick >= int(_respawn_deadlines[peer_value]):
			due_peer_ids.append(peer_id)
	due_peer_ids.sort()
	for peer_id in due_peer_ids:
		_respawn_deadlines.erase(peer_id)
		if not machine.respawn_player(peer_id):
			continue
		var player := machine.players[peer_id] as PlayerMatchState
		var stats := StatSystem.derive(player.effective_card_stacks(), catalog)
		var spawn_position := _safe_respawn_position(peer_id)
		if not world.respawn_peer(peer_id, stats, spawn_position):
			player.eliminate()
			continue
		_events.append({
			"event_type": &"PLAYER_RESPAWNED",
			"server_tick": tick,
			"payload": {
				"peer_id": peer_id,
				"position": spawn_position,
				"alive_peer_ids": machine.alive_participant_ids(),
				"respawn_deadlines": _respawn_deadlines.duplicate(true),
			},
		})


func _safe_respawn_position(peer_id: int) -> Vector2:
	var preferred := _spawn_assignments_cache.get(peer_id, ArenaLayout.center(current_map_id)) as Vector2
	var candidates: Array[Vector2] = [preferred]
	for anchor in ArenaLayout.spawn_anchors(current_map_id):
		if anchor != preferred:
			candidates.append(anchor)
	candidates.sort_custom(func(left: Vector2, right: Vector2) -> bool:
		return left.distance_squared_to(preferred) < right.distance_squared_to(preferred)
	)
	for candidate in candidates:
		var available := true
		for other_id in machine.alive_participant_ids():
			if other_id == peer_id:
				continue
			var other := world.combatants.get(other_id) as CombatantState
			if other != null and other.alive and other.position.distance_to(candidate) < GameConstants.SHIP_COLLISION_RADIUS * 3.0:
				available = false
				break
		if available and ArenaCollisionSystem.is_ship_position_clear(candidate, current_map_id):
			return candidate
	return preferred


func _reset_objective_for_heat() -> void:
	_objective_position = GameModeRules.objective_spawn(
		current_map_id,
		machine.round_number if GameModeRules.uses_hill(lobby.config.game_mode) else 0
	)
	_rebuild_objective_static_cache()
	_respawn_deadlines.clear()
	_objective_progress.clear()
	if GameModeRules.uses_hill(lobby.config.game_mode):
		for peer_id in machine.participant_ids():
			_objective_progress[peer_id] = 0.0
	_objective_controller_id = 0
	_flag_position = _objective_position
	_flag_carrier_id = 0
	_flag_dropped_seconds = 0.0
	_last_objective_broadcast_tick = -1


func _step_game_mode(delta: float, tick: int) -> void:
	match lobby.config.game_mode:
		GameModeRules.Mode.KING_OF_THE_HILL:
			_step_hill(delta, tick)
		GameModeRules.Mode.CAPTURE_THE_FLAG, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG:
			_step_flag(delta, tick)
	if machine.state == MatchStateMachine.State.ACTIVE_HEAT and GameModeRules.uses_objective(lobby.config.game_mode):
		var interval := maxi(GameConstants.PHYSICS_TICKS_PER_SECOND / 4, 1)
		if _last_objective_broadcast_tick < 0 or tick - _last_objective_broadcast_tick >= interval:
			_last_objective_broadcast_tick = tick
			_events.append({
				"event_type": &"OBJECTIVE_UPDATED",
				"server_tick": tick,
				"payload": {"objective": _objective_snapshot()},
			})


func _step_hill(delta: float, tick: int) -> void:
	var occupants: Array[int] = []
	for peer_id in machine.alive_participant_ids():
		var combatant := world.combatants.get(peer_id) as CombatantState
		if combatant != null and combatant.position.distance_to(_objective_position) <= GameModeRules.OBJECTIVE_ZONE_RADIUS:
			occupants.append(peer_id)
	if occupants.size() != 1:
		if _objective_controller_id != 0:
			_objective_controller_id = 0
			_emit_objective_transition(tick, &"HILL_CONTROL_LOST")
		return
	var controller_id := occupants[0]
	if controller_id != _objective_controller_id:
		_objective_controller_id = controller_id
		if not _objective_progress.has(controller_id):
			_objective_progress[controller_id] = 0.0
		_emit_objective_transition(tick, &"HILL_CONTROLLER_CHANGED")
	_objective_progress[controller_id] = float(_objective_progress.get(controller_id, 0.0)) + maxf(delta, 0.0)
	if float(_objective_progress[controller_id]) >= GameModeRules.HILL_HOLD_SECONDS:
		machine.finish_heat(controller_id, tick)
		_capture_transitions()


func _step_flag(delta: float, tick: int) -> void:
	if _flag_carrier_id != 0:
		var carrier := world.combatants.get(_flag_carrier_id) as CombatantState
		if carrier == null or not carrier.alive:
			if carrier != null:
				_flag_position = carrier.position
			_flag_carrier_id = 0
			_flag_dropped_seconds = 0.0
			_emit_objective_transition(tick, &"FLAG_DROPPED")
		else:
			_flag_position = carrier.position
			var carrier_team := int(_team_assignments_cache.get(_flag_carrier_id, 0))
			var capture_zone_id := carrier_team if GameModeRules.is_team_mode(lobby.config.game_mode) else _flag_carrier_id
			var capture_position := _capture_zones_cache.get(capture_zone_id, Vector2.ZERO) as Vector2
			if carrier.position.distance_to(capture_position) <= GameModeRules.OBJECTIVE_ZONE_RADIUS:
				if GameModeRules.is_team_mode(lobby.config.game_mode):
					machine.finish_team_heat(carrier_team, tick)
				else:
					machine.finish_heat(_flag_carrier_id, tick)
				_capture_transitions()
				return
	if _flag_carrier_id == 0:
		var pickup_id := 0
		var nearest_distance := INF
		for peer_id in machine.alive_participant_ids():
			var combatant := world.combatants.get(peer_id) as CombatantState
			if combatant == null:
				continue
			var distance := combatant.position.distance_to(_flag_position)
			if distance <= GameModeRules.FLAG_PICKUP_RADIUS and distance < nearest_distance:
				pickup_id = peer_id
				nearest_distance = distance
		if pickup_id != 0:
			_flag_carrier_id = pickup_id
			_flag_dropped_seconds = 0.0
			_emit_objective_transition(tick, &"FLAG_PICKED_UP")
		else:
			_flag_dropped_seconds += maxf(delta, 0.0)
			if _flag_position != _objective_position and _flag_dropped_seconds >= GameModeRules.FLAG_RESET_SECONDS:
				_flag_position = _objective_position
				_flag_dropped_seconds = 0.0
				_emit_objective_transition(tick, &"FLAG_RESET")


func _emit_objective_transition(tick: int, action: StringName) -> void:
	_events.append({
		"event_type": &"OBJECTIVE_TRANSITION",
		"server_tick": tick,
		"payload": {"action": action, "objective": _objective_snapshot()},
	})


func _objective_snapshot() -> Dictionary:
	return _objective_state_view().duplicate(true)


func _objective_state_view() -> Dictionary:
	var mode := lobby.config.game_mode
	_objective_view_cache.active = machine.state in [MatchStateMachine.State.COUNTDOWN, MatchStateMachine.State.ACTIVE_HEAT]
	_objective_view_cache.mode = mode
	_objective_view_cache.mode_name = GameModeRules.mode_name(mode)
	_objective_view_cache.position = _objective_position
	_objective_view_cache.zone_radius = GameModeRules.OBJECTIVE_ZONE_RADIUS
	if GameModeRules.uses_hill(mode):
		_objective_view_cache.controller_id = _objective_controller_id
		_objective_view_cache.progress = _objective_progress
		_objective_view_cache.target_seconds = GameModeRules.HILL_HOLD_SECONDS
	elif GameModeRules.uses_flag(mode):
		_objective_view_cache.flag_position = _flag_position
		_objective_view_cache.flag_carrier_id = _flag_carrier_id
		_objective_view_cache.pickup_radius = GameModeRules.FLAG_PICKUP_RADIUS
		_objective_view_cache.capture_zones = _capture_zones_cache
	return _objective_view_cache


func _team_assignments() -> Dictionary:
	return _team_assignments_cache.duplicate()


func _rebuild_team_assignments_cache() -> void:
	_team_assignments_cache.clear()
	for peer_id in machine.participant_ids():
		_team_assignments_cache[peer_id] = (machine.players[peer_id] as PlayerMatchState).team_id


func _rebuild_objective_static_cache() -> void:
	_capture_zones_cache.clear()
	var mode := lobby.config.game_mode
	if GameModeRules.uses_flag(mode):
		if GameModeRules.is_team_mode(mode):
			for team_id in range(1, GameModeRules.team_count_for_mode(mode, lobby.config.team_count) + 1):
				_capture_zones_cache[team_id] = GameModeRules.capture_zone(mode, team_id, current_map_id)
		else:
			for peer_id in machine.participant_ids():
				_capture_zones_cache[peer_id] = _spawn_assignments_cache.get(
					peer_id,
					GameModeRules.capture_zone(mode, peer_id, current_map_id)
				)
	_objective_view_cache = {
		"active": false,
		"mode": mode,
		"mode_name": GameModeRules.mode_name(mode),
		"position": _objective_position,
		"zone_radius": GameModeRules.OBJECTIVE_ZONE_RADIUS,
	}


func _state_payload() -> Dictionary:
	return {
		"state": machine.state,
		"state_name": machine.state_name(),
		"entered_tick": machine.state_entered_tick,
		"deadline_tick": machine.state_deadline_tick,
		"round_number": machine.round_number,
		"heat_number": machine.heat_number,
		"map_id": current_map_id,
		"map_name": ArenaLayout.display_name(current_map_id),
		"game_mode": lobby.config.game_mode,
		"game_mode_name": GameModeRules.mode_name(lobby.config.game_mode),
		"last_heat_winner": machine.last_heat_winner,
		"last_round_winner": machine.last_round_winner,
		"last_heat_winner_team": machine.last_heat_winner_team,
		"last_round_winner_team": machine.last_round_winner_team,
		"match_winner_team": machine.match_winner_team,
		"team_heat_wins": machine.team_heat_wins.duplicate(true),
		"team_round_wins": machine.team_round_wins.duplicate(true),
		"teams": _team_assignments(),
		"draft_bye_peer_id": _next_draft_bye_peer_id if machine.state == MatchStateMachine.State.DRAFT and machine.round_number > 1 and not GameModeRules.is_team_mode(lobby.config.game_mode) else 0,
		"draft_bye_peer_ids": _next_draft_bye_peer_ids.duplicate(),
		"match_winner": machine.match_winner,
		"rounds_to_win": machine.config.rounds_to_win,
		"can_extend_match": machine.can_extend_match(),
		"tied_heat": machine.tied_heat,
		"scores": machine.score_snapshot(),
		"alive_peer_ids": machine.alive_participant_ids(),
		"respawn_deadlines": _respawn_deadlines.duplicate(true),
		"participant_peer_ids": machine.participant_ids(),
		"builds": _public_builds(),
		"powerups": powerups.snapshot() if machine.state == MatchStateMachine.State.ACTIVE_HEAT else [],
		"random_spawn_powerups": lobby.config.random_spawn_powerups,
		"random_powerup_interval_seconds": lobby.config.random_powerup_interval_seconds,
		"random_powerups_permanent": lobby.config.random_powerups_permanent,
		"objective": _objective_snapshot(),
		"overtime_start_tick": machine.state_entered_tick + roundi(
			overtime_start_seconds * GameConstants.PHYSICS_TICKS_PER_SECOND
		) if machine.state == MatchStateMachine.State.ACTIVE_HEAT else -1,
	}


func _public_builds() -> Dictionary:
	var builds: Dictionary = {}
	for player_value in machine.players.values():
		var player := player_value as PlayerMatchState
		if player.connected:
			builds[player.peer_id] = player.effective_card_stacks()
	return builds


func _ready_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_id in machine.participant_ids():
		var offer := draft.get_offer(peer_id)
		if offer != null and offer.locked:
			result.append(peer_id)
	return result


func _shuffle_anchors(anchors: Array[Vector2]) -> void:
	for index in range(anchors.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := anchors[index]
		anchors[index] = anchors[swap_index]
		anchors[swap_index] = temporary
