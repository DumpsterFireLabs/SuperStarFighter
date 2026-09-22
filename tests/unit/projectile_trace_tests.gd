extends RefCounted

## Frozen pre-extraction tick traces exercise phase ordering, ownership,
## mines, missile interception, shields and ordinary/beam projectiles together.
static func trace(seed_value: int, map_id: StringName) -> String:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var world := AuthoritativeWorld.new()
    world.set_map_id(map_id)
    for peer in range(1, 9):
        var stats := CombatStats.create_base()
        stats.max_health = 600
        stats.projectile_count = 3
        stats.ricochet_count = 3
        stats.pierce_count = 2
        stats.mine_layer_enabled = true
        stats.missile_launcher_enabled = true
        stats.missile_capacity = 10
        stats.mine_capacity = 10
        stats.rebound_shield_enabled = peer % 2 == 0
        stats.beam_weapon = peer % 3 == 0
        var pilot := world.add_peer(peer, stats)
        pilot.position = Vector2(1000 + peer * 90, 800 + peer % 2 * 80)
        pilot.aim_angle = PI if peer % 2 else 0.0
        world._spawn_mine(pilot)
        world._spawn_missile(pilot)
    var hash_state := HashingContext.new()
    hash_state.start(HashingContext.HASH_SHA256)
    for tick in range(1, 181):
        for peer in range(1, 9):
            world.submit_input(peer, PlayerInputFrame.new(tick, tick, Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1), rng.randf_range(0, TAU), tick % 5 != 0, tick % 7 == 0))
        world.step(1.0 / 60.0)
        hash_state.update(PlayerSnapshotCodec.encode(world.server_tick, 0, world.snapshot_states()))
        for packet in ProjectilePacketCodec.encode_correction_chunks(tick, tick, world.active_projectiles(), true):
            hash_state.update(packet)
        var batch := world.drain_projectile_batch()
        hash_state.update(var_to_bytes(batch.removed))
        hash_state.update(var_to_bytes(world.drain_kill_events()))
    return hash_state.finish().hex_encode()


static func run(context: TestContext) -> void:
    var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/projectile_phase_traces.json"))
    for row: Dictionary in rows:
        context.expect_equal(trace(int(row.seed), StringName(row.map)), String(row.sha256), "projectile phase trace remains identical: %s/%d" % [row.map, row.seed])
