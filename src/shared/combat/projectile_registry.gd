class_name ProjectileRegistry
extends RefCounted

var maximum_per_owner: int = GameConstants.MAX_PROJECTILES_PER_OWNER
var maximum_global: int = GameConstants.MAX_PROJECTILES_GLOBAL
var _by_id: Dictionary = {}
var _ordered_ids: Array[int] = []
var _owner_cleanup_remaining: Dictionary = {}


func add(projectile: ProjectileState) -> Array[int]:
	var removed: Array[int] = []
	if _by_id.has(projectile.projectile_id):
		remove(projectile.projectile_id)
	_by_id[projectile.projectile_id] = projectile
	_ordered_ids.append(projectile.projectile_id)
	while count_for_owner(projectile.owner_id) > maximum_per_owner:
		var oldest_owner_id := _oldest_for_owner(projectile.owner_id)
		if oldest_owner_id < 0:
			break
		remove(oldest_owner_id)
		removed.append(oldest_owner_id)
	while _ordered_ids.size() > maximum_global:
		var oldest_id: int = _ordered_ids[0]
		remove(oldest_id)
		removed.append(oldest_id)
	return removed


func remove(projectile_id: int) -> bool:
	if not _by_id.erase(projectile_id):
		return false
	_ordered_ids.erase(projectile_id)
	return true


func get_projectile(projectile_id: int) -> ProjectileState:
	return _by_id.get(projectile_id) as ProjectileState


func all_projectiles() -> Array[ProjectileState]:
	var result: Array[ProjectileState] = []
	for projectile_id in _ordered_ids:
		result.append(_by_id[projectile_id] as ProjectileState)
	return result


func size() -> int:
	return _ordered_ids.size()


func count_for_owner(owner_id: int) -> int:
	var count := 0
	for projectile_id in _ordered_ids:
		var projectile := _by_id[projectile_id] as ProjectileState
		if projectile.owner_id == owner_id:
			count += 1
	return count


func schedule_owner_cleanup(owner_id: int) -> void:
	_owner_cleanup_remaining[owner_id] = GameConstants.DEAD_OWNER_PROJECTILE_LIFETIME


func step_cleanup(delta: float) -> Array[int]:
	var removed: Array[int] = []
	var completed_owners: Array[int] = []
	for owner_value in _owner_cleanup_remaining:
		var owner_id := int(owner_value)
		var remaining := float(_owner_cleanup_remaining[owner_id]) - maxf(delta, 0.0)
		_owner_cleanup_remaining[owner_id] = remaining
		if remaining <= 0.000001:
			completed_owners.append(owner_id)
	for owner_id in completed_owners:
		_owner_cleanup_remaining.erase(owner_id)
		for projectile_id in _ordered_ids.duplicate():
			var projectile := _by_id[projectile_id] as ProjectileState
			if projectile.owner_id == owner_id:
				remove(projectile_id)
				removed.append(projectile_id)
	return removed


func _oldest_for_owner(owner_id: int) -> int:
	for projectile_id in _ordered_ids:
		var projectile := _by_id[projectile_id] as ProjectileState
		if projectile.owner_id == owner_id:
			return projectile_id
	return -1
