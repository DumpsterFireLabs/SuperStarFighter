class_name AuthoritativeWorld
extends RefCounted

const ProjectileSimulation = preload("res://src/shared/combat/projectile_simulation.gd")

const CombatSpatialIndexScript = preload("res://src/shared/combat/combat_spatial_index.gd")
const CombatFeedbackBufferScript = preload("res://src/shared/combat/combat_feedback_buffer.gd")

var server_tick: int = 0
var simulation_paused: bool = false
var combatants: Dictionary = {}
var latest_inputs: Dictionary = {}
var acknowledged_inputs: Dictionary = {}
var input_timeouts: Dictionary = {}
var input_ages: Dictionary = {}
var projectile_registry := ProjectileRegistry.new()
var spatial_index := CombatSpatialIndexScript.new()
var arena_effects := ArenaEffectState.new()
var _effect_geometry_mask := 0
var _cargo_projectile_geometry := preload("res://src/shared/arena/projectile_geometry_references.gd").new()
var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var movement_fields: Array[ArenaMovementField] = []
var team_assignments: Dictionary = {}
var _next_projectile_id: int = 1
var _spawned_since_batch: Array[ProjectileState] = []
var _removed_since_batch: Array[int] = []
var _ram_contact_ticks: Dictionary = {}
var _kills_since_drain: Array[Dictionary] = []
var combat_contact_serial: int = 0
var combat_hull_damage: float = 0.0

var _combat_feedback := CombatFeedbackBufferScript.new()
var _mine_detonations: Array[Dictionary] = []
var _ordered_peer_ids_cache: Array[int] = []
var _ordered_peer_ids_dirty: bool = true
var performance_profiling_enabled: bool = false
var last_step_profile_usec: Dictionary = {}
var last_projectile_profile_usec: Dictionary = {}
var _projectile_geometry_normal: Dictionary = {}
var _projectile_geometry_beam: Dictionary = {}
var _projectile_geometry_missile: Dictionary = {}

const SHIP_SEPARATION_SPEED: float = 360.0
const SHIP_OVERLAP_SOLVER_PASSES: int = 6
const SHIP_SEPARATION_SLOP: float = 1.0
const RAM_REFERENCE_SPEED: float = 480.0
const PROJECTILE_COLLISION_ITERATIONS: int = 16
const COLLISION_SURFACE_EPSILON: float = 0.35


func add_peer(peer_id: int, stats: CombatStats = null) -> CombatantState:
	if combatants.has(peer_id):
		return combatants[peer_id] as CombatantState
	var anchors := ArenaLayout.spawn_anchors(map_id)
	var spawn_index := combatants.size() % anchors.size()
	var combat_stats := stats if stats != null else CombatStats.create_base()
	var combatant := CombatantState.create(peer_id, combat_stats, anchors[spawn_index])
	combatants[peer_id] = combatant
	_ordered_peer_ids_dirty = true
	latest_inputs[peer_id] = PlayerInputFrame.new()
	acknowledged_inputs[peer_id] = 0
	return combatant


func remove_peer(peer_id: int) -> void:
	_combat_feedback.forget_peer(peer_id)
	projectile_registry.forget_owner_metrics(peer_id)
	combatants.erase(peer_id)
	_ordered_peer_ids_dirty = true
	latest_inputs.erase(peer_id)
	acknowledged_inputs.erase(peer_id)
	input_timeouts.erase(peer_id)
	input_ages.erase(peer_id)
	team_assignments.erase(peer_id)
	projectile_registry.schedule_owner_cleanup(peer_id)


func set_team_assignments(assignments: Dictionary) -> void:
	team_assignments.clear()
	for peer_value in assignments.keys():
		var peer_id := int(peer_value)
		var team_id := int(assignments[peer_value])
		if team_id > 0:
			team_assignments[peer_id] = team_id


func are_allies(left_peer_id: int, right_peer_id: int) -> bool:
	var left_team := int(team_assignments.get(left_peer_id, 0))
	return left_team > 0 and left_team == int(team_assignments.get(right_peer_id, 0))


func submit_input(peer_id: int, frame: PlayerInputFrame) -> bool:
	if simulation_paused:
		return false
	if not combatants.has(peer_id) or not frame.is_valid():
		return false
	var previous := latest_inputs.get(peer_id) as PlayerInputFrame
	if previous != null and acknowledged_inputs.has(peer_id):
		var previous_sequence := int(acknowledged_inputs[peer_id])
		if frame.sequence == previous_sequence or not SequenceMath.is_newer(frame.sequence, previous_sequence):
			return false
	latest_inputs[peer_id] = frame
	acknowledged_inputs[peer_id] = frame.sequence
	input_ages[peer_id] = 0.0
	return true


func step(
	delta: float,
	controls_enabled: bool = true
) -> void:
	if simulation_paused:
		return
	var phase_started := Time.get_ticks_usec() if performance_profiling_enabled else 0
	server_tick = SequenceMath.increment(server_tick)
	if not controls_enabled:
		return
	_refresh_effect_geometry()
	var peer_ids := _ordered_peer_ids()
	for peer_id in peer_ids:
		var combatant := combatants[peer_id] as CombatantState
		if not combatant.alive:
			continue
		var frame := latest_inputs[peer_id] as PlayerInputFrame
		if input_timeouts.has(peer_id):
			input_ages[peer_id] = float(input_ages.get(peer_id, 0.0)) + maxf(delta, 0.0)
			if float(input_ages[peer_id]) > float(input_timeouts[peer_id]):
				frame = PlayerInputFrame.new(frame.sequence, server_tick, Vector2.ZERO, frame.aim_angle)
				latest_inputs[peer_id] = frame
		var actions := ArenaMovementSystem.step_input_with_fields(combatant, frame, delta, movement_fields)
		if actions & CombatantState.ACTION_MINE:
			_spawn_mine(combatant)
		if actions & CombatantState.ACTION_MISSILE:
			_spawn_missile(combatant)
		var motion := ArenaCollisionSystem.move_ship(combatant.position, combatant.velocity, delta, map_id, arena_effects.hidden_cover)
		combatant.position = motion.position
		combatant.velocity = motion.velocity
		if actions & CombatantState.ACTION_SHOT:
			_spawn_shot(combatant)
	var movement_complete := Time.get_ticks_usec() if performance_profiling_enabled else 0
	for peer_id in _resolve_ship_overlaps(peer_ids):
		projectile_registry.schedule_owner_cleanup(peer_id)
	spatial_index.rebuild_ships(combatants, peer_ids)
	_resolve_rebound_shield_damage(peer_ids, delta)
	_resolve_kinetic_vents(peer_ids)
	var overlaps_complete := Time.get_ticks_usec() if performance_profiling_enabled else 0
	_step_projectiles(delta, peer_ids)
	var projectiles_complete := Time.get_ticks_usec() if performance_profiling_enabled else 0
	for projectile_id in projectile_registry.step_cleanup(delta):
		_record_removed(projectile_id)
	# Motion changes cells even without a registry membership revision. Rebuild
	# on the first threat query, after next-tick spawns/removals, rather than
	# eagerly building an index that can be invalidated before any NPC uses it.
	spatial_index.invalidate_projectile_threats()
	if performance_profiling_enabled:
		var completed := Time.get_ticks_usec()
		last_step_profile_usec = {
			"movement": movement_complete - phase_started,
			"overlaps": overlaps_complete - movement_complete,
			"projectiles": projectiles_complete - overlaps_complete,
			"cleanup_and_threats": completed - projectiles_complete,
		}


func prepare_heat(
	participant_stats: Dictionary,
	spawn_assignments: Dictionary
) -> void:
	clear_projectiles()
	_ram_contact_ticks.clear()
	_kills_since_drain.clear()
	_combat_feedback.clear()
	_mine_detonations.clear()
	for peer_id in _ordered_peer_ids():
		var combatant := combatants[peer_id] as CombatantState
		if participant_stats.has(peer_id) and spawn_assignments.has(peer_id):
			combatant.reset_for_heat(
				participant_stats[peer_id] as CombatStats,
				spawn_assignments[peer_id] as Vector2
			)
			# A new heat must not inherit movement, firing, or shielding from the
			# previous one. This is especially important for server-owned NPCs,
			# which do not submit neutral input during the countdown.
			latest_inputs[peer_id] = PlayerInputFrame.new(
				int(acknowledged_inputs.get(peer_id, 0)),
				server_tick
			)
		else:
			combatant.shield.drain_feedback()
			combatant.alive = false
			combatant.health = 0.0
			combatant.velocity = Vector2.ZERO
			combatant.shield.active = false
			combatant.cloak_remaining = 0.0


func reset_match_inventories() -> void:
	clear_projectiles()
	for combatant_value in combatants.values():
		(combatant_value as CombatantState).reset_match_inventory()


func respawn_peer(peer_id: int, stats: CombatStats, spawn_position: Vector2) -> bool:
	var combatant := combatants.get(peer_id) as CombatantState
	if combatant == null or combatant.alive:
		return false
	combatant.reset_for_heat(stats, spawn_position, false)
	arena_effects.protect_respawn(peer_id)
	latest_inputs[peer_id] = PlayerInputFrame.new()
	projectile_registry.schedule_owner_cleanup(peer_id)
	return true


func set_map_id(value: StringName) -> void:
	map_id = ArenaLayout.normalized_map_id(value)
	arena_effects.reset(map_id, arena_effects.settings)
	movement_fields = ArenaLayout.movement_fields(map_id)
	# These dictionaries reference immutable entries owned by ArenaCollisionSystem's
	# shared geometry cache. Detach from them instead of clearing the cache entry.
	_projectile_geometry_normal = {}
	_projectile_geometry_beam = {}
	_projectile_geometry_missile = {}
	_cargo_projectile_geometry.reset()
	clear_projectiles()


func set_spectator(peer_id: int) -> void:
	var combatant := combatants.get(peer_id) as CombatantState
	if combatant == null:
		return
	combatant.alive = false
	combatant.health = 0.0
	combatant.velocity = Vector2.ZERO
	combatant.shield.active = false
	combatant.cloak_remaining = 0.0


func clear_projectiles() -> void:
	for projectile in projectile_registry.all_projectiles():
		_remove_projectile(projectile.projectile_id)


func apply_overtime(
	heat_elapsed: float,
	delta: float,
	zone_center: Vector2 = GameConstants.ARENA_SIZE * 0.5,
	minimum_radius: float = GameConstants.OVERTIME_MINIMUM_RADIUS
) -> Array[int]:
	var damage_events: Array[Dictionary] = []
	for peer_id in _ordered_peer_ids():
		var combatant := combatants[peer_id] as CombatantState
		if not combatant.alive:
			continue
		var damage := OvertimeSystem.damage_for_position(
			combatant.position,
			heat_elapsed,
			delta,
			zone_center,
			minimum_radius
		)
		if damage > 0.0:
			damage_events.append({
				"projectile_id": 2_000_000_000 + peer_id,
				"target_id": peer_id,
				"damage": damage,
				"source": "overtime",
			})
	var deaths := _resolve_damage_events(damage_events)
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
			"life_generation": combatant.life_generation,
			"shield": combatant.shield.energy,
			"ammunition": combatant.weapon.ammunition,
			"alive": combatant.alive,
			"shielding": combatant.shield.active,
			"afterburner_active": combatant.afterburner_remaining > 0.0,
			"mine_charges": combatant.mine_charges_remaining,
			"mine_cooldown": combatant.mine_cooldown_remaining,
			"missile_charges": combatant.missile_charges_remaining,
			"missile_cooldown": combatant.missile_cooldown_remaining,
			"cloaked": combatant.is_cloaked(),
			"cloak_charges": combatant.cloak_charges_remaining,
			"cloak_cooldown": combatant.cloak_cooldown_remaining,
			"perfect_guard_active": combatant.shield.is_perfect_guard_active() or combatant.shield.has_perfect_guard_feedback(),
			"kinetic_vent_active": combatant.kinetic_vent_feedback_remaining > 0.0,
			"breakaway_active": combatant.breakaway_remaining > 0.0,
			"kinetic_vent_charge": combatant.shield.kinetic_vent_charge,
			"breakaway_cooldown": combatant.breakaway_cooldown_remaining,
		})
	return states


func ordered_peer_ids_view() -> Array[int]:
	return _ordered_peer_ids()


func acknowledged_input(peer_id: int) -> int:
	return int(acknowledged_inputs.get(peer_id, 0))


func drain_projectile_batch() -> Dictionary:
	var spawned := _spawned_since_batch
	var removed := _removed_since_batch
	_spawned_since_batch = []
	_removed_since_batch = []
	var result := {
		"spawned": spawned,
		"removed": removed,
	}
	return result


func has_projectile_batch() -> bool:
	return not _spawned_since_batch.is_empty() or not _removed_since_batch.is_empty()


func active_projectiles() -> Array[ProjectileState]:
	return projectile_registry.all_projectiles()


func active_projectile_ids_view() -> Array[int]:
	return projectile_registry.ordered_ids_view()


func projectile_threat_ids(position: Vector2, radius: float, maximum_count: int) -> Array[int]:
	if spatial_index.projectile_revision != projectile_registry.revision:
		spatial_index.rebuild_projectile_threats(projectile_registry)
	return spatial_index.query_projectile_threats(position, radius, maximum_count)


func maximum_projectile_speed() -> float:
	if spatial_index.projectile_revision != projectile_registry.revision:
		spatial_index.rebuild_projectile_threats(projectile_registry)
	return spatial_index.maximum_projectile_speed


func drain_kill_events() -> Array[Dictionary]:
	var result := _kills_since_drain.duplicate(true)
	_kills_since_drain.clear()
	return result


# Raw participant feedback. Hit/guard totals are private; for_recipient filters
# public shield cues against cloak visibility before anything goes on the wire.
func drain_combat_feedback() -> Dictionary:
	for peer_id in _ordered_peer_ids():
		var combatant := combatants[peer_id] as CombatantState
		var shield_events := combatant.shield.drain_feedback()
		if shield_events != Vector2i.ZERO:
			_combat_feedback.record_shield_events(peer_id, combatant.life_generation, shield_events)
	return _combat_feedback.drain()


func drain_mine_detonations() -> Array[Dictionary]:
	var result := _mine_detonations
	_mine_detonations = []
	return result


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
			projectile.radius,
			map_id, arena_effects.hidden_cover)
		if not spawn_normal.is_zero_approx():
			arena_effects.damage_cover(projectile.position, projectile.radius, projectile.damage)
			_refresh_effect_geometry()
			if not projectile.ricochet(spawn_normal):
				continue
			projectile.position = combatant.position + spawn_normal * (
				GameConstants.SHIP_COLLISION_RADIUS + projectile.radius + 1.0
			)
		for removed_id in projectile_registry.add(projectile):
			_record_removed(removed_id)
		_spawned_since_batch.append(projectile)


func _spawn_mine(combatant: CombatantState) -> void:
	var mine := ProjectileState.create_mine(
		_next_projectile_id,
		combatant.peer_id,
		combatant.position
	)
	_next_projectile_id = SequenceMath.increment(_next_projectile_id)
	for removed_id in projectile_registry.add(mine):
		_record_removed(removed_id)
	_spawned_since_batch.append(mine)


func _spawn_missile(combatant: CombatantState) -> void:
	var muzzle := combatant.position + Vector2.from_angle(combatant.aim_angle) * 34.0
	var missile := ProjectileState.create_missile(
		_next_projectile_id,
		combatant.peer_id,
		muzzle,
		combatant.aim_angle,
		_acquire_missile_target(
			combatant.peer_id,
			muzzle,
			Vector2.from_angle(combatant.aim_angle),
			GameConstants.MISSILE_RANGE
		)
	)
	_next_projectile_id = SequenceMath.increment(_next_projectile_id)
	if not ArenaCollisionSystem.projectile_obstacle_normal(missile.position, missile.radius, map_id, arena_effects.hidden_cover).is_zero_approx():
		return
	for removed_id in projectile_registry.add(missile):
		_record_removed(removed_id)
	_spawned_since_batch.append(missile)


func _acquire_missile_target(
	owner_id: int,
	origin: Vector2,
	forward: Vector2,
	maximum_range: float
) -> int:
	return ProjectileSimulation._acquire_missile_target(self, owner_id, origin, forward, maximum_range)


func _step_projectiles(delta: float, peer_ids: Array[int]) -> void:
	ProjectileSimulation._step_projectiles(self, delta, peer_ids)


func _nearest_projectile_missile_hit(projectile: ProjectileState, start: Vector2, finish: Vector2, start_fraction: float, paths: Dictionary) -> Variant:
	return ProjectileSimulation._nearest_projectile_missile_hit(self, projectile, start, finish, start_fraction, paths)


func _step_missile_guidance(missile: ProjectileState, delta: float) -> void:
	ProjectileSimulation._step_missile_guidance(self, missile, delta)


func _missile_target_is_visible_in_cone(
	missile: ProjectileState,
	target: CombatantState,
	half_angle: float
) -> bool:
	return ProjectileSimulation._missile_target_is_visible_in_cone(self, missile, target, half_angle)


func _step_mine_activation(delta: float, mine_ids: Array[int]) -> void:
	ProjectileSimulation._step_mine_activation(self, delta, mine_ids)


func _step_mine_magnetism(delta: float, armed_mine_ids: Array[int]) -> void:
	ProjectileSimulation._step_mine_magnetism(self, delta, armed_mine_ids)


func _nearest_mine_target(mine: ProjectileState) -> CombatantState:
	return ProjectileSimulation._nearest_mine_target(self, mine)


func _step_mine_proximity(damage_events: Array[Dictionary], armed_mine_ids: Array[int]) -> void:
	ProjectileSimulation._step_mine_proximity(self, damage_events, armed_mine_ids)


func _nearest_projectile_mine_hit(
	projectile: ProjectileState,
	start: Vector2,
	finish: Vector2
) -> Variant:
	return ProjectileSimulation._nearest_projectile_mine_hit(self, projectile, start, finish)


func _detonate_mine(mine: ProjectileState, damage_events: Array[Dictionary]) -> void:
	ProjectileSimulation._detonate_mine(self, mine, damage_events)


func _nearest_projectile_ship_hit(
	projectile: ProjectileState,
	start: Vector2,
	finish: Vector2,
	peer_ids: Array[int]
) -> Variant:
	return ProjectileSimulation._nearest_projectile_ship_hit(self, projectile, start, finish, peer_ids)


func _resolve_projectile_ship_hit(
	projectile: ProjectileState,
	peer_id: int,
	damage_events: Array[Dictionary]
) -> bool:
	return ProjectileSimulation._resolve_projectile_ship_hit(self, projectile, peer_id, damage_events)


func _resolve_ship_overlaps(peer_ids: Array[int]) -> Array[int]:
	var minimum_distance := GameConstants.SHIP_COLLISION_RADIUS * 2.0
	var ram_damage_events: Array[Dictionary] = []
	for _pass in SHIP_OVERLAP_SOLVER_PASSES:
		var overlap_found := false
		spatial_index.rebuild_ships(combatants, peer_ids)
		for left_peer_id in peer_ids:
			var left := combatants[left_peer_id] as CombatantState
			if not left.alive:
				continue
			for right_peer_id in spatial_index.query_nearby_ships(left.position, minimum_distance):
				if right_peer_id <= left_peer_id:
					continue
				var right := combatants[right_peer_id] as CombatantState
				if not right.alive:
					continue
				var difference := right.position - left.position
				var distance := difference.length()
				if distance >= minimum_distance:
					continue
				overlap_found = true
				var fallback_angle := float(posmod(left.peer_id * 31 + right.peer_id * 17, 360)) * PI / 180.0
				var normal := difference / distance if distance > 0.001 else Vector2.from_angle(fallback_angle)
				_append_ram_damage(left, right, normal, ram_damage_events)
				_append_ram_damage(right, left, -normal, ram_damage_events)
				_separate_ship_pair(left, right, normal, minimum_distance)
				var left_into := maxf(left.velocity.dot(normal), 0.0)
				var right_into := minf(right.velocity.dot(normal), 0.0)
				left.velocity -= normal * left_into
				right.velocity -= normal * right_into
				left.velocity -= normal * SHIP_SEPARATION_SPEED
				right.velocity += normal * SHIP_SEPARATION_SPEED
				var left_safe := ArenaCollisionSystem.move_ship(left.position, left.velocity, 0.0, map_id, arena_effects.hidden_cover)
				var right_safe := ArenaCollisionSystem.move_ship(right.position, right.velocity, 0.0, map_id, arena_effects.hidden_cover)
				left.position = left_safe.position
				left.velocity = left_safe.velocity
				right.position = right_safe.position
				right.velocity = right_safe.velocity
		if not overlap_found:
			break
	return _resolve_damage_events(ram_damage_events)


func _resolve_rebound_shield_damage(peer_ids: Array[int], delta: float) -> void:
	var events: Array[Dictionary] = []
	var radius := GameConstants.REBOUND_SHIELD_RADIUS + GameConstants.SHIP_COLLISION_RADIUS
	for peer_id in peer_ids:
		var source := combatants[peer_id] as CombatantState
		if not source.alive or not source.shield.active or not source.stats.rebound_shield_enabled:
			continue
		for target_id in spatial_index.query_nearby_ships(source.position, radius):
			if target_id == peer_id or are_allies(peer_id, target_id):
				continue
			var target := combatants[target_id] as CombatantState
			if not target.alive or source.position.distance_to(target.position) > radius:
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(source.position, target.position, map_id, arena_effects.hidden_cover):
				continue
			events.append({"attacker_id": peer_id, "target_id": target_id,
				"damage": GameConstants.REBOUND_SHIELD_DAMAGE_PER_SECOND * maxf(delta, 0.0),
				"source": "rebound_shield", "mechanic": "rebound_contact"})
	for peer_id in _resolve_damage_events(events):
		projectile_registry.schedule_owner_cleanup(peer_id)


func _resolve_kinetic_vents(peer_ids: Array[int]) -> void:
	var releases: Array[Dictionary] = []
	for peer_id in peer_ids:
		var source := combatants[peer_id] as CombatantState
		if not source.alive:
			continue
		var charge := source.shield.consume_kinetic_vent_release()
		if charge < GameConstants.KINETIC_VENT_MINIMUM_CHARGE:
			continue
		source.mark_kinetic_vent_release()
		releases.append({"source": source, "charge": charge})
	if releases.is_empty():
		return
	spatial_index.rebuild_projectile_threats(projectile_registry)
	for release in releases:
		var source := release.source as CombatantState
		var charge_fraction := clampf(
			float(release.charge) / GameConstants.KINETIC_VENT_MAXIMUM_CHARGE,
			0.0,
			1.0
		)
		var impulse := source.stats.kinetic_vent_impulse * lerpf(0.65, 1.0, charge_fraction)
		for target_id in spatial_index.query_nearby_ships(source.position, GameConstants.KINETIC_VENT_RADIUS):
			if target_id == source.peer_id or are_allies(source.peer_id, target_id):
				continue
			var target := combatants.get(target_id) as CombatantState
			if (
				target == null
				or not target.alive
				or target.position.distance_to(source.position) > GameConstants.KINETIC_VENT_RADIUS
			):
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(source.position, target.position, map_id, arena_effects.hidden_cover):
				continue
			var outward := target.position - source.position
			if outward.is_zero_approx():
				outward = Vector2.from_angle(source.aim_angle)
			target.velocity = (target.velocity + outward.normalized() * impulse).limit_length(
				maxf(target.stats.max_speed * 2.5, 1.0)
			)
		for projectile_id in spatial_index.query_projectile_threats(
			source.position,
			GameConstants.KINETIC_VENT_RADIUS,
			GameConstants.MAX_PROJECTILES_GLOBAL
		):
			var projectile := projectile_registry.get_projectile(projectile_id)
			if (
				projectile == null
				or projectile.owner_id == source.peer_id
				or are_allies(source.peer_id, projectile.owner_id)
			):
				continue
			if projectile.position.distance_to(source.position) > GameConstants.KINETIC_VENT_RADIUS:
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(source.position, projectile.position, map_id, arena_effects.hidden_cover):
				continue
			var outward := projectile.position - source.position
			if outward.is_zero_approx():
				outward = Vector2.from_angle(source.aim_angle)
			if projectile.is_mine:
				projectile.apply_kinetic_vent(outward, impulse)
			elif not projectile.velocity.is_zero_approx():
				projectile.velocity = outward.normalized() * projectile.velocity.length()
				if projectile.is_missile:
					projectile.missile_target_id = 0
			_record_projectile_update(projectile)
	spatial_index.invalidate_projectile_threats()


func _separate_ship_pair(
	left: CombatantState,
	right: CombatantState,
	normal: Vector2,
	minimum_distance: float
) -> void:
	var target_distance := minimum_distance + SHIP_SEPARATION_SLOP
	var penetration := maxf(target_distance - (right.position - left.position).dot(normal), 0.0)
	if penetration <= 0.0:
		return
	var half_correction := normal * penetration * 0.5
	var left_safe := ArenaCollisionSystem.move_ship(left.position - half_correction, left.velocity, 0.0, map_id, arena_effects.hidden_cover)
	var right_safe := ArenaCollisionSystem.move_ship(right.position + half_correction, right.velocity, 0.0, map_id, arena_effects.hidden_cover)
	left.position = left_safe.position
	right.position = right_safe.position
	var remaining := maxf(target_distance - (right.position - left.position).dot(normal), 0.0)
	if remaining > 0.001:
		# A wall or cover piece may reject one ship's half of the correction. Transfer
		# that unfulfilled distance to the free ship instead of leaving the pair
		# overlapped. Alternate first choice to avoid a permanent peer-ID bias.
		var move_right_first := posmod(server_tick + left.peer_id + right.peer_id, 2) == 0
		if move_right_first:
			remaining = _move_separation_remainder(right, normal, remaining)
			_move_separation_remainder(left, -normal, remaining)
		else:
			remaining = _move_separation_remainder(left, -normal, remaining)
			_move_separation_remainder(right, normal, remaining)
	if left.position.distance_to(right.position) < target_distance - 0.001:
		_force_separate_ship_pair(left, right, normal, target_distance)


func _move_separation_remainder(combatant: CombatantState, direction: Vector2, distance: float) -> float:
	if distance <= 0.001:
		return 0.0
	var original_position := combatant.position
	var safe := ArenaCollisionSystem.move_ship(original_position + direction * distance, combatant.velocity, 0.0, map_id, arena_effects.hidden_cover)
	combatant.position = safe.position
	var achieved := maxf((combatant.position - original_position).dot(direction), 0.0)
	return maxf(distance - achieved, 0.0)


func _force_separate_ship_pair(
	left: CombatantState,
	right: CombatantState,
	preferred_normal: Vector2,
	target_distance: float
) -> void:
	var right_candidate := _best_separation_candidate(
		left.position,
		right.position,
		preferred_normal,
		target_distance,
		left.peer_id,
		right.peer_id
	)
	var left_candidate := _best_separation_candidate(
		right.position,
		left.position,
		-preferred_normal,
		target_distance,
		left.peer_id,
		right.peer_id
	)
	var right_cost := right.position.distance_squared_to(right_candidate) if right_candidate != Vector2.INF else INF
	var left_cost := left.position.distance_squared_to(left_candidate) if left_candidate != Vector2.INF else INF
	if right_cost < INF or left_cost < INF:
		if right_cost <= left_cost:
			right.position = right_candidate
		else:
			left.position = left_candidate
		return
	var midpoint := (left.position + right.position) * 0.5
	var start_angle := preferred_normal.angle()
	for sample_index in 32:
		var direction := Vector2.from_angle(start_angle + TAU * float(sample_index) / 32.0)
		var candidate_left := midpoint - direction * target_distance * 0.5
		var candidate_right := midpoint + direction * target_distance * 0.5
		if (
			_ship_position_available(candidate_left, left.peer_id, right.peer_id, target_distance)
			and _ship_position_available(candidate_right, left.peer_id, right.peer_id, target_distance)
		):
			left.position = candidate_left
			right.position = candidate_right
			return


func _best_separation_candidate(
	anchor: Vector2,
	current: Vector2,
	preferred_direction: Vector2,
	target_distance: float,
	ignore_left_id: int,
	ignore_right_id: int
) -> Vector2:
	var best := Vector2.INF
	var best_cost := INF
	var start_angle := preferred_direction.angle()
	for sample_index in 32:
		var direction := Vector2.from_angle(start_angle + TAU * float(sample_index) / 32.0)
		var candidate := anchor + direction * target_distance
		if not _ship_position_available(candidate, ignore_left_id, ignore_right_id, target_distance):
			continue
		var cost := current.distance_squared_to(candidate) + float(sample_index) * 0.001
		if cost < best_cost:
			best = candidate
			best_cost = cost
	return best


func _ship_position_available(position: Vector2, ignore_left_id: int, ignore_right_id: int, minimum_distance: float) -> bool:
	if not ArenaCollisionSystem.is_ship_position_clear(position, map_id, SHIP_SEPARATION_SLOP, arena_effects.hidden_cover):
		return false
	for peer_value in combatants.keys():
		var peer_id := int(peer_value)
		if peer_id == ignore_left_id or peer_id == ignore_right_id:
			continue
		var other := combatants[peer_id] as CombatantState
		if other.alive and position.distance_to(other.position) < minimum_distance:
			return false
	return true


func _append_ram_damage(
	attacker: CombatantState,
	target: CombatantState,
	direction_to_target: Vector2,
	damage_events: Array[Dictionary]
) -> void:
	if are_allies(attacker.peer_id, target.peer_id) or attacker.stats.shield_ram_damage <= 0.0 or not attacker.shield.active:
		return
	var impact_speed := (attacker.velocity - target.velocity).dot(direction_to_target)
	if impact_speed < attacker.stats.shield_ram_min_speed:
		return
	var contact_key := "%d:%d" % [attacker.peer_id, target.peer_id]
	var cooldown_ticks := ceili(attacker.stats.shield_ram_cooldown * GameConstants.PHYSICS_TICKS_PER_SECOND)
	if _ram_contact_ticks.has(contact_key) and server_tick - int(_ram_contact_ticks[contact_key]) < cooldown_ticks:
		return
	if not attacker.shield.try_absorb_contact(attacker.stats):
		return
	_ram_contact_ticks[contact_key] = server_tick
	var speed_scale := clampf(impact_speed / RAM_REFERENCE_SPEED, 0.5, 2.0)
	damage_events.append({
		"projectile_id": 3_000_000_000 + attacker.peer_id,
		"attacker_id": attacker.peer_id,
		"target_id": target.peer_id,
		"damage": attacker.stats.shield_ram_damage * speed_scale,
		"source": "shield_ram",
		"mechanic": "ram_contact",
	})


func _apply_projectile_knockback(target: CombatantState, projectile: ProjectileState, factor: float) -> void:
	ProjectileSimulation._apply_projectile_knockback(self, target, projectile, factor)


func _resolve_damage_events(damage_events: Array[Dictionary]) -> Array[int]:
	var deaths: Array[int] = []
	var impacts := DamageResolver.resolve_tick_with_feedback(combatants, damage_events)
	for impact in impacts:
		var target_id := int(impact.target_id)
		var killer_id := int(impact.attacker_id)
		if killer_id != target_id and combatants.has(killer_id):
			combat_contact_serial += 1
			combat_hull_damage += float(impact.damage)
			_combat_feedback.record_hit(killer_id, float(impact.damage), String(impact.source))
		if not bool(impact.lethal):
			continue
		_combat_feedback.record_death(target_id, {
			"killer_id": killer_id, "source": impact.source,
			"mechanic": impact.mechanic, "damage": impact.damage,
			"life_generation": impact.life_generation,
		})
		deaths.append(target_id)
		if killer_id != 0 and killer_id != target_id and combatants.has(killer_id):
			var kill := {"killer_id": killer_id, "target_id": target_id}
			if String(impact.mechanic) == "ram_contact":
				kill["mechanic"] = "ram_contact"
			_kills_since_drain.append(kill)
	return deaths


func _record_shield_feedback(attacker_id: int, defender_id: int, reason: String) -> void:
	if attacker_id != defender_id and combatants.has(attacker_id):
		combat_contact_serial += 1
	_combat_feedback.record_block(attacker_id if combatants.has(attacker_id) else 0, defender_id, reason)


static func _projectile_source(projectile: ProjectileState) -> String:
	if projectile.is_missile:
		return "missile"
	if projectile.is_beam:
		return "beam"
	return "projectile"


static func _hull_hit_mechanic(target: CombatantState, projectile: ProjectileState) -> String:
	if projectile.has_rebounded:
		return "reflected"
	if target.shield.active:
		return "outside_shield_arc"
	if target.shield.depletion_locked:
		return "shield_depleted"
	return ""


func _remove_projectile(projectile_id: int) -> void:
	if projectile_registry.remove(projectile_id):
		_record_removed(projectile_id)


func _record_removed(projectile_id: int) -> void:
	if projectile_id not in _removed_since_batch:
		_removed_since_batch.append(projectile_id)


func _record_projectile_update(projectile: ProjectileState) -> void:
	for pending in _spawned_since_batch:
		if pending.projectile_id == projectile.projectile_id:
			return
	_spawned_since_batch.append(projectile)


func _ordered_peer_ids() -> Array[int]:
	if _ordered_peer_ids_dirty:
		_ordered_peer_ids_cache.clear()
		for peer_value in combatants.keys():
			_ordered_peer_ids_cache.append(int(peer_value))
		_ordered_peer_ids_cache.sort()
		_ordered_peer_ids_dirty = false
	return _ordered_peer_ids_cache


static func _segment_circle_hit_fraction(
	start: Vector2,
	finish: Vector2,
	center: Vector2,
	radius: float
) -> float:
	var segment := finish - start
	if segment.is_zero_approx():
		return 0.0 if start.distance_squared_to(center) <= radius * radius else -1.0
	var offset := start - center
	var a := segment.length_squared()
	var b := 2.0 * offset.dot(segment)
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	return fraction if fraction >= 0.0 and fraction <= 1.0 else -1.0


func _refresh_effect_geometry() -> void:
	if _effect_geometry_mask == arena_effects.hidden_cover: return
	_effect_geometry_mask = arena_effects.hidden_cover
	# Damage can open cargo during a sweep; subsequent impacts use the new revision.
	_cargo_projectile_geometry.prepare(map_id, arena_effects.hidden_cover)
	_projectile_geometry_normal = {}
	_projectile_geometry_beam = {}
	_projectile_geometry_missile = {}

func step_arena_effects(elapsed: float, overtime_seconds: float) -> void:
	var events := arena_effects.step(elapsed, overtime_seconds, combatants)
	_refresh_effect_geometry()
	for peer_id in _resolve_damage_events(events):
		projectile_registry.schedule_owner_cleanup(peer_id)
