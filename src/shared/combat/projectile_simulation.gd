extends RefCounted

## Projectile phase execution. World retains authoritative state and damage queues.
## Order is deliberate: armed mines, missile paths, shots, missiles, damage, arming.
## No retained world reference or independently mutable combat state.

static func _acquire_missile_target(world: AuthoritativeWorld,
	owner_id: int,
	origin: Vector2,
	forward: Vector2,
	maximum_range: float
) -> int:
	var best_id := 0
	var best_distance_squared := maxf(maximum_range, 0.0) * maxf(maximum_range, 0.0)
	for peer_id in world._ordered_peer_ids():
		var candidate := world.combatants[peer_id] as CombatantState
		if not candidate.alive or peer_id == owner_id or world.are_allies(owner_id, peer_id):
			continue
		var offset := candidate.position - origin
		var distance_squared := offset.length_squared()
		if distance_squared > best_distance_squared or offset.is_zero_approx():
			continue
		if absf(forward.angle_to(offset.normalized())) > GameConstants.MISSILE_ACQUISITION_HALF_ANGLE:
			continue
		if not ArenaCollisionSystem.has_clear_line_of_sight(origin, candidate.position, world.map_id, world.arena_effects.hidden_cover):
			continue
		if best_id != 0 and is_equal_approx(distance_squared, best_distance_squared) and peer_id > best_id:
			continue
		best_id = peer_id
		best_distance_squared = distance_squared
	return best_id



static func _step_projectiles(world: AuthoritativeWorld, delta: float, peer_ids: Array[int]) -> void:
	var registry := world.projectile_registry
	var spatial_index := world.spatial_index
	var arena_effects := world.arena_effects
	var profiling := world.performance_profiling_enabled
	var map_id := world.map_id
	var cargo_geometry := world._cargo_projectile_geometry
	var profile_started := Time.get_ticks_usec() if profiling else 0
	if profiling:
		world.last_projectile_profile_usec = {
			"mine_setup": 0, "guidance": 0, "obstacle_sweep": 0,
			"ship_sweep": 0, "mine_sweep": 0, "hit_resolution": 0,
			"damage_resolution": 0, "sweep_count": 0, "ship_candidates": 0,
		}
	var damage_events: Array[Dictionary] = []
	var safe_delta := maxf(delta, 0.0)
	var projectile_ids := registry.ordered_ids_view()
	var mine_ids: Array[int] = []
	var armed_mine_ids: Array[int] = []
	if registry.has_mines():
		for projectile_id in projectile_ids:
			if projectile_id == ProjectileRegistry.REMOVED_ID:
				continue
			var candidate := registry.get_projectile(projectile_id)
			if candidate == null or not candidate.is_mine:
				continue
			mine_ids.append(projectile_id)
			if candidate.is_mine_armed():
				armed_mine_ids.append(projectile_id)
	_step_mine_magnetism(world, safe_delta, armed_mine_ids)
	spatial_index.rebuild_armed_mines(registry, armed_mine_ids)
	_step_mine_proximity(world, damage_events, armed_mine_ids)
	if profiling:
		world.last_projectile_profile_usec.mine_setup = Time.get_ticks_usec() - profile_started
	if world._projectile_geometry_normal.is_empty():
		world._projectile_geometry_normal = ArenaCollisionSystem.projectile_geometry(
			map_id,
			GameConstants.PROJECTILE_RADIUS, arena_effects.hidden_cover)
	if world._projectile_geometry_beam.is_empty():
		world._projectile_geometry_beam = ArenaCollisionSystem.projectile_geometry(map_id, 7.0, arena_effects.hidden_cover)
	if world._projectile_geometry_missile.is_empty():
		world._projectile_geometry_missile = ArenaCollisionSystem.projectile_geometry(
			map_id,
			GameConstants.MISSILE_RADIUS, arena_effects.hidden_cover)
	cargo_geometry.prepare(map_id, arena_effects.hidden_cover)
	# Guide once, then test shots against missile motion over this same tick.
	# Bullets resolve first so insertion order cannot protect incoming missiles.
	var missile_paths: Dictionary = {}
	var shot_ids: Array[int] = []
	var missile_ids: Array[int] = []
	for projectile_id in projectile_ids:
		var candidate := registry.get_projectile(projectile_id)
		if candidate == null or candidate.is_mine:
			continue
		if not candidate.is_missile:
			shot_ids.append(projectile_id)
			continue
		missile_ids.append(projectile_id)
		var guidance_started := Time.get_ticks_usec() if profiling else 0
		_step_missile_guidance(world, candidate, safe_delta)
		if profiling:
			world.last_projectile_profile_usec.guidance += Time.get_ticks_usec() - guidance_started
		if candidate.lifetime_remaining <= safe_delta:
			continue
		var finish := candidate.position + candidate.velocity * safe_delta
		var obstacle: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(candidate.position, finish, candidate.radius, map_id, world._projectile_geometry_missile)
		var ship: Variant = _nearest_projectile_ship_hit(world, candidate, candidate.position, finish, peer_ids)
		var end_fraction := minf(float(obstacle.fraction) if obstacle != null else 1.0, float(ship.fraction) if ship != null else 1.0)
		missile_paths[projectile_id] = {"start": candidate.position, "finish": finish, "end_fraction": end_fraction}
	spatial_index.rebuild_missile_sweeps(missile_paths)
	shot_ids.append_array(missile_ids)
	for projectile_id in shot_ids:
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := registry.get_projectile(projectile_id)
		if projectile == null:
			continue
		if projectile.is_mine:
			continue
		projectile.lifetime_remaining -= safe_delta
		if projectile.lifetime_remaining <= 0.0:
			world._remove_projectile(projectile.projectile_id)
			continue
		var projectile_speed := projectile.velocity.length()
		var travel_remaining := projectile_speed * safe_delta
		var collision_iterations := 0
		while travel_remaining > 0.001 and collision_iterations < world.PROJECTILE_COLLISION_ITERATIONS:
			if projectile_speed <= 0.001:
				break
			collision_iterations += 1
			var direction := projectile.velocity / projectile_speed
			var start := projectile.position
			var finish := start + direction * travel_remaining
			var projectile_geometry := (
				world._projectile_geometry_beam if projectile.is_beam
				else (world._projectile_geometry_missile if projectile.is_missile else world._projectile_geometry_normal)
			)
			var sweep_started := Time.get_ticks_usec() if profiling else 0
			if arena_effects.enabled & ArenaEffectRules.CARGO:
				projectile_geometry = cargo_geometry.for_radius(projectile.radius)
			var obstacle_hit: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(
				start,
				finish,
				projectile.radius,
				map_id,
				projectile_geometry
			)
			if profiling:
				world.last_projectile_profile_usec.obstacle_sweep += Time.get_ticks_usec() - sweep_started
				world.last_projectile_profile_usec.sweep_count += 1
			var obstacle_fraction := clampf(float(obstacle_hit.get("fraction", INF)), 0.0, 1.0) if obstacle_hit != null else INF
			sweep_started = Time.get_ticks_usec() if profiling else 0
			var ship_hit: Variant = _nearest_projectile_ship_hit(world, projectile, start, finish, peer_ids)
			if profiling:
				world.last_projectile_profile_usec.ship_sweep += Time.get_ticks_usec() - sweep_started
			var ship_fraction := clampf(float(ship_hit.get("fraction", INF)), 0.0, 1.0) if ship_hit != null else INF
			var mine_hit: Variant = null
			if not armed_mine_ids.is_empty():
				sweep_started = Time.get_ticks_usec() if profiling else 0
				mine_hit = _nearest_projectile_mine_hit(world, projectile, start, finish)
				if profiling:
					world.last_projectile_profile_usec.mine_sweep += Time.get_ticks_usec() - sweep_started
			var mine_fraction := clampf(float(mine_hit.get("fraction", INF)), 0.0, 1.0) if mine_hit != null else INF
			var missile_hit: Variant = null
			if not projectile.is_missile and not missile_paths.is_empty():
				var start_fraction := clampf(1.0 - travel_remaining / (projectile_speed * safe_delta), 0.0, 1.0)
				missile_hit = _nearest_projectile_missile_hit(world, projectile, start, finish, start_fraction, missile_paths)
			if missile_hit != null and float(missile_hit.fraction) <= minf(obstacle_fraction, minf(ship_fraction, mine_fraction)):
				projectile.position = missile_hit.position as Vector2
				world._remove_projectile(int(missile_hit.missile_id))
				world._remove_projectile(projectile.projectile_id)
				break
			if mine_hit != null and mine_fraction <= obstacle_fraction and mine_fraction <= ship_fraction:
				projectile.position = mine_hit.position as Vector2
				var mine := registry.get_projectile(int(mine_hit.mine_id))
				world._remove_projectile(projectile.projectile_id)
				if mine != null:
					var detonation_started := Time.get_ticks_usec() if profiling else 0
					_detonate_mine(world, mine, damage_events)
					if profiling:
						world.last_projectile_profile_usec.hit_resolution += Time.get_ticks_usec() - detonation_started
				break
			if ship_hit != null and ship_fraction <= obstacle_fraction:
				projectile.position = ship_hit.position as Vector2
				travel_remaining *= maxf(1.0 - ship_fraction, 0.0)
				var impact_started := Time.get_ticks_usec() if profiling else 0
				var survives_impact := _resolve_projectile_ship_hit(world, projectile, int(ship_hit.peer_id), damage_events)
				if profiling:
					world.last_projectile_profile_usec.hit_resolution += Time.get_ticks_usec() - impact_started
				if not survives_impact:
					break
				projectile.position += projectile.velocity.normalized() * world.COLLISION_SURFACE_EPSILON
				travel_remaining = maxf(travel_remaining - world.COLLISION_SURFACE_EPSILON, 0.0)
				continue
			if obstacle_hit != null:
				projectile.position = obstacle_hit.position as Vector2
				travel_remaining *= maxf(1.0 - obstacle_fraction, 0.0)
				arena_effects.damage_cover(projectile.position, projectile.radius, projectile.damage)
				world._refresh_effect_geometry()
				var obstacle_normal := obstacle_hit.normal as Vector2
				if projectile.ricochet(obstacle_normal):
					projectile.position += obstacle_normal * world.COLLISION_SURFACE_EPSILON
					travel_remaining = maxf(travel_remaining - world.COLLISION_SURFACE_EPSILON, 0.0)
					continue
				world._remove_projectile(projectile.projectile_id)
				break
			projectile.position = finish
			travel_remaining = 0.0

	var damage_started := Time.get_ticks_usec() if profiling else 0
	for peer_id in world._resolve_damage_events(damage_events):
		registry.schedule_owner_cleanup(peer_id)
	_step_mine_activation(world, safe_delta, mine_ids)
	if profiling:
		world.last_projectile_profile_usec.damage_resolution = Time.get_ticks_usec() - damage_started



static func _nearest_projectile_missile_hit(world: AuthoritativeWorld, projectile: ProjectileState, start: Vector2, finish: Vector2, start_fraction: float, paths: Dictionary) -> Variant:
	var nearest: Variant = null
	var nearest_fraction := INF
	for missile_id in world.spatial_index.query_missiles_along_segment(start, finish, projectile.radius):
		var missile := world.projectile_registry.get_projectile(missile_id)
		if missile == null or missile.owner_id == projectile.owner_id or world.are_allies(projectile.owner_id, missile.owner_id):
			continue
		var path: Dictionary = paths[missile_id]
		var missile_start: Vector2 = (path.start as Vector2).lerp(path.finish as Vector2, start_fraction)
		var fraction := world._segment_circle_hit_fraction(start - missile_start, finish - (path.finish as Vector2), Vector2.ZERO, projectile.radius + missile.radius)
		if fraction < 0.0 or fraction >= nearest_fraction:
			continue
		# A missile that already reached a wall or ship cannot be intercepted.
		if lerpf(start_fraction, 1.0, fraction) > float(path.end_fraction):
			continue
		nearest_fraction = fraction
		nearest = {"missile_id": missile_id, "fraction": fraction, "position": start.lerp(finish, fraction)}
	return nearest



static func _step_missile_guidance(world: AuthoritativeWorld, missile: ProjectileState, delta: float) -> void:
	var combatants := world.combatants
	if not missile.is_missile or missile.velocity.is_zero_approx():
		return
	var target := combatants.get(missile.missile_target_id) as CombatantState
	if target != null and (
		not target.alive
		or world.are_allies(missile.owner_id, target.peer_id)
		or not _missile_target_is_visible_in_cone(world, missile, target, GameConstants.MISSILE_GUIDANCE_HALF_ANGLE)
	):
		missile.missile_target_id = 0
		target = null
	if target == null:
		missile.missile_target_id = _acquire_missile_target(world,
			missile.owner_id,
			missile.position,
			missile.velocity.normalized(),
			missile.lifetime_remaining * GameConstants.MISSILE_SPEED
		)
		target = combatants.get(missile.missile_target_id) as CombatantState
		if target == null:
			return
	missile.steer_missile_toward(target.position, delta)



static func _missile_target_is_visible_in_cone(world: AuthoritativeWorld,
	missile: ProjectileState,
	target: CombatantState,
	half_angle: float
) -> bool:
	var offset := target.position - missile.position
	if offset.is_zero_approx():
		return true
	if absf(missile.velocity.normalized().angle_to(offset.normalized())) > half_angle:
		return false
	return ArenaCollisionSystem.has_clear_line_of_sight(missile.position, target.position, world.map_id, world.arena_effects.hidden_cover)



static func _step_mine_activation(world: AuthoritativeWorld, delta: float, mine_ids: Array[int]) -> void:
	for projectile_id in mine_ids:
		var mine := world.projectile_registry.get_projectile(projectile_id)
		if mine != null:
			mine.step_mine_activation(delta)



static func _step_mine_magnetism(world: AuthoritativeWorld, delta: float, armed_mine_ids: Array[int]) -> void:
	var target_scan_interval := maxi(
		ceili(float(GameConstants.PHYSICS_TICKS_PER_SECOND) / GameConstants.MINE_MAGNETIC_TARGET_RATE),
		1
	)
	for projectile_id in armed_mine_ids:
		var mine := world.projectile_registry.get_projectile(projectile_id)
		if mine == null:
			continue
		var displaced_by_vent := mine.step_kinetic_vent_displacement(delta)
		if not displaced_by_vent and posmod(world.server_tick + projectile_id, target_scan_interval) == 0:
			var target := _nearest_mine_target(world, mine)
			if target == null:
				mine.velocity = Vector2.ZERO
			else:
				var offset := target.position - mine.position
				mine.velocity = (
					offset.normalized() * GameConstants.MINE_MAGNETIC_SPEED
					if not offset.is_zero_approx() else Vector2.ZERO
				)
		if mine.velocity.is_zero_approx():
			continue
		var finish := mine.position + mine.velocity * maxf(delta, 0.0)
		var obstacle_hit: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(
			mine.position,
			finish,
			mine.radius,
			world.map_id, {}, world.arena_effects.hidden_cover
		)
		if obstacle_hit == null:
			mine.position = finish
		else:
			mine.position = obstacle_hit.position as Vector2
			mine.velocity = Vector2.ZERO
			mine.kinetic_vent_displacement_remaining = 0.0



static func _nearest_mine_target(world: AuthoritativeWorld, mine: ProjectileState) -> CombatantState:
	var nearest: CombatantState
	var nearest_distance_squared := GameConstants.MINE_MAGNETIC_RADIUS * GameConstants.MINE_MAGNETIC_RADIUS
	for peer_id in world.spatial_index.query_nearby_ships(
		mine.position,
		GameConstants.MINE_MAGNETIC_RADIUS
	):
		var candidate := world.combatants[peer_id] as CombatantState
		if not candidate.alive or peer_id == mine.owner_id or world.are_allies(mine.owner_id, peer_id):
			continue
		var distance_squared := candidate.position.distance_squared_to(mine.position)
		if distance_squared > nearest_distance_squared:
			continue
		if nearest != null and is_equal_approx(distance_squared, nearest_distance_squared) and peer_id > nearest.peer_id:
			continue
		nearest = candidate
		nearest_distance_squared = distance_squared
	return nearest



static func _step_mine_proximity(world: AuthoritativeWorld, damage_events: Array[Dictionary], armed_mine_ids: Array[int]) -> void:
	for projectile_id in armed_mine_ids:
		var mine := world.projectile_registry.get_projectile(projectile_id)
		if mine == null:
			continue
		for peer_id in world.spatial_index.query_nearby_ships(
			mine.position,
			GameConstants.MINE_TRIGGER_RADIUS + GameConstants.SHIP_COLLISION_RADIUS
		):
			var target := world.combatants[peer_id] as CombatantState
			if not target.alive or peer_id == mine.owner_id or world.are_allies(mine.owner_id, peer_id):
				continue
			if target.position.distance_to(mine.position) <= GameConstants.MINE_TRIGGER_RADIUS + GameConstants.SHIP_COLLISION_RADIUS:
				_detonate_mine(world, mine, damage_events)
				break



static func _nearest_projectile_mine_hit(world: AuthoritativeWorld,
	projectile: ProjectileState,
	start: Vector2,
	finish: Vector2
) -> Variant:
	var nearest_mine_id := 0
	var nearest_fraction := INF
	for mine_id in world.spatial_index.query_mines_along_segment(
		start,
		finish,
		projectile.radius + GameConstants.MINE_RADIUS
	):
		if mine_id == projectile.projectile_id:
			continue
		var mine := world.projectile_registry.get_projectile(mine_id)
		if mine == null:
			continue
		var fraction := world._segment_circle_hit_fraction(
			start,
			finish,
			mine.position,
			projectile.radius + mine.radius
		)
		if fraction < 0.0 or fraction >= nearest_fraction:
			continue
		nearest_fraction = fraction
		nearest_mine_id = mine_id
	if nearest_mine_id == 0:
		return null
	return {
		"mine_id": nearest_mine_id,
		"fraction": nearest_fraction,
		"position": start.lerp(finish, nearest_fraction),
	}



static func _detonate_mine(world: AuthoritativeWorld, mine: ProjectileState, damage_events: Array[Dictionary]) -> void:
	var registry := world.projectile_registry
	var spatial_index := world.spatial_index
	var arena_effects := world.arena_effects
	var map_id := world.map_id
	var detonations := world._mine_detonations
	if mine == null or not mine.is_mine_armed() or registry.get_projectile(mine.projectile_id) == null:
		return
	var pending: Array[int] = [mine.projectile_id]
	var queued: Dictionary = {}
	queued[mine.projectile_id] = true
	while not pending.is_empty():
		var current_id: int = pending.pop_front()
		var current := registry.get_projectile(current_id)
		if current == null or not current.is_mine_armed():
			continue
		if detonations.size() < GameConstants.MAX_PROJECTILES_GLOBAL:
			detonations.append({"projectile_id": current.projectile_id, "owner_id": current.owner_id, "position": current.position})
		world._remove_projectile(current.projectile_id)
		for peer_id in spatial_index.query_nearby_ships(
			current.position,
			GameConstants.MINE_BLAST_RADIUS + GameConstants.SHIP_COLLISION_RADIUS
		):
			var target := world.combatants[peer_id] as CombatantState
			# Once triggered, the blast can hit every ship, including its owner and allies.
			if not target.alive:
				continue
			if target.position.distance_to(current.position) > GameConstants.MINE_BLAST_RADIUS + GameConstants.SHIP_COLLISION_RADIUS:
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(current.position, target.position, map_id, arena_effects.hidden_cover):
				continue
			damage_events.append({
				"projectile_id": current.projectile_id,
				"attacker_id": current.owner_id,
				"target_id": peer_id,
				"damage": current.damage,
				"source": "mine",
				"mechanic": "blast_ignores_shield",
			})
		for candidate_id in spatial_index.query_nearby_mines(
			current.position,
			GameConstants.MINE_BLAST_RADIUS + GameConstants.MINE_RADIUS
		):
			if queued.has(candidate_id):
				continue
			var candidate := registry.get_projectile(candidate_id)
			if candidate == null or not candidate.is_mine_armed():
				continue
			if candidate.position.distance_to(current.position) > GameConstants.MINE_BLAST_RADIUS + candidate.radius:
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(current.position, candidate.position, map_id, arena_effects.hidden_cover):
				continue
			queued[candidate_id] = true
			pending.append(candidate_id)



static func _nearest_projectile_ship_hit(world: AuthoritativeWorld,
	projectile: ProjectileState,
	start: Vector2,
	finish: Vector2,
	peer_ids: Array[int]
) -> Variant:
	var nearest_peer_id := 0
	var nearest_fraction := INF
	var candidates := world.spatial_index.query_ships_along_segment(
		start,
		finish,
		GameConstants.SHIP_COLLISION_RADIUS + projectile.radius
	)
	if world.performance_profiling_enabled and not world.last_projectile_profile_usec.is_empty():
		world.last_projectile_profile_usec.ship_candidates += candidates.size()
	for peer_id in candidates:
		var target := world.combatants[peer_id] as CombatantState
		if not target.alive or not projectile.can_hit(peer_id) or world.are_allies(projectile.owner_id, peer_id):
			continue
		var fraction := world._segment_circle_hit_fraction(
			start,
			finish,
			target.position,
			GameConstants.SHIP_COLLISION_RADIUS + projectile.radius
		)
		if fraction < 0.0 or fraction >= nearest_fraction:
			continue
		nearest_fraction = fraction
		nearest_peer_id = peer_id
	if nearest_peer_id == 0:
		return null
	return {
		"peer_id": nearest_peer_id,
		"fraction": nearest_fraction,
		"position": start.lerp(finish, nearest_fraction),
	}



static func _resolve_projectile_ship_hit(world: AuthoritativeWorld,
	projectile: ProjectileState,
	peer_id: int,
	damage_events: Array[Dictionary]
) -> bool:
	var registry := world.projectile_registry
	var combatants := world.combatants
	var target := combatants.get(peer_id) as CombatantState
	if target == null or not target.alive or not projectile.can_hit(peer_id):
		return true
	var impact_vector := projectile.position - target.position
	if impact_vector.is_zero_approx():
		impact_vector = -projectile.velocity.normalized()
	var perfect_guard := target.shield.is_perfect_guard_active()
	if target.shield.try_block(target.aim_angle, impact_vector, target.stats):
		target.shield.register_blocked_damage(projectile.damage, target.stats)
		_apply_projectile_knockback(world, target, projectile, 0.2)
		if target.stats.shield_damage_heal_fraction > 0.0:
			target.health = minf(
				target.health + projectile.damage * target.stats.shield_damage_heal_fraction,
				target.stats.max_health
			)
		if target.stats.rebound_shield_enabled and not projectile.has_rebounded:
			var source := combatants.get(projectile.owner_id) as CombatantState
			var source_position := source.position if source != null else projectile.position - projectile.velocity
			var old_owner_id := projectile.owner_id
			if projectile.rebound_toward(
				target.peer_id,
				source_position,
				target.stats.rebound_damage_factor,
				target.stats.rebound_range_factor
			):
				projectile.owner_id = old_owner_id
				for removed_id in registry.transfer_owner(projectile.projectile_id, target.peer_id):
					world._record_removed(removed_id)
				if registry.get_projectile(projectile.projectile_id) != null:
					world._record_shield_feedback(old_owner_id, peer_id, "rebound")
					world._record_projectile_update(projectile)
					return true
				world._record_shield_feedback(old_owner_id, peer_id, "rebound")
				return false
		world._record_shield_feedback(projectile.owner_id, peer_id, "perfect_guard" if perfect_guard else "shield")
		world._remove_projectile(projectile.projectile_id)
		return false
	_apply_projectile_knockback(world, target, projectile, 1.0)
	damage_events.append({
		"projectile_id": projectile.projectile_id,
		"attacker_id": projectile.owner_id,
		"target_id": peer_id,
		"damage": projectile.damage,
		"source": world._projectile_source(projectile),
		"mechanic": world._hull_hit_mechanic(target, projectile),
		"original_shooter_id": projectile.original_shooter_id,
		"ricochet_count": projectile.ricochet_count,
	})
	if not projectile.register_hull_hit(peer_id):
		world._remove_projectile(projectile.projectile_id)
		return false
	return true



static func _apply_projectile_knockback(world: AuthoritativeWorld, target: CombatantState, projectile: ProjectileState, factor: float) -> void:
	if projectile.knockback <= 0.0 or projectile.velocity.is_zero_approx():
		return
	target.velocity += projectile.velocity.normalized() * projectile.knockback * maxf(factor, 0.0)
	target.velocity = target.velocity.limit_length(maxf(target.stats.max_speed * 2.5, 1.0))
