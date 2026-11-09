class_name OperatorCommands
extends RefCounted

## Operator console logic shared by the loopback admin port and the in-game
## admin panel. These functions read and change the lobby and session they are
## given and return the console's result dictionaries; NetworkBridge keeps the
## public operator_* entry points and applies the world and replication side
## effects (NPC entities, lobby broadcast, logging, match restarts).

const MAX_LISTED_BLOCKED_SOURCES: int = 256


static func status_report(lobby: ServerLobby, session: NetworkSessionOwner, world: AuthoritativeWorld, metrics: ServerTickMetrics, logging_status: Dictionary, server_running: bool, now_usec: int) -> Dictionary:
	var lobby_summary := lobby.serialize() if lobby != null else {}
	lobby_summary.erase("players")
	return {
		"ok": server_running,
		"server_name": String(session.configuration_value("server_name", "")),
		"port": int(session.configuration_value("port", 0)),
		"auto_start": bool(session.configuration_value("auto_start", false)),
		"match_active": lobby.match_active if lobby != null else false,
		"server_tick": world.server_tick if world != null else 0,
		"human_count": lobby.human_count() if lobby != null else 0,
		"npc_count": lobby.npc_count() if lobby != null else 0,
		"active_projectiles": world.projectile_registry.size() if world != null else 0,
		"blocked_source_count": session.blocked_sources().size(),
		"uptime_seconds": metrics.uptime_seconds(now_usec) if server_running else 0.0,
		"metrics": metrics.latest.duplicate(true),
		"logging": logging_status,
		"metrics_age_seconds": metrics.window_age_seconds(now_usec) if not metrics.latest.is_empty() else -1.0,
		"lobby": lobby_summary,
	}


static func players_report(lobby: ServerLobby, session: NetworkSessionOwner, server_running: bool) -> Dictionary:
	var players: Array[Dictionary] = []
	var blocked_sources: Array = session.blocked_sources()
	blocked_sources.sort()
	var blocked_source_count := blocked_sources.size()
	if blocked_sources.size() > MAX_LISTED_BLOCKED_SOURCES:
		blocked_sources = blocked_sources.slice(0, MAX_LISTED_BLOCKED_SOURCES)
	if lobby != null:
		for peer_id in lobby.human_peer_ids():
			var player := lobby.players[peer_id] as PlayerMatchState
			players.append({
				"peer_id": peer_id,
				"display_name": player.display_name,
				"source": session.peer_source(peer_id),
				"ready": player.lobby_ready,
				"spectator": player.spectator,
			})
	return {
		"ok": server_running,
		"players": players,
		"blocked_sources": blocked_sources,
		"blocked_source_count": blocked_source_count,
		"blocked_sources_truncated": blocked_source_count > blocked_sources.size(),
	}


static func kick(lobby: ServerLobby, session: NetworkSessionOwner, peer_id: int, block_source: bool) -> Dictionary:
	var player := lobby.players.get(peer_id) as PlayerMatchState
	if player == null or player.is_npc:
		return {"ok": false, "error": "That human player is not connected."}
	return session.operator_kick(peer_id, player.display_name, block_source)


## Validates and applies one operator setting. Scalar lobby settings come from
## LobbySettings; the map pool and the session settings are handled here. On
## success the result is the lobby's (it may list NPCs to add or remove).
static func set_setting(lobby: ServerLobby, session: NetworkSessionOwner, setting: String, value: Variant) -> Dictionary:
	var setting_id := StringName(setting)
	if LobbySettings.has(setting_id):
		var typed := LobbySettings.coerce(setting_id, value)
		if not typed.ok:
			return {"ok": false, "error": typed.error}
		return LobbySettings.apply(lobby, ServerLobby.OPERATOR_AUTHORITY_ID, setting_id, typed.value)
	match setting:
		"map_pool":
			if not value is Array:
				return invalid_type(setting, "a list of map IDs")
			return lobby.request_map_pool(ServerLobby.OPERATOR_AUTHORITY_ID, value)
		"server_name":
			if not value is String:
				return invalid_type(setting, "text")
			var server_name := String(value).strip_edges()
			if not LanDiscoveryProtocol.is_valid_server_name(server_name):
				return {"ok": false, "error": "Server name is outside the supported range."}
			session.set_server_name(server_name)
			return {"ok": true, "changed": true}
		"auto_start":
			if not value is bool:
				return invalid_type(setting, "true or false")
			session.set_auto_start(bool(value))
			return {"ok": true, "changed": true}
	return {"ok": false, "error": "Unknown or restart-only setting: %s" % setting}


static func invalid_type(setting: String, expected: String) -> Dictionary:
	return {"ok": false, "error": "%s requires %s." % [setting, expected]}
