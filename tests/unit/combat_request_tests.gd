extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_cloak_ambush(context)
	_rebound_radius(context)
	_missile_interception(context)
	_selection_events(context, parent)


static func _cloak_ambush(context: TestContext) -> void:
	var stats := StatSystem.derive({&"cloak": 1}, CardCatalog.create_default())
	var pilot := CombatantState.create(1, stats)
	var activation := PlayerInputFrame.new(1, 1, Vector2.ZERO, 0.0, true, false, false, true, 1, 3)
	context.expect_equal(pilot.step_input(activation, 1.0 / 60.0), CombatantState.ACTION_CLOAK, "cloak activation wins over simultaneous held fire")
	var firing := PlayerInputFrame.new(2, 2, Vector2.ZERO, 0.0, true)
	context.expect_equal(pilot.step_input(firing, 1.0 / 60.0), 0, "ambush reveals the pilot before shooting")
	context.expect_false(pilot.is_cloaked(), "fire cancels cloak without waiting five seconds")
	context.expect_equal(pilot.weapon.ammunition, stats.magazine_size, "decloaking does not spend ammunition")
	# The existing weapon timer transports the brief delay through correction.
	var packet := PlayerSnapshotCodec.encode(2, 2, [], pilot.prediction_state())
	var decoded := PlayerSnapshotCodec.decode(packet)
	var replay := CombatantState.create(1, stats)
	replay.restore_prediction_state(decoded.local_state, stats)
	context.expect_equal(replay.step_input(firing, 0.05), 0, "prediction correction retains the first half of the ambush delay")
	context.expect_equal(replay.step_input(firing, 0.05), CombatantState.ACTION_SHOT, "a revealed pilot fires after only 0.1 seconds")
	context.expect_equal(replay.weapon.ammunition, stats.magazine_size - 1, "ambush consumes exactly one shot")
	pilot.reset_for_heat(stats, Vector2.ZERO)
	pilot.activate_cloak()
	pilot.apply_damage(1.0)
	context.expect_true(pilot.try_fire(), "damage-induced decloak allows immediate retaliation")


static func _rebound_radius(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	var source := world.add_peer(1, StatSystem.derive({&"rebound_shields": 1}, CardCatalog.create_default()))
	source.position = Vector2(400, 300)
	var enemy := world.add_peer(2)
	enemy.position = Vector2(450, 300)
	var ally := world.add_peer(3)
	ally.position = Vector2(400, 350)
	var outside := world.add_peer(4)
	outside.position = Vector2(340, 300)
	world.set_team_assignments({1: 1, 2: 2, 3: 1, 4: 2})
	world.submit_input(1, PlayerInputFrame.new(1, 1, Vector2.ZERO, 0.0, false, true))
	for tick in 6:
		world.step(1.0 / 60.0)
	context.expect_approx(enemy.health, 98.0, "active rebound radius applies 20 damage per second")
	context.expect_approx(ally.health, 100.0, "rebound radius protects teammates")
	context.expect_approx(source.health, 100.0, "rebound radius never damages its owner")
	context.expect_approx(outside.health, 100.0, "rebound radius does not reach beyond the visible shield and target hull")
	world.submit_input(1, PlayerInputFrame.new(2, 7))
	world.step(0.1)
	context.expect_approx(enemy.health, 98.0, "releasing rebound shield stops contact damage")
	enemy.health = 0.1
	world.submit_input(1, PlayerInputFrame.new(3, 8, Vector2.ZERO, 0.0, false, true))
	world.step(1.0 / 60.0)
	context.expect_false(enemy.alive, "rebound radius can eliminate a low-health enemy")
	context.expect_equal(world.drain_kill_events(), [{"killer_id": 1, "target_id": 2}], "rebound radius credits its owner with the kill")
	var feedback := world.drain_combat_feedback()
	context.expect_equal(feedback[2].death.source, "rebound_shield", "rebound damage has a distinct death recap")
	enemy.reset_for_heat(CombatStats.create_base(), Vector2(450, 300))
	source.shield.energy = 0.0
	world.step(0.1)
	context.expect_approx(enemy.health, 100.0, "depleted rebound shields cannot deal contact damage")


static func _missile_interception(context: TestContext) -> void:
	for beam in [false, true]:
		for missile_first in [false, true]:
			var world := AuthoritativeWorld.new()
			var stats := CombatStats.create_base()
			stats.beam_weapon = beam
			var shot := ProjectileState.create(10, 1, 1, Vector2(350, 300), 0.0, stats)
			shot.velocity = Vector2(1000, 0)
			var missile := ProjectileState.create_missile(20, 2, Vector2(400, 250), PI / 2.0)
			missile.velocity = Vector2(0, 1000)
			world.projectile_registry.add(missile if missile_first else shot)
			world.projectile_registry.add(shot if missile_first else missile)
			world.step(0.1)
			context.expect_equal(world.projectile_registry.size(), 0, "crossing hostile shot destroys missile regardless of beam type or insertion order")
			var removed: Array = world.drain_projectile_batch().removed
			context.expect_true(10 in removed and 20 in removed, "missile interception replicates both removals")
	for owner in [1, 3]:
		var world := AuthoritativeWorld.new()
		world.set_team_assignments({1: 1, 3: 1})
		var shot := ProjectileState.create(10, 1, 1, Vector2(350, 300), 0.0, CombatStats.create_base())
		shot.velocity = Vector2(1000, 0)
		var missile := ProjectileState.create_missile(20, owner, Vector2(400, 250), PI / 2.0)
		missile.velocity = Vector2(0, 1000)
		world.projectile_registry.add(shot)
		world.projectile_registry.add(missile)
		world.step(0.1)
		context.expect_equal(world.projectile_registry.size(), 2, "friendly and own shots pass through missiles")
	var miss_world := AuthoritativeWorld.new()
	var miss_shot := ProjectileState.create(10, 1, 1, Vector2(350, 300), 0.0, CombatStats.create_base())
	miss_shot.velocity = Vector2(1000, 0)
	var late_missile := ProjectileState.create_missile(20, 2, Vector2(400, 210), PI / 2.0)
	late_missile.velocity = Vector2(0, 1000)
	miss_world.projectile_registry.add(miss_shot)
	miss_world.projectile_registry.add(late_missile)
	miss_world.step(0.1)
	context.expect_equal(miss_world.projectile_registry.size(), 2, "paths that cross at different times do not intercept")
	var cover_world := AuthoritativeWorld.new()
	cover_world.set_map_id(&"riftline")
	var covered := ProjectileState.create_missile(20, 2, Vector2(1700, 300), PI / 2.0)
	var blocked := ProjectileState.create(10, 1, 1, Vector2(1450, 300), 0.0, CombatStats.create_base())
	blocked.velocity = Vector2(3000, 0)
	covered.velocity = Vector2(0, 1)
	cover_world.projectile_registry.add(blocked)
	cover_world.projectile_registry.add(covered)
	cover_world.step(0.1)
	context.expect_true(cover_world.projectile_registry.get_projectile(20) != null, "cover blocks shots before they can intercept a missile")


static func _selection_events(context: TestContext, parent: Node) -> void:
	var profiles := InputProfileManager.new()
	profiles.apply_active_bindings()
	var view := NetworkWorldView.new()
	parent.add_child(view)
	view.set_network_active(true)
	view.set_physics_process(false)
	view.local_peer_id = 1
	view.controls_enabled = true
	var stats := StatSystem.derive({&"afterburner": 1, &"mine_layer": 1, &"hunter_missiles": 1}, CardCatalog.create_default())
	view.local_stats = stats
	var ship := CombatShipView.new()
	view.add_child(ship)
	ship.setup(1, stats, Vector2(400, 300), Color.WHITE, true)
	view.ships[1] = ship
	view.selected_special_slot = 0
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	view.get_viewport().push_input(event)
	event.pressed = false
	view.get_viewport().push_input(event)
	event.pressed = true
	view.get_viewport().push_input(event)
	context.expect_equal(view.selected_special_slot, 2, "two quick E taps select missiles before any physics tick")
	event.echo = true
	view.get_viewport().push_input(event)
	context.expect_equal(view.selected_special_slot, 2, "holding E does not repeatedly cycle abilities")
	event.echo = false
	event.pressed = false
	view.get_viewport().push_input(event)
	event.physical_keycode = KEY_Q
	event.pressed = true
	view.get_viewport().push_input(event)
	context.expect_equal(view.selected_special_slot, 1, "Q selects the previous special")
	view.controls_enabled = false
	view.match_payload = {"state_name": "COUNTDOWN"}
	view._input(event)
	context.expect_equal(view.selected_special_slot, 0, "countdown allows selecting the ability advertised in the HUD")
	view.input_blocked = true
	view._input(event)
	context.expect_equal(view.selected_special_slot, 0, "modal input blocking preserves ability selection")
	event.pressed = false
	view.get_viewport().push_input(event)
	view.free()
	profiles.free()
