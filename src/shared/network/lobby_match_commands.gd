extends RefCounted

## Lobby and match commands. They run only after NetworkBridge has admitted and
## validated the sender, take the lobby (and the match coordinator where they
## need it) explicitly, and return a LobbyCommandOutcome describing what should
## happen. NetworkBridge._apply_command_outcome applies it, so nothing here
## touches the bridge, the world or the transport.

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const MatchPresetsScript = preload("res://src/shared/lobby/match_presets.gd")


## Applies one scalar setting from LobbySettings. `value` must already have the
## setting's type.
static func apply_setting(lobby: ServerLobby, sender_id: int, setting_id: StringName, value: Variant) -> LobbyCommandOutcome:
	var result := LobbySettings.apply(lobby, sender_id, setting_id, value)
	if not result.ok:
		return LobbyCommandOutcome.rejected(String(result.error))
	var outcome := LobbyCommandOutcome.new()
	# Rounds, player limit and NPC toggles report no "changed" flag; they
	# always republish, as they did before the descriptor table existed.
	outcome.broadcast_lobby = bool(result.get("changed", true))
	outcome.removed_npc_ids = result.get("removed_npc_ids", []) as Array
	outcome.added_npc_result = result
	return outcome


static func request_team_assignment(lobby: ServerLobby, sender_id: int, peer_id: int, team_selection: int) -> LobbyCommandOutcome:
	return _from_result(lobby.request_team_assignment(sender_id, peer_id, team_selection))


static func request_map_pool(lobby: ServerLobby, sender_id: int, pool: Array) -> LobbyCommandOutcome:
	return _from_result(lobby.request_map_pool(sender_id, pool))


static func request_arena_effects(lobby: ServerLobby, sender_id: int, settings: Dictionary) -> LobbyCommandOutcome:
	return _from_result(lobby.request_arena_effects(sender_id, settings))


static func request_player_color(lobby: ServerLobby, sender_id: int, random_color: bool, color_value: String) -> LobbyCommandOutcome:
	return _from_result(lobby.request_player_color(sender_id, random_color, color_value))


static func request_player_appearance(lobby: ServerLobby, sender_id: int, random_color: bool, color_value: String, pattern_value: String) -> LobbyCommandOutcome:
	var pattern := ShipAppearanceScript.normalized_pattern(pattern_value)
	return _from_result(lobby.request_player_appearance(sender_id, random_color, color_value, pattern))


static func request_npc_difficulty(lobby: ServerLobby, sender_id: int, npc_peer_id: int, difficulty: int) -> LobbyCommandOutcome:
	return _from_result(lobby.request_npc_difficulty(sender_id, npc_peer_id, difficulty))


static func request_ready_state(lobby: ServerLobby, sender_id: int, ready: bool) -> LobbyCommandOutcome:
	return _from_result(lobby.request_ready(sender_id, ready))


static func request_eject_player(lobby: ServerLobby, sender_id: int, target_peer_id: int) -> LobbyCommandOutcome:
	var result := lobby.request_eject(sender_id, target_peer_id)
	if not result.ok:
		return LobbyCommandOutcome.rejected(String(result.error))
	var outcome := LobbyCommandOutcome.new()
	outcome.eject_peer_id = target_peer_id
	outcome.added_npc_result = result
	outcome.broadcast_lobby = true
	return outcome


static func request_start_match(lobby: ServerLobby, sender_id: int) -> LobbyCommandOutcome:
	var result := lobby.request_start(sender_id)
	if not result.ok:
		return LobbyCommandOutcome.rejected(String(result.error))
	var outcome := LobbyCommandOutcome.new()
	outcome.added_npc_result = result
	outcome.broadcast_lobby = true
	outcome.start_match = true
	return outcome


static func request_match_preset(lobby: ServerLobby, sender_id: int, preset_id: String) -> LobbyCommandOutcome:
	var result: Dictionary = MatchPresetsScript.apply(lobby, sender_id, preset_id)
	if not bool(result.ok):
		return LobbyCommandOutcome.rejected(String(result.error))
	var outcome := LobbyCommandOutcome.new()
	outcome.removed_npc_ids = result.get("removed_npc_ids", []) as Array
	outcome.added_npc_result = result
	outcome.broadcast_lobby = true
	return outcome


## `can_control` is whether the sender leads the lobby or holds admin rights.
static func request_rematch(can_control: bool) -> LobbyCommandOutcome:
	if not can_control:
		return LobbyCommandOutcome.rejected("Only the lobby leader or an authenticated admin may start a fresh rematch.")
	var outcome := LobbyCommandOutcome.new()
	outcome.fresh_rematch = true
	return outcome


static func request_return_to_lobby(coordinator: AuthoritativeMatchCoordinator, can_control: bool) -> LobbyCommandOutcome:
	if not can_control:
		return LobbyCommandOutcome.rejected("Only the lobby leader or an authenticated admin may return the match to the lobby.")
	if coordinator == null or not coordinator.return_to_lobby():
		return LobbyCommandOutcome.rejected("Return to lobby is only available from the final results screen.")
	var outcome := LobbyCommandOutcome.new()
	outcome.drain_coordinator = true
	outcome.release_finished_match = true
	return outcome


static func request_extend_match(coordinator: AuthoritativeMatchCoordinator, can_control: bool) -> LobbyCommandOutcome:
	if not can_control:
		return LobbyCommandOutcome.rejected("Only the lobby leader or an authenticated admin may extend the match.")
	if coordinator == null or not coordinator.extend_match():
		return LobbyCommandOutcome.rejected("Match extension is only available from final results with at least two competing participants.")
	var outcome := LobbyCommandOutcome.new()
	outcome.drain_coordinator = true
	return outcome


static func request_match_paused(coordinator: AuthoritativeMatchCoordinator, sender_id: int, paused: bool) -> LobbyCommandOutcome:
	if coordinator == null or not coordinator.request_pause(sender_id, paused):
		return LobbyCommandOutcome.rejected("Only the host may pause or resume a running match.")
	var outcome := LobbyCommandOutcome.new()
	outcome.drain_coordinator = true
	return outcome


## Shared shape of most lobby requests: refuse, or republish when changed.
static func _from_result(result: Dictionary) -> LobbyCommandOutcome:
	if not result.ok:
		return LobbyCommandOutcome.rejected(String(result.error))
	var outcome := LobbyCommandOutcome.new()
	outcome.broadcast_lobby = bool(result.get("changed", false))
	return outcome
