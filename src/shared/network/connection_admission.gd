class_name ConnectionAdmission
extends RefCounted


static func validate_hello(
	protocol_version: int,
	display_name: String,
	current_players: int,
	maximum_players: int,
	supplied_proof: String = "",
	expected_proof: String = ""
) -> StringName:
	if protocol_version != GameConstants.PROTOCOL_VERSION:
		return NetworkProtocol.REJECT_VERSION_MISMATCH
	if ServerLobby.sanitize_display_name(display_name).is_empty():
		return NetworkProtocol.REJECT_INVALID_NAME
	if current_players >= maximum_players:
		return NetworkProtocol.REJECT_SERVER_FULL
	if not NetworkProtocol.is_valid_auth_proof(supplied_proof):
		return NetworkProtocol.REJECT_INVALID_PASSWORD
	if not NetworkProtocol.constant_time_string_equal(supplied_proof, expected_proof):
		return NetworkProtocol.REJECT_INVALID_PASSWORD
	return &""
