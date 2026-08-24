class_name ProjectilePacketCodec
extends RefCounted

const HEADER_SIZE: int = 7
const PROJECTILE_RECORD_SIZE: int = 26
const POSITION_SCALE: float = 16.0
const VELOCITY_SCALE: float = 8.0
const DAMAGE_SCALE: float = 100.0
const LIFETIME_SCALE: float = 1000.0


static func encode_batch(
	server_tick: int,
	spawned: Array[ProjectileState],
	removed: Array[int]
) -> PackedByteArray:
	var bytes := PackedByteArray()
	ByteCodec.append_u8(bytes, NetworkProtocol.PACKET_VERSION)
	ByteCodec.append_u32(bytes, server_tick)
	var spawn_count := mini(spawned.size(), NetworkProtocol.MAX_PACKET_PROJECTILES)
	ByteCodec.append_u16(bytes, spawn_count)
	for index in spawn_count:
		_append_projectile(bytes, spawned[index])
	var remaining_capacity := NetworkProtocol.MAX_PACKET_PROJECTILES - spawn_count
	var removed_count := mini(removed.size(), remaining_capacity)
	ByteCodec.append_u16(bytes, removed_count)
	for index in removed_count:
		ByteCodec.append_u32(bytes, removed[index])
	return bytes


static func decode_batch(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE + 2:
		return _error("Projectile packet header is truncated.")
	if ByteCodec.read_u8(bytes, 0) != NetworkProtocol.PACKET_VERSION:
		return _error("Unsupported projectile packet version.")
	var spawn_count := ByteCodec.read_u16(bytes, 5)
	if spawn_count > NetworkProtocol.MAX_PACKET_PROJECTILES:
		return _error("Projectile spawn count exceeds the protocol bound.")
	var removed_count_offset := HEADER_SIZE + spawn_count * PROJECTILE_RECORD_SIZE
	if bytes.size() < removed_count_offset + 2:
		return _error("Projectile spawn records are truncated.")
	var removed_count := ByteCodec.read_u16(bytes, removed_count_offset)
	if spawn_count + removed_count > NetworkProtocol.MAX_PACKET_PROJECTILES:
		return _error("Projectile entity count exceeds the protocol bound.")
	var expected_size := removed_count_offset + 2 + removed_count * 4
	if bytes.size() != expected_size:
		return _error("Projectile packet payload size does not match its counts.")
	var spawned: Array[ProjectileState] = []
	var offset := HEADER_SIZE
	for index in spawn_count:
		spawned.append(_read_projectile(bytes, offset))
		offset += PROJECTILE_RECORD_SIZE
	var removed: Array[int] = []
	offset += 2
	for index in removed_count:
		removed.append(ByteCodec.read_u32(bytes, offset))
		offset += 4
	return {"ok": true, "server_tick": ByteCodec.read_u32(bytes, 1), "spawned": spawned, "removed": removed}


static func encode_correction(server_tick: int, active: Array[ProjectileState]) -> PackedByteArray:
	return encode_batch(server_tick, active, [])


static func decode_correction(bytes: PackedByteArray) -> Dictionary:
	var decoded := decode_batch(bytes)
	if decoded.ok and not (decoded.removed as Array).is_empty():
		return _error("Projectile correction packets cannot contain removals.")
	return decoded


static func _append_projectile(bytes: PackedByteArray, projectile: ProjectileState) -> void:
	ByteCodec.append_u32(bytes, projectile.projectile_id)
	ByteCodec.append_u32(bytes, projectile.owner_id)
	ByteCodec.append_u32(bytes, projectile.shot_sequence)
	ByteCodec.append_u16(bytes, roundi(clampf(projectile.position.x, 0.0, GameConstants.ARENA_SIZE.x) * POSITION_SCALE))
	ByteCodec.append_u16(bytes, roundi(clampf(projectile.position.y, 0.0, GameConstants.ARENA_SIZE.y) * POSITION_SCALE))
	ByteCodec.append_i16(bytes, roundi(clampf(projectile.velocity.x, -4095.0, 4095.0) * VELOCITY_SCALE))
	ByteCodec.append_i16(bytes, roundi(clampf(projectile.velocity.y, -4095.0, 4095.0) * VELOCITY_SCALE))
	ByteCodec.append_u16(bytes, roundi(clampf(projectile.damage, 0.0, 655.35) * DAMAGE_SCALE))
	ByteCodec.append_u8(bytes, clampi(projectile.remaining_pierces, 0, 255))
	ByteCodec.append_u8(bytes, clampi(projectile.remaining_ricochets, 0, 255))
	ByteCodec.append_u16(bytes, roundi(clampf(projectile.lifetime_remaining, 0.0, 65.535) * LIFETIME_SCALE))


static func _read_projectile(bytes: PackedByteArray, offset: int) -> ProjectileState:
	var projectile := ProjectileState.new()
	projectile.projectile_id = ByteCodec.read_u32(bytes, offset)
	projectile.owner_id = ByteCodec.read_u32(bytes, offset + 4)
	projectile.shot_sequence = ByteCodec.read_u32(bytes, offset + 8)
	projectile.position = Vector2(ByteCodec.read_u16(bytes, offset + 12) / POSITION_SCALE, ByteCodec.read_u16(bytes, offset + 14) / POSITION_SCALE)
	projectile.velocity = Vector2(ByteCodec.read_i16(bytes, offset + 16) / VELOCITY_SCALE, ByteCodec.read_i16(bytes, offset + 18) / VELOCITY_SCALE)
	projectile.damage = ByteCodec.read_u16(bytes, offset + 20) / DAMAGE_SCALE
	projectile.remaining_pierces = ByteCodec.read_u8(bytes, offset + 22)
	projectile.remaining_ricochets = ByteCodec.read_u8(bytes, offset + 23)
	projectile.lifetime_remaining = ByteCodec.read_u16(bytes, offset + 24) / LIFETIME_SCALE
	return projectile


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
