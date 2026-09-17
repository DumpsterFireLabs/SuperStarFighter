extends RefCounted

## Orders interleaved delta/correction streams without discarding an entire
## recovery snapshot just because another projectile has a newer update.
const MAX_HISTORY: int = GameConstants.MAX_PROJECTILES_GLOBAL * 4
var _floor: int = -1
var _minimum_tick: int = -1
var _versions: Dictionary[int, int] = {}


static func stamp(tick: int, sequence: int) -> int:
	return (SequenceMath.normalize(tick) << 16) | (sequence & 0xffff)


static func newer(candidate: int, reference: int) -> bool:
	if candidate < 0:
		return false
	if reference < 0:
		return true
	var candidate_tick := candidate >> 16
	var reference_tick := reference >> 16
	if candidate_tick != reference_tick:
		return SequenceMath.is_newer(candidate_tick, reference_tick)
	var difference := (candidate - reference) & 0xffff
	return difference != 0 and difference < 0x8000


func reset(start_tick: int = -1) -> void:
	_versions.clear()
	_floor = -1
	_minimum_tick = start_tick


func accepts_packet(version: int) -> bool:
	if _minimum_tick >= 0 and not SequenceMath.is_newer_or_equal(version >> 16, _minimum_tick):
		return false
	return newer(version, _floor)


func accepts_entity(projectile_id: int, version: int) -> bool:
	return newer(version, _versions.get(projectile_id, -1))


func can_remove_missing(projectile_id: int, version: int) -> bool:
	return not newer(_versions.get(projectile_id, -1), version)


func record(projectile_id: int, version: int) -> void:
	_versions[projectile_id] = version


func finish_packet(version: int, complete: bool = false) -> void:
	if complete:
		_floor = version
		_prune()
	if _versions.size() > MAX_HISTORY:
		# If full recovery packets are lost for a long time, bound tombstones by
		# advancing the rejection floor before forgetting them. Otherwise an old
		# correction could resurrect an entity whose removal was forgotten.
		var ordered := _versions.values()
		ordered.sort_custom(func(left: int, right: int) -> bool: return newer(right, left))
		_floor = ordered[ordered.size() / 2]
		_prune()


func _prune() -> void:
	for projectile_id in _versions.keys():
		if not newer(_versions[projectile_id], _floor):
			_versions.erase(projectile_id)
