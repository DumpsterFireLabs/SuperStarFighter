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


class AdminBridge extends NetworkBridge:
	var emitted: Array[StringName] = []

	func _broadcast_match_event(event_type: StringName, _payload: Dictionary) -> void:
		emitted.append(event_type)

	func _drain_match_coordinator() -> void:
		pass


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
	_transport_liveness(context)
	_proxy_mode(context)
	_transport_congestion(context)
	_server_health(context)
	_admin_restart(context)
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
	_admission_broadcast_lifetime(context)
	_session_observations(context)


static func _admin_restart(context: TestContext) -> void:
	var bridge := AdminBridge.new()
	bridge.session.role = NetworkBridge.Role.SERVER
	bridge.lobby = ServerLobby.new()
	bridge.world = AuthoritativeWorld.new()
	context.expect_false(bridge.operator_restart_match().ok, "admin restart rejects an idle server")
	bridge.lobby.admit(2, "First")
	bridge.lobby.admit(3, "Second")
	bridge.lobby.request_ready(2, true)
	bridge.lobby.request_ready(3, true)
	context.expect_true(bridge.lobby.request_start(2).ok, "admin restart fixture starts an active match")
	for peer_id in [2, 3]:
		bridge.world.add_peer(peer_id)
	bridge.match_coordinator = AuthoritativeMatchCoordinator.new(bridge.lobby, bridge.world, 12345)
	context.expect_true(bridge.match_coordinator.start(0), "admin restart fixture starts its coordinator")
	var prior := bridge.match_coordinator
	prior.machine.round_number = 3
	bridge.world.simulation_paused = true
	var result := bridge.operator_restart_match()
	context.expect_true(result.ok, "authenticated operator can restart an active match")
	context.expect_true(bridge.match_coordinator != prior, "restart replaces the old coordinator")
	context.expect_equal(bridge.match_coordinator.machine.round_number, 1, "restart begins at round one")
	context.expect_false(bridge.world.simulation_paused, "restart clears a server pause")
	context.expect_true(bridge.emitted.has(&"MATCH_START_ACCEPTED"), "restart announces its new match to clients")
	bridge.free()


static func _admission_broadcast_lifetime(context: TestContext) -> void:
	var bridge := CommandBridge.new()
	bridge.session.role = NetworkBridge.Role.SERVER
	bridge._admission_lobby_broadcast_pending = true
	bridge._flush_admission_lobby_state()
	bridge._flush_admission_lobby_state()
	context.expect_equal(bridge.broadcasts, 1, "one scheduled admission broadcast consumes all pending roster changes")
	bridge._admission_lobby_broadcast_pending = true
	bridge.stop()
	bridge._flush_admission_lobby_state()
	context.expect_equal(bridge.broadcasts, 1, "deferred admission callback cannot publish after shutdown")
	bridge.free()


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
	# No bridge, scene tree or transport peer is needed to verify packet generation.
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


static func _transport_liveness(context: TestContext) -> void:
	context.expect_equal(NetworkSessionOwner.transport_url(" 192.0.2.4 ", 7000), "ws://192.0.2.4:7000", "IPv4 hosts form a trimmed WebSocket URL")
	context.expect_equal(NetworkSessionOwner.transport_url("::1", 7123), "ws://[::1]:7123", "IPv6 literals are bracketed in the WebSocket URL")
	context.expect_equal(NetworkSessionOwner.transport_url("[::1]", 7123), "ws://[::1]:7123", "bracketed IPv6 literals are not double-bracketed")
	var runtime := Node.new()
	var owner := NetworkSessionOwner.new(runtime, func() -> Dictionary: return {})
	owner.role = NetworkBridge.Role.CLIENT
	context.expect_equal(owner.get_network_statistics().rtt_ms, -1, "round-trip time is unavailable before transport exists")
	owner._transport_peer = WebSocketMultiplayerPeer.new()
	context.expect_equal(owner.get_network_statistics().rtt_ms, -1, "round-trip time is unavailable before the first pong")
	owner.record_round_trip(40.0)
	context.expect_equal(owner.get_network_statistics(), {"rtt_ms": 40, "rtt_variance_ms": 20}, "first ping seeds smoothed round-trip time and variance")
	owner.record_round_trip(80.0)
	owner.record_round_trip(-1.0)
	owner.record_round_trip(INF)
	context.expect_equal(owner.get_network_statistics(), {"rtt_ms": 45, "rtt_variance_ms": 25}, "later pings smooth round-trip time; invalid samples are ignored")
	owner._transport_peer = null
	var now := Time.get_ticks_msec() / 1000.0
	owner.local_peer_id = 9
	owner._last_server_heard = now - NetworkProtocol.TRANSPORT_IDLE_TIMEOUT_SECONDS - 1.0
	var lost: Array[String] = []
	owner.connection_lost.connect(func(message: String) -> void: lost.append(message))
	owner.check_server_liveness()
	owner.check_server_liveness()
	owner._on_client_server_disconnected()
	context.expect_equal(lost, ["The connection to the server timed out."], "a silent server is reported lost exactly once")
	context.expect_equal(owner.local_peer_id, 0, "a timed-out client forgets its admitted identity")
	owner.role = NetworkBridge.Role.SERVER
	var events: Array[String] = []
	owner.log_requested.connect(func(_level: String, event_name: String, _fields: Dictionary) -> void: events.append(event_name))
	owner.note_peer_alive(5)
	context.expect_false(owner._last_heard.has(5), "unadmitted peers do not gain a liveness deadline")
	owner.complete_handshake(5)
	owner.complete_handshake(6)
	owner._last_heard[5] = now - NetworkProtocol.TRANSPORT_IDLE_TIMEOUT_SECONDS - 1.0
	owner.process_pending_connections()
	context.expect_equal(events, ["peer_timed_out"], "a silent admitted peer times out")
	context.expect_equal(owner._last_heard.keys(), [6], "only the silent peer loses its liveness deadline")
	var rejections: Array[int] = []
	owner.rejection_requested.connect(func(peer_id: int, _reason: StringName, _message: String) -> void: rejections.append(peer_id))
	context.expect_true(owner.accept_transport_message(6), "admitted peers' pings and probe acks are accepted")
	for _request in NetworkProtocol.MAX_CONTROL_REQUESTS_PER_SECOND + 5:
		owner.accept_control_request(6, "ready_state", true)
	context.expect_true(owner.accept_transport_message(6), "a lobby-control burst cannot starve liveness traffic")
	owner.forget_admission(6)
	context.expect_true(owner._last_heard.is_empty(), "forgotten admissions drop their liveness deadline")
	context.expect_false(owner.accept_transport_message(6), "an ejected peer's in-flight ping is ignored")
	context.expect_false(owner.accept_transport_message(99), "pre-admission liveness traffic is ignored")
	context.expect_equal(rejections, [], "late liveness traffic never replaces the original rejection reason")
	runtime.free()


static func _transport_congestion(context: TestContext) -> void:
	var runtime := Node.new()
	var owner := NetworkSessionOwner.new(runtime, func() -> Dictionary: return {})
	owner.role = NetworkBridge.Role.SERVER
	var probes: Array[int] = []
	owner.probe_requested.connect(func(peer_id: int, _server_usec: int) -> void: probes.append(peer_id))
	owner.complete_handshake(7)
	owner._process_probes(1_000_000)
	owner._process_probes(1_100_000)
	context.expect_equal(probes, [7], "admitted peers are probed at most once per probe interval")
	owner._process_probes(1_000_000 + int(NetworkProtocol.TRANSPORT_PROBE_INTERVAL_SECONDS * 1_000_000.0))
	context.expect_equal(probes, [7, 7], "probing repeats after the interval")
	owner.record_probe_ack(7, 1_000_000, 1_020_000)
	context.expect_false(owner.congested_peers().has(7), "a probe at baseline round trip is not congestion")
	owner.record_probe_ack(7, 424_242, 2_000_000)
	context.expect_false(owner.congested_peers().has(7), "unknown or duplicate probe acknowledgements are ignored")
	var second := 1_000_000 + int(NetworkProtocol.TRANSPORT_PROBE_INTERVAL_SECONDS * 1_000_000.0)
	owner.record_probe_ack(7, second, second + 20_000 + int(NetworkProtocol.TRANSPORT_CONGESTION_ENTER_MS * 1000.0) + 10_000)
	context.expect_true(owner.congested_peers().has(7), "round trip well above the baseline marks the stream congested")
	owner._probes[7].outstanding[3_000_000] = true
	owner.record_probe_ack(7, 3_000_000, 3_000_000 + 20_000 + int((NetworkProtocol.TRANSPORT_CONGESTION_ENTER_MS + NetworkProtocol.TRANSPORT_CONGESTION_EXIT_MS) * 500.0))
	context.expect_true(owner.congested_peers().has(7), "hysteresis keeps a congested stream thinned between the thresholds")
	owner._probes[7].outstanding[4_000_000] = true
	owner.record_probe_ack(7, 4_000_000, 4_021_000)
	context.expect_false(owner.congested_peers().has(7), "a drained stream leaves congestion")
	owner._probes[7].outstanding[5_000_000] = true
	owner._probes[7].next_probe = 9_000_000
	owner._process_probes(5_000_000 + int(NetworkProtocol.TRANSPORT_CONGESTION_ENTER_MS * 1000.0) + 60_000)
	context.expect_true(owner.congested_peers().has(7), "an unanswered probe counts as queueing before its ack arrives")
	owner._probes[7].outstanding.clear()
	owner._probes[7].next_probe = 0
	owner._probes[7].outstanding[6_000_000] = true
	owner.record_probe_ack(7, 6_000_000, 6_021_000)
	context.expect_false(owner.congested_peers().has(7), "a healthy ack clears queueing before the dropped-ack case")
	var expiry_usec := int(NetworkProtocol.TRANSPORT_PROBE_EXPIRY_SECONDS * 1_000_000.0)
	var dropped_probe := 6_030_000
	owner._process_probes(dropped_probe)
	context.expect_true((owner._probes[7].outstanding as Dictionary).has(dropped_probe), "a new probe is outstanding")
	owner._probes[7].next_probe = dropped_probe + expiry_usec * 10
	owner._process_probes(dropped_probe + int(NetworkProtocol.TRANSPORT_CONGESTION_ENTER_MS * 1000.0) + 60_000)
	context.expect_true(owner.congested_peers().has(7), "a probe whose ack was dropped first reads as queueing")
	owner._process_probes(dropped_probe + expiry_usec + 1)
	context.expect_true((owner._probes[7].outstanding as Dictionary).is_empty(), "a probe whose ack never arrives expires")
	var fresh_probe := dropped_probe + expiry_usec + 2
	owner._probes[7].outstanding[fresh_probe] = true
	owner.record_probe_ack(7, fresh_probe, fresh_probe + 21_000)
	context.expect_false(owner.congested_peers().has(7), "a dropped ack cannot hold a healthy peer in congestion")
	owner.forget_admission(7)
	context.expect_true(owner.congested_peers().is_empty() and owner._probes.is_empty(), "departed peers leave the congestion set")
	runtime.free()
	var scheduler := NetworkReplicationScheduler.new()
	var lobby := ServerLobby.new()
	lobby.admit(7, "Slow")
	lobby.admit(8, "Fast")
	lobby.match_active = true
	var world := AuthoritativeWorld.new()
	world.add_peer(7)
	world.add_peer(8)
	var received := {7: 0, 8: 0}
	scheduler.player_snapshot_ready.connect(func(peer_id: int, _packet: PackedByteArray) -> void: received[peer_id] += 1)
	scheduler.set_transport_congested_peers({7: true})
	var snapshot_interval := GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PLAYER_SNAPSHOT_RATE
	for round_index in 8:
		world.server_tick = (round_index + 1) * snapshot_interval
		scheduler.replicate_tick(world.server_tick, lobby, world)
	context.expect_equal(received, {7: 2, 8: 8}, "a congested stream receives one snapshot in four while others are unaffected")
	context.expect_equal(scheduler.payload_metrics().transport_congested_peers, 1, "metrics report transport-congested peers")


static func _proxy_mode(context: TestContext) -> void:
	for address in ["192.0.2.4", "game.example.com", "::1", "wss://game.example.com", "WSS://game.example.com:8443/play", "ws://127.0.0.1:7000"]:
		context.expect_true(NetworkProtocol.is_valid_server_address(address), "%s is a valid server address" % address)
	for address in ["", "has space", "wss://", "wss://:443", "wss://user@game.example.com", "http://game.example.com", "game.example.com/path", "x".repeat(254), "game.example.com:7000", "203.0.113.5:7000", "[game.example.com]", "[2001:db8::1", "2001:db8::1]", "[::1]]", "[[::1]]", "[192.0.2.4]"]:
		context.expect_false(NetworkProtocol.is_valid_server_address(address), "%s is rejected as a server address" % address)
	context.expect_equal(NetworkSessionOwner.transport_url(" wss://game.example.com ", 7000), "wss://game.example.com", "wss:// URLs keep their own port instead of the port field")
	context.expect_true(NetworkProtocol.is_valid_server_address("[2001:db8::1]"), "bracketed IPv6 literals are valid server addresses")
	context.expect_equal(NetworkSessionOwner.transport_url("game.example.com", 7000), "ws://game.example.com:7000", "hostnames are not bracketed")
	context.expect_equal(NetworkSessionOwner.transport_url("2001:db8::1", 7000), "ws://[2001:db8::1]:7000", "unbracketed IPv6 literals are bracketed")
	for address in ["game.example.com:7000", "[2001:db8::1", "2001:db8::1]"]:
		context.expect_equal(NetworkSessionOwner.transport_url(address, 7000), "", "%s does not form a WebSocket URL" % address)
	var runtime := Node.new()
	var owner := NetworkSessionOwner.new(runtime, func() -> Dictionary: return {})
	owner._behind_proxy = true
	context.expect_equal(owner._peer_auth_source(41), "proxied:41", "proxied players are tracked per connection, not by the shared proxy address")
	context.expect_false(owner.operator_block_source("127.0.0.1").ok, "address bans are refused behind a proxy")
	# A proxy-address ban from an older ban file must not block every player.
	owner._blocked_sources["127.0.0.1"] = true
	var challenged: Array[int] = []
	owner.challenge_requested.connect(func(id: int, _challenge: String) -> void: challenged.append(id))
	var now := Time.get_ticks_msec() / 1000.0
	for failure in NetworkProtocol.AUTH_FAILURE_LIMIT:
		owner._proxy_failure_limiter.register_failure("proxy", now)
	for id in [51, 52, 53]:
		owner._peer_auth_sources[id] = owner._peer_auth_source(id)
		owner._pending_handshakes.begin(id, now)
	owner._start_queued_handshakes()
	owner._start_queued_handshakes()
	context.expect_equal(challenged, [51], "repeated wrong passwords throttle proxied challenges to one per interval")
	owner._next_proxy_challenge = now - 0.01
	owner._start_queued_handshakes()
	context.expect_equal(challenged, [51, 52], "throttled proxied players are still admitted in arrival order")
	owner._proxy_failure_limiter.clear()
	owner._start_queued_handshakes()
	context.expect_equal(challenged, [51, 52, 53], "challenges resume at full speed once the failure window clears")
	runtime.free()


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
	var stalled: Array[PackedByteArray] = []
	var listener := func(peer: int, packet: PackedByteArray) -> void:
		received.append(packet)
		if peer == 1:
			stalled.append(packet)
		else:
			var decoded := ProjectilePacketCodec.decode_correction(packet)
			scheduler.acknowledge_recovery(peer, int(decoded.server_tick), int(decoded.batch_sequence), int(decoded.chunk_index))
	scheduler.projectile_recovery_ready.connect(listener)
	scheduler._send_projectile_correction(lobby, world)
	context.expect_equal(received.size(), 0, "full recovery is queued without a synchronous fan-out burst")
	for tick in 180:
		var previous := received.size()
		scheduler._flush_recovery(lobby)
		context.expect_true(received.size() - previous <= 32, "each peer sends at most one recovery chunk in a tick")
	context.expect_equal(stalled.size(), 2, "non-acknowledging peer cannot fill the transport with recovery traffic")
	context.expect_equal(scheduler.payload_metrics().recovery_active_peers, 1, "healthy peers finish independently of stalled peer")
	var first := ProjectilePacketCodec.decode_correction(stalled[0])
	scheduler.acknowledge_recovery(1, int(first.server_tick), int(first.batch_sequence), 26)
	scheduler.acknowledge_recovery(1, int(first.server_tick) + 1, int(first.batch_sequence), 0)
	scheduler.acknowledge_recovery(1, int(first.server_tick), int(first.batch_sequence) + 1, 0)
	scheduler._flush_recovery(lobby)
	context.expect_equal(stalled.size(), 2, "unsent and stale acknowledgements do not release capacity")
	scheduler.acknowledge_recovery(1, int(first.server_tick), int(first.batch_sequence), 0)
	scheduler.acknowledge_recovery(1, int(first.server_tick), int(first.batch_sequence), 0)
	for tick in 18: scheduler._flush_recovery(lobby)
	context.expect_equal(stalled.size(), 3, "one acknowledged chunk releases exactly one slot")
	for tick in 12: scheduler._flush_recovery(lobby)
	context.expect_equal(stalled.size(), 3, "duplicate acknowledgement cannot inflate window")
	var total := 0
	for packet in received: total += packet.size()
	context.expect_equal(scheduler.outbound_bytes(), total, "accounting includes actual per-peer recovery sends")
	var snapshot_counts: Dictionary = {}
	scheduler.player_snapshot_ready.connect(func(peer: int, _packet: PackedByteArray) -> void: snapshot_counts[peer] = int(snapshot_counts.get(peer, 0)) + 1)
	for index in 4: scheduler._send_player_snapshots(lobby, world)
	context.expect_equal(snapshot_counts[1], 2, "stalled peer temporarily receives ten player snapshots per second")
	context.expect_equal(snapshot_counts[2], 4, "healthy peer retains full snapshot rate")
	lobby.remove(1)
	scheduler._flush_recovery(lobby)
	context.expect_equal(scheduler.payload_metrics().recovery_active_peers, 0, "disconnect releases queued recovery and inflight records")
	scheduler.clear()
	context.expect_equal(scheduler.payload_metrics().recovery_pending_chunks, 0, "rematch discards old recovery queue")
	context.expect_equal(scheduler.payload_metrics().recovery_active_peers, 0, "rematch releases every peer window")

	scheduler.projectile_recovery_ready.disconnect(listener)
