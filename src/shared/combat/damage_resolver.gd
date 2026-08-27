class_name DamageResolver
extends RefCounted


static func resolve_tick(
	combatants: Dictionary,
	damage_events: Array[Dictionary]
) -> Array[int]:
	var deaths: Array[int] = []
	for death in resolve_tick_with_attribution(combatants, damage_events):
		deaths.append(int(death.target_id))
	return deaths


static func resolve_tick_with_attribution(
	combatants: Dictionary,
	damage_events: Array[Dictionary]
) -> Array[Dictionary]:
	var ordered := damage_events.duplicate()
	ordered.sort_custom(_event_precedes)
	var deaths: Array[Dictionary] = []
	for event in ordered:
		var target_id := int(event.get("target_id", 0))
		var target := combatants.get(target_id) as CombatantState
		if target == null:
			continue
		if target.apply_damage(float(event.get("damage", 0.0))):
			deaths.append({
				"target_id": target_id,
				"killer_id": int(event.get("attacker_id", 0)),
			})
	return deaths


static func _event_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_id := int(left.get("projectile_id", 0))
	var right_id := int(right.get("projectile_id", 0))
	if left_id == right_id:
		return int(left.get("target_id", 0)) < int(right.get("target_id", 0))
	return left_id < right_id
