class_name ProjectileState
extends RefCounted

var projectile_id: int = 0
var owner_id: int = 0
var shot_sequence: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var damage: float = 0.0
var radius: float = GameConstants.PROJECTILE_RADIUS
var lifetime_remaining: float = GameConstants.PROJECTILE_LIFETIME_SECONDS
var remaining_pierces: int = 0
var remaining_ricochets: int = 0
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
	projectile.velocity = Vector2.from_angle(angle) * stats.projectile_speed
	projectile.damage = stats.projectile_damage
	projectile.remaining_pierces = stats.pierce_count
	projectile.remaining_ricochets = stats.ricochet_count
	return projectile


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
