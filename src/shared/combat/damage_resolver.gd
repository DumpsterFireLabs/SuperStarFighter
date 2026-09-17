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
	var deaths: Array[Dictionary] = []
	for impact in resolve_tick_with_feedback(combatants, damage_events):
		if bool(impact.lethal):
			deaths.append({"target_id": impact.target_id, "killer_id": impact.attacker_id})
	return deaths


# Report only damage actually applied. Later impacts in a lethal volley must not
# confirm damage against an already dead ship or inflate the attacker's readout.
static func resolve_tick_with_feedback(
	combatants: Dictionary,
	damage_events: Array[Dictionary]
) -> Array[Dictionary]:
	var ordered := damage_events.duplicate()
	ordered.sort_custom(_event_precedes)
	var impacts: Array[Dictionary] = []
	for event in ordered:
		var target_id := int(event.get("target_id", 0))
		var target := combatants.get(target_id) as CombatantState
		var amount := float(event.get("damage", 0.0))
		if target == null or not target.alive or not is_finite(amount) or amount <= 0.0:
			continue
		var health_before := target.health
		var lethal := target.apply_damage(amount)
		impacts.append({
			"target_id": target_id,
			"attacker_id": int(event.get("attacker_id", 0)),
			"damage": maxf(health_before - target.health, 0.0),
			"source": String(event.get("source", "projectile")),
			"mechanic": String(event.get("mechanic", "")),
			"original_shooter_id": int(event.get("original_shooter_id", 0)),
			"life_generation": target.life_generation,
			"health_before": health_before,
			"ricochet_count": int(event.get("ricochet_count", 0)),
			"lethal": lethal,
		})
	return impacts


static func _event_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_id := int(left.get("projectile_id", 0))
	var right_id := int(right.get("projectile_id", 0))
	if left_id == right_id:
		return int(left.get("target_id", 0)) < int(right.get("target_id", 0))
	return left_id < right_id
