class_name ProjectileCorrectionAssembler
extends RefCounted

var _sequence: int = -1
var _tick: int = -1
var _chunk_count: int = 0
var _chunks: Dictionary = {}


func clear() -> void:
	_sequence = -1
	_tick = -1
	_chunk_count = 0
	_chunks.clear()


func accept(decoded: Dictionary) -> Dictionary:
	if not bool(decoded.get("complete_snapshot", false)):
		return decoded
	var sequence := int(decoded.batch_sequence)
	var tick := int(decoded.server_tick)
	var chunk_count := int(decoded.chunk_count)
	if sequence != _sequence or tick != _tick:
		# Old retransmissions must not evict the current in-progress recovery.
		if _tick >= 0 and (not SequenceMath.is_newer_or_equal(tick, _tick) or (tick == _tick and ((sequence - _sequence) & 0xffff) >= 0x8000)):
			return {}
		_sequence = sequence
		_tick = tick
		_chunk_count = chunk_count
		_chunks.clear()
	if chunk_count != _chunk_count:
		return {}
	_chunks[int(decoded.chunk_index)] = decoded.spawned
	if _chunks.size() != chunk_count:
		# Publish useful records immediately. Absence becomes authoritative only
		# after every chunk has arrived; otherwise a lost chunk deletes live shots.
		var partial := decoded.duplicate()
		partial.complete_snapshot = false
		return partial
	var active: Array[ProjectileState] = []
	for chunk_index in chunk_count:
		if not _chunks.has(chunk_index):
			return {}
		for projectile in _chunks[chunk_index] as Array:
			active.append(projectile as ProjectileState)
	var assembled := decoded.duplicate()
	assembled.spawned = active
	assembled.chunk_index = 0
	assembled.chunk_count = 1
	clear()
	return assembled
