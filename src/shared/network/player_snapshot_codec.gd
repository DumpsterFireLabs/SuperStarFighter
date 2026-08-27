class_name PlayerSnapshotCodec
extends RefCounted

const HEADER_SIZE: int = 10
const PLAYER_RECORD_SIZE: int = 20
const POSITION_SCALE: float = 16.0
const VELOCITY_SCALE: float = 8.0
const RESOURCE_SCALE: float = 100.0


static func encode(server_tick: int, acknowledged_input: int, states: Array[Dictionary]) -> PackedByteArray:
	var bytes := PackedByteArray()
	ByteCodec.append_u8(bytes, NetworkProtocol.PACKET_VERSION)
	ByteCodec.append_u32(bytes, server_tick)
	ByteCodec.append_u32(bytes, acknowledged_input)
	var count := mini(states.size(), NetworkProtocol.MAX_SNAPSHOT_PLAYERS)
	ByteCodec.append_u8(bytes, count)
	for index in count:
		var state := states[index]
		ByteCodec.append_u32(bytes, int(state.get("peer_id", 0)))
		var position: Vector2 = state.get("position", Vector2.ZERO)
		var velocity: Vector2 = state.get("velocity", Vector2.ZERO)
		ByteCodec.append_u16(bytes, roundi(clampf(position.x, 0.0, GameConstants.ARENA_SIZE.x) * POSITION_SCALE))
		ByteCodec.append_u16(bytes, roundi(clampf(position.y, 0.0, GameConstants.ARENA_SIZE.y) * POSITION_SCALE))
		ByteCodec.append_i16(bytes, roundi(clampf(velocity.x, -4095.0, 4095.0) * VELOCITY_SCALE))
		ByteCodec.append_i16(bytes, roundi(clampf(velocity.y, -4095.0, 4095.0) * VELOCITY_SCALE))
		ByteCodec.append_u16(bytes, roundi(MovementSystem.normalize_aim_angle(float(state.get("aim_angle", 0.0))) / TAU * 65535.0))
		ByteCodec.append_u16(bytes, roundi(clampf(float(state.get("health", 0.0)), 0.0, 655.35) * RESOURCE_SCALE))
		ByteCodec.append_u16(bytes, roundi(clampf(float(state.get("shield", 0.0)), 0.0, 655.35) * RESOURCE_SCALE))
		ByteCodec.append_u8(bytes, clampi(int(state.get("ammunition", 0)), 0, 255))
		var flags := 0
		if bool(state.get("alive", true)):
			flags |= 1
		if bool(state.get("shielding", false)):
			flags |= 2
		if bool(state.get("afterburner_active", false)):
			flags |= 4
		ByteCodec.append_u8(bytes, flags)
	return bytes


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE:
		return _error("Player snapshot header is truncated.")
	if ByteCodec.read_u8(bytes, 0) != NetworkProtocol.PACKET_VERSION:
		return _error("Unsupported player snapshot version.")
	var count := ByteCodec.read_u8(bytes, 9)
	if count > NetworkProtocol.MAX_SNAPSHOT_PLAYERS:
		return _error("Player snapshot count exceeds the protocol bound.")
	var expected_size := HEADER_SIZE + count * PLAYER_RECORD_SIZE
	if bytes.size() != expected_size:
		return _error("Player snapshot payload size does not match its count.")
	var states: Array[Dictionary] = []
	var offset := HEADER_SIZE
	for index in count:
		var flags := ByteCodec.read_u8(bytes, offset + 19)
		if flags & ~7:
			return _error("Player snapshot contains unsupported state flags.")
		states.append({
			"peer_id": ByteCodec.read_u32(bytes, offset),
			"position": Vector2(ByteCodec.read_u16(bytes, offset + 4) / POSITION_SCALE, ByteCodec.read_u16(bytes, offset + 6) / POSITION_SCALE),
			"velocity": Vector2(ByteCodec.read_i16(bytes, offset + 8) / VELOCITY_SCALE, ByteCodec.read_i16(bytes, offset + 10) / VELOCITY_SCALE),
			"aim_angle": float(ByteCodec.read_u16(bytes, offset + 12)) / 65535.0 * TAU,
			"health": ByteCodec.read_u16(bytes, offset + 14) / RESOURCE_SCALE,
			"shield": ByteCodec.read_u16(bytes, offset + 16) / RESOURCE_SCALE,
			"ammunition": ByteCodec.read_u8(bytes, offset + 18),
			"alive": bool(flags & 1),
			"shielding": bool(flags & 2),
			"afterburner_active": bool(flags & 4),
		})
		offset += PLAYER_RECORD_SIZE
	return {"ok": true, "server_tick": ByteCodec.read_u32(bytes, 1), "acknowledged_input": ByteCodec.read_u32(bytes, 5), "states": states}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
