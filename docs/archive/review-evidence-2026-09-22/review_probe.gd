extends SceneTree

## Read-only review probes. No application settings or gameplay source are changed.
const AudioDirectorScript = preload("res://src/client/presentation/audio_director.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var report := {}
	var bridge := NetworkBridge.new()
	root.add_child(bridge)
	var view := NetworkWorldView.new()
	root.add_child(view)
	view.setup(bridge)
	view.set_physics_process(false)
	view.local_peer_id = 1
	view.input_blocked = true
	view.apply_match_state({"state_name": "ACTIVE_HEAT", "game_mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG, "teams": {1: 1, 2: 2}, "competitive_view": true})
	var world := AuthoritativeWorld.new()
	var pilot := world.add_peer(1)
	var remote := world.add_peer(2)
	pilot.position = Vector2(300, 300)
	remote.position = Vector2(500, 300)
	_snapshot(view, world, 300)
	remote.alive = false
	remote.health = 0
	for tick in [591, 594, 597, 600]:
		_snapshot(view, world, tick)
	world.respawn_peer(2, remote.stats, Vector2(2500, 1300))
	_snapshot(view, world, 603)
	view.replicated_visuals._update_remote_ships()
	var shown := (view.replicated_visuals.ships[2] as CombatShipView).global_position
	report.remote_respawn = {"authoritative": str(remote.position), "displayed_immediately": str(shown), "error_pixels": shown.distance_to(remote.position), "alive": (view.replicated_visuals.ships[2] as CombatShipView).combatant.alive}
	pilot.alive = false
	pilot.health = 0
	_snapshot(view, world, 606)
	report.competitive_spectator = {"local_team": 1, "enemy_team": 2, "targets": view.hud_camera._living_spectator_targets()}
	view.free()
	bridge.free()

	var catalog := CardCatalog.create_default()
	var target_stats := StatSystem.derive({&"impossible_engine": 3}, catalog)
	var target := CombatantState.create(3, target_stats, Vector2(1000, 700))
	target.velocity = Vector2(target_stats.max_speed, 0)
	var bullet_stats := CombatStats.create_base()
	bullet_stats.projectile_knockback = 1800.0
	var bullet := ProjectileState.create(1, 4, 1, Vector2(900, 700), 0, bullet_stats)
	world._apply_projectile_knockback(target, bullet, 1.0)
	world._apply_projectile_knockback(target, bullet, 1.0)
	var body := PlayerSnapshotCodec.encode_combatant_body({3: target}, [3])
	var decoded := PlayerSnapshotCodec.decode(PlayerSnapshotCodec.assemble(610, 0, body, target.prediction_state()))
	report.velocity_round_trip = {"speed_stat": target.stats.max_speed, "authoritative_velocity": str(target.velocity), "decoded_velocity": str(decoded.states[0].velocity), "error_pixels_per_second": target.velocity.distance_to(decoded.states[0].velocity)}

	var projectiles: Array[ProjectileState] = []
	for index in 1024:
		projectiles.append(ProjectileState.create(index + 1, index % 32 + 1, index, Vector2(500, 500), 0, CombatStats.create_base()))
	var packets := ProjectilePacketCodec.encode_correction_chunks(600, 10, projectiles, true)
	var assembler := ProjectileCorrectionAssembler.new()
	var published := 0
	var bytes := 0
	for index in packets.size():
		bytes += packets[index].size()
		if index == 13: continue
		if not assembler.accept(ProjectilePacketCodec.decode_batch(packets[index])).is_empty(): published += 1
	report.full_recovery_loss = {"projectiles": projectiles.size(), "chunks": packets.size(), "payload_bytes_per_recipient": bytes, "dropped_chunks": 1, "published_recoveries": published, "independent_8_percent_chunk_loss_success_probability": pow(0.92, packets.size()), "independent_12_percent_chunk_loss_success_probability": pow(0.88, packets.size())}

	var audio := AudioDirectorScript.new()
	var cold: Array[int] = []
	var warm: Array[int] = []
	for family in [WeaponSoundProfile.FAMILY_STANDARD, WeaponSoundProfile.FAMILY_AUTOMATIC, WeaponSoundProfile.FAMILY_HEAVY, WeaponSoundProfile.FAMILY_RAIL, WeaponSoundProfile.FAMILY_SCATTER, WeaponSoundProfile.FAMILY_BEAM_PULSE, WeaponSoundProfile.FAMILY_BEAM_REPEATER, WeaponSoundProfile.FAMILY_BEAM_LANCE]:
		var profile := WeaponSoundProfile.new()
		profile.family = family
		profile.power_tier = 3
		for variant in 3:
			var started := Time.get_ticks_usec()
			audio._weapon_stream(profile, variant)
			cold.append(Time.get_ticks_usec() - started)
			started = Time.get_ticks_usec()
			audio._weapon_stream(profile, variant)
			warm.append(Time.get_ticks_usec() - started)
	cold.sort()
	warm.sort()
	report.weapon_audio_cache = {"samples": cold.size(), "cold_p50_usec": NetworkBridge.percentile_usec(cold, 0.5), "cold_p95_usec": NetworkBridge.percentile_usec(cold, 0.95), "cold_max_usec": cold.back(), "warm_p95_usec": NetworkBridge.percentile_usec(warm, 0.95), "cache_entries": audio.weapon_stream_cache.size()}
	audio.free()

	var starts: Array[int] = []
	for iteration in 8:
		var lobby := ServerLobby.new()
		var draft_world := AuthoritativeWorld.new()
		for peer in range(1, 33):
			lobby.admit(peer, "Review%d" % peer)
			draft_world.add_peer(peer)
		var coordinator := AuthoritativeMatchCoordinator.new(lobby, draft_world, 7390 + iteration)
		var started := Time.get_ticks_usec()
		coordinator.start(0)
		starts.append(Time.get_ticks_usec() - started)
	starts.sort()
	report.draft_start = {"players": 32, "samples": starts.size(), "p50_usec": NetworkBridge.percentile_usec(starts, 0.5), "max_usec": starts.back(), "scope": "coordinator.start only, empty human builds; constructor, transport, client UI excluded"}
	print("SSF_REVIEW_PROBES=" + JSON.stringify(report))
	quit(0)

func _snapshot(view: NetworkWorldView, world: AuthoritativeWorld, tick: int) -> void:
	var pilot := world.combatants[1] as CombatantState
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(tick, 0, world.snapshot_states(), pilot.prediction_state())))
