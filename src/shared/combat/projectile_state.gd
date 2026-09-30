class_name ProjectileState
extends RefCounted

var projectile_id: int = 0
var owner_id: int = 0
var shot_sequence: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var damage: float = 0.0
var knockback: float = 0.0
var radius: float = GameConstants.PROJECTILE_RADIUS
var lifetime_remaining: float = GameConstants.PROJECTILE_LIFETIME_SECONDS
var remaining_pierces: int = 0
var remaining_ricochets: int = 0
var is_beam: bool = false
var is_mine: bool = false
var is_missile: bool = false
var missile_target_id: int = 0
# Drones reuse missile_target_id for their current target and damage for hull.
var is_drone: bool = false
var is_drone_bolt: bool = false
var drone_slot: int = 0
var drone_fire_cooldown: float = 0.0
# Authority only: a cloaked owner's wing is withheld from replication and cannot be hit.
var drone_hidden: bool = false
# Presentation only: escorts face their owner's aim. Derived locally, never sent.
var drone_facing: float = -PI * 0.5
var mine_activation_remaining: float = 0.0
var kinetic_vent_displacement_remaining: float = 0.0
var has_rebounded: bool = false
var original_shooter_id: int = 0
var ricochet_count: int = 0
var hit_peer_ids: Dictionary = {}


static func travel_speed(stats: CombatStats) -> float:
	return 4000.0 if stats.beam_weapon else stats.projectile_speed


static func create(
	id: int,
	owner: int,
	sequence: int,
	spawn_position: Vector2,
	angle: float,
	stats: CombatStats
) -> ProjectileState:
	var projectile := ProjectileState.new()
	projectile.projectile_id = id
	projectile.owner_id = owner
	projectile.shot_sequence = sequence
	projectile.position = spawn_position
	projectile.is_beam = stats.beam_weapon
	projectile.velocity = Vector2.from_angle(angle) * travel_speed(stats)
	projectile.damage = stats.projectile_damage
	projectile.knockback = stats.projectile_knockback
	projectile.lifetime_remaining = stats.projectile_lifetime
	if projectile.is_beam:
		projectile.radius = 7.0
		projectile.lifetime_remaining = 0.18 * stats.projectile_lifetime / GameConstants.PROJECTILE_LIFETIME_SECONDS
	projectile.remaining_pierces = stats.pierce_count
	projectile.remaining_ricochets = stats.ricochet_count
	return projectile


static func create_mine(id: int, owner: int, spawn_position: Vector2) -> ProjectileState:
	var mine := ProjectileState.new()
	mine.projectile_id = id
	mine.owner_id = owner
	mine.position = spawn_position
	mine.velocity = Vector2.ZERO
	mine.damage = GameConstants.MINE_DAMAGE
	mine.radius = GameConstants.MINE_RADIUS
	mine.lifetime_remaining = INF
	mine.is_mine = true
	mine.mine_activation_remaining = GameConstants.MINE_ACTIVATION_SECONDS
	return mine


static func create_missile(
	id: int,
	owner: int,
	spawn_position: Vector2,
	angle: float,
	target_id: int = 0
) -> ProjectileState:
	var missile := ProjectileState.new()
	missile.projectile_id = id
	missile.owner_id = owner
	missile.position = spawn_position
	missile.velocity = Vector2.from_angle(angle) * GameConstants.MISSILE_SPEED
	missile.damage = GameConstants.MISSILE_DAMAGE
	missile.radius = GameConstants.MISSILE_RADIUS
	missile.lifetime_remaining = GameConstants.MISSILE_RANGE / GameConstants.MISSILE_SPEED
	missile.is_missile = true
	missile.missile_target_id = target_id
	return missile


static func create_drone(id: int, owner: int, spawn_position: Vector2, slot: int) -> ProjectileState:
	var drone := ProjectileState.new()
	drone.projectile_id = id
	drone.owner_id = owner
	drone.position = spawn_position
	drone.damage = GameConstants.DRONE_HEALTH
	drone.radius = GameConstants.DRONE_RADIUS
	drone.lifetime_remaining = GameConstants.DRONE_LIFETIME_SECONDS
	drone.is_drone = true
	drone.drone_slot = slot
	# Stagger the wing so four drones never fire on the same tick.
	drone.drone_fire_cooldown = GameConstants.DRONE_FIRE_INTERVAL_SECONDS * (0.5 + 0.25 * slot)
	return drone


static func create_drone_bolt(id: int, owner: int, spawn_position: Vector2, angle: float) -> ProjectileState:
	var bolt := ProjectileState.new()
	bolt.projectile_id = id
	bolt.owner_id = owner
	bolt.position = spawn_position
	bolt.velocity = Vector2.from_angle(angle) * GameConstants.DRONE_BOLT_SPEED
	bolt.damage = GameConstants.DRONE_BOLT_DAMAGE
	bolt.radius = GameConstants.DRONE_BOLT_RADIUS
	bolt.lifetime_remaining = GameConstants.DRONE_BOLT_LIFETIME_SECONDS
	bolt.is_drone_bolt = true
	return bolt


## Formation point for a wing slot: two escorts ahead-flank, two behind-flank.
static func drone_formation_point(owner_position: Vector2, owner_aim: float, slot: int) -> Vector2:
	var angles := [deg_to_rad(55.0), deg_to_rad(-55.0), deg_to_rad(140.0), deg_to_rad(-140.0)]
	return owner_position + Vector2.from_angle(owner_aim + float(angles[posmod(slot, angles.size())])) * GameConstants.DRONE_FORMATION_DISTANCE


## Shared by authority and client presentation so both follow the same path.
## The owner's velocity is fed forward so the wing holds formation in flight.
func steer_drone_toward(target_position: Vector2, owner_velocity: Vector2, owner_aim: float) -> void:
	if not is_drone:
		return
	drone_facing = owner_aim
	velocity = (owner_velocity + (target_position - position) * GameConstants.DRONE_FOLLOW_GAIN).limit_length(GameConstants.DRONE_MAX_SPEED)


## One cue per wing: the lead drone of a fresh deployment, not a wing
## re-sent after its owner's cloak ends.
func is_fresh_wing_lead() -> bool:
	return is_drone and drone_slot == 0 and lifetime_remaining >= GameConstants.DRONE_LIFETIME_SECONDS - 0.5


## Shared wall-aware motion so client drones slide along cover exactly as authority does.
func move_drone(delta: float, map_id: StringName, hidden_cover: int) -> void:
	var remaining := velocity * maxf(delta, 0.0)
	# One slide lets escorts skirt cover instead of sticking to it.
	for _attempt in 2:
		if remaining.is_zero_approx():
			return
		var finish := position + remaining
		var obstacle_hit: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(position, finish, radius, map_id, {}, hidden_cover)
		if obstacle_hit == null:
			position = finish
			return
		var normal := obstacle_hit.normal as Vector2
		var fraction := clampf(float(obstacle_hit.get("fraction", 0.0)), 0.0, 1.0)
		position = (obstacle_hit.position as Vector2) + normal * AuthoritativeWorld.COLLISION_SURFACE_EPSILON
		remaining = (remaining * (1.0 - fraction)).slide(normal)
		velocity = velocity.slide(normal)


func steer_missile_toward(target_position: Vector2, delta: float) -> void:
	if not is_missile or velocity.is_zero_approx():
		return
	var offset := target_position - position
	if offset.is_zero_approx():
		return
	var current_angle := velocity.angle()
	var angular_error := angle_difference(current_angle, offset.angle())
	var maximum_turn := GameConstants.MISSILE_TURN_RATE * maxf(delta, 0.0)
	velocity = Vector2.from_angle(current_angle + clampf(angular_error, -maximum_turn, maximum_turn)) * GameConstants.MISSILE_SPEED


func is_mine_armed() -> bool:
	return is_mine and mine_activation_remaining <= 0.0


func step_mine_activation(delta: float) -> void:
	if is_mine:
		mine_activation_remaining = maxf(mine_activation_remaining - maxf(delta, 0.0), 0.0)


func apply_kinetic_vent(direction: Vector2, speed: float) -> void:
	if not is_mine or direction.is_zero_approx():
		return
	velocity = direction.normalized() * maxf(speed, 0.0)
	kinetic_vent_displacement_remaining = GameConstants.KINETIC_VENT_MINE_DISPLACEMENT_SECONDS


func step_kinetic_vent_displacement(delta: float) -> bool:
	if kinetic_vent_displacement_remaining <= 0.0:
		return false
	kinetic_vent_displacement_remaining = maxf(
		kinetic_vent_displacement_remaining - maxf(delta, 0.0),
		0.0
	)
	return true


func step(delta: float) -> bool:
	var safe_delta := maxf(delta, 0.0)
	position += velocity * safe_delta
	lifetime_remaining -= safe_delta
	return lifetime_remaining > 0.0


func can_hit(peer_id: int) -> bool:
	return peer_id != owner_id and not hit_peer_ids.has(peer_id)


func register_hull_hit(peer_id: int) -> bool:
	if not can_hit(peer_id):
		return true
	hit_peer_ids[peer_id] = true
	if remaining_pierces > 0:
		remaining_pierces -= 1
		return true
	return false


func ricochet(collision_normal: Vector2) -> bool:
	if remaining_ricochets <= 0 or collision_normal.is_zero_approx():
		return false
	velocity = velocity.bounce(collision_normal.normalized())
	remaining_ricochets -= 1
	ricochet_count += 1
	return true


func rebound_toward(
	new_owner_id: int,
	source_position: Vector2,
	damage_factor: float = 0.5,
	range_factor: float = 0.5
) -> bool:
	if has_rebounded or is_mine or is_drone or new_owner_id <= 0 or velocity.is_zero_approx():
		return false
	var return_direction := source_position - position
	if return_direction.is_zero_approx():
		return_direction = -velocity
	velocity = return_direction.normalized() * velocity.length()
	original_shooter_id = owner_id
	owner_id = new_owner_id
	damage *= clampf(damage_factor, 0.0, 1.0)
	lifetime_remaining *= clampf(range_factor, 0.0, 1.0)
	has_rebounded = true
	missile_target_id = 0
	return true
