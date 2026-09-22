class_name NetworkReplicationScheduler
extends RefCounted

# Owns packet scheduling and correction assembly, never the RPC authority boundary.
const ProjectileCorrectionAssemblerScript = preload("res://src/shared/network/projectile_correction_assembler.gd")
const PARTIAL_PROJECTILE_CORRECTION_COUNT: int = 40
# Two unacknowledged chunks per peer bound reliable recovery in the transport.
# One new chunk per six physics ticks leaves room for live snapshots and deltas.
const RECOVERY_WINDOW: int = 2
const RECOVERY_INTERVAL_TICKS: int = 6
var _recoveries: Dictionary = {}
var _recovery_clock: int = 0
var _congested_until: Dictionary = {}
var _snapshot_round: int = 0
var _payload_bytes: Dictionary = {}
var _peak_recovery_queue: int = 0
signal player_snapshot_ready(peer_id: int, packet: PackedByteArray)
signal projectile_batch_ready(packet: PackedByteArray)
signal projectile_correction_ready(packet: PackedByteArray)
signal projectile_recovery_ready(peer_id: int, packet: PackedByteArray)
signal combat_feedback_ready(peer_id: int, tick: int, payload: Dictionary)
signal mine_detonations_ready(tick: int, events: Array)

var _outbound_bytes: int = 0
var _paused_replication_ticks: int = 0
var _projectile_message_sequence: int = 0
var _projectile_correction_cursor: int = 0
var _projectile_correction_send_count: int = 0
var _projectile_correction_assembler := ProjectileCorrectionAssemblerScript.new()


func clear() -> void:
	_paused_replication_ticks = 0
	_projectile_message_sequence = 0
	_projectile_correction_cursor = 0
	_projectile_correction_send_count = 0
	_projectile_correction_assembler.clear()
	_recoveries.clear()
	_congested_until.clear()
	_recovery_clock = 0
	_snapshot_round = 0


func replicate_tick(tick: int, lobby: ServerLobby, world: AuthoritativeWorld) -> void:
	# Keep connections and late spectators refreshed while the game clock is frozen.
	if world != null and world.simulation_paused:
		_paused_replication_ticks += 1
		tick = _paused_replication_ticks
	else:
		_paused_replication_ticks = 0
	if lobby != null and lobby.match_active and tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PLAYER_SNAPSHOT_RATE) == 0:
		_send_player_snapshots(lobby, world)
	_send_projectile_batch(lobby, world)
	_send_mine_detonations(lobby, world)
	if lobby != null and lobby.match_active and tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PROJECTILE_CORRECTION_RATE) == 0:
		_send_projectile_correction(lobby, world)
	_flush_recovery(lobby)
	if tick % 3 == 0:
		_send_combat_feedback(lobby, world)


func _send_player_snapshots(lobby: ServerLobby, world: AuthoritativeWorld) -> void:
	if lobby == null or lobby.players.is_empty():
		return
	var public_body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), 0)
	_snapshot_round += 1
	for peer_id in lobby.human_peer_ids_view():
		# Backlogged recovery ACKs signal a constrained path. Temporarily halve
		# snapshot traffic for that peer; keep inputs and gameplay deltas intact.
		if _recovery_clock < int(_congested_until.get(peer_id, 0)) and _snapshot_round % 2 == 0:
			continue
		var combatant := world.combatants.get(peer_id) as CombatantState
		var body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), peer_id) if combatant != null and combatant.is_cloaked() else public_body
		var correction := combatant.prediction_state() if combatant != null else {}
		correction["input_age_ticks"] = roundi(float(world.input_ages.get(peer_id, 0.0)) * GameConstants.PHYSICS_TICKS_PER_SECOND)
		correction["active_ordnance"] = world.projectile_registry.count_for_owner(peer_id)
		correction["active_mines"] = world.projectile_registry.mine_count_for_owner(peer_id)
		correction["budget_evictions"] = world.projectile_registry.budget_evictions_for_owner(peer_id)
		var packet := PlayerSnapshotCodec.assemble(world.server_tick, world.acknowledged_input(peer_id), body, correction)
		player_snapshot_ready.emit(peer_id, packet)
		record_payload("players", packet.size())


func _send_combat_feedback(lobby: ServerLobby, world: AuthoritativeWorld) -> void:
	var feedback := world.drain_combat_feedback()
	if lobby == null or feedback.is_empty():
		return
	for peer_id in lobby.human_peer_ids_view():
		var payload := CombatFeedbackBuffer.for_recipient(feedback, world.combatants, peer_id, world.server_tick)
		if not payload.is_empty():
			combat_feedback_ready.emit(peer_id, world.server_tick, payload)
			record_payload("feedback", var_to_bytes(payload).size())


func _send_mine_detonations(lobby: ServerLobby, world: AuthoritativeWorld) -> void:
	var events := world.drain_mine_detonations()
	if lobby == null or lobby.human_count() == 0:
		return
	for start in range(0, events.size(), 8):
		var chunk := events.slice(start, start + 8)
		mine_detonations_ready.emit(world.server_tick, chunk)
		record_payload("feedback", var_to_bytes(chunk).size() * lobby.human_count())


func _send_projectile_batch(lobby: ServerLobby, world: AuthoritativeWorld) -> void:
	if not world.has_projectile_batch():
		return
	var batch := world.drain_projectile_batch()
	if lobby == null or lobby.human_count() == 0:
		return
	var sequence := _next_projectile_message_sequence()
	var packets := ProjectilePacketCodec.encode_batch_chunks(
		world.server_tick,
		sequence,
		batch.spawned as Array[ProjectileState],
		batch.removed as Array[int]
	)
	for packet in packets:
		projectile_batch_ready.emit(packet)
		record_payload("projectile_delta", packet.size() * lobby.human_count())


func _send_projectile_correction(lobby: ServerLobby, world: AuthoritativeWorld) -> void:
	if lobby == null or lobby.human_count() == 0:
		return
	var complete_snapshot := _projectile_correction_send_count % GameConstants.PROJECTILE_CORRECTION_RATE == 0
	_projectile_correction_send_count += 1
	if world.projectile_registry.size() == 0 and not complete_snapshot:
		return
	var active := _projectiles_for_correction(world, complete_snapshot)
	var sequence := _next_projectile_message_sequence()
	var packets := ProjectilePacketCodec.encode_correction_chunks(
		world.server_tick,
		sequence,
		active,
		complete_snapshot
	)
	if complete_snapshot:
		for peer_id in lobby.human_peer_ids_view():
			if not _recoveries.has(peer_id):
				_recoveries[peer_id] = {"packets": packets, "next": 0, "inflight": {},
					"sequence": sequence, "tick": world.server_tick, "next_send": _recovery_clock}
		_peak_recovery_queue = maxi(_peak_recovery_queue, packets.size())
	else:
		for packet in packets:
			projectile_correction_ready.emit(packet)
			record_payload("projectile_motion", packet.size() * lobby.human_count())


func _flush_recovery(lobby: ServerLobby) -> void:
	if lobby == null or not lobby.match_active or lobby.human_count() == 0:
		_recoveries.clear()
		_congested_until.clear()
		return
	_recovery_clock += 1
	for peer_id in _congested_until.keys():
		if _recovery_clock >= int(_congested_until[peer_id]) or not lobby.human_peer_ids_view().has(peer_id):
			_congested_until.erase(peer_id)
	for peer_id in _recoveries.keys():
		if not lobby.human_peer_ids_view().has(peer_id):
			_recoveries.erase(peer_id)
			continue
		var state: Dictionary = _recoveries[peer_id]
		var packets: Array = state.packets
		var inflight: Dictionary = state.inflight
		for sent_at: int in inflight.values():
			if _recovery_clock - sent_at >= 12:
				_congested_until[peer_id] = _recovery_clock + 120
		if inflight.size() >= RECOVERY_WINDOW or int(state.next) >= packets.size() or _recovery_clock < int(state.next_send):
			continue
		var index := int(state.next)
		state.next = index + 1
		var packet: PackedByteArray = packets[index]
		inflight[index] = _recovery_clock
		state.next_send = _recovery_clock + RECOVERY_INTERVAL_TICKS
		projectile_recovery_ready.emit(peer_id, packet)
		record_payload("projectile_recovery", packet.size())


func acknowledge_recovery(peer_id: int, tick: int, sequence: int, chunk: int) -> void:
	var state: Dictionary = _recoveries.get(peer_id, {})
	if state.is_empty() or int(state.tick) != tick or int(state.sequence) != sequence:
		return
	var inflight: Dictionary = state.inflight
	# Only an actually sent chunk can release capacity. Duplicate/forged ACKs
	# cannot enlarge the window; the bridge derives peer_id from the RPC sender.
	if not inflight.erase(chunk):
		return
	if int(state.next) == state.packets.size() and inflight.is_empty():
		_recoveries.erase(peer_id)


func payload_metrics() -> Dictionary:
	var pending := 0
	var inflight := 0
	for state: Dictionary in _recoveries.values():
		pending = maxi(pending, state.packets.size() - int(state.next))
		inflight = maxi(inflight, state.inflight.size())
	return {"scope": "application payload estimate; excludes RPC/ENet/IP overhead and retransmission",
		"bytes_by_category": _payload_bytes.duplicate(), "recovery_pending_chunks": pending,
		"recovery_inflight_chunks_per_peer": inflight, "recovery_active_peers": _recoveries.size(),
		"congested_peers": _congested_until.size(),
		"peak_recovery_chunks": _peak_recovery_queue}


func record_payload(category: String, count: int) -> void:
	assert(category in ["players", "feedback", "projectile_delta", "projectile_motion", "projectile_recovery", "control"])
	_payload_bytes[category] = int(_payload_bytes.get(category, 0)) + maxi(count, 0)
	_outbound_bytes += maxi(count, 0)


func _projectiles_for_correction(world: AuthoritativeWorld, complete_snapshot: bool) -> Array[ProjectileState]:
	var active: Array[ProjectileState] = []
	if complete_snapshot:
		active = world.active_projectiles()
	else:
		var window := world.projectile_registry.projectile_window(
			_projectile_correction_cursor,
			PARTIAL_PROJECTILE_CORRECTION_COUNT
		)
		active = window.projectiles as Array[ProjectileState]
		_projectile_correction_cursor = int(window.next_slot)
		# Guided flight needs every correction even during heavy ordinary fire.
		var included_ids: Dictionary = {}
		for projectile in active:
			included_ids[projectile.projectile_id] = true
		for projectile in world.active_projectiles():
			if projectile.is_missile and not included_ids.has(projectile.projectile_id):
				active.append(projectile)
	return active


func _next_projectile_message_sequence() -> int:
	_projectile_message_sequence = (_projectile_message_sequence + 1) & 0xffff
	return _projectile_message_sequence


func accept_projectile_correction_chunk(decoded: Dictionary) -> Dictionary:
	return _projectile_correction_assembler.accept(decoded)


func record_outbound_bytes(count: int) -> void:
	record_payload("control", count)


func outbound_bytes() -> int:
	return _outbound_bytes


func reset_outbound_bytes() -> void:
	_outbound_bytes = 0
	_payload_bytes.clear()
	_peak_recovery_queue = int(payload_metrics().recovery_pending_chunks)
