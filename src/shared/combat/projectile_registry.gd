class_name ProjectileRegistry
extends RefCounted

var maximum_per_owner: int = GameConstants.MAX_PROJECTILES_PER_OWNER
var maximum_global: int = GameConstants.MAX_PROJECTILES_GLOBAL
var _by_id: Dictionary = {}
var _ordered_ids: Array[int] = []
var _slot_by_id: Dictionary = {}
var _owner_counts: Dictionary = {}
var _owner_ordered_ids: Dictionary = {}
var _owner_heads: Dictionary = {}
var _owner_cleanup_remaining: Dictionary = {}
var _active_count: int = 0
var _mine_count: int = 0
var _ordered_head: int = 0
var revision: int = 0
var budget_evictions: int = 0
var _owner_budget_evictions: Dictionary = {}
var _moving_eviction_cursor: int = 0

const REMOVED_ID: int = -1
const COMPACT_MINIMUM_SLOTS: int = 128


func add(projectile: ProjectileState) -> Array[int]:
	var removed: Array[int] = []
	if _by_id.has(projectile.projectile_id):
		remove(projectile.projectile_id)
	_by_id[projectile.projectile_id] = projectile
	_slot_by_id[projectile.projectile_id] = _ordered_ids.size()
	_ordered_ids.append(projectile.projectile_id)
	_active_count += 1
	if projectile.is_mine:
		_mine_count += 1
	revision += 1
	_owner_counts[projectile.owner_id] = count_for_owner(projectile.owner_id) + 1
	var owner_ids := _owner_ordered_ids.get(projectile.owner_id, []) as Array
	owner_ids.append(projectile.projectile_id)
	_owner_ordered_ids[projectile.owner_id] = owner_ids
	if not _owner_heads.has(projectile.owner_id):
		_owner_heads[projectile.owner_id] = 0
	# Mines have a bounded reservation inside the existing total budgets.
	# Ordinary fire may replace moving ordnance, never a deployed mine.
	if projectile.is_mine:
		while mine_count_for_owner(projectile.owner_id) > mine_limit_per_owner():
			_evict(_oldest_for_owner(projectile.owner_id, true), removed)
		while _mine_count > mine_limit_global():
			_evict(_oldest_mine_global(), removed)
	while count_for_owner(projectile.owner_id) > maximum_per_owner:
		var oldest_owner_id := _oldest_for_owner(projectile.owner_id, false)
		if oldest_owner_id < 0:
			break
		_evict(oldest_owner_id, removed)
	while _active_count > maximum_global:
		var oldest_id := _oldest_moving_global()
		if oldest_id < 0:
			break
		_evict(oldest_id, removed)
	return removed


func remove(projectile_id: int) -> bool:
	var projectile := _by_id.get(projectile_id) as ProjectileState
	if projectile == null:
		return false
	_by_id.erase(projectile_id)
	_active_count -= 1
	if projectile.is_mine:
		_mine_count = maxi(_mine_count - 1, 0)
	revision += 1
	var slot := int(_slot_by_id.get(projectile_id, -1))
	_slot_by_id.erase(projectile_id)
	if slot >= 0 and slot < _ordered_ids.size():
		_ordered_ids[slot] = REMOVED_ID
	var owner_count := maxi(count_for_owner(projectile.owner_id) - 1, 0)
	if owner_count == 0:
		_owner_counts.erase(projectile.owner_id)
		_owner_ordered_ids.erase(projectile.owner_id)
		_owner_heads.erase(projectile.owner_id)
	else:
		_owner_counts[projectile.owner_id] = owner_count
		_advance_owner_head(projectile.owner_id)
		_compact_owner_queue_if_needed(projectile.owner_id)
	_advance_global_head()
	_compact_if_needed()
	return true


func transfer_owner(projectile_id: int, new_owner_id: int) -> Array[int]:
	var removed: Array[int] = []
	var projectile := _by_id.get(projectile_id) as ProjectileState
	if projectile == null or new_owner_id <= 0 or projectile.owner_id == new_owner_id:
		return removed
	var old_owner_id := projectile.owner_id
	_remove_owner_tracking(old_owner_id, projectile_id)
	projectile.owner_id = new_owner_id
	_owner_counts[new_owner_id] = count_for_owner(new_owner_id) + 1
	var owner_ids := _owner_ordered_ids.get(new_owner_id, []) as Array
	owner_ids.append(projectile_id)
	_owner_ordered_ids[new_owner_id] = owner_ids
	if not _owner_heads.has(new_owner_id):
		_owner_heads[new_owner_id] = 0
	if projectile.is_mine:
		while mine_count_for_owner(new_owner_id) > mine_limit_per_owner():
			_evict(_oldest_for_owner(new_owner_id, true), removed)
	while count_for_owner(new_owner_id) > maximum_per_owner:
		var oldest_owner_id := _oldest_for_owner(new_owner_id, false)
		if oldest_owner_id < 0:
			break
		_evict(oldest_owner_id, removed)
	revision += 1
	return removed


func get_projectile(projectile_id: int) -> ProjectileState:
	return _by_id.get(projectile_id) as ProjectileState


func all_projectiles() -> Array[ProjectileState]:
	var result: Array[ProjectileState] = []
	for projectile_id in _ordered_ids:
		if projectile_id != REMOVED_ID:
			result.append(_by_id[projectile_id] as ProjectileState)
	return result


## A stable, allocation-free view for authoritative hot paths. Entries equal to
## REMOVED_ID are tombstones and must be skipped by callers.
func ordered_ids_view() -> Array[int]:
	return _ordered_ids


func projectile_window(start_slot: int, maximum_count: int) -> Dictionary:
	var projectiles: Array[ProjectileState] = []
	if _ordered_ids.is_empty() or maximum_count <= 0:
		return {"projectiles": projectiles, "next_slot": 0}
	var slot := clampi(start_slot, 0, _ordered_ids.size() - 1)
	var visited := 0
	while visited < _ordered_ids.size() and projectiles.size() < maximum_count:
		var projectile_id := _ordered_ids[slot]
		if projectile_id != REMOVED_ID:
			var projectile := _by_id.get(projectile_id) as ProjectileState
			if projectile != null:
				projectiles.append(projectile)
		slot = (slot + 1) % _ordered_ids.size()
		visited += 1
	return {"projectiles": projectiles, "next_slot": slot}


func size() -> int:
	return _active_count


func has_mines() -> bool:
	return _mine_count > 0


func mine_count() -> int:
	return _mine_count


func retained_owner_slot_count() -> int:
	var result := 0
	for owner_ids in _owner_ordered_ids.values():
		result += (owner_ids as Array).size()
	return result


func count_for_owner(owner_id: int) -> int:
	return int(_owner_counts.get(owner_id, 0))


func mine_limit_per_owner() -> int:
	return mini(16, maxi(maximum_per_owner / 4, 1))


func mine_limit_global() -> int:
	return mini(512, maxi(maximum_global / 2, 1))


func mine_count_for_owner(owner_id: int) -> int:
	var count := 0
	for id in _owner_ordered_ids.get(owner_id, []):
		var projectile := get_projectile(int(id))
		if projectile != null and projectile.is_mine:
			count += 1
	return count


func budget_evictions_for_owner(owner_id: int) -> int:
	return int(_owner_budget_evictions.get(owner_id, 0))


func forget_owner_metrics(owner_id: int) -> void:
	_owner_budget_evictions.erase(owner_id)


func _evict(id: int, removed: Array[int]) -> void:
	var projectile := get_projectile(id)
	if projectile == null:
		return
	_owner_budget_evictions[projectile.owner_id] = budget_evictions_for_owner(projectile.owner_id) + 1
	budget_evictions += 1
	remove(id)
	removed.append(id)


func schedule_owner_cleanup(owner_id: int) -> void:
	# Capture this life's projectiles. A later respawn or ownership transfer must
	# never let an old death timer remove newly created ordnance.
	_owner_cleanup_remaining[owner_id] = {
		"remaining": GameConstants.DEAD_OWNER_PROJECTILE_LIFETIME,
		"ids": (_owner_ordered_ids.get(owner_id, []) as Array).duplicate(),
	}


func step_cleanup(delta: float) -> Array[int]:
	var removed: Array[int] = []
	var completed_owners: Array[int] = []
	for owner_value in _owner_cleanup_remaining:
		var owner_id := int(owner_value)
		var cleanup := _owner_cleanup_remaining[owner_id] as Dictionary
		var remaining := float(cleanup.remaining) - maxf(delta, 0.0)
		cleanup.remaining = remaining
		if remaining <= 0.000001:
			completed_owners.append(owner_id)
	for owner_id in completed_owners:
		var owner_ids := (_owner_cleanup_remaining[owner_id] as Dictionary).ids as Array
		_owner_cleanup_remaining.erase(owner_id)
		for projectile_value in owner_ids:
			var projectile_id := int(projectile_value)
			var projectile := get_projectile(projectile_id)
			if projectile != null and projectile.owner_id == owner_id:
				remove(projectile_id)
				removed.append(projectile_id)
	return removed


func _oldest_for_owner(owner_id: int, mines: bool = false) -> int:
	_advance_owner_head(owner_id)
	var owner_ids := _owner_ordered_ids.get(owner_id, []) as Array
	var head := int(_owner_heads.get(owner_id, 0))
	for index in range(head, owner_ids.size()):
		var projectile := get_projectile(int(owner_ids[index]))
		if projectile != null and projectile.is_mine == mines:
			return int(owner_ids[index])
	return -1


func _oldest_mine_global() -> int:
	for id in _ordered_ids:
		var projectile := get_projectile(id)
		if projectile != null and projectile.is_mine:
			return id
	return -1


func _oldest_moving_global() -> int:
	while _moving_eviction_cursor < _ordered_ids.size():
		var id := _ordered_ids[_moving_eviction_cursor]
		var projectile := get_projectile(id)
		if projectile != null and not projectile.is_mine:
			return id
		_moving_eviction_cursor += 1
	return -1


func _remove_owner_tracking(owner_id: int, projectile_id: int) -> void:
	var owner_ids := _owner_ordered_ids.get(owner_id, []) as Array
	owner_ids.erase(projectile_id)
	var owner_count := maxi(count_for_owner(owner_id) - 1, 0)
	if owner_count == 0:
		_owner_counts.erase(owner_id)
		_owner_ordered_ids.erase(owner_id)
		_owner_heads.erase(owner_id)
		return
	_owner_counts[owner_id] = owner_count
	_owner_ordered_ids[owner_id] = owner_ids
	_owner_heads[owner_id] = 0


func _advance_owner_head(owner_id: int) -> void:
	var owner_ids := _owner_ordered_ids.get(owner_id, []) as Array
	var head := int(_owner_heads.get(owner_id, 0))
	while head < owner_ids.size() and not _by_id.has(int(owner_ids[head])):
		head += 1
	_owner_heads[owner_id] = head


func _compact_owner_queue_if_needed(owner_id: int) -> void:
	var owner_ids := _owner_ordered_ids.get(owner_id, []) as Array
	if owner_ids.size() < COMPACT_MINIMUM_SLOTS:
		return
	var tombstone_count := owner_ids.size() - count_for_owner(owner_id)
	if tombstone_count * 2 < owner_ids.size():
		return
	var compacted: Array[int] = []
	for projectile_value in owner_ids:
		var projectile_id := int(projectile_value)
		if _by_id.has(projectile_id):
			compacted.append(projectile_id)
	_owner_ordered_ids[owner_id] = compacted
	_owner_heads[owner_id] = 0


func _oldest_global() -> int:
	_advance_global_head()
	if _ordered_head >= _ordered_ids.size():
		return -1
	return _ordered_ids[_ordered_head]


func _advance_global_head() -> void:
	while _ordered_head < _ordered_ids.size() and _ordered_ids[_ordered_head] == REMOVED_ID:
		_ordered_head += 1


func _compact_if_needed() -> void:
	if _ordered_ids.size() < COMPACT_MINIMUM_SLOTS:
		return
	var tombstone_count := _ordered_ids.size() - _active_count
	if tombstone_count * 2 < _ordered_ids.size():
		return
	var compacted: Array[int] = []
	_slot_by_id.clear()
	for projectile_id in _ordered_ids:
		if projectile_id == REMOVED_ID:
			continue
		_slot_by_id[projectile_id] = compacted.size()
		compacted.append(projectile_id)
	_ordered_ids = compacted
	_ordered_head = 0
	_moving_eviction_cursor = 0
