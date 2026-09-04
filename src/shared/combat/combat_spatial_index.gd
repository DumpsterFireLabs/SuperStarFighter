class_name CombatSpatialIndex
extends RefCounted

const CELL_SIZE: float = 200.0
const GRID_WIDTH: int = ceili(GameConstants.ARENA_SIZE.x / CELL_SIZE) + 2
const GRID_HEIGHT: int = ceili(GameConstants.ARENA_SIZE.y / CELL_SIZE) + 2
const SHIP_SWEEP_PADDING: float = GameConstants.SHIP_COLLISION_RADIUS + maxf(7.0, GameConstants.MISSILE_RADIUS)
const RESPAWN_THREAT_LOOKAHEAD_SECONDS: float = 0.6
var projectile_revision: int = -1
var maximum_projectile_speed: float = 0.0
var _ship_cells: Dictionary = {}
var _ship_sweep_cells: Dictionary = {}
var _ship_sweep_grid: Array = []
var _projectile_threat_cells: Dictionary = {}
var _armed_mine_cells: Dictionary = {}
var _empty_ids: Array[int] = []
var _respawn_threat_cells: Dictionary = {}
var _respawn_threat_tick: int = -1
var _respawn_threat_revision: int = -1


func _init() -> void:
	_ship_sweep_grid.resize(GRID_WIDTH * GRID_HEIGHT)
	_ship_sweep_grid.fill(_empty_ids)


func respawn_threats_at(position: Vector2, registry: ProjectileRegistry, tick: int) -> Array:
	if _respawn_threat_tick != tick or _respawn_threat_revision != registry.revision:
		_respawn_threat_tick = tick
		_respawn_threat_revision = registry.revision
		_respawn_threat_cells.clear()
		for id in registry.ordered_ids_view():
			if id == ProjectileRegistry.REMOVED_ID:
				continue
			var projectile := registry.get_projectile(id)
			var finish := projectile.position if projectile.is_mine else projectile.position + projectile.velocity * minf(RESPAWN_THREAT_LOOKAHEAD_SECONDS, projectile.lifetime_remaining)
			var radius := GameConstants.MINE_BLAST_RADIUS + GameConstants.SHIP_COLLISION_RADIUS if projectile.is_mine else projectile.radius + GameConstants.SHIP_COLLISION_RADIUS + 35.0
			var threat := {"owner_id": projectile.owner_id, "start": projectile.position, "finish": finish, "radius": radius}
			var minimum := _cell_for(Vector2(minf(projectile.position.x, finish.x) - radius, minf(projectile.position.y, finish.y) - radius))
			var maximum := _cell_for(Vector2(maxf(projectile.position.x, finish.x) + radius, maxf(projectile.position.y, finish.y) + radius))
			for y in range(minimum.y, maximum.y + 1):
				for x in range(minimum.x, maximum.x + 1):
					var cell := Vector2i(x, y)
					if not _respawn_threat_cells.has(cell):
						_respawn_threat_cells[cell] = []
					(_respawn_threat_cells[cell] as Array).append(threat)
	return _respawn_threat_cells.get(_cell_for(position), []) as Array


func rebuild_ships(combatants: Dictionary, ordered_peer_ids: Array[int]) -> void:
	_ship_cells.clear()
	_ship_sweep_cells.clear()
	_ship_sweep_grid.fill(_empty_ids)
	for peer_id in ordered_peer_ids:
		var combatant := combatants.get(peer_id) as CombatantState
		if combatant == null or not combatant.alive:
			continue
		_append_cell_id(_ship_cells, _cell_for(combatant.position), peer_id)
		# Pre-expand once per ship instead of expanding every projectile query.
		# Typical short sweeps can then borrow one cell's immutable candidate list.
		var minimum := _cell_for(combatant.position - Vector2.ONE * SHIP_SWEEP_PADDING)
		var maximum := _cell_for(combatant.position + Vector2.ONE * SHIP_SWEEP_PADDING)
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				_append_cell_id(_ship_sweep_cells, Vector2i(x, y), peer_id)

	# Ship cells occupy a small fixed arena grid. Reuse the same candidate arrays
	# for short projectile sweeps without hashing/allocating Vector2i query keys.
	# The sparse map remains the exact fallback for long/out-of-arena queries.
	for cell in _ship_sweep_cells:
		var grid_x := int(cell.x) + 1
		var grid_y := int(cell.y) + 1
		if grid_x >= 0 and grid_x < GRID_WIDTH and grid_y >= 0 and grid_y < GRID_HEIGHT:
			_ship_sweep_grid[grid_y * GRID_WIDTH + grid_x] = _ship_sweep_cells[cell]


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
	if _ship_cells.is_empty():
		return _empty_ids
	if padding <= SHIP_SWEEP_PADDING:
		var start_x := floori(start.x / CELL_SIZE)
		var start_y := floori(start.y / CELL_SIZE)
		var finish_x := floori(finish.x / CELL_SIZE)
		var finish_y := floori(finish.y / CELL_SIZE)
		if start_x == finish_x and start_y == finish_y:
			var grid_x := start_x + 1
			var grid_y := start_y + 1
			if grid_x >= 0 and grid_x < GRID_WIDTH and grid_y >= 0 and grid_y < GRID_HEIGHT:
				return _ship_sweep_grid[grid_y * GRID_WIDTH + grid_x] as Array[int]
			return _ship_sweep_cells.get(Vector2i(start_x, start_y), _empty_ids) as Array[int]
		var start_cell := Vector2i(start_x, start_y)
		var end_cell := Vector2i(finish_x, finish_y)
		var result: Array[int] = []
		for y in range(mini(start_cell.y, end_cell.y), maxi(start_cell.y, end_cell.y) + 1):
			for x in range(mini(start_cell.x, end_cell.x), maxi(start_cell.x, end_cell.x) + 1):
				for peer_id in _ship_sweep_cells.get(Vector2i(x, y), _empty_ids) as Array[int]:
					if not peer_id in result:
						result.append(peer_id)
		result.sort()
		return result
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
	var minimum_cell := _cell_for(minimum)
	var maximum_cell := _cell_for(maximum)
	if minimum_cell == maximum_cell:
		return cells.get(minimum_cell, _empty_ids) as Array[int]
	var result: Array[int] = []
	for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
		for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
			var ids := cells.get(Vector2i(cell_x, cell_y), _empty_ids) as Array[int]
			for entity_id in ids:
				result.append(entity_id)
	result.sort()
	return result


func _append_cell_id(cells: Dictionary, cell: Vector2i, entity_id: int) -> void:
	if cells.has(cell):
		(cells[cell] as Array[int]).append(entity_id)
		return
	var ids: Array[int] = [entity_id]
	cells[cell] = ids


func _cell_for(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))
