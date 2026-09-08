extends RefCounted

const Metadata = preload("res://src/shared/models/stat_metadata.gd")


static func tooltip(card: CardDefinition, stacks: int, stack_heading: String = "OWNED STACKS") -> String:
	var lines := PackedStringArray([
		card.display_name.to_upper(),
		"%s · %s · %s TIER DROP" % [card.rarity_name().to_upper(), card.category_name().to_upper(), card.rarity_drop_chance_text()],
		"",
		card.description,
		"",
		"%s: %d" % [stack_heading, stacks],
		"CARD STATS",
	])
	var stat_lines := PackedStringArray()
	for row in modifier_rows(card, stacks):
		stat_lines.append("%s  %s · %s" % [row.name, row.each, row.total])
	if card.special_behavior_id == &"beam_weapon":
		stat_lines.append("Weapon Form  Pulse beam")
	elif card.special_behavior_id == &"auto_repair":
		stat_lines.append("Special  Automatic hull repair")
	elif card.special_behavior_id == &"afterburner":
		stat_lines.append("Special  Forward burst on Special binding")
	elif card.special_behavior_id == &"mine_layer":
		stat_lines.append("Special  Drop an explosive mine on Special binding")
	elif card.special_behavior_id == &"missile_launcher":
		stat_lines.append("Special  Launch a limited-range seeker on Special binding")
	elif card.special_behavior_id == &"cloak":
		var cloak_stats := CombatStats.create_base()
		cloak_stats.cloak_capacity = maxi(stacks, 1)
		stat_lines.append("Fire/damage reveals; firing adds a 0.1s attack delay.")
		stat_lines.append("Special  Unlimited uses; %.1fs invisible, %.2fs cooldown from activation" % [cloak_stats.cloak_duration_seconds(), cloak_stats.cloak_cooldown_seconds()])
	elif card.special_behavior_id == &"rebound_shield":
		stat_lines.append("Shield Form  Rebound projectiles with stack-scaled damage and range")
	elif card.special_behavior_id == &"kinetic_vent":
		stat_lines.append("Shield Form  Release blocked damage as a defensive pulse")
	elif card.special_behavior_id == &"breakaway_thrusters":
		stat_lines.append("Escape System  Burst mobility after shield break or heavy hull damage")
	if stat_lines.is_empty():
		stat_lines.append("Special behavior described above")
	lines.append_array(stat_lines)
	if card.multiplicative_modifiers.has("drag") or card.additive_modifiers.has("drag"):
		lines.append("Passive braking slows the ship when movement input is released.")
	return "\n".join(lines)


static func _card_stat_name(property_name: String) -> String:
	return Metadata.label(StringName(property_name))


static func modifier_rows(card: CardDefinition, stacks: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for group in [card.additive_modifiers, card.multiplicative_modifiers, card.integer_modifiers]:
		var names: Array = group.keys()
		names.sort()
		for key in names:
			var property := StringName(key)
			var value := float(group[key])
			var multiplier: bool = is_same(group, card.multiplicative_modifiers)
			var each: String = "×%.2f" % value if multiplier else Metadata.format_value(property, value, true)
			var total: String = "×%.2f" % pow(value, stacks) if multiplier else Metadata.format_value(property, value * stacks, true)
			rows.append({"name": Metadata.label(property), "each": each + " each", "total": total + " total"})
	return rows
