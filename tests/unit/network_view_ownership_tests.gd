extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	_shared_resource_identity(context)
	var bridge := NetworkBridge.new()
	parent.add_child(bridge)
	var view := NetworkWorldView.new()
	parent.add_child(view)
	view.setup(bridge)
	view.set_physics_process(false)
	view.local_peer_id = 1
	var prediction_owner := view.local_prediction
	var visual_owner := view.replicated_visuals
	var hud_owner := view.hud_camera
	var draw_layers: Array[Node] = [view.arena, view.projectile_layer, view.effects_layer, view.powerup_layer, view.camera, view.hud_root]
	context.expect_empty(view.find_children("*", "SubViewport", true, false), "network ownership creates no additional render targets")
	view.apply_match_state({"state_name": "ACTIVE_HEAT", "teams": {1: 1, 2: 2}, "game_mode": GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG})
	context.expect_equal(view.arena.local_peer_id, 1, "match coordination passes local identity into shared arena")
	context.expect_equal(view.arena.local_team_id, 1, "match coordination passes team identity into shared arena")
	var authority := AuthoritativeWorld.new()
	var pilot := authority.add_peer(1)
	pilot.position = Vector2(300, 300)
	pilot.weapon.ammunition = 3
	pilot.weapon.cooldown_remaining = 0.25
	pilot.afterburner_cooldown_remaining = 1.5
	var remote := authority.add_peer(2)
	remote.position = Vector2(1000, 700)
	_emit_snapshot(bridge, authority, 10)
	context.expect_true(view.prediction_initialized, "snapshot initializes local prediction through owner")
	context.expect_equal(view.local_weapon.ammunition, 3, "private correction and public resources reach local weapon")
	context.expect_approx(view.local_special_cooldown_remaining, 1.5, "private cooldown survives codec and prediction owner")
	context.expect_equal(view.local_active_ordnance, 7, "private ordnance usage reaches local prediction")
	context.expect_true(view.interpolation.sample(2, view._now_seconds()).ok, "remote snapshot reaches interpolation owner")
	context.expect_equal(view.ships, visual_owner.ships, "compatibility dictionary exposes authoritative visual ownership")
	var local_ship := view.ships[1] as CombatShipView
	var child_count := view.get_child_count()
	view.input_blocked = true
	for unused in 8:
		view._physics_process(1.0 / 60.0)
	context.expect_equal(view.input_sequence, 8, "each physics frame advances owned input sequence")
	context.expect_equal(view.get_child_count(), child_count, "steady presentation frames do not create drawable nodes")
	context.expect_equal(view.local_prediction, prediction_owner, "physics retains prediction owner")
	context.expect_equal(view.replicated_visuals, visual_owner, "physics retains replicated visual owner")
	context.expect_equal(view.hud_camera, hud_owner, "physics retains HUD camera owner")
	context.expect_equal(view.ships[1], local_ship, "physics preserves local drawable identity")
	_projectile_reconciliation(context, view, bridge, local_ship)
	remote.cloak_remaining = 5.0
	_emit_snapshot(bridge, authority, 13)
	context.expect_false(view.ships.has(2), "cloak omission removes replicated drawable")
	context.expect_false(view.presentation_states.has(2), "cloak omission clears damage feedback history")
	context.expect_false(view.interpolation.sample(2, view._now_seconds()).ok, "cloak omission clears interpolation history")
	context.expect_false(view._living_spectator_targets().has(2), "HUD cannot target a cloaked omitted pilot")
	remote.cloak_remaining = 0.0
	remote.position = Vector2(1200, 800)
	_emit_snapshot(bridge, authority, 16)
	context.expect_equal((view.ships[2] as CombatShipView).global_position, remote.position, "revealed drawable starts at fresh authoritative location")
	view.apply_match_state({"state_name": "COUNTDOWN"})
	context.expect_false(view.prediction_initialized, "countdown requires a fresh local prediction baseline")
	context.expect_empty(view.presentation_states, "countdown clears previous heat feedback")
	context.expect_false(view.interpolation.sample(2, view._now_seconds()).ok, "countdown clears previous heat interpolation")
	context.expect_equal(view.ships[1], local_ship, "countdown retains existing ships for authoritative respawn")
	view.camera_shake_remaining = 1.0
	view.camera.offset = Vector2(10, 10)
	view._nearest_incoming_cache = ProjectileState.create(99, 2, 1, Vector2(500, 300), 0.0, view.local_stats)
	view.reset_match_presentation()
	context.expect_equal(view.local_peer_id, 1, "fresh match reset retains connected local identity")
	context.expect_equal(view.input_sequence, 8, "fresh match reset retains input sequence")
	context.expect_equal(view.client_tick, 8, "fresh match reset retains client tick")
	context.expect_empty(view.ships, "fresh match clears prior combatant drawables")
	context.expect_empty(view.authoritative_projectiles.all_projectiles(), "fresh match clears authoritative and predicted projectiles")
	context.expect_empty(view.predicted_projectile_ids, "fresh match clears pending volley ownership")
	context.expect_equal(view.local_active_ordnance, 0, "fresh match clears private ordnance state")
	context.expect_equal(view.camera.offset, Vector2.ZERO, "fresh match clears camera shake offset")
	context.expect_equal(view._nearest_incoming_cache, null, "fresh match clears incoming projectile cache")
	context.expect_equal([view.arena, view.projectile_layer, view.effects_layer, view.powerup_layer, view.camera, view.hud_root], draw_layers, "fresh match reuses drawing layers and HUD surfaces")
	view.reset_session()
	context.expect_equal(view.local_peer_id, 0, "disconnect reset clears local identity")
	context.expect_equal(view.input_sequence, 0, "disconnect reset clears local input sequence")
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


static func _projectile_reconciliation(context: TestContext, view: NetworkWorldView, bridge: NetworkBridge, ship: CombatShipView) -> void:
	view.local_weapon.shot_sequence = 11
	view._spawn_predicted_projectile(ship, 0.0)
	context.expect_true(view.authoritative_projectiles.get_projectile(-1) != null, "local shot creates a predicted drawable")
	var authoritative := ProjectileState.create(101, 1, 11, ship.global_position + Vector2(31, 0), 0.0, view.local_stats)
	var chunks := ProjectilePacketCodec.encode_batch_chunks(11, 1, [authoritative], [])
	bridge.client_projectile_batch_received.emit(ProjectilePacketCodec.decode_batch(chunks[0]))
	context.expect_equal(view.authoritative_projectiles.get_projectile(-1), null, "authoritative delta removes predicted duplicate")
	context.expect_equal(view.authoritative_projectiles.all_projectiles().size(), 1, "authoritative delta retains one shot drawable")
	view.local_weapon.shot_sequence = 12
	view._spawn_predicted_projectile(ship, 0.0)
	var corrected := ProjectileState.create(102, 1, 12, ship.global_position + Vector2(50, 0), 0.0, view.local_stats)
	chunks = ProjectilePacketCodec.encode_correction_chunks(12, 2, [corrected], true)
	bridge.client_projectile_correction_received.emit(ProjectilePacketCodec.decode_correction(chunks[0]))
	context.expect_empty(view.predicted_projectile_ids, "full correction reconciles lost shot delta")
	context.expect_equal(view.authoritative_projectiles.all_projectiles().size(), 1, "full correction prunes stale authoritative shot and prediction")
	context.expect_true(view.authoritative_projectiles.get_projectile(102) != null, "corrected authoritative shot remains drawable")


static func _shared_resource_identity(context: TestContext) -> void:
	for item in [
		["res://src/client/presentation/combat_ship_view.gd", "uid://b061orywmckq2"],
		["res://src/client/presentation/arena_view.gd", "uid://cdl15qj8tl3tx"],
		["res://src/client/presentation/projectile_layer.gd", "uid://b5j1hr2do1suh"],
	]:
		context.expect_equal(ResourceLoader.get_resource_uid(item[0]), ResourceUID.text_to_id(item[1]), "shared drawable move preserves resource identity: %s" % item[0])
