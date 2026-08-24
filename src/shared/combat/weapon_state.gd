class_name WeaponState
extends RefCounted

var ammunition: int = 0
var cooldown_remaining: float = 0.0
var reload_remaining: float = 0.0
var reloading: bool = false
var shot_sequence: int = 0


func reset(stats: CombatStats) -> void:
	ammunition = stats.magazine_size
	cooldown_remaining = 0.0
	reload_remaining = 0.0
	reloading = false
	shot_sequence = 0


func step(stats: CombatStats, delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
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
	shot_sequence += 1
	cooldown_remaining = 1.0 / stats.fire_rate
	if ammunition <= 0:
		_start_reload(stats)
	return true


func _start_reload(stats: CombatStats) -> void:
	if reloading:
		return
	reloading = true
	reload_remaining = stats.reload_duration
