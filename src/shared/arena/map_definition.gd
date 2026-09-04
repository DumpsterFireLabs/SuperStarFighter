class_name MapDefinition
extends Resource

## Authored geometry and presentation data shared by server, client and lab.
@export var map_id: StringName
@export var display_name: String
@export var cover: Array[Rect2] = []
@export var circles: Array[Vector3] = [] # center x/y, radius
@export var spawns: Array[Vector2] = []
@export var movement_fields: Array[Resource] = []
@export var central_radius: float = 0.0
@export var material_family: StringName = &"station"
@export var floor_color: Color
@export var border_color: Color
@export var obstacle_color: Color
@export var line_color: Color


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(map_id).is_empty() or String(map_id) != String(map_id).to_snake_case():
		errors.append("Map ID must be a nonempty snake_case identifier.")
	if display_name.strip_edges().is_empty():
		errors.append("Map display name is required.")
	if material_family not in [&"station", &"cargo", &"crystal", &"thermal", &"stone"]:
		errors.append("Unknown material family.")
	var bounds := Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)
	if not is_finite(central_radius) or central_radius < 0.0:
		errors.append("Central radius must be finite and nonnegative.")
	for rectangle in cover:
		if not rectangle.position.is_finite() or not rectangle.size.is_finite() or rectangle.size.x <= 0.0 or rectangle.size.y <= 0.0 or not bounds.encloses(rectangle):
			errors.append("Cover must have finite positive dimensions within the arena.")
	for circle in circles:
		if not circle.is_finite() or circle.z <= 0.0 or not bounds.encloses(Rect2(Vector2(circle.x, circle.y) - Vector2.ONE * circle.z, Vector2.ONE * circle.z * 2.0)):
			errors.append("Circles must have finite positive radii within the arena.")
	var field_ids := {}
	for resource in movement_fields:
		var field := resource as ArenaMovementFieldDefinition
		if field == null:
			errors.append("Movement field entry must be an ArenaMovementFieldDefinition.")
			continue
		errors.append_array(field.validation_errors(bounds))
		if field_ids.has(field.field_id):
			errors.append("Duplicate movement field ID: %s" % field.field_id)
		field_ids[field.field_id] = true
	for color in [floor_color, border_color, obstacle_color, line_color]:
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a) or color.a <= 0.0:
			errors.append("Map palette must contain finite visible colors.")
	if spawns.size() != GameConstants.MAX_PLAYERS:
		errors.append("Map must provide exactly 32 spawn anchors.")
	var safe_bounds := bounds.grow(-96.0)
	for index in spawns.size():
		var anchor := spawns[index]
		if not anchor.is_finite() or not safe_bounds.has_point(anchor):
			errors.append("Spawn anchor lies outside safe arena bounds.")
		for rectangle in cover:
			if rectangle.grow(96.0).has_point(anchor):
				errors.append("Spawn anchor overlaps cover.")
		for circle in circles:
			if anchor.distance_to(Vector2(circle.x, circle.y)) <= circle.z + 96.0:
				errors.append("Spawn anchor overlaps a circle.")
		for other in range(index + 1, spawns.size()):
			if anchor.distance_to(spawns[other]) < 160.0 - 0.001:
				errors.append("Spawn anchors must be at least 160 pixels apart.")
	return errors
