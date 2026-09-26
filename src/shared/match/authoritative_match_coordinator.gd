class_name AuthoritativeMatchCoordinator
extends RefCounted

const CardPowerupSystemScript = preload("res://src/shared/combat/card_powerup_system.gd")
const RespawnPlacementScript = preload("res://src/shared/combat/respawn_placement.gd")
const MAX_RESPAWN_ATTEMPTS_PER_TICK: int = 2

var observations: MatchObservations = preload("res://src/shared/match/match_observations.gd").new()

var lobby: ServerLobby
var world: AuthoritativeWorld
var machine: MatchStateMachine
var draft: DraftManager
var catalog: CardCatalog
var powerups: RefCounted
var match_seed: int
var overtime_start_seconds: float = GameConstants.OVERTIME_START_SECONDS
var _heat_overtime_limit_seconds: float = GameConstants.OVERTIME_TIME_LIMIT_SECONDS
var current_map_id: StringName = ArenaLayout.DEFAULT_MAP_ID

var _rng := RandomNumberGenerator.new()
var _emitted_history_count: int = 0
var _events: Array[MatchEvent] = []
var _private_offers: Array[Dictionary] = []
var _finished: bool = false
var _next_draft_bye_peer_id: int = 0
var _next_draft_bye_peer_ids: Array[int] = []
var _map_rotation: Array[StringName] = []
var _map_round_number: int = 0
var _hill := HillModeHandler.new()
var _flag := FlagModeHandler.new()
# Private compatibility views for existing studies/fixtures; handlers own storage.
var _objective_position: Vector2:
	get:
		return _mode_state().position
var _objective_progress: Dictionary:
	get:
		return _hill.state.progress
	set(value):
		_hill.state.progress.assign(value)
var _flag_position: Vector2:
	get:
		return _flag.state.flag_position
var _flag_carrier_id: int:
	get:
		return _flag.state.flag_carrier_id
var _last_arena_effect_snapshot: Dictionary = {}
var _last_arena_effect_tick := -1
var _last_objective_broadcast_tick: int = -1
var _team_assignments_cache: Dictionary = {}
var _capture_zones_cache: Dictionary:
	get:
		return _flag.state.capture_zones
var _spawn_assignments_cache: Dictionary = {}
var _respawn_deadlines: Dictionary = {}
var _respawn_retry_ticks: Dictionary = {}
# Departed participants whose seats are held: previous peer id -> {"name", "deadline"}.
var _awaiting_reconnect: Dictionary = {}
# Wall-clock seconds for hold deadlines. Match ticks freeze while a hold pauses
# the match, so they cannot time the hold. Tests may replace this clock.
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
var _reconnect_hold: bool = false
var _paused_before_reconnect_hold: bool = false
var _heat_time_limit_reached: bool = false
var incremental_drafts: bool = false
const DRAFT_SLICE_BUDGET_USEC: int = 2000
const DRAFT_PLAYERS_PER_SLICE: int = 2
var _draft_preparation_started_usec: int = 0
var _phase_work: Dictionary = {}


func record_phase_work(phase: StringName, elapsed_usec: int) -> void:
	var row: Dictionary = _phase_work.get(phase, {"count": 0, "total_usec": 0, "max_usec": 0})
	row.count += 1
	row.total_usec += elapsed_usec
	row.max_usec = maxi(row.max_usec, elapsed_usec)
	_phase_work[phase] = row


func phase_work_snapshot() -> Dictionary:
	return _phase_work.duplicate(true)


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
		player.ship_pattern = lobby_player.ship_pattern
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
	if _finished or world.simulation_paused:
		return
	var tick := world.server_tick
	match machine.state:
		MatchStateMachine.State.DRAFT:
			if draft.is_preparing():
				_step_draft_preparation()
				return
			if draft.all_locked() or machine.is_draft_timed_out(tick):
				if not draft.all_locked():
					draft.resolve_timeout()
				var applied := draft.apply_locked_selections(machine.players)
				_events.append(MatchEvent.new(&"DRAFT_RESOLVED", tick, {
					"selections": applied,
					"builds": _public_builds(),
				}))
				machine.draft_completed(tick)
				_capture_transitions()
		MatchStateMachine.State.ACTIVE_HEAT:
			var heat_elapsed := maxf(
				float(tick - machine.state_entered_tick) /
				GameConstants.PHYSICS_TICKS_PER_SECOND,
				0.0
			)
			if world.arena_effects.enabled != 0:
				world.step_arena_effects(heat_elapsed, overtime_start_seconds)
				var effect_snapshot := world.arena_effects.snapshot()
				if tick - _last_arena_effect_tick >= 6 or effect_snapshot.hidden_cover != _last_arena_effect_snapshot.get("hidden_cover", -1):
					_last_arena_effect_snapshot = effect_snapshot
					_last_arena_effect_tick = tick
					_events.append(MatchEvent.new(&"ARENA_EFFECTS_UPDATED", tick, effect_snapshot))
			if heat_elapsed >= overtime_start_seconds:
				var overtime_elapsed := (
					GameConstants.OVERTIME_START_SECONDS +
					heat_elapsed - overtime_start_seconds
				)
				world.apply_overtime(
					overtime_elapsed,
					delta,
					_overtime_center(),
					_overtime_minimum_radius()
				)
			var safe_radius := OvertimeSystem.radius_at(npc_overtime_elapsed(), _overtime_center(), _overtime_minimum_radius())
			for powerup_event in powerups.step(tick, world, machine.players, _overtime_center(), safe_radius):
				var payload := (powerup_event.payload as Dictionary).duplicate(true)
				if StringName(powerup_event.event_type) == &"CARD_POWERUP_COLLECTED":
					observations.record_pickup(int(payload.peer_id), lobby.config.random_powerups_permanent)
					payload["builds"] = _public_builds()
				_events.append(MatchEvent.new(powerup_event.event_type, tick, payload))
			_sync_combat_and_resolve(tick)
			if machine.state == MatchStateMachine.State.ACTIVE_HEAT:
				_step_respawns(tick)
				_step_game_mode(delta, tick)
			if machine.state == MatchStateMachine.State.ACTIVE_HEAT and tick >= heat_end_tick():
				_heat_time_limit_reached = true
				machine.finish_timed_heat(tick, _objective_progress)
				_capture_transitions()
			observations.observe(tick, machine, world)
		_:
			machine.advance_time(tick)
			_capture_transitions()


func select_card(peer_id: int, offer_token: String, card_id: StringName) -> int:
	if machine.state != MatchStateMachine.State.DRAFT:
		return DraftManager.SelectionResult.NO_ACTIVE_DRAFT
	var result := draft.select_card(peer_id, offer_token, card_id)
	if result == DraftManager.SelectionResult.ACCEPTED:
		_events.append(MatchEvent.new(&"DRAFT_READY", world.server_tick, {"ready_peer_ids": _ready_peer_ids()}))
	return result


func add_late_spectator(player: PlayerMatchState) -> void:
	var added := machine.add_player(player.peer_id, player.display_name, player.join_sequence)
	added.is_npc = player.is_npc
	added.ship_color = player.ship_color
	added.ship_pattern = player.ship_pattern
	added.participant = false
	added.spectator = true
	world.set_spectator(player.peer_id)


## With hold_for_reconnect, a departing human participant keeps their seat until
## reconnect_peer() or release_reconnect(). Returns whether the seat was kept.
func disconnect_peer(peer_id: int, hold_for_reconnect: bool = false) -> bool:
	var player := machine.players.get(peer_id) as PlayerMatchState
	var was_active_participant := (
		machine.state == MatchStateMachine.State.ACTIVE_HEAT and
		peer_id in machine.participant_ids()
	)
	var keep_seat := (
		hold_for_reconnect and player != null and player.connected and
		player.participant and not player.is_npc and
		machine.state not in [MatchStateMachine.State.LOBBY, MatchStateMachine.State.MATCH_RESULT]
	)
	if draft != null and draft.is_active():
		draft.withdraw_player(peer_id)
	_respawn_deadlines.erase(peer_id)
	_respawn_retry_ticks.erase(peer_id)
	machine.disconnect_player(peer_id, world.server_tick, keep_seat)
	if keep_seat:
		_awaiting_reconnect[peer_id] = {
			"name": player.display_name,
			"deadline": float(clock.call()) + GameConstants.RECONNECT_GRACE_SECONDS,
		}
	if was_active_participant:
		_events.append(MatchEvent.new(&"PLAYER_ELIMINATED", world.server_tick, {
			"peer_ids": [peer_id],
			"eliminations": [{
				"killer_id": 0,
				"victim_id": peer_id,
				"reason": "disconnect",
			}],
			"reason": "disconnect",
			"scores": machine.score_snapshot(),
		}))
	_capture_transitions()
	_update_reconnect_hold()
	return keep_seat


func can_reconnect(previous_peer_id: int) -> bool:
	return _awaiting_reconnect.has(previous_peer_id)


## Returns a held seat to its player under their new peer id. The new peer must
## already have a lobby record and a world combatant.
func reconnect_peer(previous_peer_id: int, peer_id: int) -> bool:
	if not _awaiting_reconnect.has(previous_peer_id):
		return false
	var player := machine.reconnect_player(previous_peer_id, peer_id)
	if player == null:
		return false
	_awaiting_reconnect.erase(previous_peer_id)
	# The lobby record is authoritative for names; keep the scoreboard in step.
	var lobby_player := lobby.players.get(peer_id) as PlayerMatchState
	if lobby_player != null:
		player.display_name = lobby_player.display_name
	if _team_assignments_cache.has(previous_peer_id):
		_team_assignments_cache[peer_id] = _team_assignments_cache[previous_peer_id]
		_team_assignments_cache.erase(previous_peer_id)
	if _spawn_assignments_cache.has(previous_peer_id):
		_spawn_assignments_cache[peer_id] = _spawn_assignments_cache[previous_peer_id]
		_spawn_assignments_cache.erase(previous_peer_id)
	if _hill.state.progress.has(previous_peer_id):
		_hill.state.progress[peer_id] = _hill.state.progress[previous_peer_id]
		_hill.state.progress.erase(previous_peer_id)
	var bye_index := _next_draft_bye_peer_ids.find(previous_peer_id)
	if bye_index >= 0:
		_next_draft_bye_peer_ids[bye_index] = peer_id
	if _next_draft_bye_peer_id == previous_peer_id:
		_next_draft_bye_peer_id = peer_id
	observations.rekey_peer(previous_peer_id, peer_id)
	world.set_spectator(peer_id)
	world.set_team_assignments(_team_assignments_cache)
	_rebuild_objective_static_cache()
	var tick := world.server_tick
	if machine.state == MatchStateMachine.State.COUNTDOWN:
		# The heat was prepared without this pilot; join it before it starts so a
		# returning 1v1 opponent is not left to wait out a one-ship heat.
		_join_prepared_heat(player)
	elif machine.state == MatchStateMachine.State.ACTIVE_HEAT and GameModeRules.uses_respawns(lobby.config.game_mode):
		_respawn_deadlines[peer_id] = tick + lobby.config.duration_to_ticks(GameModeRules.OBJECTIVE_RESPAWN_SECONDS)
	if draft != null and draft.is_active():
		var offer := draft.restore_player(previous_peer_id, peer_id)
		if offer != null and not draft.is_preparing() and not offer.locked:
			_private_offers.append({
				"peer_id": peer_id,
				"offer_token": offer.token,
				"card_ids": offer.card_ids.duplicate(),
				"deadline_tick": machine.state_deadline_tick,
				"build_complete": offer.build_complete,
			})
		_events.append(MatchEvent.new(&"DRAFT_READY", tick, {"ready_peer_ids": _ready_peer_ids()}))
	_update_reconnect_hold()
	_events.append(MatchEvent.new(&"STATE_CHANGED", tick, _state_payload()))
	return true


func _join_prepared_heat(player: PlayerMatchState) -> void:
	var peer_id := player.peer_id
	var stats := StatSystem.derive(player.effective_card_stacks(), catalog)
	var spawn_position := _safe_respawn_position(peer_id)
	if not spawn_position.is_finite() or not world.respawn_peer(peer_id, stats, spawn_position):
		return
	player.reset_for_heat(stats)
	_spawn_assignments_cache[peer_id] = spawn_position
	if not _hill.state.progress.has(peer_id) and GameModeRules.uses_hill(lobby.config.game_mode):
		_hill.state.progress[peer_id] = 0.0
	# Capture the Flag bases follow spawn positions.
	_rebuild_objective_static_cache()


## Releases every held seat whose grace period has run out and returns their
## previous peer ids. The coordinator owns these deadlines, so no hold can
## outlive its grace period even if the caller lost track of it.
func expire_reconnects() -> Array[int]:
	var expired: Array[int] = []
	if _awaiting_reconnect.is_empty():
		return expired
	var now := float(clock.call())
	for peer_value in _awaiting_reconnect.keys():
		if now >= float(_awaiting_reconnect[peer_value].deadline):
			expired.append(int(peer_value))
	expired.sort()
	for peer_id in expired:
		release_reconnect(peer_id)
	return expired


## Gives up a held seat. If the match was waiting on it, the departure result
## (forfeit or return to lobby) is applied now.
func release_reconnect(previous_peer_id: int) -> void:
	if not _awaiting_reconnect.erase(previous_peer_id):
		return
	if _reconnect_hold and _awaiting_reconnect.is_empty():
		_set_reconnect_hold(false)
		machine.resolve_departures(world.server_tick)
		_capture_transitions()
	else:
		_update_reconnect_hold()


func awaiting_reconnect_names() -> Array[String]:
	var names: Array[String] = []
	var peer_ids := _awaiting_reconnect.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		names.append(String(_awaiting_reconnect[peer_id].name))
	return names


func _update_reconnect_hold() -> void:
	var hold := (
		not _awaiting_reconnect.is_empty() and not _finished and
		machine.state not in [MatchStateMachine.State.LOBBY, MatchStateMachine.State.MATCH_RESULT] and
		machine.departure_result_due()
	)
	if hold != _reconnect_hold:
		_set_reconnect_hold(hold)
	elif hold:
		_append_pause_event()


func _set_reconnect_hold(hold: bool) -> void:
	_reconnect_hold = hold
	var was_paused := world.simulation_paused
	if hold:
		_paused_before_reconnect_hold = was_paused
		world.simulation_paused = true
	else:
		# A host pause only outlives the hold while the match can still be paused;
		# a result or lobby reached meanwhile must never be left frozen.
		world.simulation_paused = (
			_paused_before_reconnect_hold and not _finished and
			machine.state not in [MatchStateMachine.State.LOBBY, MatchStateMachine.State.MATCH_RESULT]
		)
	if world.simulation_paused != was_paused:
		_discard_held_inputs()
	_append_pause_event()


## Discards held actions on a pause edge without resetting input sequence validation.
func _discard_held_inputs() -> void:
	for input_peer in world.latest_inputs:
		var previous := world.latest_inputs[input_peer] as PlayerInputFrame
		world.latest_inputs[input_peer] = PlayerInputFrame.new(previous.sequence, world.server_tick, Vector2.ZERO, previous.aim_angle)


func _append_pause_event() -> void:
	_events.append(MatchEvent.new(&"MATCH_PAUSE_CHANGED", world.server_tick, {
		"paused": world.simulation_paused,
		"awaiting_reconnect": awaiting_reconnect_names() if _reconnect_hold else [],
	}))


func state() -> int:
	return machine.state


func controls_enabled() -> bool:
	return not world.simulation_paused and machine.state == MatchStateMachine.State.ACTIVE_HEAT


func request_pause(peer_id: int, paused: bool) -> bool:
	if peer_id == 0 or peer_id != lobby.leader_id or _finished or machine.state in [MatchStateMachine.State.LOBBY, MatchStateMachine.State.MATCH_RESULT]:
		return false
	if _reconnect_hold:
		# The match stays paused until the seat is filled or released.
		_paused_before_reconnect_hold = paused
		return true
	if world.simulation_paused == paused:
		return true
	world.simulation_paused = paused
	_discard_held_inputs()
	_events.append(MatchEvent.new(&"MATCH_PAUSE_CHANGED", world.server_tick, {"paused": paused}))
	return true


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


func npc_objective_state() -> ObjectiveState:
	_sync_objective_activity()
	return _mode_state().snapshot()


func _overtime_center() -> Vector2:
	if GameModeRules.uses_hill(lobby.config.game_mode):
		return _objective_position
	return ArenaLayout.center(current_map_id)


func _overtime_minimum_radius() -> float:
	if GameModeRules.uses_hill(lobby.config.game_mode):
		return GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS
	if GameModeRules.uses_flag(lobby.config.game_mode):
		var radius := GameConstants.OVERTIME_MINIMUM_RADIUS
		for zone in _capture_zones_cache.values():
			radius = maxf(radius, _overtime_center().distance_to(zone as Vector2) + GameModeRules.OBJECTIVE_ZONE_RADIUS)
		return minf(radius, OvertimeSystem.initial_radius(_overtime_center()))
	return GameConstants.OVERTIME_MINIMUM_RADIUS


func heat_end_tick() -> int:
	return machine.state_entered_tick + roundi((overtime_start_seconds + _heat_overtime_limit_seconds) * GameConstants.PHYSICS_TICKS_PER_SECOND)


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
	var result: Array[Dictionary] = []
	for event in _events:
		result.append(event.to_dictionary())
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
		var started_usec := Time.get_ticks_usec()
		var transition := machine.event_history[_emitted_history_count] as Dictionary
		if int(transition.state) in [MatchStateMachine.State.LOBBY, MatchStateMachine.State.MATCH_RESULT]:
			world.simulation_paused = false
		_emitted_history_count += 1
		observations.enter_state(int(transition.state), int(transition.entered_tick), machine, world, current_map_id)
		if int(transition.state) == MatchStateMachine.State.HEAT_RESULT and not lobby.config.random_powerups_permanent:
			for player_value in machine.players.values():
				(player_value as PlayerMatchState).clear_temporary_cards()
		if int(transition.state) == MatchStateMachine.State.DRAFT:
			_select_map_for_round(int(transition.round_number))
		if int(transition.state) == MatchStateMachine.State.COUNTDOWN:
			_prepare_countdown()
		_events.append(MatchEvent.new(&"STATE_CHANGED", int(transition.entered_tick), _state_payload()))
		_handle_state_entry(int(transition.state))
		record_phase_work(StringName("enter_" + MatchStateMachine.State.keys()[int(transition.state)]), Time.get_ticks_usec() - started_usec)


func _handle_state_entry(new_state: int) -> void:
	match new_state:
		MatchStateMachine.State.DRAFT:
			_start_draft()
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
			_respawn_retry_ticks.clear()
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
	if incremental_drafts:
		_draft_preparation_started_usec = Time.get_ticks_usec()
		draft.begin_draft(machine.players, machine.round_number, skipped_peer_ids)
		return
	draft.start_draft(machine.players, machine.round_number, skipped_peer_ids)
	_publish_draft_offers()


func _step_draft_preparation() -> void:
	var started_usec := Time.get_ticks_usec()
	for index in DRAFT_PLAYERS_PER_SLICE:
		var peer_id := draft.prepare_next_player()
		var player := machine.players.get(peer_id) as PlayerMatchState
		var offer := draft.get_offer(peer_id)
		if player != null and player.connected and player.is_npc and offer != null and not offer.locked:
			draft.select_card(peer_id, offer.token, draft.choose_npc_card(player, lobby.config.game_mode, machine.players))
		if not draft.is_preparing() or Time.get_ticks_usec() - started_usec >= DRAFT_SLICE_BUDGET_USEC:
			break
	record_phase_work(&"draft_slice", Time.get_ticks_usec() - started_usec)
	if not draft.is_preparing():
		# Everybody receives the full decision interval, beginning at publication.
		machine.state_deadline_tick = world.server_tick + lobby.config.duration_to_ticks(lobby.config.draft_duration_seconds)
		_events.append(MatchEvent.new(&"STATE_CHANGED", world.server_tick, _state_payload()))
		_publish_draft_offers()
		record_phase_work(&"draft_prepare_wall", Time.get_ticks_usec() - _draft_preparation_started_usec)


func _publish_draft_offers() -> void:
	var peer_ids := machine.players.keys()
	peer_ids.sort()
	for peer_value in peer_ids:
		var peer_id := int(peer_value)
		var offer := draft.get_offer(peer_id)
		if offer == null:
			continue
		var player := machine.players[peer_id] as PlayerMatchState
		if offer.skipped:
			observations.record_bye(peer_id)
			continue
		if player.is_npc:
			if not offer.locked and not offer.card_ids.is_empty():
				var chosen_id := draft.choose_npc_card(player, lobby.config.game_mode, machine.players)
				draft.select_card(peer_id, offer.token, chosen_id)
			continue
		_private_offers.append({
			"peer_id": peer_id,
			"offer_token": offer.token,
			"card_ids": offer.card_ids.duplicate(),
			"deadline_tick": machine.state_deadline_tick,
			"build_complete": offer.build_complete,
		})
	_events.append(MatchEvent.new(&"DRAFT_READY", world.server_tick, {"ready_peer_ids": _ready_peer_ids()}))


func _prepare_countdown() -> void:
	# Prepare the full playable state before publishing countdown navigation.
	# Other transitions retain their event-before-entry ordering (notably draft).
	powerups.clear()
	_prepare_world_heat()
	_reset_objective_for_heat()
	if GameModeRules.uses_objective(lobby.config.game_mode):
		NpcObjectiveNavigation._graph(current_map_id)


func _prepare_world_heat() -> void:
	# Freeze the population rule before publication. Deaths and disconnects must
	# not extend a deadline already announced to LAN or internet clients.
	_heat_overtime_limit_seconds = GameModeRules.overtime_limit_seconds(lobby.config.game_mode, machine.participant_ids().size())
	var participant_stats: Dictionary = {}
	var anchors := ArenaLayout.spawn_anchors(current_map_id)
	_shuffle_anchors(anchors)
	var participant_ids := machine.participant_ids()
	var spawn_assignments := (
		_team_spawn_assignments(participant_ids, anchors)
		if GameModeRules.is_team_mode(lobby.config.game_mode) else
		_spread_spawn_assignments(participant_ids, anchors)
	)
	for index in participant_ids.size():
		var peer_id := participant_ids[index]
		var player := machine.players[peer_id] as PlayerMatchState
		participant_stats[peer_id] = StatSystem.derive(player.effective_card_stacks(), catalog)
		if not spawn_assignments.has(peer_id):
			spawn_assignments[peer_id] = anchors[index]
	world.set_team_assignments(_team_assignments_cache)
	_spawn_assignments_cache = spawn_assignments.duplicate(true)
	world.prepare_heat(participant_stats, spawn_assignments)
	world.arena_effects.reset(current_map_id, lobby.config.arena_effects)
	_last_arena_effect_snapshot = {}
	_last_arena_effect_tick = -1


func _spread_spawn_assignments(participant_ids: Array[int], anchors: Array[Vector2]) -> Dictionary:
	var result: Dictionary = {}
	var available := anchors.duplicate()
	for peer_id in participant_ids:
		if available.is_empty():
			break
		var best_index := 0
		if not result.is_empty():
			var best_clearance_squared := -1.0
			for anchor_index in available.size():
				var anchor := available[anchor_index] as Vector2
				var clearance_squared := INF
				for assigned_position in result.values():
					clearance_squared = minf(
						clearance_squared,
						anchor.distance_squared_to(assigned_position as Vector2)
					)
				if clearance_squared > best_clearance_squared:
					best_clearance_squared = clearance_squared
					best_index = anchor_index
		result[peer_id] = available.pop_at(best_index)
	return result


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
	var kill_events := world.drain_kill_events()
	for kill_event in kill_events:
		machine.scores.award_kill(int(kill_event.killer_id))
		if int(kill_event.target_id) == _flag_carrier_id:
			observations.add_contribution(int(kill_event.killer_id), "carrier_stops")
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
		_events.append(MatchEvent.new(&"PLAYER_ELIMINATED", tick, {
			"peer_ids": newly_eliminated,
			"eliminations": _elimination_records(newly_eliminated, kill_events),
			"reason": "combat",
			"scores": machine.score_snapshot(),
			"respawn_deadlines": _respawn_deadlines.duplicate(true),
		}))
		machine.eliminate_players(newly_eliminated, tick)
		_capture_transitions()


func _elimination_records(peer_ids: Array[int], kill_events: Array[Dictionary]) -> Array[Dictionary]:
	var killers_by_victim: Dictionary = {}
	for event in kill_events:
		killers_by_victim[int(event.get("target_id", 0))] = int(event.get("killer_id", 0))
	var records: Array[Dictionary] = []
	for victim_id in peer_ids:
		var killer_id := int(killers_by_victim.get(victim_id, 0))
		records.append({
			"killer_id": killer_id,
			"victim_id": victim_id,
			"reason": "combat" if killer_id != 0 else "environment",
		})
	return records


func _step_respawns(tick: int) -> void:
	if not GameModeRules.uses_respawns(lobby.config.game_mode) or _respawn_deadlines.is_empty() or tick >= heat_end_tick():
		return
	var due_peer_ids: Array[int] = []
	for peer_value in _respawn_deadlines.keys():
		var peer_id := int(peer_value)
		if tick >= int(_respawn_deadlines[peer_value]) and tick >= int(_respawn_retry_ticks.get(peer_id, 0)):
			due_peer_ids.append(peer_id)
	due_peer_ids.sort()
	var attempts := 0
	for peer_id in due_peer_ids:
		var pending := machine.players.get(peer_id) as PlayerMatchState
		if pending == null or not pending.connected or not pending.participant or pending.alive:
			_respawn_deadlines.erase(peer_id)
			_respawn_retry_ticks.erase(peer_id)
			continue
		if attempts >= MAX_RESPAWN_ATTEMPTS_PER_TICK:
			break
		attempts += 1
		var spawn_position := _safe_respawn_position(peer_id)
		if not spawn_position.is_finite():
			# Preserve the visible deadline, but bound retries when the safe zone
			# is crowded or blocked rather than reviving inside occupied geometry.
			_respawn_retry_ticks[peer_id] = tick + GameConstants.PHYSICS_TICKS_PER_SECOND / 2
			continue
		_respawn_deadlines.erase(peer_id)
		_respawn_retry_ticks.erase(peer_id)
		if not machine.respawn_player(peer_id):
			continue
		var player := machine.players[peer_id] as PlayerMatchState
		var stats := StatSystem.derive(player.effective_card_stacks(), catalog)
		if not world.respawn_peer(peer_id, stats, spawn_position):
			player.eliminate()
			continue
		_events.append(MatchEvent.new(&"PLAYER_RESPAWNED", tick, {
			"peer_id": peer_id,
			"position": spawn_position,
			"alive_peer_ids": machine.alive_participant_ids(),
			"respawn_deadlines": _respawn_deadlines.duplicate(true),
		}))


func _safe_respawn_position(peer_id: int) -> Vector2:
	var preferred := _spawn_assignments_cache.get(peer_id, ArenaLayout.center(current_map_id)) as Vector2
	var center := _overtime_center()
	var radius := OvertimeSystem.radius_at(npc_overtime_elapsed(), center, _overtime_minimum_radius())
	return RespawnPlacementScript.choose(world, peer_id, preferred, center, radius)


func _reset_objective_for_heat() -> void:
	_heat_time_limit_reached = false
	var position := GameModeRules.objective_spawn(
		current_map_id,
		machine.round_number if GameModeRules.uses_hill(lobby.config.game_mode) else 0
	)
	var hill_participants: Array[int] = []
	if GameModeRules.uses_hill(lobby.config.game_mode):
		hill_participants = machine.participant_ids()
	_hill.reset(position, hill_participants)
	_flag.reset(position)
	_rebuild_objective_static_cache()
	_respawn_deadlines.clear()
	_respawn_retry_ticks.clear()
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
			_events.append(MatchEvent.objective_event(tick, _mode_state()))


func _step_hill(delta: float, tick: int) -> void:
	_sync_objective_activity()
	_consume_objective_result(_hill.step(delta, world, machine.alive_participant_ids(), observations), tick)


func _step_flag(delta: float, tick: int) -> void:
	_sync_objective_activity()
	_consume_objective_result(_flag.step(delta, world, machine.alive_participant_ids(), observations), tick)


func _consume_objective_result(result: ObjectiveStepResult, tick: int) -> void:
	for transition in result.transitions:
		_events.append(MatchEvent.objective_event(tick, transition.objective, transition.action))
	# Handler contributions and intermediate transitions precede result payloads.
	if result.winner_team_id != 0:
		machine.finish_team_heat(result.winner_team_id, tick)
		_capture_transitions()
	elif result.winner_peer_id != 0:
		machine.finish_heat(result.winner_peer_id, tick)
		_capture_transitions()


func _mode_state() -> ObjectiveState:
	return _hill.state if GameModeRules.uses_hill(lobby.config.game_mode) else _flag.state


func _sync_objective_activity() -> void:
	_mode_state().active = machine.state in [MatchStateMachine.State.COUNTDOWN, MatchStateMachine.State.ACTIVE_HEAT]


func _objective_snapshot() -> Dictionary:
	_sync_objective_activity()
	return _mode_state().to_dictionary()


func _team_assignments() -> Dictionary:
	return _team_assignments_cache.duplicate()


func _rebuild_team_assignments_cache() -> void:
	_team_assignments_cache.clear()
	for peer_id in machine.participant_ids():
		_team_assignments_cache[peer_id] = (machine.players[peer_id] as PlayerMatchState).team_id


func _rebuild_objective_static_cache() -> void:
	_flag.configure(lobby.config.game_mode, current_map_id, lobby.config.team_count,
		machine.participant_ids(), _team_assignments_cache, _spawn_assignments_cache)


func _state_payload() -> Dictionary:
	return {
		"paused": world.simulation_paused,
		"awaiting_reconnect": awaiting_reconnect_names() if _reconnect_hold else [],
		"objective_contributions": observations.contributions.duplicate(true),
		"state": machine.state,
		"state_name": machine.state_name(),
		"entered_tick": machine.state_entered_tick,
		"deadline_tick": machine.state_deadline_tick,
		"heat_end_tick": heat_end_tick() if machine.state == MatchStateMachine.State.ACTIVE_HEAT else -1,
		"heat_time_limit_reached": _heat_time_limit_reached,
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
		"extension_end_round_number": machine.extension_end_round_number,
		"can_extend_match": machine.can_extend_match(),
		"tied_heat": machine.tied_heat,
		"scores": machine.score_snapshot(),
		"alive_peer_ids": machine.alive_participant_ids(),
		"respawn_deadlines": _respawn_deadlines.duplicate(true),
		"participant_peer_ids": machine.participant_ids(),
		"players": _public_players(),
		"builds": _public_builds(),
		"powerups": powerups.snapshot() if machine.state == MatchStateMachine.State.ACTIVE_HEAT else [],
		"arena_effect_settings": lobby.config.arena_effects.duplicate(),
		"arena_effect_state": world.arena_effects.snapshot(),
		"random_spawn_powerups": lobby.config.random_spawn_powerups,
		"random_powerup_interval_seconds": lobby.config.random_powerup_interval_seconds,
		"random_powerups_permanent": lobby.config.random_powerups_permanent,
		"competitive_view": machine.config.competitive_view,
		"objective": _objective_snapshot(),
		"overtime_center": _overtime_center(),
		"overtime_minimum_radius": _overtime_minimum_radius(),
		"overtime_start_tick": machine.state_entered_tick + roundi(
			overtime_start_seconds * GameConstants.PHYSICS_TICKS_PER_SECOND
		) if machine.state == MatchStateMachine.State.ACTIVE_HEAT else -1,
	}


func _public_players() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var peer_ids := machine.players.keys()
	peer_ids.sort()
	for peer_value in peer_ids:
		var player := machine.players[peer_value] as PlayerMatchState
		if player.connected:
			result.append({
				"peer_id": player.peer_id,
				"display_name": player.display_name,
				"ship_color": player.ship_color,
				"ship_pattern": player.ship_pattern,
			})
	return result


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


func overtime_observation() -> Vector3i:
	# Logging needs only the deadline and heat identity, never a full snapshot.
	var start_tick := machine.state_entered_tick + roundi(overtime_start_seconds * GameConstants.PHYSICS_TICKS_PER_SECOND)
	return Vector3i(start_tick, machine.round_number, machine.heat_number)
