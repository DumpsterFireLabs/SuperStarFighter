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
var has_rebounded: bool = false
var hit_peer_ids: Dictionary = {}


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
	projectile.velocity = Vector2.from_angle(angle) * (4000.0 if projectile.is_beam else stats.projectile_speed)
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
	return mine


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
	return true


func rebound_toward(new_owner_id: int, source_position: Vector2) -> bool:
	if has_rebounded or is_mine or new_owner_id <= 0 or velocity.is_zero_approx():
		return false
	var return_direction := source_position - position
	if return_direction.is_zero_approx():
		return_direction = -velocity
	velocity = return_direction.normalized() * velocity.length()
	owner_id = new_owner_id
	damage *= 0.5
	lifetime_remaining *= 0.5
	has_rebounded = true
	return true
