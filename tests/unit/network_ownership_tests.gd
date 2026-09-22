extends RefCounted

class CommandBridge extends NetworkBridge:
	var broadcasts := 0
	var rejected := 0
	func _broadcast_lobby_state() -> void:
		broadcasts += 1
	func _send_request_rejected(_peer: int, _message: String) -> void:
		rejected += 1


class RecordingBridge extends NetworkBridge:
	var log_writes: Array[String] = []

	func _write_log_output(text: String) -> void:
		log_writes.append(text)


class RecordingLogWriter extends "res://src/server/server_log_writer.gd":
	var writes: Array[String] = []

	func _write_output(text: String) -> void:
		writes.append(text)


class RecordingReplication extends NetworkReplicationScheduler:
	var calls: Array[StringName] = []

	func _send_player_snapshots(_lobby: ServerLobby, _world: AuthoritativeWorld) -> void:
		calls.append(&"players")

	func _send_projectile_batch(_lobby: ServerLobby, _world: AuthoritativeWorld) -> void:
		calls.append(&"projectiles")

	func _send_mine_detonations(_lobby: ServerLobby, _world: AuthoritativeWorld) -> void:
		calls.append(&"mines")

	func _send_projectile_correction(_lobby: ServerLobby, _world: AuthoritativeWorld) -> void:
		calls.append(&"corrections")

	func _send_combat_feedback(_lobby: ServerLobby, _world: AuthoritativeWorld) -> void:
		calls.append(&"feedback")


static func run(context: TestContext) -> void:
	var command_bridge := CommandBridge.new()
	command_bridge.lobby = ServerLobby.new()
	command_bridge.lobby.admit(2, "Host")
	command_bridge.lobby.admit(3, "Guest")
	command_bridge.commands.request_lobby_config(3, 5)
	context.expect_equal(command_bridge.rejected, 1, "command service retains leader authorization")
	command_bridge.commands.request_lobby_config(2, 5)
	context.expect_equal(command_bridge.lobby.config.rounds_to_win, 5, "command service applies accepted settings")
	context.expect_equal(command_bridge.broadcasts, 1, "accepted command publishes once")
	var service: RefCounted = command_bridge.commands
	command_bridge.free()
	context.expect_equal(service._owner.get_ref(), null, "command service cannot retain its bridge")
	_admission_queue(context)
	_server_health(context)
	_server_log_batching(context)
	_server_log_worker(context)
	var first := NetworkBridge.new()
	var second := NetworkBridge.new()
	context.expect_true(first.session != second.session and first.replication != second.replication, "each bridge owns an independent session and packet scheduler")
	first.session.role = NetworkBridge.Role.CLIENT
	first.session.local_peer_id = 17
	first.session._client_password = "session-secret"
	first.session._configuration = {"lobby_password": "session-secret"}
	first.session.latest_lobby_state = {"revision": 91}
	first.session._pending_handshakes.begin(17, 10.0, "challenge")
	first.session._pending_disconnects[17] = 15.0
	first.session._peer_auth_sources[17] = "127.0.0.1"
	first.session._malformed_control_strikes[17] = 1
	first.session._blocked_sources["127.0.0.1"] = true
	first.session._ban_file_path = "user://unused-owner-test.json"
	first.session._authentication_attempt_limiter.register_failure("127.0.0.1", 10.0)
	first.replication._projectile_message_sequence = 0xffff
	context.expect_equal(first.replication._next_projectile_message_sequence(), 0, "owner preserves uint16 projectile sequence rollover")
	first.replication._projectile_correction_cursor = 41
	first.replication._projectile_correction_send_count = 9
	first._accept_projectile_correction_chunk({"server_tick": 10, "complete_snapshot": true, "batch_sequence": 7, "chunk_count": 2, "chunk_index": 0, "spawned": []})
	context.expect_equal(first.local_peer_id, 17, "bridge identity observes session-owned state")
	context.expect_equal(first.replication._projectile_correction_cursor, 41, "correction cursor belongs only to the replication owner")
	context.expect_empty(second.session._pending_disconnects, "parallel bridge sessions cannot share disconnect timers")
	first.stop()
	context.expect_equal(first.role, NetworkBridge.Role.NONE, "teardown marks role inactive before releasing transport")
	context.expect_equal(first.local_peer_id, 0, "teardown releases client identity")
	context.expect_true(first.session._client_password.is_empty() and first.session._configuration.is_empty(), "teardown clears retained authentication secrets")
	context.expect_true(first.session._pending_handshakes.size() == 0 and first.session._pending_disconnects.is_empty(), "teardown clears admission and deferred disconnect state")
	context.expect_true(first.session._peer_auth_sources.is_empty() and first.session._malformed_control_strikes.is_empty(), "teardown clears per-peer admission isolation state")
	context.expect_true(first.session._blocked_sources.is_empty() and first.session._ban_file_path.is_empty(), "teardown clears in-memory source policy without writing its disk file")
	context.expect_true(first.replication._projectile_message_sequence == 0 and first.replication._projectile_correction_cursor == 0 and first.replication._projectile_correction_send_count == 0, "teardown resets packet sequence and correction scheduling")
	context.expect_empty(first.replication._projectile_correction_assembler._chunks, "teardown discards incomplete correction chunks before reconnect")
	context.expect_empty(first.latest_lobby_state, "teardown clears the prior server lobby revision")
	context.expect_empty(first.session._authentication_attempt_limiter._states, "teardown clears authentication throttling lifetime")
	first.stop()
	context.expect_equal(first.get_network_statistics().rtt_ms, -1, "repeated teardown retains unavailable transport statistics")
	first.free()
	second.free()
	_schedule(context)
	_missile_corrections(context)
	_ban_persistence(context)
	_replication_contract(context)
	_recovery_budget(context)
	_session_observations(context)


static func _server_log_worker(context: TestContext) -> void:
	var writer := RecordingLogWriter.new(12)
	writer.enqueue("first")
	writer.enqueue("second")
	writer.enqueue("over-capacity")
	context.expect_equal(writer.start(), OK, "dedicated log worker starts")
	writer.stop()
	context.expect_equal(writer.writes[0], "first\nsecond", "worker drains queued records in order before shutdown")
	context.expect_equal(writer.writes.size(), 2, "bounded worker reports output pressure explicitly")
	var overflow: Dictionary = JSON.parse_string(writer.writes[1])
	context.expect_equal(overflow.event, "server_log_overflow", "slow output produces a visible overflow marker")
	context.expect_equal(overflow.dropped_batches, 1, "worker accounts for batches beyond its memory bound")
	context.expect_equal(writer.status().dropped_batches, 1, "admin-visible log pressure survives draining the output queue")
	context.expect_equal(writer.status().queued_characters, 0, "shutdown drains the bounded producer queue")
	writer.stop()
	context.expect_false(writer._thread.is_started(), "repeated log shutdown leaves no running thread")


static func _server_log_batching(context: TestContext) -> void:
	var bridge := RecordingBridge.new()
	bridge._batch_tick_logs = true
	bridge._log("info", "first_event", {"count": 1})
	bridge._log("warning", "second_event", {"count": 2})
	context.expect_empty(bridge.log_writes, "tick events do not each flush the output sink")
	bridge._flush_tick_logs()
	context.expect_equal(bridge.log_writes.size(), 1, "a tick flush writes its complete event batch once")
	var lines := bridge.log_writes[0].split("\n")
	context.expect_equal(lines.size(), 2, "batching preserves JSON-line record boundaries")
	context.expect_equal(JSON.parse_string(lines[0]).event, "first_event", "batched logs preserve event order")
	context.expect_equal(JSON.parse_string(lines[1]).count, 2, "batched logs preserve structured fields")
	bridge._flush_tick_logs()
	context.expect_equal(bridge.log_writes.size(), 1, "an empty batch does not duplicate output")
	bridge._log("info", "outside_tick")
	context.expect_equal(bridge.log_writes.size(), 2, "startup and operator logs outside a tick remain immediate")
	bridge._batch_tick_logs = true
	bridge._log("info", "pending_shutdown")
	bridge.stop()
	context.expect_equal(bridge.log_writes.size(), 3, "teardown flushes any pending tick records")
	bridge.free()


static func _server_health(context: TestContext) -> void:
	var bridge := NetworkBridge.new()
	bridge.session.role = NetworkBridge.Role.SERVER
	bridge.lobby = ServerLobby.new()
	bridge.world = AuthoritativeWorld.new()
	bridge._server_started_usec = Time.get_ticks_usec()
	bridge._reset_metrics_window()
	context.expect_equal(bridge.operator_status().metrics_age_seconds, -1.0, "health has an explicit unavailable age before its first window")
	# Age the operational clock instead of sleeping. Frozen simulation time must
	# not prevent a report or retain timing samples indefinitely.
	bridge.world.simulation_paused = true
	bridge.world.server_tick = 42
	bridge._metrics_started_usec -= NetworkBridge.METRICS_INTERVAL_USEC
	bridge._physics_process(1.0 / 60.0)
	context.expect_equal(bridge.world.server_tick, 42, "health reporting does not advance a paused match")
	context.expect_equal(bridge._metrics_window, 1, "paused idle server rotates health on wall time")
	context.expect_empty(bridge._simulation_sample_usec, "paused health rotation releases timing samples")
	var status := bridge.operator_status()
	context.expect_equal(status.metrics.physics_samples, 1, "health counts callbacks independently of match ticks")
	context.expect_true(status.metrics.window_seconds >= 10.0 and status.metrics.physics_ticks_per_second < 1.0, "wall-time health exposes a stalled callback rate despite cheap simulation work")
	context.expect_true(status.metrics.simulation_paused, "operators can distinguish pause from simulation failure")
	status.metrics.clear()
	context.expect_false(bridge.operator_status().metrics.is_empty(), "admin status cannot mutate retained health metrics")
	bridge.world.simulation_paused = false
	bridge._physics_process(1.0 / 60.0)
	bridge.flush_metrics()
	context.expect_equal(bridge._metrics_window, 2, "shutdown flush includes an idle server's partial window")
	bridge.flush_metrics()
	context.expect_equal(bridge._metrics_window, 2, "repeated flush does not duplicate an empty health window")
	bridge.free()


static func _replication_contract(context: TestContext) -> void:
	# No bridge, scene tree or ENet peer is needed to verify packet generation.
	var scheduler := NetworkReplicationScheduler.new()
	var lobby := ServerLobby.new()
	lobby.admit(7, "PacketPilot")
	lobby.match_active = true
	var first_world := AuthoritativeWorld.new()
	first_world.add_peer(7).position = Vector2(300, 400)
	first_world.server_tick = 60
	var packets: Array[Dictionary] = []
	var cues: Array[Dictionary] = []
	scheduler.player_snapshot_ready.connect(func(peer_id: int, packet: PackedByteArray) -> void:
		packets.append({"peer_id": peer_id, "decoded": PlayerSnapshotCodec.decode(packet)})
	)
	scheduler.combat_feedback_ready.connect(func(peer_id: int, tick: int, payload: Dictionary) -> void:
		cues.append({"peer_id": peer_id, "tick": tick, "payload": payload})
	)
	first_world.combatants[7].shield.active = true
	first_world.combatants[7].shield.try_absorb_contact(first_world.combatants[7].stats)
	scheduler.replicate_tick(60, lobby, first_world)
	context.expect_equal(packets[0].peer_id, 7, "packet output identifies its recipient without invoking RPC")
	context.expect_true(packets[0].decoded.ok, "independent scheduler emits a valid player packet")
	context.expect_equal(packets[0].decoded.states[0].position, Vector2(300, 400), "packet output uses the supplied authoritative world")
	context.expect_equal(cues[0].payload.shield_cues[0].blocks, 1, "independent feedback output retains authoritative shield events")
	var second_world := AuthoritativeWorld.new()
	second_world.add_peer(7).position = Vector2(900, 800)
	second_world.server_tick = 120
	scheduler.replicate_tick(120, lobby, second_world)
	context.expect_equal(packets[1].decoded.states[0].position, Vector2(900, 800), "rematch replication cannot retain a stale world binding")
	context.expect_true(scheduler.outbound_bytes() > 0, "replication owner accounts generated outbound bytes")
	scheduler.reset_outbound_bytes()
	context.expect_equal(scheduler.outbound_bytes(), 0, "metrics reset does not require writable bridge aliases")


static func _session_observations(context: TestContext) -> void:
	var bridge := NetworkBridge.new()
	var payload := {"revision": 1, "players": [{"peer_id": 7, "display_name": "Pilot"}]}
	bridge.session.accept_welcome(7, payload)
	payload.players[0].display_name = "Changed"
	var observed := bridge.latest_lobby_state
	observed.players.clear()
	context.expect_equal(bridge.local_peer_id, 7, "welcome command updates read-only bridge identity")
	context.expect_equal(bridge.latest_lobby_state.players[0].display_name, "Pilot", "session observations cannot mutate accepted lobby state")
	context.expect_false(bridge.session.accept_lobby_state({"revision": 1, "players": []}), "owner rejects a duplicated lobby revision")
	context.expect_true(bridge.session.accept_lobby_state({"revision": 2, "players": []}), "owner accepts a newer lobby revision")
	bridge.stop()
	context.expect_empty(bridge.latest_lobby_state, "teardown clears owned observations")
	bridge.free()


static func _missile_corrections(context: TestContext) -> void:
	var bridge := NetworkBridge.new()
	bridge.world = AuthoritativeWorld.new()
	for id in range(1, 121):
		bridge.world.projectile_registry.add(ProjectileState.create(id, id, 1, Vector2(300, 300), 0.0, CombatStats.create_base()))
	var missile := ProjectileState.create_missile(121, 1, Vector2(300, 300), 0.0, 2)
	bridge.world.projectile_registry.add(missile)
	for unused in 4:
		var active := bridge.replication._projectiles_for_correction(bridge.world, false)
		context.expect_equal(active.count(missile), 1, "each partial correction includes guided ordnance exactly once beyond the rotating bullet window")
	context.expect_equal(bridge.replication._projectiles_for_correction(bridge.world, true).size(), 121, "full correction still includes all active projectiles")
	bridge.free()


static func _schedule(context: TestContext) -> void:
	var bridge := NetworkBridge.new()
	bridge.lobby = ServerLobby.new()
	bridge.lobby.match_active = true
	var scheduler := RecordingReplication.new()
	for tick in range(1, GameConstants.PHYSICS_TICKS_PER_SECOND + 1):
		scheduler.replicate_tick(tick, bridge.lobby, bridge.world)
	context.expect_equal(scheduler.calls.count(&"players"), GameConstants.PLAYER_SNAPSHOT_RATE, "player snapshots keep their configured server cadence")
	context.expect_equal(scheduler.calls.count(&"corrections"), GameConstants.PROJECTILE_CORRECTION_RATE, "projectile correction cadence is unchanged")
	context.expect_equal(scheduler.calls.count(&"feedback"), 20, "private combat feedback retains its 20 Hz cadence")
	context.expect_equal(scheduler.calls.count(&"projectiles"), 60, "projectile deltas are checked on every server callback")
	context.expect_equal(scheduler.calls.count(&"mines"), 60, "mine detonations are checked on every server callback")
	scheduler.calls.clear()
	scheduler.replicate_tick(60, bridge.lobby, bridge.world)
	context.expect_equal(scheduler.calls, [&"players", &"projectiles", &"mines", &"corrections", &"feedback"], "coincident sends preserve packet scheduling order")
	bridge.lobby.match_active = false
	scheduler.calls.clear()
	scheduler.replicate_tick(60, bridge.lobby, bridge.world)
	context.expect_equal(scheduler.calls, [&"projectiles", &"mines", &"feedback"], "inactive lobby suppresses snapshots while still draining transient feedback")
	bridge.free()


static func _ban_persistence(context: TestContext) -> void:
	var directory := ProjectSettings.globalize_path("res://reports/network-owner-tests")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("bans-%d.json" % Time.get_ticks_usec())
	var first := NetworkBridge.new()
	first.session._ban_file_path = path
	context.expect_true(first.operator_block_source(" [::1] ").ok, "session owner persists a normalized source ban atomically")
	first.stop()
	var reopened := NetworkBridge.new()
	reopened.session._ban_file_path = path
	reopened.session._load_blocked_sources()
	context.expect_true(reopened.session._blocked_sources.has("::1"), "new session reloads the persisted ban after prior teardown")
	context.expect_true(reopened.operator_unblock_source("::1").ok, "source unblocking persists through the same owner")
	reopened.session._blocked_sources["stale"] = true
	reopened.session._load_blocked_sources()
	context.expect_empty(reopened.session._blocked_sources, "reload replaces stale in-memory source policy with persisted empty list")
	context.expect_false(reopened.operator_block_source("not an address").ok, "extracted ban owner still rejects invalid addresses")
	first.free()
	reopened.free()
	DirAccess.remove_absolute(path)


static func _admission_queue(context: TestContext) -> void:
	var runtime := Node.new()
	var owner := NetworkSessionOwner.new(runtime, func() -> Dictionary: return {})
	var challenged: Array[int] = []
	var rejected: Array[Dictionary] = []
	owner.challenge_requested.connect(func(id: int, challenge: String) -> void:
		context.expect_true(NetworkProtocol.is_valid_auth_challenge(challenge), "queued admission generates a fresh valid challenge")
		challenged.append(id)
	)
	owner.rejection_requested.connect(func(id: int, reason: StringName, _message: String) -> void: rejected.append({"id": id, "reason": reason}))
	var now := Time.get_ticks_msec() / 1000.0
	for id in range(1, 8):
		owner._peer_auth_sources[id] = "198.51.100.1" if id < 7 else "198.51.100.2"
		owner._pending_handshakes.begin(id, now)
	owner._start_queued_handshakes()
	context.expect_equal(challenged, [1, 2, 7], "shared-address cohort queues without blocking another source")
	context.expect_equal(owner._pending_auth_count_for_source("198.51.100.1", 0), 2, "queue preserves the two-proof per-source budget")
	context.expect_empty(rejected, "legitimate concurrency alone is not a failed-password rejection")
	owner.complete_handshake(1)
	owner.process_pending_connections()
	context.expect_equal(challenged, [1, 2, 7, 3], "completing authentication promotes the oldest waiting peer")
	context.expect_equal(owner._pending_handshakes.expired(now + NetworkProtocol.HANDSHAKE_TIMEOUT_SECONDS), [2, 3, 4, 5, 6, 7], "promotion does not extend the original connection deadline")
	context.expect_false(owner.validate_hello(4, GameConstants.PROTOCOL_VERSION, "Premature", "0".repeat(64), 0, 32), "queued peers cannot authenticate before receiving a challenge")
	context.expect_equal(rejected.back().reason, NetworkProtocol.REJECT_MALFORMED_TRAFFIC, "premature proof is isolated without granting authority")
	owner._pending_handshakes.begin(8, now - NetworkProtocol.HANDSHAKE_TIMEOUT_SECONDS - 1)
	owner._peer_auth_sources[8] = "198.51.100.3"
	owner.process_pending_connections()
	context.expect_false(challenged.has(8), "expired queued peer never receives a challenge")
	context.expect_equal(rejected.back().reason, NetworkProtocol.REJECT_HANDSHAKE_TIMEOUT, "queue wait remains bounded by the handshake timeout")
	owner._blocked_sources["198.51.100.1"] = true
	owner.process_pending_connections()
	context.expect_false(owner._pending_handshakes.has(5) or owner._pending_handshakes.has(6), "source bans also reject waiting handshakes")
	owner.stop()
	context.expect_equal(owner._pending_handshakes.size(), 0, "session stop clears queued and active handshakes")
	runtime.free()


static func _recovery_budget(context: TestContext) -> void:
	var scheduler := NetworkReplicationScheduler.new()
	var lobby := ServerLobby.new()
	for peer in range(1, 33): lobby.admit(peer, "P%d" % peer)
	lobby.match_active = true
	var world := AuthoritativeWorld.new()
	var stats := CombatStats.create_base()
	for index in 1024:
		world.projectile_registry.add(ProjectileState.create(index + 1, index / 32 + 1, index, Vector2(700, 700), 0, stats))
	var received: Array[PackedByteArray] = []
	scheduler.projectile_recovery_ready.connect(func(packet: PackedByteArray) -> void: received.append(packet))
	scheduler._send_projectile_correction(lobby, world)
	context.expect_equal(received.size(), 0, "full recovery is queued without a synchronous fan-out burst")
	var total := 0
	for tick in 8:
		var previous := received.size()
		scheduler._flush_recovery(lobby)
		context.expect_true(received.size() - previous <= 4, "each tick obeys the recovery chunk budget")
	for packet in received: total += packet.size()
	context.expect_equal(scheduler.payload_metrics().recovery_pending_chunks, 0, "maximum population drains before next correction")
	context.expect_equal(scheduler.outbound_bytes(), total * 32, "accounting includes every recovery recipient")
	context.expect_true(received.size() > 20, "dense fixture exercises chunking")
	scheduler._projectile_correction_send_count = 0
	scheduler._send_projectile_correction(lobby, world)
	scheduler.clear()
	context.expect_equal(scheduler.payload_metrics().recovery_pending_chunks, 0, "rematch discards old recovery queue")
