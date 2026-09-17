extends RefCounted

## Optional cue policy and history. Only constructed for enabled matches.
var heat_damaged_peers: Dictionary = {}
var _silly_contact_ticks: Dictionary = {}
var _silly_recent_damage: Dictionary = {}
var _silly_perfect_blocks: Dictionary = {}
var _silly_uncloaked: Dictionary = {}
var _silly_danger_active: Dictionary = {}
var _silly_danger_ticks: Dictionary = {}
var _silly_feedback_ticks: Dictionary = {}
var _silly_landed_hits: Dictionary = {}


func reset() -> void:
	heat_damaged_peers.clear()
	_silly_contact_ticks.clear()
	_silly_recent_damage.clear()
	_silly_perfect_blocks.clear()
	_silly_uncloaked.clear()
	_silly_danger_active.clear()
	_silly_danger_ticks.clear()
	_silly_feedback_ticks.clear()
	_silly_landed_hits.clear()


func forget_peer(peer_id: int) -> void:
	_silly_uncloaked.erase(peer_id)
	_silly_danger_active.erase(peer_id)
	_silly_danger_ticks.erase(peer_id)
	_silly_landed_hits.erase(peer_id)


func record_silly_contact(world: AuthoritativeWorld, attacker: CombatantState, target: CombatantState, normal: Vector2) -> void:
	if world.are_allies(attacker.peer_id, target.peer_id) or attacker.velocity.dot(normal) <= 0.0 or (attacker.velocity - target.velocity).dot(normal) < 180.0:
		return
	var cue := ""
	if attacker.shield.active and attacker.stats.shield_ram_damage > 0.0:
		cue = "bonk"
	elif Vector2.from_angle(target.aim_angle).dot(normal) > 0.5:
		cue = "uwu"
	if cue.is_empty():
		return
	var key := "%d:%d" % [attacker.peer_id, target.peer_id]
	if world.server_tick - int(_silly_contact_ticks.get(key, -100000)) < GameConstants.PHYSICS_TICKS_PER_SECOND * 2:
		return
	_silly_contact_ticks[key] = world.server_tick
	world._combat_feedback.record_silly_cue(attacker.peer_id, cue)
	world._combat_feedback.record_silly_cue(target.peer_id, cue)


# Life generations prevent a block or hit from qualifying after either ship respawns.
func _remember_silly_contact(world: AuthoritativeWorld, history: Dictionary, defender_id: int, attacker_id: int) -> void:
	var defender := world.combatants.get(defender_id) as CombatantState
	var attacker := world.combatants.get(attacker_id) as CombatantState
	if defender == null or attacker == null:
		return
	history["%d:%d" % [defender_id, attacker_id]] = {
		"tick": world.server_tick, "defender_life": defender.life_generation,
		"attacker_life": attacker.life_generation,
	}
	while history.size() > GameConstants.DEFAULT_MAX_PLAYERS * GameConstants.DEFAULT_MAX_PLAYERS:
		history.erase(history.keys()[0])


func _recent_silly_contact(world: AuthoritativeWorld, history: Dictionary, defender: CombatantState, attacker: CombatantState, seconds: int) -> bool:
	var entry: Dictionary = history.get("%d:%d" % [defender.peer_id, attacker.peer_id], {})
	return not entry.is_empty() and int(entry.defender_life) == defender.life_generation and int(entry.attacker_life) == attacker.life_generation and world.server_tick - int(entry.tick) <= seconds * GameConstants.PHYSICS_TICKS_PER_SECOND


func _silly_feedback_ready(world: AuthoritativeWorld, peer_id: int, cue: String, seconds: int = 20) -> bool:
	return world.server_tick - int(_silly_feedback_ticks.get("%d:%s" % [peer_id, cue], -100000)) >= seconds * GameConstants.PHYSICS_TICKS_PER_SECOND


func _mark_silly_feedback(world: AuthoritativeWorld, peer_id: int, cue: String) -> void:
	_silly_feedback_ticks["%d:%s" % [peer_id, cue]] = world.server_tick
	while _silly_feedback_ticks.size() > GameConstants.DEFAULT_MAX_PLAYERS * 16:
		_silly_feedback_ticks.erase(_silly_feedback_ticks.keys()[0])


func _emit_silly_feedback(world: AuthoritativeWorld, peer_id: int, cue: String) -> void:
	if not _silly_feedback_ready(world, peer_id, cue):
		return
	_mark_silly_feedback(world, peer_id, cue)
	world._combat_feedback.record_silly_cue(peer_id, cue)


func observe_silly_wall_collision(world: AuthoritativeWorld, pilot: CombatantState, resolved_velocity: Vector2) -> void:
	if pilot.afterburner_remaining > 0.0 and pilot.velocity.length() >= 600.0 and (pilot.velocity - resolved_velocity).length() >= 300.0:
		_emit_silly_feedback(world, pilot.peer_id, "record_scratch")


func observe_silly_pickup(world: AuthoritativeWorld, peer_id: int, pickup_position: Vector2) -> void:
	if not _silly_feedback_ready(world, peer_id, "yoink"):
		return
	for other_id in world._ordered_peer_ids():
		var other := world.combatants[other_id] as CombatantState
		var offset := pickup_position - other.position
		if other_id == peer_id or world.are_allies(peer_id, other_id) or not other.alive or other.is_cloaked():
			continue
		if offset.length_squared() > 120.0 * 120.0 or other.velocity.dot(offset) <= 0.0:
			continue
		if ArenaCollisionSystem.has_clear_line_of_sight(other.position, pickup_position, world.map_id):
			_emit_silly_feedback(world, peer_id, "yoink")
			return


func observe_silly_pursuit(world: AuthoritativeWorld, peer_ids: Array[int]) -> void:
	for chaser_id in peer_ids:
		var chaser := world.combatants[chaser_id] as CombatantState
		if not chaser.alive or not _silly_feedback_ready(world, chaser_id, "why_are_you_running"):
			continue
		for runner_id in peer_ids:
			var runner := world.combatants[runner_id] as CombatantState
			if runner_id == chaser_id or world.are_allies(chaser_id, runner_id) or not runner.alive or runner.is_cloaked() or runner.afterburner_remaining <= 0.0:
				continue
			var offset := runner.position - chaser.position
			if offset.length_squared() < 100.0 * 100.0 or offset.length_squared() > 900.0 * 900.0:
				continue
			var direction := offset.normalized()
			if runner.velocity.dot(direction) < 120.0 or chaser.velocity.dot(direction) < 60.0 or (runner.velocity - chaser.velocity).dot(direction) <= 0.0:
				continue
			if not _recent_silly_contact(world, _silly_recent_damage, runner, chaser, 5):
				continue
			if ArenaCollisionSystem.has_clear_line_of_sight(chaser.position, runner.position, world.map_id):
				_emit_silly_feedback(world, chaser_id, "why_are_you_running")
				break


func observe_silly_danger(world: AuthoritativeWorld, peer_ids: Array[int]) -> void:
	for peer_id in peer_ids:
		var pilot := world.combatants[peer_id] as CombatantState
		var enemies := 0
		if pilot.alive and pilot.health > 0.0 and pilot.health < pilot.stats.max_health * 0.15:
			for other_id in peer_ids:
				if other_id == peer_id or world.are_allies(peer_id, other_id):
					continue
				var other := world.combatants[other_id] as CombatantState
				if not other.alive or other.is_cloaked() or pilot.position.distance_squared_to(other.position) > 600.0 * 600.0:
					continue
				if not ArenaCollisionSystem.has_clear_line_of_sight(pilot.position, other.position, world.map_id):
					continue
				enemies += 1
				if enemies >= 3:
					break
		var in_danger := enemies >= 3
		var prior_life := int(_silly_danger_active.get(peer_id, -1))
		if in_danger:
			if prior_life != pilot.life_generation and world.server_tick - int(_silly_danger_ticks.get(peer_id, -100000)) >= 30 * GameConstants.PHYSICS_TICKS_PER_SECOND:
				world._combat_feedback.record_silly_cue(peer_id, "im_in_danger")
				_silly_danger_ticks[peer_id] = world.server_tick
			_silly_danger_active[peer_id] = pilot.life_generation
		else:
			_silly_danger_active.erase(peer_id)


func silly_kill_cue(world: AuthoritativeWorld, killer_id: int, victim_id: int, impact: Dictionary) -> String:
	var killer := world.combatants.get(killer_id) as CombatantState
	var victim := world.combatants.get(victim_id) as CombatantState
	if killer == null or victim == null or killer_id == victim_id:
		return ""
	if String(impact.get("mechanic", "")) == "reflected" and int(impact.get("original_shooter_id", 0)) == victim_id:
		return "jokes_on_you"
	if not killer.alive:
		return ""
	if int(impact.get("ricochet_count", 0)) > 0 and killer.health > 0.0 and killer.health < killer.stats.max_health * 0.1:
		return "calculated"
	var uncloaked: Dictionary = _silly_uncloaked.get(killer_id, {})
	if not killer.is_cloaked() and not uncloaked.is_empty() and int(uncloaked.life) == killer.life_generation and world.server_tick - int(uncloaked.tick) <= GameConstants.PHYSICS_TICKS_PER_SECOND:
		return "surprise"
	if _recent_silly_contact(world, _silly_perfect_blocks, killer, victim, 2):
		return "nope"
	if killer.health > 0.0 and killer.health < killer.stats.max_health * 0.1 and _recent_silly_contact(world, _silly_recent_damage, killer, victim, 5):
		return "call_an_ambulance"
	if String(impact.get("source", "")) == "missile" and _silly_feedback_ready(world, killer_id, "technologia"):
		_mark_silly_feedback(world, killer_id, "technologia")
		return "technologia"
	return ""


func observe_hits(world: AuthoritativeWorld, impacts: Array[Dictionary]) -> void:
	# Record all hits before evaluating deaths, including simultaneous trades.
	for impact in impacts:
		var attacker_id := int(impact.attacker_id)
		if float(impact.damage) > 0.0 and attacker_id != int(impact.target_id) and world.combatants.has(attacker_id) and not world.are_allies(attacker_id, int(impact.target_id)):
			_silly_landed_hits[attacker_id] = (world.combatants[attacker_id] as CombatantState).life_generation


func observe_impact(world: AuthoritativeWorld, impact: Dictionary) -> void:
	if float(impact.damage) > 0.0:
		heat_damaged_peers[int(impact.target_id)] = true
	var target_id := int(impact.target_id)
	var killer_id := int(impact.attacker_id)
	if float(impact.damage) > 0.0 and killer_id != target_id and world.combatants.has(killer_id):
		_remember_silly_contact(world, _silly_recent_damage, target_id, killer_id)
	if String(impact.source) == "mine" and float(impact.damage) > 0.0 and float(impact.health_before) < (world.combatants[target_id] as CombatantState).stats.max_health * 0.15:
		_emit_silly_feedback(world, target_id, "it_was_at_this_moment")
	if bool(impact.lethal) and int(_silly_landed_hits.get(target_id, -1)) != int(impact.life_generation):
		_emit_silly_feedback(world, target_id, "sad_trombone")


func record_uncloaked(peer_id: int, tick: int, life: int) -> void:
	_silly_uncloaked[peer_id] = {"tick": tick, "life": life}


func record_perfect_block(world: AuthoritativeWorld, defender_id: int, attacker_id: int) -> void:
	_remember_silly_contact(world, _silly_perfect_blocks, defender_id, attacker_id)
