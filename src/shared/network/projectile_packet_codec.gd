class_name ProjectilePacketCodec
extends RefCounted

const HEADER_SIZE: int = 14
const PROJECTILE_RECORD_SIZE: int = 31
const POSITION_SCALE: float = 16.0
const VELOCITY_SCALE: float = 8.0
const DAMAGE_SCALE: float = 100.0
const LIFETIME_SCALE: float = 1000.0

const KIND_DELTA: int = 0
const KIND_PARTIAL_CORRECTION: int = 1
const KIND_FULL_CORRECTION: int = 2


static func encode_batch_chunks(
	server_tick: int,
	batch_sequence: int,
	spawned: Array[ProjectileState],
	removed: Array[int]
) -> Array[PackedByteArray]:
	return _encode_chunks(server_tick, batch_sequence, KIND_DELTA, spawned, removed)


static func encode_correction_chunks(
	server_tick: int,
	batch_sequence: int,
	active: Array[ProjectileState],
	complete_snapshot: bool
) -> Array[PackedByteArray]:
	var kind := KIND_FULL_CORRECTION if complete_snapshot else KIND_PARTIAL_CORRECTION
	return _encode_chunks(server_tick, batch_sequence, kind, active, [])


static func _encode_chunks(
	server_tick: int,
	batch_sequence: int,
	kind: int,
	spawned: Array[ProjectileState],
	removed: Array[int]
) -> Array[PackedByteArray]:
	var pieces: Array[Dictionary] = []
	var spawn_index := 0
	var removed_index := 0
	while spawn_index < spawned.size() or removed_index < removed.size() or pieces.is_empty():
		var chunk_spawned: Array[ProjectileState] = []
		var chunk_removed: Array[int] = []
		var remaining_bytes := NetworkProtocol.MAX_PROJECTILE_MESSAGE_BYTES - HEADER_SIZE - 2
		while spawn_index < spawned.size() and remaining_bytes >= PROJECTILE_RECORD_SIZE:
			chunk_spawned.append(spawned[spawn_index])
			spawn_index += 1
			remaining_bytes -= PROJECTILE_RECORD_SIZE
		while removed_index < removed.size() and remaining_bytes >= 4:
			chunk_removed.append(removed[removed_index])
			removed_index += 1
			remaining_bytes -= 4
		pieces.append({"spawned": chunk_spawned, "removed": chunk_removed})
	var result: Array[PackedByteArray] = []
	for chunk_index in pieces.size():
		var piece := pieces[chunk_index] as Dictionary
		result.append(_encode_chunk(
			server_tick,
			batch_sequence,
			kind,
			chunk_index,
			pieces.size(),
			piece.spawned as Array[ProjectileState],
			piece.removed as Array[int]
		))
	return result


static func _encode_chunk(
	server_tick: int,
	batch_sequence: int,
	kind: int,
	chunk_index: int,
	chunk_count: int,
	spawned: Array[ProjectileState],
	removed: Array[int]
) -> PackedByteArray:
	var bytes := PackedByteArray()
	ByteCodec.append_u8(bytes, NetworkProtocol.PACKET_VERSION)
	ByteCodec.append_u32(bytes, server_tick)
	ByteCodec.append_u8(bytes, kind)
	ByteCodec.append_u16(bytes, batch_sequence & 0xffff)
	ByteCodec.append_u16(bytes, chunk_index)
	ByteCodec.append_u16(bytes, chunk_count)
	ByteCodec.append_u16(bytes, spawned.size())
	for projectile in spawned:
		_append_projectile(bytes, projectile)
	ByteCodec.append_u16(bytes, removed.size())
	for projectile_id in removed:
		ByteCodec.append_u32(bytes, projectile_id)
	return bytes


static func decode_batch(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE + 2:
		return _error("Projectile packet header is truncated.")
	if ByteCodec.read_u8(bytes, 0) != NetworkProtocol.PACKET_VERSION:
		return _error("Unsupported projectile packet version.")
	if bytes.size() > NetworkProtocol.MAX_PROJECTILE_MESSAGE_BYTES:
		return _error("Projectile packet exceeds the transport message budget.")
	var kind := ByteCodec.read_u8(bytes, 5)
	if kind < KIND_DELTA or kind > KIND_FULL_CORRECTION:
		return _error("Projectile packet kind is invalid.")
	var chunk_index := ByteCodec.read_u16(bytes, 8)
	var chunk_count := ByteCodec.read_u16(bytes, 10)
	if chunk_count == 0 or chunk_index >= chunk_count:
		return _error("Projectile packet chunk metadata is invalid.")
	var spawn_count := ByteCodec.read_u16(bytes, 12)
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
		if ByteCodec.read_u32(bytes, offset) == ProjectileRegistry.REMOVED_ID:
			return _error("Projectile ID zero is reserved.")
		if (ByteCodec.read_u8(bytes, offset + 26) & 0xf0) != 0:
			return _error("Projectile packet contains unsupported presentation flags.")
		spawned.append(_read_projectile(bytes, offset))
		offset += PROJECTILE_RECORD_SIZE
	var removed: Array[int] = []
	offset += 2
	for index in removed_count:
		var projectile_id := ByteCodec.read_u32(bytes, offset)
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			return _error("Projectile ID zero is reserved.")
		removed.append(projectile_id)
		offset += 4
	return {
		"ok": true,
		"server_tick": ByteCodec.read_u32(bytes, 1),
		"kind": kind,
		"batch_sequence": ByteCodec.read_u16(bytes, 6),
		"chunk_index": chunk_index,
		"chunk_count": chunk_count,
		"complete_snapshot": kind == KIND_FULL_CORRECTION,
		"spawned": spawned,
		"removed": removed,
	}


static func decode_correction(bytes: PackedByteArray) -> Dictionary:
	var decoded := decode_batch(bytes)
	if decoded.ok and int(decoded.kind) == KIND_DELTA:
		return _error("Projectile correction packet has the wrong kind.")
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
	var serialized_lifetime := projectile.mine_activation_remaining if projectile.is_mine else projectile.lifetime_remaining
	ByteCodec.append_u16(bytes, roundi(clampf(serialized_lifetime, 0.0, 65.535) * LIFETIME_SCALE))
	var flags := 0
	if projectile.is_beam:
		flags |= 1
	if projectile.is_mine:
		flags |= 2
	if projectile.has_rebounded:
		flags |= 4
	if projectile.is_missile:
		flags |= 8
	ByteCodec.append_u8(bytes, flags)
	ByteCodec.append_u32(bytes, projectile.missile_target_id)


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
	var flags := ByteCodec.read_u8(bytes, offset + 26)
	projectile.is_beam = (flags & 1) != 0
	projectile.is_mine = (flags & 2) != 0
	projectile.has_rebounded = (flags & 4) != 0
	projectile.is_missile = (flags & 8) != 0
	projectile.missile_target_id = ByteCodec.read_u32(bytes, offset + 27)
	if projectile.is_mine:
		projectile.radius = GameConstants.MINE_RADIUS
		projectile.mine_activation_remaining = projectile.lifetime_remaining
		projectile.lifetime_remaining = INF
	elif projectile.is_missile:
		projectile.radius = GameConstants.MISSILE_RADIUS
	return projectile


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
