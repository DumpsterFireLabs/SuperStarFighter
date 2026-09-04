class_name PlayerSnapshotCodec
extends RefCounted

const HEADER_SIZE: int = 10
const PLAYER_RECORD_SIZE: int = 35
const POSITION_SCALE: float = 16.0
const VELOCITY_SCALE: float = 8.0
const RESOURCE_SCALE: float = 100.0
const LOCAL_FIELDS: Array[StringName] = [
	&"afterburner_remaining", &"afterburner_cooldown_remaining",
	&"breakaway_remaining", &"breakaway_cooldown_remaining",
	&"cloak_remaining", &"cloak_cooldown_remaining",
	&"burst_damage_window_remaining", &"time_since_damage", &"kinetic_vent_feedback_remaining",
	&"weapon_cooldown", &"reload_remaining", &"cadence_remainder",
	&"shield_inactivity", &"guard_window", &"guard_feedback", &"vent_release", &"burst_damage",
]
const LOCAL_STATE_SIZE: int = 57 # Combat correction plus private ordnance usage/counter.


static func encode(server_tick: int, acknowledged_input: int, states: Array[Dictionary], local_state: Dictionary = {}) -> PackedByteArray:
	return assemble(server_tick, acknowledged_input, encode_state_body(states), local_state)


static func encode_state_body(states: Array[Dictionary]) -> PackedByteArray:
	var body := PackedByteArray()
	var count := mini(states.size(), NetworkProtocol.MAX_SNAPSHOT_PLAYERS)
	ByteCodec.append_u8(body, count)
	for index in count:
		_append_state(body, states[index])
	return body


static func encode_combatant_body(combatants: Dictionary, ordered_peer_ids: Array[int], recipient_id: int = -1) -> PackedByteArray:
	var body := PackedByteArray()
	ByteCodec.append_u8(body, 0)
	for peer_id in ordered_peer_ids:
		var combatant := combatants[peer_id] as CombatantState
		# -1 is the full authority/debug view. Network callers always provide a
		# recipient: even allies and spectators receive no hidden ship record.
		if recipient_id >= 0 and peer_id != recipient_id and combatant.is_cloaked():
			continue
		if body[0] >= NetworkProtocol.MAX_SNAPSHOT_PLAYERS:
			break
		_append_combatant(body, peer_id, combatant)
		body[0] += 1
	return body


static func assemble(server_tick: int, acknowledged_input: int, body: PackedByteArray, local_state: Dictionary = {}) -> PackedByteArray:
	var bytes := PackedByteArray()
	ByteCodec.append_u8(bytes, NetworkProtocol.PACKET_VERSION)
	ByteCodec.append_u32(bytes, server_tick)
	ByteCodec.append_u32(bytes, acknowledged_input)
	bytes.append_array(body)
	_append_local_state(bytes, local_state)
	return bytes


static func _local_scale(field: StringName) -> float:
	if field in [&"weapon_cooldown", &"cadence_remainder"]:
		return 10000.0
	return 100.0 if field in [&"burst_damage", &"vent_release"] else 1000.0


static func _append_local_state(bytes: PackedByteArray, state: Dictionary) -> void:
	for field in [&"peer_id", &"life_generation", &"last_special_sequence", &"shot_sequence"]:
		ByteCodec.append_u32(bytes, maxi(int(state.get(field, 0)), 0))
	var flags := (1 if bool(state.get("reloading", false)) else 0)
	flags |= 2 if bool(state.get("shield_locked", false)) else 0
	flags |= 4 if bool(state.get("shield_active", false)) else 0
	flags |= 8 if bool(state.get("shield_depleted", false)) else 0
	flags |= 16 if int(state.get("last_special_sequence", -1)) >= 0 else 0
	ByteCodec.append_u8(bytes, flags)
	for field in LOCAL_FIELDS:
		ByteCodec.append_u16(bytes, clampi(roundi(float(state.get(field, 0.0)) * _local_scale(field)), 0, 65535))
	ByteCodec.append_u8(bytes, clampi(int(state.get("active_ordnance", 0)), 0, 255))
	ByteCodec.append_u8(bytes, clampi(int(state.get("active_mines", 0)), 0, 255))
	ByteCodec.append_u32(bytes, int(state.get("budget_evictions", 0)) & 0xffffffff)


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
		float(state.get("breakaway_cooldown", 0.0)),
		int(state.get("missile_charges", 0)),
		float(state.get("missile_cooldown", 0.0))
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
		combatant.breakaway_cooldown_remaining,
		combatant.missile_charges_remaining,
		combatant.missile_cooldown_remaining
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
	breakaway_cooldown: float,
	missile_charges: int,
	missile_cooldown: float
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
	ByteCodec.append_u16(bytes, clampi(missile_charges, 0, 65535))
	ByteCodec.append_u16(bytes, roundi(clampf(missile_cooldown, 0.0, 65.535) * 1000.0))


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE:
		return _error("Player snapshot header is truncated.")
	if ByteCodec.read_u8(bytes, 0) != NetworkProtocol.PACKET_VERSION:
		return _error("Unsupported player snapshot version.")
	var count := ByteCodec.read_u8(bytes, 9)
	if count > NetworkProtocol.MAX_SNAPSHOT_PLAYERS:
		return _error("Player snapshot count exceeds the protocol bound.")
	var expected_size := HEADER_SIZE + count * PLAYER_RECORD_SIZE + LOCAL_STATE_SIZE
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
			"missile_charges": ByteCodec.read_u16(bytes, offset + 31),
			"missile_cooldown": ByteCodec.read_u16(bytes, offset + 33) / 1000.0,
		})
		offset += PLAYER_RECORD_SIZE
	var local_flags := ByteCodec.read_u8(bytes, offset + 16)
	if local_flags & ~31:
		return _error("Player snapshot contains unsupported local correction flags.")
	var local_state := {
		"peer_id": ByteCodec.read_u32(bytes, offset),
		"life_generation": ByteCodec.read_u32(bytes, offset + 4),
		"last_special_sequence": ByteCodec.read_u32(bytes, offset + 8) if local_flags & 16 else -1,
		"shot_sequence": ByteCodec.read_u32(bytes, offset + 12),
		"reloading": bool(local_flags & 1), "shield_locked": bool(local_flags & 2),
		"shield_active": bool(local_flags & 4), "shield_depleted": bool(local_flags & 8),
	}
	for index in LOCAL_FIELDS.size():
		var field := LOCAL_FIELDS[index]
		local_state[field] = ByteCodec.read_u16(bytes, offset + 17 + index * 2) / _local_scale(field)
	local_state["active_ordnance"] = ByteCodec.read_u8(bytes, offset + 51)
	local_state["active_mines"] = ByteCodec.read_u8(bytes, offset + 52)
	local_state["budget_evictions"] = ByteCodec.read_u32(bytes, offset + 53)
	return {"ok": true, "server_tick": ByteCodec.read_u32(bytes, 1), "acknowledged_input": ByteCodec.read_u32(bytes, 5), "states": states, "local_state": local_state}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
