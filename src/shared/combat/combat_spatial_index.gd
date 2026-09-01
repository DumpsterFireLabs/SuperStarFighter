class_name CombatSpatialIndex
extends RefCounted

const CELL_SIZE: float = 200.0
var projectile_revision: int = -1
var maximum_projectile_speed: float = 0.0
var _ship_cells: Dictionary = {}
var _projectile_threat_cells: Dictionary = {}
var _armed_mine_cells: Dictionary = {}
var _empty_ids: Array[int] = []


func rebuild_ships(combatants: Dictionary, ordered_peer_ids: Array[int]) -> void:
	_ship_cells.clear()
	for peer_id in ordered_peer_ids:
		var combatant := combatants.get(peer_id) as CombatantState
		if combatant == null or not combatant.alive:
			continue
		_append_cell_id(_ship_cells, _cell_for(combatant.position), peer_id)


func rebuild_projectile_threats(registry: ProjectileRegistry) -> void:
	_projectile_threat_cells.clear()
	var maximum_speed_squared := 0.0
	for projectile_id in registry.ordered_ids_view():
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := registry.get_projectile(projectile_id)
		if projectile == null:
			continue
		maximum_speed_squared = maxf(maximum_speed_squared, projectile.velocity.length_squared())
		_append_cell_id(_projectile_threat_cells, _cell_for(projectile.position), projectile_id)
	maximum_projectile_speed = sqrt(maximum_speed_squared)
	projectile_revision = registry.revision


func invalidate_projectile_threats() -> void:
	projectile_revision = -1


func rebuild_armed_mines(registry: ProjectileRegistry, armed_mine_ids: Array[int]) -> void:
	_armed_mine_cells.clear()
	for mine_id in armed_mine_ids:
		var mine := registry.get_projectile(mine_id)
		if mine != null:
			_append_cell_id(_armed_mine_cells, _cell_for(mine.position), mine_id)


func query_mines_along_segment(start: Vector2, finish: Vector2, padding: float) -> Array[int]:
	var minimum := Vector2(minf(start.x, finish.x) - padding, minf(start.y, finish.y) - padding)
	var maximum := Vector2(maxf(start.x, finish.x) + padding, maxf(start.y, finish.y) + padding)
	return _query_cells(_armed_mine_cells, minimum, maximum)


func query_nearby_mines(position: Vector2, radius: float) -> Array[int]:
	var extent := Vector2.ONE * maxf(radius, 0.0)
	return _query_cells(_armed_mine_cells, position - extent, position + extent)


func query_ships_along_segment(start: Vector2, finish: Vector2, padding: float) -> Array[int]:
	var minimum := Vector2(minf(start.x, finish.x) - padding, minf(start.y, finish.y) - padding)
	var maximum := Vector2(maxf(start.x, finish.x) + padding, maxf(start.y, finish.y) + padding)
	return _query_cells(_ship_cells, minimum, maximum)


func query_nearby_ships(position: Vector2, radius: float) -> Array[int]:
	var extent := Vector2.ONE * maxf(radius, 0.0)
	return _query_cells(_ship_cells, position - extent, position + extent)


func query_projectile_threats(position: Vector2, radius: float, maximum_count: int) -> Array[int]:
	var result: Array[int] = []
	if maximum_count <= 0:
		return result
	var center_cell := _cell_for(position)
	var maximum_ring := ceili(maxf(radius, 0.0) / CELL_SIZE)
	for ring in maximum_ring + 1:
		var ring_ids: Array[int] = []
		for cell_y in range(center_cell.y - ring, center_cell.y + ring + 1):
			for cell_x in range(center_cell.x - ring, center_cell.x + ring + 1):
				if ring > 0 and maxi(absi(cell_x - center_cell.x), absi(cell_y - center_cell.y)) != ring:
					continue
				for projectile_id in _projectile_threat_cells.get(Vector2i(cell_x, cell_y), _empty_ids) as Array[int]:
					ring_ids.append(projectile_id)
		ring_ids.sort()
		for projectile_id in ring_ids:
			result.append(projectile_id)
			if result.size() >= maximum_count:
				return result
	return result


func _query_cells(cells: Dictionary, minimum: Vector2, maximum: Vector2) -> Array[int]:
	var result: Array[int] = []
	var minimum_cell := _cell_for(minimum)
	var maximum_cell := _cell_for(maximum)
	if minimum_cell == maximum_cell:
		return cells.get(minimum_cell, _empty_ids) as Array[int]
	for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
		for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
			var ids := cells.get(Vector2i(cell_x, cell_y), _empty_ids) as Array[int]
			for entity_id in ids:
				result.append(entity_id)
	result.sort()
	return result


func _append_cell_id(cells: Dictionary, cell: Vector2i, entity_id: int) -> void:
	var ids: Array[int] = []
	if cells.has(cell):
		ids = cells[cell] as Array[int]
	else:
		cells[cell] = ids
	ids.append(entity_id)


func _cell_for(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))
