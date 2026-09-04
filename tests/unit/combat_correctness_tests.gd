extends RefCounted

const DT: float = 1.0 / 60.0


static func run(context: TestContext) -> void:
	_cleanup(context)
	_cadence(context)
	_specials_and_timeout(context)
	_prediction(context)
	_local_snapshot(context)


static func _cleanup(context: TestContext) -> void:
	var registry := ProjectileRegistry.new()
	var stats := CombatStats.create_base()
	for id in [1, 2]:
		registry.add(ProjectileState.create(id, 1, id, Vector2(400, 400), 0.0, stats))
	registry.schedule_owner_cleanup(1)
	registry.transfer_owner(2, 2)
	registry.add(ProjectileState.create(3, 1, 3, Vector2(400, 400), 0.0, stats))
	var removed := registry.step_cleanup(GameConstants.DEAD_OWNER_PROJECTILE_LIFETIME)
	context.expect_equal(removed, [1], "death cleanup only removes captured projectiles still owned by the dead pilot")
	context.expect_true(registry.get_projectile(3) != null, "fresh respawn projectile survives an earlier cleanup timer")
	context.expect_true(registry.get_projectile(2) != null, "reflected projectile survives its former owner's cleanup")
	context.expect_equal(registry.count_for_owner(1), 1, "cleanup preserves fresh projectile owner tracking")
	registry.maximum_per_owner = 1
	registry.add(ProjectileState.create(4, 1, 4, Vector2(400, 400), 0.0, stats))
	context.expect_true(registry.get_projectile(3) == null, "owner cap still retires oldest fresh projectile after cleanup")


static func _cadence(context: TestContext) -> void:
	for rate in [15.0, 16.0, 19.0, 20.0]:
		var stats := CombatStats.create_base()
		stats.fire_rate = rate
		stats.magazine_size = 10000
		var weapon := WeaponState.new()
		weapon.reset(stats)
		var shots := 0
		for tick in 600:
			weapon.step(stats, DT)
			if weapon.try_fire(stats, false):
				shots += 1
		context.expect_true(absi(shots - roundi(rate * 10.0)) <= 1, "%.0f Hz weapon maintains its intended sustained cadence (%d shots / 10s)" % [rate, shots])
		weapon.step(stats, 10.0)
		weapon.step(stats, DT)
		context.expect_true(weapon.try_fire(stats, false), "idle weapon can fire immediately")
		context.expect_approx(weapon.cooldown_remaining, 1.0 / rate, "idle weapon gains no stored firing credit")
		context.expect_false(weapon.try_fire(stats, false), "idle weapon cannot emit an instantaneous catch-up shot")
		weapon.request_reload(stats)
		weapon.step(stats, stats.reload_duration + 1.0)
		weapon.try_fire(stats, false)
		context.expect_approx(weapon.cooldown_remaining, 1.0 / rate, "reload completion gains no stored firing credit")


static func _specials_and_timeout(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	stats.mine_layer_enabled = true
	stats.mine_capacity = 5
	var pilot := CombatantState.create(1, stats)
	for tick in 360:
		pilot.step_input(PlayerInputFrame.new(tick + 1, tick, Vector2.ZERO, 0.0, false, false, false, true, 1), DT)
	context.expect_equal(pilot.mine_charges_remaining, 4, "retransmitted special press cannot spend again after cooldown")
	pilot.step_input(PlayerInputFrame.new(361, 361, Vector2.ZERO, 0.0, false, false, false, true, 361), DT)
	context.expect_equal(pilot.mine_charges_remaining, 3, "a fresh special press spends one new charge")
	pilot.reset_for_heat(stats, Vector2.ZERO, false)
	pilot.step_input(PlayerInputFrame.new(362, 362, Vector2.ZERO, 0.0, false, false, false, true, 361), DT)
	context.expect_equal(pilot.mine_charges_remaining, 3, "respawn does not replay a prior life's special press")
	pilot.last_special_sequence = 0xffffffff
	pilot.step_input(PlayerInputFrame.new(363, 363, Vector2.ZERO, 0.0, false, false, false, true, 0), DT)
	context.expect_equal(pilot.mine_charges_remaining, 2, "special press identity supports uint32 wrap")
	var frame := PlayerInputFrame.new(400, 400, Vector2.ZERO, 0.0, false, false, false, true, 361)
	var decoded := InputPacketCodec.decode(InputPacketCodec.encode(frame))
	context.expect_equal((decoded.frame as PlayerInputFrame).special_sequence, 361, "input codec retains stable press identity separately from frame sequence")
	var world := AuthoritativeWorld.new()
	var human := world.add_peer(1)
	world.input_timeouts[1] = GameConstants.INPUT_STALE_SECONDS
	world.submit_input(1, PlayerInputFrame.new(1, 1, Vector2.UP, 0.0, true, true, false, true))
	for tick in 32:
		world.step(DT)
	var stale := world.latest_inputs[1] as PlayerInputFrame
	context.expect_true(stale.movement == Vector2.ZERO and not stale.firing and not stale.shielding and not stale.special_activated, "silent human connection neutralizes all held controls after timeout")
	context.expect_false(human.shield.active, "input timeout releases the shield")
	context.expect_equal(world.acknowledged_input(1), 1, "timeout preserves monotonic input acknowledgement")
	context.expect_true(world.submit_input(1, PlayerInputFrame.new(2, 2, Vector2.UP)), "fresh input resumes after timeout")
	world.step(DT)
	context.expect_equal((world.latest_inputs[1] as PlayerInputFrame).movement, Vector2.UP, "fresh movement is not immediately timed out")


static func _correction(world: AuthoritativeWorld, pilot: CombatantState, wire_roundtrip: bool = false) -> Dictionary:
	if wire_roundtrip:
		var decoded := PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(world.server_tick, world.acknowledged_input(pilot.peer_id), world.snapshot_states(), pilot.prediction_state()))
		var received := (decoded.states as Array)[0] as Dictionary
		received.merge(decoded.local_state, true)
		return received
	var state := world.snapshot_states()[0].duplicate()
	state.merge(pilot.prediction_state(), true)
	return state


static func _prediction(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	stats.afterburner_enabled = true
	stats.breakaway_thrusters_enabled = true
	stats.mine_layer_enabled = true
	stats.mine_capacity = 4
	stats.fire_rate = 19.0
	for delay in [0, 6, 12, 18]:
		var wire_roundtrip: bool = delay == 18
		var world := AuthoritativeWorld.new()
		var pilot := world.add_peer(1, stats)
		pilot.position = Vector2(400, 400)
		pilot.shield.energy = 0.1
		var prediction := ClientPredictionBuffer.new()
		prediction.reset_to_snapshot(_correction(world, pilot), stats)
		var snapshots: Array[Dictionary] = []
		var max_error := 0.0
		var maximum_speed := 0.0
		for tick in 90:
			var frame := PlayerInputFrame.new(tick + 1, tick + 1, Vector2.UP, 0.0, tick > 15, tick < 12, tick == 35, tick < 6, 1)
			world.submit_input(1, frame)
			world.step(DT)
			snapshots.append(_correction(world, pilot, wire_roundtrip))
			prediction.predict(frame, stats, DT)
			if tick >= delay and tick % 3 == 0:
				var authoritative := snapshots[tick - delay]
				prediction.reconcile(authoritative.position, authoritative.velocity, tick - delay + 1, stats, world.map_id, false, authoritative)
			max_error = maxf(max_error, prediction.predicted_position.distance_to(pilot.position))
			maximum_speed = maxf(maximum_speed, prediction.predicted_velocity.length())
		context.expect_true(max_error < (1.0 if wire_roundtrip else 0.01), "shared boost/shield/reload replay matches authority with %d delayed frames, wire=%s (error %.5f)" % [delay, wire_roundtrip, max_error])
		context.expect_true(maximum_speed > stats.max_speed, "prediction retains the Afterburner speed multiplier")
		context.expect_equal(prediction.simulated_combatant.weapon.shot_sequence, pilot.weapon.shot_sequence, "replay preserves shot sequence through a manual reload")
		context.expect_equal(prediction.simulated_combatant.mine_charges_remaining, pilot.mine_charges_remaining, "replay never double-spends a retransmitted special")
		context.expect_equal(prediction.simulated_combatant.shield.depletion_locked, pilot.shield.depletion_locked, "replay retains shield depletion and recovery state")
		pilot.alive = false
		world.respawn_peer(1, stats, Vector2(400, 400))
		prediction.reset_to_snapshot(_correction(world, pilot), stats)
		context.expect_empty(prediction.buffered_inputs, "new life clears old input replay")
		context.expect_equal(prediction.simulated_combatant.weapon.ammunition, stats.magazine_size, "new life restores a full local magazine")
		context.expect_false(prediction.simulated_combatant.weapon.reloading, "new life clears stale local reload")


static func _local_snapshot(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	for id in 32:
		world.add_peer(id + 1)
	var pilot := world.combatants[17] as CombatantState
	pilot.weapon.reloading = true
	pilot.weapon.reload_remaining = 0.431
	pilot.weapon.shot_sequence = 123
	pilot.weapon.cooldown_remaining = 0.0526
	pilot.last_special_sequence = 42
	pilot.afterburner_remaining = 0.271
	pilot.shield.depletion_locked = true
	var packet := PlayerSnapshotCodec.assemble(20, 10, PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view()), pilot.prediction_state())
	context.expect_true(packet.size() <= 1200, "32-player snapshot with recipient correction remains within 1200 bytes (%d)" % packet.size())
	var decoded := PlayerSnapshotCodec.decode(packet)
	context.expect_true(decoded.ok, "recipient correction snapshot decodes")
	var correction := decoded.local_state as Dictionary
	context.expect_equal(correction.peer_id, 17, "correction belongs only to the receiving pilot")
	context.expect_equal(correction.shot_sequence, 123, "snapshot retains authoritative shot sequence")
	context.expect_equal(correction.last_special_sequence, 42, "snapshot retains consumed special press identity")
	context.expect_true(correction.reloading and correction.shield_locked, "snapshot retains reload and depleted shield flags")
	context.expect_approx(correction.afterburner_remaining, 0.271, "snapshot retains boost duration")
	context.expect_approx(correction.weapon_cooldown, 0.0526, "snapshot preserves sub-millisecond weapon cadence")
	context.expect_approx(correction.reload_remaining, 0.431, "snapshot retains reload progress")
	context.expect_equal(correction.life_generation, pilot.life_generation, "snapshot retains life generation even if the death snapshot was lost")
	context.expect_false(PlayerSnapshotCodec.decode(packet.slice(0, packet.size() - 1)).ok, "truncated correction trailer is rejected")
	packet[packet.size() - PlayerSnapshotCodec.LOCAL_STATE_SIZE + 16] = 128
	context.expect_false(PlayerSnapshotCodec.decode(packet).ok, "unknown correction flags are rejected")
