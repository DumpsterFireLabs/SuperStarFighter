class_name CardDefinition
extends Resource

enum Category {
	SHIP,
	SHIELD,
	WEAPON,
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

const RARITY_DROP_CHANCES := {
	Rarity.COMMON: 45.0,
	Rarity.UNCOMMON: 28.0,
	Rarity.RARE: 16.0,
	Rarity.EPIC: 8.0,
	Rarity.LEGENDARY: 3.0,
}

@export var card_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var category: Category = Category.SHIP
@export var rarity: Rarity = Rarity.COMMON
@export_range(1, 10, 1) var max_stacks: int = 3
@export var additive_modifiers: Dictionary = {}
@export var multiplicative_modifiers: Dictionary = {}
@export var integer_modifiers: Dictionary = {}
@export var special_behavior_id: StringName


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if card_id.is_empty():
		errors.append("Card ID cannot be empty.")
	if display_name.strip_edges().is_empty():
		errors.append("Card %s requires a display name." % card_id)
	if description.strip_edges().is_empty():
		errors.append("Card %s requires a description." % card_id)
	if max_stacks < 1:
		errors.append("Card %s must allow at least one stack." % card_id)
	for modifiers in [additive_modifiers, multiplicative_modifiers, integer_modifiers]:
		for modifier_name in modifiers:
			if String(modifier_name).is_empty() or not modifiers[modifier_name] is float and not modifiers[modifier_name] is int:
				errors.append("Card %s has an invalid modifier entry." % card_id)
	if not RARITY_DROP_CHANCES.has(rarity):
		errors.append("Card %s has an invalid rarity." % card_id)
	return errors


func category_name() -> String:
	return Category.keys()[category].capitalize()


func rarity_name() -> String:
	return Rarity.keys()[rarity].capitalize()


func rarity_drop_chance() -> float:
	return float(RARITY_DROP_CHANCES.get(rarity, 0.0))


func rarity_color() -> Color:
	match rarity:
		Rarity.UNCOMMON: return Color("62ff9b")
		Rarity.RARE: return Color("42e8ff")
		Rarity.EPIC: return Color("d39cff")
		Rarity.LEGENDARY: return Color("fff36a")
		_: return Color("d6e2f2")
