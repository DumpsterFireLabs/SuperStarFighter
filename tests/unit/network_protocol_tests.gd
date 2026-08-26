class_name NetworkProtocolTests
extends RefCounted


static func run(context: TestContext) -> void:
	_validate_sequence_wrap(context)
	_validate_input_codec(context)
	_validate_snapshot_codec(context)
	_validate_projectile_codec(context)
	_validate_lan_discovery_protocol(context)
	_validate_rate_limiting(context)
	_validate_observability_bounds(context)
	_validate_lobby_authority(context)
	_validate_npc_lobby_and_inputs(context)
	_validate_prediction_and_interpolation(context)
	_validate_authoritative_world(context)
	_validate_connection_admission(context)
	_validate_reconnect_reset(context)


static func _validate_sequence_wrap(context: TestContext) -> void:
	context.expect_true(SequenceMath.is_newer(11, 10), "later sequence is newer")
	context.expect_false(SequenceMath.is_newer(10, 10), "duplicate sequence is not newer")
	context.expect_false(SequenceMath.is_newer(9, 10), "older sequence is not newer")
	context.expect_true(SequenceMath.is_newer(0, 0xffffffff), "sequence comparison handles uint32 wrap")
	context.expect_false(SequenceMath.is_newer(0xffffffff, 0), "pre-wrap sequence is older after wrap")
	context.expect_equal(SequenceMath.increment(0xffffffff), 0, "uint32 sequence increment wraps to zero")


static func _validate_lan_discovery_protocol(context: TestContext) -> void:
	var query_packet := LanDiscoveryProtocol.encode_query("test-nonce")
	context.expect_true(query_packet.size() <= LanDiscoveryProtocol.MAX_PACKET_BYTES, "LAN discovery query is bounded")
	var query := LanDiscoveryProtocol.decode_query(query_packet)
	context.expect_true(query.ok and query.nonce == "test-nonce", "LAN discovery query round-trips its nonce")
	context.expect_false(LanDiscoveryProtocol.decode_query(PackedByteArray()).ok, "empty LAN discovery query is rejected")
	context.expect_false(LanDiscoveryProtocol.decode_query(PackedByteArray([1, 2, 3])).ok, "malformed LAN discovery query is rejected")
	var oversized := PackedByteArray()
	oversized.resize(LanDiscoveryProtocol.MAX_PACKET_BYTES + 1)
	context.expect_false(LanDiscoveryProtocol.decode_query(oversized).ok, "oversized LAN discovery query is rejected before JSON parsing")
	var response_packet := LanDiscoveryProtocol.encode_response("test-nonce", {
		"protocol_version": GameConstants.PROTOCOL_VERSION,
		"instance_id": "unit-server-1",
		"server_name": "Neon Local Arena",
		"game_port": 7000,
		"human_count": 2,
		"npc_count": 3,
		"player_limit": 8,
		"match_active": false,
	})
	context.expect_true(response_packet.size() <= LanDiscoveryProtocol.MAX_PACKET_BYTES, "LAN discovery response is bounded")
	var response := LanDiscoveryProtocol.decode_response(response_packet)
	context.expect_true(response.ok, "valid LAN discovery response decodes")
	context.expect_equal(response.server_name, "Neon Local Arena", "LAN response retains its display name")
	context.expect_equal(response.human_count + response.npc_count, 5, "LAN response retains bounded participant counts")
	context.expect_true(LanDiscoveryProtocol.is_valid_server_name("Friends Only"), "printable LAN server name is valid")
	context.expect_false(LanDiscoveryProtocol.is_valid_server_name("Bad\nName"), "control characters are invalid in LAN server names")
	var invalid_counts := JSON.stringify({
		"magic": LanDiscoveryProtocol.RESPONSE_MAGIC, "nonce": "x", "instance_id": "bad-counts", "protocol_version": 6,
		"server_name": "Bad Counts", "game_port": 7000, "human_count": 20,
		"npc_count": 20, "player_limit": 32, "match_active": false,
	}).to_utf8_buffer()
	context.expect_false(LanDiscoveryProtocol.decode_response(invalid_counts).ok, "LAN response cannot advertise more participants than its limit")


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
	stats.beam_weapon = true
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
		context.expect_true(decoded_projectile.is_beam, "projectile beam presentation flag round-trips")
	context.expect_false(ProjectilePacketCodec.decode_batch(packet.slice(0, 8)).ok, "truncated projectile batch is rejected")
	var bad_flags := packet.duplicate()
	bad_flags[ProjectilePacketCodec.HEADER_SIZE + 26] = 2
	context.expect_false(ProjectilePacketCodec.decode_batch(bad_flags).ok, "unsupported projectile presentation flags are rejected")
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
	var control := RequestRateLimiter.new(2, 2)
	context.expect_equal(control.register(4, 0.0), RequestRateLimiter.Decision.ACCEPT, "control request within its rate window is accepted")
	context.expect_equal(control.register(4, 0.0), RequestRateLimiter.Decision.ACCEPT, "control request at its window limit is accepted")
	context.expect_equal(control.register(4, 0.0), RequestRateLimiter.Decision.DROP, "excess control request is isolated")
	control.register(4, 1.0)
	control.register(4, 1.0)
	context.expect_equal(control.register(4, 1.0), RequestRateLimiter.Decision.DISCONNECT, "sustained excessive control requests disconnect only their sender")
	control.remove_peer(4)
	context.expect_equal(control.register(4, 2.0), RequestRateLimiter.Decision.ACCEPT, "removed peer has no stale limiter state")


static func _validate_observability_bounds(context: TestContext) -> void:
	context.expect_equal(NetworkBridge.percentile_usec([10, 50, 20, 40, 30], 0.95), 50, "simulation diagnostics compute a deterministic p95")
	context.expect_equal(NetworkBridge.percentile_usec([], 0.95), 0, "empty simulation diagnostics have a zero percentile")
	var oversized := "x".repeat(NetworkProtocol.MAX_LOG_STRING_LENGTH + 20)
	var bounded: Variant = NetworkBridge._bounded_log_value(oversized)
	context.expect_equal((bounded as String).length(), NetworkProtocol.MAX_LOG_STRING_LENGTH, "structured log strings are bounded")
	var collection: Array[int] = []
	for index in NetworkProtocol.MAX_LOG_COLLECTION_LENGTH + 5:
		collection.append(index)
	context.expect_equal((NetworkBridge._bounded_log_value(collection) as Array).size(), NetworkProtocol.MAX_LOG_COLLECTION_LENGTH, "structured log collections are bounded")


static func _validate_lobby_authority(context: TestContext) -> void:
	var config := MatchConfig.new()
	config.max_players = 4
	var lobby := ServerLobby.new(config)
	context.expect_false(ServerLobby.is_valid_display_name(""), "empty display name is invalid")
	context.expect_false(ServerLobby.is_valid_display_name("abcdefghijklmnopq"), "display name longer than 16 characters is invalid")
	context.expect_false(ServerLobby.is_valid_display_name("bad\nname"), "control characters are invalid in display names")
	context.expect_true(ServerLobby.is_valid_display_name("Nova 星"), "printable Unicode display name is valid")
	context.expect_equal(NetworkProtocol.rejection_message(NetworkProtocol.REJECT_EJECTED), "You were removed from the lobby by its leader.", "ejected clients receive a clear recovery message")
	context.expect_true(lobby.admit(2, " Nova ").ok, "first peer is admitted with trimmed name")
	context.expect_equal(lobby.leader_id, 2, "first admitted peer becomes leader")
	context.expect_true(lobby.admit(3, "Nova").ok, "duplicate base name is admitted")
	context.expect_equal((lobby.players[3] as PlayerMatchState).display_name, "Nova#2", "duplicate display name receives deterministic suffix")
	context.expect_false(lobby.request_start(2).ok, "leader cannot start before every human is ready")
	context.expect_true(lobby.request_ready(2, true).ok, "human leader may ready up")
	context.expect_false(lobby.request_start(2).ok, "one unready human still blocks match start")
	context.expect_true(lobby.request_ready(3, true).ok, "joined human may ready up")
	context.expect_true(lobby.all_humans_ready(), "lobby reports all humans ready")
	context.expect_true(lobby.admit(8, "EjectMe").ok, "temporary eject target joins the waiting lobby")
	context.expect_false(lobby.request_eject(3, 8).ok, "non-leader cannot eject a lobby player")
	context.expect_false(lobby.request_eject(2, 2).ok, "leader cannot eject themselves")
	context.expect_true(lobby.request_eject(2, 8).ok, "leader may eject another human from the waiting lobby")
	context.expect_false(lobby.players.has(8), "ejected human is removed from authoritative lobby state")
	context.expect_false(lobby.request_rounds_to_win(3, 5).ok, "non-leader cannot change lobby config")
	context.expect_true(lobby.request_rounds_to_win(2, 5).ok, "leader can change lobby config")
	context.expect_equal(lobby.config.rounds_to_win, 5, "authorized lobby config change applies")
	context.expect_false(lobby.all_humans_ready(), "settings changes clear human readiness")
	lobby.request_ready(2, true)
	lobby.request_ready(3, true)
	context.expect_true(lobby.request_start(2).ok, "leader starts with two participants")
	context.expect_false(lobby.request_eject(2, 3).ok, "leader cannot eject a player during an active match")
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


static func _validate_npc_lobby_and_inputs(context: TestContext) -> void:
	var config := MatchConfig.new()
	config.max_players = GameConstants.MAX_PLAYERS
	var lobby := ServerLobby.new(config)
	context.expect_true(lobby.admit(100, "SoloPilot").ok, "solo NPC fixture admits its human leader")
	context.expect_false(lobby.request_player_limit(999, 4).ok, "non-leader cannot change the player limit")
	context.expect_true(lobby.request_player_limit(100, 4).ok, "leader can set a total player limit")
	context.expect_equal(lobby.player_limit, 4, "authoritative lobby retains the selected player limit")
	var enable_result := lobby.request_npcs_enabled(100, true)
	context.expect_true(enable_result.ok, "leader can enable server NPCs")
	context.expect_equal((enable_result.added_npcs as Array).size(), 3, "enabling NPC fill creates configurable waiting NPC rows")
	var npc_id := lobby.npc_peer_ids()[0]
	context.expect_false(lobby.request_npc_difficulty(999, npc_id, NpcPilotController.Difficulty.SKILLED).ok, "non-leader cannot change NPC difficulty")
	context.expect_false(lobby.request_npc_difficulty(100, 100, NpcPilotController.Difficulty.SKILLED).ok, "human players cannot be assigned NPC difficulty")
	context.expect_false(lobby.request_npc_difficulty(100, npc_id, 99).ok, "invalid NPC difficulty is rejected")
	context.expect_true(lobby.request_npc_difficulty(100, npc_id, NpcPilotController.Difficulty.SKILLED).ok, "leader can configure one waiting NPC independently")
	context.expect_equal((lobby.players[npc_id] as PlayerMatchState).npc_difficulty, NpcPilotController.Difficulty.SKILLED, "configured NPC stores its authoritative difficulty")
	context.expect_true(lobby.request_ready(100, true).ok, "solo human readies before NPC force start")
	var start_result := lobby.request_start(100)
	context.expect_true(start_result.ok, "one human can force-start when NPCs are enabled")
	context.expect_empty(start_result.added_npcs as Array, "already configured waiting NPCs require no hidden start-time fill")
	context.expect_equal(lobby.participant_count(), 4, "solo force-start reaches the configured participant count")
	context.expect_equal(lobby.npc_count(), 3, "authoritative lobby distinguishes NPC participants")
	context.expect_equal(lobby.leader_id, 100, "NPCs never replace the human lobby leader")
	var serialized := lobby.serialize()
	context.expect_equal(serialized.player_limit, 4, "serialized lobby publishes the configured player limit")
	context.expect_true(serialized.npcs_enabled, "serialized lobby publishes NPC enablement")
	context.expect_equal(serialized.npc_count, 3, "serialized lobby publishes its NPC count")
	context.expect_true(serialized.all_humans_ready, "serialized lobby publishes aggregate readiness")
	var serialized_npc := (serialized.players as Array).filter(func(player: Dictionary) -> bool: return int(player.peer_id) == npc_id)[0] as Dictionary
	context.expect_equal(serialized_npc.npc_difficulty, NpcPilotController.Difficulty.SKILLED, "serialized NPC row publishes its individual difficulty")

	for difficulty in range(NpcPilotController.Difficulty.EASY, NpcPilotController.Difficulty.INSANE + 1):
		var lower := NpcPilotController.difficulty_profile(difficulty - 1)
		var upper := NpcPilotController.difficulty_profile(difficulty)
		context.expect_true(int(upper.reaction_ticks) < int(lower.reaction_ticks), "%s reacts faster than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.aim_error_degrees) < float(lower.aim_error_degrees), "%s aims more accurately than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.pursuit) > float(lower.pursuit), "%s applies more movement pressure than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.fire_duty) > float(lower.fire_duty), "%s fires more decisively than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.awareness_range) > float(lower.awareness_range), "%s detects targets farther away than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])

	var world := AuthoritativeWorld.new()
	var human := world.add_peer(100)
	world.add_peer(npc_id)
	var npc := world.combatants[npc_id] as CombatantState
	human.position = Vector2(1100.0, 900.0)
	npc.position = Vector2(700.0, 900.0)
	var controller := NpcPilotController.new()
	world.server_tick = 40
	controller.submit_inputs(world, lobby.npc_peer_ids(), lobby.npc_difficulties())
	var npc_input := world.latest_inputs[npc_id] as PlayerInputFrame
	context.expect_true(npc_input.firing, "server-owned NPC acquires a target and fires without a client")
	context.expect_true(absf(npc_input.aim_angle) <= deg_to_rad(2.6), "skilled NPC aim stays within its configured error envelope")
	world.step(1.0 / 60.0)
	context.expect_true(npc.velocity.length() > 0.0, "server-owned NPC produces authoritative movement")
	var passive_controller := NpcPilotController.new()
	world.server_tick = 80
	passive_controller.submit_inputs(world, [npc_id], {npc_id: NpcPilotController.Difficulty.PASSIVE})
	var passive_input := world.latest_inputs[npc_id] as PlayerInputFrame
	context.expect_false(passive_input.firing or passive_input.shielding, "passive NPC remains non-hostile")
	context.expect_true(passive_input.movement.length() <= 0.26, "passive NPC movement remains deliberately gentle")

	var overtime_world := AuthoritativeWorld.new()
	var endangered_npc_id := ServerLobby.NPC_PEER_ID_BASE + 20
	var endangered_npc := overtime_world.add_peer(endangered_npc_id)
	endangered_npc.position = Vector2(400.0, ArenaLayout.center().y)
	overtime_world.server_tick = 120
	var overtime_controller := NpcPilotController.new()
	overtime_controller.submit_inputs(
		overtime_world,
		[endangered_npc_id],
		{endangered_npc_id: NpcPilotController.Difficulty.PASSIVE},
		120.0
	)
	var overtime_input := overtime_world.latest_inputs[endangered_npc_id] as PlayerInputFrame
	var overtime_world_movement := MovementSystem.ship_relative_to_world(
		overtime_input.movement,
		overtime_input.aim_angle
	)
	context.expect_true(
		overtime_world_movement.dot((ArenaLayout.center() - endangered_npc.position).normalized()) > 0.95,
		"even a passive NPC urgently steers toward safety outside the overtime circle"
	)

	var cover_world := AuthoritativeWorld.new()
	var holding_npc_id := ServerLobby.NPC_PEER_ID_BASE + 30
	var flanking_npc_id := holding_npc_id + 1
	var holding_npc := cover_world.add_peer(holding_npc_id)
	var flanking_npc := cover_world.add_peer(flanking_npc_id)
	holding_npc.position = Vector2(700.0, 550.0)
	flanking_npc.position = Vector2(1200.0, 550.0)
	cover_world.server_tick = 120
	var cover_controller := NpcPilotController.new()
	var cover_difficulties := {
		holding_npc_id: NpcPilotController.Difficulty.NEUTRAL,
		flanking_npc_id: NpcPilotController.Difficulty.NEUTRAL,
	}
	cover_controller.submit_inputs(
		cover_world,
		[holding_npc_id, flanking_npc_id],
		cover_difficulties
	)
	var holding_input := cover_world.latest_inputs[holding_npc_id] as PlayerInputFrame
	var flanking_input := cover_world.latest_inputs[flanking_npc_id] as PlayerInputFrame
	var initial_flank_world_movement := MovementSystem.ship_relative_to_world(
		flanking_input.movement,
		flanking_input.aim_angle
	)
	context.expect_equal(
		holding_input.movement,
		Vector2.ZERO,
		"lower-ID member of an occluded NPC pair holds instead of mirror-strafing"
	)
	context.expect_false(
		holding_input.firing or flanking_input.firing,
		"NPCs do not waste shots through blocking cover"
	)
	context.expect_true(
		absf(initial_flank_world_movement.y) > 0.55,
		"higher-ID member of an occluded NPC pair commits to a cover flank"
	)
	var flank_start := flanking_npc.position
	for _tick in 240:
		cover_controller.submit_inputs(
			cover_world,
			[holding_npc_id, flanking_npc_id],
			cover_difficulties
		)
		cover_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_true(
		flanking_npc.position.distance_to(flank_start) > 100.0,
		"deterministic flanker escapes the symmetric cover loop"
	)
	context.expect_true(
		absf(flanking_npc.position.y - 550.0) > 70.0 or holding_npc.health < holding_npc.stats.max_health,
		"cover flank opens a new lane or converts into combat"
	)

	var loop_world := AuthoritativeWorld.new()
	var loop_holder := loop_world.add_peer(holding_npc_id)
	var loop_flanker := loop_world.add_peer(flanking_npc_id)
	loop_holder.position = Vector2(700.0, 550.0)
	loop_flanker.position = Vector2(1200.0, 550.0)
	var loop_controller := NpcPilotController.new()
	for decision_tick in range(0, GameConstants.PHYSICS_TICKS_PER_SECOND * 4, 10):
		loop_world.server_tick = decision_tick
		loop_controller.submit_inputs(
			loop_world,
			[holding_npc_id, flanking_npc_id],
			cover_difficulties
		)
	var loop_holder_input := loop_world.latest_inputs[holding_npc_id] as PlayerInputFrame
	var loop_flanker_input := loop_world.latest_inputs[flanking_npc_id] as PlayerInputFrame
	var loop_holder_world_movement := MovementSystem.ship_relative_to_world(
		loop_holder_input.movement,
		loop_holder_input.aim_angle
	)
	var loop_flanker_world_movement := MovementSystem.ship_relative_to_world(
		loop_flanker_input.movement,
		loop_flanker_input.aim_angle
	)
	context.expect_true(
		loop_holder_world_movement.length() > 0.4,
		"a persistently blocked holder eventually joins the breakout instead of waiting for overtime"
	)
	context.expect_true(
		loop_holder_world_movement.y * loop_flanker_world_movement.y < -0.1,
		"loop breakout sends the paired NPCs around opposite sides of cover"
	)
	loop_flanker.position = Vector2(700.0, 900.0)
	loop_world.server_tick = GameConstants.PHYSICS_TICKS_PER_SECOND * 5
	loop_controller.submit_inputs(loop_world, [holding_npc_id, flanking_npc_id], cover_difficulties)
	loop_flanker.position = Vector2(1200.0, 550.0)
	loop_world.server_tick += 10
	loop_controller.submit_inputs(loop_world, [holding_npc_id, flanking_npc_id], cover_difficulties)
	loop_holder_input = loop_world.latest_inputs[holding_npc_id] as PlayerInputFrame
	context.expect_equal(
		loop_holder_input.movement,
		Vector2.ZERO,
		"a sustained clear sightline resets the blocked-loop breakout state"
	)

	var flicker_world := AuthoritativeWorld.new()
	var flicker_holder := flicker_world.add_peer(holding_npc_id)
	var flicker_flanker := flicker_world.add_peer(flanking_npc_id)
	flicker_holder.position = Vector2(700.0, 550.0)
	flicker_flanker.position = Vector2(1200.0, 550.0)
	var flicker_controller := NpcPilotController.new()
	for decision_tick in range(0, 150, 10):
		flicker_world.server_tick = decision_tick
		flicker_controller.submit_inputs(flicker_world, [holding_npc_id, flanking_npc_id], cover_difficulties)
	flicker_flanker.position = Vector2(700.0, 900.0)
	for decision_tick in range(150, 180, 10):
		flicker_world.server_tick = decision_tick
		flicker_controller.submit_inputs(flicker_world, [holding_npc_id, flanking_npc_id], cover_difficulties)
	flicker_flanker.position = Vector2(1200.0, 550.0)
	for decision_tick in range(180, 240, 10):
		flicker_world.server_tick = decision_tick
		flicker_controller.submit_inputs(flicker_world, [holding_npc_id, flanking_npc_id], cover_difficulties)
	var flicker_holder_input := flicker_world.latest_inputs[holding_npc_id] as PlayerInputFrame
	context.expect_true(
		flicker_holder_input.movement.length() > 0.4,
		"brief sightline flickers do not restart a persistent cover loop"
	)

	var central_loop_world := AuthoritativeWorld.new()
	var central_holder := central_loop_world.add_peer(holding_npc_id)
	var central_flanker := central_loop_world.add_peer(flanking_npc_id)
	central_holder.position = ArenaLayout.center() - Vector2(280.0, 0.0)
	central_flanker.position = ArenaLayout.center() + Vector2(280.0, 0.0)
	var central_loop_controller := NpcPilotController.new()
	for decision_tick in range(0, GameConstants.PHYSICS_TICKS_PER_SECOND * 4, 10):
		central_loop_world.server_tick = decision_tick
		central_loop_controller.submit_inputs(
			central_loop_world,
			[holding_npc_id, flanking_npc_id],
			cover_difficulties
		)
	var central_holder_input := central_loop_world.latest_inputs[holding_npc_id] as PlayerInputFrame
	var central_flanker_input := central_loop_world.latest_inputs[flanking_npc_id] as PlayerInputFrame
	var central_holder_movement := MovementSystem.ship_relative_to_world(
		central_holder_input.movement,
		central_holder_input.aim_angle
	)
	var central_flanker_movement := MovementSystem.ship_relative_to_world(
		central_flanker_input.movement,
		central_flanker_input.aim_angle
	)
	context.expect_true(
		central_holder_movement.length() > 0.4,
		"persistent occlusion around the central obstacle also triggers a breakout"
	)
	var holder_orbit_direction := (central_holder.position - ArenaLayout.center()).cross(central_holder_movement)
	var flanker_orbit_direction := (central_flanker.position - ArenaLayout.center()).cross(central_flanker_movement)
	context.expect_true(
		holder_orbit_direction * flanker_orbit_direction < 0.0,
		"central-obstacle breakout closes angular separation instead of preserving a mirrored orbit"
	)
	var central_lane_opened := false
	for _tick in GameConstants.PHYSICS_TICKS_PER_SECOND * 4:
		central_loop_controller.submit_inputs(
			central_loop_world,
			[holding_npc_id, flanking_npc_id],
			cover_difficulties
		)
		central_loop_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
		if NpcPilotController._first_blocking_obstacle(
			central_holder.position,
			central_flanker.position
		).is_empty():
			central_lane_opened = true
	context.expect_true(
		central_lane_opened,
		"central-obstacle breakout produces a clear engagement lane before overtime"
	)

	lobby.return_to_lobby()
	var replacement := lobby.admit(101, "SecondPilot")
	context.expect_true(replacement.ok, "a joining human can replace an NPC in the waiting lobby")
	context.expect_equal((replacement.removed_npc_ids as Array).size(), 1, "human admission reports the replaced NPC entity")
	context.expect_equal(lobby.human_count(), 2, "human replacement increases the connected human count")
	context.expect_equal(lobby.players.size(), 4, "human replacement preserves the configured total-player limit")


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

	var blocked_world := AuthoritativeWorld.new()
	var blocked_shooter := blocked_world.add_peer(20)
	blocked_shooter.position = Vector2(GameConstants.SHIP_COLLISION_RADIUS, 500.0)
	blocked_world.submit_input(20, PlayerInputFrame.new(1, 1, Vector2.ZERO, PI, true))
	blocked_world.step(1.0 / 60.0)
	var blocked_batch := blocked_world.drain_projectile_batch()
	context.expect_empty(blocked_batch.spawned, "muzzle against boundary cannot create projectile beyond wall")
	context.expect_equal(blocked_world.projectile_registry.size(), 0, "blocked muzzle leaves no through-wall projectile")

	var ricochet_stats := CombatStats.create_base()
	ricochet_stats.ricochet_count = 1
	var ricochet_world := AuthoritativeWorld.new()
	var ricochet_shooter := ricochet_world.add_peer(21, ricochet_stats)
	ricochet_shooter.position = Vector2(GameConstants.SHIP_COLLISION_RADIUS, 600.0)
	ricochet_world.submit_input(21, PlayerInputFrame.new(1, 1, Vector2.ZERO, PI, true))
	ricochet_world.step(1.0 / 60.0)
	var ricochet_batch := ricochet_world.drain_projectile_batch()
	context.expect_equal((ricochet_batch.spawned as Array).size(), 1, "wall-adjacent ricochet shot bounces instead of crossing wall")
	if not (ricochet_batch.spawned as Array).is_empty():
		var bounced := ricochet_batch.spawned[0] as ProjectileState
		context.expect_true(bounced.velocity.x > 0.0, "wall-adjacent ricochet reflects back into arena")


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


static func _validate_reconnect_reset(context: TestContext) -> void:
	var view := NetworkWorldView.new()
	view.camera = Camera2D.new()
	view.camera.position = Vector2(50.0, 75.0)
	view.local_peer_id = 99
	view.input_sequence = 400
	view.client_tick = 500
	view.prediction_initialized = true
	view.prediction.predicted_position = Vector2(3000.0, 1700.0)
	view.reset_session()
	context.expect_equal(view.local_peer_id, 0, "disconnect clears prior local peer identity")
	context.expect_equal(view.input_sequence, 0, "disconnect clears prior input sequence")
	context.expect_equal(view.client_tick, 0, "disconnect clears prior client tick")
	context.expect_false(view.prediction_initialized, "disconnect clears prior prediction initialization")
	context.expect_equal(view.camera.position, ArenaLayout.center(), "disconnect recenters network camera on the arena")
	view.local_peer_id = 99
	view.set_network_active(false, false)
	context.expect_equal(view.local_peer_id, 99, "hiding the arena in a connected lobby preserves local peer identity")
	view.set_network_active(true)
	context.expect_equal(view.local_peer_id, 99, "match activation restores rendering with the same local peer identity")
	var local_ship := SandboxShip.new()
	local_ship.setup(99, CombatStats.create_base(), Vector2(140.0, 220.0), Color.WHITE, true)
	view.ships[99] = local_ship
	view.local_peer_id = 99
	view.apply_match_state({"state_name": "COUNTDOWN", "builds": {}})
	context.expect_equal(view.camera.position, local_ship.global_position, "round countdown snaps the camera to the local ship")
	local_ship.free()
	view.camera.free()
	view.free()
