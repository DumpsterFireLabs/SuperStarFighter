class_name PlayerScoreState
extends RefCounted

var heat_wins: int = 0
var round_wins: int = 0
var kills: int = 0


func reset_heat_wins() -> void:
	heat_wins = 0


func reset_match() -> void:
	heat_wins = 0
	round_wins = 0
	kills = 0
