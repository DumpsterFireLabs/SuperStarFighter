extends RefCounted

const DT: float = 1.0 / 60.0
const ProjectileSimulation = preload("res://src/shared/combat/projectile_simulation.gd")


static func run(context: TestContext) -> void:
	_card_and_inventory(context)
	_deploy_and_follow(context)
	_firing_and_cloak(context)
	_drones_are_destructible(context)
	_owner_fire_never_evicts_drones(context)
	_retirement(context)
	_replication(context)
	_mine_blasts(context)


## End-to-end: authority → real codecs → bridge → an opponent's client view.
static func run_network(context: TestContext, parent: Node) -> void:
	var bridge := NetworkBridge.new()
	parent.add_child(bridge)
	var view := NetworkWorldFixture.new()
	parent.add_child(view)
	view.setup(bridge)
	view.set_physics_process(false)
	view.local_peer_id = 2
	var cues: Array[StringName] = []
	view.presentation_event.connect(func(event_name: StringName, _payload: Dictionary) -> void:
		if event_name == &"drone_deploy":
			cues.append(event_name))
	var world := _drone_world()
	var enemy := world.add_peer(2)
	enemy.position = Vector2(1500, 1500)
	var scheduler := NetworkReplicationScheduler.new()
	var sequence := [0]
	var state := {"input": 1}
	var tick_once := func(movement: Vector2, deploy: bool = false) -> void:
		state.input += 1
		world.submit_input(1, PlayerInputFrame.new(state.input, state.input, movement, 0.4, false, false, false, deploy, state.input, SpecialAbilitySelection.Slot.DRONE if deploy else -1))
		world.step(DT)
		var batch := world.drain_projectile_batch()
		sequence[0] += 1
		for packet in ProjectilePacketCodec.encode_batch_chunks(world.server_tick, sequence[0], batch.spawned as Array[ProjectileState], batch.removed as Array[int]):
			bridge.client_projectile_batch_received.emit(ProjectilePacketCodec.decode_batch(packet))
		if world.server_tick % 6 == 0:
			sequence[0] += 1
			for packet in ProjectilePacketCodec.encode_correction_chunks(world.server_tick, sequence[0], scheduler._projectiles_for_correction(world, false), false):
				bridge.client_projectile_correction_received.emit(ProjectilePacketCodec.decode_correction(packet))
		if world.server_tick % 3 == 0 or not view.replicated_visuals.ships.has(1):
			var body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view(), 2)
			bridge.client_snapshot_received.emit(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.assemble(world.server_tick, 0, body, (world.combatants[2] as CombatantState).prediction_state())))
		# Stand in for perfect remote interpolation so only drone replication is measured.
		var owner_view := view.replicated_visuals.ships.get(1) as CombatShipView
		var owner := world.combatants[1] as CombatantState
		if owner_view != null:
			owner_view.combatant.position = owner.position
			owner_view.combatant.velocity = owner.velocity
			owner_view.combatant.aim_angle = owner.aim_angle
		view.replicated_visuals._step_projectile_visuals(DT)
	var client_drones := func() -> Array[ProjectileState]:
		var result: Array[ProjectileState] = []
		for projectile in view.replicated_visuals.authoritative_projectiles.all_projectiles():
			if projectile.is_drone:
				result.append(projectile)
		return result
	var worst_error := func() -> float:
		var worst := 0.0
		for drone in client_drones.call():
			var authority := world.projectile_registry.get_projectile(drone.projectile_id)
			worst = maxf(worst, INF if authority == null else drone.position.distance_to(authority.position))
		return worst

	tick_once.call(Vector2.ZERO)
	tick_once.call(Vector2.ZERO, true)
	context.expect_equal((client_drones.call() as Array).size(), GameConstants.DRONE_WING_SIZE, "an opponent's client receives the deployed wing")
	context.expect_equal(cues.size(), 1, "a deployment plays one cue, not one per drone")
	var worst_in_flight := 0.0
	for unused in 90:
		tick_once.call(Vector2(0.0, -1.0))
		worst_in_flight = maxf(worst_in_flight, worst_error.call())
	context.expect_true(worst_in_flight < 12.0, "client drones track authority while the owner flies (worst %.2f px)" % worst_in_flight)

	(world.combatants[1] as CombatantState).cloak_remaining = 1.0
	tick_once.call(Vector2.ZERO)
	context.expect_equal((client_drones.call() as Array).size(), 0, "cloaking withdraws the wing from opponents on the next tick")
	var complete := scheduler._projectiles_for_correction(world, true)
	var leaked := 0
	for projectile in complete:
		if projectile.is_drone:
			leaked += 1
	context.expect_equal(leaked, 0, "a complete snapshot never carries a cloaked owner's wing")
	var cloaked_shot := ProjectileState.create(9100, 2, 1, (world.combatants[1] as CombatantState).position + Vector2(-200, -60), 0.0, enemy.stats)
	world.projectile_registry.add(cloaked_shot)
	for unused in 40:
		tick_once.call(Vector2.ZERO)
		context.expect_equal((client_drones.call() as Array).size(), 0, "no correction re-sends a hidden wing")
	context.expect_equal(_drones(world).size(), GameConstants.DRONE_WING_SIZE, "hidden drones survive shots while cloaked")

	for unused in 30:
		tick_once.call(Vector2.ZERO)
	context.expect_equal((client_drones.call() as Array).size(), GameConstants.DRONE_WING_SIZE, "the wing reappears for opponents when cloak ends")
	context.expect_true(worst_error.call() < 12.0, "a revealed wing appears at its authoritative positions")
	context.expect_equal(cues.size(), 1, "a wing revealed after cloak does not replay the deploy cue")

	var victim := _drones(world)[0]
	ProjectileSimulation._damage_drone(world, victim, GameConstants.DRONE_HEALTH)
	tick_once.call(Vector2.ZERO)
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(victim.projectile_id), null, "a destroyed drone disappears for opponents")
	view.free()
	bridge.free()


static func _mine_blasts(context: TestContext) -> void:
	var world := _drone_world()
	_deploy(world, 1)
	for tick in 30:
		world.step(DT)
	var owner := world.combatants[1] as CombatantState
	var mine := ProjectileState.create_mine(9500, 3, owner.position + Vector2(0, 60))
	mine.mine_activation_remaining = 0.0
	world.projectile_registry.add(mine)
	world.spatial_index.rebuild_armed_mines(world.projectile_registry, [9500] as Array[int])
	var events: Array[Dictionary] = []
	ProjectileSimulation._detonate_mine(world, mine, events)
	context.expect_equal(_drones(world).size(), 0, "a mine blast destroys every drone in range")

	var cloaked := _drone_world()
	_deploy(cloaked, 1)
	(cloaked.combatants[1] as CombatantState).cloak_remaining = 5.0
	for tick in 30:
		cloaked.step(DT)
	var cloaked_owner := cloaked.combatants[1] as CombatantState
	var hidden_mine := ProjectileState.create_mine(9501, 3, cloaked_owner.position + Vector2(0, 60))
	hidden_mine.mine_activation_remaining = 0.0
	cloaked.projectile_registry.add(hidden_mine)
	ProjectileSimulation._detonate_mine(cloaked, hidden_mine, [] as Array[Dictionary])
	context.expect_equal(_drones(cloaked).size(), GameConstants.DRONE_WING_SIZE, "a cloaked owner's wing is intangible to blasts")


static func _drone_world() -> AuthoritativeWorld:
	var world := AuthoritativeWorld.new()
	var stats := CombatStats.create_base()
	stats.drone_bay_enabled = true
	stats.drone_capacity = 2
	world.add_peer(1, stats).position = Vector2(400, 200)
	return world


static func _deploy(world: AuthoritativeWorld, sequence: int) -> void:
	world.submit_input(1, PlayerInputFrame.new(sequence, sequence, Vector2.ZERO, 0.0, false, false, false, true, sequence, SpecialAbilitySelection.Slot.DRONE))
	world.step(DT)


static func _drones(world: AuthoritativeWorld, owner_id: int = 1) -> Array[ProjectileState]:
	var result: Array[ProjectileState] = []
	for projectile in world.active_projectiles():
		if projectile.is_drone and projectile.owner_id == owner_id:
			result.append(projectile)
	return result


static func _card_and_inventory(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	var card := catalog.get_card(&"escort_wing")
	context.expect_true(card != null, "Escort Wing is in the default catalog")
	context.expect_equal(card.rarity, CardDefinition.Rarity.MYTHICAL, "Escort Wing is a Mythical card")
	context.expect_empty(StatSystem.validate_card(card), "Escort Wing validates")
	var stats := StatSystem.derive({&"escort_wing": 2}, catalog)
	context.expect_true(stats.drone_bay_enabled, "Escort Wing unlocks the drone bay")
	context.expect_equal(stats.drone_capacity, 4, "each Escort Wing stack adds two wings per heat")
	context.expect_true(SpecialAbilitySelection.Slot.DRONE in SpecialAbilitySelection.owned_slots(stats), "drone bay owns a Special slot")
	var pilot := CombatantState.create(1, stats)
	context.expect_equal(pilot.drone_charges_remaining, 4, "a heat starts with full drone wings")
	context.expect_true(pilot.deploy_drones(), "a ready drone bay deploys")
	context.expect_false(pilot.deploy_drones(), "drone bay cooldown blocks an immediate second wing")
	pilot.reset_for_heat(stats, Vector2.ZERO, false)
	context.expect_equal(pilot.drone_charges_remaining, 3, "objective respawns do not refill drone wings")


static func _deploy_and_follow(context: TestContext) -> void:
	var world := _drone_world()
	_deploy(world, 1)
	var owner := world.combatants[1] as CombatantState
	context.expect_equal(_drones(world).size(), GameConstants.DRONE_WING_SIZE, "Special deploys a full wing")
	context.expect_equal(owner.drone_charges_remaining, 1, "deploying consumes one wing")
	var slots := {}
	for drone in _drones(world):
		slots[drone.drone_slot] = true
	context.expect_equal(slots.size(), GameConstants.DRONE_WING_SIZE, "every drone holds its own formation slot")
	for tick in 60:
		world.submit_input(1, PlayerInputFrame.new(tick + 2, tick + 2, Vector2.RIGHT, 0.0))
		world.step(DT)
	var furthest := 0.0
	for drone in _drones(world):
		furthest = maxf(furthest, drone.position.distance_to(owner.position))
	context.expect_true(furthest < GameConstants.DRONE_FORMATION_DISTANCE * 1.6, "drones keep formation while the owner flies")
	var first_wing := {}
	for drone in _drones(world):
		first_wing[drone.projectile_id] = true
	for tick in ceili(GameConstants.DRONE_COOLDOWN_SECONDS / DT):
		world.step(DT)
	_deploy(world, 1000)
	var replacements := _drones(world)
	context.expect_equal(replacements.size(), GameConstants.DRONE_WING_SIZE, "a new wing replaces rather than stacks on the old one")
	for drone in replacements:
		context.expect_false(first_wing.has(drone.projectile_id), "the previous wing is retired on redeploy")


static func _firing_and_cloak(context: TestContext) -> void:
	var world := _drone_world()
	var enemy := world.add_peer(2)
	enemy.position = Vector2(800, 200)
	_deploy(world, 1)
	for tick in 120:
		world.step(DT)
	var drone_damage := enemy.stats.max_health - enemy.health
	context.expect_true(drone_damage > 0.0, "drones damage an enemy within range")
	context.expect_true(drone_damage <= GameConstants.DRONE_BOLT_DAMAGE * GameConstants.DRONE_WING_SIZE * 3.0, "a wing's output stays below a single cannon's")
	context.expect_equal(world.recent_hostile_attacker(2, 600), 1, "drone damage is credited to the owner")
	var bolt := ProjectileState.create_drone_bolt(9000, 1, Vector2.ZERO, 0.0)
	context.expect_equal(AuthoritativeWorld._projectile_source(bolt), "drone", "drone bolts report their own damage source")

	var cloaked := _drone_world()
	var cloak_target := cloaked.add_peer(2)
	cloak_target.position = Vector2(800, 200)
	_deploy(cloaked, 1)
	(cloaked.combatants[1] as CombatantState).cloak_remaining = 10.0
	for tick in 120:
		cloaked.step(DT)
	context.expect_approx(cloak_target.health, cloak_target.stats.max_health, "drones hold fire while their owner is cloaked")

	var hidden := _drone_world()
	var hidden_target := hidden.add_peer(2)
	hidden_target.position = Vector2(800, 200)
	hidden_target.cloak_remaining = 10.0
	_deploy(hidden, 1)
	for tick in 120:
		hidden.step(DT)
	context.expect_approx(hidden_target.health, hidden_target.stats.max_health, "drones cannot acquire a cloaked enemy")


static func _drones_are_destructible(context: TestContext) -> void:
	var world := _drone_world()
	var enemy := world.add_peer(2)
	enemy.position = Vector2(400, 700)
	_deploy(world, 1)
	for tick in 60:
		world.step(DT)
	var drone: ProjectileState
	for candidate in _drones(world):
		if candidate.drone_slot == 0:
			drone = candidate
	# Fire up at the front escort from below; no other wing member sits in this lane.
	var shot := ProjectileState.create(8000, 2, 1, drone.position + Vector2(0, 120), -PI * 0.5, enemy.stats)
	world.projectile_registry.add(shot)
	var drone_id := drone.projectile_id
	for tick in 20:
		world.step(DT)
	context.expect_equal(world.projectile_registry.get_projectile(drone_id), null, "one standard enemy shot destroys a drone")
	context.expect_equal(world.projectile_registry.get_projectile(8000), null, "the shot is consumed by the drone")
	context.expect_true((world.drain_projectile_batch().removed as Array).has(drone_id), "drone destruction replicates")

	var own := _drone_world()
	_deploy(own, 1)
	var own_drone := _drones(own)[0]
	var friendly := ProjectileState.create(8001, 1, 1, own_drone.position - Vector2(60, 0), 0.0, CombatStats.create_base())
	own.projectile_registry.add(friendly)
	own.step(DT)
	context.expect_true(own.projectile_registry.get_projectile(own_drone.projectile_id) != null, "the owner's shots pass through their own drones")


static func _owner_fire_never_evicts_drones(context: TestContext) -> void:
	var world := _drone_world()
	_deploy(world, 1)
	var stats := CombatStats.create_base()
	for index in GameConstants.MAX_PROJECTILES_PER_OWNER + 10:
		for removed_id in world.projectile_registry.add(ProjectileState.create(10000 + index, 1, index, Vector2(400, 1000), 0.0, stats)):
			world._record_removed(removed_id)
	context.expect_equal(_drones(world).size(), GameConstants.DRONE_WING_SIZE, "ordinary fire never evicts a deployed drone")


static func _retirement(context: TestContext) -> void:
	var world := _drone_world()
	_deploy(world, 1)
	for tick in ceili(GameConstants.DRONE_LIFETIME_SECONDS / DT) + 2:
		world.step(DT)
	context.expect_equal(_drones(world).size(), 0, "drones retire after their lifetime")

	var dead := _drone_world()
	_deploy(dead, 1)
	(dead.combatants[1] as CombatantState).apply_damage(1000.0)
	dead.projectile_registry.schedule_owner_cleanup(1)
	for tick in ceili(GameConstants.DEAD_OWNER_PROJECTILE_LIFETIME / DT) + 2:
		dead.step(DT)
	context.expect_equal(_drones(dead).size(), 0, "drones are retired shortly after their owner dies")


static func _replication(context: TestContext) -> void:
	var drone := ProjectileState.create_drone(77, 5, Vector2(640, 320), 3)
	drone.damage = 12.5
	drone.missile_target_id = 9
	var bolt := ProjectileState.create_drone_bolt(78, 5, Vector2(700, 320), 0.5)
	var packets := ProjectilePacketCodec.encode_batch_chunks(1, 1, [drone, bolt] as Array[ProjectileState], [])
	var decoded := ProjectilePacketCodec.decode_batch(packets[0])
	context.expect_true(bool(decoded.ok), "drone projectile packets decode")
	var decoded_drone := (decoded.spawned as Array)[0] as ProjectileState
	var decoded_bolt := (decoded.spawned as Array)[1] as ProjectileState
	context.expect_true(decoded_drone.is_drone and not decoded_drone.is_drone_bolt, "drone flag round-trips")
	context.expect_equal(decoded_drone.drone_slot, 3, "formation slot round-trips")
	context.expect_equal(decoded_drone.remaining_pierces, 0, "the slot byte is not misread as pierces")
	context.expect_approx(decoded_drone.damage, 12.5, "drone hull round-trips", 0.01)
	context.expect_approx(decoded_drone.radius, GameConstants.DRONE_RADIUS, "drone radius is restored")
	context.expect_true(decoded_bolt.is_drone_bolt and not decoded_bolt.is_drone, "drone bolt flag round-trips")
	context.expect_approx(decoded_bolt.radius, GameConstants.DRONE_BOLT_RADIUS, "drone bolt radius is restored")

	var pilot := CombatantState.create(4, CombatStats.create_base())
	pilot.drone_charges_remaining = 3
	pilot.drone_cooldown_remaining = 2.25
	var local_state := pilot.prediction_state()
	var packet := PlayerSnapshotCodec.encode(10, 10, [] as Array[Dictionary], local_state)
	var snapshot := PlayerSnapshotCodec.decode(packet)
	context.expect_true(bool(snapshot.ok), "player snapshot with drone inventory decodes")
	context.expect_equal(int(snapshot.local_state.drone_charges), 3, "drone wings reach the owner's HUD")
	context.expect_approx(float(snapshot.local_state.drone_cooldown), 2.25, "drone cooldown reaches the owner's HUD", 0.001)
