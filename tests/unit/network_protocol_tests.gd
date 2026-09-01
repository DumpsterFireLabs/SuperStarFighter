class_name NetworkProtocolTests
extends RefCounted

const CardPowerupSystemScript = preload("res://src/shared/combat/card_powerup_system.gd")
const AuthenticationAttemptLimiterScript = preload("res://src/shared/network/authentication_attempt_limiter.gd")
const ProjectileCorrectionAssemblerScript = preload("res://src/shared/network/projectile_correction_assembler.gd")
const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")


static func run(context: TestContext) -> void:
	_validate_sequence_wrap(context)
	_validate_input_codec(context)
	_validate_snapshot_codec(context)
	_validate_projectile_codec(context)
	_validate_lan_discovery_protocol(context)
	_validate_rate_limiting(context)
	_validate_observability_bounds(context)
	_validate_lobby_authority(context)
	_validate_team_assignment_authority(context)
	_validate_npc_lobby_and_inputs(context)
	_validate_prediction_and_interpolation(context)
	_validate_authoritative_world(context)
	_validate_new_card_mechanics(context)
	_validate_card_powerups(context)
	_validate_connection_admission(context)
	_validate_reconnect_reset(context)


static func _validate_sequence_wrap(context: TestContext) -> void:
	context.expect_true(SequenceMath.is_newer(11, 10), "later sequence is newer")
	context.expect_false(SequenceMath.is_newer(10, 10), "duplicate sequence is not newer")
	context.expect_false(SequenceMath.is_newer(9, 10), "older sequence is not newer")
	context.expect_true(SequenceMath.is_newer(0, 0xffffffff), "sequence comparison handles uint32 wrap")
	context.expect_false(SequenceMath.is_newer(0xffffffff, 0), "pre-wrap sequence is older after wrap")
	context.expect_equal(SequenceMath.increment(0xffffffff), 0, "uint32 sequence increment wraps to zero")
	var channels := [
		NetworkProtocol.CHANNEL_CONTROL,
		NetworkProtocol.CHANNEL_INPUT,
		NetworkProtocol.CHANNEL_PLAYER_SNAPSHOT,
		NetworkProtocol.CHANNEL_PROJECTILE_DELTA,
		NetworkProtocol.CHANNEL_PROJECTILE_CORRECTION,
		NetworkProtocol.CHANNEL_OBJECTIVE,
	]
	var unique_channels: Dictionary = {}
	for channel in channels:
		unique_channels[channel] = true
	context.expect_equal(unique_channels.size(), channels.size(), "latency-sensitive ENet streams use independent channels")
	context.expect_equal(NetworkProtocol.CHANNEL_COUNT, channels.size(), "ENet allocation covers every declared transport channel")


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
		"password_required": true,
	})
	context.expect_true(response_packet.size() <= LanDiscoveryProtocol.MAX_PACKET_BYTES, "LAN discovery response is bounded")
	var response := LanDiscoveryProtocol.decode_response(response_packet)
	context.expect_true(response.ok, "valid LAN discovery response decodes")
	context.expect_equal(response.server_name, "Neon Local Arena", "LAN response retains its display name")
	context.expect_equal(response.human_count + response.npc_count, 5, "LAN response retains bounded participant counts")
	context.expect_true(response.password_required, "LAN response advertises password protection without exposing the password")
	context.expect_true(LanDiscoveryProtocol.is_valid_server_name("Friends Only"), "printable LAN server name is valid")
	context.expect_false(LanDiscoveryProtocol.is_valid_server_name("Bad\nName"), "control characters are invalid in LAN server names")
	var invalid_counts := JSON.stringify({
		"magic": LanDiscoveryProtocol.RESPONSE_MAGIC, "nonce": "x", "instance_id": "bad-counts", "protocol_version": 6,
		"server_name": "Bad Counts", "game_port": 7000, "human_count": 20,
		"npc_count": 20, "player_limit": 32, "match_active": false,
	}).to_utf8_buffer()
	context.expect_false(LanDiscoveryProtocol.decode_response(invalid_counts).ok, "LAN response cannot advertise more participants than its limit")


static func _validate_input_codec(context: TestContext) -> void:
	var original := PlayerInputFrame.new(0xfffffffe, 800, Vector2(0.5, -0.75), 5.5, true, true, true, true)
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
		context.expect_true(frame.firing and frame.shielding and frame.manual_reload and frame.special_activated, "input action bits round-trip")
	context.expect_false(InputPacketCodec.decode(packet.slice(0, 12)).ok, "truncated input packet is rejected")
	var bad_version := packet.duplicate()
	bad_version[0] = 99
	context.expect_false(InputPacketCodec.decode(bad_version).ok, "input packet version mismatch is rejected")
	var bad_actions := packet.duplicate()
	bad_actions[15] = 16
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
			"afterburner_active": peer_id == 2,
			"mine_charges": 9 if peer_id == 2 else 0,
			"mine_cooldown": 7.25 if peer_id == 2 else 0.0,
			"cloaked": peer_id == 2,
			"cloak_charges": 3 if peer_id == 2 else 0,
			"cloak_cooldown": 12.5 if peer_id == 2 else 0.0,
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
		context.expect_true(bool(first.afterburner_active), "snapshot carries the authoritative Afterburner bloom state")
		context.expect_equal(int(first.mine_charges), 9, "snapshot carries authoritative remaining mine charges")
		context.expect_approx(float(first.mine_cooldown), 7.25, "snapshot carries the authoritative mine cooldown")
		context.expect_true(bool(first.cloaked), "snapshot carries the authoritative cloak state")
		context.expect_equal(int(first.cloak_charges), 3, "snapshot carries heat-scoped cloak charges")
		context.expect_approx(float(first.cloak_cooldown), 12.5, "snapshot carries the authoritative cloak cooldown")
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
	projectile.has_rebounded = true
	var spawned: Array[ProjectileState] = [projectile]
	var mine := ProjectileState.create_mine(78, 4, Vector2(400.0, 500.0))
	spawned.append(mine)
	var packets := ProjectilePacketCodec.encode_batch_chunks(1000, 7, spawned, [10, 11])
	context.expect_equal(packets.size(), 1, "small projectile batch fits one bounded transport message")
	var packet := packets[0]
	var decoded := ProjectilePacketCodec.decode_batch(packet)
	context.expect_true(decoded.ok, "projectile batch decodes")
	if decoded.ok:
		context.expect_equal(decoded.server_tick, 1000, "projectile batch tick round-trips")
		context.expect_equal(decoded.batch_sequence, 7, "projectile batch sequence round-trips")
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
		context.expect_true(decoded_projectile.has_rebounded, "projectile rebound presentation flag round-trips")
		var decoded_mine := decoded.spawned[1] as ProjectileState
		context.expect_true(decoded_mine.is_mine, "mine presentation flag round-trips")
		context.expect_approx(decoded_mine.radius, GameConstants.MINE_RADIUS, "decoded mine restores its collision radius")
		context.expect_approx(decoded_mine.mine_activation_remaining, GameConstants.MINE_ACTIVATION_SECONDS, "mine activation time round-trips")
		context.expect_approx(decoded_mine.damage, 100.0, "mine damage round-trips")
	context.expect_false(ProjectilePacketCodec.decode_batch(packet.slice(0, 8)).ok, "truncated projectile batch is rejected")
	var bad_flags := packet.duplicate()
	bad_flags[ProjectilePacketCodec.HEADER_SIZE + 26] = 8
	context.expect_false(ProjectilePacketCodec.decode_batch(bad_flags).ok, "unsupported projectile presentation flags are rejected")
	var correction := ProjectilePacketCodec.encode_correction_chunks(1001, 8, spawned, true)[0]
	context.expect_true(ProjectilePacketCodec.decode_correction(correction).ok, "projectile correction round-trips")
	context.expect_false(ProjectilePacketCodec.decode_correction(packet).ok, "projectile correction rejects removal records")
	var crowded: Array[ProjectileState] = []
	for projectile_id in 100:
		crowded.append(ProjectileState.create(1000 + projectile_id, 4, projectile_id, Vector2(20.0 + projectile_id, 40.0), 0.0, stats))
	var crowded_packets := ProjectilePacketCodec.encode_correction_chunks(1002, 9, crowded, true)
	context.expect_true(crowded_packets.size() > 1, "crowded projectile correction is divided into transport-safe chunks")
	var reconstructed_count := 0
	var assembler := ProjectileCorrectionAssemblerScript.new()
	var assembled_correction: Dictionary = {}
	for crowded_packet in crowded_packets:
		context.expect_true(crowded_packet.size() <= NetworkProtocol.MAX_PROJECTILE_MESSAGE_BYTES, "projectile chunk stays within its transport byte budget")
		var crowded_decoded := ProjectilePacketCodec.decode_correction(crowded_packet)
		context.expect_true(crowded_decoded.ok, "each crowded projectile chunk decodes independently")
		if crowded_decoded.ok:
			reconstructed_count += (crowded_decoded.spawned as Array).size()
			var assembled := assembler.accept(crowded_decoded)
			if not assembled.is_empty():
				assembled_correction = assembled
	context.expect_equal(reconstructed_count, crowded.size(), "chunked correction preserves every projectile record")
	context.expect_equal((assembled_correction.get("spawned", []) as Array).size(), crowded.size(), "client correction assembly applies a full snapshot only after every chunk arrives")
	context.expect_true(bool(assembled_correction.get("complete_snapshot", false)), "assembled crowded correction retains full-snapshot semantics")
	var removed: Array[int] = []
	for projectile_id in 100:
		removed.append(2000 + projectile_id)
	var mixed_packets := ProjectilePacketCodec.encode_batch_chunks(1003, 10, crowded, removed)
	var mixed_spawned_count := 0
	var mixed_removed_count := 0
	for mixed_packet in mixed_packets:
		context.expect_true(mixed_packet.size() <= NetworkProtocol.MAX_PROJECTILE_MESSAGE_BYTES, "mixed projectile batch chunk stays within its transport byte budget")
		var mixed_decoded := ProjectilePacketCodec.decode_batch(mixed_packet)
		context.expect_true(mixed_decoded.ok, "each mixed projectile batch chunk decodes")
		if mixed_decoded.ok:
			mixed_spawned_count += (mixed_decoded.spawned as Array).size()
			mixed_removed_count += (mixed_decoded.removed as Array).size()
	context.expect_equal(mixed_spawned_count, crowded.size(), "chunked projectile batch preserves all spawn records")
	context.expect_equal(mixed_removed_count, removed.size(), "chunked projectile batch preserves all removal records")


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
	var authentication := AuthenticationAttemptLimiterScript.new(3, 10.0, 30.0)
	context.expect_false(authentication.register_failure("203.0.113.5", 0.0), "first incorrect password does not block a source")
	context.expect_false(authentication.register_failure("203.0.113.5", 1.0), "second incorrect password remains retryable")
	context.expect_true(authentication.register_failure("203.0.113.5", 2.0), "repeated incorrect passwords block their source")
	context.expect_true(authentication.is_blocked("203.0.113.5", 20.0), "authentication cooldown survives reconnects")
	context.expect_false(authentication.is_blocked("203.0.113.6", 20.0), "authentication cooldown is isolated by source")
	context.expect_false(authentication.is_blocked("203.0.113.5", 32.0), "authentication cooldown expires deterministically")


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
	context.expect_equal(NetworkProtocol.rejection_message(NetworkProtocol.REJECT_INVALID_PASSWORD), "The lobby password is incorrect.", "password rejection gives a retryable message")
	context.expect_true(NetworkProtocol.is_valid_lobby_password("friends only"), "printable lobby passwords are accepted")
	context.expect_false(NetworkProtocol.is_valid_lobby_password(""), "empty lobby passwords are rejected")
	context.expect_false(NetworkProtocol.is_valid_lobby_password("bad\npassword"), "control characters are rejected in lobby passwords")
	var authentication_challenge := "ab".repeat(NetworkProtocol.AUTH_CHALLENGE_BYTES)
	var password_proof := NetworkProtocol.lobby_password_proof(authentication_challenge, "friends only")
	var admin_proof := NetworkProtocol.admin_password_proof(authentication_challenge, "friends only")
	context.expect_true(NetworkProtocol.is_valid_auth_challenge(authentication_challenge), "authentication challenge uses the bounded wire format")
	context.expect_true(NetworkProtocol.is_valid_auth_proof(password_proof), "lobby password produces a bounded proof")
	context.expect_false("friends only" in password_proof, "authentication proof never contains the lobby password")
	context.expect_false(password_proof == NetworkProtocol.lobby_password_proof("cd".repeat(NetworkProtocol.AUTH_CHALLENGE_BYTES), "friends only"), "fresh challenges prevent proof replay")
	context.expect_false(password_proof == admin_proof, "lobby credentials cannot be replayed against the admin control plane")
	context.expect_true(NetworkProtocol.is_valid_auth_proof(admin_proof), "admin challenge response uses the bounded proof format")
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
	context.expect_false(lobby.config.random_spawn_powerups, "random spawn powerups default off")
	context.expect_equal(lobby.config.game_mode, GameModeRules.Mode.DEATH_MATCH, "Death Match is the default lobby mode")
	var hill_lobby := ServerLobby.new()
	hill_lobby.admit(20, "HillHost")
	context.expect_true(hill_lobby.request_game_mode(20, GameModeRules.Mode.KING_OF_THE_HILL).ok, "leader can select King of the Hill")
	context.expect_true(hill_lobby.config.random_spawn_powerups, "King of the Hill enables temporary arena powerups by default")
	context.expect_false(hill_lobby.config.random_powerups_permanent, "King of the Hill default powerups expire after the heat")
	context.expect_false(lobby.request_game_mode(3, GameModeRules.Mode.TEAM_DEATH_MATCH).ok, "non-leader cannot change the game mode")
	context.expect_true(lobby.request_game_mode(2, GameModeRules.Mode.TEAM_DEATH_MATCH).ok, "leader can select Team Death Match")
	context.expect_equal(lobby.config.team_count, 2, "Team Death Match defaults to two teams")
	context.expect_equal((lobby.players[2] as PlayerMatchState).team_id, 1, "team modes deterministically place the first participant on Cyan")
	context.expect_equal((lobby.players[3] as PlayerMatchState).team_id, 2, "team modes balance the next participant onto Magenta")
	context.expect_false(lobby.request_random_spawn_powerups(3, true).ok, "non-leader cannot enable random spawn powerups")
	context.expect_true(lobby.request_random_spawn_powerups(2, true).ok, "leader can enable random spawn powerups")
	context.expect_true(lobby.config.random_spawn_powerups, "authoritative lobby retains the powerup option")
	context.expect_false(lobby.request_random_powerup_interval(3, 12.0).ok, "non-leader cannot change the random drop interval")
	context.expect_false(lobby.request_random_powerup_interval(2, 4.0).ok, "drop intervals below five seconds are rejected")
	context.expect_true(lobby.request_random_powerup_interval(2, 12.0).ok, "leader can configure the random drop interval")
	context.expect_true(lobby.request_random_powerups_permanent(2, true).ok, "leader can make random drops permanent for the match")
	context.expect_false(lobby.request_overtime_start(2, 121.0).ok, "overtime values beyond two minutes are rejected")
	context.expect_true(lobby.request_overtime_start(2, 75.0).ok, "leader can configure when overtime begins")
	context.expect_false(lobby.request_player_color(3, false, "not-a-colour").ok, "malformed custom ship colours are rejected")
	context.expect_true(lobby.request_player_color(3, false, "ff00aa").ok, "each human can choose a custom ship colour")
	context.expect_equal((lobby.players[3] as PlayerMatchState).ship_color, "ff00aa", "custom ship colour is stored authoritatively")
	context.expect_false(lobby.request_player_appearance(3, false, "ff00aa", &"unsupported").ok, "unsupported ship patterns are rejected")
	context.expect_true(lobby.request_player_appearance(3, false, "ff00aa", ShipAppearanceScript.ZEBRA).ok, "each human can choose a supported hull pattern")
	context.expect_equal((lobby.players[3] as PlayerMatchState).ship_pattern, ShipAppearanceScript.ZEBRA, "custom ship pattern is stored authoritatively")
	context.expect_true(lobby.request_player_color(3, true, "").ok, "a player can return to a server-selected random colour")
	context.expect_equal((lobby.players[3] as PlayerMatchState).ship_pattern, ShipAppearanceScript.ZEBRA, "randomizing colour preserves the selected hull pattern")
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
	context.expect_true(serialized.random_spawn_powerups, "serialized lobby publishes the optional powerup rule")
	context.expect_approx(float(serialized.random_powerup_interval_seconds), 12.0, "serialized lobby publishes the drop interval")
	context.expect_true(serialized.random_powerups_permanent, "serialized lobby publishes drop permanence")
	context.expect_approx(float(serialized.overtime_start_seconds), 75.0, "serialized lobby publishes the overtime start")
	context.expect_equal(serialized.game_mode, GameModeRules.Mode.TEAM_DEATH_MATCH, "serialized lobby publishes the selected game mode")
	context.expect_equal(serialized.team_count, 2, "serialized lobby publishes the configured team count")
	var serialized_player := (serialized.players as Array).filter(func(player: Dictionary) -> bool: return int(player.peer_id) == 3)[0] as Dictionary
	context.expect_equal(String(serialized_player.ship_color).length(), 6, "serialized player rows publish canonical RGB ship colours")
	context.expect_equal(serialized_player.ship_pattern, ShipAppearanceScript.ZEBRA, "serialized player rows publish the authoritative hull pattern")
	context.expect_true(serialized_player.has("team_selection"), "serialized player rows distinguish Auto from an explicit team selection")


static func _validate_team_assignment_authority(context: TestContext) -> void:
	var config := MatchConfig.new()
	config.max_players = 4
	var lobby := ServerLobby.new(config)
	context.expect_true(lobby.request_rounds_to_win(ServerLobby.OPERATOR_AUTHORITY_ID, 4).ok, "server operator can configure an empty dedicated lobby")
	context.expect_equal(lobby.config.rounds_to_win, 4, "operator configuration reaches authoritative lobby state")
	context.expect_true(lobby.admit(10, "Host").ok, "team authority fixture admits its host")
	context.expect_true(lobby.admit(11, "Guest").ok, "team authority fixture admits a second human")
	context.expect_true(lobby.request_player_limit(10, 4).ok, "team authority fixture reserves four participant seats")
	context.expect_true(lobby.request_npcs_enabled(10, true).ok, "team authority fixture fills its remaining seats with NPCs")
	context.expect_true(lobby.request_game_mode(10, GameModeRules.Mode.TEAM_DEATH_MATCH).ok, "host can enable Team Death Match")
	context.expect_false(lobby.request_team_count(11, 4).ok, "non-host cannot change the configured team count")
	context.expect_false(lobby.request_team_count(10, 5).ok, "team count cannot exceed the participant limit")
	context.expect_true(lobby.request_team_count(10, 4).ok, "host can configure up to four populated teams")
	context.expect_equal(lobby.config.team_count, 4, "authoritative lobby retains the configured team count")
	context.expect_equal(lobby.team_setup_error(), "", "Auto assignment balances four participants across all four teams")
	var npc_ids := lobby.npc_peer_ids()
	context.expect_equal(npc_ids.size(), 2, "team authority fixture exposes two NPC assignment targets")
	var npc_id := npc_ids[0]
	context.expect_true(lobby.request_team_assignment(11, npc_id, 4).ok, "any connected human may assign an NPC team")
	context.expect_equal((lobby.players[npc_id] as PlayerMatchState).team_selection, 4, "NPC stores its explicit team selection")
	context.expect_false(lobby.request_team_assignment(11, 10, 2).ok, "non-host cannot assign another human's team")
	context.expect_true(lobby.request_team_assignment(11, 11, 3).ok, "a non-host human may assign their own team")
	context.expect_true(lobby.request_team_assignment(10, 11, 2).ok, "host may override another human's team")
	context.expect_false(lobby.request_team_assignment(11, npc_id, 5).ok, "team selections outside the configured range are rejected")
	context.expect_equal(lobby.team_setup_error(), "", "Auto seats rebalance around explicit assignments so every team remains populated")
	var serialized := lobby.serialize()
	context.expect_true(serialized.team_setup_valid, "serialized lobby publishes a valid multi-team setup")
	context.expect_equal(serialized.team_count, 4, "serialized lobby keeps the multi-team selection")


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
	context.expect_true(lobby.request_all_npc_difficulty(100, NpcPilotController.Difficulty.INSANE).ok, "leader can set every waiting NPC difficulty at once")
	for bulk_npc_id in lobby.npc_peer_ids():
		context.expect_equal((lobby.players[bulk_npc_id] as PlayerMatchState).npc_difficulty, NpcPilotController.Difficulty.INSANE, "bulk difficulty applies to every existing NPC")
	context.expect_equal(lobby.default_npc_difficulty, NpcPilotController.Difficulty.INSANE, "bulk difficulty becomes the default for future NPC seats")
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
	context.expect_equal(serialized.default_npc_difficulty, NpcPilotController.Difficulty.INSANE, "serialized lobby publishes the bulk NPC difficulty")

	for difficulty in range(NpcPilotController.Difficulty.EASY, NpcPilotController.Difficulty.INSANE + 1):
		var lower := NpcPilotController.difficulty_profile(difficulty - 1)
		var upper := NpcPilotController.difficulty_profile(difficulty)
		context.expect_true(int(upper.reaction_ticks) < int(lower.reaction_ticks), "%s reacts faster than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.aim_error_degrees) < float(lower.aim_error_degrees), "%s aims more accurately than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.pursuit) > float(lower.pursuit), "%s applies more movement pressure than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.fire_duty) > float(lower.fire_duty), "%s fires more decisively than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.awareness_range) > float(lower.awareness_range), "%s detects targets farther away than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.pressure) > float(lower.pressure), "%s closes neutral-range engagements more aggressively than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])
		context.expect_true(float(upper.dodge_strength) > float(lower.dodge_strength), "%s commits more strongly to projectile evasion than %s" % [NpcPilotController.difficulty_name(difficulty), NpcPilotController.difficulty_name(difficulty - 1)])

	var threat_world := AuthoritativeWorld.new()
	var threat_npc_id := ServerLobby.NPC_PEER_ID_BASE + 8
	var threat_npc := threat_world.add_peer(threat_npc_id)
	var threat_attacker := threat_world.add_peer(208)
	threat_npc.position = Vector2(1000.0, 900.0)
	threat_attacker.position = Vector2(1600.0, 900.0)
	var incoming := ProjectileState.create(800, threat_attacker.peer_id, 1, Vector2(1250.0, 900.0), PI, threat_attacker.stats)
	threat_world.projectile_registry.add(incoming)
	var threat_controller := NpcPilotController.new()
	var neutral_threat := threat_controller._projectile_evasion(threat_world, threat_npc, NpcPilotController.difficulty_profile(NpcPilotController.Difficulty.NEUTRAL))
	var insane_profile := NpcPilotController.difficulty_profile(NpcPilotController.Difficulty.INSANE)
	var insane_threat := threat_controller._projectile_evasion(threat_world, threat_npc, insane_profile)
	context.expect_true(
		(insane_threat.steering as Vector2).length() * float(insane_profile.dodge_strength) > (neutral_threat.steering as Vector2).length() * float(NpcPilotController.difficulty_profile(NpcPilotController.Difficulty.NEUTRAL).dodge_strength),
		"Insane NPC projectile evasion applies materially stronger lateral steering than Neutral"
	)
	context.expect_true(bool(insane_threat.imminent) and not bool(neutral_threat.imminent), "Insane NPC reacts defensively to incoming rounds earlier than Neutral")
	threat_world.server_tick = 60
	threat_controller.submit_inputs(threat_world, [threat_npc_id], {threat_npc_id: NpcPilotController.Difficulty.INSANE})
	var threat_input := threat_world.latest_inputs[threat_npc_id] as PlayerInputFrame
	context.expect_true(threat_input.shielding and absf(threat_input.movement.x) > 0.35, "Insane NPC combines reactive shielding with a decisive projectile dodge")

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

	var far_world := AuthoritativeWorld.new()
	var far_human := far_world.add_peer(200)
	var far_npc_id := ServerLobby.NPC_PEER_ID_BASE + 10
	var far_npc := far_world.add_peer(far_npc_id)
	far_human.position = Vector2(3020.0, 140.0)
	far_npc.position = Vector2(180.0, 140.0)
	far_world.server_tick = 120
	var far_controller := NpcPilotController.new()
	far_controller.submit_inputs(far_world, [far_npc_id], {far_npc_id: NpcPilotController.Difficulty.PASSIVE})
	var far_input := far_world.latest_inputs[far_npc_id] as PlayerInputFrame
	var far_world_movement := MovementSystem.ship_relative_to_world(far_input.movement, far_input.aim_angle)
	context.expect_true(far_world_movement.dot(Vector2.RIGHT) > 0.05, "even a passive NPC acquires and pursues a target across the full map")

	var contact_world := AuthoritativeWorld.new()
	var contact_human := contact_world.add_peer(300)
	var contact_npc_id := ServerLobby.NPC_PEER_ID_BASE + 11
	var contact_npc := contact_world.add_peer(contact_npc_id)
	contact_human.position = Vector2(1000.0, 1000.0)
	contact_npc.position = Vector2(1035.0, 1000.0)
	contact_world.server_tick = 120
	var contact_controller := NpcPilotController.new()
	contact_controller.submit_inputs(contact_world, [contact_npc_id], {contact_npc_id: NpcPilotController.Difficulty.INSANE})
	var contact_input := contact_world.latest_inputs[contact_npc_id] as PlayerInputFrame
	var contact_escape := MovementSystem.ship_relative_to_world(contact_input.movement, contact_input.aim_angle)
	context.expect_true(contact_escape.dot(Vector2.RIGHT) > 0.55, "NPC close-contact recovery steers decisively away from an overlapping opponent")
	context.expect_false(contact_input.firing or contact_input.shielding, "NPC close-contact recovery releases fire and shield until separation")

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
	var collision_prediction := ClientPredictionBuffer.new()
	collision_prediction.predicted_position = Vector2(GameConstants.SHIP_COLLISION_RADIUS + 1.0, 400.0)
	collision_prediction.predicted_velocity = Vector2(-240.0, 0.0)
	collision_prediction.predict(PlayerInputFrame.new(1, 1), stats, 0.1)
	context.expect_true(
		collision_prediction.predicted_position.x >= GameConstants.SHIP_COLLISION_RADIUS,
		"local prediction mirrors authoritative arena collision instead of crossing a wall"
	)
	context.expect_true(
		collision_prediction.predicted_velocity.x >= -0.001,
		"local prediction mirrors authoritative wall slide velocity"
	)

	var interpolation := RemoteInterpolator.new()
	interpolation.add_sample(3, 0.0, 0, {"position": Vector2.ZERO, "velocity": Vector2(100.0, 0.0), "aim_angle": 0.0})
	interpolation.add_sample(3, 0.2, 12, {"position": Vector2(20.0, 0.0), "velocity": Vector2(100.0, 0.0), "aim_angle": PI * 0.5})
	var interpolated := interpolation.sample(3, 0.2)
	context.expect_approx((interpolated.position as Vector2).x, 10.0, "remote player renders 100 ms behind between snapshots")
	context.expect_false(interpolated.extrapolated, "surrounded remote sample interpolates")
	var extrapolated := interpolation.sample(3, 0.5)
	context.expect_approx((extrapolated.position as Vector2).x, 30.0, "remote extrapolation is capped at 100 ms")
	context.expect_true(extrapolated.extrapolated, "late remote sample reports extrapolation")
	interpolation.clear()
	context.expect_false(bool(interpolation.sample(3, 0.5).get("ok", false)), "heat reset discards stale remote interpolation samples")
	var jittered_interpolation := RemoteInterpolator.new()
	jittered_interpolation.add_sample(4, 0.05, 0, {"position": Vector2.ZERO, "velocity": Vector2(100.0, 0.0), "aim_angle": 0.0})
	jittered_interpolation.add_sample(4, 0.25, 6, {"position": Vector2(10.0, 0.0), "velocity": Vector2(100.0, 0.0), "aim_angle": 0.0})
	var jittered_sample := jittered_interpolation.sample(4, 0.25)
	context.expect_approx(
		(jittered_sample.position as Vector2).x,
		9.8,
		"server-tick interpolation resists uneven snapshot arrival spacing",
		0.05
	)

	var predicted_projectiles := PredictedProjectileTracker.new()
	predicted_projectiles.add(2, 7, 0.0)
	context.expect_true(predicted_projectiles.reconcile(2, 7), "authoritative projectile matches owner and shot sequence")
	predicted_projectiles.add(2, 8, 0.0)
	context.expect_true(predicted_projectiles.reject(2, 8, 1.0), "rejected predicted projectile begins fade")
	context.expect_empty(predicted_projectiles.step(1.099), "rejected projectile remains during 100 ms fade")
	context.expect_equal(predicted_projectiles.step(1.1), ["2:8"], "rejected projectile is removed after 100 ms fade")
	predicted_projectiles.add(2, 9, 2.0)
	context.expect_empty(predicted_projectiles.step(2.399, 0.4), "unconfirmed projectile remains inside its network allowance")
	context.expect_equal(predicted_projectiles.step(2.4, 0.4), ["2:9"], "unconfirmed projectile expires at its bounded confirmation timeout")


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
	var team_world := AuthoritativeWorld.new()
	var team_shooter := team_world.add_peer(31)
	var team_ally := team_world.add_peer(32)
	var team_enemy := team_world.add_peer(33)
	team_shooter.position = Vector2(450.0, 350.0)
	team_ally.position = Vector2(550.0, 350.0)
	team_enemy.position = Vector2(650.0, 350.0)
	team_world.set_team_assignments({31: 1, 32: 1, 33: 2})
	var team_projectile := ProjectileState.create(3100, 31, 1, Vector2(500.0, 350.0), 0.0, team_shooter.stats)
	team_world.projectile_registry.add(team_projectile)
	team_world.step(0.2)
	context.expect_equal(team_ally.health, team_ally.stats.max_health, "team projectiles pass through allies without friendly-fire damage")
	context.expect_true(team_enemy.health < team_enemy.stats.max_health, "team projectiles continue on to damage opposing ships")
	var team_npc_controller := NpcPilotController.new()
	context.expect_equal(team_npc_controller._nearest_target(team_world, team_shooter, 4000.0).peer_id, 33, "NPC targeting ignores a nearer ally and selects an opposing pilot")
	context.expect_true(world.submit_input(2, PlayerInputFrame.new(4, 34, Vector2.ZERO, aim_to_second, false, false, true)), "authoritative world accepts manual reload input")
	world.step(1.0 / 60.0)
	context.expect_true(first.weapon.reloading, "authoritative manual reload starts before the magazine is empty")
	var snapshot := world.snapshot_states()
	context.expect_equal(snapshot.size(), 2, "authoritative snapshot contains every connected combatant")
	context.expect_true(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(world.server_tick, world.acknowledged_input(2), snapshot)).ok, "authoritative world snapshot survives wire encoding")
	first.health = 12.0
	second.health = 37.0
	var second_build_stats := StatSystem.derive({&"glass_reactor": 2}, CardCatalog.create_default())
	world.prepare_heat({2: first.stats, 3: second_build_stats}, {2: Vector2(300.0, 300.0), 3: Vector2(600.0, 300.0)})
	context.expect_equal(first.health, first.stats.max_health, "new heats refill human hull to its complete derived maximum")
	context.expect_equal(second.health, second.stats.max_health, "new heats refill NPC hull to its complete card-modified maximum")

	var contact_world := AuthoritativeWorld.new()
	var contact_left := contact_world.add_peer(40)
	var contact_right := contact_world.add_peer(41)
	contact_left.position = Vector2(1000.0, 1000.0)
	contact_right.position = Vector2(1000.0, 1000.0)
	contact_world.submit_input(40, PlayerInputFrame.new(1, 1, Vector2(0.0, -1.0), 0.0, true, true))
	contact_world.submit_input(41, PlayerInputFrame.new(1, 1, Vector2(0.0, -1.0), PI, true, false))
	for _tick in 30:
		contact_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_true(contact_left.position.distance_to(contact_right.position) >= GameConstants.SHIP_COLLISION_RADIUS * 2.0 - 0.01, "ramming ships remain physically separated while shielding and firing")
	context.expect_true(contact_left.velocity.length() > 1.0 or contact_right.velocity.length() > 1.0, "overlap recovery preserves separating motion instead of freezing both ships")

	var pinned_world := AuthoritativeWorld.new()
	var pinned_stats := CombatStats.create_base()
	pinned_stats.max_health = 600.0
	pinned_stats.projectile_damage = 1.0
	var pinned_left := pinned_world.add_peer(42, pinned_stats)
	var pinned_right := pinned_world.add_peer(43, pinned_stats)
	pinned_left.position = Vector2(GameConstants.SHIP_COLLISION_RADIUS, 900.0)
	pinned_right.position = Vector2(GameConstants.SHIP_COLLISION_RADIUS + 30.0, 900.0)
	var minimum_contact_distance := INF
	for contact_tick in 120:
		var left_shielding := contact_tick % 2 == 0
		pinned_world.submit_input(42, PlayerInputFrame.new(contact_tick + 1, contact_tick + 1, Vector2(0.0, -1.0), 0.0, not left_shielding, left_shielding))
		pinned_world.submit_input(43, PlayerInputFrame.new(contact_tick + 1, contact_tick + 1, Vector2(0.0, -1.0), PI, left_shielding, not left_shielding))
		pinned_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
		minimum_contact_distance = minf(minimum_contact_distance, pinned_left.position.distance_to(pinned_right.position))
	context.expect_true(minimum_contact_distance >= GameConstants.SHIP_COLLISION_RADIUS * 2.0 - 0.01, "wall-pinned shield/fire collisions transfer blocked correction and never leave ships interpenetrating (minimum %.3f)" % minimum_contact_distance)
	context.expect_true(pinned_right.position.x > GameConstants.SHIP_COLLISION_RADIUS + 30.0, "wall-pinned contact expels the movable ship instead of trapping the pair")
	var cover_world := AuthoritativeWorld.new()
	var cover_left := cover_world.add_peer(44, pinned_stats)
	var cover_right := cover_world.add_peer(45, pinned_stats)
	var cover_edge_x := ArenaLayout.center().x + ArenaLayout.CENTRAL_RADIUS + GameConstants.SHIP_COLLISION_RADIUS
	cover_left.position = Vector2(cover_edge_x, ArenaLayout.center().y)
	cover_right.position = Vector2(cover_edge_x + 30.0, ArenaLayout.center().y)
	cover_world.submit_input(44, PlayerInputFrame.new(1, 1, Vector2(0.0, -1.0), 0.0, false, true))
	cover_world.submit_input(45, PlayerInputFrame.new(1, 1, Vector2(0.0, -1.0), PI, true, false))
	cover_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_true(cover_left.position.distance_to(cover_right.position) >= GameConstants.SHIP_COLLISION_RADIUS * 2.0 - 0.01, "cover-pinned shield/fire collision transfers rejected correction to the free ship")
	context.expect_true(cover_right.position.x > cover_edge_x + 30.0, "cover-pinned contact ejects outward instead of retaining a sticky overlap")

	var cluster_world := AuthoritativeWorld.new()
	var cluster_ids: Array[int] = [46, 47, 48, 49]
	for cluster_id in cluster_ids:
		var cluster_ship := cluster_world.add_peer(cluster_id, pinned_stats)
		cluster_ship.position = Vector2(1000.0, 900.0)
	cluster_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	var cluster_separated := true
	for left_index in cluster_ids.size():
		for right_index in range(left_index + 1, cluster_ids.size()):
			var left_cluster_ship := cluster_world.combatants[cluster_ids[left_index]] as CombatantState
			var right_cluster_ship := cluster_world.combatants[cluster_ids[right_index]] as CombatantState
			if left_cluster_ship.position.distance_to(right_cluster_ship.position) < GameConstants.SHIP_COLLISION_RADIUS * 2.0 - 0.01:
				cluster_separated = false
	context.expect_true(cluster_separated, "authoritative fallback separation untangles a multi-ship contact cluster in one simulation tick")

	var ram_stats := StatSystem.derive({&"ramming_shields": 1}, CardCatalog.create_default())
	var ram_world := AuthoritativeWorld.new()
	var rammer := ram_world.add_peer(50, ram_stats)
	var ram_target := ram_world.add_peer(51)
	rammer.position = Vector2(900.0, 900.0)
	ram_target.position = Vector2(939.0, 900.0)
	rammer.velocity = Vector2(160.0, 0.0)
	ram_target.velocity = Vector2.ZERO
	ram_world.submit_input(50, PlayerInputFrame.new(1, 1, Vector2.ZERO, PI * 0.5, false, true))
	ram_world.submit_input(51, PlayerInputFrame.new(1, 1, Vector2.ZERO, PI, false, false))
	ram_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	var health_after_ram := ram_target.health
	context.expect_true(health_after_ram < ram_target.stats.max_health, "Ramming Shields deals authoritative melee damage at practical speed whenever the shield is up")
	rammer.position = Vector2(900.0, 900.0)
	ram_target.position = Vector2(939.0, 900.0)
	rammer.velocity = Vector2(160.0, 0.0)
	ram_world.submit_input(50, PlayerInputFrame.new(2, 2, Vector2.ZERO, PI * 0.5, false, true))
	ram_world.submit_input(51, PlayerInputFrame.new(2, 2, Vector2.ZERO, PI, false, false))
	ram_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_equal(ram_target.health, health_after_ram, "shield-ram contact cooldown prevents per-tick damage stacking")

	var blocked_world := AuthoritativeWorld.new()
	var blocked_shooter := blocked_world.add_peer(20)
	blocked_shooter.position = Vector2(GameConstants.SHIP_COLLISION_RADIUS, 500.0)
	blocked_world.submit_input(20, PlayerInputFrame.new(1, 1, Vector2.ZERO, PI, true))
	blocked_world.step(1.0 / 60.0)
	var blocked_batch := blocked_world.drain_projectile_batch()
	context.expect_empty(blocked_batch.spawned, "muzzle against boundary cannot create projectile beyond wall")
	context.expect_equal(blocked_world.projectile_registry.size(), 0, "blocked muzzle leaves no through-wall projectile")

	var scatter_stats := StatSystem.derive({&"scatter_array": 1}, CardCatalog.create_default())
	var scatter_world := AuthoritativeWorld.new()
	var scatter_shooter := scatter_world.add_peer(22, scatter_stats)
	scatter_shooter.position = Vector2(100.0, 900.0)
	scatter_world.submit_input(22, PlayerInputFrame.new(1, 1, Vector2.ZERO, PI, true))
	scatter_world.step(1.0 / 60.0)
	var scatter_spawn_batch := scatter_world.drain_projectile_batch()
	context.expect_equal(
		(scatter_spawn_batch.spawned as Array).size(),
		scatter_stats.projectile_count,
		"Scatter Array registers every authoritative projectile in one shot"
	)
	scatter_world.submit_input(22, PlayerInputFrame.new(2, 2, Vector2.ZERO, PI, false))
	for _tick in 10:
		scatter_world.step(1.0 / 60.0)
	var scatter_collision_batch := scatter_world.drain_projectile_batch()
	context.expect_equal(
		(scatter_collision_batch.removed as Array).size(),
		scatter_stats.projectile_count,
		"every authoritative Scatter Array projectile collides with the arena barrier"
	)
	context.expect_equal(
		scatter_world.projectile_registry.size(),
		0,
		"no authoritative multi-shot projectile survives beyond the barrier"
	)

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

	var rebound_damage_world := AuthoritativeWorld.new()
	var rebound_target := rebound_damage_world.add_peer(24)
	rebound_target.position = Vector2(55.0, 500.0)
	var rebound_stats := CombatStats.create_base()
	rebound_stats.projectile_speed = 3000.0
	rebound_stats.ricochet_count = 1
	var rebound_projectile := ProjectileState.create(2400, 23, 1, Vector2(20.0, 500.0), PI, rebound_stats)
	rebound_damage_world.projectile_registry.add(rebound_projectile)
	rebound_damage_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_true(rebound_target.health < rebound_target.stats.max_health, "a round damages an enemy reached by the unused movement remaining after its ricochet")

	var beam_rebound_stats := CombatStats.create_base()
	beam_rebound_stats.beam_weapon = true
	beam_rebound_stats.ricochet_count = 1
	var beam_rebound_world := AuthoritativeWorld.new()
	for beam_index in 3:
		var tangent_beam := ProjectileState.create(
			100 + beam_index,
			90,
			7,
			Vector2(1565.0, 1085.0 + float(beam_index) * 0.5),
			0.0,
			beam_rebound_stats
		)
		beam_rebound_world.projectile_registry.add(tangent_beam)
	beam_rebound_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_equal(beam_rebound_world.projectile_registry.size(), 3, "every near-tangent beam in a multi-shot volley survives its rebound")
	var all_beams_rebounded := true
	for tangent_beam in beam_rebound_world.active_projectiles():
		if tangent_beam.velocity.y <= 0.0 or tangent_beam.remaining_ricochets != 0:
			all_beams_rebounded = false
	context.expect_true(all_beams_rebounded, "swept authority independently rebounds every beam in the volley")


static func _validate_card_powerups(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	var system := CardPowerupSystemScript.new(catalog, 4242)
	var world := AuthoritativeWorld.new()
	var combatant := world.add_peer(2)
	combatant.position = Vector2(200.0, 200.0)
	var player := PlayerMatchState.new(2, "Collector", 1)
	var players := {2: player}
	system.begin_heat(100, &"prism_array", false)
	context.expect_empty(system.step(5000, world, players), "disabled random powerups never spawn")
	system.begin_heat(100, &"prism_array", true)
	context.expect_empty(system.step(1299, world, players), "first powerup waits for the full twenty-second interval")
	var spawn_events := system.step(1300, world, players)
	context.expect_equal(spawn_events.size(), 1, "enabled powerups spawn exactly once at the twenty-second boundary")
	if spawn_events.is_empty():
		return
	var spawned := (spawn_events[0] as Dictionary).payload as Dictionary
	var card := catalog.get_card(StringName(spawned.card_id))
	context.expect_true(card != null and card.rarity >= CardDefinition.Rarity.RARE, "arena powerups are always Rare or better")
	context.expect_false(ArenaLayout.overlaps_obstacle(spawned.position as Vector2, CardPowerupSystemScript.POWERUP_RADIUS, &"prism_array"), "powerups spawn clear of map obstacles")
	context.expect_equal(system.snapshot().size(), 1, "active powerup snapshot supports late-joining spectators")
	combatant.position = spawned.position
	var collection_events := system.step(1301, world, players)
	context.expect_equal(collection_events.size(), 1, "touching an authoritative powerup collects it")
	context.expect_equal(int(player.temporary_card_stacks.get(card.card_id, 0)), 1, "default arena powerup enters the player's heat-only inventory")
	context.expect_empty(system.snapshot(), "collected powerup is removed from authoritative map state")
	var permanent_system := CardPowerupSystemScript.new(catalog, 31337)
	permanent_system.begin_heat(200, &"prism_array", true, 5.0, true)
	context.expect_empty(permanent_system.step(499, world, players), "custom five-second drop interval waits until its exact boundary")
	var fast_spawn_events := permanent_system.step(500, world, players)
	context.expect_equal(fast_spawn_events.size(), 1, "custom drop interval drives authoritative spawn timing")
	if not fast_spawn_events.is_empty():
		var fast_spawn := (fast_spawn_events[0] as Dictionary).payload as Dictionary
		combatant.position = fast_spawn.position
		permanent_system.step(501, world, players)
		context.expect_equal(player.card_stack(StringName(fast_spawn.card_id)), 1, "permanent-drop option stores the pickup in the match-long inventory")
	var powerup_cloak := world.add_peer(3)
	CardPowerupSystemScript._apply_updated_stats(powerup_cloak, StatSystem.derive({&"cloak": 1}, catalog))
	context.expect_equal(powerup_cloak.cloak_charges_remaining, 1, "a mid-heat Cloak! pickup immediately grants its heat-scoped use")


static func _validate_new_card_mechanics(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	var afterburner_stats := StatSystem.derive({&"afterburner": 1}, catalog)
	context.expect_true(afterburner_stats.afterburner_enabled, "Afterburner card enables the authoritative special action")
	var boost_world := AuthoritativeWorld.new()
	var boosted := boost_world.add_peer(200, afterburner_stats)
	boosted.position = Vector2(400.0, 400.0)
	boost_world.submit_input(200, PlayerInputFrame.new(1, 1, Vector2.ZERO, 0.0, false, false, false, true))
	boost_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_true(boosted.velocity.x >= afterburner_stats.afterburner_impulse - 0.01, "Shift special applies an immediate forward Afterburner burst")
	context.expect_true(boosted.afterburner_remaining > 0.0, "Afterburner retains a short boosted acceleration window")
	var first_cooldown := boosted.afterburner_cooldown_remaining
	boost_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_true(boosted.afterburner_cooldown_remaining < first_cooldown, "holding the special input cannot reset the Afterburner cooldown")

	var mine_stats := StatSystem.derive({&"mine_layer": 1}, catalog)
	context.expect_true(mine_stats.mine_layer_enabled, "Star Mines enables the authoritative mine special")
	context.expect_equal(mine_stats.mine_capacity, 10, "one Star Mines card supplies ten mine charges per heat")
	var mine_world := AuthoritativeWorld.new()
	var layer := mine_world.add_peer(230, mine_stats)
	var mine_target := mine_world.add_peer(231)
	layer.position = Vector2(500.0, 500.0)
	mine_target.position = Vector2(620.0, 500.0)
	mine_world.submit_input(230, PlayerInputFrame.new(1, 1, Vector2.ZERO, 0.0, false, false, false, true))
	mine_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_equal(layer.mine_charges_remaining, 9, "placing a mine consumes exactly one of ten charges")
	context.expect_true(layer.mine_cooldown_remaining > 2.9, "placing a mine starts the three-second cooldown")
	context.expect_equal(mine_world.active_projectiles().size(), 1, "Shift places one persistent authoritative mine")
	var placed_mine := mine_world.active_projectiles()[0] as ProjectileState
	context.expect_false(placed_mine.is_mine_armed(), "a newly placed mine begins its quarter-second activation delay")
	mine_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_equal(mine_world.active_projectiles().size(), 1, "repeated special frames cannot bypass the mine cooldown")
	var two_stack_mines := StatSystem.derive({&"mine_layer": 2}, catalog)
	layer.reset_for_heat(two_stack_mines, Vector2(500.0, 500.0))
	context.expect_equal(layer.mine_charges_remaining, 20, "a new heat replenishes all ten mine charges per stack")
	layer.mine_charges_remaining = 7
	layer.alive = false
	context.expect_true(mine_world.respawn_peer(230, two_stack_mines, Vector2(500.0, 500.0)), "an eliminated mine layer can respawn in an objective heat")
	context.expect_equal(layer.mine_charges_remaining, 7, "an objective respawn does not replenish heat-scoped mine charges")
	mine_world.reset_match_inventories()
	layer.reset_for_heat(mine_stats, Vector2(500.0, 500.0))
	context.expect_equal(layer.mine_charges_remaining, 10, "a new match heat restores the first Star Mines stack to ten charges")

	var magnetic_world := AuthoritativeWorld.new()
	var magnetic_layer := magnetic_world.add_peer(235, mine_stats)
	var magnetic_target := magnetic_world.add_peer(236)
	magnetic_layer.position = Vector2(500.0, 500.0)
	magnetic_target.position = Vector2(750.0, 500.0)
	var magnetic_mine := ProjectileState.create_mine(905, 235, magnetic_layer.position)
	magnetic_mine.mine_activation_remaining = 0.0
	magnetic_world.projectile_registry.add(magnetic_mine)
	magnetic_world.step(0.5)
	context.expect_approx(magnetic_mine.position.x, 530.0, "an armed mine slowly drags toward a nearby enemy")
	context.expect_approx(magnetic_mine.position.y, 500.0, "magnetic mine travel follows the target direction")
	context.expect_approx(magnetic_mine.velocity.length(), GameConstants.MINE_MAGNETIC_SPEED, "magnetic mine travel uses the bounded pull speed")
	magnetic_target.position = Vector2(900.0, 500.0)
	for _tick in 6:
		magnetic_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_approx(magnetic_mine.position.x, 535.0, "a mine stops pulling after its next bounded target scan finds no nearby enemy")
	context.expect_true(magnetic_mine.velocity.is_zero_approx(), "a mine outside acquisition range stops drifting within one target-scan interval")

	var blast_world := AuthoritativeWorld.new()
	blast_world.add_peer(237, mine_stats).position = Vector2(300.0, 500.0)
	var blast_target := blast_world.add_peer(238)
	blast_target.position = Vector2(700.0, 500.0)
	var blast_mine := ProjectileState.create_mine(906, 237, Vector2(500.0, 500.0))
	blast_mine.mine_activation_remaining = 0.0
	blast_world.projectile_registry.add(blast_mine)
	var blast_trigger := ProjectileState.create(907, 238, 1, Vector2(475.0, 500.0), 0.0, CombatStats.create_base())
	blast_world.projectile_registry.add(blast_trigger)
	blast_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_approx(blast_target.health, 0.0, "the enlarged mine blast reaches a hull 200 pixels from its center")
	var proximity_world := AuthoritativeWorld.new()
	var proximity_layer := proximity_world.add_peer(240, mine_stats)
	var proximity_target := proximity_world.add_peer(241)
	proximity_layer.position = Vector2(700.0, 500.0)
	proximity_target.position = Vector2(950.0, 500.0)
	proximity_world.submit_input(240, PlayerInputFrame.new(1, 1, Vector2.ZERO, 0.0, false, false, false, true))
	proximity_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	proximity_target.position = Vector2(780.0, 500.0)
	proximity_world.submit_input(240, PlayerInputFrame.new(2, 2))
	proximity_world.step(0.20)
	context.expect_equal(proximity_world.active_projectiles().size(), 1, "enemy proximity cannot trigger a mine during its activation delay")
	context.expect_approx(proximity_target.health, 100.0, "an inactive mine cannot damage an enemy")
	proximity_world.step(0.05)
	proximity_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_empty(proximity_world.active_projectiles(), "an enemy entering the trigger radius detonates the mine")
	context.expect_approx(proximity_target.health, 0.0, "a mine deals 100 damage and eliminates a stock hull")

	var chain_world := AuthoritativeWorld.new()
	var chain_layer := chain_world.add_peer(242, mine_stats)
	chain_layer.position = Vector2(300.0, 300.0)
	var chain_target := chain_world.add_peer(243)
	chain_target.position = Vector2(950.0, 500.0)
	var chain_positions := [Vector2(500.0, 500.0), Vector2(650.0, 500.0), Vector2(800.0, 500.0)]
	for chain_index in chain_positions.size():
		var chain_mine := ProjectileState.create_mine(910 + chain_index, 242, chain_positions[chain_index])
		chain_mine.mine_activation_remaining = 0.0
		chain_world.projectile_registry.add(chain_mine)
	var inactive_chain_mine := ProjectileState.create_mine(914, 242, Vector2(950.0, 500.0))
	chain_world.projectile_registry.add(inactive_chain_mine)
	var chain_trigger := ProjectileState.create(913, 243, 1, Vector2(475.0, 500.0), 0.0, CombatStats.create_base())
	chain_world.projectile_registry.add(chain_trigger)
	chain_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_equal(chain_world.active_projectiles().size(), 1, "an armed mine blast recursively detonates other armed mines in range")
	context.expect_equal((chain_world.active_projectiles()[0] as ProjectileState).projectile_id, 914, "an inactive mine cannot join a chain reaction")
	context.expect_approx(chain_target.health, 0.0, "a chained mine blast applies its own 100 damage")

	var cloak_stats := StatSystem.derive({&"cloak": 1}, catalog)
	context.expect_true(cloak_stats.cloak_enabled, "Cloak! enables the authoritative special action")
	context.expect_equal(cloak_stats.cloak_capacity, 1, "each Cloak! card supplies one use per heat")
	var cloak_world := AuthoritativeWorld.new()
	var cloaked := cloak_world.add_peer(250, cloak_stats)
	cloak_world.submit_input(250, PlayerInputFrame.new(1, 1, Vector2.ZERO, 0.0, true, false, false, true))
	cloak_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_true(cloaked.is_cloaked(), "Shift activates five seconds of authoritative invisibility")
	context.expect_equal(cloaked.cloak_charges_remaining, 0, "activating Cloak! consumes exactly one card charge")
	context.expect_true(cloaked.cloak_remaining > 4.9, "Cloak! retains almost its full five-second duration after activation")
	context.expect_true(cloaked.cloak_cooldown_remaining > 19.9, "activating Cloak! starts its 20-second cooldown")
	context.expect_equal(cloaked.weapon.ammunition, cloak_stats.magazine_size, "a firing input cannot consume ammunition while cloaked")
	context.expect_false(cloaked.apply_damage(10.0), "nonlethal damage leaves the cloaked pilot alive")
	context.expect_false(cloaked.is_cloaked(), "taking positive damage immediately breaks invisibility")
	cloak_world.submit_input(250, PlayerInputFrame.new(2, 2))
	cloak_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	cloak_world.submit_input(250, PlayerInputFrame.new(3, 3, Vector2.ZERO, 0.0, false, false, false, true))
	cloak_world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
	context.expect_false(cloaked.is_cloaked(), "a spent Cloak! card cannot reactivate during the same heat")
	var two_cloak_stats := StatSystem.derive({&"cloak": 2}, catalog)
	cloaked.reset_for_heat(two_cloak_stats, Vector2(400.0, 400.0))
	context.expect_equal(cloaked.cloak_charges_remaining, 2, "a new heat restores one Cloak! use per stack")
	context.expect_approx(cloaked.cloak_cooldown_remaining, 0.0, "a new heat clears the Cloak! cooldown")
	context.expect_true(cloaked.activate_cloak(), "the first stacked Cloak! use activates immediately")
	cloaked.apply_damage(1.0)
	cloaked.release_special_activation()
	context.expect_false(cloaked.activate_cloak(), "a second stacked use cannot bypass the shared cooldown")
	cloaked.release_special_activation()
	cloaked.step(Vector2.ZERO, 0.0, false, GameConstants.CLOAK_COOLDOWN_SECONDS)
	context.expect_true(cloaked.activate_cloak(), "a stacked Cloak! use becomes available after 20 seconds")
	cloaked.reset_for_heat(two_cloak_stats, Vector2(400.0, 400.0))
	cloaked.activate_cloak()
	cloaked.apply_damage(1.0)
	cloaked.alive = false
	context.expect_true(cloak_world.respawn_peer(250, two_cloak_stats, Vector2(400.0, 400.0)), "an eliminated cloaked pilot can respawn in an objective heat")
	context.expect_equal(cloaked.cloak_charges_remaining, 1, "an objective respawn does not replenish heat-scoped Cloak! uses")
	context.expect_true(cloaked.cloak_cooldown_remaining > 19.9, "an objective respawn does not clear the Cloak! cooldown")

	var ramming_stats := StatSystem.derive({&"ramming_shields": 1}, catalog)
	context.expect_true(ramming_stats.shield_ram_damage >= 44.0, "Ramming Shields independently enables serious melee damage")

	var knockback_stats := StatSystem.derive({&"concussion_rounds": 1}, catalog)
	var hull_world := AuthoritativeWorld.new()
	hull_world.add_peer(210, knockback_stats)
	var hull_target := hull_world.add_peer(211)
	hull_target.position = Vector2(600.0, 400.0)
	var hull_projectile := ProjectileState.create(500, 210, 1, Vector2(500.0, 400.0), 0.0, knockback_stats)
	var hull_damage_events: Array[Dictionary] = []
	hull_projectile.position = Vector2(590.0, 400.0)
	hull_world._resolve_projectile_ship_hit(hull_projectile, 211, hull_damage_events)
	context.expect_approx(hull_target.velocity.x, knockback_stats.projectile_knockback, "unshielded projectile hit applies full knockback", 0.01)

	var nosferatu_stats := StatSystem.derive({&"nosferatu_shield": 1}, catalog)
	context.expect_approx(nosferatu_stats.shield_damage_heal_fraction, 0.25, "Nosferatu Shield heals 25% of blocked projectile damage", 0.001)
	var shield_world := AuthoritativeWorld.new()
	shield_world.add_peer(220, knockback_stats)
	var shield_target := shield_world.add_peer(221, nosferatu_stats)
	shield_target.position = Vector2(600.0, 400.0)
	shield_target.health = 50.0
	shield_target.aim_angle = PI
	shield_target.shield.active = true
	var shield_projectile := ProjectileState.create(501, 220, 1, Vector2(500.0, 400.0), 0.0, knockback_stats)
	var shield_damage_events: Array[Dictionary] = []
	shield_projectile.position = Vector2(590.0, 400.0)
	shield_world._resolve_projectile_ship_hit(shield_projectile, 221, shield_damage_events)
	context.expect_approx(shield_target.velocity.x, knockback_stats.projectile_knockback * 0.2, "shield block retains only a small fraction of projectile knockback", 0.01)
	context.expect_approx(shield_target.health, 50.0 + shield_projectile.damage * nosferatu_stats.shield_damage_heal_fraction, "Nosferatu Shield converts a percentage of blocked damage into hull health", 0.01)

	var rebound_stats := StatSystem.derive({&"rebound_shields": 1}, catalog)
	var rebound_world := AuthoritativeWorld.new()
	var rebound_source := rebound_world.add_peer(250)
	var rebound_target := rebound_world.add_peer(251, rebound_stats)
	rebound_source.position = Vector2(500.0, 400.0)
	rebound_source.health = 10.0
	rebound_target.position = Vector2(600.0, 400.0)
	rebound_target.aim_angle = PI
	rebound_target.shield.active = true
	var reflected := ProjectileState.create(503, 250, 1, Vector2(590.0, 400.0), 0.0, CombatStats.create_base())
	rebound_world.projectile_registry.add(reflected)
	var rebound_damage_events: Array[Dictionary] = []
	context.expect_true(rebound_world._resolve_projectile_ship_hit(reflected, 251, rebound_damage_events), "Rebound Shields preserve a blocked projectile")
	context.expect_true(reflected.has_rebounded and reflected.owner_id == 251, "blocked projectile becomes the shield owner's reflected shot")
	context.expect_approx(reflected.damage, 12.5, "authoritative rebound retains half damage")
	context.expect_approx(reflected.lifetime_remaining, GameConstants.PROJECTILE_LIFETIME_SECONDS * 0.5, "authoritative rebound retains half remaining range")
	context.expect_true(reflected.velocity.x < 0.0, "authoritative rebound aims at the original shooter")
	var rebound_batch := rebound_world.drain_projectile_batch()
	context.expect_equal((rebound_batch.spawned as Array).size(), 1, "rebound is sent immediately as an authoritative projectile update")
	rebound_world.step(0.2)
	var rebound_kills := rebound_world.drain_kill_events()
	context.expect_false(rebound_source.alive, "reflected projectile can damage its original shooter")
	context.expect_equal(rebound_kills.size(), 1, "lethal reflected projectile emits one kill")
	if not rebound_kills.is_empty():
		context.expect_equal(int(rebound_kills[0].killer_id), 251, "reflected kill is credited to the shield owner")
	var stacked_rebound_stats := StatSystem.derive({&"rebound_shields": 2}, catalog)
	var stacked_rebound_world := AuthoritativeWorld.new()
	var stacked_rebound_source := stacked_rebound_world.add_peer(252)
	var stacked_rebound_target := stacked_rebound_world.add_peer(253, stacked_rebound_stats)
	stacked_rebound_source.position = Vector2(500.0, 400.0)
	stacked_rebound_target.position = Vector2(600.0, 400.0)
	stacked_rebound_target.aim_angle = PI
	stacked_rebound_target.shield.active = true
	var stacked_reflection := ProjectileState.create(504, 252, 1, Vector2(590.0, 400.0), 0.0, CombatStats.create_base())
	stacked_rebound_world.projectile_registry.add(stacked_reflection)
	var stacked_rebound_events: Array[Dictionary] = []
	context.expect_true(stacked_rebound_world._resolve_projectile_ship_hit(stacked_reflection, 253, stacked_rebound_events), "stacked Rebound Shields preserve the reflected projectile")
	context.expect_approx(stacked_reflection.damage, 25.0 * 0.625, "a second Rebound Shields stack raises reflected damage")
	context.expect_approx(stacked_reflection.lifetime_remaining, GameConstants.PROJECTILE_LIFETIME_SECONDS * 0.625, "a second Rebound Shields stack raises reflected range")

	var lethal_world := AuthoritativeWorld.new()
	lethal_world.add_peer(230)
	var lethal_target := lethal_world.add_peer(231)
	lethal_target.position = Vector2(600.0, 400.0)
	lethal_target.health = 10.0
	var lethal_projectile := ProjectileState.create(502, 230, 1, Vector2(550.0, 400.0), 0.0, CombatStats.create_base())
	lethal_world.projectile_registry.add(lethal_projectile)
	lethal_world.step(0.05)
	var kill_events := lethal_world.drain_kill_events()
	context.expect_equal(kill_events.size(), 1, "authoritative lethal damage emits exactly one kill attribution")
	if not kill_events.is_empty():
		context.expect_equal(int(kill_events[0].killer_id), 230, "projectile kill is credited to its owning pilot")
	var match_scores := MatchScoreState.new()
	match_scores.register_player(230)
	match_scores.award_kill(230)
	match_scores.clear_heat_wins()
	context.expect_equal(int((match_scores.snapshot()[230] as Dictionary).kills), 1, "kill total persists when a heat score is reset")


static func _validate_connection_admission(context: TestContext) -> void:
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION + 1, "Pilot", 0, 32),
		NetworkProtocol.REJECT_VERSION_MISMATCH,
		"version-mismatched hello receives exact rejection code"
	)
	var challenge := "12".repeat(NetworkProtocol.AUTH_CHALLENGE_BYTES)
	var correct_proof := NetworkProtocol.lobby_password_proof(challenge, "correct")
	var wrong_proof := NetworkProtocol.lobby_password_proof(challenge, "wrong")
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "Pilot", 32, 32, correct_proof, correct_proof),
		NetworkProtocol.REJECT_SERVER_FULL,
		"full server hello receives exact rejection code"
	)
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "bad\nname", 0, 32, correct_proof, correct_proof),
		NetworkProtocol.REJECT_INVALID_NAME,
		"invalid-name hello receives exact rejection code"
	)
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "Pilot", 0, 32, correct_proof, correct_proof),
		&"",
		"valid hello passes admission validation"
	)
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "Pilot", 0, 32, wrong_proof, correct_proof),
		NetworkProtocol.REJECT_INVALID_PASSWORD,
		"incorrect lobby password is rejected before admission"
	)
	context.expect_equal(
		ConnectionAdmission.validate_hello(GameConstants.PROTOCOL_VERSION, "Pilot", 0, 32, correct_proof, correct_proof),
		&"",
		"matching lobby password passes admission"
	)
	var handshakes := HandshakeRegistry.new()
	handshakes.begin(9, 100.0, challenge)
	context.expect_true(handshakes.has(9), "new transport peer enters pending handshake registry")
	context.expect_equal(handshakes.challenge_for(9), challenge, "pending handshake retains its one-use authentication challenge")
	context.expect_empty(handshakes.expired(109.999), "handshake remains pending before ten-second deadline")
	context.expect_equal(handshakes.expired(110.0), [9], "handshake expires at ten-second deadline")
	context.expect_true(handshakes.complete(9), "completed handshake is removed")


static func _validate_reconnect_reset(context: TestContext) -> void:
	var bridge := NetworkBridge.new()
	bridge.role = NetworkBridge.Role.CLIENT
	bridge.local_peer_id = 99
	bridge.latest_lobby_state = {"revision": 500, "match_active": false}
	bridge.stop()
	context.expect_equal(bridge.role, NetworkBridge.Role.NONE, "disconnect marks transport inactive before teardown callbacks can re-enter")
	context.expect_equal(bridge.local_peer_id, 0, "disconnect clears the prior network peer identity")
	context.expect_empty(bridge.latest_lobby_state, "disconnect clears lobby revision state so a new server can start from revision one")
	bridge.free()
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
