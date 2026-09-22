extends RefCounted

const DT: float = 1.0 / 60.0


static func run(context: TestContext) -> void:
	for delay in [0, 6, 12]:
		_held_input_replay(context, delay)
	var prediction := ClientPredictionBuffer.new()
	var stats := CombatStats.create_base()
	prediction.predicted_position = Vector2(100, 400)
	prediction.reconcile(Vector2(90, 400), Vector2.ZERO, 0, stats)
	var displayed := prediction.visual_position(0.05)
	prediction.reconcile(Vector2(85, 400), Vector2.ZERO, 0, stats)
	context.expect_equal(prediction.visual_position(0), displayed, "overlapping corrections preserve the displayed position")
	context.expect_equal(prediction.visual_position(0.1), Vector2(85, 400), "overlapping smoothing still converges to authority")
	for age in [-5, 0, 1, 65535, 70000]:
		var packet := PlayerSnapshotCodec.encode(1, 1, [], {"input_age_ticks": age})
		var decoded := PlayerSnapshotCodec.decode(packet)
		context.expect_true(decoded.ok, "input age correction decodes")
		context.expect_equal(decoded.local_state.input_age_ticks, clampi(age, 0, 65535), "input age has a bounded integer wire representation")
		packet[0] = NetworkProtocol.PACKET_VERSION - 1
		context.expect_false(PlayerSnapshotCodec.decode(packet).ok, "previous packet version cannot silently omit replay age")


static func _held_input_replay(context: TestContext, delay: int) -> void:
	var stats := CombatStats.create_base()
	stats.afterburner_enabled = true
	var world := AuthoritativeWorld.new()
	var pilot := world.add_peer(1, stats)
	pilot.position = Vector2(400, 400)
	world.input_timeouts[1] = 10.0
	var lobby := ServerLobby.new()
	lobby.admit(1, "ReplayPilot")
	var scheduler := NetworkReplicationScheduler.new()
	var received: Array[Dictionary] = []
	scheduler.player_snapshot_ready.connect(func(_peer_id: int, packet: PackedByteArray) -> void:
		var decoded := PlayerSnapshotCodec.decode(packet)
		var correction: Dictionary = decoded.states[0].duplicate()
		correction.merge(decoded.local_state, true)
		received.append({"ack": decoded.acknowledged_input, "state": correction})
	)
	var prediction := ClientPredictionBuffer.new()
	var initial: Dictionary = world.snapshot_states()[0].duplicate()
	initial.merge(pilot.prediction_state(), true)
	prediction.reset_to_snapshot(initial, stats)
	var maximum_error := 0.0
	for tick in range(1, 91):
		var frame := PlayerInputFrame.new(tick, tick, Vector2.UP if tick < 45 else Vector2.ZERO, 0, false, tick < 45, false, tick < 45, 1, SpecialAbilitySelection.Slot.AFTERBURNER, 1 if tick <= 12 else -1)
		# Authority extrapolates one held sample while newer samples are lost.
		# Delivery resumes with a stop at tick 45; later held neutral frames
		# likewise keep one acknowledgement while server time advances.
		if tick in [1, 45]: world.submit_input(1, frame)
		world.step(DT, true)
		scheduler._send_player_snapshots(lobby, world)
		prediction.predict(frame, stats, DT, world.map_id)
		if tick > delay:
			var snapshot := received[tick - delay - 1]
			var correction := snapshot.state as Dictionary
			context.expect_equal(correction.input_age_ticks, tick - delay if tick - delay < 45 else tick - delay - 44, "recipient trailer carries authoritative elapsed input ticks")
			prediction.reconcile(correction.position, correction.velocity, snapshot.ack, stats, world.map_id, false, correction)
			maximum_error = maxf(maximum_error, prediction.predicted_position.distance_to(pilot.position))
			context.expect_true(absf(prediction.simulated_combatant.shield.energy - pilot.shield.energy) < 0.02, "stalled acknowledgements do not double-drain shield energy")
			context.expect_true(absf(prediction.simulated_combatant.shield.perfect_guard_window_remaining - pilot.shield.perfect_guard_window_remaining) < 0.00002, "replay age preserves the exact Perfect Guard clock")
	# The wire quantizes position, velocity and boost timers; a timer landing
	# across a tick boundary can contribute a small additional motion error.
	context.expect_true(maximum_error < 3.0, "held-input wire replay counts authoritative time once with %d delayed ticks (%.3f px)" % [delay, maximum_error])
	context.expect_equal(prediction.snap_count, 0, "held input does not produce avoidable hard corrections")
	context.expect_equal(prediction.buffered_inputs.size(), 90 - (45 if delay < 45 else 1), "time coverage does not falsely acknowledge buffered input identities")
