extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_shared_resource_identity(context)
	_registry_invariants(context, parent)
	_replication_ordering(context, parent)
	var bridge := NetworkBridge.new()
	parent.add_child(bridge)
	var view := NetworkWorldFixture.new()
	parent.add_child(view)
	view.setup(bridge)
	view.set_physics_process(false)
	view.local_peer_id = 1
	var prediction_owner := view.local_prediction
	var visual_owner := view.replicated_visuals
	var hud_owner := view.hud_camera
	var draw_layers: Array[Node] = [view.replicated_visuals.arena, view.replicated_visuals.projectile_layer, view.replicated_visuals.effects_layer, view.replicated_visuals.powerup_layer, view.hud_camera.camera, view.hud_camera.hud_root]
	context.expect_empty(view.find_children("*", "SubViewport", true, false), "network ownership creates no additional render targets")
	view.apply_match_state({"state_name": "ACTIVE_HEAT", "teams": {1: 1, 2: 2}, "game_mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG})
	context.expect_equal(view.replicated_visuals.arena.local_peer_id, 1, "match coordination passes local identity into shared arena")
	context.expect_equal(view.replicated_visuals.arena.local_team_id, 1, "match coordination passes team identity into shared arena")
	var authority := AuthoritativeWorld.new()
	var pilot := authority.add_peer(1)
	pilot.position = Vector2(300, 300)
	pilot.weapon.ammunition = 3
	pilot.weapon.cooldown_remaining = 0.25
	pilot.afterburner_cooldown_remaining = 1.5
	var remote := authority.add_peer(2)
	remote.position = Vector2(1000, 700)
	_emit_snapshot(bridge, authority, 10)
	context.expect_true(view.local_prediction.prediction_initialized, "snapshot initializes local prediction through owner")
	context.expect_equal(view.local_prediction.local_weapon.ammunition, 3, "private correction and public resources reach local weapon")
	context.expect_approx(view.local_prediction.local_special_cooldown_remaining, 1.5, "private cooldown survives codec and prediction owner")
	context.expect_equal(view.local_prediction.local_active_ordnance, 7, "private ordnance usage reaches local prediction")
	context.expect_true(view.replicated_visuals.interpolation.sample(2, view._now_seconds()).ok, "remote snapshot reaches interpolation owner")
	context.expect_equal(view.replicated_visuals.ships, visual_owner.ships, "compatibility dictionary exposes authoritative visual ownership")
	var local_ship := view.replicated_visuals.ships[1] as CombatShipView
	var child_count := view.get_child_count()
	view.input_blocked = true
	for unused in 8:
		view._physics_process(1.0 / 60.0)
	context.expect_equal(view.local_prediction.input_sequence, 8, "each physics frame advances owned input sequence")
	context.expect_equal(view.get_child_count(), child_count, "steady presentation frames do not create drawable nodes")
	context.expect_equal(view.local_prediction, prediction_owner, "physics retains prediction owner")
	context.expect_equal(view.replicated_visuals, visual_owner, "physics retains replicated visual owner")
	context.expect_equal(view.hud_camera, hud_owner, "physics retains HUD camera owner")
	context.expect_equal(view.replicated_visuals.ships[1], local_ship, "physics preserves local drawable identity")
	view.apply_match_pause(true)
	var paused_position := local_ship.global_position
	var paused_ammo := view.local_prediction.local_weapon.ammunition
	for unused in 120:
		view._physics_process(1.0 / 60.0)
	context.expect_equal(view.local_prediction.input_sequence, 8, "global pause stops local input generation")
	context.expect_equal(local_ship.global_position, paused_position, "global pause freezes client prediction")
	context.expect_equal(view.local_prediction.local_weapon.ammunition, paused_ammo, "global pause preserves predicted ammunition")
	context.expect_empty(view.local_prediction.prediction.buffered_inputs, "global pause discards unacknowledged prediction replay")
	context.expect_false(view.controls_enabled, "global pause disables local combat controls")
	view.apply_match_pause(false)
	context.expect_true(view.controls_enabled, "resume restores active-heat controls")
	context.expect_false(view.local_prediction.prediction_initialized, "resume waits for an authoritative prediction baseline")
	_projectile_reconciliation(context, view, bridge, local_ship)
	_missile_visuals(context, view, bridge)
	var upgraded_builds := {1: {&"reinforced_hull": 1}, 2: {&"reinforced_hull": 1}}
	view.apply_builds(upgraded_builds)
	upgraded_builds[2].clear()
	context.expect_approx((view.replicated_visuals.ships[2] as CombatShipView).combatant.stats.max_health, 125.0, "powerup updates the visible remote build")
	remote.alive = false
	_emit_snapshot(bridge, authority, 11)
	remote.alive = true
	_emit_snapshot(bridge, authority, 12)
	context.expect_approx((view.replicated_visuals.ships[2] as CombatShipView).combatant.stats.max_health, 125.0, "respawn preserves a detached powerup build")
	remote.cloak_remaining = 5.0
	_emit_snapshot(bridge, authority, 13)
	context.expect_false(view.replicated_visuals.ships.has(2), "cloak omission removes replicated drawable")
	context.expect_false(view.replicated_visuals.presentation_states.has(2), "cloak omission clears damage feedback history")
	context.expect_false(view.replicated_visuals.interpolation.sample(2, view._now_seconds()).ok, "cloak omission clears interpolation history")
	context.expect_false(view.hud_camera._living_spectator_targets().has(2), "HUD cannot target a cloaked omitted pilot")
	remote.cloak_remaining = 0.0
	remote.position = Vector2(1200, 800)
	_emit_snapshot(bridge, authority, 16)
	context.expect_equal((view.replicated_visuals.ships[2] as CombatShipView).global_position, remote.position, "revealed drawable starts at fresh authoritative location")
	context.expect_approx((view.replicated_visuals.ships[2] as CombatShipView).combatant.stats.max_health, 125.0, "cloak reappearance preserves the latest powerup build")
	view.apply_builds({})
	context.expect_approx((view.replicated_visuals.ships[2] as CombatShipView).combatant.stats.max_health, 100.0, "empty build update clears temporary upgrades")
	context.expect_approx(view.local_prediction.local_stats.max_health, 100.0, "empty build update clears local prediction upgrades")
	view.apply_match_state({"state_name": "COUNTDOWN"})
	context.expect_false(view.local_prediction.prediction_initialized, "countdown requires a fresh local prediction baseline")
	context.expect_empty(view.replicated_visuals.presentation_states, "countdown clears previous heat feedback")
	context.expect_false(view.replicated_visuals.interpolation.sample(2, view._now_seconds()).ok, "countdown clears previous heat interpolation")
	context.expect_equal(view.replicated_visuals.ships[1], local_ship, "countdown retains existing ships for authoritative respawn")
	view.hud_camera.camera_shake_remaining = 1.0
	view.hud_camera.camera.offset = Vector2(10, 10)
	view.hud_camera._nearest_incoming_cache = ProjectileState.create(99, 2, 1, Vector2(500, 300), 0.0, view.local_prediction.local_stats)
	view.reset_match_presentation()
	context.expect_equal(view.local_peer_id, 1, "fresh match reset retains connected local identity")
	context.expect_equal(view.local_prediction.input_sequence, 8, "fresh match reset retains input sequence")
	context.expect_equal(view.local_prediction.client_tick, 8, "fresh match reset retains client tick")
	context.expect_empty(view.replicated_visuals.ships, "fresh match clears prior combatant drawables")
	context.expect_empty(view.replicated_visuals.authoritative_projectiles.all_projectiles(), "fresh match clears authoritative and predicted projectiles")
	context.expect_empty(view.local_prediction.predicted_projectile_ids, "fresh match clears pending volley ownership")
	context.expect_equal(view.local_prediction.local_active_ordnance, 0, "fresh match clears private ordnance state")
	context.expect_equal(view.hud_camera.camera.offset, Vector2.ZERO, "fresh match clears camera shake offset")
	context.expect_equal(view.hud_camera._nearest_incoming_cache, null, "fresh match clears incoming projectile cache")
	context.expect_equal([view.replicated_visuals.arena, view.replicated_visuals.projectile_layer, view.replicated_visuals.effects_layer, view.replicated_visuals.powerup_layer, view.hud_camera.camera, view.hud_camera.hud_root], draw_layers, "fresh match reuses drawing layers and HUD surfaces")
	view.reset_session()
	context.expect_equal(view.local_peer_id, 0, "disconnect reset clears local identity")
	context.expect_equal(view.local_prediction.input_sequence, 0, "disconnect reset clears local input sequence")
	var callback := Callable(visual_owner, "_on_projectile_batch")
	context.expect_true(bridge.client_projectile_batch_received.is_connected(callback), "replication callback belongs directly to its persistent owner")
	view.free()
	context.expect_false(bridge.client_projectile_batch_received.is_connected(callback), "view teardown disconnects surviving RefCounted owner's bridge callback")
	context.expect_false(bridge.client_projectile_correction_received.is_connected(Callable(visual_owner, "_on_projectile_correction")), "view teardown disconnects correction callback")
	bridge.client_projectile_batch_received.emit({"spawned": [], "removed": []})
	bridge.free()


static func _emit_snapshot(bridge: NetworkBridge, authority: AuthoritativeWorld, tick: int) -> void:
	var private_state := (authority.combatants[1] as CombatantState).prediction_state()
	private_state["active_ordnance"] = 7
	var body := PlayerSnapshotCodec.encode_combatant_body(authority.combatants, authority.ordered_peer_ids_view(), 1)
	bridge.client_snapshot_received.emit(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.assemble(tick, 0, body, private_state)))


static func _projectile_reconciliation(context: TestContext, view: NetworkWorldFixture, bridge: NetworkBridge, ship: CombatShipView) -> void:
	view.local_prediction.local_weapon.shot_sequence = 11
	view.local_prediction._spawn_predicted_projectile(ship, 0.0)
	context.expect_true(view.replicated_visuals.authoritative_projectiles.get_projectile(-1) != null, "local shot creates a predicted drawable")
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.all_projectiles().size(), 1, "first predicted shot is enumerable by the renderer")
	var authoritative := ProjectileState.create(101, 1, 11, ship.global_position + Vector2(31, 0), 0.0, view.local_prediction.local_stats)
	var chunks := ProjectilePacketCodec.encode_batch_chunks(11, 1, [authoritative], [])
	bridge.client_projectile_batch_received.emit(ProjectilePacketCodec.decode_batch(chunks[0]))
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(-1), null, "authoritative delta removes predicted duplicate")
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.all_projectiles().size(), 1, "authoritative delta retains one shot drawable")
	view.local_prediction.local_weapon.shot_sequence = 12
	view.local_prediction._spawn_predicted_projectile(ship, 0.0)
	var corrected := ProjectileState.create(102, 1, 12, ship.global_position + Vector2(50, 0), 0.0, view.local_prediction.local_stats)
	chunks = ProjectilePacketCodec.encode_correction_chunks(12, 2, [corrected], true)
	bridge.client_projectile_correction_received.emit(ProjectilePacketCodec.decode_correction(chunks[0]))
	context.expect_empty(view.local_prediction.predicted_projectile_ids, "full correction reconciles lost shot delta")
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.all_projectiles().size(), 1, "full correction prunes stale authoritative shot and prediction")
	context.expect_true(view.replicated_visuals.authoritative_projectiles.get_projectile(102) != null, "corrected authoritative shot remains drawable")


static func _missile_visuals(context: TestContext, view: NetworkWorldFixture, bridge: NetworkBridge) -> void:
	var missile := ProjectileState.create_missile(201, 1, Vector2(300, 300), 0.0, 2)
	var target := view.replicated_visuals.ships[2] as CombatShipView
	target.combatant.position = Vector2(950, 440)
	var chunks := ProjectilePacketCodec.encode_correction_chunks(20, 3, [missile], true)
	bridge.client_projectile_correction_received.emit(ProjectilePacketCodec.decode_correction(chunks[0]))
	var visual := view.replicated_visuals.authoritative_projectiles.get_projectile(201)
	context.expect_equal(visual.missile_target_id, 2, "missile target survives wire replication")
	var world := AuthoritativeWorld.new()
	world.add_peer(1).position = Vector2(200, 300)
	world.add_peer(2).position = target.combatant.position
	world.projectile_registry.add(missile)
	for tick in 30:
		world.step(1.0 / 60.0)
		view.replicated_visuals._step_projectile_visuals(1.0 / 60.0)
	context.expect_true(visual.position.distance_to(missile.position) < 0.1, "replicated missile follows authoritative curved flight between corrections")
	context.expect_true(visual.velocity.y > 0, "missile visual turns toward its target")
	visual.lifetime_remaining = 0.001
	var before := visual.position
	view.replicated_visuals._step_projectile_visuals(0.1)
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(201), visual, "predicted expiry cannot hide a live authoritative missile")
	context.expect_equal(visual.position, before, "expired prediction stops travelling while waiting for authority")
	missile.position = Vector2(740, 550)
	missile.velocity = Vector2.RIGHT * GameConstants.MISSILE_SPEED
	missile.missile_target_id = 0
	missile.lifetime_remaining = 1.0
	chunks = ProjectilePacketCodec.encode_correction_chunks(50, 4, [missile], true)
	bridge.client_projectile_correction_received.emit(ProjectilePacketCodec.decode_correction(chunks[0]))
	context.expect_equal(visual.missile_target_id, 0, "correction clears a lost missile lock")
	view.replicated_visuals._step_projectile_visuals(0.1)
	context.expect_approx(visual.position.x, 770.0 - GameConstants.MISSILE_RADIUS, "missile prediction stops at the terrain surface")
	before = visual.position
	view.replicated_visuals._step_projectile_visuals(0.5)
	context.expect_equal(visual.position, before, "missile prediction cannot travel through terrain after contact")
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(201), visual, "predicted terrain contact cannot hide a live missile")
	context.expect_true(not visual.velocity.is_zero_approx(), "stationary missile retains its visible body orientation")
	bridge.client_projectile_batch_received.emit({"server_tick": 51, "batch_sequence": 5, "spawned": [], "removed": [201]})
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(201), null, "confirmed impact immediately removes missile visual")
	chunks = ProjectilePacketCodec.encode_correction_chunks(60, 6, [missile], true)
	bridge.client_projectile_correction_received.emit(ProjectilePacketCodec.decode_correction(chunks[0]))
	bridge.client_projectile_correction_received.emit({"server_tick": 61, "batch_sequence": 7, "spawned": [], "complete_snapshot": true})
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(201), null, "full snapshot retires missile when removal delta was lost")


static func _replication_ordering(context: TestContext, parent: Node) -> void:
	var bridge := NetworkBridge.new()
	parent.add_child(bridge)
	var view := NetworkWorldFixture.new()
	parent.add_child(view)
	view.setup(bridge)
	view.set_physics_process(false)
	var mine := ProjectileState.create_mine(101, 2, Vector2(300, 300))
	_deliver_delta(bridge, 200, 20, [mine], [])
	_deliver_correction(bridge, 190, 19, [])
	context.expect_true(view.replicated_visuals.authoritative_projectiles.get_projectile(101) != null, "older complete correction preserves a newer spawn")
	var recovered := ProjectileState.create_mine(102, 2, Vector2(400, 300))
	_deliver_correction(bridge, 195, 19, [recovered])
	context.expect_true(view.replicated_visuals.authoritative_projectiles.get_projectile(102) != null, "older recovery still fills a missing entity despite a newer unrelated delta")
	_deliver_delta(bridge, 210, 21, [], [101])
	_deliver_correction(bridge, 205, 20, [mine])
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(101), null, "older correction cannot resurrect a later removal")
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(102), null, "complete recovery still prunes genuinely stale entities")
	_deliver_delta(bridge, 200, 20, [mine], [])
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(101), null, "old delta cannot undo complete recovery or newer removal")
	var fresh := ProjectileState.create_mine(103, 2, Vector2(500, 300))
	_deliver_delta(bridge, 220, 22, [fresh], [])
	var moved := ProjectileState.create_mine(103, 2, Vector2(600, 300))
	_deliver_correction(bridge, 225, 23, [moved], false)
	_deliver_delta(bridge, 221, 22, [fresh], [])
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(103).position, moved.position, "older delta cannot rewind a newer partial correction")
	_deliver_delta(bridge, 226, 24, [mine], [101])
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(101), null, "same-batch removal wins over spawn")
	var many: Array[ProjectileState] = []
	for id in range(300, 350):
		many.append(ProjectileState.create_mine(id, id % 32 + 2, Vector2(700, 300)))
	_deliver_delta(bridge, 230, 25, many, [])
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.size(), 51, "all chunks of one delta sequence are accepted")
	var chunks := ProjectilePacketCodec.encode_correction_chunks(232, 26, many, true)
	bridge._accept_projectile_correction_chunk(ProjectilePacketCodec.decode_correction(chunks[0]))
	var interleaved := ProjectileState.create_mine(400, 2, Vector2(800, 300))
	_deliver_delta(bridge, 233, 27, [interleaved], [])
	for index in range(1, chunks.size()):
		bridge._accept_projectile_correction_chunk(ProjectilePacketCodec.decode_correction(chunks[index]))
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.size(), 51, "assembled recovery preserves a delta received between its chunks")
	context.expect_true(view.replicated_visuals.authoritative_projectiles.get_projectile(400) != null, "interleaved new entity survives old recovery assembly")
	view.apply_match_state({"state_name": "COUNTDOWN", "entered_tick": 300}, 300)
	_deliver_delta(bridge, 299, 28, [mine], [])
	context.expect_empty(view.replicated_visuals.authoritative_projectiles.all_projectiles(), "heat boundary rejects delayed prior-heat projectiles")
	_deliver_delta(bridge, 300, 29, [mine], [])
	context.expect_true(view.replicated_visuals.authoritative_projectiles.get_projectile(101) != null, "heat boundary accepts current-tick data")
	view.reset_session()
	_deliver_delta(bridge, 0xfffffffe, 0xffff, [mine], [])
	_deliver_delta(bridge, 1, 0, [], [101])
	_deliver_correction(bridge, 0xffffffff, 0xffff, [mine])
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(101), null, "tick wrap preserves removal ordering")
	view.reset_session()
	_deliver_delta(bridge, 10, 0xffff, [mine], [])
	_deliver_delta(bridge, 10, 0, [], [101])
	_deliver_correction(bridge, 10, 0xffff, [mine])
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.get_projectile(101), null, "same-tick message sequence wrap preserves removal ordering")
	_objective_ordering(context, view)
	view.free()
	bridge.free()
	var history := preload("res://src/client/network/projectile_replication_history.gd").new()
	for id in range(1, history.MAX_HISTORY + 2):
		history.record(id, history.stamp(id, id))
	history.finish_packet(history.stamp(5000, 5000))
	context.expect_true(history._versions.size() <= history.MAX_HISTORY, "recovery loss cannot grow projectile history without bound")
	context.expect_false(history.accepts_packet(history.stamp(1, 1)), "forgotten tombstones advance packet rejection floor")
	context.expect_true(history.accepts_packet(history.stamp(5001, 5001)), "bounded history continues accepting fresh recovery")


static func _deliver_delta(bridge: NetworkBridge, tick: int, sequence: int, spawned: Array[ProjectileState], removed: Array[int]) -> void:
	for packet in ProjectilePacketCodec.encode_batch_chunks(tick, sequence, spawned, removed):
		bridge.client_projectile_batch_received.emit(ProjectilePacketCodec.decode_batch(packet))


static func _deliver_correction(bridge: NetworkBridge, tick: int, sequence: int, active: Array[ProjectileState], complete: bool = true) -> void:
	for packet in ProjectilePacketCodec.encode_correction_chunks(tick, sequence, active, complete):
		bridge._accept_projectile_correction_chunk(ProjectilePacketCodec.decode_correction(packet))


static func _objective_ordering(context: TestContext, view: NetworkWorldFixture) -> void:
	view.reset_session()
	context.expect_true(view.apply_objective_state({"flag_carrier_id": 2}, 100), "objective transition establishes a version")
	context.expect_false(view.apply_objective_state({"flag_carrier_id": 0}, 99, true), "older periodic objective cannot undo a reliable transition")
	context.expect_true(view.apply_objective_state({"flag_carrier_id": 3}, 100, true), "same-tick final periodic objective supersedes an intermediate transition")
	context.expect_false(view.apply_objective_state({"flag_carrier_id": 2}, 100), "late intermediate transition cannot undo same-tick periodic state")
	view.apply_match_state({"state_name": "ACTIVE_HEAT", "objective": {"flag_carrier_id": 0}}, 99)
	context.expect_equal(view.match_payload.objective.flag_carrier_id, 3, "late reliable state retains newer objective observation")
	view.apply_match_state({"state_name": "COUNTDOWN", "entered_tick": 200, "objective": {"flag_carrier_id": 0}}, 200)
	context.expect_false(view.apply_objective_state({"flag_carrier_id": 3}, 199, true), "new heat rejects the prior heat objective")
	context.expect_false(view.apply_objective_state({"flag_carrier_id": 3}, 200, true), "full state wins over same-tick periodic objective")
	view.reset_session()
	view.apply_objective_state({"flag_carrier_id": 2}, 0xffffffff)
	context.expect_true(view.apply_objective_state({"flag_carrier_id": 3}, 0), "objective ordering handles server tick wrap")


static func _registry_invariants(context: TestContext, parent: Node) -> void:
	var view := NetworkWorldFixture.new()
	parent.add_child(view)
	view.set_physics_process(false)
	var stats := CombatStats.create_base()
	for id in range(1, 81):
		var shot := ProjectileState.create(id, 2, id, Vector2.ZERO, 0.0, stats)
		var reflected := ProjectileState.create(id, 3, id, Vector2.ZERO, 0.0, stats)
		view.replicated_visuals.authoritative_projectiles.add(shot)
		view.replicated_visuals._synchronize_projectile(shot, reflected)
		context.expect_equal(view.replicated_visuals.authoritative_projectiles.count_for_owner(2), 0, "reflection releases original owner membership")
		context.expect_equal(view.replicated_visuals.authoritative_projectiles.count_for_owner(3), 1, "reflection records new owner membership")
		view.replicated_visuals.authoritative_projectiles.remove(id)
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.count_for_owner(3), 0, "reflected removal clears new owner membership")
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.retained_owner_slot_count(), 0, "repeated reflection and removal leave no owner slots")
	context.expect_empty(view.replicated_visuals.authoritative_projectiles.add(ProjectileState.create(100, 2, 100, Vector2.ZERO, 0.0, stats)), "repeated reflections cannot evict a later shot from an empty registry")
	view.reset_session()
	context.expect_equal(view.replicated_visuals.authoritative_projectiles.count_for_owner(2), 0, "session reset clears all projectile memberships")
	view.free()
	var registry := ProjectileRegistry.new()
	registry.maximum_per_owner = 2
	registry.maximum_global = 2
	registry.add(ProjectileState.create(-1, 2, 1, Vector2.ZERO, 0.0, stats))
	registry.add(ProjectileState.create(-2, 2, 2, Vector2.ZERO, 0.0, stats))
	context.expect_equal(registry.add(ProjectileState.create(-3, 2, 3, Vector2.ZERO, 0.0, stats)), [-1], "owner budget can evict negative predicted IDs")
	context.expect_equal(registry.add(ProjectileState.create(-4, 3, 4, Vector2.ZERO, 0.0, stats)), [-2], "global budget can evict negative predicted IDs")
	context.expect_equal(registry.all_projectiles().size(), 2, "negative IDs remain enumerable after tombstone removal")


static func _shared_resource_identity(context: TestContext) -> void:
	for item in [
		["res://src/client/presentation/combat_ship_view.gd", "uid://b061orywmckq2"],
		["res://src/client/presentation/arena_view.gd", "uid://cdl15qj8tl3tx"],
		["res://src/client/presentation/projectile_layer.gd", "uid://b5j1hr2do1suh"],
	]:
		context.expect_equal(ResourceLoader.get_resource_uid(item[0]), ResourceUID.text_to_id(item[1]), "shared drawable move preserves resource identity: %s" % item[0])
