extends Node

const SAMPLE_TICKS: int = 120
const WARMUP_TICKS: int = 20
# This fixture deliberately combines the 32-combatant and 1,024-projectile
# ceilings. It is a defensive overload gate, not the normal-match frame target.
const P95_BUDGET_USEC: int = 20_000
const P99_BUDGET_USEC: int = 24_000
const MAXIMUM_BUDGET_USEC: int = 30_000

var _next_projectile_id: int = 1


func _ready() -> void:
	var world := AuthoritativeWorld.new()
	var npc_controller := NpcPilotController.new()
	world.performance_profiling_enabled = true
	var npc_ids: Array[int] = []
	var difficulties: Dictionary = {}
	var anchors := ArenaLayout.spawn_anchors(world.map_id)
	for index in GameConstants.MAX_PLAYERS:
		var peer_id := ServerLobby.NPC_PEER_ID_BASE + index + 1
		var combatant := world.add_peer(peer_id)
		combatant.position = anchors[index % anchors.size()]
		npc_ids.append(peer_id)
		difficulties[peer_id] = NpcPilotController.Difficulty.INSANE
	_fill_projectiles(world, npc_ids)
	var samples: Array[int] = []
	var phase_totals := {"npc": 0, "movement": 0, "overlaps": 0, "projectiles": 0, "cleanup_and_threats": 0}
	var maximum_projectiles := world.projectile_registry.size()
	for tick in SAMPLE_TICKS + WARMUP_TICKS:
		var started_usec := Time.get_ticks_usec()
		npc_controller.submit_inputs(world, npc_ids, difficulties)
		var npc_complete_usec := Time.get_ticks_usec()
		world.step(1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND)
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		world.drain_projectile_batch()
		_fill_projectiles(world, npc_ids)
		maximum_projectiles = maxi(maximum_projectiles, world.projectile_registry.size())
		if tick >= WARMUP_TICKS:
			samples.append(elapsed_usec)
			phase_totals.npc = int(phase_totals.npc) + npc_complete_usec - started_usec
			for phase in ["movement", "overlaps", "projectiles", "cleanup_and_threats"]:
				phase_totals[phase] = int(phase_totals[phase]) + int(world.last_step_profile_usec.get(phase, 0))
	samples.sort()
	var p50 := _percentile(samples, 0.50)
	var p95 := _percentile(samples, 0.95)
	var p99 := _percentile(samples, 0.99)
	var maximum: int = samples.back() if not samples.is_empty() else 0
	print("SSF_PERFORMANCE_RESULT p50_usec=%d p95_usec=%d p99_usec=%d max_usec=%d projectiles=%d npcs=%d" % [
		p50, p95, p99, maximum, maximum_projectiles, npc_ids.size(),
	])
	print("SSF_PERFORMANCE_PHASES npc=%d movement=%d overlaps=%d projectiles=%d cleanup_and_threats=%d" % [
		int(phase_totals.npc) / SAMPLE_TICKS,
		int(phase_totals.movement) / SAMPLE_TICKS,
		int(phase_totals.overlaps) / SAMPLE_TICKS,
		int(phase_totals.projectiles) / SAMPLE_TICKS,
		int(phase_totals.cleanup_and_threats) / SAMPLE_TICKS,
	])
	if maximum_projectiles != GameConstants.MAX_PROJECTILES_GLOBAL:
		push_error("Performance fixture did not maintain the global projectile ceiling.")
		get_tree().quit(1)
	elif p95 > P95_BUDGET_USEC:
		push_error("Performance p95 %d usec exceeds the %d usec overload budget." % [p95, P95_BUDGET_USEC])
		get_tree().quit(1)
	elif p99 > P99_BUDGET_USEC:
		push_error("Performance p99 %d usec exceeds the %d usec overload budget." % [p99, P99_BUDGET_USEC])
		get_tree().quit(1)
	elif maximum > MAXIMUM_BUDGET_USEC:
		push_error("Performance maximum %d usec exceeds the %d usec overload budget." % [maximum, MAXIMUM_BUDGET_USEC])
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _fill_projectiles(world: AuthoritativeWorld, owner_ids: Array[int]) -> void:
	var stats := CombatStats.create_base()
	stats.projectile_damage = 0.0
	stats.projectile_lifetime = 12.0
	stats.projectile_speed = 1200.0
	stats.pierce_count = GameConstants.MAX_PLAYERS
	stats.ricochet_count = 4
	while world.projectile_registry.size() < GameConstants.MAX_PROJECTILES_GLOBAL:
		var owner_id := owner_ids[(_next_projectile_id - 1) % owner_ids.size()]
		var lane := (_next_projectile_id - 1) % 64
		var row := (_next_projectile_id - 1) / 64.0
		var position := Vector2(80.0 + lane * 48.0, 90.0 + posmod(row, 18) * 94.0)
		var angle := float(posmod(_next_projectile_id * 47, 360)) * PI / 180.0
		var projectile := ProjectileState.create(_next_projectile_id, owner_id, _next_projectile_id, position, angle, stats)
		world.projectile_registry.add(projectile)
		_next_projectile_id += 1


func _percentile(sorted_samples: Array[int], percentile: float) -> int:
	if sorted_samples.is_empty():
		return 0
	var index := ceili(clampf(percentile, 0.0, 1.0) * sorted_samples.size()) - 1
	return sorted_samples[clampi(index, 0, sorted_samples.size() - 1)]
