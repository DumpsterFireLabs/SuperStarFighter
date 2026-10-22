class_name MapDefinition
extends Resource

## Authored geometry and presentation data shared by server, client and lab.
@export var map_id: StringName
@export var display_name: String
@export var cover: Array[Rect2] = []
@export var circles: Array[Vector3] = [] # center x/y, radius
@export var spawns: Array[Vector2] = []
## Neutral flag location, authored for equal team access and full zone clearance.
@export var flag_spawn: Vector2 = Vector2.INF
@export var movement_fields: Array[Resource] = []
@export var central_radius: float = 0.0
@export var material_family: StringName = &"station"
@export var floor_color: Color
@export var border_color: Color
@export var obstacle_color: Color
@export var line_color: Color
## ArenaEffectRules mask that always runs on this map, ignoring host settings.
@export var intrinsic_effects: int = 0
## Damage per second-long burn for ships touching a circle obstacle.
@export var contact_damage: float = 0.0
## Random solar pulse interval in seconds; zero uses the host frequency.
@export var pulse_interval_range: Vector2 = Vector2.ZERO
## Replaces the default solar pulse warning when set.
@export var pulse_prompt: String = ""
## Final overtime radius for modes without an objective; zero uses the default.
@export var overtime_minimum_radius: float = 0.0


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(map_id).is_empty() or String(map_id) != String(map_id).to_snake_case():
		errors.append("Map ID must be a nonempty snake_case identifier.")
	if display_name.strip_edges().is_empty():
		errors.append("Map display name is required.")
	if material_family not in [&"station", &"cargo", &"crystal", &"thermal", &"stone"]:
		errors.append("Unknown material family.")
	var bounds := Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)
	if intrinsic_effects < 0 or intrinsic_effects > 7:
		errors.append("Intrinsic effects must be an arena effect mask.")
	if not is_finite(contact_damage) or contact_damage < 0.0:
		errors.append("Contact damage must be finite and nonnegative.")
	if not pulse_interval_range.is_zero_approx() and (not pulse_interval_range.is_finite() or pulse_interval_range.x < 6.0 or pulse_interval_range.y < pulse_interval_range.x):
		errors.append("Pulse interval range must be at least 6 seconds and ordered.")
	if not is_finite(overtime_minimum_radius) or overtime_minimum_radius < 0.0:
		errors.append("Overtime minimum radius must be finite and nonnegative.")
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
	var objective_radius := GameConstants.OBJECTIVE_ZONE_RADIUS
	if not flag_spawn.is_finite() or not bounds.grow(-objective_radius).has_point(flag_spawn):
		errors.append("Flag spawn must be finite and keep its full zone inside the arena.")
	else:
		for rectangle in cover:
			if rectangle.grow(objective_radius).has_point(flag_spawn):
				errors.append("Flag zone overlaps cover.")
		for circle in circles:
			if flag_spawn.distance_to(Vector2(circle.x, circle.y)) <= circle.z + objective_radius:
				errors.append("Flag zone overlaps a circle.")
		for resource in movement_fields:
			var field := resource as ArenaMovementFieldDefinition
			if field != null and field.event_horizon_radius > 0.0 and flag_spawn.distance_to(field.center) < field.event_horizon_radius + objective_radius + GameConstants.OBJECTIVE_HAZARD_CLEARANCE:
				errors.append("Flag zone is too close to an event horizon.")
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
		for resource in movement_fields:
			var field := resource as ArenaMovementFieldDefinition
			if field != null and field.event_horizon_radius > 0.0 and anchor.distance_to(field.center) <= field.event_horizon_radius + 96.0:
				errors.append("Spawn anchor %d overlaps an event horizon." % index)
		for other in range(index + 1, spawns.size()):
			if anchor.distance_to(spawns[other]) < 160.0 - 0.001:
				errors.append("Spawn anchors must be at least 160 pixels apart.")
	# Do not build a navigation graph from malformed or non-finite geometry.
	if errors.is_empty():
		var navigation_circles: Array[Vector3] = circles.duplicate()
		for resource in movement_fields:
			var field := resource as ArenaMovementFieldDefinition
			if field.event_horizon_radius > 0.0:
				navigation_circles.append(Vector3(field.center.x, field.center.y, field.event_horizon_radius))
		var navigation := MapNavigationValidation.new(cover, navigation_circles, flag_spawn)
		for index in spawns.size():
			if not navigation.reaches_destination(spawns[index]):
				errors.append("Map %s spawn %d has no ship-clear route to the flag with all doors closed." % [map_id, index])
			if not navigation.has_spawn_exits(spawns[index]):
				errors.append("Map %s spawn %d needs two 96px-wide, 180px-long exits at least 90 degrees apart into the flag's navigation region with all doors closed." % [map_id, index])
		var final_radius := overtime_minimum_radius if overtime_minimum_radius > 0.0 else GameConstants.OVERTIME_MINIMUM_RADIUS
		if not navigation.reaches_overtime(final_radius):
			errors.append("Map %s has no ship-clear route from the flag region into the final overtime disk with all doors closed." % map_id)
	return errors
