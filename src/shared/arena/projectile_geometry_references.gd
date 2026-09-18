extends RefCounted

## Retain shared geometry only for the current map/cover revision.
var _map_id: StringName = &""
var _hidden_cover: int = -1
var _by_radius: Dictionary = {}


func prepare(map_id: StringName, hidden_cover: int) -> void:
	if map_id == _map_id and hidden_cover == _hidden_cover:
		return
	_map_id = map_id
	_hidden_cover = hidden_cover
	_by_radius.clear()


func for_radius(radius: float) -> Dictionary:
	if not _by_radius.has(radius):
		_by_radius[radius] = ArenaCollisionSystem.projectile_geometry(_map_id, radius, _hidden_cover)
	return _by_radius[radius]


func reset() -> void:
	_map_id = &""
	_hidden_cover = -1
	_by_radius.clear()
