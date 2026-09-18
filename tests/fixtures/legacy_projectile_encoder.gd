# Frozen projectile wire-layout reference encoder: keep independent of the production writer.
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


