class_name ArenaMovementSystem
extends RefCounted

## Supplies the exact same map-adjusted input to authority and client replay.


static func step_input(
	combatant: CombatantState,
	frame: PlayerInputFrame,
	delta: float,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
) -> int:
	return step_input_with_fields(combatant, frame, delta, ArenaLayout.movement_fields(map_id))


static func step_input_with_fields(
	combatant: CombatantState,
	frame: PlayerInputFrame,
	delta: float,
	fields: Array[ArenaMovementField]
) -> int:
	if fields.is_empty():
		return combatant.step_input(frame, delta)
	var movement := MovementSystem.ship_relative_to_world(frame.movement, frame.aim_angle)
	var speed_multiplier := 1.0
	var gravity := Vector2.ZERO
	for resource in fields:
		var field := resource as ArenaMovementField
		if field == null:
			continue
		var strength := field.influence_at(combatant.position)
		if strength <= 0.0:
			continue
		var flow := field.flow_direction_at(combatant.position)
		if field.gravity_acceleration > 0.0:
			gravity += flow * field.gravity_acceleration * strength
			continue
		var alignment := maxf(movement.normalized().dot(flow), 0.0) if not movement.is_zero_approx() else 0.0
		movement = (movement + flow * field.flow_input_strength * strength).limit_length(1.0)
		speed_multiplier *= lerpf(1.0, field.maximum_speed_multiplier, alignment * strength)
	var actions := combatant.step_input_with_movement(frame, delta, movement, speed_multiplier)
	if combatant.alive:
		combatant.velocity += gravity * maxf(delta, 0.0)
	return actions


## Strength of the flowing currents at a point, which drives the ship wake.
## Gravity wells have their own visuals and do not count as currents.
static func influence_at(
	position: Vector2,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
) -> float:
	var influence := 0.0
	for resource in ArenaLayout.movement_fields(map_id):
		var field := resource as ArenaMovementField
		if field != null and not field.is_gravity():
			influence = maxf(influence, field.influence_at(position))
	return influence


## Bends a projectile through gravity wells. Returns true once it has fallen
## past an event horizon and should be removed.
static func bend_projectile(projectile: ProjectileState, delta: float, map_id: StringName) -> bool:
	if projectile.is_mine:
		return false
	for field in ArenaLayout.movement_fields(map_id):
		if field.gravity_acceleration <= 0.0:
			continue
		if field.crushes(projectile.position, 0.0):
			return true
		var acceleration := field.flow_direction_at(projectile.position) * field.gravity_acceleration * field.influence_at(projectile.position)
		var speed := projectile.velocity.length()
		projectile.velocity += acceleration * maxf(delta, 0.0) * (0.35 if projectile.is_beam else 1.0)
		# Lensing changes the direction of light, preserving its travel speed.
		if projectile.is_beam and speed > 0.0:
			projectile.velocity = projectile.velocity.normalized() * speed
	return false
