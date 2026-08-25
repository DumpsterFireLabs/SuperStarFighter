class_name NpcPilotController
extends RefCounted

var _sequences: Dictionary = {}


func submit_inputs(world: AuthoritativeWorld, npc_peer_ids: Array[int]) -> void:
	for peer_id in npc_peer_ids:
		var combatant := world.combatants.get(peer_id) as CombatantState
		if combatant == null or not combatant.alive:
			continue
		var target := _nearest_target(world, combatant)
		if target == null:
			continue
		var offset := target.position - combatant.position
		var distance := offset.length()
		var aim_angle := offset.angle() if not offset.is_zero_approx() else combatant.aim_angle
		var phase := float(world.server_tick + peer_id % 997) * 0.035
		var forward := -0.9 if distance > 360.0 else (0.45 if distance < 210.0 else 0.0)
		var strafe := sin(phase) * 0.72
		var movement := Vector2(strafe, forward).limit_length(1.0)
		var shielding := distance < 700.0 and posmod(world.server_tick + peer_id, 240) < 34
		var sequence := SequenceMath.increment(int(_sequences.get(peer_id, 0)))
		_sequences[peer_id] = sequence
		world.submit_input(peer_id, PlayerInputFrame.new(
			sequence,
			world.server_tick,
			movement,
			aim_angle,
			not shielding and distance < 2400.0,
			shielding
		))


func remove_peer(peer_id: int) -> void:
	_sequences.erase(peer_id)


func clear() -> void:
	_sequences.clear()


func _nearest_target(world: AuthoritativeWorld, source: CombatantState) -> CombatantState:
	var nearest: CombatantState
	var nearest_distance_squared := INF
	for peer_value in world.combatants.keys():
		var peer_id := int(peer_value)
		if peer_id == source.peer_id:
			continue
		var candidate := world.combatants[peer_id] as CombatantState
		if not candidate.alive:
			continue
		var distance_squared := source.position.distance_squared_to(candidate.position)
		if distance_squared < nearest_distance_squared:
			nearest = candidate
			nearest_distance_squared = distance_squared
	return nearest
