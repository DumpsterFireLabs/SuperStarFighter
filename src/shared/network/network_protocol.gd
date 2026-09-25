class_name NetworkProtocol
extends RefCounted

const PACKET_VERSION: int = 17
const SERVER_PEER_ID: int = 1

const CHANNEL_CONTROL: int = 0
const CHANNEL_INPUT: int = 1
const CHANNEL_PLAYER_SNAPSHOT: int = 2
const CHANNEL_PROJECTILE_DELTA: int = 3
const CHANNEL_PROJECTILE_CORRECTION: int = 4
const CHANNEL_OBJECTIVE: int = 5
const CHANNEL_COUNT: int = 6
# One WebSocket (TCP) stream per peer carries every channel in order.
const TRANSPORT_HANDSHAKE_TIMEOUT_SECONDS: float = 5.0
const TRANSPORT_BUFFER_BYTES: int = 1 << 20
const TRANSPORT_MAX_QUEUED_PACKETS: int = 4096
const TRANSPORT_PING_INTERVAL_SECONDS: float = 1.0
const TRANSPORT_CONNECT_ATTEMPTS: int = 12
const TRANSPORT_CONNECT_WINDOW_SECONDS: float = 10.0
# TCP never times out a silent peer, so both ends require regular traffic.
const TRANSPORT_IDLE_TIMEOUT_SECONDS: float = 10.0
const MAX_SERVER_ADDRESS_LENGTH: int = 512
# Behind a reverse proxy every player shares one source address, so repeated
# wrong passwords slow new challenges globally instead of locking a source out.
const PROXY_THROTTLED_CHALLENGE_INTERVAL_SECONDS: float = 1.0

const ACTION_FIRE: int = 1
const ACTION_SHIELD: int = 2
const ACTION_RELOAD: int = 4
const ACTION_SPECIAL: int = 8
const ACTION_SHIELD_PRESS: int = 16
const ACTION_MASK: int = ACTION_FIRE | ACTION_SHIELD | ACTION_RELOAD | ACTION_SPECIAL | ACTION_SHIELD_PRESS

const HANDSHAKE_TIMEOUT_SECONDS: float = 10.0
const MAX_INPUTS_PER_SECOND: int = 60
const MAX_CONTROL_REQUESTS_PER_SECOND: int = 20
const TRAFFIC_STRIKES_BEFORE_DISCONNECT: int = 3
const MAX_OFFER_TOKEN_LENGTH: int = 64
const MAX_CARD_ID_LENGTH: int = 64
const MAX_LOBBY_PASSWORD_LENGTH: int = 64
const MIN_ADMIN_PASSWORD_LENGTH: int = 12
const AUTH_CHALLENGE_BYTES: int = 32
const AUTH_CHALLENGE_HEX_LENGTH: int = AUTH_CHALLENGE_BYTES * 2
const AUTH_PROOF_HEX_LENGTH: int = 64
const AUTH_RESERVED_PEERS: int = 8
const AUTH_MAX_PENDING_PER_SOURCE: int = 2
const AUTH_FAILURE_LIMIT: int = 8
const AUTH_FAILURE_WINDOW_SECONDS: float = 60.0
const AUTH_COOLDOWN_SECONDS: float = 60.0
const AUTH_MAX_TRACKED_SOURCES: int = 4096
const CONNECTION_ATTEMPT_LIMIT: int = 64
const CONNECTION_ATTEMPT_WINDOW_SECONDS: float = 60.0
const CONNECTION_ATTEMPT_COOLDOWN_SECONDS: float = 60.0
const ADMIN_MAX_MESSAGE_BYTES: int = 4096
const ADMIN_MAX_CLIENTS: int = 4
const ADMIN_MAX_REQUESTS_PER_SECOND: int = 20
const ADMIN_AUTH_TIMEOUT_SECONDS: float = 10.0
const ADMIN_IDLE_TIMEOUT_SECONDS: float = 300.0
const ADMIN_AUTH_FAILURE_LIMIT: int = 5
const ADMIN_AUTH_FAILURE_WINDOW_SECONDS: float = 60.0
const ADMIN_AUTH_COOLDOWN_SECONDS: float = 300.0
const ADMIN_MAX_RESPONSE_BYTES: int = 65536
const MAX_BLOCKED_SOURCES: int = 4096
const MAX_BAN_FILE_BYTES: int = 262144
const MAX_LOG_STRING_LENGTH: int = 128
const MAX_LOG_COLLECTION_LENGTH: int = 16
const MAX_SNAPSHOT_PLAYERS: int = GameConstants.MAX_PLAYERS
const MAX_PACKET_PROJECTILES: int = GameConstants.MAX_PROJECTILES_GLOBAL
const MAX_PROJECTILE_MESSAGE_BYTES: int = 1200

const REJECT_SERVER_FULL: StringName = &"SERVER_FULL"
const REJECT_VERSION_MISMATCH: StringName = &"VERSION_MISMATCH"
const REJECT_INVALID_NAME: StringName = &"INVALID_NAME"
const REJECT_INVALID_PASSWORD: StringName = &"INVALID_PASSWORD"
const REJECT_HANDSHAKE_TIMEOUT: StringName = &"HANDSHAKE_TIMEOUT"
const REJECT_MALFORMED_TRAFFIC: StringName = &"MALFORMED_TRAFFIC"
const REJECT_SERVER_CLOSED: StringName = &"SERVER_CLOSED"
const REJECT_EJECTED: StringName = &"EJECTED"
const REJECT_AUTH_RATE_LIMITED: StringName = &"AUTH_RATE_LIMITED"
const REJECT_KICKED: StringName = &"KICKED"
const REJECT_BLOCKED: StringName = &"BLOCKED"


static func rejection_message(reason: StringName) -> String:
	match reason:
		REJECT_SERVER_FULL:
			return "The server is full."
		REJECT_VERSION_MISMATCH:
			return "Client and server protocol versions do not match."
		REJECT_INVALID_NAME:
			return "Display name must contain 1–16 visible characters without unsafe formatting."
		REJECT_INVALID_PASSWORD:
			return "The lobby password is incorrect."
		REJECT_HANDSHAKE_TIMEOUT:
			return "The connection handshake timed out."
		REJECT_MALFORMED_TRAFFIC:
			return "The server rejected malformed or excessive network traffic."
		REJECT_SERVER_CLOSED:
			return "The server closed the connection."
		REJECT_EJECTED:
			return "You were removed from the lobby by its leader."
		REJECT_AUTH_RATE_LIMITED:
			return "Too many unsuccessful password attempts. Try again in one minute."
		REJECT_KICKED:
			return "A server operator removed you from the server."
		REJECT_BLOCKED:
			return "This connection is blocked by the server operator."
		_:
			return "The server rejected the connection."


## Accepts a hostname or IP, or a ws:// / wss:// URL (for example a
## Cloudflare-proxied wss://game.example.com) with a non-empty host.
static func is_valid_server_address(address: String) -> bool:
	if address.is_empty() or address.length() > MAX_SERVER_ADDRESS_LENGTH or address.contains(" "):
		return false
	var lowered := address.to_lower()
	for scheme in ["wss://", "ws://"]:
		if lowered.begins_with(scheme):
			var authority := address.substr(scheme.length()).get_slice("/", 0)
			return not authority.is_empty() and not authority.begins_with(":") and not authority.contains("@")
	return address.length() <= 253 and not address.contains("/")


static func is_valid_lobby_password(password: String) -> bool:
	if password.is_empty() or password.length() > MAX_LOBBY_PASSWORD_LENGTH:
		return false
	for index in password.length():
		var codepoint := password.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true


static func is_valid_admin_password(password: String) -> bool:
	return password.length() >= MIN_ADMIN_PASSWORD_LENGTH and is_valid_lobby_password(password)


static func is_valid_auth_challenge(challenge: String) -> bool:
	return _is_lower_hex(challenge, AUTH_CHALLENGE_HEX_LENGTH)


static func is_valid_auth_proof(proof: String) -> bool:
	return _is_lower_hex(proof, AUTH_PROOF_HEX_LENGTH)


static func lobby_password_proof(challenge: String, password: String) -> String:
	if not is_valid_auth_challenge(challenge) or not is_valid_lobby_password(password):
		return ""
	return ("ssf-lobby-auth-v1\u001f%s\u001f%s" % [challenge, password]).sha256_text()


static func admin_password_proof(challenge: String, password: String) -> String:
	if not is_valid_auth_challenge(challenge) or not is_valid_admin_password(password):
		return ""
	return ("ssf-admin-auth-v1\u001f%s\u001f%s" % [challenge, password]).sha256_text()


static func admin_command_signature(challenge: String, password: String, sequence: int, request: Dictionary) -> String:
	if not is_valid_auth_challenge(challenge) or not is_valid_admin_password(password) or sequence < 1 or sequence > 2_147_483_647:
		return ""
	var keys := request.keys()
	for key in keys:
		if not key is String:
			return ""
	keys.sort()
	var ordered: Dictionary = {}
	for key in keys:
		ordered[key] = request[key]
	var crypto := Crypto.new()
	var session_key := crypto.hmac_digest(HashingContext.HASH_SHA256, password.to_utf8_buffer(), ("ssf-admin-session-v1\u001f" + challenge).to_utf8_buffer())
	var message := ("ssf-admin-command-v1\u001f%d\u001f%s" % [sequence, JSON.stringify(ordered)]).to_utf8_buffer()
	return crypto.hmac_digest(HashingContext.HASH_SHA256, session_key, message).hex_encode()


static func constant_time_string_equal(left: String, right: String) -> bool:
	var left_bytes := left.to_utf8_buffer()
	var right_bytes := right.to_utf8_buffer()
	var difference := left_bytes.size() ^ right_bytes.size()
	var comparison_size := maxi(left_bytes.size(), right_bytes.size())
	for index in comparison_size:
		var left_value := left_bytes[index] if index < left_bytes.size() else 0
		var right_value := right_bytes[index] if index < right_bytes.size() else 0
		difference |= left_value ^ right_value
	return difference == 0


static func _is_lower_hex(value: String, expected_length: int) -> bool:
	if value.length() != expected_length:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true
