class_name NpcObjectiveNavigation
extends RefCounted

const CLEARANCE := GameConstants.SHIP_COLLISION_RADIUS + 18.0
const ROUTE_REFRESH_TICKS := 60
const MAX_PLANS_PER_TICK := 2
static var _graphs: Dictionary = {}
var _routes: Dictionary = {}
var _budget_tick := -1
var _plans_this_tick := 0


func clear() -> void:
	_routes.clear()
	_budget_tick = -1


func remove_peer(peer_id: int) -> void:
	_routes.erase(peer_id)


func steering(peer_id: int, from: Vector2, destination: Vector2, map_id: StringName, tick: int, hidden_cover: int = 0) -> Vector2:
	if from.distance_to(destination) <= GameConstants.SHIP_COLLISION_RADIUS * 1.25:
		_routes.erase(peer_id)
		return Vector2.ZERO
	if segment_clear(from, destination, map_id, CLEARANCE - 2.0, hidden_cover):
		_routes.erase(peer_id)
		return (destination - from).limit_length(220.0) / 220.0
	if tick != _budget_tick:
		_budget_tick = tick
		_plans_this_tick = 0
	var route := _routes.get(peer_id, {}) as Dictionary
	var stale: bool = route.is_empty() or route.get("mask", -1) != hidden_cover or route.get("map", &"") != map_id or tick >= int(route.get("refresh", 0)) or (route.get("destination", destination) as Vector2).distance_to(destination) > 320.0
	if stale and _plans_this_tick < MAX_PLANS_PER_TICK:
		_plans_this_tick += 1
		route = {"map": map_id, "mask": hidden_cover, "refresh": tick + ROUTE_REFRESH_TICKS + posmod(peer_id, 17), "destination": destination, "points": plan_route(from, destination, map_id, hidden_cover)}
		_routes[peer_id] = route
	if route.is_empty() or route.get("map", &"") != map_id:
		return Vector2.ZERO
	var points := route.points as PackedVector2Array
	while not points.is_empty() and from.distance_to(points[0]) < 38.0:
		points.remove_at(0)
	route.points = points
	if points.is_empty():
		return Vector2.ZERO
	# Rejoin after knockback only through a collision-clear segment. Waiting for
	# the next bounded plan is safer than steering through the intervening cover.
	if not segment_clear(from, points[0], map_id, GameConstants.SHIP_COLLISION_RADIUS + 2.0, hidden_cover):
		route.refresh = tick
		return Vector2.ZERO
	return (points[0] - from).limit_length(220.0) / 220.0


static func segment_clear(from: Vector2, to: Vector2, map_id: StringName, clearance: float = CLEARANCE - 2.0, hidden_cover: int = 0) -> bool:
	for rectangle in ArenaCollisionSystem.cover_rectangles(map_id, hidden_cover):
		if NpcPilotController._segment_intersects_rect(from, to, rectangle.grow(clearance)):
			return false
	for circle in ArenaLayout.circle_obstacles(map_id):
		if NpcPilotController._segment_intersects_circle(from, to, circle.center, float(circle.radius) + clearance):
			return false
	return true


static func _point_clear(point: Vector2, map_id: StringName, hidden_cover: int = 0) -> bool:
	if not ArenaLayout.arena_rect().grow(-CLEARANCE).has_point(point):
		return false
	for rectangle in ArenaCollisionSystem.cover_rectangles(map_id, hidden_cover):
		if rectangle.grow(CLEARANCE - 2.0).has_point(point):
			return false
	for circle in ArenaLayout.circle_obstacles(map_id):
		if point.distance_to(circle.center) <= float(circle.radius) + CLEARANCE - 2.0:
			return false
	return true


static func _graph(map_id: StringName, hidden_cover: int = 0) -> Dictionary:
	var key := "%s:%d" % [map_id, hidden_cover]
	if _graphs.has(key):
		return _graphs[key]
	var points := PackedVector2Array()
	for rectangle in ArenaCollisionSystem.cover_rectangles(map_id, hidden_cover):
		var expanded := rectangle.grow(CLEARANCE)
		for corner in [expanded.position, Vector2(expanded.end.x, expanded.position.y), expanded.end, Vector2(expanded.position.x, expanded.end.y)]:
			if _point_clear(corner, map_id, hidden_cover):
				points.append(corner)
	for circle in ArenaLayout.circle_obstacles(map_id):
		var radius := (float(circle.radius) + CLEARANCE) / cos(PI / 12.0)
		for index in 12:
			var point: Vector2 = circle.center + Vector2.from_angle(TAU * float(index) / 12.0) * radius
			if _point_clear(point, map_id, hidden_cover):
				points.append(point)
	var edges: Array[Dictionary] = []
	for index in points.size():
		edges.append({})
	for first in points.size():
		for second in range(first + 1, points.size()):
			if segment_clear(points[first], points[second], map_id, CLEARANCE - 2.0, hidden_cover):
				var distance := points[first].distance_to(points[second])
				edges[first][second] = distance
				edges[second][first] = distance
	var graph := {"points": points, "edges": edges}
	_graphs[key] = graph
	return graph


static func plan_route(from: Vector2, destination: Vector2, map_id: StringName, hidden_cover: int = 0) -> PackedVector2Array:
	if segment_clear(from, destination, map_id, CLEARANCE - 2.0, hidden_cover):
		return PackedVector2Array([destination])
	var graph := _graph(map_id, hidden_cover)
	var points := graph.points as PackedVector2Array
	var edges := graph.edges as Array[Dictionary]
	var count := points.size()
	var distances := PackedFloat64Array()
	var parents := PackedInt32Array()
	var visited := PackedByteArray()
	distances.resize(count)
	parents.resize(count)
	visited.resize(count)
	distances.fill(INF)
	parents.fill(-1)
	var start_clearance := CLEARANCE - 2.0 if _point_clear(from, map_id, hidden_cover) else GameConstants.SHIP_COLLISION_RADIUS + 2.0
	for index in count:
		if segment_clear(from, points[index], map_id, start_clearance, hidden_cover):
			distances[index] = from.distance_to(points[index])
	var best := -1
	var best_distance := INF
	for _iteration in count:
		var current := -1
		var shortest := INF
		for index in count:
			if visited[index] == 0 and distances[index] < shortest:
				current = index
				shortest = distances[index]
		if current < 0 or shortest >= best_distance:
			break
		visited[current] = 1
		if segment_clear(points[current], destination, map_id, CLEARANCE - 2.0, hidden_cover):
			var total := shortest + points[current].distance_to(destination)
			if total < best_distance:
				best = current
				best_distance = total
		for neighbor in edges[current]:
			var candidate: float = shortest + float(edges[current][neighbor])
			if candidate < distances[int(neighbor)]:
				distances[int(neighbor)] = candidate
				parents[int(neighbor)] = current
	if best < 0:
		return PackedVector2Array()
	var route := PackedVector2Array([destination])
	while best >= 0:
		route.insert(0, points[best])
		best = parents[best]
	return route
