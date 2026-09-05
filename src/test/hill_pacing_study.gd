extends SceneTree

## Paired exploratory experiments using production combat, drafting and objectives.
## Alternative profiles are test-only; they never affect a running game.
class LegacyLimit extends AuthoritativeMatchCoordinator:
	func heat_end_tick() -> int:
		return machine.state_entered_tick + roundi((overtime_start_seconds + 60.0) * GameConstants.PHYSICS_TICKS_PER_SECOND)

class TargetExperiment extends HillModeHandler:
	var target_seconds: float = 20.0
	func step(delta: float, world: AuthoritativeWorld, alive_ids: Array[int], observations: MatchObservations) -> ObjectiveStepResult:
		var result := super.step(delta, world, alive_ids, observations)
		if state.controller_id != 0 and state.progress.get(state.controller_id, 0.0) >= target_seconds:
			result.winner_peer_id = state.controller_id
		return result

class RespawnExperiment extends LegacyLimit:
	var respawn_seconds: float = 5.0
	func _sync_combat_and_resolve(tick: int) -> void:
		var already_scheduled := _respawn_deadlines.duplicate()
		super._sync_combat_and_resolve(tick)
		for peer_id in _respawn_deadlines:
			if not already_scheduled.has(peer_id):
				_respawn_deadlines[peer_id] = tick + lobby.config.duration_to_ticks(respawn_seconds)

class DeadlineExperiment extends AuthoritativeMatchCoordinator:
	func heat_end_tick() -> int:
		var overtime_limit := 30.0 if machine.participant_ids().size() >= 8 else GameConstants.OVERTIME_TIME_LIMIT_SECONDS
		return machine.state_entered_tick + roundi((overtime_start_seconds + overtime_limit) * GameConstants.PHYSICS_TICKS_PER_SECOND)

var profile: String = "production"
var seed_count: int = 3
var output_path: String = "res://reports/hill-pacing.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profile = arg.trim_prefix("--profile=")
		if arg.begins_with("--seeds="): seed_count = clampi(int(arg.trim_prefix("--seeds=")), 1, 20)
		if arg.begins_with("--output="): output_path = arg.trim_prefix("--output=")
	if profile not in ["production", "legacy-limit", "short-target", "slow-respawn", "crowded-limit"]:
		push_error("Unknown hill experiment profile")
		quit(1)
		return
	var rows: Array[Dictionary] = []
	for count in [2, 8, 32]:
		for map_id in [&"core_arena", &"dead_freight", &"solar_tide"]:
			for seed_index in seed_count:
				var row := _case(count, map_id, 7100 + seed_index)
				rows.append(row)
				print("SSF_HILL_CASE %s" % JSON.stringify(row))
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write hill pacing report")
		quit(1)
		return
	file.store_string(JSON.stringify({"profile": profile, "seed_count": seed_count, "rows": rows,
		"limitations": "One opening heat per map/population/seed; deterministic skilled NPCs with automatic drafting. Not human balance or FPS evidence."}, "\t") + "\n")
	print("SSF_HILL_STUDY_COMPLETE profile=%s rows=%d" % [profile, rows.size()])
	quit(0)


func _case(count: int, map_id: StringName, match_seed: int) -> Dictionary:
	var config := MatchConfig.new()
	config.max_players = count
	config.game_mode = GameModeRules.Mode.KING_OF_THE_HILL
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	var ids: Array[int] = []
	var difficulties: Dictionary = {}
	for peer_id in range(2, count + 2):
		lobby.admit(peer_id, "Study%d" % peer_id)
		var player := lobby.players[peer_id] as PlayerMatchState
		player.is_npc = true
		player.npc_difficulty = NpcPilotController.Difficulty.SKILLED
		player.lobby_ready = true
		world.add_peer(peer_id)
		ids.append(peer_id)
		difficulties[peer_id] = player.npc_difficulty
	var coordinator: AuthoritativeMatchCoordinator
	if profile == "crowded-limit":
		coordinator = DeadlineExperiment.new(lobby, world, match_seed)
	elif profile in ["legacy-limit", "short-target"]:
		coordinator = LegacyLimit.new(lobby, world, match_seed)
	elif profile == "slow-respawn":
		var experiment := RespawnExperiment.new(lobby, world, match_seed)
		experiment.respawn_seconds = 5.0 if count == 2 else 8.0 if count == 8 else 12.0
		coordinator = experiment
	else:
		coordinator = AuthoritativeMatchCoordinator.new(lobby, world, match_seed)
	if profile == "short-target":
		var experiment := TargetExperiment.new()
		experiment.target_seconds = 20.0 if count == 2 else 10.0 if count == 8 else 5.0
		coordinator._hill = experiment
	# Pin the opening map without changing production map selection.
	coordinator._map_rotation.assign([map_id])
	coordinator.start(0)
	var npc := NpcPilotController.new()
	var occupancy_ticks := {"empty": 0, "solo": 0, "contested": 0}
	var time_limit := false
	for unused_tick in 9000:
		var active := coordinator.controls_enabled()
		if active:
			npc.submit_inputs(world, ids, difficulties, coordinator.npc_overtime_elapsed(), coordinator.npc_objective_state())
		world.step(1.0 / 60.0, active)
		coordinator.step(1.0 / 60.0)
		if active:
			var state := coordinator._hill.state
			occupancy_ticks["contested" if state.contested else "solo" if state.controller_id != 0 else "empty"] += 1
		world.drain_projectile_batch()
		world.drain_combat_feedback()
		for event in coordinator.drain_events():
			if event.event_type == &"STATE_CHANGED" and event.payload.get("state_name", "") == "HEAT_RESULT":
				time_limit = bool(event.payload.get("heat_time_limit_reached", false))
		if not coordinator.observations.heats.is_empty():
			break
	var heat: Dictionary = coordinator.observations.heats[0].duplicate(true) if not coordinator.observations.heats.is_empty() else {}
	return {"players": count, "map": String(map_id), "seed": match_seed, "incomplete": heat.is_empty(),
		"time_limit": time_limit, "occupancy_ticks": occupancy_ticks, "progress": coordinator._hill.state.progress.duplicate(), "heat": heat}
