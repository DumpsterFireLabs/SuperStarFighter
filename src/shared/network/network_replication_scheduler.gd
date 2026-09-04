class_name NetworkReplicationScheduler
extends RefCounted

# Owns packet scheduling and correction assembly, never the RPC authority boundary.
const ProjectileCorrectionAssemblerScript = preload("res://src/shared/network/projectile_correction_assembler.gd")
const PARTIAL_PROJECTILE_CORRECTION_COUNT: int = 40
var bridge: NetworkBridge

var _outbound_bytes: int = 0
var _projectile_message_sequence: int = 0
var _projectile_correction_cursor: int = 0
var _projectile_correction_send_count: int = 0
var _projectile_correction_assembler := ProjectileCorrectionAssemblerScript.new()


func _init(network_bridge: NetworkBridge) -> void:
	bridge = network_bridge


func clear() -> void:
	_projectile_message_sequence = 0
	_projectile_correction_cursor = 0
	_projectile_correction_send_count = 0
	_projectile_correction_assembler.clear()


func replicate_tick(tick: int) -> void:
	if bridge.lobby != null and bridge.lobby.match_active and tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PLAYER_SNAPSHOT_RATE) == 0:
		_send_player_snapshots()
	_send_projectile_batch()
	_send_mine_detonations()
	if bridge.lobby != null and bridge.lobby.match_active and tick % (GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PROJECTILE_CORRECTION_RATE) == 0:
		_send_projectile_correction()
	if tick % 3 == 0:
		_send_combat_feedback()


func _broadcast_lobby_state() -> void:
	if bridge.lobby == null:
		return
	var state := bridge.lobby.serialize()
	bridge.lobby_state.rpc(state)
	_outbound_bytes += JSON.stringify(state).length() * maxi(bridge.lobby.human_count(), 1)


func _broadcast_match_event(event_type: StringName, payload: Dictionary) -> void:
	var tick := bridge.world.server_tick if bridge.world != null else 0
	bridge.match_event.rpc(event_type, tick, payload)
	bridge._log("info", "match_event", {"event_type": String(event_type), "server_tick": tick})


func _send_player_snapshots() -> void:
	if bridge.lobby == null or bridge.lobby.players.is_empty():
		return
	var public_body := PlayerSnapshotCodec.encode_combatant_body(bridge.world.combatants, bridge.world.ordered_peer_ids_view(), 0)
	for peer_id in bridge.lobby.human_peer_ids_view():
		var combatant := bridge.world.combatants.get(peer_id) as CombatantState
		var body := PlayerSnapshotCodec.encode_combatant_body(bridge.world.combatants, bridge.world.ordered_peer_ids_view(), peer_id) if combatant != null and combatant.is_cloaked() else public_body
		var correction := combatant.prediction_state() if combatant != null else {}
		correction["active_ordnance"] = bridge.world.projectile_registry.count_for_owner(peer_id)
		correction["active_mines"] = bridge.world.projectile_registry.mine_count_for_owner(peer_id)
		correction["budget_evictions"] = bridge.world.projectile_registry.budget_evictions_for_owner(peer_id)
		var packet := PlayerSnapshotCodec.assemble(bridge.world.server_tick, bridge.world.acknowledged_input(peer_id), body, correction)
		bridge.world_snapshot.rpc_id(peer_id, packet)
		_outbound_bytes += packet.size()


func _send_combat_feedback() -> void:
	var feedback := bridge.world.drain_combat_feedback()
	if bridge.lobby == null:
		return
	for peer_id in bridge.lobby.human_peer_ids_view():
		if feedback.has(peer_id):
			var payload := feedback[peer_id] as Dictionary
			bridge.match_event.rpc_id(peer_id, &"COMBAT_FEEDBACK", bridge.world.server_tick, payload)
			_outbound_bytes += var_to_bytes(payload).size()


func _send_mine_detonations() -> void:
	var events := bridge.world.drain_mine_detonations()
	if bridge.lobby == null or bridge.lobby.human_count() == 0:
		return
	for start in range(0, events.size(), 8):
		var chunk := events.slice(start, start + 8)
		bridge.mine_detonations.rpc(bridge.world.server_tick, chunk)
		_outbound_bytes += var_to_bytes(chunk).size() * bridge.lobby.human_count()


func _send_projectile_batch() -> void:
	if not bridge.world.has_projectile_batch():
		return
	var batch := bridge.world.drain_projectile_batch()
	if bridge.lobby == null or bridge.lobby.human_count() == 0:
		return
	var sequence := _next_projectile_message_sequence()
	var packets := ProjectilePacketCodec.encode_batch_chunks(
		bridge.world.server_tick,
		sequence,
		batch.spawned as Array[ProjectileState],
		batch.removed as Array[int]
	)
	for packet in packets:
		bridge.projectile_batch.rpc(packet)
		_outbound_bytes += packet.size() * maxi(bridge.lobby.human_count(), 1)


func _send_projectile_correction() -> void:
	if bridge.lobby == null or bridge.lobby.players.is_empty():
		return
	var complete_snapshot := _projectile_correction_send_count % GameConstants.PROJECTILE_CORRECTION_RATE == 0
	_projectile_correction_send_count += 1
	if bridge.world.projectile_registry.size() == 0 and not complete_snapshot:
		return
	var active := _projectiles_for_correction(complete_snapshot)
	var sequence := _next_projectile_message_sequence()
	var packets := ProjectilePacketCodec.encode_correction_chunks(
		bridge.world.server_tick,
		sequence,
		active,
		complete_snapshot
	)
	for packet in packets:
		bridge.projectile_correction.rpc(packet)
		_outbound_bytes += packet.size() * bridge.lobby.human_count()


func _projectiles_for_correction(complete_snapshot: bool) -> Array[ProjectileState]:
	var active: Array[ProjectileState] = []
	if complete_snapshot:
		active = bridge.world.active_projectiles()
	else:
		var window := bridge.world.projectile_registry.projectile_window(
			_projectile_correction_cursor,
			PARTIAL_PROJECTILE_CORRECTION_COUNT
		)
		active = window.projectiles as Array[ProjectileState]
		_projectile_correction_cursor = int(window.next_slot)
		# Guided flight needs every correction even during heavy ordinary fire.
		var included_ids: Dictionary = {}
		for projectile in active:
			included_ids[projectile.projectile_id] = true
		for projectile in bridge.world.active_projectiles():
			if projectile.is_missile and not included_ids.has(projectile.projectile_id):
				active.append(projectile)
	return active


func _next_projectile_message_sequence() -> int:
	_projectile_message_sequence = (_projectile_message_sequence + 1) & 0xffff
	return _projectile_message_sequence


func _accept_projectile_correction_chunk(decoded: Dictionary) -> void:
	var assembled := _projectile_correction_assembler.accept(decoded)
	if not assembled.is_empty():
		bridge.client_projectile_correction_received.emit(assembled)
