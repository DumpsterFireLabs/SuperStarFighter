class_name ArenaMovementField
extends RefCounted

## Immutable runtime value. Authoring Resources never cross the simulation boundary.
var _values: Dictionary

var field_id: StringName:
	get:
		return _values[&"field_id"]
	set(_value):
		pass
var display_name: String:
	get:
		return _values[&"display_name"]
	set(_value):
		pass
var center: Vector2:
	get:
		return _values[&"center"]
	set(_value):
		pass
var inner_radius: float:
	get:
		return _values[&"inner_radius"]
	set(_value):
		pass
var outer_radius: float:
	get:
		return _values[&"outer_radius"]
	set(_value):
		pass
var clockwise: bool:
	get:
		return _values[&"clockwise"]
	set(_value):
		pass
var maximum_speed_multiplier: float:
	get:
		return _values[&"maximum_speed_multiplier"]
	set(_value):
		pass
var flow_input_strength: float:
	get:
		return _values[&"flow_input_strength"]
	set(_value):
		pass
var feather_width: float:
	get:
		return _values[&"feather_width"]
	set(_value):
		pass


func _init(source: ArenaMovementFieldDefinition) -> void:
	_values = {
		&"field_id": source.field_id,
		&"display_name": source.display_name,
		&"center": source.center,
		&"inner_radius": source.inner_radius,
		&"outer_radius": source.outer_radius,
		&"clockwise": source.clockwise,
		&"maximum_speed_multiplier": source.maximum_speed_multiplier,
		&"flow_input_strength": source.flow_input_strength,
		&"feather_width": source.feather_width,
	}
	_values.make_read_only()


func influence_at(position: Vector2) -> float:
	if not position.is_finite():
		return 0.0
	var distance := position.distance_to(center)
	if distance <= inner_radius or distance >= outer_radius:
		return 0.0
	var inner_strength := _smooth_unit((distance - inner_radius) / feather_width)
	var outer_strength := _smooth_unit((outer_radius - distance) / feather_width)
	return minf(inner_strength, outer_strength)


func flow_direction_at(position: Vector2) -> Vector2:
	var radial := position - center
	if radial.is_zero_approx() or not radial.is_finite():
		return Vector2.ZERO
	var normalized := radial.normalized()
	return Vector2(-normalized.y, normalized.x) if clockwise else Vector2(normalized.y, -normalized.x)


func mechanic_prompt() -> String:
	return "%s · %s" % [display_name.to_upper(), "CLOCKWISE" if clockwise else "COUNTERCLOCKWISE"]


static func _smooth_unit(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
