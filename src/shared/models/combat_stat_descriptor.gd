class_name CombatStatDescriptor
extends RefCounted

enum Polarity { LOWER = -1, CONTEXTUAL = 0, HIGHER = 1 }
var property: StringName
var label: String
var short_label: String
var unit: String
var minimum: float
var maximum: float
var integer: bool
var polarity: Polarity
var upper_bound_property: StringName


func _init(id: StringName, definition: Array) -> void:
	property = id
	label = definition[0]
	short_label = definition[1]
	unit = definition[2]
	minimum = definition[3]
	maximum = definition[4]
	integer = definition[5]
	polarity = definition[6]
	upper_bound_property = definition[7] if definition.size() > 7 else &""


func bounded(value: float, upper_override: float = INF) -> Variant:
	var upper := minf(maximum, upper_override)
	return clampi(roundi(value), int(minimum), int(upper)) if integer else clampf(value, minimum, upper)


func format_value(value: float, signed: bool = false) -> String:
	var scaled := value * 100.0 if unit == "%" else value
	var number := str(roundi(scaled)) if is_equal_approx(scaled, roundf(scaled)) else "%.2f" % scaled
	if signed and scaled >= 0.0:
		number = "+" + number
	return number + ("" if unit.is_empty() else unit if unit in ["%", "°", "s", "×"] else " " + unit)


func is_beneficial(change: float) -> bool:
	return not is_zero_approx(change) and (polarity == Polarity.CONTEXTUAL or (change > 0.0 if polarity == Polarity.HIGHER else change < 0.0))
