class_name CombatantState
extends RefCounted

var peer_id: int = 0
var stats: CombatStats = CombatStats.create_base()
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var aim_angle: float = 0.0
var health: float = 0.0
var alive: bool = true
var time_since_damage: float = 0.0
var shield: ShieldState = ShieldState.new()
var weapon: WeaponState = WeaponState.new()


static func create(
	id: int,
	combat_stats: CombatStats,
	spawn_position: Vector2 = Vector2.ZERO
) -> CombatantState:
	var combatant := CombatantState.new()
	combatant.peer_id = id
	combatant.reset_for_heat(combat_stats, spawn_position)
	return combatant


func reset_for_heat(combat_stats: CombatStats, spawn_position: Vector2) -> void:
	stats = combat_stats.duplicate_stats()
	position = spawn_position
	velocity = Vector2.ZERO
	aim_angle = 0.0
	health = stats.max_health
	alive = true
	time_since_damage = 0.0
	shield.reset(stats)
	weapon.reset(stats)


func step(
	input_direction: Vector2,
	new_aim_angle: float,
	shield_held: bool,
	delta: float
) -> void:
	if not alive:
		velocity = Vector2.ZERO
		return
	aim_angle = MovementSystem.normalize_aim_angle(new_aim_angle, aim_angle)
	shield.step(shield_held, stats, delta)
	velocity = MovementSystem.step_velocity(
		velocity,
		input_direction,
		stats,
		delta,
		shield.active
	)
	weapon.step(stats, delta)
	var safe_delta := maxf(delta, 0.0)
	var previous_damage_time := time_since_damage
	time_since_damage += safe_delta
	if stats.auto_repair_enabled:
		var repair_time := maxf(
			time_since_damage - stats.auto_repair_delay,
			0.0
		) - maxf(previous_damage_time - stats.auto_repair_delay, 0.0)
		if repair_time > 0.0:
			health = minf(health + stats.auto_repair_rate * repair_time, stats.max_health)


func try_fire() -> bool:
	if not alive:
		return false
	return weapon.try_fire(stats, shield.active)


func request_reload() -> bool:
	if not alive:
		return false
	return weapon.request_reload(stats)


func apply_damage(amount: float) -> bool:
	if not alive or amount <= 0.0:
		return false
	time_since_damage = 0.0
	health = clampf(health - amount, 0.0, stats.max_health)
	if health > 0.0:
		return false
	alive = false
	velocity = Vector2.ZERO
	shield.active = false
	return true


func health_fraction() -> float:
	return health / stats.max_health if stats.max_health > 0.0 else 0.0
