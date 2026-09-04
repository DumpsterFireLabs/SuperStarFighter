extends RefCounted


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
	first._accept_projectile_correction_chunk({"complete_snapshot": true, "batch_sequence": 7, "chunk_count": 2, "chunk_index": 0, "spawned": []})
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
	_session_observations(context)


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
