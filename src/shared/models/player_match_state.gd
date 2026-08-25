class_name PlayerMatchState
extends RefCounted

var peer_id: int
var display_name: String
var join_sequence: int
var connected: bool = true
var is_npc: bool = false
var participant: bool = true
var alive: bool = false
var spectator: bool = true
var lobby_ready: bool = false

var health: float = 0.0
var shield_energy: float = 0.0
var ammunition: int = 0
var card_stacks: Dictionary = {}
var score := PlayerScoreState.new()


func _init(peer_id_value: int = 0, display_name_value: String = "", join_sequence_value: int = 0) -> void:
	peer_id = peer_id_value
	display_name = display_name_value
	join_sequence = join_sequence_value


func card_stack(card_id: StringName) -> int:
	return int(card_stacks.get(card_id, 0))


func add_card(card: CardDefinition) -> bool:
	var current_stacks := card_stack(card.card_id)
	if current_stacks >= card.max_stacks:
		return false
	card_stacks[card.card_id] = current_stacks + 1
	return true


func reset_for_heat(stats: CombatStats) -> void:
	alive = connected and participant
	spectator = not alive
	health = stats.max_health if alive else 0.0
	shield_energy = stats.shield_capacity if alive else 0.0
	ammunition = stats.magazine_size if alive else 0


func eliminate() -> void:
	alive = false
	spectator = true
	health = 0.0


func reset_match() -> void:
	alive = false
	spectator = true
	card_stacks.clear()
	score.reset_match()
	health = 0.0
	shield_energy = 0.0
	ammunition = 0
