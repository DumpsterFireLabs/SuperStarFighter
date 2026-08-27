class_name PlayerInputFrame
extends RefCounted

var sequence: int = 0
var client_tick: int = 0
var movement: Vector2 = Vector2.ZERO
var aim_angle: float = 0.0
var firing: bool = false
var shielding: bool = false
var manual_reload: bool = false
var special_activated: bool = false


func _init(
	sequence_value: int = 0,
	client_tick_value: int = 0,
	movement_value: Vector2 = Vector2.ZERO,
	aim_angle_value: float = 0.0,
	firing_value: bool = false,
	shielding_value: bool = false,
	manual_reload_value: bool = false,
	special_activated_value: bool = false
) -> void:
	sequence = sequence_value
	client_tick = client_tick_value
	movement = movement_value
	aim_angle = aim_angle_value
	firing = firing_value
	shielding = shielding_value
	manual_reload = manual_reload_value
	special_activated = special_activated_value


func is_valid() -> bool:
	return (
		sequence >= 0
		and client_tick >= 0
		and is_finite(movement.x)
		and is_finite(movement.y)
		and movement.length_squared() <= 1.0002
		and is_finite(aim_angle)
	)


func normalized_aim_angle() -> float:
	return fposmod(aim_angle, TAU)
