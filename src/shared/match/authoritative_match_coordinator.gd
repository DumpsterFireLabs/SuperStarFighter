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
var _map_rotation: Array[StringName] = []
var _map_round_number: int = 0


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
	draft = DraftManager.new(catalog, match_seed)


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
			"payload": {"peer_ids": [peer_id], "reason": "disconnect"},
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


func is_finished() -> bool:
	return _finished


func return_to_lobby() -> bool:
	if _finished or not machine.return_to_lobby(world.server_tick):
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
			powerups.clear()
			world.clear_projectiles()
		MatchStateMachine.State.ROUND_RESULT:
			_next_draft_bye_peer_id = machine.last_round_winner
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
	if machine.round_number > 1 and _next_draft_bye_peer_id != 0:
		skipped_peer_ids.append(_next_draft_bye_peer_id)
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
	var spawn_assignments: Dictionary = {}
	var anchors := ArenaLayout.spawn_anchors(current_map_id)
	_shuffle_anchors(anchors)
	var participant_ids := machine.participant_ids()
	for index in participant_ids.size():
		var peer_id := participant_ids[index]
		var player := machine.players[peer_id] as PlayerMatchState
		participant_stats[peer_id] = StatSystem.derive(player.effective_card_stacks(), catalog)
		spawn_assignments[peer_id] = anchors[index]
	world.prepare_heat(participant_stats, spawn_assignments)


func _select_map_for_round(round_number: int) -> void:
	if round_number <= 0 or round_number == _map_round_number or _map_rotation.is_empty():
		return
	_map_round_number = round_number
	current_map_id = _map_rotation[posmod(round_number - 1, _map_rotation.size())]
	world.set_map_id(current_map_id)


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
		_events.append({
			"event_type": &"PLAYER_ELIMINATED",
			"server_tick": tick,
			"payload": {"peer_ids": newly_eliminated, "reason": "combat"},
		})
		machine.eliminate_players(newly_eliminated, tick)
		_capture_transitions()


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
		"last_heat_winner": machine.last_heat_winner,
		"last_round_winner": machine.last_round_winner,
		"draft_bye_peer_id": _next_draft_bye_peer_id if machine.state == MatchStateMachine.State.DRAFT and machine.round_number > 1 else 0,
		"match_winner": machine.match_winner,
		"tied_heat": machine.tied_heat,
		"scores": machine.scores.snapshot(),
		"alive_peer_ids": machine.alive_participant_ids(),
		"participant_peer_ids": machine.participant_ids(),
		"builds": _public_builds(),
		"powerups": powerups.snapshot() if machine.state == MatchStateMachine.State.ACTIVE_HEAT else [],
		"random_spawn_powerups": lobby.config.random_spawn_powerups,
		"random_powerup_interval_seconds": lobby.config.random_powerup_interval_seconds,
		"random_powerups_permanent": lobby.config.random_powerups_permanent,
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
