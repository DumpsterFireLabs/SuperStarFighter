class_name NetworkSessionOwner
extends RefCounted

# Owns one transport/admission lifetime. RPC endpoints stay on NetworkBridge.
const AuthenticationAttemptLimiterScript = preload("res://src/shared/network/authentication_attempt_limiter.gd")
var bridge: NetworkBridge

var role: NetworkBridge.Role = NetworkBridge.Role.NONE
var local_peer_id: int = 0
var latest_lobby_state: Dictionary = {}
var last_error: String = ""
var _configuration: Dictionary = {}
var _enet_peer: ENetMultiplayerPeer
var _lan_discovery: LanDiscoveryService
var _pending_handshakes := HandshakeRegistry.new()
var _pending_disconnects: Dictionary = {}
var _rate_limiter := InputRateLimiter.new()
var _control_rate_limiter := RequestRateLimiter.new()
var _authentication_attempt_limiter := AuthenticationAttemptLimiterScript.new()
var _connection_attempt_limiter := AuthenticationAttemptLimiterScript.new(
	NetworkProtocol.CONNECTION_ATTEMPT_LIMIT,
	NetworkProtocol.CONNECTION_ATTEMPT_WINDOW_SECONDS,
	NetworkProtocol.CONNECTION_ATTEMPT_COOLDOWN_SECONDS
)
var _peer_auth_sources: Dictionary = {}
var _blocked_sources: Dictionary = {}
var _ban_file_path: String = ""
var _malformed_control_strikes: Dictionary = {}
var _client_name: String = "Pilot"
var _client_protocol_version: int = GameConstants.PROTOCOL_VERSION
var _client_password: String = ""
var _discovery_instance_id: String = ""


func _init(network_bridge: NetworkBridge) -> void:
	bridge = network_bridge


func start_server(configuration: Dictionary) -> Error:
	stop()
	role = NetworkBridge.Role.SERVER
	var lobby_password := String(configuration.get("lobby_password", ""))
	if not NetworkProtocol.is_valid_lobby_password(lobby_password):
		last_error = "A lobby password containing 1–%d printable characters is required." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH
		role = NetworkBridge.Role.NONE
		return ERR_INVALID_PARAMETER
	_configuration = configuration.duplicate(true)
	_configuration.erase("admin_password")
	_configuration.erase("admin_password_file")
	_configuration.erase("lobby_password_file")
	_ban_file_path = String(configuration.get("ban_file", "user://server-bans.json"))
	_load_blocked_sources()
	var match_config := MatchConfig.new()
	match_config.port = int(configuration.get("port", GameConstants.DEFAULT_PORT))
	if match_config.port == LanDiscoveryProtocol.DISCOVERY_PORT:
		last_error = "UDP port %d is reserved for LAN server discovery." % LanDiscoveryProtocol.DISCOVERY_PORT
		role = NetworkBridge.Role.NONE
		return ERR_INVALID_PARAMETER
	match_config.max_players = int(configuration.get("max_players", GameConstants.DEFAULT_MAX_PLAYERS))
	match_config.rounds_to_win = int(configuration.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN))
	match_config.competitive_view = bool(configuration.get("competitive_view", false))
	if bool(configuration.get("test_fast_match", false)):
		match_config.draft_duration_seconds = 0.75
		match_config.countdown_duration_seconds = 0.25
		match_config.heat_result_duration_seconds = 0.25
		match_config.round_result_duration_seconds = 0.25
	bridge.lobby = ServerLobby.new(match_config)
	bridge.world = AuthoritativeWorld.new()
	var preset_id := String(configuration.get("match_preset", ""))
	if not preset_id.is_empty():
		var preset_result := preload("res://src/shared/lobby/match_presets.gd").apply(bridge.lobby, ServerLobby.OPERATOR_AUTHORITY_ID, preset_id)
		if not bool(preset_result.ok):
			last_error = String(preset_result.error)
			role = NetworkBridge.Role.NONE
			return ERR_INVALID_PARAMETER
		bridge._activate_added_npcs(preset_result)
	bridge.match_coordinator = null
	bridge._reset_metrics_window()
	bridge._metrics_window = 0
	bridge._logged_overtime_key = ""
	_discovery_instance_id = "%x-%x" % [Time.get_ticks_msec(), bridge.get_instance_id()]
	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_server(
		match_config.port,
		match_config.max_players + NetworkProtocol.AUTH_RESERVED_PEERS,
		NetworkProtocol.CHANNEL_COUNT
	)
	if error != OK:
		last_error = "Could not bind UDP port %d (error %d)." % [match_config.port, error]
		bridge._log("error", "server_bind_failed", {"port": match_config.port, "error": error})
		role = NetworkBridge.Role.NONE
		return error
	bridge.multiplayer.multiplayer_peer = _enet_peer
	if not bridge.multiplayer.peer_connected.is_connected(bridge._on_server_peer_connected):
		bridge.multiplayer.peer_connected.connect(bridge._on_server_peer_connected)
	if not bridge.multiplayer.peer_disconnected.is_connected(bridge._on_server_peer_disconnected):
		bridge.multiplayer.peer_disconnected.connect(bridge._on_server_peer_disconnected)
	_lan_discovery = LanDiscoveryService.new()
	_lan_discovery.name = "LanDiscoveryResponder"
	bridge.add_child(_lan_discovery)
	var discovery_error := _lan_discovery.start_responder(_lan_discovery_payload)
	if discovery_error != OK:
		bridge._log("warning", "lan_discovery_unavailable", {
			"port": LanDiscoveryProtocol.DISCOVERY_PORT,
			"error": discovery_error,
		})
	bridge._log("info", "server_started", {
		"port": match_config.port,
		"max_players": match_config.max_players,
		"rounds_to_win": match_config.rounds_to_win,
	})
	return OK


func start_client(
	host: String,
	port: int,
	display_name: String,
	protocol_version: int = GameConstants.PROTOCOL_VERSION,
	lobby_password: String = ""
) -> Error:
	stop()
	role = NetworkBridge.Role.CLIENT
	_client_name = display_name
	_client_protocol_version = protocol_version
	_client_password = lobby_password
	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_client(host, port, NetworkProtocol.CHANNEL_COUNT)
	if error != OK:
		last_error = "Could not connect to %s:%d (error %d)." % [host, port, error]
		role = NetworkBridge.Role.NONE
		return error
	bridge.multiplayer.multiplayer_peer = _enet_peer
	if not bridge.multiplayer.connected_to_server.is_connected(bridge._on_client_transport_connected):
		bridge.multiplayer.connected_to_server.connect(bridge._on_client_transport_connected)
	if not bridge.multiplayer.connection_failed.is_connected(bridge._on_client_connection_failed):
		bridge.multiplayer.connection_failed.connect(bridge._on_client_connection_failed)
	if not bridge.multiplayer.server_disconnected.is_connected(bridge._on_client_server_disconnected):
		bridge.multiplayer.server_disconnected.connect(bridge._on_client_server_disconnected)
	return OK


func stop() -> void:
	# Mark teardown before closing ENet. Closing a live client can synchronously emit
	# server_disconnected; that callback must see NONE instead of recursively
	# entering the UI's disconnect path while this cleanup is still in progress.
	var stopped_role := role
	role = NetworkBridge.Role.NONE
	if stopped_role == NetworkBridge.Role.SERVER and _enet_peer != null:
		bridge._log("info", "server_shutdown", {
			"connected_peers": bridge.lobby.human_count() if bridge.lobby != null else 0,
			"participant_records": bridge.lobby.players.size() if bridge.lobby != null else 0,
			"active_ships": bridge.world.combatants.size() if bridge.world != null else 0,
			"active_projectiles": bridge.world.projectile_registry.size() if bridge.world != null else 0,
			"pending_handshakes": _pending_handshakes.size(),
		})
	if _enet_peer != null:
		_enet_peer.close()
	_enet_peer = null
	if _lan_discovery != null:
		_lan_discovery.stop()
		_lan_discovery.queue_free()
		_lan_discovery = null
	if bridge.is_inside_tree() and bridge.multiplayer.multiplayer_peer != null:
		bridge.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending_handshakes.clear()
	_pending_disconnects.clear()
	_rate_limiter.clear()
	_control_rate_limiter.clear()
	_authentication_attempt_limiter.clear()
	_connection_attempt_limiter.clear()
	_peer_auth_sources.clear()
	_blocked_sources.clear()
	_ban_file_path = ""
	_malformed_control_strikes.clear()
	bridge.replication.clear()
	_client_password = ""
	_configuration.clear()
	local_peer_id = 0
	latest_lobby_state.clear()
	bridge.match_coordinator = null
	bridge.npc_controller.clear()


func _lan_discovery_payload() -> Dictionary:
	return {
		"instance_id": _discovery_instance_id,
		"protocol_version": GameConstants.PROTOCOL_VERSION,
		"server_name": String(_configuration.get("server_name", "Super Star Fighter Server")),
		"game_port": int(_configuration.get("port", GameConstants.DEFAULT_PORT)),
		"human_count": bridge.lobby.human_count() if bridge.lobby != null else 0,
		"npc_count": bridge.lobby.npc_count() if bridge.lobby != null else 0,
		"player_limit": bridge.lobby.player_limit if bridge.lobby != null else int(_configuration.get("max_players", GameConstants.DEFAULT_MAX_PLAYERS)),
		"match_active": bridge.lobby.match_active if bridge.lobby != null else false,
		"password_required": true,
	}


func get_network_statistics() -> Dictionary:
	var unavailable := {
		"rtt_ms": -1,
		"rtt_variance_ms": 0,
		"packet_loss_percent": 0.0,
		"packet_throttle_percent": 100.0,
	}
	if role != NetworkBridge.Role.CLIENT or _enet_peer == null:
		return unavailable
	var server_peer := _enet_peer.get_peer(NetworkProtocol.SERVER_PEER_ID)
	if server_peer == null:
		return unavailable
	return {
		"rtt_ms": int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)),
		"rtt_variance_ms": int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)),
		"packet_loss_percent": (
			float(server_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS))
			/ ENetPacketPeer.PACKET_LOSS_SCALE
			* 100.0
		),
		"packet_throttle_percent": (
			float(server_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
			/ ENetPacketPeer.PACKET_THROTTLE_SCALE
			* 100.0
		),
	}


func _on_server_peer_connected(peer_id: int) -> void:
	var source := _peer_auth_source(peer_id)
	_peer_auth_sources[peer_id] = source
	var now := bridge._now_seconds()
	if _blocked_sources.has(_normalized_source(source)):
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_BLOCKED)
		return
	if (
		_connection_attempt_limiter.is_blocked(source, now) or
		_connection_attempt_limiter.register_failure(source, now)
	):
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	if _pending_auth_count_for_source(source, peer_id) >= NetworkProtocol.AUTH_MAX_PENDING_PER_SOURCE:
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	if _authentication_attempt_limiter.is_blocked(source, now):
		_pending_handshakes.begin(peer_id, now)
		_reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	var challenge := Crypto.new().generate_random_bytes(NetworkProtocol.AUTH_CHALLENGE_BYTES).hex_encode()
	_pending_handshakes.begin(peer_id, now, challenge)
	bridge.authentication_challenge.rpc_id(peer_id, challenge)


func _on_server_peer_disconnected(peer_id: int) -> void:
	_pending_handshakes.complete(peer_id)
	_peer_auth_sources.erase(peer_id)
	_pending_disconnects.erase(peer_id)
	_rate_limiter.remove_peer(peer_id)
	_control_rate_limiter.remove_peer(peer_id)
	_malformed_control_strikes.erase(peer_id)
	if bridge.match_coordinator != null:
		bridge.match_coordinator.disconnect_peer(peer_id)
		bridge._drain_match_coordinator()
	var departed := bridge.lobby.remove(peer_id) if bridge.lobby != null else null
	var replacement_npcs: Array[PlayerMatchState] = []
	if departed != null and bridge.match_coordinator == null:
		replacement_npcs = bridge.lobby.restore_npc_fill()
		bridge._activate_added_npcs({"added_npcs": replacement_npcs})
	if bridge.world != null:
		bridge.world.remove_peer(peer_id)
	if departed != null:
		bridge._broadcast_lobby_state()
		bridge.server_peer_departed.emit(peer_id)
		bridge._log("info", "peer_left", {"peer_id": peer_id})


func _peer_auth_source(peer_id: int) -> String:
	if _enet_peer == null:
		return "peer:%d" % peer_id
	var packet_peer := _enet_peer.get_peer(peer_id)
	if packet_peer == null:
		return "peer:%d" % peer_id
	var address := packet_peer.get_remote_address()
	return address if not address.is_empty() else "peer:%d" % peer_id


func _pending_auth_count_for_source(source: String, excluded_peer_id: int) -> int:
	var normalized := _normalized_source(source)
	var count := 0
	for peer_value in _peer_auth_sources.keys():
		var peer_id := int(peer_value)
		if peer_id != excluded_peer_id and _pending_handshakes.has(peer_id) and _normalized_source(String(_peer_auth_sources[peer_id])) == normalized:
			count += 1
	return count


func operator_kick(peer_id: int, block_source: bool = false) -> Dictionary:
	if role != NetworkBridge.Role.SERVER or bridge.lobby == null:
		return {"ok": false, "error": "The server is not running."}
	var player := bridge.lobby.players.get(peer_id) as PlayerMatchState
	if player == null or player.is_npc:
		return {"ok": false, "error": "That human player is not connected."}
	var source := String(_peer_auth_sources.get(peer_id, ""))
	if block_source:
		var block_result := operator_block_source(source)
		if not block_result.ok:
			return block_result
	var reason := NetworkProtocol.REJECT_BLOCKED if block_source else NetworkProtocol.REJECT_KICKED
	bridge.connection_rejected.rpc_id(peer_id, reason, NetworkProtocol.rejection_message(reason))
	_pending_disconnects[peer_id] = bridge._now_seconds() + 0.1
	bridge._log("warning", "operator_peer_removed", {
		"peer_id": peer_id,
		"display_name": player.display_name,
		"blocked": block_source,
	})
	return {"ok": true, "peer_id": peer_id, "source": source, "blocked": block_source}


func operator_block_source(source: String) -> Dictionary:
	var normalized := _normalized_source(source)
	if not _is_valid_block_source(normalized):
		return {"ok": false, "error": "A bounded source address is required."}
	if not _blocked_sources.has(normalized) and _blocked_sources.size() >= NetworkProtocol.MAX_BLOCKED_SOURCES:
		return {"ok": false, "error": "The blocked-source limit has been reached."}
	_blocked_sources[normalized] = true
	var save_error := _save_blocked_sources()
	if not save_error.is_empty():
		_blocked_sources.erase(normalized)
		return {"ok": false, "error": save_error}
	return {"ok": true, "source": normalized}


func operator_unblock_source(source: String) -> Dictionary:
	var normalized := _normalized_source(source)
	if not _blocked_sources.erase(normalized):
		return {"ok": false, "error": "That source is not blocked."}
	var save_error := _save_blocked_sources()
	if not save_error.is_empty():
		_blocked_sources[normalized] = true
		return {"ok": false, "error": save_error}
	return {"ok": true, "source": normalized}


func operator_set_lobby_password(password: String) -> Dictionary:
	if not NetworkProtocol.is_valid_lobby_password(password):
		return {"ok": false, "error": "Lobby password must contain 1–%d printable characters." % NetworkProtocol.MAX_LOBBY_PASSWORD_LENGTH}
	_configuration.lobby_password = password
	bridge._log("info", "operator_setting_changed", {"setting": "lobby_password"})
	return {"ok": true, "setting": "lobby_password"}


func _load_blocked_sources() -> void:
	_blocked_sources.clear()
	if _ban_file_path.is_empty() or not FileAccess.file_exists(_ban_file_path):
		return
	var file := FileAccess.open(_ban_file_path, FileAccess.READ)
	if file == null:
		bridge._log("warning", "ban_file_read_failed", {"path": _ban_file_path})
		return
	if file.get_length() > NetworkProtocol.MAX_BAN_FILE_BYTES:
		bridge._log("warning", "ban_file_too_large", {"path": _ban_file_path})
		return
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Array:
		bridge._log("warning", "ban_file_invalid", {"path": _ban_file_path})
		return
	for value in decoded:
		if _blocked_sources.size() >= NetworkProtocol.MAX_BLOCKED_SOURCES:
			break
		var source := _normalized_source(String(value))
		if _is_valid_block_source(source):
			_blocked_sources[source] = true


func _save_blocked_sources() -> String:
	if _ban_file_path.is_empty():
		return "No ban-file path is configured."
	var target_path := ProjectSettings.globalize_path(_ban_file_path)
	var temporary_path := target_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return "Could not write the temporary ban file."
	var sources: Array = _blocked_sources.keys()
	sources.sort()
	file.store_string(JSON.stringify(sources, "  "))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return "Could not flush the temporary ban file."
	var replace_error := DirAccess.rename_absolute(temporary_path, target_path)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return "Could not atomically replace the ban file."
	return ""


static func _normalized_source(source: String) -> String:
	var normalized := source.strip_edges().to_lower()
	if normalized.begins_with("[") and normalized.ends_with("]"):
		normalized = normalized.substr(1, normalized.length() - 2)
	return normalized


static func _is_valid_block_source(source: String) -> bool:
	return not source.is_empty() and source.length() <= 64 and source.is_valid_ip_address()


func _on_client_transport_connected() -> void:
	# The server supplies a fresh challenge before the client sends credentials.
	pass


func _on_client_connection_failed() -> void:
	if role != NetworkBridge.Role.CLIENT:
		return
	last_error = "Could not reach the server."
	bridge.client_connection_lost.emit(last_error)


func _on_client_server_disconnected() -> void:
	if role != NetworkBridge.Role.CLIENT:
		return
	var message := last_error if not last_error.is_empty() else NetworkProtocol.rejection_message(NetworkProtocol.REJECT_SERVER_CLOSED)
	local_peer_id = 0
	bridge.client_connection_lost.emit(message)


func _process_pending_connections() -> void:
	var now := bridge._now_seconds()
	if _pending_handshakes.size() > 0:
		for peer_id in _pending_handshakes.expired(now):
			_reject_connection(peer_id, NetworkProtocol.REJECT_HANDSHAKE_TIMEOUT)
	if not _pending_disconnects.is_empty():
		for peer_value in _pending_disconnects.keys():
			var peer_id := int(peer_value)
			if now >= float(_pending_disconnects[peer_id]):
				_pending_disconnects.erase(peer_id)
				if _enet_peer != null:
					_enet_peer.disconnect_peer(peer_id)


func _reject_connection(peer_id: int, reason: StringName) -> void:
	var message := NetworkProtocol.rejection_message(reason)
	bridge.connection_rejected.rpc_id(peer_id, reason, message)
	_pending_handshakes.complete(peer_id)
	_pending_disconnects[peer_id] = bridge._now_seconds() + 0.1
	bridge._log("warning", "connection_rejected", {"peer_id": peer_id, "reason": String(reason)})


func _accept_control_request(peer_id: int, request_name: String) -> bool:
	if bridge.lobby == null or not bridge.lobby.players.has(peer_id):
		bridge._log("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": "request_before_handshake"})
		_reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	var decision := _control_rate_limiter.register(peer_id, bridge._now_seconds())
	if decision == RequestRateLimiter.Decision.DISCONNECT:
		bridge._log("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": "%s_rate_limit" % request_name})
		_reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	return decision == RequestRateLimiter.Decision.ACCEPT


func _reject_malformed_control(peer_id: int, detail: String) -> void:
	var strikes := int(_malformed_control_strikes.get(peer_id, 0)) + 1
	_malformed_control_strikes[peer_id] = strikes
	if strikes >= NetworkProtocol.TRAFFIC_STRIKES_BEFORE_DISCONNECT:
		bridge._log("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": detail})
		_reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	bridge._reject_request(peer_id, detail)


func complete_admission(sender_id: int, display_name: String) -> void:
	var result := bridge.lobby.admit(sender_id, display_name)
	if not result.ok:
		_reject_connection(sender_id, result.reason)
		return
	_pending_handshakes.complete(sender_id)
	bridge._remove_npc_entities(result.get("removed_npc_ids", []) as Array)
	var player := result.player as PlayerMatchState
	bridge.world.add_peer(sender_id)
	bridge.world.input_timeouts[sender_id] = GameConstants.INPUT_STALE_SECONDS
	if bridge.match_coordinator != null:
		bridge.match_coordinator.add_late_spectator(player)
	bridge.server_welcome.rpc_id(sender_id, sender_id, bridge.lobby.serialize())
	if bridge.match_coordinator != null:
		bridge.match_event.rpc_id(
			sender_id,
			&"STATE_CHANGED",
			bridge.world.server_tick,
			bridge.match_coordinator.current_state_payload()
		)
	bridge._outbound_bytes += 64
	bridge._broadcast_lobby_state()
	bridge.server_peer_admitted.emit(sender_id, player)
	bridge._log("info", "peer_joined", {"peer_id": sender_id, "display_name": player.display_name, "spectator": player.spectator})
	if bool(_configuration.get("auto_start", false)) and bridge.lobby.participant_count() >= GameConstants.MIN_PLAYERS and not bridge.lobby.match_active:
		for peer_id in bridge.lobby.human_peer_ids():
			bridge.lobby.request_ready(peer_id, true)
		var start_result := bridge.lobby.request_start(bridge.lobby.leader_id)
		if start_result.ok:
			bridge._activate_added_npcs(start_result)
			bridge._broadcast_lobby_state()
			bridge._start_match_coordinator(bridge.lobby.leader_id)
