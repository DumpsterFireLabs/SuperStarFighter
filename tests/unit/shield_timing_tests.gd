extends RefCounted

class RecordingBridge extends NetworkBridge:
	var packets: Array[PackedByteArray] = []
	func send_input(frame: PlayerInputFrame) -> void:
		packets.append(InputPacketCodec.encode(frame))
	func send_action_input(frame: PlayerInputFrame) -> void:
		# These deterministic schedules intentionally impair even the edge copy;
		# the TCP integration fixture verifies real reliable delivery separately.
		packets.append(InputPacketCodec.encode(frame))


static func run(context: TestContext, parent: Node) -> void:
	_codec_and_authority(context)
	_pressure_and_replay(context)
	for profile in ["lan", "latency", "jitter", "loss", "reorder", "expired"]:
		for seed_value in [7, 29, 101]:
			_input_delivery(context, parent, profile, seed_value)


static func _frame(sequence: int, held: bool, press: int = -1) -> PlayerInputFrame:
	return PlayerInputFrame.new(sequence, sequence, Vector2.ZERO, 0.0, false, held, false, false, -1, -1, press)


static func _codec_and_authority(context: TestContext) -> void:
	for sequence in [10, 0, 0xffffffff]:
		var press: int = (sequence - 1) & 0xffffffff
		var decoded := InputPacketCodec.decode(InputPacketCodec.encode(_frame(sequence, false, press)))
		context.expect_true(decoded.ok and decoded.frame.shield_press_sequence == press, "released shield press survives codec and sequence wrap")
	for press in [11, (10 - GameConstants.SHIELD_PRESS_RETENTION_TICKS - 1) & 0xffffffff]:
		context.expect_false(InputPacketCodec.decode(InputPacketCodec.encode(_frame(10, true, press))).ok, "wire rejects future or expired shield press identity")
	var world := AuthoritativeWorld.new()
	var defender := world.add_peer(2)
	world.submit_input(2, _frame(1, true, 1))
	world.step(1.0 / 60.0)
	defender.shield.perfect_guard_window_remaining = 0.0
	world.submit_input(2, _frame(2, false, 1))
	world.submit_input(2, _frame(3, true, 3))
	world.step(1.0 / 60.0)
	context.expect_true(defender.shield.is_perfect_guard_active(), "coalesced release/repress opens a new guard window")
	defender.shield.try_block(0.0, Vector2.RIGHT, defender.stats)
	world.submit_input(2, _frame(4, true, 3))
	world.step(1.0 / 60.0)
	context.expect_false(defender.shield.is_perfect_guard_active(), "retransmission cannot renew a consumed Perfect Guard")
	context.expect_false(world.submit_input(2, _frame(2, false, 1)), "reordered old release cannot lower the current shield")
	defender.shield.depletion_locked = true
	defender.shield.active = false
	defender.shield.energy = 0.0
	world.submit_input(2, _frame(5, true, 5))
	world.step(1.0 / 60.0)
	context.expect_false(defender.shield.active, "fresh press cannot bypass depletion lock")
	var snapshot := PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(world.server_tick, 5, world.snapshot_states(), defender.prediction_state()))
	context.expect_equal(snapshot.local_state.last_shield_press_sequence, 5, "recipient correction acknowledges consumed shield identity")


static func _pressure_and_replay(context: TestContext) -> void:
	var stats := CombatStats.create_base()
	var timed := ShieldState.new()
	timed.reset(stats)
	timed.step(true, stats, 0.0)
	for tick in 14:
		timed.step(true, stats, 1.0 / 60.0)
	context.expect_true(timed.is_perfect_guard_active(), "guard remains available just before its deadline")
	timed.step(true, stats, 1.0 / 60.0)
	context.expect_false(timed.is_perfect_guard_active(), "guard closes at 250 ms without an extra floating-point tick")
	var correction := PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(2, 2, [], {"guard_window": 0.25 - 2.0 / 60.0}))
	timed.reset(stats)
	timed.active = true
	timed.perfect_guard_window_remaining = correction.local_state.guard_window
	for tick in 13:
		timed.step(true, stats, 1.0 / 60.0)
	context.expect_false(timed.is_perfect_guard_active(), "snapshot precision preserves the same 250 ms guard deadline in replay")
	var defender := CombatantState.create(2, stats, Vector2(500, 720))
	var prediction := ClientPredictionBuffer.new()
	var initial := defender.prediction_state()
	initial.position = defender.position
	prediction.reset_to_snapshot(initial, stats)
	for sequence in range(1, 20):
		var frame := _frame(sequence, sequence != 2, 3 if sequence >= 3 and sequence <= 18 else (1 if sequence < 3 else -1))
		defender.step_input(frame, 1.0 / 60.0)
		prediction.predict(frame, stats, 1.0 / 60.0)
		context.expect_approx(prediction.simulated_combatant.shield.energy, defender.shield.energy, "authority and replay use identical shield drain around transitions")
		context.expect_approx(prediction.simulated_combatant.shield.perfect_guard_window_remaining, defender.shield.perfect_guard_window_remaining, "authority and replay agree on the guard deadline")
	# A same-tick volley gets one discounted block, then normal costs.
	var world := AuthoritativeWorld.new()
	defender = world.add_peer(2, stats)
	defender.position = Vector2(500, 720)
	defender.step_input(_frame(30, true, 30), 0.0)
	var damages: Array[Dictionary] = []
	for index in 3:
		var shot := ProjectileState.create(index + 1, 1, index, defender.position + Vector2(20, 0), PI, stats)
		world.projectile_registry.add(shot)
		world._resolve_projectile_ship_hit(shot, 2, damages)
	context.expect_approx(defender.shield.energy, 45.0, "three simultaneous blocks cost 5 + 25 + 25 energy")
	context.expect_empty(damages, "all three covered impacts stop at the shield")
	context.expect_false(defender.shield.is_perfect_guard_active(), "multishot cannot reuse the first-hit discount")
	var state := defender.prediction_state()
	state.position = defender.position
	state.shield = defender.shield.energy
	prediction.reset_to_snapshot(state, stats)
	prediction.predict(_frame(31, true, 30), stats, 1.0 / 60.0)
	context.expect_false(prediction.simulated_combatant.shield.is_perfect_guard_active(), "snapshot replay cannot reopen a server-consumed guard")


static func _input_delivery(context: TestContext, parent: Node, profile: String, seed_value: int) -> void:
	var bridge := RecordingBridge.new()
	parent.add_child(bridge)
	var view := NetworkWorldFixture.new()
	parent.add_child(view)
	view.setup(bridge)
	view.set_network_active(true)
	view.set_physics_process(false)
	view.local_peer_id = 2
	view.controls_enabled = true
	var ship := CombatShipView.new()
	view.add_child(ship)
	ship.setup(2, CombatStats.create_base(), Vector2(500, 720), Color.WHITE, true)
	view.replicated_visuals.ships[2] = ship
	var initial := ship.combatant.prediction_state()
	initial.position = ship.global_position
	view.local_prediction.prediction.reset_to_snapshot(initial, ship.combatant.stats)
	view.local_prediction.prediction_initialized = true
	var world := AuthoritativeWorld.new()
	var defender := world.add_peer(2)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var queue: Array[Dictionary] = []
	var activation_ticks: Array[int] = []
	var was_active := false
	var local_immediate := false
	for tick in 75:
		if tick == 10:
			Input.action_press("shield")
		else:
			Input.action_release("shield")
		view.local_prediction.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
		if tick == 10:
			local_immediate = ship.combatant.shield.active and ship.combatant.shield.is_perfect_guard_active()
		for packet in bridge.packets:
			if (profile == "loss" and tick >= 10 and tick <= 15) or (profile == "expired" and tick >= 10 and tick <= 30):
				continue
			var delay := 1 if profile == "lan" else 6 if profile == "latency" else random.randi_range(1, 7) if profile in ["jitter", "reorder"] else 0
			queue.append({"due": tick + delay, "packet": packet})
			if profile == "reorder":
				queue.append({"due": tick + delay + 2, "packet": packet})
		bridge.packets.clear()
		for index in range(queue.size() - 1, -1, -1):
			if int(queue[index].due) <= tick:
				var decoded := InputPacketCodec.decode(queue[index].packet)
				world.submit_input(2, decoded.frame)
				queue.remove_at(index)
		world.step(1.0 / 60.0)
		if defender.shield.active and not was_active:
			activation_ticks.append(tick)
		was_active = defender.shield.active
	var label := "%s seed %d" % [profile, seed_value]
	context.expect_true(local_immediate, "local shield and guard highlight respond on sampled press: " + label)
	context.expect_equal(activation_ticks.size(), 0 if profile == "expired" else 1, "short tap is delivered once or expires after blackout: " + label)
	context.expect_false(defender.shield.active, "retained tap does not leave authority holding shield: " + label)
	if not activation_ticks.is_empty():
		context.expect_true(activation_ticks[0] <= 26, "tap recovery remains bounded in exercised network schedule: " + label)
	view.free()
	bridge.free()
