class_name CardIdentity
extends RefCounted

## Identity comes from supported mechanics and beneficial modifiers, never names
## or rarity. A mixed card keeps its tradeoffs in the effective preview below.
const ROLES := {
	&"hull": "Hull durability", &"mobility": "Flight control", &"repair": "Hull recovery",
	&"shield": "Shield sustain", &"coverage": "Shield coverage", &"ram": "Shield assault",
	&"damage": "Direct damage", &"cycling": "Weapon uptime", &"velocity": "Projectile reach",
	&"scatter": "Multi shot", &"pierce": "Piercing", &"ricochet": "Ricochet",
	&"beam": "Beam weapon", &"boost": "Burst mobility", &"mine": "Area denial",
	&"missile": "Seeking ordnance", &"cloak": "Concealment", &"rebound": "Return fire",
	&"vent": "Shield pulse", &"escape": "Shield break escape",
}
const SPECIAL_FAMILIES := {
	&"auto_repair": &"repair", &"beam_weapon": &"beam", &"afterburner": &"boost",
	&"mine_layer": &"mine", &"missile_launcher": &"missile", &"cloak": &"cloak",
	&"rebound_shield": &"rebound", &"kinetic_vent": &"vent", &"breakaway_thrusters": &"escape",
}
const Metadata = preload("res://src/shared/models/stat_metadata.gd")
const SUMMARIES := {
	&"hull": "Strengthen your hull.", &"mobility": "Change how your ship handles.",
	&"repair": "Recover hull during combat.", &"shield": "Improve shield endurance.",
	&"coverage": "Change your shield coverage.", &"ram": "Turn your shield into a weapon.",
	&"damage": "Change the force of each shot.", &"cycling": "Change your weapon's firing cycle.",
	&"velocity": "Change projectile reach.", &"scatter": "Fire multiple projectiles.",
	&"pierce": "Shoot through targets.", &"ricochet": "Bounce shots off cover.",
	&"beam": "Convert your weapon to a beam.", &"boost": "Activate a burst of speed.",
	&"mine": "Deploy explosive mines.", &"missile": "Launch seeking missiles.",
	&"cloak": "Become temporarily invisible.", &"rebound": "Return blocked projectiles.",
	&"vent": "Release stored shield energy.", &"escape": "Boost away after heavy damage.",
}
const SPECIAL_FLAGS := Metadata.SPECIAL_FLAGS


static func family(card: CardDefinition) -> StringName:
	if SPECIAL_FAMILIES.has(card.special_behavior_id):
		return SPECIAL_FAMILIES[card.special_behavior_id]
	# Distinctive projectile forms outrank general damage/speed improvements.
	for entry in [[&"pierce_count", &"pierce"], [&"ricochet_count", &"ricochet"], [&"projectile_count", &"scatter"]]:
		if _beneficial_modifier(card, entry[0]):
			return entry[1]
	var scores: Dictionary = {}
	var base := CombatStats.create_base()
	var modifier_groups := [card.additive_modifiers, card.multiplicative_modifiers, card.integer_modifiers]
	for modifier_index in modifier_groups.size():
		var modifiers: Dictionary = modifier_groups[modifier_index]
		for key in modifiers:
			var property := StringName(key)
			if not _beneficial_modifier(card, property):
				continue
			var group := _stat_family(property, card.category)
			var weight := absf(float(modifiers[key]) - 1.0) if modifier_index == 1 else absf(float(modifiers[key])) / maxf(absf(float(base.get(property))), 1.0)
			scores[group] = float(scores.get(group, 0.0)) + weight
	var best: StringName = [&"hull", &"shield", &"damage"][card.category]
	var best_score := -1.0
	for group in scores:
		if float(scores[group]) > best_score:
			best_score = float(scores[group])
			best = group
	return best


static func role(card: CardDefinition) -> String:
	return ROLES[family(card)]


static func summary(card: CardDefinition) -> String:
	if SPECIAL_FAMILIES.has(card.special_behavior_id):
		return SUMMARIES[family(card)]
	# Distinguish tactical effects within a family without inventing numerical
	# benefits. Effective values and capped effects remain in the build preview.
	var tactics := {
		&"projectile_count": "Add projectiles to each volley.", &"pierce_count": "Carry shots through more targets.",
		&"ricochet_count": "Reach around cover with bouncing shots.", &"shield_arc_degrees": "Cover attacks from wider angles.",
		&"shield_capacity": "Absorb more pressure before depletion.", &"shield_regeneration_delay": "Start recharging your shield sooner.",
		&"shield_regeneration": "Recover shield energy faster.", &"shield_block_cost": "Spend less energy per blocked impact.",
		&"reload_duration": "Shorten your reload downtime.", &"magazine_size": "Fire more shots before reloading.",
		&"fire_rate": "Fire volleys more frequently.", &"projectile_speed": "Make shots reach targets sooner.",
		&"projectile_lifetime": "Keep shots travelling farther.", &"projectile_damage": "Deal more damage with each hit.",
		&"max_health": "Survive more hull damage.", &"max_speed": "Raise your top flight speed.",
		&"acceleration": "Build flight speed faster.",
	}
	for property in tactics:
		var property_family: StringName = {&"projectile_count": &"scatter", &"pierce_count": &"pierce", &"ricochet_count": &"ricochet"}.get(property, _stat_family(property, card.category))
		if _beneficial_modifier(card, property) and property_family == family(card):
			return tactics[property]
	return SUMMARIES[family(card)]


static func _stat_family(property: StringName, category: int) -> StringName:
	var value := String(property)
	if value.begins_with("auto_repair") or property == &"shield_damage_heal_fraction":
		return &"repair"
	if value.begins_with("shield_ram"):
		return &"ram"
	if property == &"shield_arc_degrees":
		return &"coverage"
	if value.begins_with("shield_"):
		return &"shield"
	if property in [&"max_speed", &"acceleration", &"drag"] or value.begins_with("afterburner"):
		return &"mobility"
	if property in [&"fire_rate", &"reload_duration", &"magazine_size"]:
		return &"cycling"
	if property in [&"projectile_speed", &"projectile_lifetime"]:
		return &"velocity"
	if property == &"max_health":
		return &"hull"
	return [&"hull", &"shield", &"damage"][category]


static func _beneficial_modifier(card: CardDefinition, property: StringName) -> bool:
	var additive := float(card.additive_modifiers.get(property, 0.0)) + float(card.integer_modifiers.get(property, 0))
	var multiplier := float(card.multiplicative_modifiers.get(property, 1.0)) - 1.0
	return additive < 0.0 or multiplier < 0.0 if Metadata.descriptor(property).polarity == CombatStatDescriptor.Polarity.LOWER else additive > 0.0 or multiplier > 0.0


## Three headline rows: unlocking a mechanic, meaningful changes, and a visible
## tradeoff where present. Limits and omitted changes are reported separately.
static func summarize(build: Dictionary, card: CardDefinition, catalog: CardCatalog, rows: Array[Dictionary]) -> Dictionary:
	var typed: Array[StatChange] = []
	for row in rows:
		typed.append(StatChange.from_dictionary(row))
	return summarize_typed(build, card, catalog, typed)


static func summarize_typed(build: Dictionary, card: CardDefinition, catalog: CardCatalog, rows: Array[StatChange]) -> Dictionary:
	var highlights: Array[Dictionary] = []
	var positives: Array[Dictionary] = []
	var downsides: Array[Dictionary] = []
	var neutral: Array[Dictionary] = []
	var limited := false
	if SPECIAL_FLAGS.has(card.special_behavior_id):
		var before := StatSystem.derive(build, catalog)
		if not bool(before.get(SPECIAL_FLAGS[card.special_behavior_id])):
			highlights.append({"text": "Unlock: %s" % role(card), "kind": &"benefit", "property": card.special_behavior_id})
	for row in rows:
		limited = limited or bool(row.limited)
		var property := StringName(row.property)
		var change := float(row.after) - float(row.before)
		var kind: StringName = Metadata.change_kind(property, change)
		var item := {"text": "%s %s → %s%s" % [stat_name(property), stat_value(row.before, property), stat_value(row.after, property), " *" if row.limited else ""], "kind": kind, "property": property}
		if kind == &"drawback":
			downsides.append(item)
		elif kind == &"benefit":
			positives.append(item)
		else:
			neutral.append(item)
	var slots_for_benefits := 3 - highlights.size() - (1 if not downsides.is_empty() else 0)
	for item in positives.slice(0, slots_for_benefits):
		highlights.append(item)
	if not downsides.is_empty():
		highlights.append(downsides[0])
	for item in neutral:
		if highlights.size() < 3:
			highlights.append(item)
	var omitted := rows.size() + (1 if highlights.any(func(item: Dictionary) -> bool: return item.property == card.special_behavior_id) else 0) - highlights.size()
	var notes := PackedStringArray()
	if limited:
		notes.append("* At limit")
	if downsides.size() > 1:
		notes.append("%d more tradeoffs" % (downsides.size() - 1))
	if omitted > 0:
		notes.append("+%d changes in details" % omitted)
	return {"rows": highlights, "note": " · ".join(notes), "omitted": omitted}


static func stat_name(property: StringName) -> String:
	return Metadata.label(property, true)


static func stat_value(value: float, property: StringName = &"") -> String:
	return Metadata.format_value(property, value)
