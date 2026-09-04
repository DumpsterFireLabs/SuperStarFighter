extends RefCounted


static func run(context: TestContext) -> void:
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
