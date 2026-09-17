extends RefCounted


static func run(context: TestContext, parent: Node) -> void:
	var bridge := NetworkBridge.new()
	parent.add_child(bridge)
	var view := NetworkWorldFixture.new()
	parent.add_child(view)
	view.setup(bridge)
	view.set_physics_process(false)
	view.local_peer_id = 1
	view.input_blocked = true
	view.apply_match_state({"state_name": "ACTIVE_HEAT"})
	var world := AuthoritativeWorld.new()
	var pilot := world.add_peer(1)
	pilot.position = Vector2(300, 300)
	var remote := world.add_peer(2)
	remote.position = Vector2(1200, 800)
	_snapshot(view, world, 1)
	context.expect_equal(view.hud_camera.camera.position, pilot.position, "initial living snapshot places camera at the local spawn")
	pilot.alive = false
	pilot.health = 0.0
	_snapshot(view, world, 4)
	context.expect_equal(view.hud_camera.spectator_target_id, 2, "death selects the surviving spectator target")
	context.expect_true(view.hud_camera.camera_shake_remaining > 0.0, "local elimination retains its brief impact shake")
	var largest_snapshot_jump := 0.0
	for tick in range(7, 128, 3):
		for frame in 3:
			view._physics_process(1.0 / 60.0)
			(view.replicated_visuals.ships[1] as CombatShipView)._process(1.0 / 60.0)
		var before := view.hud_camera.camera.position
		_snapshot(view, world, tick)
		largest_snapshot_jump = maxf(largest_snapshot_jump, before.distance_to(view.hud_camera.camera.position))
	context.expect_approx(largest_snapshot_jump, 0.0, "repeated dead snapshots cannot pull the spectator camera back to the corpse")
	context.expect_true(view.hud_camera.camera.position.distance_to(remote.position) < 1.0, "spectator camera settles on the survivor across continuing snapshots")
	context.expect_approx(view.hud_camera.camera_shake_remaining, 0.0, "elimination shake expires while spectating")
	context.expect_true(view.hud_camera.camera.offset.length() < 0.01, "spectator camera has no persistent impact offset")
	context.expect_approx((view.replicated_visuals.ships[1] as CombatShipView).elimination_pulse_remaining, 0.0, "dead snapshots do not restart the elimination animation indefinitely")
	remote.alive = false
	_snapshot(view, world, 130)
	context.expect_equal(view.hud_camera.spectator_target_id, 0, "no survivors selects the arena view")
	view._physics_process(1.0 / 60.0)
	var arena_view_position := view.hud_camera.camera.position
	_snapshot(view, world, 133)
	context.expect_equal(view.hud_camera.camera.position, arena_view_position, "dead snapshots also leave the arena camera alone")
	world.respawn_peer(1, pilot.stats, Vector2(600, 400))
	_snapshot(view, world, 136)
	context.expect_equal(view.hud_camera.camera.position, pilot.position, "respawn restores the camera to the new local spawn")
	context.expect_equal(view.hud_camera.spectator_target_id, 0, "respawn leaves spectator mode")
	# A late spectator's first snapshot is dead too: it must not center on
	# the placeholder ship before the spectator camera takes over.
	view.reset_session()
	view.local_peer_id = 1
	pilot.alive = false
	var initial_arena_position := view.hud_camera.camera.position
	_snapshot(view, world, 139)
	context.expect_equal(view.hud_camera.camera.position, initial_arena_position, "initial dead snapshot preserves the late spectator's arena camera")
	parent.remove_child(view)
	view.free()
	parent.remove_child(bridge)
	bridge.free()


static func _snapshot(view: NetworkWorldFixture, world: AuthoritativeWorld, tick: int) -> void:
	var pilot := world.combatants[1] as CombatantState
	view._on_snapshot(PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(tick, 0, world.snapshot_states(), pilot.prediction_state())))
