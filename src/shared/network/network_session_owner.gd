class_name NetworkSessionOwner
extends RefCounted

# Owns one transport/admission lifetime. RPC endpoints stay on NetworkBridge.
const AuthenticationAttemptLimiterScript = preload("res://src/shared/network/authentication_attempt_limiter.gd")
signal log_requested(level: String, event_name: String, fields: Dictionary)
signal challenge_requested(peer_id: int, challenge: String)
signal rejection_requested(peer_id: int, reason: StringName, message: String)
signal connection_lost(message: String)
## keeps_seat is false when the server removed the peer or the player chose to leave.
signal peer_departed(peer_id: int, keeps_seat: bool)
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
var _transport_peer: WebSocketMultiplayerPeer
var _peer_capacity: int = 0
var _round_trip_ms: float = -1.0
var _round_trip_variance_ms: float = 0.0
var _client_url: String = ""
var _connect_attempts: int = 0
var _connect_deadline: float = 0.0
var _connect_generation: int = 0
var _connect_rng := RandomNumberGenerator.new()
var _last_heard: Dictionary = {}
var _last_server_heard: float = 0.0
var _server_loss_reported: bool = false
var _behind_proxy: bool = false
# peer_id -> {baseline_ms, queue_delay_ms, outstanding: {sent_usec: true}, congested, next_probe}
var _probes: Dictionary = {}
var _congested_peers: Dictionary = {}
signal probe_requested(peer_id: int, server_usec: int)
var _proxy_failure_limiter := AuthenticationAttemptLimiterScript.new()
var _next_proxy_challenge: float = 0.0
## Test hook: trusts this certificate chain for wss:// instead of system roots.
var tls_trusted_chain: X509Certificate
var _lan_discovery: LanDiscoveryService
var _pending_handshakes := HandshakeRegistry.new()
var _pending_disconnects: Dictionary = {}
# Peers whose next departure must not hold a match seat: removed by the server
# (kick, ban, rejection) or leaving deliberately.
var _seatless_departures: Dictionary = {}
var _lingering_transport: WebSocketMultiplayerPeer
var _lingering_deadline: float = 0.0
var _rate_limiter := InputRateLimiter.new()
var _control_rate_limiter := RequestRateLimiter.new()
var _transport_rate_limiter := RequestRateLimiter.new(NetworkProtocol.MAX_TRANSPORT_MESSAGES_PER_SECOND)
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
# Server URL -> the seat token that server issued, kept across stop() so a
# dropped player can reconnect into their match seat.
var _reconnect_tokens: Dictionary = {}
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
	_transport_peer = _new_transport_peer(NetworkProtocol.SERVER_INBOUND_BUFFER_BYTES, NetworkProtocol.SERVER_OUTBOUND_BUFFER_BYTES)
	_peer_capacity = match_config.max_players + NetworkProtocol.AUTH_RESERVED_PEERS
	_behind_proxy = bool(configuration.get("behind_proxy", false))
	var bind_address := String(configuration.get("bind_address", "*"))
	var error := _transport_peer.create_server(match_config.port, bind_address)
	if error != OK:
		_transport_peer = null
		last_error = "Could not bind TCP %s:%d (error %d)." % [bind_address, match_config.port, error]
		log_requested.emit("error", "server_bind_failed", {"port": match_config.port, "error": error})
		role = NetworkBridge.Role.NONE
		return error
	# All game traffic goes through the authoritative server. Disable Godot's
	# unused peer-to-peer announcements, including relays to closing peers.
	var scene_multiplayer := runtime.multiplayer as SceneMultiplayer
	if scene_multiplayer != null: scene_multiplayer.server_relay = false
	runtime.multiplayer.multiplayer_peer = _transport_peer
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
		"bind_address": bind_address,
		"behind_proxy": _behind_proxy,
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
	_client_url = transport_url(host, port)
	if _client_url.is_empty():
		last_error = "Invalid server address %s." % host.strip_edges()
		role = NetworkBridge.Role.NONE
		return ERR_INVALID_PARAMETER
	_server_loss_reported = false
	_connect_attempts = 1
	_connect_deadline = _now_seconds() + NetworkProtocol.TRANSPORT_CONNECT_WINDOW_SECONDS
	_connect_rng.randomize()
	var error := _open_client_transport()
	if error != OK:
		last_error = "Could not connect to %s (error %d)." % [_client_url, error]
		role = NetworkBridge.Role.NONE
		return error
	if not runtime.multiplayer.connected_to_server.is_connected(_on_client_transport_connected):
		runtime.multiplayer.connected_to_server.connect(_on_client_transport_connected)
	if not runtime.multiplayer.connection_failed.is_connected(_on_client_connection_failed):
		runtime.multiplayer.connection_failed.connect(_on_client_connection_failed)
	if not runtime.multiplayer.server_disconnected.is_connected(_on_client_server_disconnected):
		runtime.multiplayer.server_disconnected.connect(_on_client_server_disconnected)
	return OK


func _open_client_transport() -> Error:
	_transport_peer = _new_transport_peer(NetworkProtocol.CLIENT_INBOUND_BUFFER_BYTES, NetworkProtocol.CLIENT_OUTBOUND_BUFFER_BYTES)
	var tls: TLSOptions = null
	if _client_url.to_lower().begins_with("wss://"):
		tls = TLSOptions.client(tls_trusted_chain) if tls_trusted_chain != null else TLSOptions.client()
	var error := _transport_peer.create_client(_client_url, tls)
	if error != OK:
		_transport_peer = null
		return error
	runtime.multiplayer.multiplayer_peer = _transport_peer
	return OK


## Stops the session but keeps the client socket open briefly, polled by
## poll_lingering_transport(), so packets already sent (a leave notice) reach
## the server. Closing at once can discard them.
func stop_after_delivery() -> void:
	var transport := _transport_peer if role == NetworkBridge.Role.CLIENT else null
	_transport_peer = null
	stop()
	if transport != null:
		_lingering_transport = transport
		_lingering_deadline = _now_seconds() + NetworkProtocol.LEAVE_DELIVERY_SECONDS


## Returns true while a stopped client's socket is still delivering.
func poll_lingering_transport() -> bool:
	if _lingering_transport == null:
		return false
	_lingering_transport.poll()
	if _lingering_transport.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED or _now_seconds() >= _lingering_deadline:
		_close_lingering_transport()
		return false
	return true


func _close_lingering_transport() -> void:
	if _lingering_transport != null:
		_lingering_transport.close()
	_lingering_transport = null


func stop() -> void:
	_close_lingering_transport()
	_connect_generation += 1
	# Mark teardown before closing the transport. Closing a live client can synchronously emit
	# server_disconnected; that callback must see NONE instead of recursively
	# entering the UI's disconnect path while this cleanup is still in progress.
	var stopped_role := role
	role = NetworkBridge.Role.NONE
	_disconnect_transport_signals()
	if stopped_role == NetworkBridge.Role.SERVER and _transport_peer != null:
		var status: Dictionary = _status_provider.call()
		log_requested.emit("info", "server_shutdown", {
			"connected_peers": int(status.get("human_count", 0)),
			"participant_records": int(status.get("participant_records", 0)),
			"active_ships": int(status.get("active_ships", 0)),
			"active_projectiles": int(status.get("active_projectiles", 0)),
			"pending_handshakes": _pending_handshakes.size(),
		})
	if _transport_peer != null:
		_transport_peer.close()
	_transport_peer = null
	_peer_capacity = 0
	_round_trip_ms = -1.0
	_round_trip_variance_ms = 0.0
	if _lan_discovery != null:
		_lan_discovery.stop()
		_lan_discovery.queue_free()
		_lan_discovery = null
	if runtime.is_inside_tree() and runtime.multiplayer.multiplayer_peer != null:
		runtime.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending_handshakes.clear()
	_pending_disconnects.clear()
	_seatless_departures.clear()
	_last_heard.clear()
	_probes.clear()
	_congested_peers.clear()
	_behind_proxy = false
	_proxy_failure_limiter.clear()
	_next_proxy_challenge = 0.0
	_rate_limiter.clear()
	_control_rate_limiter.clear()
	_transport_rate_limiter.clear()
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
	# TCP retransmits internally, so loss appears as latency rather than drops.
	var connected := role == NetworkBridge.Role.CLIENT and _transport_peer != null and _round_trip_ms >= 0.0
	return {
		"rtt_ms": int(round(_round_trip_ms)) if connected else -1,
		"rtt_variance_ms": int(round(_round_trip_variance_ms)) if connected else 0,
	}


## Smooths application-level ping samples (RFC 6298 style SRTT/RTTVAR).
func record_round_trip(sample_ms: float) -> void:
	if not is_finite(sample_ms) or sample_ms < 0.0:
		return
	if _round_trip_ms < 0.0:
		_round_trip_ms = sample_ms
		_round_trip_variance_ms = sample_ms * 0.5
		return
	var difference := sample_ms - _round_trip_ms
	_round_trip_ms += difference * 0.125
	_round_trip_variance_ms += (absf(difference) - _round_trip_variance_ms) * 0.25


func can_send_to(peer_id: int) -> bool:
	if _transport_peer == null or not runtime.is_inside_tree(): return false
	if not runtime.multiplayer.get_peers().has(peer_id): return false
	var peer := _transport_peer.get_peer(peer_id)
	return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func _has_transport_peer(peer_id: int) -> bool:
	return _transport_peer != null and runtime.is_inside_tree() and runtime.multiplayer.get_peers().has(peer_id)


static func transport_url(host: String, port: int) -> String:
	var address := host.strip_edges()
	# Full URLs (e.g. wss://game.example.com behind Cloudflare) carry their own port.
	if address.to_lower().begins_with("ws://") or address.to_lower().begins_with("wss://"):
		return address
	# Outside a URL, a colon or bracket is only valid around an IPv6 literal;
	# anything else (e.g. an accidental host:port) yields "" rather than a bad URL.
	if address.contains(":") or address.contains("[") or address.contains("]"):
		var literal := NetworkProtocol.unbracketed_ipv6(address)
		if literal.is_empty():
			return ""
		address = "[%s]" % literal
	return "ws://%s:%d" % [address, port]


static func _new_transport_peer(inbound_bytes: int, outbound_bytes: int) -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = NetworkProtocol.TRANSPORT_HANDSHAKE_TIMEOUT_SECONDS
	peer.inbound_buffer_size = inbound_bytes
	peer.outbound_buffer_size = outbound_bytes
	peer.max_queued_packets = NetworkProtocol.TRANSPORT_MAX_QUEUED_PACKETS
	return peer


func _on_server_peer_connected(peer_id: int) -> void:
	if runtime.multiplayer.get_peers().size() > _peer_capacity:
		# WebSocket servers have no peer cap; bound admitted plus reserved peers.
		log_requested.emit("warning", "connection_capacity_exceeded", {"peer_id": peer_id})
		_transport_peer.disconnect_peer(peer_id)
		return
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
	if _authentication_attempt_limiter.is_blocked(source, now):
		_pending_handshakes.begin(peer_id, now)
		reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
		return
	_pending_handshakes.begin(peer_id, now)
	_start_queued_handshakes()
	if _pending_handshakes.has(peer_id) and _pending_handshakes.challenge_for(peer_id).is_empty():
		log_requested.emit("info", "authentication_queued", {"peer_id": peer_id})


func _on_server_peer_disconnected(peer_id: int) -> void:
	_pending_handshakes.complete(peer_id)
	_last_heard.erase(peer_id)
	_probes.erase(peer_id)
	_congested_peers.erase(peer_id)
	_peer_auth_sources.erase(peer_id)
	_pending_disconnects.erase(peer_id)
	_rate_limiter.remove_peer(peer_id)
	_control_rate_limiter.remove_peer(peer_id)
	_transport_rate_limiter.remove_peer(peer_id)
	_malformed_control_strikes.erase(peer_id)
	var keeps_seat := not _seatless_departures.has(peer_id)
	_seatless_departures.erase(peer_id)
	peer_departed.emit(peer_id, keeps_seat)


func _peer_auth_source(peer_id: int) -> String:
	if _behind_proxy:
		# Every connection arrives from the proxy; never throttle or ban its address.
		return "proxied:%d" % peer_id
	if _transport_peer == null:
		return "peer:%d" % peer_id
	var packet_peer := _transport_peer.get_peer(peer_id)
	if packet_peer == null:
		return "peer:%d" % peer_id
	var address := packet_peer.get_connected_host()
	return address if not address.is_empty() else "peer:%d" % peer_id


func _pending_auth_count_for_source(source: String, excluded_peer_id: int) -> int:
	var normalized := _normalized_source(source)
	var count := 0
	for peer_value in _peer_auth_sources.keys():
		var peer_id := int(peer_value)
		if peer_id != excluded_peer_id and not _pending_handshakes.challenge_for(peer_id).is_empty() and _normalized_source(String(_peer_auth_sources[peer_id])) == normalized:
			count += 1
	return count


func _start_queued_handshakes() -> void:
	# Keep the per-source in-flight proof budget while accommodating cohorts
	# behind one NAT. The peer capacity bounds total peers; the original admission deadline
	# also bounds queue residence and is never extended by promotion.
	var now := _now_seconds()
	for peer_id in _pending_handshakes.queued_peers():
		var source := String(_peer_auth_sources.get(peer_id, "peer:%d" % peer_id))
		if _blocked_sources.has(_normalized_source(source)):
			reject_connection(peer_id, NetworkProtocol.REJECT_BLOCKED)
			continue
		if _authentication_attempt_limiter.is_blocked(source, now):
			reject_connection(peer_id, NetworkProtocol.REJECT_AUTH_RATE_LIMITED)
			continue
		if _pending_auth_count_for_source(source, peer_id) >= NetworkProtocol.AUTH_MAX_PENDING_PER_SOURCE:
			continue
		if _behind_proxy and _proxy_failure_limiter.is_blocked("proxy", now):
			if now < _next_proxy_challenge:
				break
			_next_proxy_challenge = now + NetworkProtocol.PROXY_THROTTLED_CHALLENGE_INTERVAL_SECONDS
		var challenge := Crypto.new().generate_random_bytes(NetworkProtocol.AUTH_CHALLENGE_BYTES).hex_encode()
		if _pending_handshakes.start_challenge(peer_id, challenge, now):
			challenge_requested.emit(peer_id, challenge)


func operator_kick(peer_id: int, display_name: String, block_source: bool = false) -> Dictionary:
	var source := String(_peer_auth_sources.get(peer_id, ""))
	if block_source:
		var block_result := operator_block_source(source)
		if not block_result.ok:
			return block_result
	var reason := NetworkProtocol.REJECT_BLOCKED if block_source else NetworkProtocol.REJECT_KICKED
	rejection_requested.emit(peer_id, reason, NetworkProtocol.rejection_message(reason))
	_pending_disconnects[peer_id] = _now_seconds() + 0.1
	_seatless_departures[peer_id] = true
	log_requested.emit("warning", "operator_peer_removed", {
		"peer_id": peer_id,
		"display_name": display_name,
		"blocked": block_source,
	})
	return {"ok": true, "peer_id": peer_id, "source": source, "blocked": block_source}


func operator_block_source(source: String) -> Dictionary:
	if _behind_proxy:
		return {"ok": false, "error": "Address bans are unavailable behind a proxy because every player shares its address. Kick the player instead."}
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
	# A TCP listener refuses connections beyond its small accept backlog, so a
	# burst of simultaneous joins retries with jittered backoff before admission.
	if local_peer_id == 0 and _connect_attempts < NetworkProtocol.TRANSPORT_CONNECT_ATTEMPTS and _now_seconds() < _connect_deadline and runtime.is_inside_tree():
		var backoff := minf(0.1 * pow(2.0, _connect_attempts - 1), 1.0) * _connect_rng.randf_range(0.5, 1.5)
		_connect_attempts += 1
		runtime.get_tree().create_timer(backoff).timeout.connect(_retry_client_transport.bind(_connect_generation))
		return
	last_error = "Could not reach the server."
	connection_lost.emit(last_error)


func _retry_client_transport(generation: int) -> void:
	if generation != _connect_generation or role != NetworkBridge.Role.CLIENT or local_peer_id != 0:
		return
	if _transport_peer != null:
		_transport_peer.close()
	if _open_client_transport() != OK:
		_on_client_connection_failed()


func _on_client_server_disconnected() -> void:
	if role != NetworkBridge.Role.CLIENT or _server_loss_reported:
		return
	_server_loss_reported = true
	var message := last_error if not last_error.is_empty() else NetworkProtocol.rejection_message(NetworkProtocol.REJECT_SERVER_CLOSED)
	local_peer_id = 0
	connection_lost.emit(message)


func process_pending_connections() -> void:
	var now := _now_seconds()
	if _pending_handshakes.size() > 0:
		for peer_id in _pending_handshakes.expired(now):
			reject_connection(peer_id, NetworkProtocol.REJECT_HANDSHAKE_TIMEOUT)
	_start_queued_handshakes()
	_process_probes(Time.get_ticks_usec())
	_disconnect_overflowing_peers()
	for peer_value in _last_heard.keys():
		if now - float(_last_heard[peer_value]) > NetworkProtocol.TRANSPORT_IDLE_TIMEOUT_SECONDS:
			var peer_id := int(peer_value)
			_last_heard.erase(peer_id)
			log_requested.emit("warning", "peer_timed_out", {"peer_id": peer_id})
			if _has_transport_peer(peer_id):
				_transport_peer.disconnect_peer(peer_id)
	if not _pending_disconnects.is_empty():
		for peer_value in _pending_disconnects.keys():
			var peer_id := int(peer_value)
			if now >= float(_pending_disconnects[peer_id]):
				_pending_disconnects.erase(peer_id)
				if _has_transport_peer(peer_id):
					_transport_peer.disconnect_peer(peer_id)


func reject_connection(peer_id: int, reason: StringName) -> void:
	var message := NetworkProtocol.rejection_message(reason)
	rejection_requested.emit(peer_id, reason, message)
	_pending_handshakes.complete(peer_id)
	_pending_disconnects[peer_id] = _now_seconds() + 0.1
	_seatless_departures[peer_id] = true
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
	_last_heard[peer_id] = _now_seconds()
	_probes[peer_id] = {"baseline_ms": INF, "queue_delay_ms": 0.0, "outstanding": {}, "congested": false, "next_probe": 0}


func _process_probes(now_usec: int) -> void:
	for peer_value in _probes.keys():
		var state: Dictionary = _probes[peer_value]
		var outstanding: Dictionary = state.outstanding
		for sent_usec in outstanding.keys():
			if now_usec - int(sent_usec) > int(NetworkProtocol.TRANSPORT_PROBE_EXPIRY_SECONDS * 1_000_000.0):
				outstanding.erase(sent_usec)
		# An unanswered probe is at least this late; count it before its ack arrives.
		if not outstanding.is_empty() and is_finite(float(state.baseline_ms)):
			var oldest_ms := (now_usec - int(outstanding.keys().min())) / 1000.0
			_update_congestion(int(peer_value), state, maxf(float(state.queue_delay_ms), oldest_ms - float(state.baseline_ms)))
		if now_usec < int(state.next_probe) or outstanding.size() >= NetworkProtocol.TRANSPORT_PROBE_MAX_OUTSTANDING:
			continue
		state.next_probe = now_usec + int(NetworkProtocol.TRANSPORT_PROBE_INTERVAL_SECONDS * 1_000_000.0)
		outstanding[now_usec] = true
		probe_requested.emit(int(peer_value), now_usec)


func _disconnect_overflowing_peers() -> void:
	for peer_value in _probes.keys():
		var peer_id := int(peer_value)
		if not _has_transport_peer(peer_id):
			continue
		var peer := _transport_peer.get_peer(peer_id)
		if peer == null or peer.get_current_outbound_buffered_amount() < NetworkProtocol.SERVER_OUTBOUND_OVERFLOW_BYTES:
			continue
		log_requested.emit("warning", "peer_outbound_overflow", {"peer_id": peer_id, "buffered_bytes": peer.get_current_outbound_buffered_amount()})
		_probes.erase(peer_id)
		_congested_peers.erase(peer_id)
		_transport_peer.disconnect_peer(peer_id)


## Pings and probe acks from peers that are no longer admitted (for example
## during an eject's disconnect grace) are ignored rather than treated as
## pre-handshake traffic, and they are limited apart from lobby controls.
func accept_transport_message(peer_id: int) -> bool:
	if not _last_heard.has(peer_id):
		return false
	var decision := _transport_rate_limiter.register(peer_id, _now_seconds())
	if decision == RequestRateLimiter.Decision.DISCONNECT:
		log_requested.emit("warning", "traffic_peer_isolated", {"peer_id": peer_id, "traffic": "transport", "detail": "transport_rate_limit"})
		reject_connection(peer_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
	return decision == RequestRateLimiter.Decision.ACCEPT


## Server-side round trip for one probe; queueing shows as delay above baseline.
func record_probe_ack(peer_id: int, server_usec: int, now_usec: int = -1) -> void:
	var state: Dictionary = _probes.get(peer_id, {})
	if state.is_empty() or not (state.outstanding as Dictionary).erase(server_usec):
		return
	if now_usec < 0:
		now_usec = Time.get_ticks_usec()
	var rtt_ms := (now_usec - server_usec) / 1000.0
	if rtt_ms < 0.0:
		return
	# Let the baseline creep upward (1 ms per probe) so a route change is learned.
	var baseline := minf(float(state.baseline_ms) + 1.0, rtt_ms) if is_finite(float(state.baseline_ms)) else rtt_ms
	state.baseline_ms = baseline
	state.queue_delay_ms = rtt_ms - baseline
	_update_congestion(peer_id, state, float(state.queue_delay_ms))


func _update_congestion(peer_id: int, state: Dictionary, queue_delay_ms: float) -> void:
	var was_congested := bool(state.congested)
	# Hysteresis between the enter and exit thresholds avoids flapping per probe.
	var congested := queue_delay_ms > NetworkProtocol.TRANSPORT_CONGESTION_ENTER_MS if not was_congested else queue_delay_ms > NetworkProtocol.TRANSPORT_CONGESTION_EXIT_MS
	if congested == was_congested:
		return
	state.congested = congested
	if congested:
		_congested_peers[peer_id] = true
	else:
		_congested_peers.erase(peer_id)
	log_requested.emit("warning" if congested else "info", "peer_transport_congested" if congested else "peer_transport_recovered", {"peer_id": peer_id, "queue_delay_ms": roundi(queue_delay_ms)})


## Peers whose outbound stream is backlogged; read by replication each tick.
func congested_peers() -> Dictionary:
	return _congested_peers


## Refreshes an admitted peer's liveness deadline.
func note_peer_alive(peer_id: int) -> void:
	if _last_heard.has(peer_id):
		_last_heard[peer_id] = _now_seconds()


func note_server_alive() -> void:
	_last_server_heard = _now_seconds()


## Reports a lost server when an admitted client stops receiving pongs.
func check_server_liveness() -> void:
	if role != NetworkBridge.Role.CLIENT or local_peer_id == 0 or _server_loss_reported:
		return
	if _now_seconds() - _last_server_heard <= NetworkProtocol.TRANSPORT_IDLE_TIMEOUT_SECONDS:
		return
	last_error = "The connection to the server timed out."
	if _transport_peer != null:
		_transport_peer.close()
	_on_client_server_disconnected()



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
	if not NetworkProtocol.is_valid_auth_challenge(challenge):
		reject_connection(sender_id, NetworkProtocol.REJECT_MALFORMED_TRAFFIC)
		return false
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
			if _behind_proxy and _proxy_failure_limiter.register_failure("proxy", _now_seconds()):
				log_requested.emit("warning", "proxy_authentication_throttled", {"interval_seconds": NetworkProtocol.PROXY_THROTTLED_CHALLENGE_INTERVAL_SECONDS})
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
	_last_heard.erase(peer_id)
	_probes.erase(peer_id)
	_congested_peers.erase(peer_id)
	_rate_limiter.remove_peer(peer_id)
	_control_rate_limiter.remove_peer(peer_id)
	_transport_rate_limiter.remove_peer(peer_id)
	_malformed_control_strikes.erase(peer_id)
	_pending_handshakes.complete(peer_id)


func schedule_disconnect(peer_id: int) -> void:
	_pending_disconnects[peer_id] = _now_seconds() + 0.1
	_seatless_departures[peer_id] = true


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
		"proof": NetworkProtocol.lobby_password_proof(challenge, _client_password),
		"reconnect_token": String(_reconnect_tokens.get(_client_url, ""))}
	_client_password = ""
	return result


func accept_welcome(peer_id: int, state: Dictionary, reconnect_token: String = "") -> void:
	local_peer_id = peer_id
	if not reconnect_token.is_empty():
		_reconnect_tokens[_client_url] = reconnect_token
	_last_server_heard = _now_seconds()
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
