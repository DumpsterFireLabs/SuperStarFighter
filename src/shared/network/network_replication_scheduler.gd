class_name NetworkReplicationScheduler
extends RefCounted

# Owns packet scheduling and correction assembly, never the RPC authority boundary.
const ProjectileCorrectionAssemblerScript = preload("res://src/shared/network/projectile_correction_assembler.gd")
const PARTIAL_PROJECTILE_CORRECTION_COUNT: int = 40
# TCP delivers every projectile delta in order, so a complete projectile
# snapshot is only needed by a peer without one this match (match start, a
# join or a rejoin) and as a slow safety net against simulation drift.
const FULL_SNAPSHOT_INTERVAL_SECONDS: int = 10
# One chunk per six physics ticks leaves room for live snapshots and deltas.
const RECOVERY_INTERVAL_TICKS: int = 6
# peer_id -> {packets, next, next_send}: a complete snapshot being paced out.
var _recoveries: Dictionary = {}
# Peers that hold a complete projectile set for the current match.
var _synchronized_peers: Dictionary = {}
var _recovery_clock: int = 0
# Peers whose outbound TCP stream is backlogged (see NetworkSessionOwner probes).
var _transport_congested: Dictionary = {}
# Peers so far behind that replaceable streams are paused (a copy, so starts
# and finishes can be detected), and the union excluded from those streams.
var _transport_resyncing: Dictionary = {}
var _replaceable_excluded: Dictionary = {}
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
	_synchronized_peers.clear()
	_transport_congested = {}
	_transport_resyncing = {}
	_replaceable_excluded = {}
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
		if _transport_resyncing.has(peer_id):
			continue
		# A backlogged TCP stream would deliver every queued snapshot late; send
		# one in four (5 Hz) so the backlog drains and the next one is fresh.
		if _transport_congested.has(peer_id) and _snapshot_round % 4 != 0:
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
		if _transport_resyncing.has(peer_id):
			continue
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
		record_payload("feedback", var_to_bytes(chunk).size() * maxi(lobby.human_count() - _transport_resyncing.size(), 0))


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
		record_payload("projectile_delta", packet.size() * maxi(lobby.human_count() - _transport_resyncing.size(), 0))


func _send_projectile_correction(lobby: ServerLobby, world: AuthoritativeWorld) -> void:
	if lobby == null or lobby.human_count() == 0:
		return
	var periodic := _projectile_correction_send_count % (GameConstants.PROJECTILE_CORRECTION_RATE * FULL_SNAPSHOT_INTERVAL_SECONDS) == 0
	_projectile_correction_send_count += 1
	var unsynchronized: Array[int] = []
	for peer_id in lobby.human_peer_ids_view():
		if not _recoveries.has(peer_id) and not _transport_resyncing.has(peer_id) and (periodic or not _synchronized_peers.has(peer_id)):
			unsynchronized.append(peer_id)
	if not unsynchronized.is_empty():
		_queue_complete_snapshot(unsynchronized, world)
	if world.projectile_registry.size() == 0:
		return
	var packets := ProjectilePacketCodec.encode_correction_chunks(
		world.server_tick,
		_next_projectile_message_sequence(),
		_projectiles_for_correction(world, false),
		false
	)
	var recipients := 0
	for peer_id in lobby.human_peer_ids_view():
		if not _replaceable_excluded.has(peer_id): recipients += 1
	for packet in packets:
		projectile_correction_ready.emit(packet)
		record_payload("projectile_motion", packet.size() * maxi(recipients, 0))


func _queue_complete_snapshot(peer_ids: Array[int], world: AuthoritativeWorld) -> void:
	# One encoding is shared by every recipient; each is paced independently.
	var packets := ProjectilePacketCodec.encode_correction_chunks(
		world.server_tick,
		_next_projectile_message_sequence(),
		_projectiles_for_correction(world, true),
		true
	)
	for peer_id in peer_ids:
		_recoveries[peer_id] = {"packets": packets, "next": 0, "next_send": _recovery_clock}
	_peak_recovery_queue = maxi(_peak_recovery_queue, packets.size())


func _flush_recovery(lobby: ServerLobby) -> void:
	if lobby == null or not lobby.match_active or lobby.human_count() == 0:
		# The next match starts every peer without a projectile set.
		_recoveries.clear()
		_synchronized_peers.clear()
		return
	_recovery_clock += 1
	var humans := lobby.human_peer_ids_view()
	for peer_id in _synchronized_peers.keys():
		if not humans.has(peer_id):
			_synchronized_peers.erase(peer_id)
	for peer_id in _recoveries.keys():
		if not humans.has(peer_id):
			_recoveries.erase(peer_id)
			continue
		var state: Dictionary = _recoveries[peer_id]
		if _recovery_clock < int(state.next_send):
			continue
		var packets: Array = state.packets
		var packet: PackedByteArray = packets[int(state.next)]
		state.next = int(state.next) + 1
		# Pace down on a backlogged stream so snapshots are not starved behind it.
		state.next_send = _recovery_clock + RECOVERY_INTERVAL_TICKS * (4 if _transport_congested.has(peer_id) else 1)
		projectile_recovery_ready.emit(peer_id, packet)
		record_payload("projectile_recovery", packet.size())
		# TCP delivers the queued chunks in order; no acknowledgement is needed.
		if int(state.next) >= packets.size():
			_recoveries.erase(peer_id)
			_synchronized_peers[peer_id] = true


## Sends the peer a fresh complete projectile snapshot at the next correction
## tick, abandoning any snapshot still being paced to it.
func request_complete_snapshot(peer_id: int) -> void:
	_synchronized_peers.erase(peer_id)
	_recoveries.erase(peer_id)


func set_transport_congested_peers(peers: Dictionary) -> void:
	_transport_congested = peers
	_refresh_replaceable_exclusions()


func transport_congested_peers() -> Dictionary:
	return _transport_congested


## A resyncing peer's queued replaceable data is already stale. Its projectile
## set is forgotten when the pause starts, so the first correction tick after
## it drains sends a fresh complete snapshot.
func set_transport_resyncing_peers(peers: Dictionary) -> void:
	for peer_id in peers:
		if not _transport_resyncing.has(peer_id):
			request_complete_snapshot(peer_id)
	_transport_resyncing = peers.duplicate()
	_refresh_replaceable_exclusions()


func transport_resyncing_peers() -> Dictionary:
	return _transport_resyncing


## Peers that receive no replaceable broadcast this tick: periodic corrections
## skip congested and resyncing peers.
func correction_excluded_peers() -> Dictionary:
	return _replaceable_excluded


func _refresh_replaceable_exclusions() -> void:
	_replaceable_excluded = _transport_congested.duplicate()
	_replaceable_excluded.merge(_transport_resyncing)


func payload_metrics() -> Dictionary:
	var pending := 0
	for state: Dictionary in _recoveries.values():
		pending = maxi(pending, state.packets.size() - int(state.next))
	return {"scope": "application payload estimate; excludes RPC/WebSocket/TCP overhead and retransmission",
		"bytes_by_category": _payload_bytes.duplicate(), "recovery_pending_chunks": pending,
		"recovery_active_peers": _recoveries.size(), "synchronized_peers": _synchronized_peers.size(),
		"transport_congested_peers": _transport_congested.size(),
		"transport_resyncing_peers": _transport_resyncing.size(),
		"peak_recovery_chunks": _peak_recovery_queue}


func record_payload(category: String, count: int) -> void:
	assert(category in ["players", "feedback", "projectile_delta", "projectile_motion", "projectile_recovery", "control"])
	_payload_bytes[category] = int(_payload_bytes.get(category, 0)) + maxi(count, 0)
	_outbound_bytes += maxi(count, 0)


func _projectiles_for_correction(world: AuthoritativeWorld, complete_snapshot: bool) -> Array[ProjectileState]:
	var active: Array[ProjectileState] = []
	if complete_snapshot:
		active = AuthoritativeWorld.replicated_only(world.active_projectiles())
	else:
		var window := world.projectile_registry.projectile_window(
			_projectile_correction_cursor,
			PARTIAL_PROJECTILE_CORRECTION_COUNT
		)
		active = AuthoritativeWorld.replicated_only(window.projectiles as Array[ProjectileState])
		_projectile_correction_cursor = int(window.next_slot)
		# Guided flight and escort drones need every correction even during heavy ordinary fire.
		var included_ids: Dictionary = {}
		for projectile in active:
			included_ids[projectile.projectile_id] = true
		for projectile in world.active_projectiles():
			if (projectile.is_missile or projectile.is_drone) and AuthoritativeWorld.is_replicated(projectile) and not included_ids.has(projectile.projectile_id):
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
