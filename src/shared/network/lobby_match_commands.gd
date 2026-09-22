extends RefCounted

## Lobby/match commands execute only after the RPC owner admits and validates
## the sender. A weak link prevents a bridge/service ownership cycle.
const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
var _owner: WeakRef
var _bridge: Node:
	get: return _owner.get_ref() as Node
var lobby: ServerLobby:
	get: return _bridge.lobby
var world: AuthoritativeWorld:
	get: return _bridge.world
var session: NetworkSessionOwner:
	get: return _bridge.session
var match_coordinator: AuthoritativeMatchCoordinator:
	get: return _bridge.match_coordinator


func _init(owner: Node) -> void:
	_owner = weakref(owner)


func request_lobby_config(sender_id: int, rounds_to_win: int) -> void:
	var result := lobby.request_rounds_to_win(sender_id, rounds_to_win)
	if result.ok:
		_bridge._broadcast_lobby_state()
	else:
		_bridge._send_request_rejected(sender_id, result.error)


func request_player_limit(sender_id: int, player_limit: int) -> void:
	var result := lobby.request_player_limit(sender_id, player_limit)
	if result.ok:
		_bridge._remove_npc_entities(result.get("removed_npc_ids", []) as Array)
		_bridge._activate_added_npcs(result)
		_bridge._broadcast_lobby_state()
	else:
		_bridge._send_request_rejected(sender_id, result.error)


func request_npcs_enabled(sender_id: int, enabled: bool) -> void:
	var result := lobby.request_npcs_enabled(sender_id, enabled)
	if result.ok:
		_bridge._remove_npc_entities(result.get("removed_npc_ids", []) as Array)
		_bridge._activate_added_npcs(result)
		_bridge._broadcast_lobby_state()
	else:
		_bridge._send_request_rejected(sender_id, result.error)


func request_game_mode(sender_id: int, mode: int) -> void:
	var result := lobby.request_game_mode(sender_id, mode)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_team_count(sender_id: int, team_count: int) -> void:
	var result := lobby.request_team_count(sender_id, team_count)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_team_assignment(sender_id: int, peer_id: int, team_selection: int) -> void:
	var result := lobby.request_team_assignment(sender_id, peer_id, team_selection)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_arena_effects(sender_id: int, settings: Dictionary) -> void:
	var result := lobby.request_arena_effects(sender_id, settings)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_random_spawn_powerups(sender_id: int, enabled: bool) -> void:
	var result := lobby.request_random_spawn_powerups(sender_id, enabled)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_player_color(sender_id: int, random_color: bool, color_value: String) -> void:
	var result := lobby.request_player_color(sender_id, random_color, color_value)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_player_appearance(sender_id: int, random_color: bool, color_value: String, pattern_value: String) -> void:
	var pattern := ShipAppearanceScript.normalized_pattern(pattern_value)
	var result := lobby.request_player_appearance(sender_id, random_color, color_value, pattern)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_npc_difficulty(sender_id: int, npc_peer_id: int, difficulty: int) -> void:
	var result := lobby.request_npc_difficulty(sender_id, npc_peer_id, difficulty)
	if result.ok:
		if bool(result.get("changed", false)):
			_bridge._broadcast_lobby_state()
	else:
		_bridge._send_request_rejected(sender_id, result.error)


func request_all_npc_difficulty(sender_id: int, difficulty: int) -> void:
	var result := lobby.request_all_npc_difficulty(sender_id, difficulty)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_random_powerup_interval(sender_id: int, seconds: float) -> void:
	var result := lobby.request_random_powerup_interval(sender_id, seconds)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_random_powerups_permanent(sender_id: int, permanent: bool) -> void:
	var result := lobby.request_random_powerups_permanent(sender_id, permanent)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_competitive_view(sender_id: int, enabled: bool) -> void:
	var result := lobby.request_competitive_view(sender_id, enabled)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_silly_mode(sender_id: int, enabled: bool) -> void:
	var result := lobby.request_silly_mode(sender_id, enabled)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_overtime_start(sender_id: int, seconds: float) -> void:
	var result := lobby.request_overtime_start(sender_id, seconds)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_ready_state(sender_id: int, ready: bool) -> void:
	var result := lobby.request_ready(sender_id, ready)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
	elif bool(result.get("changed", false)):
		_bridge._broadcast_lobby_state()


func request_eject_player(sender_id: int, target_peer_id: int) -> void:
	var result := lobby.request_eject(sender_id, target_peer_id)
	if not result.ok:
		_bridge._send_request_rejected(sender_id, result.error)
		return
	if world != null:
		world.remove_peer(target_peer_id)
	session.forget_admission(target_peer_id)
	_bridge._activate_added_npcs(result)
	var reason := NetworkProtocol.REJECT_EJECTED
	_bridge.connection_rejected.rpc_id(target_peer_id, reason, NetworkProtocol.rejection_message(reason))
	session.schedule_disconnect(target_peer_id)
	_bridge._broadcast_lobby_state()
	_bridge.server_peer_departed.emit(target_peer_id)
	_bridge._log("info", "peer_ejected", {"leader_id": sender_id, "peer_id": target_peer_id})


func request_start_match(sender_id: int) -> void:
	var result := lobby.request_start(sender_id)
	if result.ok:
		_bridge._activate_added_npcs(result)
		_bridge._broadcast_lobby_state()
		_bridge._start_match_coordinator(sender_id)
	else:
		_bridge._send_request_rejected(sender_id, result.error)


func request_match_preset(sender_id: int, preset_id: String) -> void:
	var result := preload("res://src/shared/lobby/match_presets.gd").apply(lobby, sender_id, preset_id)
	if not bool(result.ok):
		_bridge._send_request_rejected(sender_id, String(result.error))
		return
	_bridge._remove_npc_entities(result.get("removed_npc_ids", []) as Array)
	_bridge._activate_added_npcs(result)
	_bridge._broadcast_lobby_state()


func request_rematch(sender_id: int) -> void:
	var result: Dictionary = _bridge._prepare_fresh_rematch(sender_id)
	if not bool(result.ok):
		_bridge._send_request_rejected(sender_id, String(result.error))
		return
	_bridge._broadcast_lobby_state()
	_bridge._broadcast_match_event(&"MATCH_START_ACCEPTED", {"leader_id": sender_id, "fresh_rematch": true})
	_bridge._drain_match_coordinator()


func request_return_to_lobby(sender_id: int) -> void:
	if sender_id != lobby.leader_id:
		_bridge._send_request_rejected(sender_id, "Only the lobby leader may return the match to the lobby.")
		return
	if match_coordinator == null or not match_coordinator.return_to_lobby():
		_bridge._send_request_rejected(sender_id, "Return to lobby is only available from the final results screen.")
		return
	_bridge._drain_match_coordinator()
	if match_coordinator.is_finished():
		_bridge.match_coordinator = null
		_bridge._broadcast_lobby_state()


func request_extend_match(sender_id: int) -> void:
	if sender_id != lobby.leader_id:
		_bridge._send_request_rejected(sender_id, "Only the lobby leader may extend the match.")
		return
	if match_coordinator == null or not match_coordinator.extend_match():
		_bridge._send_request_rejected(sender_id, "Match extension is only available from final results with at least two competing participants.")
		return
	_bridge._drain_match_coordinator()


func request_match_paused(sender_id: int, paused: bool) -> void:
	if match_coordinator == null or not match_coordinator.request_pause(sender_id, paused):
		_bridge._send_request_rejected(sender_id, "Only the host may pause or resume a running match.")
		return
	_bridge._drain_match_coordinator()
