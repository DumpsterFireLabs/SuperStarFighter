class_name NpcPilotController
extends RefCounted

enum Difficulty {
	PASSIVE,
	EASY,
	NEUTRAL,
	SKILLED,
	INSANE,
}

const DIFFICULTY_NAMES: Array[String] = ["Passive", "Easy", "Neutral", "Skilled", "Insane"]
const DIFFICULTY_PROFILES := {
	Difficulty.PASSIVE: {
		"reaction_ticks": 36, "aim_error_degrees": 24.0, "lead_seconds": 0.0,
		"awareness_range": 900.0, "pursuit": 0.18, "strafe": 0.18,
		"preferred_min": 460.0, "preferred_max": 820.0,
		"fire_range": 0.0, "fire_duty": 0.0, "shield_range": 0.0, "shield_duty": 0.0,
	},
	Difficulty.EASY: {
		"reaction_ticks": 20, "aim_error_degrees": 14.0, "lead_seconds": 0.0,
		"awareness_range": 1300.0, "pursuit": 0.42, "strafe": 0.32,
		"preferred_min": 300.0, "preferred_max": 620.0,
		"fire_range": 900.0, "fire_duty": 0.32, "shield_range": 480.0, "shield_duty": 0.05,
	},
	Difficulty.NEUTRAL: {
		"reaction_ticks": 10, "aim_error_degrees": 7.0, "lead_seconds": 0.08,
		"awareness_range": 1900.0, "pursuit": 0.65, "strafe": 0.5,
		"preferred_min": 250.0, "preferred_max": 540.0,
		"fire_range": 1450.0, "fire_duty": 0.58, "shield_range": 650.0, "shield_duty": 0.1,
	},
	Difficulty.SKILLED: {
		"reaction_ticks": 5, "aim_error_degrees": 2.5, "lead_seconds": 0.18,
		"awareness_range": 2600.0, "pursuit": 0.85, "strafe": 0.68,
		"preferred_min": 220.0, "preferred_max": 500.0,
		"fire_range": 2100.0, "fire_duty": 0.8, "shield_range": 820.0, "shield_duty": 0.16,
	},
	Difficulty.INSANE: {
		"reaction_ticks": 2, "aim_error_degrees": 0.4, "lead_seconds": 0.3,
		"awareness_range": 4000.0, "pursuit": 1.0, "strafe": 0.85,
		"preferred_min": 190.0, "preferred_max": 460.0,
		"fire_range": 3200.0, "fire_duty": 0.94, "shield_range": 1050.0, "shield_duty": 0.22,
	},
}

var _sequences: Dictionary = {}
var _next_decision_ticks: Dictionary = {}


func submit_inputs(world: AuthoritativeWorld, npc_peer_ids: Array[int], difficulties: Dictionary = {}) -> void:
	for peer_id in npc_peer_ids:
		var combatant := world.combatants.get(peer_id) as CombatantState
		if combatant == null or not combatant.alive:
			continue
		var difficulty := int(difficulties.get(peer_id, Difficulty.NEUTRAL))
		var profile := difficulty_profile(difficulty)
		if world.server_tick < int(_next_decision_ticks.get(peer_id, 0)):
			continue
		_next_decision_ticks[peer_id] = world.server_tick + int(profile.reaction_ticks)
		var target := _nearest_target(world, combatant, float(profile.awareness_range))
		if target == null:
			_submit_decision(world, peer_id, Vector2.ZERO, combatant.aim_angle, false, false)
			continue
		var offset := target.position - combatant.position
		var distance := offset.length()
		var predicted_offset := offset + target.velocity * float(profile.lead_seconds)
		var aim_angle := predicted_offset.angle() if not predicted_offset.is_zero_approx() else combatant.aim_angle
		var error_phase := float(world.server_tick) * 0.021 + float(peer_id % 997) * 0.73
		aim_angle += sin(error_phase) * deg_to_rad(float(profile.aim_error_degrees))
		var phase := float(world.server_tick + peer_id % 997) * 0.035
		var forward := -float(profile.pursuit) if distance > float(profile.preferred_max) else (float(profile.pursuit) * 0.75 if distance < float(profile.preferred_min) else 0.0)
		var strafe := sin(phase) * float(profile.strafe)
		var movement := Vector2(strafe, forward).limit_length(1.0)
		var shield_phase := float(posmod(world.server_tick + peer_id, 180)) / 180.0
		var shielding := distance < float(profile.shield_range) and shield_phase < float(profile.shield_duty)
		var fire_phase := float(posmod(world.server_tick + peer_id * 3, 120)) / 120.0
		var firing := not shielding and distance < float(profile.fire_range) and fire_phase < float(profile.fire_duty)
		_submit_decision(world, peer_id, movement, aim_angle, firing, shielding)


static func is_valid_difficulty(difficulty: int) -> bool:
	return difficulty >= Difficulty.PASSIVE and difficulty <= Difficulty.INSANE


static func difficulty_name(difficulty: int) -> String:
	return DIFFICULTY_NAMES[difficulty] if is_valid_difficulty(difficulty) else "Neutral"


static func difficulty_profile(difficulty: int) -> Dictionary:
	return DIFFICULTY_PROFILES.get(difficulty, DIFFICULTY_PROFILES[Difficulty.NEUTRAL]) as Dictionary


func remove_peer(peer_id: int) -> void:
	_sequences.erase(peer_id)
	_next_decision_ticks.erase(peer_id)


func clear() -> void:
	_sequences.clear()
	_next_decision_ticks.clear()


func _submit_decision(world: AuthoritativeWorld, peer_id: int, movement: Vector2, aim_angle: float, firing: bool, shielding: bool) -> void:
	var sequence := SequenceMath.increment(int(_sequences.get(peer_id, world.acknowledged_inputs.get(peer_id, 0))))
	_sequences[peer_id] = sequence
	world.submit_input(peer_id, PlayerInputFrame.new(sequence, world.server_tick, movement, aim_angle, firing, shielding))


func _nearest_target(world: AuthoritativeWorld, source: CombatantState, awareness_range: float) -> CombatantState:
	var nearest: CombatantState
	var nearest_distance_squared := awareness_range * awareness_range
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
