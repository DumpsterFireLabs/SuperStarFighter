class_name NetworkProtocolTests
extends RefCounted


static func run(context: TestContext) -> void:
	_validate_sequence_wrap(context)
	_validate_input_codec(context)
	_validate_snapshot_codec(context)
	_validate_projectile_codec(context)
	_validate_rate_limiting(context)
	_validate_lobby_authority(context)
	_validate_prediction_and_interpolation(context)
	_validate_authoritative_world(context)
	_validate_connection_admission(context)


static func _validate_sequence_wrap(context: TestContext) -> void:
	context.expect_true(SequenceMath.is_newer(11, 10), "later sequence is newer")
	context.expect_false(SequenceMath.is_newer(10, 10), "duplicate sequence is not newer")
	context.expect_false(SequenceMath.is_newer(9, 10), "older sequence is not newer")
	context.expect_true(SequenceMath.is_newer(0, 0xffffffff), "sequence comparison handles uint32 wrap")
	context.expect_false(SequenceMath.is_newer(0xffffffff, 0), "pre-wrap sequence is older after wrap")
	context.expect_equal(SequenceMath.increment(0xffffffff), 0, "uint32 sequence increment wraps to zero")


static func _validate_input_codec(context: TestContext) -> void:
	var original := PlayerInputFrame.new(0xfffffffe, 800, Vector2(0.5, -0.75), 5.5, true, true)
	var packet := InputPacketCodec.encode(original)
	context.expect_equal(packet.size(), InputPacketCodec.PACKET_SIZE, "input codec uses a fixed packet size")
	var decoded := InputPacketCodec.decode(packet)
	context.expect_true(decoded.ok, "valid input packet decodes")
	if decoded.ok:
		var frame := decoded.frame as PlayerInputFrame
		context.expect_equal(frame.sequence, original.sequence, "input sequence round-trips")
		context.expect_equal(frame.client_tick, original.client_tick, "input client tick round-trips")
		context.expect_approx(frame.movement.x, original.movement.x, "input X quantization round-trips", 0.0001)
		context.expect_approx(frame.movement.y, original.movement.y, "input Y quantization round-trips", 0.0001)
		context.expect_approx(angle_difference(frame.aim_angle, original.aim_angle), 0.0, "input aim quantization round-trips", 0.0001)
		context.expect_true(frame.firing and frame.shielding, "input action bits round-trip")
	context.expect_false(InputPacketCodec.decode(packet.slice(0, 12)).ok, "truncated input packet is rejected")
	var bad_version := packet.duplicate()
	bad_version[0] = 99
	context.expect_false(InputPacketCodec.decode(bad_version).ok, "input packet version mismatch is rejected")
	var bad_actions := packet.duplicate()
	bad_actions[15] = 4
	context.expect_false(InputPacketCodec.decode(bad_actions).ok, "impossible input action bits are rejected")
	var excessive_movement := packet.duplicate()
	excessive_movement[9] = 0xff
	excessive_movement[10] = 0x7f
	excessive_movement[11] = 0xff
	excessive_movement[12] = 0x7f
	context.expect_false(InputPacketCodec.decode(excessive_movement).ok, "over-magnitude input is rejected before clamping")


static func _validate_snapshot_codec(context: TestContext) -> void:
	var states: Array[Dictionary] = []
	for peer_id in range(2, 34):
		states.append({
			"peer_id": peer_id,
			"position": Vector2(peer_id * 10.25, peer_id * 5.5),
			"velocity": Vector2(120.5, -80.25),
			"aim_angle": 1.25,
			"health": 87.5,
			"shield": 62.25,
			"ammunition": 7,
			"alive": true,
			"shielding": peer_id % 2 == 0,
		})
	var packet := PlayerSnapshotCodec.encode(900, 44, states)
	var decoded := PlayerSnapshotCodec.decode(packet)
	context.expect_true(decoded.ok, "maximum-size player snapshot decodes")
	if decoded.ok:
		context.expect_equal((decoded.states as Array).size(), 32, "snapshot preserves its bounded player count")
		context.expect_equal(decoded.server_tick, 900, "snapshot server tick round-trips")
		context.expect_equal(decoded.acknowledged_input, 44, "snapshot acknowledgement round-trips")
		var first: Dictionary = decoded.states[0]
		context.expect_equal(first.peer_id, 2, "snapshot player identity round-trips")
		context.expect_approx((first.position as Vector2).x, 20.5, "snapshot position quantization round-trips")
		context.expect_approx((first.velocity as Vector2).y, -80.25, "snapshot velocity quantization round-trips")
	context.expect_false(PlayerSnapshotCodec.decode(packet.slice(0, packet.size() - 1)).ok, "truncated player snapshot is rejected")
	var oversized := PackedByteArray()
	oversized.resize(PlayerSnapshotCodec.HEADER_SIZE)
	oversized[0] = NetworkProtocol.PACKET_VERSION
	oversized[9] = 33
	context.expect_false(PlayerSnapshotCodec.decode(oversized).ok, "oversized player count is rejected")


static func _validate_projectile_codec(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	stats.pierce_count = 2
	stats.ricochet_count = 1
	var projectile := ProjectileState.create(77, 4, 12, Vector2(321.25, 654.5), 0.75, stats)
	projectile.lifetime_remaining = 1.875
	var spawned: Array[ProjectileState] = [projectile]
	var packet := ProjectilePacketCodec.encode_batch(1000, spawned, [10, 11])
	var decoded := ProjectilePacketCodec.decode_batch(packet)
	context.expect_true(decoded.ok, "projectile batch decodes")
	if decoded.ok:
		context.expect_equal(decoded.server_tick, 1000, "projectile batch tick round-trips")
		context.expect_equal(decoded.removed, [10, 11], "projectile removals round-trip")
		var decoded_projectile := decoded.spawned[0] as ProjectileState
		context.expect_equal(decoded_projectile.projectile_id, 77, "projectile identity round-trips")
		context.expect_equal(decoded_projectile.owner_id, 4, "projectile owner round-trips")
		context.expect_equal(decoded_projectile.shot_sequence, 12, "projectile shot sequence round-trips")
		context.expect_approx(decoded_projectile.position.x, 321.25, "projectile position round-trips")
		context.expect_approx(decoded_projectile.damage, 25.0, "projectile damage round-trips")
		context.expect_equal(decoded_projectile.remaining_pierces, 2, "projectile pierce count round-trips")
		context.expect_equal(decoded_projectile.remaining_ricochets, 1, "projectile ricochet count round-trips")
	context.expect_false(ProjectilePacketCodec.decode_batch(packet.slice(0, 8)).ok, "truncated projectile batch is rejected")
	var correction := ProjectilePacketCodec.encode_correction(1001, spawned)
	context.expect_true(ProjectilePacketCodec.decode_correction(correction).ok, "projectile correction round-trips")
	context.expect_false(ProjectilePacketCodec.decode_correction(packet).ok, "projectile correction rejects removal records")


static func _validate_rate_limiting(context: TestContext) -> void:
	var limiter := InputRateLimiter.new()
	for index in NetworkProtocol.MAX_INPUTS_PER_SECOND:
		context.expect_equal(limiter.register(2, 0.0), InputRateLimiter.Decision.ACCEPT, "input within first rate window is accepted")
	context.expect_equal(limiter.register(2, 0.0), InputRateLimiter.Decision.DROP, "excess input is dropped")
	for window in [1.0, 2.0]:
		for index in NetworkProtocol.MAX_INPUTS_PER_SECOND:
			limiter.register(2, window)
		var decision := limiter.register(2, window)
		if window == 1.0:
			context.expect_equal(decision, InputRateLimiter.Decision.DROP, "second excessive window is dropped")
		else:
			context.expect_equal(decision, InputRateLimiter.Decision.DISCONNECT, "sustained excessive input disconnects")
	var malformed := InputRateLimiter.new()
	context.expect_equal(malformed.register(3, 0.0, false), InputRateLimiter.Decision.DROP, "first malformed packet is dropped")
	context.expect_equal(malformed.register(3, 0.1, false), InputRateLimiter.Decision.DROP, "second malformed packet is dropped")
	context.expect_equal(malformed.register(3, 0.2, false), InputRateLimiter.Decision.DISCONNECT, "sustained malformed packets disconnect")


static func _validate_lobby_authority(context: TestContext) -> void:
	var config := MatchConfig.new()
	config.max_players = 4
	var lobby := ServerLobby.new(config)
	context.expect_false(ServerLobby.is_valid_display_name(""), "empty display name is invalid")
	context.expect_false(ServerLobby.is_valid_display_name("abcdefghijklmnopq"), "display name longer than 16 characters is invalid")
	context.expect_false(ServerLobby.is_valid_display_name("bad\nname"), "control characters are invalid in display names")
	context.expect_true(ServerLobby.is_valid_display_name("Nova 星"), "printable Unicode display name is valid")
	context.expect_true(lobby.admit(2, " Nova ").ok, "first peer is admitted with trimmed name")
	context.expect_equal(lobby.leader_id, 2, "first admitted peer becomes leader")
	context.expect_true(lobby.admit(3, "Nova").ok, "duplicate base name is admitted")
	context.expect_equal((lobby.players[3] as PlayerMatchState).display_name, "Nova#2", "duplicate display name receives deterministic suffix")
	context.expect_false(lobby.request_rounds_to_win(3, 5).ok, "non-leader cannot change lobby config")
	context.expect_true(lobby.request_rounds_to_win(2, 5).ok, "leader can change lobby config")
	context.expect_equal(lobby.config.rounds_to_win, 5, "authorized lobby config change applies")
	context.expect_true(lobby.request_start(2).ok, "leader starts with two participants")
	context.expect_true(lobby.admit(4, "Late").ok, "late peer is admitted during match")
	context.expect_false((lobby.players[4] as PlayerMatchState).participant, "late peer joins as spectator")
	lobby.remove(2)
	context.expect_equal(lobby.leader_id, 3, "leader transfers to earliest remaining peer")
	lobby.return_to_lobby()
	context.expect_true((lobby.players[4] as PlayerMatchState).participant, "late spectator promotes on lobby return")
	context.expect_equal(lobby.participant_count(), 2, "all connected peers participate after reset")
	context.expect_true(lobby.admit(5, "Fourth").ok, "lobby admits up to configured capacity")
	context.expect_true(lobby.admit(6, "Fourth Again").ok, "lobby admits its final capacity slot")
	context.expect_false(lobby.admit(7, "Full").ok, "full lobby rejects another peer")
	var serialized := lobby.serialize()
	context.expect_equal(serialized.leader_id, 3, "serialized lobby contains authoritative leader")
	context.expect_equal((serialized.players as Array).size(), 4, "serialized lobby contains all admitted peers")


static func _validate_prediction_and_interpolation(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	var prediction := ClientPredictionBuffer.new()
	prediction.predicted_position = Vector2(100.0, 100.0)
	for sequence in range(1, 122):
		var frame := PlayerInputFrame.new(sequence, sequence, Vector2(0.0, -1.0), 0.0)
		prediction.predict(frame, stats, 1.0 / 60.0)
	context.expect_true(prediction.buffered_inputs.size() >= 120, "prediction buffer retains at least 120 input frames")
	var before_reconcile := prediction.predicted_position
	var result := prediction.reconcile(before_reconcile - Vector2(10.0, 0.0), prediction.predicted_velocity, 120, stats)
	context.expect_false(result.snapped, "prediction errors up to 128 pixels use smoothing")
	context.expect_equal(prediction.buffered_inputs.size(), 1, "acknowledged prediction inputs are pruned")
	context.expect_true(prediction.visual_position(0.05) != prediction.predicted_position, "small correction retains a temporary visual offset")
	prediction.predicted_position += Vector2(200.0, 0.0)
	var snap_result := prediction.reconcile(Vector2.ZERO, Vector2.ZERO, 121, stats)
	context.expect_true(snap_result.snapped, "prediction error above 128 pixels snaps")
	context.expect_equal(prediction.snap_count, 1, "prediction snap increments diagnostics")

	var interpolation := RemoteInterpolator.new()
	interpolation.add_sample(3, 0.0, {"position": Vector2.ZERO, "velocity": Vector2(100.0, 0.0), "aim_angle": 0.0})
	interpolation.add_sample(3, 0.2, {"position": Vector2(20.0, 0.0), "velocity": Vector2(100.0, 0.0), "aim_angle": PI * 0.5})
	var interpolated := interpolation.sample(3, 0.2)
	context.expect_approx((interpolated.position as Vector2).x, 10.0, "remote player renders 100 ms behind between snapshots")
	context.expect_false(interpolated.extrapolated, "surrounded remote sample interpolates")
	var extrapolated := interpolation.sample(3, 0.5)
	context.expect_approx((extrapolated.position as Vector2).x, 30.0, "remote extrapolation is capped at 100 ms")
	context.expect_true(extrapolated.extrapolated, "late remote sample reports extrapolation")

	var predicted_projectiles := PredictedProjectileTracker.new()
	predicted_projectiles.add(2, 7, 0.0)
	context.expect_true(predicted_projectiles.reconcile(2, 7), "authoritative projectile matches owner and shot sequence")
	predicted_projectiles.add(2, 8, 0.0)
	context.expect_true(predicted_projectiles.reject(2, 8, 1.0), "rejected predicted projectile begins fade")
	context.expect_empty(predicted_projectiles.step(1.099), "rejected projectile remains during 100 ms fade")
	context.expect_equal(predicted_projectiles.step(1.1), ["2:8"], "rejected projectile is removed after 100 ms fade")


static func _validate_authoritative_world(context: TestContext) -> void:
	var wall_collision := ArenaCollisionSystem.move_ship(Vector2(25.0, 100.0), Vector2(-100.0, 0.0), 1.0)
	context.expect_approx((wall_collision.position as Vector2).x, GameConstants.SHIP_COLLISION_RADIUS, "authoritative arena prevents crossing outer wall")
	context.expect_approx((wall_collision.velocity as Vector2).x, 0.0, "outer wall removes inward velocity and preserves slide")
	var central_collision := ArenaCollisionSystem.move_ship(ArenaLayout.center() + Vector2(210.0, 0.0), Vector2(-100.0, 50.0), 0.2)
	var central_position := central_collision.position as Vector2
	var central_velocity := central_collision.velocity as Vector2
	var central_normal := (central_position - ArenaLayout.center()).normalized()
	context.expect_true(central_position.distance_to(ArenaLayout.center()) >= 200.0, "authoritative movement excludes central obstacle")
	context.expect_true(central_velocity.dot(-central_normal) <= 0.0001, "central obstacle removes inward velocity")
	context.expect_true(central_velocity.length() > 0.0, "central obstacle preserves tangential slide motion")

	var world := AuthoritativeWorld.new()
	var first := world.add_peer(2)
	var second := world.add_peer(3)
	var start_x := first.position.x
	context.expect_true(world.submit_input(2, PlayerInputFrame.new(1, 1, Vector2(0.0, -1.0), 0.0)), "authoritative world accepts first valid input")
	context.expect_false(world.submit_input(2, PlayerInputFrame.new(1, 2, Vector2.ZERO, 0.0)), "authoritative world ignores duplicate input sequence")
	world.step(1.0 / 60.0)
	context.expect_true(first.position.x > start_x, "authoritative world applies ship-relative forward movement")
	context.expect_equal(world.acknowledged_input(2), 1, "authoritative world tracks latest accepted input")
	var aim_to_second := (second.position - first.position).angle()
	context.expect_true(world.submit_input(2, PlayerInputFrame.new(2, 2, Vector2.ZERO, aim_to_second, true)), "authoritative world accepts firing input")
	world.step(1.0 / 60.0)
	var projectile_batch := world.drain_projectile_batch()
	context.expect_equal((projectile_batch.spawned as Array).size(), 1, "authoritative firing creates projectile")
	world.submit_input(2, PlayerInputFrame.new(3, 3, Vector2.ZERO, aim_to_second, false))
	for tick in 30:
		world.step(1.0 / 60.0)
	context.expect_true(second.health < second.stats.max_health, "authoritative projectile damages another peer")
	context.expect_equal(first.health, first.stats.max_health, "authoritative projectile preserves owner immunity")
	var snapshot := world.snapshot_states()
	context.expect_equal(snapshot.size(), 2, "authoritative snapshot contains every connected combatant")
	context.expect_true(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(world.server_tick, world.acknowledged_input(2), snapshot)).ok, "authoritative world snapshot survives wire encoding")


static func _validate_connection_admission(context: TestContext) -> void:
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION + 1, "Pilot", 0, 32),
		NetworkProtocol.REJECT_VERSION_MISMATCH,
		"version-mismatched hello receives exact rejection code"
	)
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "Pilot", 32, 32),
		NetworkProtocol.REJECT_SERVER_FULL,
		"full server hello receives exact rejection code"
	)
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "bad\nname", 0, 32),
		NetworkProtocol.REJECT_INVALID_NAME,
		"invalid-name hello receives exact rejection code"
	)
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "Pilot", 0, 32),
		&"",
		"valid hello passes admission validation"
	)
	var handshakes := HandshakeRegistry.new()
	handshakes.begin(9, 100.0)
	context.expect_true(handshakes.has(9), "new transport peer enters pending handshake registry")
	context.expect_empty(handshakes.expired(109.999), "handshake remains pending before ten-second deadline")
	context.expect_equal(handshakes.expired(110.0), [9], "handshake expires at ten-second deadline")
	context.expect_true(handshakes.complete(9), "completed handshake is removed")
