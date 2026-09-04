extends RefCounted

const Presentation = preload("res://src/client/presentation/combat_feedback_presentation.gd")
const Buffer = preload("res://src/shared/combat/combat_feedback_buffer.gd")


static func run(context: TestContext) -> void:
	_damage_resolution(context)
	_world_feedback(context)
	_shield_feedback(context)
	_shield_presentation_contract(context)
	_shield_delivery_contract(context)
	_lethal_mechanics(context)
	_profiling(context)
	_bounds_and_presentation(context)


static func _damage_resolution(context: TestContext) -> void:
	var ship := CombatantState.create(2, CombatStats.create_base())
	ship.health = 10.0
	var events: Array[Dictionary] = [
		{"projectile_id": 3, "attacker_id": 3, "target_id": 2, "damage": 100.0},
		{"projectile_id": 1, "attacker_id": 1, "target_id": 2, "damage": 6.0, "source": "beam"},
		{"projectile_id": 2, "attacker_id": 1, "target_id": 2, "damage": 10.0, "source": "missile"},
	]
	var impacts := DamageResolver.resolve_tick_with_feedback({2: ship}, events)
	context.expect_equal(impacts.size(), 2, "lethal volley confirms no impacts against the already dead ship")
	context.expect_approx(float(impacts[1].damage), 4.0, "lethal feedback counts actual remaining hull damage")
	context.expect_equal(String(impacts[1].source), "missile", "recap source follows deterministic lethal projectile ordering")
	context.expect_true(bool(impacts[1].lethal), "exact lethal impact is marked")
	ship.reset_for_heat(CombatStats.create_base(), Vector2.ZERO)
	var invalid: Array[Dictionary] = [{"target_id": 2, "damage": NAN}, {"target_id": 2, "damage": -10.0}, {"target_id": 9, "damage": 10.0}]
	context.expect_true(DamageResolver.resolve_tick_with_feedback({2: ship}, invalid).is_empty(), "invalid or absent-target damage never confirms an impact")
	context.expect_true(is_finite(ship.health), "nonfinite damage cannot poison authoritative health")


static func _world_feedback(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	world.add_peer(1)
	var target := world.add_peer(2)
	target.health = 20.0
	target.cloak_remaining = 5.0
	world._resolve_damage_events([{"projectile_id": 1, "attacker_id": 1, "target_id": 2, "damage": 30.0, "source": "mine", "mechanic": "blast_ignores_shield"}])
	var feedback := world.drain_combat_feedback()
	context.expect_equal(feedback.size(), 2, "damage confirmations go only to attacker and lethal victim")
	context.expect_equal(int(feedback[1].hit_count), 1, "attacker receives authoritative hit confirmation")
	context.expect_approx(float(feedback[1].hit_damage), 20.0, "attacker readout excludes overkill")
	context.expect_equal(String(feedback[2].death.source), "mine", "victim recap identifies mine source")
	context.expect_equal(int(feedback[2].death.life_generation), target.life_generation, "recap identifies the victim life to reject stale respawn messages")
	context.expect_false(feedback[1].has("target_id") or feedback[1].has("position"), "confirmation cannot expose hidden target identity or position")
	context.expect_false(feedback[2].death.has("position"), "death recap exposes no cloaked killer position")
	context.expect_true(world.drain_combat_feedback().is_empty(), "feedback drains once")
	context.expect_equal(world.drain_kill_events(), [{"killer_id": 1, "target_id": 2}], "existing kill score attribution remains intact")
	world.respawn_peer(2, CombatStats.create_base(), Vector2(10, 10))
	target.health = 1.0
	world.apply_overtime(100.0, 1.0)
	feedback = world.drain_combat_feedback()
	context.expect_equal(String(feedback[2].death.source), "overtime", "environmental death names overtime without inventing a killer")
	context.expect_true(world.drain_kill_events().is_empty(), "overtime grants no kill score")
	world.respawn_peer(2, CombatStats.create_base(), Vector2.ZERO)
	world._resolve_damage_events([{"target_id": 2, "attacker_id": 2, "damage": 1000.0, "source": "mine"}])
	feedback = world.drain_combat_feedback()
	context.expect_equal(int(feedback[2].hit_count), 0, "self damage never confirms an enemy hit")
	context.expect_true(world.drain_kill_events().is_empty(), "self damage grants no kill score")
	world.respawn_peer(2, CombatStats.create_base(), Vector2.ZERO)
	world.remove_peer(1)
	world._resolve_damage_events([{"target_id": 2, "attacker_id": 1, "damage": 1000.0, "source": "projectile"}])
	feedback = world.drain_combat_feedback()
	context.expect_false(feedback.has(1), "departed attackers receive no queued feedback")
	context.expect_equal(int(feedback[2].death.killer_id), 1, "a departed projectile owner retains death-cause identity")
	world.set_spectator(2)
	context.expect_true(world.drain_combat_feedback().is_empty(), "spectating is not reported as a combat death")


static func _shield_feedback(context: TestContext) -> void:
	for reason in ["shield", "perfect_guard", "rebound"]:
		var world := AuthoritativeWorld.new()
		world.add_peer(1)
		var stats := CombatStats.create_base()
		stats.rebound_shield_enabled = reason == "rebound"
		var defender := world.add_peer(2, stats)
		defender.position = Vector2(400, 400)
		defender.aim_angle = 0.0
		defender.shield.active = true
		defender.shield.perfect_guard_window_remaining = 0.1 if reason == "perfect_guard" else 0.0
		var shot := ProjectileState.create(1, 1, 1, Vector2(420, 400), PI, CombatStats.create_base())
		world.projectile_registry.add(shot)
		var damage_events: Array[Dictionary] = []
		world._resolve_projectile_ship_hit(shot, 2, damage_events)
		var feedback := world.drain_combat_feedback()
		context.expect_true(damage_events.is_empty(), "%s does not produce hull hit confirmation" % reason)
		context.expect_equal(int(feedback[1].blocked_count), 1, "%s confirms outgoing blocked shot" % reason)
		context.expect_equal(int(feedback[2].guard_count), 1, "%s confirms defender shield block" % reason)
		context.expect_equal(int(feedback[2].shield.blocks), 1, "%s records one authoritative visual impact" % reason)
		context.expect_equal(String(feedback[1].last_block_reason), reason, "%s block reason is authoritative" % reason)
		context.expect_equal(int(feedback[1].hit_count), 0, "%s shield block is distinct from hull damage" % reason)
		if reason == "rebound":
			var attacker := world.combatants[1] as CombatantState
			attacker.health = 1.0
			shot.position = attacker.position
			world._resolve_projectile_ship_hit(shot, 1, damage_events)
			world._resolve_damage_events(damage_events)
			feedback = world.drain_combat_feedback()
			context.expect_equal(int(feedback[1].death.killer_id), 2, "reflected lethal shot attributes the shield owner")
			context.expect_equal(String(feedback[1].death.mechanic), "reflected", "reflected lethal shot explains Rebound Shield")
			context.expect_equal(int(feedback[2].hit_count), 1, "rebound owner receives the confirmed hull hit")


static func _bounds_and_presentation(context: TestContext) -> void:
	var buffer := Buffer.new()
	for index in 1000:
		buffer.record_hit(1, 2.0, "beam")
	buffer.record_death(1, {"source": "mine"})
	buffer.record_block(1, 2, "shield")
	var batch := buffer.drain()
	context.expect_equal(batch.size(), 2, "a thousand impacts remain two bounded recipient payloads")
	context.expect_equal(int(batch[1].hit_count), 1000, "coalescing preserves burst hit count")
	context.expect_approx(float(batch[1].hit_damage), 2000.0, "coalescing preserves actual burst damage")
	context.expect_true(batch[1].has("death"), "block/hit updates cannot overwrite a death recap")
	for peer_id in range(1, Buffer.MAX_RECIPIENTS + 5):
		buffer.record_hit(peer_id, 1.0, "projectile")
	context.expect_equal(buffer.drain().size(), Buffer.MAX_RECIPIENTS, "recipient memory is explicitly bounded")
	context.expect_equal(Presentation.hit_text({"hit_count": 2, "hit_damage": 9.5}), "HIT ×2 · 9.5 DAMAGE", "confirmation reports the actual aggregate damage")
	context.expect_equal(Presentation.block_text({"blocked_count": 1, "last_block_reason": "rebound"}), "SHOT REFLECTED", "reflections use distinct outgoing wording")
	context.expect_equal(Presentation.guard_text({"guard_count": 1, "last_guard_reason": "perfect_guard"}), "PERFECT GUARD", "timed defender block uses distinct wording")
	context.expect_equal(Presentation.hit_text({}), "", "no event invents no speculative miss or hit")
	var recap := {"killer_id": 7, "source": "missile", "mechanic": "outside_shield_arc", "damage": 10.0}
	var text := Presentation.death_text(recap, 1, {"7": "Comet"})
	context.expect_true(text.contains("Comet · HOMING MISSILE"), "death explanation accepts serialized roster keys and identifies weapon")
	context.expect_true(text.contains("outside your shield arc"), "death explanation includes relevant shield mechanic")
	context.expect_true(Presentation.death_text({"source": "overtime"}, 1).contains("OVERTIME"), "environment death has readable source")
	context.expect_true(Presentation.death_text({"killer_id": 1, "source": "mine"}, 1).contains("YOUR OWN"), "self damage is not attributed to another pilot")
	context.expect_true(Presentation.death_text({"killer_id": 7, "source": "beam"}, 1).contains("Pilot 7"), "departed killer retains a stable fallback identity")
	var panel := CombatFeedbackPanel.new()
	panel._ready()
	panel.apply_feedback({"hit_count": 1, "hit_damage": 10.0}, 1)
	panel._process(0.8)
	var remaining := panel._remaining
	panel.apply_feedback({"shield_cues": [{"peer_id": 2, "blocks": 1}]}, 1)
	context.expect_approx(panel._remaining, remaining, "remote shield activity cannot prolong a stale private hit readout")
	panel.free()


static func _shield_presentation_contract(context: TestContext) -> void:
	for peer_id in [1, 2]:
		var world := AuthoritativeWorld.new()
		var stats := CombatStats.create_base()
		stats.shield_capacity = 160.0
		stats.shield_depletion_threshold = 45.0
		stats.shield_continuous_drain = 10.0
		stats.shield_block_cost = 1.0
		var defender := world.add_peer(peer_id, stats)
		var shield := defender.shield
		shield.active = true
		shield.energy = 26.0
		var view := NetworkWorldView.new()
		view.local_peer_id = 1
		view.controls_enabled = true
		var ship := CombatShipView.new()
		# Deliberately use base presentation stats, even for the upgraded remote.
		ship.setup(peer_id, CombatStats.create_base(), Vector2(400, 400), Color.WHITE, peer_id == 1, "Shield")
		view.ships[peer_id] = ship
		var events: Array[StringName] = []
		view.presentation_event.connect(func(event: StringName, _payload: Dictionary) -> void:
			if event in [&"shield_block", &"shield_break"]:
				events.append(event)
		)
		_present_shield(world, view, ship, 1)
		context.expect_empty(events, "first snapshot establishes shield feedback baseline")
		shield.step(true, stats, 0.2)
		_present_shield(world, view, ship, 13)
		shield.step(true, stats, 0.4)
		_present_shield(world, view, ship, 37)
		context.expect_empty(events, "continuous drain across threshold and snapshot gaps invents no shield block or break")
		shield.perfect_guard_window_remaining = 0.1
		var energy_before := shield.energy
		context.expect_true(shield.try_block(0.0, Vector2.RIGHT, stats), "low-cost Perfect Guard actually blocks")
		context.expect_true(energy_before - shield.energy < 2.0, "Perfect Guard fixture costs less than the removed heuristic")
		var impact_payload := _present_shield(world, view, ship, 38, false)
		context.expect_equal(events, [&"shield_block"], "actual low-cost impact produces one cue for local and remote ships")
		view.apply_combat_feedback(impact_payload)
		context.expect_equal(events.size(), 1, "duplicate feedback cannot replay shield cues")
		shield.try_block(0.0, Vector2.RIGHT, stats)
		shield.try_absorb_contact(stats)
		shield.step(false, stats, 10.0)
		_present_shield(world, view, ship, 638)
		context.expect_equal(events, [&"shield_block", &"shield_block"], "missed impacts coalesce into one cue even after energy regenerates")
		shield.active = true
		shield.energy = 0.1
		shield.step(true, stats, 0.1)
		shield.step(false, stats, 10.0)
		context.expect_false(shield.depletion_locked, "depletion fixture fully recovers before next snapshot")
		_present_shield(world, view, ship, 1244)
		context.expect_equal(events.back(), &"shield_break", "actual drain depletion survives a missed zero-energy snapshot")
		context.expect_equal(events.size(), 3, "drain depletion does not fabricate an impact")
		shield.active = true
		shield.energy = 0.1
		shield.try_block(0.0, Vector2.RIGHT, stats)
		_present_shield(world, view, ship, 1245)
		context.expect_equal(events.slice(3), [&"shield_block", &"shield_break"], "depleting impact confirms both events once")
		shield.step(true, stats, 0.1)
		_present_shield(world, view, ship, 1251)
		context.expect_equal(events.size(), 5, "remaining depletion-locked cannot repeat a break")
		defender.reset_for_heat(stats, defender.position)
		_present_shield(world, view, ship, 1252)
		context.expect_equal(events.size(), 5, "heat or respawn reset cannot invent cues")
		shield.active = true
		shield.energy = 0.1
		shield.try_absorb_contact(stats)
		defender.reset_for_heat(stats, defender.position)
		_present_shield(world, view, ship, 1253)
		context.expect_equal(events.size(), 5, "life reset discards pending old-life shield events")
		impact_payload.server_tick = 1000
		view.apply_combat_feedback(impact_payload)
		context.expect_equal(events.size(), 5, "feedback older than one second cannot replay after a blackout")
		view.controls_enabled = false
		impact_payload.server_tick = 1254
		view.apply_combat_feedback(impact_payload)
		context.expect_equal(events.size(), 5, "feedback cannot replay into countdown or results")
		view.controls_enabled = true
		view.match_payload = {"entered_tick": 1255}
		view.apply_combat_feedback(impact_payload)
		context.expect_equal(events.size(), 5, "previous-heat feedback cannot replay even without a fresh snapshot")
		view.ships.clear()
		ship.free()
		view.free()


static func _present_shield(world: AuthoritativeWorld, view: NetworkWorldView, ship: CombatShipView, tick: int, deliver_snapshot: bool = true) -> Dictionary:
	# Snapshot delivery is independent of the authoritative reliable feedback.
	if deliver_snapshot:
		var body := PlayerSnapshotCodec.encode_combatant_body(world.combatants, world.ordered_peer_ids_view())
		var decoded := PlayerSnapshotCodec.decode(PlayerSnapshotCodec.assemble(tick, 0, body))
		view.replicated_visuals._handle_snapshot_feedback(int(decoded.states[0].peer_id), decoded.states[0], ship)
	view.latest_server_tick = tick
	var payload := Buffer.for_recipient(world.drain_combat_feedback(), world.combatants, view.local_peer_id, tick)
	view.apply_combat_feedback(payload)
	return payload


static func _shield_delivery_contract(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	for peer_id in range(1, 33):
		var defender := world.add_peer(peer_id)
		defender.shield.active = true
		defender.shield.try_absorb_contact(defender.stats)
	var batch := world.drain_combat_feedback()
	context.expect_equal(batch.size(), 32, "crowded shield feedback stays bounded to one record per participant")
	var public := Buffer.for_recipient(batch, world.combatants, 100, 10)
	context.expect_equal(public.shield_cues.size(), 32, "spectators receive visible authoritative shield cues")
	context.expect_false(public.has("guard_count") or public.has("hit_damage"), "public cue delivery does not disclose private combat totals")
	var hidden := world.combatants[2] as CombatantState
	hidden.stats.cloak_enabled = true
	hidden.cloak_remaining = 5.0
	var filtered := Buffer.for_recipient(batch, world.combatants, 1, 10)
	context.expect_equal(filtered.shield_cues.size(), 31, "cloaked remote shield events are omitted")
	var owner := Buffer.for_recipient(batch, world.combatants, 2, 10)
	context.expect_equal(owner.shield_cues.size(), 32, "cloaked owner retains its own shield confirmation")
	owner.shield_cues[0].blocks = 999
	context.expect_equal(public.shield_cues[0].blocks, 1, "recipient payloads cannot mutate another recipient's cues")
	context.expect_empty(world.drain_combat_feedback(), "shield events drain exactly once")
	context.expect_empty(Buffer.for_recipient({}, world.combatants, 1, 11), "quiet shields send no reliable messages")
	hidden.reset_for_heat(hidden.stats, hidden.position)
	context.expect_equal(Buffer.for_recipient(batch, world.combatants, 2, 11).shield_cues.size(), 31, "a drained old-life cue is excluded after respawn")
	hidden.shield._feedback_blocks = 65534
	hidden.shield._feedback_breaks = 65534
	for index in 2:
		hidden.shield.active = true
		hidden.shield.depletion_locked = false
		hidden.shield.energy = 0.1
		hidden.shield.try_absorb_contact(hidden.stats)
	context.expect_equal(hidden.shield.drain_feedback(), Vector2i(65535, 65535), "stalled shield feedback counters saturate rather than growing or wrapping")


static func _lethal_mechanics(context: TestContext) -> void:
	for depleted in [false, true]:
		var world := AuthoritativeWorld.new()
		world.add_peer(1)
		var victim := world.add_peer(2)
		victim.position = Vector2(400, 400)
		victim.health = 1.0
		victim.aim_angle = PI
		victim.shield.active = not depleted
		victim.shield.depletion_locked = depleted
		var shot := ProjectileState.create_missile(1, 1, Vector2(420, 400), PI)
		world.projectile_registry.add(shot)
		var events: Array[Dictionary] = []
		world._resolve_projectile_ship_hit(shot, 2, events)
		world._resolve_damage_events(events)
		var feedback := world.drain_combat_feedback()
		context.expect_equal(String(feedback[2].death.source), "missile", "lethal missile retains the projectile's actual weapon type")
		context.expect_equal(String(feedback[2].death.mechanic), "shield_depleted" if depleted else "outside_shield_arc", "lethal hit distinguishes depleted shield from uncovered arc")
	var world := AuthoritativeWorld.new()
	world.add_peer(1)
	var victim := world.add_peer(2)
	victim.position = Vector2(430, 400)
	victim.health = 1.0
	victim.shield.active = true
	var mine := ProjectileState.create_mine(1, 1, Vector2(400, 400))
	mine.mine_activation_remaining = 0.0
	world.projectile_registry.add(mine)
	world.spatial_index.rebuild_ships(world.combatants, world.ordered_peer_ids_view())
	world.spatial_index.rebuild_armed_mines(world.projectile_registry, [1])
	var mine_events: Array[Dictionary] = []
	world._detonate_mine(mine, mine_events)
	world._resolve_damage_events(mine_events)
	var mine_feedback := world.drain_combat_feedback()
	context.expect_equal(String(mine_feedback[2].death.mechanic), "blast_ignores_shield", "actual mine detonation explains why an active shield did not block it")
	context.expect_equal(int(mine_feedback[1].hit_count), 1, "actual blast produces one applied hull damage confirmation")
	world._combat_feedback.record_hit(1, 10.0, "projectile")
	world.prepare_heat({}, {})
	context.expect_true(world.drain_combat_feedback().is_empty(), "heat preparation clears prior feedback")


static func _profiling(context: TestContext) -> void:
	var ordinary := AuthoritativeWorld.new()
	var profiled := AuthoritativeWorld.new()
	profiled.performance_profiling_enabled = true
	for world in [ordinary, profiled]:
		world.add_peer(1).position = Vector2(350, 400)
		world.add_peer(2).position = Vector2(520, 400)
		world.projectile_registry.add(ProjectileState.create(1, 1, 1, Vector2(400, 400), 0.0, CombatStats.create_base()))
		for tick in 12:
			world.step(1.0 / 60.0)
	context.expect_equal(profiled.snapshot_states(), ordinary.snapshot_states(), "opt-in collision profiling does not change combat outcomes")
	context.expect_equal(profiled.drain_combat_feedback(), ordinary.drain_combat_feedback(), "profiling does not change recipient feedback")
	context.expect_true(profiled.last_projectile_profile_usec.has("ship_candidates"), "projectile profile exposes broad-phase candidate counts")
	context.expect_true(profiled.last_projectile_profile_usec.has("obstacle_sweep"), "projectile profile exposes static collision timing")
