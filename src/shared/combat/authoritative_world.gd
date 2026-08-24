class_name AuthoritativeWorld
extends RefCounted

var server_tick: int = 0
var combatants: Dictionary = {}
var latest_inputs: Dictionary = {}
var acknowledged_inputs: Dictionary = {}
var projectile_registry := ProjectileRegistry.new()
var _next_projectile_id: int = 1
var _spawned_since_batch: Array[ProjectileState] = []
var _removed_since_batch: Array[int] = []


func add_peer(peer_id: int, stats: CombatStats = null) -> CombatantState:
	if combatants.has(peer_id):
		return combatants[peer_id] as CombatantState
	var anchors := ArenaLayout.spawn_anchors()
	var spawn_index := combatants.size() % anchors.size()
	var combat_stats := stats if stats != null else CombatStats.create_base()
	var combatant := CombatantState.create(peer_id, combat_stats, anchors[spawn_index])
	combatants[peer_id] = combatant
	latest_inputs[peer_id] = PlayerInputFrame.new()
	acknowledged_inputs[peer_id] = 0
	return combatant


func remove_peer(peer_id: int) -> void:
	combatants.erase(peer_id)
	latest_inputs.erase(peer_id)
	acknowledged_inputs.erase(peer_id)
	projectile_registry.schedule_owner_cleanup(peer_id)


func submit_input(peer_id: int, frame: PlayerInputFrame) -> bool:
	if not combatants.has(peer_id) or not frame.is_valid():
		return false
	var previous := latest_inputs.get(peer_id) as PlayerInputFrame
	if previous != null and acknowledged_inputs.has(peer_id):
		var previous_sequence := int(acknowledged_inputs[peer_id])
		if frame.sequence == previous_sequence or not SequenceMath.is_newer(frame.sequence, previous_sequence):
			return false
	latest_inputs[peer_id] = frame
	acknowledged_inputs[peer_id] = frame.sequence
	return true


func step(delta: float, controls_enabled: bool = true) -> void:
	server_tick = SequenceMath.increment(server_tick)
	if not controls_enabled:
		return
	var peer_ids := _ordered_peer_ids()
	for peer_id in peer_ids:
		var combatant := combatants[peer_id] as CombatantState
		if not combatant.alive:
			continue
		var frame := latest_inputs[peer_id] as PlayerInputFrame
		var world_movement := MovementSystem.ship_relative_to_world(frame.movement, frame.aim_angle)
		combatant.step(world_movement, frame.aim_angle, frame.shielding, delta)
		var motion := ArenaCollisionSystem.move_ship(combatant.position, combatant.velocity, delta)
		combatant.position = motion.position
		combatant.velocity = motion.velocity
		if frame.firing and combatant.try_fire():
			_spawn_shot(combatant)
	_resolve_ship_overlaps(peer_ids)
	_step_projectiles(delta, peer_ids)
	for projectile_id in projectile_registry.step_cleanup(delta):
		_record_removed(projectile_id)


func prepare_heat(
	participant_stats: Dictionary,
	spawn_assignments: Dictionary
) -> void:
	clear_projectiles()
	for peer_id in _ordered_peer_ids():
		var combatant := combatants[peer_id] as CombatantState
		if participant_stats.has(peer_id) and spawn_assignments.has(peer_id):
			combatant.reset_for_heat(
				participant_stats[peer_id] as CombatStats,
				spawn_assignments[peer_id] as Vector2
			)
		else:
			combatant.alive = false
			combatant.health = 0.0
			combatant.velocity = Vector2.ZERO
			combatant.shield.active = false


func set_spectator(peer_id: int) -> void:
	var combatant := combatants.get(peer_id) as CombatantState
	if combatant == null:
		return
	combatant.alive = false
	combatant.health = 0.0
	combatant.velocity = Vector2.ZERO
	combatant.shield.active = false


func clear_projectiles() -> void:
	for projectile in projectile_registry.all_projectiles():
		_remove_projectile(projectile.projectile_id)


func apply_overtime(heat_elapsed: float, delta: float) -> Array[int]:
	var damage_events: Array[Dictionary] = []
	for peer_id in _ordered_peer_ids():
		var combatant := combatants[peer_id] as CombatantState
		if not combatant.alive:
			continue
		var damage := OvertimeSystem.damage_for_position(
			combatant.position,
			heat_elapsed,
			delta
		)
		if damage > 0.0:
			damage_events.append({
				"projectile_id": 2_000_000_000 + peer_id,
				"target_id": peer_id,
				"damage": damage,
			})
	var deaths := DamageResolver.resolve_tick(combatants, damage_events)
	for peer_id in deaths:
		projectile_registry.schedule_owner_cleanup(peer_id)
	return deaths


func snapshot_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for peer_id in _ordered_peer_ids():
		var combatant := combatants[peer_id] as CombatantState
		states.append({
			"peer_id": peer_id,
			"position": combatant.position,
			"velocity": combatant.velocity,
			"aim_angle": combatant.aim_angle,
			"health": combatant.health,
			"shield": combatant.shield.energy,
			"ammunition": combatant.weapon.ammunition,
			"alive": combatant.alive,
			"shielding": combatant.shield.active,
		})
	return states


func acknowledged_input(peer_id: int) -> int:
	return int(acknowledged_inputs.get(peer_id, 0))


func drain_projectile_batch() -> Dictionary:
	var result := {
		"spawned": _spawned_since_batch.duplicate(),
		"removed": _removed_since_batch.duplicate(),
	}
	_spawned_since_batch.clear()
	_removed_since_batch.clear()
	return result


func active_projectiles() -> Array[ProjectileState]:
	return projectile_registry.all_projectiles()


func _spawn_shot(combatant: CombatantState) -> void:
	var muzzle := combatant.position + Vector2.from_angle(combatant.aim_angle) * 31.0
	for angle in MovementSystem.spread_angles(
		combatant.aim_angle,
		combatant.stats.projectile_count,
		combatant.stats.projectile_spread_degrees
	):
		var projectile := ProjectileState.create(
			_next_projectile_id,
			combatant.peer_id,
			combatant.weapon.shot_sequence,
			muzzle,
			angle,
			combatant.stats
		)
		_next_projectile_id = SequenceMath.increment(_next_projectile_id)
		var spawn_normal := ArenaCollisionSystem.projectile_obstacle_normal(
			projectile.position,
			projectile.radius
		)
		if not spawn_normal.is_zero_approx():
			if not projectile.ricochet(spawn_normal):
				continue
			projectile.position = combatant.position + spawn_normal * (
				GameConstants.SHIP_COLLISION_RADIUS + projectile.radius + 1.0
			)
		for removed_id in projectile_registry.add(projectile):
			_record_removed(removed_id)
		_spawned_since_batch.append(projectile)


func _step_projectiles(delta: float, peer_ids: Array[int]) -> void:
	var damage_events: Array[Dictionary] = []
	for projectile in projectile_registry.all_projectiles():
		var start := projectile.position
		if not projectile.step(delta):
			_remove_projectile(projectile.projectile_id)
			continue
		var obstacle_normal := ArenaCollisionSystem.projectile_obstacle_normal(
			projectile.position,
			projectile.radius
		)
		if not obstacle_normal.is_zero_approx():
			if projectile.ricochet(obstacle_normal):
				projectile.position += obstacle_normal * (projectile.radius + 0.1)
			else:
				_remove_projectile(projectile.projectile_id)
			continue
		for peer_id in peer_ids:
			var target := combatants[peer_id] as CombatantState
			if not target.alive or not projectile.can_hit(peer_id):
				continue
			if not _segment_intersects_circle(
				start,
				projectile.position,
				target.position,
				GameConstants.SHIP_COLLISION_RADIUS + projectile.radius
			):
				continue
			var impact_vector := projectile.position - target.position
			if target.shield.try_block(target.aim_angle, impact_vector, target.stats):
				_remove_projectile(projectile.projectile_id)
				break
			damage_events.append({
				"projectile_id": projectile.projectile_id,
				"target_id": peer_id,
				"damage": projectile.damage,
			})
			if not projectile.register_hull_hit(peer_id):
				_remove_projectile(projectile.projectile_id)
				break
	for peer_id in DamageResolver.resolve_tick(combatants, damage_events):
		projectile_registry.schedule_owner_cleanup(peer_id)


func _resolve_ship_overlaps(peer_ids: Array[int]) -> void:
	var minimum_distance := GameConstants.SHIP_COLLISION_RADIUS * 2.0
	for left_index in peer_ids.size():
		var left := combatants[peer_ids[left_index]] as CombatantState
		if not left.alive:
			continue
		for right_index in range(left_index + 1, peer_ids.size()):
			var right := combatants[peer_ids[right_index]] as CombatantState
			if not right.alive:
				continue
			var difference := right.position - left.position
			var distance := difference.length()
			if distance >= minimum_distance:
				continue
			var normal := difference / distance if distance > 0.001 else Vector2.RIGHT
			var correction := normal * (minimum_distance - distance) * 0.5
			left.position -= correction
			right.position += correction
			var left_into := maxf(left.velocity.dot(normal), 0.0)
			var right_into := minf(right.velocity.dot(normal), 0.0)
			left.velocity -= normal * left_into
			right.velocity -= normal * right_into


func _remove_projectile(projectile_id: int) -> void:
	if projectile_registry.remove(projectile_id):
		_record_removed(projectile_id)


func _record_removed(projectile_id: int) -> void:
	if projectile_id not in _removed_since_batch:
		_removed_since_batch.append(projectile_id)


func _ordered_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_value in combatants.keys():
		result.append(int(peer_value))
	result.sort()
	return result


static func _segment_intersects_circle(
	start: Vector2,
	finish: Vector2,
	center: Vector2,
	radius: float
) -> bool:
	var segment := finish - start
	if segment.is_zero_approx():
		return start.distance_squared_to(center) <= radius * radius
	var weight := clampf((center - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	var closest := start + segment * weight
	return closest.distance_squared_to(center) <= radius * radius
