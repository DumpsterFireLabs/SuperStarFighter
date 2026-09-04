extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_selection(context)
	_budgets(context)
	_mine_detonation_events(context)
	_ability_replay(context)
	_feedback_panel(context, parent)


static func _selection(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	var stats := StatSystem.derive({&"afterburner": 1, &"mine_layer": 1, &"hunter_missiles": 1, &"cloak": 1}, catalog)
	context.expect_equal(SpecialAbilitySelection.owned_slots(stats), [0, 1, 2, 3], "ability selector exposes all four owned actions")
	context.expect_equal(SpecialAbilitySelection.cycle(3, stats, 1), 0, "next ability wraps")
	context.expect_equal(SpecialAbilitySelection.cycle(0, stats, -1), 3, "previous ability wraps")
	context.expect_equal(SpecialAbilitySelection.ensure_owned(3, CombatStats.create_base()), -1, "removed ability clears selection")
	for slot in 4:
		var pilot := CombatantState.create(1, stats)
		var frame := PlayerInputFrame.new(1, 1, Vector2.ZERO, 0.0, false, false, false, true, 1, slot)
		var packet := InputPacketCodec.encode(frame)
		var decoded := InputPacketCodec.decode(packet)
		context.expect_true(decoded.ok, "selected ability packet decodes")
		context.expect_equal(decoded.frame.special_slot, slot, "ability identity survives wire encoding")
		var actions := pilot.step_input(decoded.frame, 1.0 / 60.0)
		var expected := [CombatantState.ACTION_BOOST, CombatantState.ACTION_MINE, CombatantState.ACTION_MISSILE, CombatantState.ACTION_CLOAK]
		context.expect_equal(actions, expected[slot], "one press activates only selected owned ability")
		context.expect_equal(pilot.mine_charges_remaining, stats.mine_capacity - (1 if slot == 1 else 0), "unselected mine charges remain intact")
		context.expect_equal(pilot.missile_charges_remaining, stats.missile_capacity - (1 if slot == 2 else 0), "unselected missile charges remain intact")
		context.expect_equal(pilot.cloak_charges_remaining, stats.cloak_capacity - (1 if slot == 3 else 0), "unselected cloak charges remain intact")
		frame.special_slot = (slot + 1) % 4
		context.expect_equal(pilot.step_input(frame, 0.01), 0, "retry with same action identity cannot spend another ability")
	var bad := InputPacketCodec.encode(PlayerInputFrame.new())
	bad[20] = 4
	context.expect_false(InputPacketCodec.decode(bad).ok, "invalid ability slot is rejected at network boundary")
	var base := CombatantState.create(2, CombatStats.create_base())
	context.expect_equal(base.step_input(PlayerInputFrame.new(1, 1, Vector2.ZERO, 0, false, false, false, true, 1, 3), 0.01), 0, "unowned explicit ability cannot activate or substitute another action")
	var profiles := InputProfileManager.new()
	context.expect_true(&"special_previous" in profiles.rebind_actions() and &"special_next" in profiles.rebind_actions(), "keyboard ability selection is remappable")
	profiles.set_scheme(InputProfileManager.Scheme.CONTROLLER, false)
	context.expect_true(&"special_previous" in profiles.rebind_actions() and &"special_next" in profiles.rebind_actions(), "controller ability selection is remappable")
	profiles.set_scheme(InputProfileManager.Scheme.KEYBOARD_MOUSE, false)
	profiles.free()


static func _budgets(context: TestContext) -> void:
	var registry := ProjectileRegistry.new()
	registry.maximum_per_owner = 4
	registry.maximum_global = 8
	registry.add(ProjectileState.create_mine(1, 1, Vector2.ZERO))
	for id in range(2, 6):
		registry.add(ProjectileState.create(id, 1, id, Vector2.ZERO, 0, CombatStats.create_base()))
	context.expect_true(registry.get_projectile(1) != null, "ordinary fire cannot evict deployed mine at owner budget")
	context.expect_true(registry.get_projectile(2) == null, "oldest moving projectile is evicted instead")
	context.expect_equal(registry.size(), 4, "mine reservation preserves existing total owner limit")
	var removed := registry.add(ProjectileState.create_mine(6, 1, Vector2.ZERO))
	context.expect_true(1 in removed, "excess deployed mine replaces oldest mine in reservation")
	context.expect_equal(registry.mine_count_for_owner(1), 1, "small owner budgets preserve a bounded mine reservation")
	for owner in range(2, 6):
		registry.add(ProjectileState.create_mine(10 + owner, owner, Vector2.ZERO))
	context.expect_equal(registry.mine_count(), 4, "global mine allocation remains bounded")
	for id in range(100, 700):
		registry.add(ProjectileState.create(id, 20 + id % 8, id, Vector2.ZERO, 0, CombatStats.create_base()))
	context.expect_equal(registry.mine_count(), 4, "global fire churn and queue compaction preserve deployed mines")
	context.expect_true(registry.size() <= 8, "mixed global ordnance stays inside hard total budget")
	context.expect_true(registry.budget_evictions > 0, "budget replacement is measured for feedback and profiling")
	context.expect_true(registry.budget_evictions_for_owner(1) > 0, "owner receives its own replacement feedback")
	registry.forget_owner_metrics(1)
	context.expect_equal(registry.budget_evictions_for_owner(1), 0, "disconnect clears owner metrics to bound reconnect history")
	var states: Array[Dictionary] = []
	for peer in 32:
		states.append({"peer_id": peer + 1})
	var packet := PlayerSnapshotCodec.encode(10, 1, states, {"peer_id": 1, "active_ordnance": 64, "active_mines": 16, "budget_evictions": 125})
	context.expect_true(packet.size() <= 1200, "32-player snapshot retains transport margin with private budget feedback")
	var decoded := PlayerSnapshotCodec.decode(packet)
	context.expect_equal(decoded.local_state.active_ordnance, 64, "owner ordnance usage round-trips")
	context.expect_equal(decoded.local_state.active_mines, 16, "owner mine usage round-trips")
	context.expect_equal(decoded.local_state.budget_evictions, 125, "owner replacement counter round-trips")


static func _mine_detonation_events(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	var mine := ProjectileState.create_mine(1, 1, Vector2(400, 400))
	world.projectile_registry.add(mine)
	var damage: Array[Dictionary] = []
	world._detonate_mine(mine, damage)
	context.expect_true(world.drain_mine_detonations().is_empty(), "unarmed mine cannot emit a detonation")
	mine.mine_activation_remaining = 0.0
	world._detonate_mine(mine, damage)
	var events := world.drain_mine_detonations()
	context.expect_equal(events.size(), 1, "actual armed mine detonation emits one presentation event")
	context.expect_equal(events[0].position, mine.position, "detonation event carries authoritative explosion position")
	world._detonate_mine(mine, damage)
	context.expect_true(world.drain_mine_detonations().is_empty(), "removed mine cannot emit a duplicate explosion")
	world.projectile_registry.maximum_per_owner = 4
	world.projectile_registry.add(ProjectileState.create_mine(2, 1, Vector2.ZERO))
	world.projectile_registry.add(ProjectileState.create_mine(3, 1, Vector2.ZERO))
	context.expect_true(world.projectile_registry.get_projectile(2) == null, "mine quota replacement retires old mine")
	context.expect_true(world.drain_mine_detonations().is_empty(), "quota replacement does not pretend a mine exploded")
	world.clear_projectiles()
	context.expect_true(world.drain_mine_detonations().is_empty(), "cleanup does not pretend mines exploded")


static func _ability_replay(context: TestContext) -> void:
	var stats := StatSystem.derive({&"mine_layer": 1, &"hunter_missiles": 1, &"cloak": 1}, CardCatalog.create_default())
	var world := AuthoritativeWorld.new()
	var pilot := world.add_peer(1, stats)
	pilot.position = Vector2(400, 400)
	var initial := world.snapshot_states()[0].duplicate()
	initial.merge(pilot.prediction_state(), true)
	var prediction := ClientPredictionBuffer.new()
	prediction.reset_to_snapshot(initial, stats)
	for slot in [1, 2, 3]:
		var frame := PlayerInputFrame.new(slot, slot, Vector2.ZERO, 0.0, false, false, false, true, slot, slot)
		prediction.predict(frame, stats, 1.0 / 60.0)
	prediction.reconcile(pilot.position, pilot.velocity, 0, stats, ArenaLayout.DEFAULT_MAP_ID, false, initial)
	context.expect_equal(prediction.simulated_combatant.mine_charges_remaining, stats.mine_capacity - 1, "unacknowledged ability replay preserves mine selection")
	context.expect_equal(prediction.simulated_combatant.missile_charges_remaining, stats.missile_capacity - 1, "unacknowledged ability replay preserves missile selection")
	context.expect_equal(prediction.simulated_combatant.cloak_charges_remaining, stats.cloak_capacity - 1, "unacknowledged ability replay preserves cloak selection")


static func _feedback_panel(context: TestContext, parent: Node) -> void:
	var panel := CombatFeedbackPanel.new()
	parent.add_child(panel)
	panel.reset_for_life(2)
	panel.apply_feedback({"hit_count": 2, "hit_damage": 40, "blocked_count": 1, "last_block_reason": "perfect_guard"}, 1)
	context.expect_true(panel.hit_label.text.contains("40"), "attacker sees actual confirmed hull damage")
	context.expect_true(panel.block_label.text.contains("PERFECT GUARD"), "blocked shot is distinct from a hit or miss")
	panel.apply_feedback({"death": {"killer_id": 2, "source": "missile", "damage": 30, "life_generation": 2}}, 1, {2: "Rival"})
	context.expect_true(panel.death_label.text.contains("Rival") and panel.death_label.text.contains("MISSILE"), "death panel identifies authoritative killer and weapon")
	panel.reset_for_life(3)
	panel.apply_feedback({"death": {"source": "overtime", "life_generation": 2}}, 1)
	context.expect_true(panel.death_label.text.is_empty(), "late death feedback from previous life cannot reappear after respawn")
	panel.apply_feedback({"death": {"source": "overtime", "life_generation": 4}}, 1)
	panel.reset_for_life(3)
	panel.reset_for_life(4)
	context.expect_true(panel.death_label.text.contains("OVERTIME"), "death arriving before its life snapshot remains visible")
	panel.clear_feedback(true)
	panel.reset_for_life(1)
	panel.apply_feedback({"death": {"source": "mine", "life_generation": 1}}, 1)
	context.expect_true(panel.death_label.text.contains("MINE"), "new session accepts restarted life generations")
	panel.clear_feedback()
	context.expect_false(panel.visible, "match reset clears combat feedback")
	parent.remove_child(panel)
	panel.free()
