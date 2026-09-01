class_name PlayerSnapshotCodec
extends RefCounted

const HEADER_SIZE: int = 10
const PLAYER_RECORD_SIZE: int = 31
const POSITION_SCALE: float = 16.0
const VELOCITY_SCALE: float = 8.0
const RESOURCE_SCALE: float = 100.0


static func encode(server_tick: int, acknowledged_input: int, states: Array[Dictionary]) -> PackedByteArray:
	return assemble(server_tick, acknowledged_input, encode_state_body(states))


static func encode_state_body(states: Array[Dictionary]) -> PackedByteArray:
	var body := PackedByteArray()
	var count := mini(states.size(), NetworkProtocol.MAX_SNAPSHOT_PLAYERS)
	ByteCodec.append_u8(body, count)
	for index in count:
		_append_state(body, states[index])
	return body


static func encode_combatant_body(combatants: Dictionary, ordered_peer_ids: Array[int]) -> PackedByteArray:
	var body := PackedByteArray()
	var count := mini(ordered_peer_ids.size(), NetworkProtocol.MAX_SNAPSHOT_PLAYERS)
	ByteCodec.append_u8(body, count)
	for index in count:
		var peer_id := ordered_peer_ids[index]
		var combatant := combatants[peer_id] as CombatantState
		_append_combatant(body, peer_id, combatant)
	return body


static func assemble(server_tick: int, acknowledged_input: int, body: PackedByteArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	ByteCodec.append_u8(bytes, NetworkProtocol.PACKET_VERSION)
	ByteCodec.append_u32(bytes, server_tick)
	ByteCodec.append_u32(bytes, acknowledged_input)
	bytes.append_array(body)
	return bytes


static func _append_state(bytes: PackedByteArray, state: Dictionary) -> void:
	_append_values(
		bytes,
		int(state.get("peer_id", 0)),
		state.get("position", Vector2.ZERO) as Vector2,
		state.get("velocity", Vector2.ZERO) as Vector2,
		float(state.get("aim_angle", 0.0)),
		float(state.get("health", 0.0)),
		float(state.get("shield", 0.0)),
		int(state.get("ammunition", 0)),
		bool(state.get("alive", true)),
		bool(state.get("shielding", false)),
		bool(state.get("afterburner_active", false)),
		int(state.get("mine_charges", 0)),
		float(state.get("mine_cooldown", 0.0)),
		bool(state.get("cloaked", false)),
		int(state.get("cloak_charges", 0)),
		float(state.get("cloak_cooldown", 0.0)),
		bool(state.get("perfect_guard_active", false)),
		bool(state.get("kinetic_vent_active", false)),
		bool(state.get("breakaway_active", false)),
		float(state.get("kinetic_vent_charge", 0.0)),
		float(state.get("breakaway_cooldown", 0.0))
	)


static func _append_combatant(bytes: PackedByteArray, peer_id: int, combatant: CombatantState) -> void:
	_append_values(
		bytes,
		peer_id,
		combatant.position,
		combatant.velocity,
		combatant.aim_angle,
		combatant.health,
		combatant.shield.energy,
		combatant.weapon.ammunition,
		combatant.alive,
		combatant.shield.active,
		combatant.afterburner_remaining > 0.0,
		combatant.mine_charges_remaining,
		combatant.mine_cooldown_remaining,
		combatant.is_cloaked(),
		combatant.cloak_charges_remaining,
		combatant.cloak_cooldown_remaining,
		combatant.shield.is_perfect_guard_active() or combatant.shield.has_perfect_guard_feedback(),
		combatant.kinetic_vent_feedback_remaining > 0.0,
		combatant.breakaway_remaining > 0.0,
		combatant.shield.kinetic_vent_charge,
		combatant.breakaway_cooldown_remaining
	)


static func _append_values(
	bytes: PackedByteArray,
	peer_id: int,
	position: Vector2,
	velocity: Vector2,
	aim_angle: float,
	health: float,
	shield: float,
	ammunition: int,
	alive: bool,
	shielding: bool,
	afterburner_active: bool,
	mine_charges: int,
	mine_cooldown: float,
	cloaked: bool,
	cloak_charges: int,
	cloak_cooldown: float,
	perfect_guard_active: bool,
	kinetic_vent_active: bool,
	breakaway_active: bool,
	kinetic_vent_charge: float,
	breakaway_cooldown: float
) -> void:
	ByteCodec.append_u32(bytes, peer_id)
	ByteCodec.append_u16(bytes, roundi(clampf(position.x, 0.0, GameConstants.ARENA_SIZE.x) * POSITION_SCALE))
	ByteCodec.append_u16(bytes, roundi(clampf(position.y, 0.0, GameConstants.ARENA_SIZE.y) * POSITION_SCALE))
	ByteCodec.append_i16(bytes, roundi(clampf(velocity.x, -4095.0, 4095.0) * VELOCITY_SCALE))
	ByteCodec.append_i16(bytes, roundi(clampf(velocity.y, -4095.0, 4095.0) * VELOCITY_SCALE))
	ByteCodec.append_u16(bytes, roundi(MovementSystem.normalize_aim_angle(aim_angle) / TAU * 65535.0))
	ByteCodec.append_u16(bytes, roundi(clampf(health, 0.0, 655.35) * RESOURCE_SCALE))
	ByteCodec.append_u16(bytes, roundi(clampf(shield, 0.0, 655.35) * RESOURCE_SCALE))
	ByteCodec.append_u8(bytes, clampi(ammunition, 0, 255))
	var flags := 0
	if alive:
		flags |= 1
	if shielding:
		flags |= 2
	if afterburner_active:
		flags |= 4
	if cloaked:
		flags |= 8
	if perfect_guard_active:
		flags |= 16
	if kinetic_vent_active:
		flags |= 32
	if breakaway_active:
		flags |= 64
	ByteCodec.append_u8(bytes, flags)
	ByteCodec.append_u16(bytes, clampi(mine_charges, 0, 65535))
	ByteCodec.append_u16(bytes, roundi(clampf(mine_cooldown, 0.0, 65.535) * 1000.0))
	ByteCodec.append_u16(bytes, clampi(cloak_charges, 0, 65535))
	ByteCodec.append_u16(bytes, roundi(clampf(cloak_cooldown, 0.0, 65.535) * 1000.0))
	ByteCodec.append_u8(bytes, roundi(clampf(kinetic_vent_charge, 0.0, GameConstants.KINETIC_VENT_MAXIMUM_CHARGE)))
	ByteCodec.append_u16(bytes, roundi(clampf(breakaway_cooldown, 0.0, 65.535) * 1000.0))


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
		if flags & ~127:
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
			"mine_charges": ByteCodec.read_u16(bytes, offset + 20),
			"mine_cooldown": ByteCodec.read_u16(bytes, offset + 22) / 1000.0,
			"cloaked": bool(flags & 8),
			"perfect_guard_active": bool(flags & 16),
			"kinetic_vent_active": bool(flags & 32),
			"breakaway_active": bool(flags & 64),
			"cloak_charges": ByteCodec.read_u16(bytes, offset + 24),
			"cloak_cooldown": ByteCodec.read_u16(bytes, offset + 26) / 1000.0,
			"kinetic_vent_charge": float(ByteCodec.read_u8(bytes, offset + 28)),
			"breakaway_cooldown": ByteCodec.read_u16(bytes, offset + 29) / 1000.0,
		})
		offset += PLAYER_RECORD_SIZE
	return {"ok": true, "server_tick": ByteCodec.read_u32(bytes, 1), "acknowledged_input": ByteCodec.read_u32(bytes, 5), "states": states}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
