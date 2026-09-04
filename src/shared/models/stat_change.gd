class_name StatChange
extends RefCounted

## Effective build comparison shared directly by simulation and card UI.
var property: StringName
var before: float
var after: float
var limited: bool
var unchanged: bool


func _init(id: StringName, previous: float, next: float, at_limit: bool = false) -> void:
	property = id
	before = previous
	after = next
	limited = at_limit
	unchanged = is_equal_approx(previous, next)


func to_dictionary() -> Dictionary:
	return {"property": property, "before": before, "after": after, "limited": limited, "unchanged": unchanged}


static func from_dictionary(value: Dictionary) -> StatChange:
	return StatChange.new(StringName(value.property), float(value.before), float(value.after), bool(value.limited))
