class_name ArenaMovementFieldDefinition
extends Resource

## Static, map-authored movement influence shared by authority, prediction and presentation.
@export var field_id: StringName
@export var display_name: String
@export var center: Vector2
@export var inner_radius: float = 0.0
@export var outer_radius: float = 0.0
@export var clockwise: bool = true
@export_range(1.0, 2.0, 0.01) var maximum_speed_multiplier: float = 1.18
@export_range(0.0, 0.5, 0.01) var flow_input_strength: float = 0.16
@export_range(1.0, 200.0, 1.0) var feather_width: float = 48.0


func validation_errors(arena_bounds: Rect2) -> PackedStringArray:
	var errors := PackedStringArray()
	if String(field_id).is_empty() or String(field_id) != String(field_id).to_snake_case():
		errors.append("Movement field ID must be a nonempty snake_case identifier.")
	if display_name.strip_edges().is_empty():
		errors.append("Movement field display name is required.")
	if not center.is_finite():
		errors.append("Movement field center must be finite.")
	if not is_finite(inner_radius) or not is_finite(outer_radius) or inner_radius < 0.0 or outer_radius <= inner_radius:
		errors.append("Movement field radii must define a positive annulus.")
	elif not arena_bounds.encloses(Rect2(center - Vector2.ONE * outer_radius, Vector2.ONE * outer_radius * 2.0)):
		errors.append("Movement field must remain inside arena bounds.")
	if not is_finite(maximum_speed_multiplier) or maximum_speed_multiplier < 1.0 or maximum_speed_multiplier > 2.0:
		errors.append("Movement field speed multiplier must be between 1 and 2.")
	if not is_finite(flow_input_strength) or flow_input_strength < 0.0 or flow_input_strength > 0.5:
		errors.append("Movement field flow input must be between 0 and 0.5.")
	var band_width := outer_radius - inner_radius
	if not is_finite(feather_width) or feather_width <= 0.0 or feather_width * 2.0 > band_width:
		errors.append("Movement field feather must be positive and fit inside the annulus.")
	return errors
