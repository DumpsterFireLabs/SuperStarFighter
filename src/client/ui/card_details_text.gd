extends RefCounted


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
	var additive_names := card.additive_modifiers.keys()
	additive_names.sort()
	for property_value in additive_names:
		var property_name := String(property_value)
		var per_stack := float(card.additive_modifiers[property_value])
		stat_lines.append("%s  %+.2f each · %+.2f total" % [_card_stat_name(property_name), per_stack, per_stack * stacks])
	var multiplier_names := card.multiplicative_modifiers.keys()
	multiplier_names.sort()
	for property_value in multiplier_names:
		var property_name := String(property_value)
		var per_stack := float(card.multiplicative_modifiers[property_value])
		stat_lines.append("%s  ×%.2f each · ×%.2f total" % [_card_stat_name(property_name), per_stack, pow(per_stack, stacks)])
	var integer_names := card.integer_modifiers.keys()
	integer_names.sort()
	for property_value in integer_names:
		var property_name := String(property_value)
		var per_stack := int(card.integer_modifiers[property_value])
		stat_lines.append("%s  %+d each · %+d total" % [_card_stat_name(property_name), per_stack, per_stack * stacks])
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
		stat_lines.append("Special  Become invisible for 5 seconds on Special binding")
	elif card.special_behavior_id == &"rebound_shield":
		stat_lines.append("Shield Form  Rebound projectiles with stack-scaled damage and range")
	elif card.special_behavior_id == &"kinetic_vent":
		stat_lines.append("Shield Form  Release blocked damage as a defensive pulse")
	elif card.special_behavior_id == &"breakaway_thrusters":
		stat_lines.append("Escape System  Burst mobility after shield break or heavy hull damage")
	if stat_lines.is_empty():
		stat_lines.append("Special behavior described above")
	lines.append_array(stat_lines)
	return "\n".join(lines)


static func _card_stat_name(property_name: String) -> String:
	return property_name.replace("_", " ").capitalize()
