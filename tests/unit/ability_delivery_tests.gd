extends RefCounted

class RecordingBridge extends NetworkBridge:
	var edges: Array[PackedByteArray] = []
	func send_input(_frame: PlayerInputFrame) -> void:
		pass # Model complete loss/throttling of ordinary samples.
	func send_action_input(frame: PlayerInputFrame) -> void:
		edges.append(InputPacketCodec.encode(frame))


static func run(context: TestContext, parent: Node) -> void:
	await _reliable_press_delivery(context, parent)
	await _movement_edge_delivery(context, parent)
	var owner := NetworkLocalPrediction.new()
	owner.special_activation_sequence = 120
	owner.special_activation_sends_remaining = 20
	owner.special_activation_slot = SpecialAbilitySelection.Slot.MINE
	owner._acknowledge_special_activation(-1)
	context.expect_equal(owner.special_activation_sends_remaining, 20, "missing ability consumption cannot acknowledge a lost press")
	owner._acknowledge_special_activation(119)
	context.expect_equal(owner.special_activation_sends_remaining, 20, "older ability consumption retains the pending press")
	owner._acknowledge_special_activation(120)
	context.expect_equal(owner.special_activation_sends_remaining, 0, "authority consumption stops retries immediately")
	owner.special_activation_sends_remaining = 20
	owner.special_activation_sequence = 0xffffffff
	owner._acknowledge_special_activation(0)
	context.expect_equal(owner.special_activation_sends_remaining, 0, "ability consumption acknowledgement handles sequence wrap")
	owner.special_activation_sends_remaining = 20
	owner.special_activation_deadline_msec = 5000
	owner._expire_special_activation(4999)
	context.expect_equal(owner.special_activation_sends_remaining, 20, "pending ability remains within its bounded retry window")
	owner._expire_special_activation(5000)
	context.expect_equal(owner.special_activation_sends_remaining, 0, "lost ability expires instead of activating after a long outage")
	owner.special_activation_sends_remaining = 20
	owner.reset_for_countdown()
	context.expect_equal(owner.special_activation_sends_remaining, 0, "a new heat cancels old ability delivery")
	var stats := CombatStats.create_base()
	stats.mine_layer_enabled = true
	stats.mine_capacity = 3
	stats.missile_launcher_enabled = true
	stats.missile_capacity = 3
	var pilot := CombatantState.create(1, stats)
	var mines := 0
	for sequence in range(1, 76):
		var slot := SpecialAbilitySelection.Slot.MINE if sequence == 1 else SpecialAbilitySelection.Slot.MISSILE
		var frame := PlayerInputFrame.new(sequence, sequence, Vector2.ZERO, 0, false, false, false, true, 1, slot)
		if pilot.step_input(frame, 1.0 / 60.0) & CombatantState.ACTION_MINE: mines += 1
	context.expect_equal(mines, 1, "extended same-identity retries activate one mine")
	context.expect_equal(pilot.mine_charges_remaining, 2, "extended retries spend one charge even after cooldown expires")
	context.expect_equal(pilot.missile_charges_remaining, 3, "changing selected slot cannot repurpose a retried press")


static func _reliable_press_delivery(context: TestContext, parent: Node) -> void:
	for action in ["special_previous", "special_next"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for slot in range(4):
		await parent.get_tree().process_frame
		await parent.get_tree().process_frame
		var bridge := RecordingBridge.new()
		parent.add_child(bridge)
		var view := NetworkWorldFixture.new()
		parent.add_child(view)
		view.setup(bridge)
		view.set_network_active(true)
		view.set_physics_process(false)
		view.local_peer_id = 2
		view.controls_enabled = true
		var stats := CombatStats.create_base()
		stats.afterburner_enabled = true
		stats.mine_layer_enabled = true
		stats.mine_capacity = 3
		stats.missile_launcher_enabled = true
		stats.missile_capacity = 3
		stats.cloak_enabled = true
		stats.cloak_capacity = 3
		var ship := CombatShipView.new()
		view.add_child(ship)
		ship.setup(2, stats, Vector2(500, 720), Color.WHITE, true)
		view.replicated_visuals.ships[2] = ship
		view.local_prediction.local_stats = stats
		var correction := ship.combatant.prediction_state()
		correction.merge({"mine_charges": 3, "missile_charges": 3, "cloak_charges": 3})
		view.local_prediction.prediction.reset_to_snapshot(correction, stats)
		view.local_prediction.prediction_initialized = true
		view.local_prediction._sync_predicted_resources(ship)
		view.local_prediction.selected_special_slot = slot
		view.local_prediction.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
		view.local_prediction.input_send_accumulator = 0.0
		Input.action_press("special")
		# Exercise standalone ability presses as well as a simultaneous edge;
		# shield reliability must not accidentally hide an ability regression.
		if slot == SpecialAbilitySelection.Slot.CLOAK: Input.action_press("shield")
		view.local_prediction.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
		Input.action_release("special")
		Input.action_release("shield")
		context.expect_equal(bridge.edges.size(), 1, "standalone or combined ability edge sends one immediate reliable frame")
		if not bridge.edges.is_empty():
			var decoded := InputPacketCodec.decode(bridge.edges[0])
			context.expect_true(decoded.ok and decoded.frame.special_activated and decoded.frame.special_slot == slot, "selected ability survives reliable edge codec")
			var pilot := CombatantState.create(2, stats)
			var expected: int = [CombatantState.ACTION_BOOST, CombatantState.ACTION_MINE, CombatantState.ACTION_MISSILE, CombatantState.ACTION_CLOAK][slot]
			context.expect_true(bool(pilot.step_input(decoded.frame, 1.0 / 60.0) & expected), "ability activates despite all ordinary packets being lost")
			context.expect_equal(pilot.step_input(decoded.frame, 1.0 / 60.0) & expected, 0, "duplicate reliable activation cannot spend another charge")
		view.free()
		bridge.free()


static func _movement_edge_delivery(context: TestContext, parent: Node) -> void:
	await parent.get_tree().process_frame
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
	var owner := view.local_prediction
	Input.action_press("move_right")
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	context.expect_equal(bridge.edges.size(), 1, "thrust begins reliably when ordinary input is lost")
	for index in 12:
		owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	Input.action_press("move_up")
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	context.expect_equal(bridge.edges.size(), 1, "held thrust and direction changes do not flood reliable input")
	Input.action_release("move_right")
	Input.action_release("move_up")
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	context.expect_equal(bridge.edges.size(), 2, "thrust release bypasses ordinary packet loss")
	var world := AuthoritativeWorld.new()
	world.add_peer(2)
	var start := InputPacketCodec.decode(bridge.edges[0]).frame as PlayerInputFrame
	var stop := InputPacketCodec.decode(bridge.edges[1]).frame as PlayerInputFrame
	context.expect_true(world.submit_input(2, start), "authority accepts the reliable movement start")
	context.expect_true(world.submit_input(2, stop), "authority accepts the reliable movement stop")
	context.expect_true((world.latest_inputs[2] as PlayerInputFrame).movement.is_zero_approx(), "authority stops holding thrust despite all ordinary samples being lost")
	context.expect_false(world.submit_input(2, start), "delayed reliable start cannot override a newer stop")
	Input.action_press("move_right")
	Input.action_press("shield")
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	context.expect_equal(bridge.edges.size(), 3, "simultaneous shield and thrust start share one reliable frame")
	context.expect_true(InputPacketCodec.decode(bridge.edges[2]).frame.shielding, "coalescing thrust preserves shield protection")
	Input.action_release("shield")
	owner.input_blocked = true
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	context.expect_true(InputPacketCodec.decode(bridge.edges.back()).frame.movement.is_zero_approx(), "opening an input-blocking screen reliably releases thrust")
	owner.input_blocked = false
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	ship.combatant.alive = false
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	context.expect_true(InputPacketCodec.decode(bridge.edges.back()).frame.movement.is_zero_approx(), "death releases thrust even while the movement key remains held")
	ship.combatant.alive = true
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	owner.reset_for_countdown()
	var before_reset := bridge.edges.size()
	owner.step(1.0 / 60.0, ship, view.hud_camera._unshaken_mouse_world_position())
	context.expect_equal(bridge.edges.size(), before_reset + 1, "a new heat sends held thrust as a fresh start")
	Input.action_release("move_right")
	view.free()
	bridge.free()
