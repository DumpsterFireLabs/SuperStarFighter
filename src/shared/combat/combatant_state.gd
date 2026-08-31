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
var afterburner_remaining: float = 0.0
var afterburner_cooldown_remaining: float = 0.0
var mine_charges_remaining: int = 0
var mine_cooldown_remaining: float = 0.0
var cloak_charges_remaining: int = 0
var cloak_remaining: float = 0.0
var cloak_activation_latched: bool = false
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


func reset_for_heat(
	combat_stats: CombatStats,
	spawn_position: Vector2,
	refresh_heat_inventory: bool = true
) -> void:
	var previous_cloak_capacity := stats.cloak_capacity
	var previous_cloak_charges := cloak_charges_remaining
	stats = combat_stats.duplicate_stats()
	if refresh_heat_inventory:
		mine_charges_remaining = stats.mine_capacity
	else:
		mine_charges_remaining = mini(mine_charges_remaining, stats.mine_capacity)
	if stats.cloak_capacity > previous_cloak_capacity:
		cloak_charges_remaining = mini(previous_cloak_charges + stats.cloak_capacity - previous_cloak_capacity, stats.cloak_capacity)
	elif stats.cloak_capacity < previous_cloak_capacity:
		cloak_charges_remaining = mini(previous_cloak_charges, stats.cloak_capacity)
	else:
		cloak_charges_remaining = mini(previous_cloak_charges, stats.cloak_capacity)
	position = spawn_position
	velocity = Vector2.ZERO
	aim_angle = 0.0
	health = stats.max_health
	alive = true
	time_since_damage = 0.0
	afterburner_remaining = 0.0
	afterburner_cooldown_remaining = 0.0
	mine_cooldown_remaining = 0.0
	cloak_remaining = 0.0
	cloak_activation_latched = false
	shield.reset(stats)
	weapon.reset(stats)


func reset_match_inventory() -> void:
	mine_charges_remaining = 0
	mine_cooldown_remaining = 0.0
	stats.mine_capacity = 0
	stats.mine_layer_enabled = false
	cloak_charges_remaining = 0
	cloak_remaining = 0.0
	cloak_activation_latched = false
	stats.cloak_capacity = 0
	stats.cloak_enabled = false


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
	var safe_delta := maxf(delta, 0.0)
	afterburner_remaining = maxf(afterburner_remaining - safe_delta, 0.0)
	afterburner_cooldown_remaining = maxf(afterburner_cooldown_remaining - safe_delta, 0.0)
	mine_cooldown_remaining = maxf(mine_cooldown_remaining - safe_delta, 0.0)
	cloak_remaining = maxf(cloak_remaining - safe_delta, 0.0)
	velocity = MovementSystem.step_velocity(
		velocity,
		input_direction,
		stats,
		delta,
		shield.active,
		stats.afterburner_speed_multiplier if afterburner_remaining > 0.0 else 1.0,
		stats.afterburner_acceleration_multiplier if afterburner_remaining > 0.0 else 1.0
	)
	weapon.step(stats, delta)
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
	if not alive or is_cloaked():
		return false
	return weapon.try_fire(stats, shield.active)


func request_reload() -> bool:
	if not alive:
		return false
	return weapon.request_reload(stats)


func activate_special() -> bool:
	if not alive or not stats.afterburner_enabled or afterburner_cooldown_remaining > 0.0:
		return false
	afterburner_remaining = stats.afterburner_duration
	afterburner_cooldown_remaining = stats.afterburner_cooldown
	var forward := Vector2.from_angle(aim_angle)
	velocity = (velocity + forward * stats.afterburner_impulse).limit_length(
		stats.max_speed * stats.afterburner_speed_multiplier
	)
	return true


func deploy_mine() -> bool:
	if not alive or not stats.mine_layer_enabled or mine_charges_remaining <= 0 or mine_cooldown_remaining > 0.0:
		return false
	mine_charges_remaining -= 1
	mine_cooldown_remaining = GameConstants.MINE_COOLDOWN_SECONDS
	return true


func activate_cloak() -> bool:
	if cloak_activation_latched:
		return false
	cloak_activation_latched = true
	if not alive or not stats.cloak_enabled or cloak_charges_remaining <= 0 or is_cloaked():
		return false
	cloak_charges_remaining -= 1
	cloak_remaining = GameConstants.CLOAK_DURATION_SECONDS
	return true


func release_special_activation() -> void:
	cloak_activation_latched = false


func is_cloaked() -> bool:
	return alive and cloak_remaining > 0.0


func apply_damage(amount: float) -> bool:
	if not alive or amount <= 0.0:
		return false
	cloak_remaining = 0.0
	time_since_damage = 0.0
	health = clampf(health - amount, 0.0, stats.max_health)
	if health > 0.0:
		return false
	alive = false
	velocity = Vector2.ZERO
	shield.active = false
	cloak_remaining = 0.0
	return true


func health_fraction() -> float:
	return health / stats.max_health if stats.max_health > 0.0 else 0.0
