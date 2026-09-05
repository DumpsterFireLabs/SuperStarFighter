class_name SpecialAbilitySelection
extends RefCounted

enum Slot { AFTERBURNER, MINE, MISSILE, CLOAK }


static func owned_slots(stats: CombatStats) -> Array[int]:
	var slots: Array[int] = []
	if stats.afterburner_enabled:
		slots.append(Slot.AFTERBURNER)
	if stats.mine_layer_enabled:
		slots.append(Slot.MINE)
	if stats.missile_launcher_enabled:
		slots.append(Slot.MISSILE)
	if stats.cloak_enabled:
		slots.append(Slot.CLOAK)
	return slots


static func ensure_owned(slot: int, stats: CombatStats) -> int:
	var slots := owned_slots(stats)
	return slot if slot in slots else (slots[0] if not slots.is_empty() else -1)


static func cycle(slot: int, stats: CombatStats, direction: int) -> int:
	var slots := owned_slots(stats)
	if slots.is_empty():
		return -1
	var current := slots.find(slot)
	return slots[posmod(current + direction, slots.size())] if current >= 0 else slots[0]


static func label(slot: int) -> String:
	return ["AFTERBURNER", "MINES", "MISSILES", "CLOAK"][slot] if slot >= 0 and slot <= Slot.CLOAK else "NONE"


## Capture individual presses, including taps between simulation ticks.
static func direction_for_event(event: InputEvent) -> int:
	if event.is_action_pressed(&"special_previous"):
		return -1
	if event.is_action_pressed(&"special_next"):
		return 1
	return 0
