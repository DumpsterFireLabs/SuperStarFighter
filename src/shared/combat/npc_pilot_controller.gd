class_name NpcPilotController
extends RefCounted

enum Difficulty {
	PASSIVE,
	EASY,
	NEUTRAL,
	SKILLED,
	INSANE,
}

const DIFFICULTY_NAMES: Array[String] = ["Passive", "Easy", "Neutral", "Skilled", "Insane"]
const OVERTIME_NAVIGATION_MARGIN: float = 170.0
const OBSTACLE_FLANK_CLEARANCE: float = 64.0
const FLANK_DIRECTION_TICKS: int = GameConstants.PHYSICS_TICKS_PER_SECOND * 8
const BLOCKED_LOOP_BREAKOUT_TICKS: int = GameConstants.PHYSICS_TICKS_PER_SECOND * 3
const BLOCKED_LOOP_RESET_TICKS: int = GameConstants.PHYSICS_TICKS_PER_SECOND
const FULL_MAP_ACQUISITION_RANGE: float = 4000.0
const CLOSE_CONTACT_ESCAPE_DISTANCE: float = GameConstants.SHIP_COLLISION_RADIUS * 2.0 + 48.0
const MAX_PROJECTILE_THREAT_CANDIDATES: int = 48
const DIFFICULTY_PROFILES := {
	Difficulty.PASSIVE: {
		"reaction_ticks": 36, "aim_error_degrees": 24.0, "lead_seconds": 0.0,
		"awareness_range": 900.0, "pursuit": 0.18, "strafe": 0.18,
		"preferred_min": 460.0, "preferred_max": 820.0,
		"fire_range": 0.0, "fire_duty": 0.0, "shield_range": 0.0, "shield_duty": 0.0,
		"lead_factor": 0.0, "pressure": 0.0, "strafe_frequency": 0.025,
		"dodge_strength": 0.0, "dodge_horizon": 0.15, "dodge_range": 80.0,
		"reactive_shield_seconds": 0.0, "flank_commit": 0.0,
	},
	Difficulty.EASY: {
		"reaction_ticks": 20, "aim_error_degrees": 14.0, "lead_seconds": 0.45,
		"awareness_range": 1300.0, "pursuit": 0.42, "strafe": 0.32,
		"preferred_min": 300.0, "preferred_max": 620.0,
		"fire_range": 900.0, "fire_duty": 0.32, "shield_range": 480.0, "shield_duty": 0.05,
		"lead_factor": 0.25, "pressure": 0.05, "strafe_frequency": 0.03,
		"dodge_strength": 0.15, "dodge_horizon": 0.3, "dodge_range": 100.0,
		"reactive_shield_seconds": 0.08, "flank_commit": 0.15,
	},
	Difficulty.NEUTRAL: {
		"reaction_ticks": 10, "aim_error_degrees": 7.0, "lead_seconds": 0.75,
		"awareness_range": 1900.0, "pursuit": 0.65, "strafe": 0.5,
		"preferred_min": 250.0, "preferred_max": 540.0,
		"fire_range": 1450.0, "fire_duty": 0.58, "shield_range": 650.0, "shield_duty": 0.1,
		"lead_factor": 0.5, "pressure": 0.15, "strafe_frequency": 0.035,
		"dodge_strength": 0.35, "dodge_horizon": 0.45, "dodge_range": 125.0,
		"reactive_shield_seconds": 0.12, "flank_commit": 0.35,
	},
	Difficulty.SKILLED: {
		"reaction_ticks": 5, "aim_error_degrees": 2.5, "lead_seconds": 1.1,
		"awareness_range": 2600.0, "pursuit": 0.85, "strafe": 0.68,
		"preferred_min": 205.0, "preferred_max": 470.0,
		"fire_range": 2400.0, "fire_duty": 0.86, "shield_range": 900.0, "shield_duty": 0.16,
		"lead_factor": 0.78, "pressure": 0.38, "strafe_frequency": 0.047,
		"dodge_strength": 0.9, "dodge_horizon": 0.7, "dodge_range": 165.0,
		"reactive_shield_seconds": 0.22, "flank_commit": 0.75,
	},
	Difficulty.INSANE: {
		"reaction_ticks": 4, "aim_error_degrees": 0.15, "lead_seconds": 1.5,
		"awareness_range": 4000.0, "pursuit": 1.0, "strafe": 0.85,
		"preferred_min": 170.0, "preferred_max": 410.0,
		"fire_range": 4000.0, "fire_duty": 0.99, "shield_range": 1250.0, "shield_duty": 0.2,
		"lead_factor": 1.0, "pressure": 0.68, "strafe_frequency": 0.065,
		"dodge_strength": 1.45, "dodge_horizon": 0.95, "dodge_range": 220.0,
		"reactive_shield_seconds": 0.35, "flank_commit": 1.0,
	},
}

var _sequences: Dictionary = {}
var _next_decision_ticks: Dictionary = {}
var _blocked_engagements: Dictionary = {}
var _objective_navigation := NpcObjectiveNavigation.new()
var objective_roles: Dictionary = {}


func submit_inputs(
	world: AuthoritativeWorld,
	npc_peer_ids: Array[int],
	difficulties: Dictionary = {},
	overtime_elapsed: float = -1.0,
	objective_state: ObjectiveState = null
) -> void:
	for peer_id in npc_peer_ids:
		var combatant := world.combatants.get(peer_id) as CombatantState
		if combatant == null or not combatant.alive:
			continue
		var difficulty := int(difficulties.get(peer_id, Difficulty.NEUTRAL))
		var profile := difficulty_profile(difficulty)
		if world.server_tick < int(_next_decision_ticks.get(peer_id, 0)):
			continue
		var reaction_ticks := int(profile.reaction_ticks)
		var first_decision := not _next_decision_ticks.has(peer_id)
		_next_decision_ticks[peer_id] = (
			world.server_tick + reaction_ticks + posmod(peer_id, reaction_ticks)
			if first_decision and reaction_ticks > 1 else
			world.server_tick + reaction_ticks
		)
		var overtime_center := ArenaLayout.center(world.map_id)
		var overtime_minimum_radius := GameConstants.OVERTIME_MINIMUM_RADIUS
		if objective_state != null and GameModeRules.uses_hill(objective_state.mode):
			overtime_center = objective_state.position
			overtime_minimum_radius = GameModeRules.HILL_OVERTIME_MINIMUM_RADIUS
		var zone_steering := overtime_steering(
			combatant.position,
			overtime_elapsed,
			world.map_id,
			overtime_center,
			overtime_minimum_radius
		)
		var objective_steering := _objective_steering(world, combatant, objective_state)
		var target := _objective_target(world, combatant, objective_state)
		if target == null:
			target = _nearest_target(world, combatant, maxf(float(profile.awareness_range), FULL_MAP_ACQUISITION_RANGE))
		if target == null:
			_blocked_engagements.erase(peer_id)
			var idle_steering := (zone_steering + objective_steering).limit_length(1.0)
			_submit_decision(
				world,
				peer_id,
				_world_to_ship_input(idle_steering, combatant.aim_angle),
				combatant.aim_angle,
				false,
				false
			)
			continue
		var offset := target.position - combatant.position
		var distance := offset.length()
		var projectile_travel_time := distance / maxf(ProjectileState.travel_speed(combatant.stats), 1.0)
		var lead_time := minf(projectile_travel_time, float(profile.lead_seconds)) * float(profile.lead_factor)
		var predicted_offset := offset + target.velocity * lead_time
		var aim_angle := predicted_offset.angle() if not predicted_offset.is_zero_approx() else combatant.aim_angle
		var error_phase := float(world.server_tick) * 0.021 + float(peer_id % 997) * 0.73
		aim_angle += sin(error_phase) * deg_to_rad(float(profile.aim_error_degrees))
		var phase := float(world.server_tick + peer_id % 997) * float(profile.strafe_frequency)
		var forward := -float(profile.pursuit) if distance > float(profile.preferred_max) else (float(profile.pursuit) * 0.75 if distance < float(profile.preferred_min) else -float(profile.pursuit) * float(profile.pressure))
		var strafe := sin(phase) * float(profile.strafe)
		var tactical_movement := MovementSystem.ship_relative_to_world(
			Vector2(strafe, forward).limit_length(1.0),
			aim_angle
		)
		var escaping_close_contact := distance < CLOSE_CONTACT_ESCAPE_DISTANCE
		if escaping_close_contact:
			var away := -offset.normalized()
			if away.is_zero_approx():
				away = Vector2.from_angle(float(posmod(peer_id * 37 + target.peer_id * 19, 360)) * PI / 180.0)
			var sidestep := away.orthogonal()
			if peer_id < target.peer_id:
				sidestep = -sidestep
			tactical_movement = (away + sidestep * 0.35).normalized() * maxf(float(profile.pursuit), 0.65)
		var blocking_obstacle := _first_blocking_obstacle(combatant.position, target.position, world.map_id, world.arena_effects.hidden_cover)
		var has_line_of_sight := blocking_obstacle.is_empty()
		var breaking_blocked_loop := false
		if has_line_of_sight:
			_note_clear_engagement(peer_id, world.server_tick)
		else:
			breaking_blocked_loop = _blocked_engagement_requires_breakout(
				peer_id,
				target.peer_id,
				blocking_obstacle,
				world.server_tick
			)
		if not has_line_of_sight:
			# One member initially holds while the other takes a deterministic flank.
			# If the pair remains occluded, the holder commits to the opposite side so
			# brief sightline flickers cannot restart the same cover loop forever.
			var flank_phase := float(posmod(world.server_tick / maxi(int(profile.reaction_ticks), 1) + peer_id * 11, 100)) / 100.0
			var should_flank := peer_id > target.peer_id or breaking_blocked_loop or flank_phase < float(profile.flank_commit)
			tactical_movement = (
				Vector2.ZERO
				if not should_flank
				else _obstacle_flank_steering(
					combatant.position,
					target.position,
					blocking_obstacle,
					peer_id,
					target.peer_id,
					world.server_tick,
					peer_id < target.peer_id,
					world.map_id
				) * maxf(float(profile.pursuit), float(profile.strafe))
			)
		if not zone_steering.is_zero_approx():
			var boundary_radius := OvertimeSystem.radius_at(
				overtime_elapsed,
				overtime_center,
				overtime_minimum_radius
			)
			var outside_boundary := combatant.position.distance_to(overtime_center) > boundary_radius
			var tactical_weight := 0.08 if outside_boundary else 0.28
			tactical_movement = (zone_steering + tactical_movement * tactical_weight).limit_length(1.0)
		elif objective_roles.has(peer_id):
			# Arrival still means hold/escort, not a return to full combat kiting.
			# Preserve close-contact separation: otherwise two objective seekers
			# pin each other inside the no-fire escape radius indefinitely.
			tactical_movement = (
				(tactical_movement + objective_steering * 0.15).limit_length(1.0)
				if escaping_close_contact else
				(objective_steering + tactical_movement * 0.12).limit_length(1.0)
			)
		var projectile_threat := _projectile_evasion(world, combatant, profile)
		var evasion := projectile_threat.get("steering", Vector2.ZERO) as Vector2
		if not evasion.is_zero_approx():
			tactical_movement = (
				tactical_movement + evasion * float(profile.dodge_strength)
			).limit_length(1.0)
		var movement := _world_to_ship_input(tactical_movement, aim_angle)
		var shield_phase := float(posmod(world.server_tick + peer_id, 180)) / 180.0
		var shielding := not escaping_close_contact and distance < float(profile.shield_range) and (
			bool(projectile_threat.get("imminent", false)) or shield_phase < float(profile.shield_duty)
		)
		if world.arena_effects.warning or world.arena_effects.pulse_radius >= 0.0:
			var source_direction := world.arena_effects.pulse_center - combatant.position
			if not source_direction.is_zero_approx():
				aim_angle = source_direction.angle()
				shielding = true
				movement = _world_to_ship_input(tactical_movement, aim_angle)
		var fire_phase := float(posmod(world.server_tick + peer_id * 3, 120)) / 120.0
		var firing := not combatant.is_cloaked() and not escaping_close_contact and has_line_of_sight and not shielding and distance < float(profile.fire_range) and fire_phase < float(profile.fire_duty)
		var afterburner_special := (
			combatant.stats.afterburner_enabled
			and combatant.afterburner_cooldown_remaining <= 0.0
			and has_line_of_sight
			and distance > float(profile.preferred_max) * 1.35
		)
		var mine_special := (
			combatant.stats.mine_layer_enabled
			and combatant.mine_charges_remaining > 0
			and combatant.mine_cooldown_remaining <= 0.0
			and distance <= GameConstants.MINE_BLAST_RADIUS * 1.6
		)
		var missile_special := (
			combatant.stats.missile_launcher_enabled
			and float(profile.fire_duty) > 0.0
			and combatant.missile_charges_remaining > 0
			and combatant.missile_cooldown_remaining <= 0.0
			and has_line_of_sight
			and distance <= GameConstants.MISSILE_RANGE
		)
		var cloak_special := (
			combatant.stats.cloak_enabled
			and combatant.cloak_cooldown_remaining <= 0.0
			and not combatant.is_cloaked()
			and (combatant.health_fraction() <= 0.55 or distance > float(profile.preferred_max) * 1.5)
		)
		var special := afterburner_special or mine_special or missile_special or cloak_special
		var slot := 3 if cloak_special else (0 if afterburner_special else (2 if missile_special else 1))
		_submit_decision(world, peer_id, movement, aim_angle, firing, shielding, special, slot)


func _objective_steering(world: AuthoritativeWorld, combatant: CombatantState, objective: ObjectiveState) -> Vector2:
	var intent := objective_intent(world, combatant, objective)
	if intent.is_empty():
		objective_roles.erase(combatant.peer_id)
		_objective_navigation.remove_peer(combatant.peer_id)
		return Vector2.ZERO
	if objective_roles.get(combatant.peer_id, &"") != intent.role:
		_objective_navigation.remove_peer(combatant.peer_id)
	objective_roles[combatant.peer_id] = intent.role
	return _objective_navigation.steering(combatant.peer_id, combatant.position, intent.destination, world.map_id, world.server_tick, world.arena_effects.hidden_cover)


func objective_intent(world: AuthoritativeWorld, combatant: CombatantState, objective: ObjectiveState) -> Dictionary:
	if objective == null or not objective.active:
		return {}
	var mode := objective.mode
	if GameModeRules.uses_hill(mode):
		return {"role": &"defend" if objective.controller_id == combatant.peer_id else &"contest", "destination": objective.position}
	if not GameModeRules.uses_flag(mode):
		return {}
	var carrier_id := objective.flag_carrier_id
	var team_id := int(world.team_assignments.get(combatant.peer_id, 0))
	var zone_id := team_id if GameModeRules.is_team_mode(mode) else combatant.peer_id
	var home: Vector2 = objective.capture_zones.get(zone_id, combatant.position)
	if carrier_id == combatant.peer_id:
		return {"role": &"runner", "destination": home}
	var carrier := world.combatants.get(carrier_id) as CombatantState
	var flag_position := objective.flag_position
	var members: Array[int] = []
	for member_id in world.ordered_peer_ids_view():
		if member_id == combatant.peer_id or world.are_allies(combatant.peer_id, member_id):
			members.append(member_id)
	var role := NpcDraftPolicy.team_role(combatant.peer_id, members)
	if carrier != null and carrier.alive:
		if not world.are_allies(combatant.peer_id, carrier_id):
			# Flag ownership is public even when its carrier has cloak equipped.
			var intercept := carrier.position + carrier.velocity.limit_length(350.0) * 0.45
			if not NpcObjectiveNavigation._point_clear(intercept, world.map_id):
				intercept = carrier.position
			return {"role": &"intercept", "destination": intercept}
		var travel := (home - carrier.position).normalized()
		# Separate escorts across the return corridor; the defender clears home.
		if role == &"defend":
			return {"role": &"defend", "destination": home}
		var side := -1.0 if posmod(combatant.peer_id, 2) == 0 else 1.0
		var escort_position := carrier.position + travel * 120.0 + travel.orthogonal() * side * 100.0
		if not NpcObjectiveNavigation._point_clear(escort_position, world.map_id):
			escort_position = carrier.position
		return {"role": &"escort", "destination": escort_position}
	if role == &"defend" and members.size() >= 3:
		# Guard the return corridor rather than waiting behind the scoring base.
		var corridor := home.lerp(flag_position, 0.32)
		return {"role": role, "destination": corridor if NpcObjectiveNavigation._point_clear(corridor, world.map_id) else home}
	return {"role": &"retrieve", "destination": flag_position}


func _objective_target(world: AuthoritativeWorld, source: CombatantState, objective: ObjectiveState) -> CombatantState:
	if objective == null or not objective.active:
		return null
	var carrier_id := objective.flag_carrier_id
	var carrier := world.combatants.get(carrier_id) as CombatantState
	if carrier == null or not carrier.alive or carrier_id == source.peer_id:
		return null
	if not world.are_allies(source.peer_id, carrier_id):
		return carrier
	# Escorts engage the threat closest to their carrier, not a distant duel.
	var nearest: CombatantState
	var closest := 900.0 * 900.0
	for peer_id in world.ordered_peer_ids_view():
		var candidate := world.combatants[peer_id] as CombatantState
		if not candidate.alive or candidate.is_cloaked() or peer_id == source.peer_id or world.are_allies(source.peer_id, peer_id):
			continue
		var distance := candidate.position.distance_squared_to(carrier.position)
		if distance < closest:
			closest = distance
			nearest = candidate
	return nearest


func _projectile_evasion(world: AuthoritativeWorld, combatant: CombatantState, profile: Dictionary) -> Dictionary:
	var horizon := maxf(float(profile.dodge_horizon), 0.01)
	var dodge_range := maxf(float(profile.dodge_range), 1.0)
	var reactive_seconds := maxf(float(profile.reactive_shield_seconds), 0.0)
	var steering := Vector2.ZERO
	var imminent := false
	var query_radius := (
		world.maximum_projectile_speed() * horizon +
		combatant.velocity.length() * horizon +
		dodge_range
	)
	for projectile_id in world.projectile_threat_ids(
		combatant.position,
		query_radius,
		MAX_PROJECTILE_THREAT_CANDIDATES
	):
		var projectile := world.projectile_registry.get_projectile(projectile_id)
		if projectile == null:
			continue
		if projectile.owner_id == combatant.peer_id or world.are_allies(projectile.owner_id, combatant.peer_id) or projectile.velocity.is_zero_approx():
			continue
		var relative_position := projectile.position - combatant.position
		var relative_velocity := projectile.velocity - combatant.velocity
		var relative_speed_squared := relative_velocity.length_squared()
		if relative_speed_squared <= 0.001:
			continue
		var closest_time := -relative_position.dot(relative_velocity) / relative_speed_squared
		if closest_time < 0.0 or closest_time > horizon:
			continue
		var closest_offset := relative_position + relative_velocity * closest_time
		var closest_distance := closest_offset.length()
		if closest_distance > dodge_range:
			continue
		var away := -closest_offset.normalized()
		if away.is_zero_approx():
			away = projectile.velocity.normalized().orthogonal()
			if posmod(combatant.peer_id + projectile.projectile_id, 2) == 0:
				away = -away
		var clearance_weight := 1.0 - clampf(closest_distance / dodge_range, 0.0, 1.0)
		var urgency_weight := 1.0 - clampf(closest_time / horizon, 0.0, 1.0) * 0.35
		steering += away * clearance_weight * urgency_weight
		var collision_distance := GameConstants.SHIP_COLLISION_RADIUS + projectile.radius + 18.0
		if closest_distance <= collision_distance and closest_time <= reactive_seconds:
			imminent = true
	return {
		"steering": steering.limit_length(1.0),
		"imminent": imminent,
	}


static func is_valid_difficulty(difficulty: int) -> bool:
	return difficulty >= Difficulty.PASSIVE and difficulty <= Difficulty.INSANE


static func difficulty_name(difficulty: int) -> String:
	return DIFFICULTY_NAMES[difficulty] if is_valid_difficulty(difficulty) else "Neutral"


static func difficulty_profile(difficulty: int) -> Dictionary:
	return DIFFICULTY_PROFILES.get(difficulty, DIFFICULTY_PROFILES[Difficulty.NEUTRAL]) as Dictionary


func remove_peer(peer_id: int) -> void:
	_sequences.erase(peer_id)
	_next_decision_ticks.erase(peer_id)
	_blocked_engagements.erase(peer_id)
	_objective_navigation.remove_peer(peer_id)
	objective_roles.erase(peer_id)


func clear() -> void:
	_sequences.clear()
	_next_decision_ticks.clear()
	_blocked_engagements.clear()
	_objective_navigation.clear()
	objective_roles.clear()


func _blocked_engagement_requires_breakout(
	peer_id: int,
	target_peer_id: int,
	obstacle: Dictionary,
	server_tick: int
) -> bool:
	var obstacle_id := _obstacle_id(obstacle)
	var state := _blocked_engagements.get(peer_id, {}) as Dictionary
	var continues_same_engagement := (
		int(state.get("target_peer_id", -1)) == target_peer_id and
		int(state.get("obstacle_id", -999)) == obstacle_id and
		server_tick - int(state.get("last_blocked_tick", server_tick)) <= BLOCKED_LOOP_RESET_TICKS
	)
	if not continues_same_engagement:
		state = {
			"target_peer_id": target_peer_id,
			"obstacle_id": obstacle_id,
			"blocked_since_tick": server_tick,
		}
	state["last_blocked_tick"] = server_tick
	_blocked_engagements[peer_id] = state
	return server_tick - int(state.blocked_since_tick) >= BLOCKED_LOOP_BREAKOUT_TICKS


func _note_clear_engagement(peer_id: int, server_tick: int) -> void:
	var state := _blocked_engagements.get(peer_id, {}) as Dictionary
	if state.is_empty():
		return
	if server_tick - int(state.get("last_blocked_tick", server_tick)) >= BLOCKED_LOOP_RESET_TICKS:
		_blocked_engagements.erase(peer_id)


static func overtime_steering(
	position: Vector2,
	heat_elapsed: float,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID,
	zone_center: Vector2 = GameConstants.ARENA_SIZE * 0.5,
	minimum_radius: float = GameConstants.OVERTIME_MINIMUM_RADIUS
) -> Vector2:
	if not OvertimeSystem.is_warning(heat_elapsed) and not OvertimeSystem.is_active(heat_elapsed):
		return Vector2.ZERO
	var from_center := position - zone_center
	var distance := from_center.length()
	if distance <= 0.001:
		return Vector2.ZERO
	var safe_radius := OvertimeSystem.radius_at(heat_elapsed, zone_center, minimum_radius)
	if distance <= safe_radius - OVERTIME_NAVIGATION_MARGIN:
		return Vector2.ZERO
	var center_obstacle_radius := (
		ArenaLayout.central_radius(map_id)
		if zone_center.is_equal_approx(ArenaLayout.center(map_id)) else
		0.0
	)
	var minimum_navigable_radius := center_obstacle_radius + GameConstants.SHIP_COLLISION_RADIUS + 12.0
	var desired_radius := maxf(
		safe_radius - OVERTIME_NAVIGATION_MARGIN,
		minimum_navigable_radius
	)
	if distance <= desired_radius:
		return Vector2.ZERO
	var desired_position := zone_center + from_center.normalized() * desired_radius
	var urgency := 1.0 if distance > safe_radius else clampf(
		(distance - (safe_radius - OVERTIME_NAVIGATION_MARGIN)) /
		OVERTIME_NAVIGATION_MARGIN,
		0.35,
		1.0
	)
	return (desired_position - position).normalized() * urgency


func _submit_decision(world: AuthoritativeWorld, peer_id: int, movement: Vector2, aim_angle: float, firing: bool, shielding: bool, special: bool = false, special_slot: int = -1) -> void:
	var sequence := SequenceMath.increment(int(_sequences.get(peer_id, world.acknowledged_inputs.get(peer_id, 0))))
	_sequences[peer_id] = sequence
	world.submit_input(peer_id, PlayerInputFrame.new(sequence, world.server_tick, movement, aim_angle, firing, shielding, false, special, sequence, special_slot))


static func _world_to_ship_input(world_movement: Vector2, aim_angle: float) -> Vector2:
	return MovementSystem.world_to_ship_relative(world_movement, aim_angle)


static func _first_blocking_obstacle(from: Vector2, to: Vector2, map_id: StringName = ArenaLayout.DEFAULT_MAP_ID, hidden_cover: int = 0) -> Dictionary:
	var rectangles := ArenaCollisionSystem.cover_rectangles(map_id, hidden_cover)
	for rectangle_index in rectangles.size():
		var rectangle := rectangles[rectangle_index]
		var expanded := rectangle.grow(GameConstants.PROJECTILE_RADIUS + 2.0)
		if _segment_intersects_rect(from, to, expanded):
			return {"kind": &"rectangle", "index": rectangle_index, "rect": rectangle}
	var circles := ArenaLayout.circle_obstacles(map_id)
	for circle_index in circles.size():
		var circle := circles[circle_index] as Dictionary
		if _segment_intersects_circle(from, to, circle.center, float(circle.radius) + GameConstants.PROJECTILE_RADIUS):
			return {"kind": &"circle", "index": circle_index, "center": circle.center, "radius": circle.radius}
	return {}


static func _obstacle_id(obstacle: Dictionary) -> int:
	return int(obstacle.get("index", -1)) if obstacle.get("kind", &"") == &"rectangle" else -100 - int(obstacle.get("index", 0))


static func _obstacle_flank_steering(
	from: Vector2,
	to: Vector2,
	obstacle: Dictionary,
	peer_id: int,
	target_peer_id: int,
	server_tick: int,
	invert_side: bool = false,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
) -> Vector2:
	var epoch := floori(float(server_tick) / float(FLANK_DIRECTION_TICKS))
	var pair_seed := mini(peer_id, target_peer_id) * 31 + maxi(peer_id, target_peer_id) * 17 + epoch
	var positive_side := posmod(pair_seed, 2) == 0
	if invert_side:
		positive_side = not positive_side
	if obstacle.get("kind", &"") == &"rectangle":
		var rectangle := (obstacle.rect as Rect2).grow(
			GameConstants.SHIP_COLLISION_RADIUS + OBSTACLE_FLANK_CLEARANCE
		)
		var target_offset := to - from
		var waypoint := rectangle.get_center()
		if absf(target_offset.x) >= absf(target_offset.y):
			waypoint.x = rectangle.position.x if from.x < rectangle.get_center().x else rectangle.end.x
			waypoint.y = rectangle.end.y if positive_side else rectangle.position.y
		else:
			waypoint.x = rectangle.end.x if positive_side else rectangle.position.x
			waypoint.y = rectangle.position.y if from.y < rectangle.get_center().y else rectangle.end.y
		return (waypoint - from).normalized()
	var circle_center: Vector2 = obstacle.get("center", ArenaLayout.center(map_id))
	var radial := from - circle_center
	if radial.is_zero_approx():
		radial = Vector2.RIGHT
	var tangent := radial.normalized().orthogonal()
	if not positive_side:
		tangent = -tangent
	return (tangent + (to - from).normalized() * 0.12).normalized()


static func _segment_intersects_rect(from: Vector2, to: Vector2, rectangle: Rect2) -> bool:
	var direction := to - from
	var minimum_time := 0.0
	var maximum_time := 1.0
	for axis in 2:
		var origin := from.x if axis == 0 else from.y
		var delta := direction.x if axis == 0 else direction.y
		var minimum := rectangle.position.x if axis == 0 else rectangle.position.y
		var maximum := rectangle.end.x if axis == 0 else rectangle.end.y
		if absf(delta) <= 0.00001:
			if origin < minimum or origin > maximum:
				return false
			continue
		var first_time := (minimum - origin) / delta
		var second_time := (maximum - origin) / delta
		if first_time > second_time:
			var swap := first_time
			first_time = second_time
			second_time = swap
		minimum_time = maxf(minimum_time, first_time)
		maximum_time = minf(maximum_time, second_time)
		if minimum_time > maximum_time:
			return false
	return maximum_time > 0.001 and minimum_time < 0.999


static func _segment_intersects_circle(
	from: Vector2,
	to: Vector2,
	center: Vector2,
	radius: float
) -> bool:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.00001:
		return false
	var closest_time := clampf((center - from).dot(segment) / length_squared, 0.0, 1.0)
	if closest_time <= 0.001 or closest_time >= 0.999:
		return false
	var closest := from + segment * closest_time
	return closest.distance_squared_to(center) <= radius * radius


func _nearest_target(world: AuthoritativeWorld, source: CombatantState, awareness_range: float) -> CombatantState:
	var nearest: CombatantState
	var nearest_distance_squared := awareness_range * awareness_range
	for peer_id in world.ordered_peer_ids_view():
		if peer_id == source.peer_id or world.are_allies(source.peer_id, peer_id):
			continue
		var candidate := world.combatants[peer_id] as CombatantState
		if not candidate.alive or candidate.is_cloaked():
			continue
		var distance_squared := source.position.distance_squared_to(candidate.position)
		if distance_squared < nearest_distance_squared:
			nearest = candidate
			nearest_distance_squared = distance_squared
	return nearest
