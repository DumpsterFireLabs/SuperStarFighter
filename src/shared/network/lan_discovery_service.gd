class_name LanDiscoveryService
extends Node

signal servers_updated(servers: Array[Dictionary])

enum Mode {
	NONE,
	RESPONDER,
	BROWSER,
}

const QUERY_INTERVAL_MSEC: int = 1000
const SERVER_EXPIRY_MSEC: int = 3500
const RESPONSE_RATE_LIMIT_MSEC: int = 400

var mode: Mode = Mode.NONE
var last_error: String = ""

var _responder := UDPServer.new()
var _browser := PacketPeerUDP.new()
var _payload_provider: Callable
var _servers: Dictionary = {}
var _query_sent_at: Dictionary = {}
var _last_response_at: Dictionary = {}
var _next_query_msec: int = 0
var _nonce_serial: int = 0
var _last_server_signature: String = ""


func start_responder(payload_provider: Callable) -> Error:
	stop()
	_payload_provider = payload_provider
	var error := _responder.listen(LanDiscoveryProtocol.DISCOVERY_PORT, "0.0.0.0")
	if error != OK:
		last_error = "Could not bind LAN discovery UDP port %d (error %d)." % [LanDiscoveryProtocol.DISCOVERY_PORT, error]
		return error
	mode = Mode.RESPONDER
	set_process(true)
	return OK


func start_browser() -> Error:
	stop()
	var error := _browser.bind(0, "0.0.0.0")
	if error != OK:
		last_error = "Could not open a LAN discovery socket (error %d)." % error
		return error
	_browser.set_broadcast_enabled(true)
	mode = Mode.BROWSER
	set_process(true)
	refresh_now()
	return OK


func refresh_now() -> void:
	if mode != Mode.BROWSER:
		return
	_send_query()
	_next_query_msec = Time.get_ticks_msec() + QUERY_INTERVAL_MSEC


func discovered_servers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for server_value in _servers.values():
		var server := (server_value as Dictionary).duplicate(true)
		server.erase("last_seen_msec")
		result.append(server)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var name_comparison := String(first.server_name).naturalnocasecmp_to(String(second.server_name))
		if name_comparison != 0:
			return name_comparison < 0
		return String(first.address) < String(second.address)
	)
	return result


func stop() -> void:
	if _responder.is_listening():
		_responder.stop()
	if _browser.is_bound():
		_browser.close()
	mode = Mode.NONE
	_payload_provider = Callable()
	_servers.clear()
	_query_sent_at.clear()
	_last_response_at.clear()
	_last_server_signature = ""
	set_process(false)


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if mode == Mode.RESPONDER:
		_process_responder()
	elif mode == Mode.BROWSER:
		_process_browser()


func _process_responder() -> void:
	if _responder.poll() != OK:
		return
	while _responder.is_connection_available():
		var peer := _responder.take_connection()
		if peer == null:
			continue
		while peer.get_available_packet_count() > 0:
			var packet := peer.get_packet()
			var query := LanDiscoveryProtocol.decode_query(packet)
			if not query.ok:
				continue
			var requester_key := "%s:%d" % [peer.get_packet_ip(), peer.get_packet_port()]
			var now := Time.get_ticks_msec()
			if now - int(_last_response_at.get(requester_key, -RESPONSE_RATE_LIMIT_MSEC)) < RESPONSE_RATE_LIMIT_MSEC:
				continue
			_last_response_at[requester_key] = now
			if _last_response_at.size() > 128:
				for stale_key in _last_response_at.keys():
					if now - int(_last_response_at[stale_key]) > SERVER_EXPIRY_MSEC:
						_last_response_at.erase(stale_key)
				while _last_response_at.size() > 128:
					_last_response_at.erase(_last_response_at.keys()[0])
			var state := _payload_provider.call() as Dictionary if _payload_provider.is_valid() else {}
			peer.put_packet(LanDiscoveryProtocol.encode_response(String(query.nonce), state))


func _process_browser() -> void:
	var now := Time.get_ticks_msec()
	if now >= _next_query_msec:
		_send_query()
		_next_query_msec = now + QUERY_INTERVAL_MSEC
	while _browser.get_available_packet_count() > 0:
		var packet := _browser.get_packet()
		var source_ip := _browser.get_packet_ip()
		var response := LanDiscoveryProtocol.decode_response(packet)
		if not response.ok or not _query_sent_at.has(String(response.nonce)):
			continue
		var entry := response.duplicate(true)
		entry.erase("ok")
		entry.erase("nonce")
		entry["address"] = source_ip
		entry["ping_ms"] = clampi(now - int(_query_sent_at[String(response.nonce)]), 0, 9999)
		entry["last_seen_msec"] = now
		_servers[String(response.instance_id)] = entry
	var changed := false
	for server_key in _servers.keys():
		if now - int((_servers[server_key] as Dictionary).last_seen_msec) > SERVER_EXPIRY_MSEC:
			_servers.erase(server_key)
			changed = true
	for nonce in _query_sent_at.keys():
		if now - int(_query_sent_at[nonce]) > SERVER_EXPIRY_MSEC:
			_query_sent_at.erase(nonce)
	var servers := discovered_servers()
	var signature := str(servers)
	if changed or signature != _last_server_signature:
		_last_server_signature = signature
		servers_updated.emit(servers)


func _send_query() -> void:
	_nonce_serial = SequenceMath.increment(_nonce_serial)
	var nonce := "%x-%x" % [Time.get_ticks_msec(), _nonce_serial]
	_query_sent_at[nonce] = Time.get_ticks_msec()
	var packet := LanDiscoveryProtocol.encode_query(nonce)
	_browser.set_dest_address("255.255.255.255", LanDiscoveryProtocol.DISCOVERY_PORT)
	_browser.put_packet(packet)
	_browser.set_dest_address("127.0.0.1", LanDiscoveryProtocol.DISCOVERY_PORT)
	_browser.put_packet(packet)
