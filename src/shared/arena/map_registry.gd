class_name MapRegistry
extends RefCounted

const DEFAULT_MAP_ID: StringName = &"core_arena"
const Definition = preload("res://src/shared/arena/map_definition.gd")
const DEFINITIONS: Array[Resource] = [
	preload("res://resources/maps/core_arena.tres"),
	preload("res://resources/maps/riftline.tres"),
	preload("res://resources/maps/prism_array.tres"),
	preload("res://resources/maps/twin_suns.tres"),
	preload("res://resources/maps/dead_freight.tres"),
	preload("res://resources/maps/longwave_array.tres"),
	preload("res://resources/maps/broken_orbit.tres"),
	preload("res://resources/maps/switchyard.tres"),
	preload("res://resources/maps/solar_tide.tres"),
	preload("res://resources/maps/relay_zero.tres"),
 ]
static var _entries: Dictionary = {}
static var _ids: Array[StringName] = []
static var _covers: Dictionary = {}
static var _circles: Dictionary = {}
static var _palettes: Dictionary = {}
static var _movement_fields: Dictionary = {}


static func validation_errors(definitions: Array[Resource] = DEFINITIONS) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	var names := {}
	for resource in definitions:
		var definition := resource as MapDefinition
		if definition == null:
			errors.append("Registry entry must be a MapDefinition.")
			continue
		errors.append_array(definition.validation_errors())
		if ids.has(definition.map_id): errors.append("Duplicate map ID: %s" % definition.map_id)
		if names.has(definition.display_name): errors.append("Duplicate map name: %s" % definition.display_name)
		ids[definition.map_id] = true
		names[definition.display_name] = true
	if not ids.has(DEFAULT_MAP_ID): errors.append("Registry must include the default map.")
	return errors


static func _ensure_loaded() -> void:
	if not _entries.is_empty():
		return
	var errors := validation_errors()
	assert(errors.is_empty(), "Invalid authored map registry: %s" % errors)
	if not errors.is_empty():
		push_error("Invalid authored map registry: %s" % errors)
		return
	for resource in DEFINITIONS:
		var definition := resource.duplicate(true) as MapDefinition
		definition.cover.make_read_only()
		definition.circles.make_read_only()
		definition.spawns.make_read_only()
		_entries[definition.map_id] = definition
		_ids.append(definition.map_id)
		_covers[definition.map_id] = definition.cover
		var obstacles: Array[Dictionary] = []
		for circle in definition.circles:
			var obstacle := {"center": Vector2(circle.x, circle.y), "radius": circle.z}
			obstacle.make_read_only()
			obstacles.append(obstacle)
		obstacles.make_read_only()
		_circles[definition.map_id] = obstacles
		var fields: Array[Resource] = []
		for field in definition.movement_fields:
			fields.append(field)
		fields.make_read_only()
		_movement_fields[definition.map_id] = fields
		var palette := {"floor": definition.floor_color, "border": definition.border_color, "obstacle": definition.obstacle_color, "line": definition.line_color}
		palette.make_read_only()
		_palettes[definition.map_id] = palette
	_ids.make_read_only()


static func ids() -> Array[StringName]:
	_ensure_loaded()
	return _ids.duplicate()


static func has_map(id: StringName) -> bool:
	_ensure_loaded()
	return _entries.has(id)


static func normalized(id: StringName) -> StringName:
	return id if has_map(id) else DEFAULT_MAP_ID


static func definition(id: StringName) -> MapDefinition:
	_ensure_loaded()
	return _entries.get(normalized(id)) as MapDefinition


static func cover(id: StringName) -> Array[Rect2]:
	_ensure_loaded()
	return _covers[normalized(id)] as Array[Rect2]


static func circles(id: StringName) -> Array[Dictionary]:
	_ensure_loaded()
	return _circles[normalized(id)] as Array[Dictionary]


static func palette(id: StringName) -> Dictionary:
	_ensure_loaded()
	return _palettes[normalized(id)] as Dictionary


static func movement_fields(id: StringName) -> Array[Resource]:
	_ensure_loaded()
	return _movement_fields[normalized(id)] as Array[Resource]
