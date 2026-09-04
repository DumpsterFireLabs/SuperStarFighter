class_name CombatFeedbackBuffer
extends RefCounted

# One fixed-shape accumulator per connected participant. A shotgun or a long
# server stall cannot create an unbounded reliable-event queue. Death recaps are
# separate from hit totals so subsequent impacts cannot displace a recap.
const MAX_RECIPIENTS: int = GameConstants.DEFAULT_MAX_PLAYERS
const MAX_COUNT: int = 65535
const MAX_DAMAGE: float = 1000000.0

var _pending: Dictionary = {}


func clear() -> void:
	_pending.clear()


func forget_peer(peer_id: int) -> void:
	_pending.erase(peer_id)


func record_hit(peer_id: int, damage: float, source: String) -> void:
	var feedback := _for_peer(peer_id)
	if feedback.is_empty():
		return
	feedback.hit_count = mini(int(feedback.hit_count) + 1, MAX_COUNT)
	feedback.hit_damage = minf(float(feedback.hit_damage) + maxf(damage, 0.0), MAX_DAMAGE)
	feedback.last_hit_source = source


func record_block(attacker_id: int, defender_id: int, reason: String) -> void:
	var outgoing := _for_peer(attacker_id)
	if not outgoing.is_empty():
		outgoing.blocked_count = mini(int(outgoing.blocked_count) + 1, MAX_COUNT)
		outgoing.last_block_reason = reason
	var incoming := _for_peer(defender_id)
	if not incoming.is_empty():
		incoming.guard_count = mini(int(incoming.guard_count) + 1, MAX_COUNT)
		incoming.last_guard_reason = reason


func record_death(peer_id: int, recap: Dictionary) -> void:
	var feedback := _for_peer(peer_id)
	if not feedback.is_empty():
		feedback.death = recap.duplicate(true)


func drain() -> Dictionary:
	var result := _pending
	_pending = {}
	return result


func _for_peer(peer_id: int) -> Dictionary:
	if peer_id == 0:
		return {}
	if not _pending.has(peer_id):
		if _pending.size() >= MAX_RECIPIENTS:
			return {}
		_pending[peer_id] = {
			"hit_count": 0, "hit_damage": 0.0, "blocked_count": 0,
			"guard_count": 0, "last_hit_source": "", "last_block_reason": "",
			"last_guard_reason": "",
		}
	return _pending[peer_id] as Dictionary
