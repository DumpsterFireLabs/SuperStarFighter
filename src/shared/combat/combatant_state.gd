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
var missile_charges_remaining: int = 0
var missile_cooldown_remaining: float = 0.0
var cloak_charges_remaining: int = 0
var cloak_remaining: float = 0.0
var cloak_cooldown_remaining: float = 0.0
var cloak_activation_latched: bool = false
var breakaway_remaining: float = 0.0
var breakaway_cooldown_remaining: float = 0.0
var burst_damage_accumulator: float = 0.0
var burst_damage_window_remaining: float = 0.0
var kinetic_vent_feedback_remaining: float = 0.0
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
	var previous_cloak_cooldown := cloak_cooldown_remaining
	stats = combat_stats.duplicate_stats()
	if refresh_heat_inventory:
		mine_charges_remaining = stats.mine_capacity
	else:
		mine_charges_remaining = mini(mine_charges_remaining, stats.mine_capacity)
	if refresh_heat_inventory:
		missile_charges_remaining = stats.missile_capacity
	else:
		missile_charges_remaining = mini(missile_charges_remaining, stats.missile_capacity)
	if refresh_heat_inventory:
		cloak_charges_remaining = stats.cloak_capacity
		cloak_cooldown_remaining = 0.0
	else:
		cloak_charges_remaining = mini(cloak_charges_remaining, stats.cloak_capacity)
		cloak_cooldown_remaining = previous_cloak_cooldown
	position = spawn_position
	velocity = Vector2.ZERO
	aim_angle = 0.0
	health = stats.max_health
	alive = true
	time_since_damage = 0.0
	afterburner_remaining = 0.0
	afterburner_cooldown_remaining = 0.0
	mine_cooldown_remaining = 0.0
	missile_cooldown_remaining = 0.0
	cloak_remaining = 0.0
	cloak_activation_latched = false
	breakaway_remaining = 0.0
	breakaway_cooldown_remaining = 0.0
	burst_damage_accumulator = 0.0
	burst_damage_window_remaining = 0.0
	kinetic_vent_feedback_remaining = 0.0
	shield.reset(stats)
	weapon.reset(stats)


func reset_match_inventory() -> void:
	mine_charges_remaining = 0
	mine_cooldown_remaining = 0.0
	stats.mine_capacity = 0
	stats.mine_layer_enabled = false
	missile_charges_remaining = 0
	missile_cooldown_remaining = 0.0
	stats.missile_capacity = 0
	stats.missile_launcher_enabled = false
	cloak_charges_remaining = 0
	cloak_remaining = 0.0
	cloak_cooldown_remaining = 0.0
	cloak_activation_latched = false
	stats.cloak_capacity = 0
	stats.cloak_enabled = false
	breakaway_remaining = 0.0
	breakaway_cooldown_remaining = 0.0
	burst_damage_accumulator = 0.0
	burst_damage_window_remaining = 0.0
	kinetic_vent_feedback_remaining = 0.0
	stats.breakaway_thrusters_enabled = false
	stats.kinetic_vent_enabled = false


func step(
	input_direction: Vector2,
	new_aim_angle: float,
	shield_held: bool,
	delta: float
) -> void:
	if not alive:
		velocity = Vector2.ZERO
		return
	var safe_delta := maxf(delta, 0.0)
	aim_angle = MovementSystem.normalize_aim_angle(new_aim_angle, aim_angle)
	afterburner_remaining = maxf(afterburner_remaining - safe_delta, 0.0)
	afterburner_cooldown_remaining = maxf(afterburner_cooldown_remaining - safe_delta, 0.0)
	mine_cooldown_remaining = maxf(mine_cooldown_remaining - safe_delta, 0.0)
	missile_cooldown_remaining = maxf(missile_cooldown_remaining - safe_delta, 0.0)
	cloak_remaining = maxf(cloak_remaining - safe_delta, 0.0)
	cloak_cooldown_remaining = maxf(cloak_cooldown_remaining - safe_delta, 0.0)
	breakaway_remaining = maxf(breakaway_remaining - safe_delta, 0.0)
	breakaway_cooldown_remaining = maxf(breakaway_cooldown_remaining - safe_delta, 0.0)
	kinetic_vent_feedback_remaining = maxf(kinetic_vent_feedback_remaining - safe_delta, 0.0)
	burst_damage_window_remaining = maxf(burst_damage_window_remaining - safe_delta, 0.0)
	if burst_damage_window_remaining <= 0.0:
		burst_damage_accumulator = 0.0
	shield.step(shield_held, stats, delta)
	if shield.consume_depletion_trigger():
		activate_breakaway()
	var breakaway_active := breakaway_remaining > 0.0
	var acceleration_multiplier := (
		stats.afterburner_acceleration_multiplier
		if afterburner_remaining > 0.0
		else 1.0
	)
	if breakaway_active:
		acceleration_multiplier *= GameConstants.BREAKAWAY_ACCELERATION_MULTIPLIER
	velocity = MovementSystem.step_velocity(
		velocity,
		input_direction,
		stats,
		delta,
		shield.active,
		stats.afterburner_speed_multiplier if afterburner_remaining > 0.0 else 1.0,
		acceleration_multiplier,
		GameConstants.BREAKAWAY_BRAKING_MULTIPLIER if breakaway_active else 1.0
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


func launch_missile() -> bool:
	if not alive or not stats.missile_launcher_enabled or missile_charges_remaining <= 0 or missile_cooldown_remaining > 0.0:
		return false
	missile_charges_remaining -= 1
	missile_cooldown_remaining = GameConstants.MISSILE_COOLDOWN_SECONDS
	return true


func activate_cloak() -> bool:
	if cloak_activation_latched:
		return false
	cloak_activation_latched = true
	if not alive or not stats.cloak_enabled or cloak_charges_remaining <= 0 or cloak_cooldown_remaining > 0.0 or is_cloaked():
		return false
	cloak_charges_remaining -= 1
	cloak_remaining = GameConstants.CLOAK_DURATION_SECONDS
	cloak_cooldown_remaining = GameConstants.CLOAK_COOLDOWN_SECONDS
	return true


func release_special_activation() -> void:
	cloak_activation_latched = false


func is_cloaked() -> bool:
	return alive and cloak_remaining > 0.0


func activate_breakaway() -> bool:
	if not alive or not stats.breakaway_thrusters_enabled or breakaway_cooldown_remaining > 0.0:
		return false
	breakaway_remaining = GameConstants.BREAKAWAY_DURATION_SECONDS
	breakaway_cooldown_remaining = stats.breakaway_cooldown
	return true


func mark_kinetic_vent_release() -> void:
	kinetic_vent_feedback_remaining = GameConstants.KINETIC_VENT_FEEDBACK_SECONDS


func apply_damage(amount: float) -> bool:
	if not alive or amount <= 0.0:
		return false
	cloak_remaining = 0.0
	time_since_damage = 0.0
	var applied_damage := minf(amount, health)
	health = clampf(health - amount, 0.0, stats.max_health)
	if health > 0.0:
		if burst_damage_window_remaining <= 0.0:
			burst_damage_accumulator = 0.0
		burst_damage_window_remaining = GameConstants.BREAKAWAY_BURST_WINDOW_SECONDS
		burst_damage_accumulator += applied_damage
		if burst_damage_accumulator >= stats.max_health * GameConstants.BREAKAWAY_BURST_HEALTH_FRACTION:
			activate_breakaway()
			burst_damage_accumulator = 0.0
			burst_damage_window_remaining = 0.0
		return false
	alive = false
	velocity = Vector2.ZERO
	shield.active = false
	breakaway_remaining = 0.0
	kinetic_vent_feedback_remaining = 0.0
	cloak_remaining = 0.0
	return true


func health_fraction() -> float:
	return health / stats.max_health if stats.max_health > 0.0 else 0.0
