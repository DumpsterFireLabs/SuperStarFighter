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
	for resource in fields:
		var field := resource as ArenaMovementField
		if field == null:
			continue
		var strength := field.influence_at(combatant.position)
		if strength <= 0.0:
			continue
		var flow := field.flow_direction_at(combatant.position)
		var alignment := maxf(movement.normalized().dot(flow), 0.0) if not movement.is_zero_approx() else 0.0
		movement = (movement + flow * field.flow_input_strength * strength).limit_length(1.0)
		speed_multiplier *= lerpf(1.0, field.maximum_speed_multiplier, alignment * strength)
	return combatant.step_input_with_movement(frame, delta, movement, speed_multiplier)


static func influence_at(
	position: Vector2,
	map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
) -> float:
	var influence := 0.0
	for resource in ArenaLayout.movement_fields(map_id):
		var field := resource as ArenaMovementField
		if field != null:
			influence = maxf(influence, field.influence_at(position))
	return influence
