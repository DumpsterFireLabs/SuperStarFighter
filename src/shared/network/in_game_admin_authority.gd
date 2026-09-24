class_name InGameAdminAuthority
extends RefCounted

const AuthenticationAttemptLimiterScript = preload("res://src/shared/network/authentication_attempt_limiter.gd")
const CHALLENGE_LIFETIME_SECONDS := 10.0

var _password: String = ""
var _pending: Dictionary = {}
var _authorized: Dictionary = {}
var _failures := AuthenticationAttemptLimiterScript.new(
	NetworkProtocol.ADMIN_AUTH_FAILURE_LIMIT,
	NetworkProtocol.ADMIN_AUTH_FAILURE_WINDOW_SECONDS,
	NetworkProtocol.ADMIN_AUTH_COOLDOWN_SECONDS
)


func configure(password: String) -> void:
	clear()
	if NetworkProtocol.is_valid_admin_password(password):
		_password = password


func enabled() -> bool:
	return not _password.is_empty()


func begin(peer_id: int, source: String, now: float) -> Dictionary:
	if not enabled():
		return {"ok": false, "error": "In-game administration is disabled on this server."}
	if _failures.is_blocked(source, now):
		return {"ok": false, "error": "Too many failed admin attempts. Try again later."}
	var challenge := Crypto.new().generate_random_bytes(NetworkProtocol.AUTH_CHALLENGE_BYTES).hex_encode()
	_pending[peer_id] = {"challenge": challenge, "expires_at": now + CHALLENGE_LIFETIME_SECONDS}
	return {"ok": true, "event": "challenge", "challenge": challenge}


func authenticate(peer_id: int, source: String, proof: String, now: float) -> Dictionary:
	if _failures.is_blocked(source, now):
		return {"ok": false, "error": "Too many failed admin attempts. Try again later."}
	var pending := _pending.get(peer_id, {}) as Dictionary
	_pending.erase(peer_id)
	if pending.is_empty() or now > float(pending.get("expires_at", 0.0)):
		return {"ok": false, "error": "Admin challenge expired. Try again."}
	var expected := NetworkProtocol.admin_password_proof(String(pending.challenge), _password)
	if not NetworkProtocol.is_valid_auth_proof(proof) or not NetworkProtocol.constant_time_string_equal(proof, expected):
		_failures.register_failure(source, now)
		return {"ok": false, "error": "Admin password was incorrect."}
	_authorized[peer_id] = {"challenge": String(pending.challenge), "sequence": 0}
	return {"ok": true, "event": "authenticated"}


func is_authorized(peer_id: int) -> bool:
	return _authorized.has(peer_id)


func verify_command(peer_id: int, sequence: int, request: Dictionary, signature: String) -> bool:
	if not _authorized.has(peer_id):
		return false
	var state := _authorized[peer_id] as Dictionary
	if sequence != int(state.sequence) + 1 or not NetworkProtocol.is_valid_auth_proof(signature):
		return false
	var expected := NetworkProtocol.admin_command_signature(String(state.challenge), _password, sequence, request)
	if expected.is_empty() or not NetworkProtocol.constant_time_string_equal(signature, expected):
		return false
	state.sequence = sequence
	_authorized[peer_id] = state
	return true


func revoke(peer_id: int) -> void:
	_pending.erase(peer_id)
	_authorized.erase(peer_id)


func clear() -> void:
	_password = ""
	_pending.clear()
	_authorized.clear()
	_failures.clear()
