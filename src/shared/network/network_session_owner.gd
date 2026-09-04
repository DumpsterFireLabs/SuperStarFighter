class_name NetworkSessionOwner
extends RefCounted

# Owns one transport/admission lifetime. RPC endpoints stay on NetworkBridge.
const AuthenticationAttemptLimiterScript = preload("res://src/shared/network/authentication_attempt_limiter.gd")
signal log_requested(level: String, event_name: String, fields: Dictionary)
signal challenge_requested(peer_id: int, challenge: String)
signal rejection_requested(peer_id: int, reason: StringName, message: String)
signal connection_lost(message: String)
signal peer_departed(peer_id: int)
signal request_rejected(peer_id: int, detail: String)
signal stopped()

# Only Godot transport hosting and a detached discovery/status snapshot are
# supplied by the RPC shell. This owner cannot reach gameplay or replication.
var runtime: Node
var _status_provider: Callable

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


func _init(transport_runtime: Node, status_provider: Callable) -> void:
	runtime = transport_runtime
	_status_provider = status_provider


func start_server(configuration: Dictionary, match_config: MatchConfig) -> Error:
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
	_discovery_instance_id = "%x-%x" % [Time.get_ticks_msec(), runtime.get_instance_id()]
	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_server(
		match_config.port,
		match_config.max_players + NetworkProtocol.AUTH_RESERVED_PEERS,
		NetworkProtocol.CHANNEL_COUNT
	)
	if error != OK:
		last_error = "Could not bind UDP port %d (error %d)." % [match_config.port, error]
		log_requested.emit("error", "server_bind_failed", {"port": match_config.port, "error": error})
		role = NetworkBridge.Role.NONE
		return error
	runtime.multiplayer.multiplayer_peer = _enet_peer
	if not runtime.multiplayer.peer_connected.is_connected(_on_server_peer_connected):
		runtime.multiplayer.peer_connected.connect(_on_server_peer_connected)
	if not runtime.multiplayer.peer_disconnected.is_connected(_on_server_peer_disconnected):
		runtime.multiplayer.peer_disconnected.connect(_on_server_peer_disconnected)
	_lan_discovery = LanDiscoveryService.new()
	_lan_discovery.name = "LanDiscoveryResponder"
	runtime.add_child(_lan_discovery)
	var discovery_error := _lan_discovery.start_responder(_lan_discovery_payload)
	if discovery_error != OK:
		log_requested.emit("warning", "lan_discovery_unavailable", {
			"port": LanDiscoveryProtocol.DISCOVERY_PORT,
			"error": discovery_error,
		})
	log_requested.emit("info", "server_started", {
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
	runtime.multiplayer.multiplayer_peer = _enet_peer
	if not runtime.multiplayer.connected_to_server.is_connected(_on_client_transport_connected):
		runtime.multiplayer.connected_to_server.connect(_on_client_transport_connected)
	if not runtime.multiplayer.connection_failed.is_connected(_on_client_connection_failed):
		runtime.multiplayer.connection_failed.connect(_on_client_connection_failed)
	if not runtime.multiplayer.server_disconnected.is_connected(_on_client_server_disconnected):
		runtime.multiplayer.server_disconnected.connect(_on_client_server_disconnected)
	return OK


func stop() -> void:
	# Mark teardown before closing ENet. Closing a live client can synchronously emit
	# server_disconnected; that callback must see NONE instead of recursively
	# entering the UI's disconnect path while this cleanup is still in progress.
	var stopped_role := role
	role = NetworkBridge.Role.NONE
	_disconnect_transport_signals()
	if stopped_role == NetworkBridge.Role.SERVER and _enet_peer != null:
		var status: Dictionary = _status_provider.call()
		log_requested.emit("info", "server_shutdown", {
			"connected_peers": int(status.get("human_count", 0)),
			"participant_records": int(status.get("participant_records", 0)),
			"active_ships": int(status.get("active_ships", 0)),
			"active_projectiles": int(status.get("active_projectiles", 0)),
			"pending_handshakes": _pending_handshakes.size(),
		})
	if _enet_peer != null:
		_enet_peer.close()
	_enet_peer = null
	if _lan_discovery != null:
		_lan_discovery.stop()
		_lan_discovery.queue_free()
		_lan_discovery = null
	if runtime.is_inside_tree() and runtime.multiplayer.multiplayer_peer != null:
		runtime.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
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
	_client_password = ""
	_configuration.clear()
	local_peer_id = 0
	latest_lobby_state.clear()
	stopped.emit()


func _disconnect_transport_signals() -> void:
	if not runtime.is_inside_tree():
		return
	var bindings := {
		"peer_connected": _on_server_peer_connected,
		"peer_disconnected": _on_server_peer_disconnected,
		"connected_to_server": _on_client_transport_connected,
		"connection_failed": _on_client_connection_failed,
		"server_disconnected": _on_client_server_disconnected,
	}
	for signal_name in bindings:
		if runtime.multiplayer.is_connected(signal_name, bindings[signal_name]):
			runtime.multiplayer.disconnect(signal_name, bindings[signal_name])


func _lan_discovery_payload() -> Dictionary:
	var result := {
		"instance_id": _discovery_instance_id,
		"protocol_version": GameConstants.PROTOCOL_VERSION,
		"server_name": String(_configuration.get("server_name", "Super Star Fighter Server")),
		"game_port": int(_configuration.get("port", GameConstants.DEFAULT_PORT)),
		"password_required": true,
	}
	result.merge(_status_provider.call(), true)
	return result


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
	var now := _now_seconds()
	if _blocked_sources.has(_normalized_source(source)):
		_pending_handshakes.begin(peer_id, now)
		reject_connection(peer_id, NetworkProtocol.REJECT_BLOCKED)
		return
	if (
		_connection_attempt_limiter.is_blocked(source, now) or
		_connection_attempt_limiter.register_failure(source, now)
	):
		_pending_handshakes.begin(peer_id, now)
		reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	if _pending_auth_count_for_source(source, peer_id) >= NetworkProtocol.AUTH_MAX_PENDING_PER_SOURCE:
		_pending_handshakes.begin(peer_id, now)
		reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	if _authentication_attempt_limiter.is_blocked(source, now):
		_pending_handshakes.begin(peer_id, now)
		reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	var challenge := Crypto.new().generate_random_bytes(NetworkProtocol.AUTH_CHALLENGE_BYTES).hex_encode()
	_pending_handshakes.begin(peer_id, now, challenge)
	challenge_requested.emit(peer_id, challenge)


func _on_server_peer_disconnected(peer_id: int) -> void:
	_pending_handshakes.complete(peer_id)
	_peer_auth_sources.erase(peer_id)
	_pending_disconnects.erase(peer_id)
	_rate_limiter.remove_peer(peer_id)
	_control_rate_limiter.remove_peer(peer_id)
	_malformed_control_strikes.erase(peer_id)
	peer_departed.emit(peer_id)


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


func operator_kick(peer_id: int, display_name: String, block_source: bool = false) -> Dictionary:
	var source := String(_peer_auth_sources.get(peer_id, ""))
	if block_source:
		var block_result := operator_block_source(source)
		if not block_result.ok:
			return block_result
	var reason := NetworkProtocol.REJECT_BLOCKED if block_source else NetworkProtocol.REJECT_KICKED
	rejection_requested.emit(peer_id, reason, NetworkProtocol.rejection_message(reason))
	_pending_disconnects[peer_id] = _now_seconds() + 0.1
	log_requested.emit("warning", "operator_peer_removed", {
		"peer_id": peer_id,
		"display_name": display_name,
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
	log_requested.emit("info", "operator_setting_changed", {"setting": "lobby_password"})
	return {"ok": true, "setting": "lobby_password"}


func _load_blocked_sources() -> void:
	_blocked_sources.clear()
	if _ban_file_path.is_empty() or not FileAccess.file_exists(_ban_file_path):
		return
	var file := FileAccess.open(_ban_file_path, FileAccess.READ)
	if file == null:
		log_requested.emit("warning", "ban_file_read_failed", {"path": _ban_file_path})
		return
	if file.get_length() > NetworkProtocol.MAX_BAN_FILE_BYTES:
		log_requested.emit("warning", "ban_file_too_large", {"path": _ban_file_path})
		return
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Array:
		log_requested.emit("warning", "ban_file_invalid", {"path": _ban_file_path})
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
	connection_lost.emit(last_error)


func _on_client_server_disconnected() -> void:
	if role != NetworkBridge.Role.CLIENT:
		return
	var message := last_error if not last_error.is_empty() else NetworkProtocol.rejection_message(NetworkProtocol.REJECT_SERVER_CLOSED)
	local_peer_id = 0
	connection_lost.emit(message)


func process_pending_connections() -> void:
	var now := _now_seconds()
	if _pending_handshakes.size() > 0:
		for peer_id in _pending_handshakes.expired(now):
			reject_connection(peer_id, NetworkProtocol.REJECT_HANDSHAKE_TIMEOUT)
	if not _pending_disconnects.is_empty():
		for peer_value in _pending_disconnects.keys():
			var peer_id := int(peer_value)
			if now >= float(_pending_disconnects[peer_id]):
				_pending_disconnects.erase(peer_id)
				if _enet_peer != null:
					_enet_peer.disconnect_peer(peer_id)


func reject_connection(peer_id: int, reason: StringName) -> void:
	var message := NetworkProtocol.rejection_message(reason)
	rejection_requested.emit(peer_id, reason, message)
	_pending_handshakes.complete(peer_id)
	_pending_disconnects[peer_id] = _now_seconds() + 0.1
	log_requested.emit("warning", "connection_rejected", {"peer_id": peer_id, "reason": String(reason)})


func accept_control_request(peer_id: int, request_name: String, admitted: bool) -> bool:
	if not admitted:
		log_requested.emit("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": "request_before_handshake"})
		reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	var decision := _control_rate_limiter.register(peer_id, _now_seconds())
	if decision == RequestRateLimiter.Decision.DISCONNECT:
		log_requested.emit("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": "%s_rate_limit" % request_name})
		reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	return decision == RequestRateLimiter.Decision.ACCEPT


func reject_malformed_control(peer_id: int, detail: String) -> void:
	var strikes := int(_malformed_control_strikes.get(peer_id, 0)) + 1
	_malformed_control_strikes[peer_id] = strikes
	if strikes >= NetworkProtocol.TRAFFIC_STRIKES_BEFORE_DISCONNECT:
		log_requested.emit("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "control", "detail": detail})
		reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return
	request_rejected.emit(peer_id, detail)


func complete_handshake(peer_id: int) -> void:
	_pending_handshakes.complete(peer_id)



static func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0



func validate_hello(sender_id: int, protocol_version: int, display_name: String, password_proof: String, participant_count: int, player_limit: int) -> bool:
	if not _pending_handshakes.has(sender_id):
		reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	if display_name.length() > NetworkProtocol.MAX_LOG_STRING_LENGTH or not NetworkProtocol.is_valid_auth_proof(password_proof):
		reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	var challenge := _pending_handshakes.challenge_for(sender_id)
	var expected_proof := NetworkProtocol.lobby_password_proof(
		challenge,
		String(_configuration.get("lobby_password", ""))
	)
	var rejection := ConnectionAdmission.validate_hello(
		protocol_version,
		display_name,
		participant_count,
		player_limit,
		password_proof,
		expected_proof
	)
	if not rejection.is_empty():
		if rejection == NetworkProtocol.REJECT_INVALID_PASSWORD:
			_authentication_attempt_limiter.register_failure(
				String(_peer_auth_sources.get(sender_id, "peer:%d" % sender_id)),
				_now_seconds()
			)
		reject_connection(sender_id, rejection)
		return false
	return true



func accept_input(sender_id: int, decoded: Dictionary) -> bool:
	var decision := _rate_limiter.register(sender_id, _now_seconds(), decoded.ok)
	if decision == InputRateLimiter.Decision.DISCONNECT:
		log_requested.emit("warning", "traffic_peer_isolated", {"peer_id": sender_id, "traffic": "input", "detail": decoded.get("error", "rate_limit")})
		reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	if decision != InputRateLimiter.Decision.ACCEPT or not decoded.ok:
		return false
	return true


func forget_admission(peer_id: int) -> void:
	_rate_limiter.remove_peer(peer_id)
	_control_rate_limiter.remove_peer(peer_id)
	_malformed_control_strikes.erase(peer_id)
	_pending_handshakes.complete(peer_id)


func schedule_disconnect(peer_id: int) -> void:
	_pending_disconnects[peer_id] = _now_seconds() + 0.1


func configuration_value(key: String, fallback: Variant = null) -> Variant:
	return _configuration.get(key, fallback)


func set_server_name(value: String) -> void:
	_configuration.server_name = value


func set_auto_start(enabled: bool) -> void:
	_configuration.auto_start = enabled


func blocked_sources() -> Array:
	return _blocked_sources.keys()


func peer_source(peer_id: int) -> String:
	return String(_peer_auth_sources.get(peer_id, ""))


func take_client_hello(challenge: String) -> Dictionary:
	var result := {"protocol": _client_protocol_version, "name": _client_name,
		"proof": NetworkProtocol.lobby_password_proof(challenge, _client_password)}
	_client_password = ""
	return result


func accept_welcome(peer_id: int, state: Dictionary) -> void:
	local_peer_id = peer_id
	latest_lobby_state = state.duplicate(true)


func accept_lobby_state(state: Dictionary) -> bool:
	var incoming_revision := int(state.get("revision", 0))
	var current_revision := int(latest_lobby_state.get("revision", 0))
	if not latest_lobby_state.is_empty() and not SequenceMath.is_newer(incoming_revision, current_revision):
		return false
	latest_lobby_state = state.duplicate(true)
	return true


func set_error(message: String) -> void:
	last_error = message
