class_name InputPacketCodec
extends RefCounted

const PACKET_SIZE: int = 16
const MOVEMENT_SCALE: float = 32767.0
const MOVEMENT_TOLERANCE_SQUARED: float = 1.05 * 1.05


static func encode(frame: PlayerInputFrame) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(0)
	ByteCodec.append_u8(bytes, NetworkProtocol.PACKET_VERSION)
	ByteCodec.append_u32(bytes, frame.sequence)
	ByteCodec.append_u32(bytes, frame.client_tick)
	var movement := MovementSystem.sanitize_input(frame.movement)
	ByteCodec.append_i16(bytes, roundi(movement.x * MOVEMENT_SCALE))
	ByteCodec.append_i16(bytes, roundi(movement.y * MOVEMENT_SCALE))
	var normalized_aim := MovementSystem.normalize_aim_angle(frame.aim_angle)
	ByteCodec.append_u16(bytes, roundi(normalized_aim / TAU * 65535.0))
	var action_bits := 0
	if frame.firing:
		action_bits |= NetworkProtocol.ACTION_FIRE
	if frame.shielding:
		action_bits |= NetworkProtocol.ACTION_SHIELD
	if frame.manual_reload:
		action_bits |= NetworkProtocol.ACTION_RELOAD
	if frame.special_activated:
		action_bits |= NetworkProtocol.ACTION_SPECIAL
	ByteCodec.append_u8(bytes, action_bits)
	return bytes


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != PACKET_SIZE:
		return _error("Input packet must contain exactly %d bytes." % PACKET_SIZE)
	if ByteCodec.read_u8(bytes, 0) != NetworkProtocol.PACKET_VERSION:
		return _error("Unsupported input packet version.")
	var raw_x := ByteCodec.read_i16(bytes, 9)
	var raw_y := ByteCodec.read_i16(bytes, 11)
	if raw_x == -32768 or raw_y == -32768:
		return _error("Input movement uses an invalid signed endpoint.")
	var movement := Vector2(raw_x / MOVEMENT_SCALE, raw_y / MOVEMENT_SCALE)
	if not movement.is_finite() or movement.length_squared() > MOVEMENT_TOLERANCE_SQUARED:
		return _error("Input movement exceeds the accepted magnitude.")
	var action_bits := ByteCodec.read_u8(bytes, 15)
	if action_bits & ~NetworkProtocol.ACTION_MASK:
		return _error("Input packet contains unsupported action bits.")
	var frame := PlayerInputFrame.new(
		ByteCodec.read_u32(bytes, 1),
		ByteCodec.read_u32(bytes, 5),
		movement.limit_length(1.0),
		float(ByteCodec.read_u16(bytes, 13)) / 65535.0 * TAU,
		bool(action_bits & NetworkProtocol.ACTION_FIRE),
		bool(action_bits & NetworkProtocol.ACTION_SHIELD),
		bool(action_bits & NetworkProtocol.ACTION_RELOAD),
		bool(action_bits & NetworkProtocol.ACTION_SPECIAL)
	)
	return {"ok": true, "frame": frame}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
