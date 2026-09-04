class_name ObjectiveState
extends RefCounted

# Authoritative objective model. Dictionaries are produced only for legacy NPC
# readers and transport; progress and capture zones have typed internal entries.
var mode: int = GameModeRules.Mode.DEATH_MATCH
var active: bool = false
var position: Vector2 = Vector2.ZERO
var controller_id: int = 0
var contested: bool = false
var progress: Dictionary[int, float] = {}
var flag_position: Vector2 = Vector2.ZERO
var flag_carrier_id: int = 0
var capture_zones: Dictionary[int, Vector2] = {}


func snapshot() -> ObjectiveState:
	var result := ObjectiveState.new()
	result.mode = mode
	result.active = active
	result.position = position
	result.controller_id = controller_id
	result.contested = contested
	result.progress.assign(progress)
	result.flag_position = flag_position
	result.flag_carrier_id = flag_carrier_id
	result.capture_zones.assign(capture_zones)
	return result


func write_view(result: Dictionary, copy_collections: bool = false) -> void:
	if result.is_empty():
		# Retain legacy String keys for the common wire fields. Mode-specific
		# properties were historically inserted by GDScript property access.
		result.merge({"active": active, "mode": mode,
			"mode_name": GameModeRules.mode_name(mode), "position": position,
			"zone_radius": GameModeRules.OBJECTIVE_ZONE_RADIUS})
	result.active = active
	result.mode = mode
	result.mode_name = GameModeRules.mode_name(mode)
	result.position = position
	result.zone_radius = GameModeRules.OBJECTIVE_ZONE_RADIUS
	if GameModeRules.uses_hill(mode):
		result.controller_id = controller_id
		result.contested = contested
		result.progress = _plain_copy(progress) if copy_collections else progress
		result.target_seconds = GameModeRules.HILL_HOLD_SECONDS
	elif GameModeRules.uses_flag(mode):
		result.flag_position = flag_position
		result.flag_carrier_id = flag_carrier_id
		result.pickup_radius = GameModeRules.FLAG_PICKUP_RADIUS
		result.capture_zones = _plain_copy(capture_zones) if copy_collections else capture_zones


func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	write_view(result, true)
	return result


static func _plain_copy(values: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result.merge(values)
	return result
