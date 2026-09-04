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
var special_sequence: int = 0
var special_slot: int = -1
var shield_press_sequence: int = -1


func _init(
	sequence_value: int = 0,
	client_tick_value: int = 0,
	movement_value: Vector2 = Vector2.ZERO,
	aim_angle_value: float = 0.0,
	firing_value: bool = false,
	shielding_value: bool = false,
	manual_reload_value: bool = false,
	special_activated_value: bool = false,
	special_sequence_value: int = -1,
	special_slot_value: int = -1,
	shield_press_sequence_value: int = -1
) -> void:
	sequence = sequence_value
	client_tick = client_tick_value
	movement = movement_value
	aim_angle = aim_angle_value
	firing = firing_value
	shielding = shielding_value
	manual_reload = manual_reload_value
	special_activated = special_activated_value
	special_sequence = special_sequence_value if special_sequence_value >= 0 else sequence_value
	special_slot = special_slot_value
	shield_press_sequence = shield_press_sequence_value


func is_valid() -> bool:
	return (
		sequence >= 0
		and client_tick >= 0
		and special_sequence >= 0 and special_sequence <= 0xffffffff
		and special_slot >= -1 and special_slot <= SpecialAbilitySelection.Slot.CLOAK
		and (shield_press_sequence == -1 or (shield_press_sequence >= 0 and shield_press_sequence <= 0xffffffff and ((sequence - shield_press_sequence) & 0xffffffff) <= GameConstants.SHIELD_PRESS_RETENTION_TICKS))
		and is_finite(movement.x)
		and is_finite(movement.y)
		and movement.length_squared() <= 1.0002
		and is_finite(aim_angle)
	)


func normalized_aim_angle() -> float:
	return fposmod(aim_angle, TAU)
