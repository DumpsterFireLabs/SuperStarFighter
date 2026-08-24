class_name ConnectionAdmission
extends RefCounted


static func validate_hello(
	protocol_version: int,
	display_name: String,
	current_players: int,
	maximum_players: int
) -> StringName:
	if protocol_version != GameConstants.PROTOCOL_VERSION:
		return NetworkProtocol.REJECT_VERSION_MISMATCH
	if not ServerLobby.is_valid_display_name(display_name.strip_edges()):
		return NetworkProtocol.REJECT_INVALID_NAME
	if current_players >= maximum_players:
		return NetworkProtocol.REJECT_SERVER_FULL
	return &""
