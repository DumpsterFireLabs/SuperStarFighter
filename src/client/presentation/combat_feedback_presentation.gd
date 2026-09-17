class_name CombatFeedbackPresentation
extends RefCounted


static func hit_text(feedback: Dictionary) -> String:
	var count := int(feedback.get("hit_count", 0))
	if count <= 0:
		return ""
	return "HIT%s · %s DAMAGE" % [" ×%d" % count if count > 1 else "", _damage_text(float(feedback.get("hit_damage", 0.0)))]


static func block_text(feedback: Dictionary) -> String:
	var count := int(feedback.get("blocked_count", 0))
	if count <= 0:
		return ""
	var reason := String(feedback.get("last_block_reason", "shield"))
	var text := "SHOT REFLECTED" if reason == "rebound" else "SHOT BLOCKED"
	if reason == "perfect_guard":
		text += " · PERFECT GUARD"
	return text + (" ×%d" % count if count > 1 else "")


static func guard_text(feedback: Dictionary) -> String:
	var count := int(feedback.get("guard_count", 0))
	if count <= 0:
		return ""
	var reason := String(feedback.get("last_guard_reason", "shield"))
	var text := "SHIELD BLOCK"
	if reason == "rebound":
		text = "REBOUND"
	elif reason == "perfect_guard":
		text = "PERFECT GUARD"
	return text + (" ×%d" % count if count > 1 else "")


static func death_text(recap: Dictionary, local_peer_id: int, names: Dictionary = {}) -> String:
	if recap.is_empty():
		return ""
	var source := String(recap.get("source", "unknown"))
	var killer_id := int(recap.get("killer_id", 0))
	var heading := "DESTROYED BY "
	if source == "overtime":
		heading += "OVERTIME"
	elif killer_id == local_peer_id and killer_id != 0:
		heading += "YOUR OWN " + source_name(source)
	elif killer_id == 0:
		heading += source_name(source)
	else:
		var pilot_name := String(names.get(killer_id, names.get(str(killer_id), "Pilot %d" % killer_id)))
		heading += pilot_name + " · " + source_name(source)
	var detail := mechanic_text(String(recap.get("mechanic", "")))
	var damage := float(recap.get("damage", 0.0))
	if damage > 0.0:
		detail = "Final hit: %s damage%s" % [_damage_text(damage), " · " + detail if not detail.is_empty() else ""]
	return heading + ("\n" + detail if not detail.is_empty() else "")


static func source_name(source: String) -> String:
	match source:
		"projectile": return "CANNON"
		"beam": return "BEAM"
		"mine": return "MINE BLAST"
		"missile": return "HOMING MISSILE"
		"shield_ram": return "SHIELD RAM"
		"rebound_shield": return "REBOUND SHIELD"
		"overtime": return "OVERTIME"
		"solar_pulse": return "SOLAR PULSE"
	return "COMBAT DAMAGE"


static func mechanic_text(mechanic: String) -> String:
	match mechanic:
		"reflected": return "Reflected by Rebound Shield"
		"outside_shield_arc": return "Hit outside your shield arc"
		"shield_depleted": return "Your shield was depleted"
		"blast_ignores_shield": return "Mine blasts bypass shields"
		"ram_contact": return "Shield Ram contact damage"
		"rebound_contact": return "Rebound Shield radius damage"
	return ""


static func _damage_text(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
