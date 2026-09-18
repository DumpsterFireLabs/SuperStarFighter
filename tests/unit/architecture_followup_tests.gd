extends RefCounted

const MatchState = preload("res://src/client/network/client_match_state.gd")
const ServerRuntime = preload("res://src/server/server_runtime.gd")
const SettingsStore = preload("res://src/client/settings_store.gd")


class SnapshotCountingCoordinator extends AuthoritativeMatchCoordinator:
	var snapshots: int = 0

	func current_state_payload() -> Dictionary:
		snapshots += 1
		return super.current_state_payload()


class SlowWriter extends "res://src/server/server_log_writer.gd":
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var writes: Array[String] = []

	func _write_output(text: String) -> void:
		if writes.is_empty():
			entered.post()
			release.wait()
		writes.append(text)


static func run(context: TestContext) -> void:
	_optional_observation(context)
	_overtime_logging(context)
	_shared_match_state(context)
	_presentation_membership(context)
	_slow_logging(context)
	_settings_sections(context)


static func _optional_observation(context: TestContext) -> void:
	var worlds: Array[AuthoritativeWorld] = []
	for enabled in [false, true]:
		var world := AuthoritativeWorld.new()
		world.set_silly_mode(enabled)
		world.add_peer(1)
		world.add_peer(2)
		world._record_shield_feedback(1, 2, "perfect_guard")
		world._resolve_damage_events([{"projectile_id": 1, "attacker_id": 1, "target_id": 2, "damage": 1000.0, "source": "missile"}])
		worlds.append(world)
	context.expect_equal(worlds[0].combatants[2].health, worlds[1].combatants[2].health, "optional cues never change authoritative damage")
	var ordinary := worlds[0].drain_combat_feedback()
	var enabled := worlds[1].drain_combat_feedback()
	context.expect_equal(ordinary[1].hit_count, enabled[1].hit_count, "disabled cues preserve ordinary hit feedback")
	context.expect_equal(ordinary[2].death, enabled[2].death, "disabled cues preserve death attribution")
	context.expect_true(ordinary[2].guard_count > 0, "disabled cues preserve guard feedback")
	context.expect_false(ordinary[2].has("silly_cue"), "disabled matches emit no hitless-death cue")
	context.expect_true(enabled[2].has("silly_cue"), "enabled matches retain cue policy")
	context.expect_true(worlds[0].silly_observer == null, "disabled worlds allocate no optional observation history")
	worlds[1].set_silly_mode(false)
	context.expect_true(worlds[1].silly_observer == null, "disabling releases cue history")
	worlds[1].set_silly_mode(true)
	context.expect_empty(worlds[1].silly_observer._silly_recent_damage, "reenabling cannot inherit old cue eligibility")
	var lobby := ServerLobby.new()
	lobby.config.silly_mode = true
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, worlds[0], 5)
	context.expect_true(worlds[0].silly_observer != null, "match configuration enables the authority observer")
	lobby.config.silly_mode = false
	coordinator = AuthoritativeMatchCoordinator.new(lobby, worlds[0], 6)
	context.expect_true(worlds[0].silly_observer == null, "a subsequent ordinary match disables the previous observer")
	var records := coordinator._elimination_records([2], [{"killer_id": 1, "target_id": 2, "silly_cue": "nope"}])
	context.expect_false(records[0].has("silly_cue"), "disabled coordination does not relay optional elimination cues")


static func _overtime_logging(context: TestContext) -> void:
	var world := AuthoritativeWorld.new()
	var coordinator := SnapshotCountingCoordinator.new(ServerLobby.new(), world, 7, 1.0)
	coordinator.machine.state = MatchStateMachine.State.ACTIVE_HEAT
	coordinator.machine.state_entered_tick = 100
	coordinator.machine.round_number = 1
	coordinator.machine.heat_number = 1
	var bridge := NetworkBridge.new()
	bridge.world = world
	bridge.match_coordinator = coordinator
	var lines: Array[String] = []
	bridge.log_output = func(line: String) -> void: lines.append(line)
	world.server_tick = 159
	bridge._log_overtime_if_needed()
	context.expect_empty(lines, "overtime logging waits for the deadline")
	world.server_tick = 160
	for tick in 120:
		bridge._log_overtime_if_needed()
	context.expect_equal(lines.size(), 1, "overtime is logged once per heat")
	context.expect_equal(JSON.parse_string(lines[0]).server_tick, 160, "overtime record preserves its trigger tick")
	coordinator.machine.heat_number = 2
	coordinator.machine.state_entered_tick = 200
	world.server_tick = 260
	bridge._log_overtime_if_needed()
	context.expect_equal(lines.size(), 2, "the next heat gets its own overtime record")
	context.expect_equal(JSON.parse_string(lines[1]).heat, 2, "overtime record preserves heat identity")
	context.expect_equal(coordinator.snapshots, 0, "overtime logging never serializes a full match snapshot")
	bridge.free()


static func _shared_match_state(context: TestContext) -> void:
	var state := MatchState.new()
	var source := {"builds": {1: {&"reinforced_hull": 1}}, "alive_peer_ids": [1]}
	state.replace(source)
	source.builds[1].clear()
	context.expect_equal(state.payload.builds[1][&"reinforced_hull"], 1, "match state detaches incoming nested builds")
	context.expect_true(state.payload.is_read_only() and state.payload.builds[1].is_read_only() and state.payload.alive_peer_ids.is_read_only(), "shared observations are recursively read-only")
	var notifications := [0]
	state.changed.connect(func() -> void: notifications[0] += 1)
	var retained := state.payload
	var replacements := {"objective": {"progress": [{"points": 4}]}, "alive_peer_ids": [1, 2]}
	state.update_fields(replacements)
	replacements.objective.progress[0].points = 99
	replacements.alive_peer_ids.clear()
	context.expect_equal(state.payload.objective.progress[0].points, 4, "field updates detach deeply aliased incoming dictionaries and arrays")
	context.expect_equal(state.payload.alive_peer_ids, [1, 2], "field updates detach replaced arrays")
	context.expect_true(state.payload.objective.progress.is_read_only() and state.payload.objective.progress[0].is_read_only(), "replacement containers reject nested mutation")
	context.expect_true(retained.alive_peer_ids == [1] and not retained.has("objective"), "retained observations keep earlier arrays and root membership")
	context.expect_equal(notifications[0], 1, "a batched field update emits one UI invalidation")
	state.apply_objective({"progress": 10}, 20, true)
	context.expect_false(state.apply_objective({"progress": 9}, 19), "older objective update is rejected")
	context.expect_false(state.apply_objective({"progress": 0}, 20), "same-tick lower priority objective update is rejected")
	context.expect_equal(notifications[0], 2, "rejected objective updates do not invalidate UI")
	state.replace({"objective": {"progress": -1}, "builds": {1: {&"reinforced_hull": 1}}}, 19)
	context.expect_equal(state.payload.objective.progress, 10, "older full state preserves the newer objective while refreshing builds")
	state.reset()
	context.expect_true(state.apply_objective({"progress": 1}, 1), "reset accepts a new session with earlier ticks")
	state.replace({"builds": {1: {&"reinforced_hull": 1}}})
	var old := state.payload
	state.update_fields({"builds": {1: {&"twin_shot": 2}}})
	context.expect_true(old.builds[1].has(&"reinforced_hull"), "an earlier observation remains stable after publication")
	var view := NetworkWorldView.new()
	view.match_state = state
	view.local_peer_id = 1
	view.apply_builds({1: {&"reinforced_hull": 2}})
	context.expect_equal(state.payload.builds[1][&"reinforced_hull"], 2, "world build updates publish to the shared screen state owner")
	context.expect_true(view.local_prediction.local_stats.max_health > 100.0, "prediction derives from the published build")
	context.expect_true(view.local_prediction.context == view.replicated_visuals.context, "presentation owners share session observations without the coordinating view")
	view.reset_session()
	context.expect_empty(state.payload, "session reset clears the shared screen and world observation together")
	view.free()


static func _presentation_membership(context: TestContext) -> void:
	var authority := ProjectileRegistry.new()
	var visuals := ProjectileRegistry.presentation_store()
	for id in range(1, GameConstants.MAX_PROJECTILES_PER_OWNER + 2):
		authority.add(ProjectileState.create(id, 1, id, Vector2.ZERO, 0.0, CombatStats.create_base()))
		visuals.add(ProjectileState.create(id, 1, id, Vector2.ZERO, 0.0, CombatStats.create_base()))
	visuals.add(ProjectileState.create(-1, 1, 100, Vector2.ZERO, 0.0, CombatStats.create_base()))
	context.expect_equal(authority.size(), GameConstants.MAX_PROJECTILES_PER_OWNER, "authority still enforces the combat projectile allowance")
	context.expect_true(visuals.get_projectile(1) != null and visuals.get_projectile(-1) != null, "speculation and reordered membership do not evict authoritative presentation")
	visuals.transfer_owner(1, 2)
	context.expect_equal(visuals.count_for_owner(2), 1, "presentation storage retains indexed ownership without budget policy")
	context.expect_equal(visuals.budget_evictions, 0, "presentation never makes independent authority budget decisions")


static func _slow_logging(context: TestContext) -> void:
	var parent := Node.new()
	var runtime := ServerRuntime.new()
	var writer := SlowWriter.new()
	var bridge := runtime.attach(parent, writer)
	bridge._log("info", "blocked_sink")
	writer.entered.wait()
	# The worker is deliberately blocked until after the producer returns.
	bridge._log("info", "while_sink_blocked")
	context.expect_equal(bridge.log_status.call().queued_batches, 1, "shared runtime accepts logs while its output sink is blocked")
	writer.release.post()
	runtime.stop()
	context.expect_equal(writer.writes.size(), 2, "runtime shutdown drains all queued records")
	context.expect_false(writer._thread.is_started(), "shared runtime joins its worker before disposing transport nodes")
	context.expect_false(bridge.log_output.is_valid(), "shutdown detaches worker callbacks")
	runtime.stop()
	parent.free()


static func _settings_sections(context: TestContext) -> void:
	var path := "res://.tools/architecture-settings-%d.cfg" % Time.get_ticks_usec()
	context.expect_equal(SettingsStore.update(func(config: ConfigFile) -> void:
		config.set_value("audio", "master", 37)
	, path), OK, "settings store creates an absent settings file")
	context.expect_equal(SettingsStore.update(func(config: ConfigFile) -> void:
		config.set_value("video", "width", 1600)
	, path), OK, "settings store saves a separate preference section")
	var result := ConfigFile.new()
	result.load(path)
	context.expect_equal(result.get_value("audio", "master"), 37, "saving video settings preserves audio preferences")
	context.expect_equal(result.get_value("video", "width"), 1600, "settings store commits the requested preference")
	DirAccess.remove_absolute(path)
