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
const DIFFICULTY_PROFILES := {
	Difficulty.PASSIVE: {
		"reaction_ticks": 36, "aim_error_degrees": 24.0, "lead_seconds": 0.0,
		"awareness_range": 900.0, "pursuit": 0.18, "strafe": 0.18,
		"preferred_min": 460.0, "preferred_max": 820.0,
		"fire_range": 0.0, "fire_duty": 0.0, "shield_range": 0.0, "shield_duty": 0.0,
	},
	Difficulty.EASY: {
		"reaction_ticks": 20, "aim_error_degrees": 14.0, "lead_seconds": 0.0,
		"awareness_range": 1300.0, "pursuit": 0.42, "strafe": 0.32,
		"preferred_min": 300.0, "preferred_max": 620.0,
		"fire_range": 900.0, "fire_duty": 0.32, "shield_range": 480.0, "shield_duty": 0.05,
	},
	Difficulty.NEUTRAL: {
		"reaction_ticks": 10, "aim_error_degrees": 7.0, "lead_seconds": 0.08,
		"awareness_range": 1900.0, "pursuit": 0.65, "strafe": 0.5,
		"preferred_min": 250.0, "preferred_max": 540.0,
		"fire_range": 1450.0, "fire_duty": 0.58, "shield_range": 650.0, "shield_duty": 0.1,
	},
	Difficulty.SKILLED: {
		"reaction_ticks": 5, "aim_error_degrees": 2.5, "lead_seconds": 0.18,
		"awareness_range": 2600.0, "pursuit": 0.85, "strafe": 0.68,
		"preferred_min": 220.0, "preferred_max": 500.0,
		"fire_range": 2100.0, "fire_duty": 0.8, "shield_range": 820.0, "shield_duty": 0.16,
	},
	Difficulty.INSANE: {
		"reaction_ticks": 2, "aim_error_degrees": 0.4, "lead_seconds": 0.3,
		"awareness_range": 4000.0, "pursuit": 1.0, "strafe": 0.85,
		"preferred_min": 190.0, "preferred_max": 460.0,
		"fire_range": 3200.0, "fire_duty": 0.94, "shield_range": 1050.0, "shield_duty": 0.22,
	},
}

var _sequences: Dictionary = {}
var _next_decision_ticks: Dictionary = {}
var _blocked_engagements: Dictionary = {}


func submit_inputs(
	world: AuthoritativeWorld,
	npc_peer_ids: Array[int],
	difficulties: Dictionary = {},
	overtime_elapsed: float = -1.0
) -> void:
	for peer_id in npc_peer_ids:
		var combatant := world.combatants.get(peer_id) as CombatantState
		if combatant == null or not combatant.alive:
			continue
		var difficulty := int(difficulties.get(peer_id, Difficulty.NEUTRAL))
		var profile := difficulty_profile(difficulty)
		if world.server_tick < int(_next_decision_ticks.get(peer_id, 0)):
			continue
		_next_decision_ticks[peer_id] = world.server_tick + int(profile.reaction_ticks)
		var zone_steering := overtime_steering(combatant.position, overtime_elapsed, world.map_id)
		var target := _nearest_target(world, combatant, maxf(float(profile.awareness_range), FULL_MAP_ACQUISITION_RANGE))
		if target == null:
			_blocked_engagements.erase(peer_id)
			_submit_decision(
				world,
				peer_id,
				_world_to_ship_input(zone_steering, combatant.aim_angle),
				combatant.aim_angle,
				false,
				false
			)
			continue
		var offset := target.position - combatant.position
		var distance := offset.length()
		var predicted_offset := offset + target.velocity * float(profile.lead_seconds)
		var aim_angle := predicted_offset.angle() if not predicted_offset.is_zero_approx() else combatant.aim_angle
		var error_phase := float(world.server_tick) * 0.021 + float(peer_id % 997) * 0.73
		aim_angle += sin(error_phase) * deg_to_rad(float(profile.aim_error_degrees))
		var phase := float(world.server_tick + peer_id % 997) * 0.035
		var forward := -float(profile.pursuit) if distance > float(profile.preferred_max) else (float(profile.pursuit) * 0.75 if distance < float(profile.preferred_min) else 0.0)
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
		var blocking_obstacle := _first_blocking_obstacle(combatant.position, target.position, world.map_id)
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
			var should_flank := peer_id > target.peer_id or breaking_blocked_loop
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
			var boundary_radius := OvertimeSystem.radius_at(overtime_elapsed)
			var outside_boundary := combatant.position.distance_to(ArenaLayout.center(world.map_id)) > boundary_radius
			var tactical_weight := 0.08 if outside_boundary else 0.28
			tactical_movement = (zone_steering + tactical_movement * tactical_weight).limit_length(1.0)
		var movement := _world_to_ship_input(tactical_movement, aim_angle)
		var shield_phase := float(posmod(world.server_tick + peer_id, 180)) / 180.0
		var shielding := not escaping_close_contact and distance < float(profile.shield_range) and shield_phase < float(profile.shield_duty)
		var fire_phase := float(posmod(world.server_tick + peer_id * 3, 120)) / 120.0
		var firing := not escaping_close_contact and has_line_of_sight and not shielding and distance < float(profile.fire_range) and fire_phase < float(profile.fire_duty)
		var special := (
			combatant.stats.afterburner_enabled
			and combatant.afterburner_cooldown_remaining <= 0.0
			and has_line_of_sight
			and distance > float(profile.preferred_max) * 1.35
		)
		_submit_decision(world, peer_id, movement, aim_angle, firing, shielding, special)


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


func clear() -> void:
	_sequences.clear()
	_next_decision_ticks.clear()
	_blocked_engagements.clear()


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


static func overtime_steering(position: Vector2, heat_elapsed: float, map_id: StringName = ArenaLayout.DEFAULT_MAP_ID) -> Vector2:
	if not OvertimeSystem.is_warning(heat_elapsed) and not OvertimeSystem.is_active(heat_elapsed):
		return Vector2.ZERO
	var center := ArenaLayout.center(map_id)
	var from_center := position - center
	var distance := from_center.length()
	if distance <= 0.001:
		return Vector2.ZERO
	var safe_radius := OvertimeSystem.radius_at(heat_elapsed)
	if distance <= safe_radius - OVERTIME_NAVIGATION_MARGIN:
		return Vector2.ZERO
	var minimum_navigable_radius := (
		ArenaLayout.central_radius(map_id) + GameConstants.SHIP_COLLISION_RADIUS + 12.0
	)
	var desired_radius := maxf(
		safe_radius - OVERTIME_NAVIGATION_MARGIN,
		minimum_navigable_radius
	)
	if distance <= desired_radius:
		return Vector2.ZERO
	var desired_position := center + from_center.normalized() * desired_radius
	var urgency := 1.0 if distance > safe_radius else clampf(
		(distance - (safe_radius - OVERTIME_NAVIGATION_MARGIN)) /
		OVERTIME_NAVIGATION_MARGIN,
		0.35,
		1.0
	)
	return (desired_position - position).normalized() * urgency


func _submit_decision(world: AuthoritativeWorld, peer_id: int, movement: Vector2, aim_angle: float, firing: bool, shielding: bool, special: bool = false) -> void:
	var sequence := SequenceMath.increment(int(_sequences.get(peer_id, world.acknowledged_inputs.get(peer_id, 0))))
	_sequences[peer_id] = sequence
	world.submit_input(peer_id, PlayerInputFrame.new(sequence, world.server_tick, movement, aim_angle, firing, shielding, false, special))


static func _world_to_ship_input(world_movement: Vector2, aim_angle: float) -> Vector2:
	return MovementSystem.world_to_ship_relative(world_movement, aim_angle)


static func _first_blocking_obstacle(from: Vector2, to: Vector2, map_id: StringName = ArenaLayout.DEFAULT_MAP_ID) -> Dictionary:
	var rectangles := ArenaLayout.cover_rectangles(map_id)
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
	for peer_value in world.combatants.keys():
		var peer_id := int(peer_value)
		if peer_id == source.peer_id:
			continue
		var candidate := world.combatants[peer_id] as CombatantState
		if not candidate.alive:
			continue
		var distance_squared := source.position.distance_squared_to(candidate.position)
		if distance_squared < nearest_distance_squared:
			nearest = candidate
			nearest_distance_squared = distance_squared
	return nearest
