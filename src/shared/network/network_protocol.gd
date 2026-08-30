class_name NetworkProtocol
extends RefCounted

const PACKET_VERSION: int = 7
const SERVER_PEER_ID: int = 1

const CHANNEL_CONTROL: int = 0
const CHANNEL_INPUT: int = 1
const CHANNEL_PLAYER_SNAPSHOT: int = 2
const CHANNEL_PROJECTILE_DELTA: int = 3
const CHANNEL_PROJECTILE_CORRECTION: int = 4
const CHANNEL_OBJECTIVE: int = 5
const CHANNEL_COUNT: int = 6

const ACTION_FIRE: int = 1
const ACTION_SHIELD: int = 2
const ACTION_RELOAD: int = 4
const ACTION_SPECIAL: int = 8
const ACTION_MASK: int = ACTION_FIRE | ACTION_SHIELD | ACTION_RELOAD | ACTION_SPECIAL

const HANDSHAKE_TIMEOUT_SECONDS: float = 10.0
const MAX_INPUTS_PER_SECOND: int = 60
const MAX_CONTROL_REQUESTS_PER_SECOND: int = 20
const TRAFFIC_STRIKES_BEFORE_DISCONNECT: int = 3
const MAX_OFFER_TOKEN_LENGTH: int = 64
const MAX_CARD_ID_LENGTH: int = 64
const MAX_LOBBY_PASSWORD_LENGTH: int = 64
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


static func rejection_message(reason: StringName) -> String:
	match reason:
		REJECT_SERVER_FULL:
			return "The server is full."
		REJECT_VERSION_MISMATCH:
			return "Client and server protocol versions do not match."
		REJECT_INVALID_NAME:
			return "Display name must contain 1–16 printable characters."
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
		_:
			return "The server rejected the connection."


static func is_valid_lobby_password(password: String) -> bool:
	if password.is_empty() or password.length() > MAX_LOBBY_PASSWORD_LENGTH:
		return false
	for index in password.length():
		var codepoint := password.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true
