class_name CardDefinition
extends Resource

enum Category {
	SHIP,
	SHIELD,
	WEAPON,
}

@export var card_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var category: Category = Category.SHIP
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
	return errors


func category_name() -> String:
	return Category.keys()[category].capitalize()

