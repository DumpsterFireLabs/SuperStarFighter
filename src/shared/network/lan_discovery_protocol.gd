class_name LanDiscoveryProtocol
extends RefCounted

const DISCOVERY_PORT: int = 7359
const MAX_PACKET_BYTES: int = 1024
const MAX_NONCE_LENGTH: int = 64
const MAX_SERVER_NAME_LENGTH: int = 40
const QUERY_MAGIC: String = "SSF_LAN_QUERY"
const RESPONSE_MAGIC: String = "SSF_LAN_RESPONSE"


static func is_valid_server_name(server_name: String) -> bool:
	var trimmed := server_name.strip_edges()
	return not trimmed.is_empty() and trimmed.length() <= MAX_SERVER_NAME_LENGTH and _is_safe_text(trimmed)


static func encode_query(nonce: String) -> PackedByteArray:
	return JSON.stringify({
		"magic": QUERY_MAGIC,
		"nonce": nonce.left(MAX_NONCE_LENGTH),
	}).to_utf8_buffer()


static func decode_query(packet: PackedByteArray) -> Dictionary:
	var decoded := _decode_packet(packet)
	if not decoded.ok:
		return decoded
	var payload := decoded.payload as Dictionary
	var nonce := String(payload.get("nonce", ""))
	if String(payload.get("magic", "")) != QUERY_MAGIC or nonce.is_empty() or nonce.length() > MAX_NONCE_LENGTH:
		return {"ok": false, "error": "invalid_query"}
	return {"ok": true, "nonce": nonce}


static func encode_response(nonce: String, server_state: Dictionary) -> PackedByteArray:
	var server_name := String(server_state.get("server_name", "Super Star Fighter Server")).strip_edges().left(MAX_SERVER_NAME_LENGTH)
	if not _is_safe_text(server_name):
		server_name = "Super Star Fighter Server"
	return JSON.stringify({
		"magic": RESPONSE_MAGIC,
		"nonce": nonce.left(MAX_NONCE_LENGTH),
		"instance_id": String(server_state.get("instance_id", "server")).left(MAX_NONCE_LENGTH),
		"protocol_version": int(server_state.get("protocol_version", GameConstants.PROTOCOL_VERSION)),
		"server_name": server_name,
		"game_port": int(server_state.get("game_port", GameConstants.DEFAULT_PORT)),
		"human_count": int(server_state.get("human_count", 0)),
		"npc_count": int(server_state.get("npc_count", 0)),
		"player_limit": int(server_state.get("player_limit", GameConstants.DEFAULT_MAX_PLAYERS)),
		"match_active": bool(server_state.get("match_active", false)),
	}).to_utf8_buffer()


static func decode_response(packet: PackedByteArray) -> Dictionary:
	var decoded := _decode_packet(packet)
	if not decoded.ok:
		return decoded
	var payload := decoded.payload as Dictionary
	var nonce := String(payload.get("nonce", ""))
	var instance_id := String(payload.get("instance_id", ""))
	var server_name := String(payload.get("server_name", ""))
	var protocol_version := int(payload.get("protocol_version", 0))
	var game_port := int(payload.get("game_port", 0))
	var human_count := int(payload.get("human_count", -1))
	var npc_count := int(payload.get("npc_count", -1))
	var player_limit := int(payload.get("player_limit", 0))
	if String(payload.get("magic", "")) != RESPONSE_MAGIC:
		return {"ok": false, "error": "invalid_magic"}
	if nonce.is_empty() or nonce.length() > MAX_NONCE_LENGTH:
		return {"ok": false, "error": "invalid_nonce"}
	if instance_id.is_empty() or instance_id.length() > MAX_NONCE_LENGTH or not _is_safe_text(instance_id):
		return {"ok": false, "error": "invalid_instance_id"}
	if server_name.is_empty() or server_name.length() > MAX_SERVER_NAME_LENGTH or not _is_safe_text(server_name):
		return {"ok": false, "error": "invalid_server_name"}
	if protocol_version <= 0 or game_port < GameConstants.MIN_PORT or game_port > GameConstants.MAX_PORT:
		return {"ok": false, "error": "invalid_endpoint"}
	if player_limit < GameConstants.MIN_PLAYERS or player_limit > GameConstants.MAX_PLAYERS:
		return {"ok": false, "error": "invalid_player_limit"}
	if human_count < 0 or npc_count < 0 or human_count + npc_count > player_limit:
		return {"ok": false, "error": "invalid_player_count"}
	return {
		"ok": true,
		"nonce": nonce,
		"instance_id": instance_id,
		"protocol_version": protocol_version,
		"server_name": server_name,
		"game_port": game_port,
		"human_count": human_count,
		"npc_count": npc_count,
		"player_limit": player_limit,
		"match_active": bool(payload.get("match_active", false)),
	}


static func _decode_packet(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return {"ok": false, "error": "invalid_size"}
	var json := JSON.new()
	if json.parse(packet.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"ok": false, "error": "invalid_json"}
	return {"ok": true, "payload": json.data}


static func _is_safe_text(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true
