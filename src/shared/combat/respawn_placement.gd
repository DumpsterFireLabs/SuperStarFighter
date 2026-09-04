class_name RespawnPlacement
extends RefCounted

const SHIP_CLEARANCE: float = 60.0
const ENEMY_CLEARANCE: float = 650.0
const THREAT_LOOKAHEAD_SECONDS: float = CombatSpatialIndex.RESPAWN_THREAT_LOOKAHEAD_SECONDS


static func choose(world: AuthoritativeWorld, peer_id: int, preferred: Vector2, safe_center: Vector2, safe_radius: float) -> Vector2:
	var candidates: Array[Vector2] = [preferred, safe_center]
	candidates.append_array(ArenaLayout.spawn_anchors(world.map_id))
	# Spawn anchors alone are often all outside late overtime. Sample the safe
	# interior as well, in a fixed order so identical worlds choose identically.
	for fraction in [0.25, 0.5, 0.8]:
		for sample in 16:
			candidates.append(safe_center + Vector2.from_angle(TAU * sample / 16.0) * maxf(safe_radius - GameConstants.SHIP_COLLISION_RADIUS, 0.0) * fraction)
	var best := Vector2.INF
	var best_score := INF
	for candidate in candidates:
		if candidate.distance_to(safe_center) + GameConstants.SHIP_COLLISION_RADIUS > safe_radius:
			continue
		if not ArenaCollisionSystem.is_ship_position_clear(candidate, world.map_id):
			continue
		var score := candidate.distance_to(preferred) * 0.05
		var occupied := false
		for other_value in world.combatants.values():
			var other := other_value as CombatantState
			if not other.alive or other.peer_id == peer_id:
				continue
			var distance := candidate.distance_to(other.position)
			if distance < SHIP_CLEARANCE:
				occupied = true
				break
			if not world.are_allies(peer_id, other.peer_id) and distance < ENEMY_CLEARANCE:
				var exposed := ArenaCollisionSystem.has_clear_line_of_sight(other.position, candidate, world.map_id)
				score += (ENEMY_CLEARANCE - distance) * (4.0 if exposed else 1.0)
		if occupied or score >= best_score:
			continue
		for threat in world.spatial_index.respawn_threats_at(candidate, world.projectile_registry, world.server_tick):
			var owner_id := int(threat.owner_id)
			if owner_id == peer_id or world.are_allies(peer_id, owner_id):
				continue
			var clearance := float(threat.radius)
			var nearest := Geometry2D.get_closest_point_to_segment(candidate, threat.start as Vector2, threat.finish as Vector2)
			if nearest.distance_to(candidate) < clearance:
				score += 10000.0 + (clearance - nearest.distance_to(candidate)) * 10.0
				if score >= best_score:
					break
		if score < best_score:
			best_score = score
			best = candidate
	return best
