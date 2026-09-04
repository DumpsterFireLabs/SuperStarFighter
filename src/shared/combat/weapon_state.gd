class_name WeaponState
extends RefCounted

var ammunition: int = 0
var cooldown_remaining: float = 0.0
var reload_remaining: float = 0.0
var reloading: bool = false
var shot_sequence: int = 0
var cadence_remainder: float = 0.0


func reset(stats: CombatStats) -> void:
	ammunition = stats.magazine_size
	cooldown_remaining = 0.0
	reload_remaining = 0.0
	reloading = false
	shot_sequence = 0
	cadence_remainder = 0.0


func step(stats: CombatStats, delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	# Carry only the fractional interval that crossed zero this frame. Idle time
	# and reload time must not accumulate credit for a burst of catch-up shots.
	cadence_remainder = minf(maxf(safe_delta - cooldown_remaining, 0.0), 1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND) if cooldown_remaining > 0.0 and not reloading else 0.0
	cooldown_remaining = maxf(cooldown_remaining - safe_delta, 0.0)
	if not reloading:
		if ammunition <= 0:
			_start_reload(stats)
		return
	reload_remaining = maxf(reload_remaining - safe_delta, 0.0)
	if reload_remaining <= 0.0:
		reloading = false
		ammunition = stats.magazine_size


func try_fire(stats: CombatStats, shielding: bool) -> bool:
	if shielding or reloading or cooldown_remaining > 0.000001:
		return false
	if ammunition <= 0:
		_start_reload(stats)
		return false
	ammunition -= 1
	shot_sequence = SequenceMath.increment(shot_sequence)
	cooldown_remaining = 1.0 / stats.fire_rate - cadence_remainder
	cadence_remainder = 0.0
	if ammunition <= 0:
		_start_reload(stats)
	return true


func request_reload(stats: CombatStats) -> bool:
	if reloading or ammunition >= stats.magazine_size:
		return false
	_start_reload(stats)
	return true


func _start_reload(stats: CombatStats) -> void:
	if reloading:
		return
	reloading = true
	cadence_remainder = 0.0
	reload_remaining = stats.reload_duration
