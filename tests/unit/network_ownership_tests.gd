extends RefCounted


class RecordingReplication extends NetworkReplicationScheduler:
	var calls: Array[StringName] = []

	func _send_player_snapshots() -> void:
		calls.append(&"players")

	func _send_projectile_batch() -> void:
		calls.append(&"projectiles")

	func _send_mine_detonations() -> void:
		calls.append(&"mines")

	func _send_projectile_correction() -> void:
		calls.append(&"corrections")

	func _send_combat_feedback() -> void:
		calls.append(&"feedback")


static func run(context: TestContext) -> void:
	var first := NetworkBridge.new()
	var second := NetworkBridge.new()
	context.expect_true(first.session != second.session and first.replication != second.replication, "each bridge owns an independent session and packet scheduler")
	first.role = NetworkBridge.Role.CLIENT
	first.local_peer_id = 17
	first._client_password = "session-secret"
	first._configuration = {"lobby_password": "session-secret"}
	first.latest_lobby_state = {"revision": 91}
	first._pending_handshakes.begin(17, 10.0, "challenge")
	first._pending_disconnects[17] = 15.0
	first._peer_auth_sources[17] = "127.0.0.1"
	first._malformed_control_strikes[17] = 1
	first._blocked_sources["127.0.0.1"] = true
	first._ban_file_path = "user://unused-owner-test.json"
	first._authentication_attempt_limiter.register_failure("127.0.0.1", 10.0)
	first._projectile_message_sequence = 0xffff
	context.expect_equal(first._next_projectile_message_sequence(), 0, "owner preserves uint16 projectile sequence rollover")
	first._projectile_correction_cursor = 41
	first._projectile_correction_send_count = 9
	first._accept_projectile_correction_chunk({"complete_snapshot": true, "batch_sequence": 7, "chunk_count": 2, "chunk_index": 0, "spawned": []})
	context.expect_equal(first.session.local_peer_id, 17, "bridge compatibility identity writes update the session owner")
	context.expect_equal(first.replication._projectile_correction_cursor, 41, "bridge correction cursor updates its actual owner")
	context.expect_empty(second._pending_disconnects, "parallel bridge sessions cannot share disconnect timers")
	first.stop()
	context.expect_equal(first.role, NetworkBridge.Role.NONE, "teardown marks role inactive before releasing transport")
	context.expect_equal(first.local_peer_id, 0, "teardown releases client identity")
	context.expect_true(first._client_password.is_empty() and first._configuration.is_empty(), "teardown clears retained authentication secrets")
	context.expect_true(first._pending_handshakes.size() == 0 and first._pending_disconnects.is_empty(), "teardown clears admission and deferred disconnect state")
	context.expect_true(first._peer_auth_sources.is_empty() and first._malformed_control_strikes.is_empty(), "teardown clears per-peer admission isolation state")
	context.expect_true(first._blocked_sources.is_empty() and first._ban_file_path.is_empty(), "teardown clears in-memory source policy without writing its disk file")
	context.expect_true(first._projectile_message_sequence == 0 and first._projectile_correction_cursor == 0 and first._projectile_correction_send_count == 0, "teardown resets packet sequence and correction scheduling")
	context.expect_empty(first._projectile_correction_assembler._chunks, "teardown discards incomplete correction chunks before reconnect")
	context.expect_empty(first.latest_lobby_state, "teardown clears the prior server lobby revision")
	context.expect_empty(first._authentication_attempt_limiter._states, "teardown clears authentication throttling lifetime")
	first.stop()
	context.expect_equal(first.get_network_statistics().rtt_ms, -1, "repeated teardown retains unavailable transport statistics")
	first.free()
	second.free()
	_schedule(context)
	_ban_persistence(context)


static func _schedule(context: TestContext) -> void:
	var bridge := NetworkBridge.new()
	bridge.lobby = ServerLobby.new()
	bridge.lobby.match_active = true
	var scheduler := RecordingReplication.new(bridge)
	for tick in range(1, GameConstants.PHYSICS_TICKS_PER_SECOND + 1):
		scheduler.replicate_tick(tick)
	context.expect_equal(scheduler.calls.count(&"players"), GameConstants.PLAYER_SNAPSHOT_RATE, "player snapshots keep their configured server cadence")
	context.expect_equal(scheduler.calls.count(&"corrections"), GameConstants.PROJECTILE_CORRECTION_RATE, "projectile correction cadence is unchanged")
	context.expect_equal(scheduler.calls.count(&"feedback"), 20, "private combat feedback retains its 20 Hz cadence")
	context.expect_equal(scheduler.calls.count(&"projectiles"), 60, "projectile deltas are checked on every server callback")
	context.expect_equal(scheduler.calls.count(&"mines"), 60, "mine detonations are checked on every server callback")
	scheduler.calls.clear()
	scheduler.replicate_tick(60)
	context.expect_equal(scheduler.calls, [&"players", &"projectiles", &"mines", &"corrections", &"feedback"], "coincident sends preserve packet scheduling order")
	bridge.lobby.match_active = false
	scheduler.calls.clear()
	scheduler.replicate_tick(60)
	context.expect_equal(scheduler.calls, [&"projectiles", &"mines", &"feedback"], "inactive lobby suppresses snapshots while still draining transient feedback")
	bridge.free()


static func _ban_persistence(context: TestContext) -> void:
	var directory := ProjectSettings.globalize_path("res://reports/network-owner-tests")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("bans-%d.json" % Time.get_ticks_usec())
	var first := NetworkBridge.new()
	first._ban_file_path = path
	context.expect_true(first.operator_block_source(" [::1] ").ok, "session owner persists a normalized source ban atomically")
	first.stop()
	var reopened := NetworkBridge.new()
	reopened._ban_file_path = path
	reopened._load_blocked_sources()
	context.expect_true(reopened._blocked_sources.has("::1"), "new session reloads the persisted ban after prior teardown")
	context.expect_true(reopened.operator_unblock_source("::1").ok, "source unblocking persists through the same owner")
	reopened._blocked_sources["stale"] = true
	reopened._load_blocked_sources()
	context.expect_empty(reopened._blocked_sources, "reload replaces stale in-memory source policy with persisted empty list")
	context.expect_false(reopened.operator_block_source("not an address").ok, "extracted ban owner still rejects invalid addresses")
	first.free()
	reopened.free()
	DirAccess.remove_absolute(path)
