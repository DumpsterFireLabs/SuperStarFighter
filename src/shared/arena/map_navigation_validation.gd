class_name MapNavigationValidation
extends RefCounted

## Authoring-only visibility graph. Uses the supplied geometry, never registry
## or NPC caches. Every edge is swept at full ship radius; lethal horizons are
## supplied as additional circles. All authored cover stays solid (doors closed).
const ROUTE_RADIUS := GameConstants.SHIP_COLLISION_RADIUS
const EXIT_RADIUS := 48.0
const EXIT_LENGTH := 180.0
const EXIT_HEADINGS := 72
const CIRCLE_VERTICES := 32
const CORNER_MARGIN := 0.1
var _cover: Array[Rect2]
var _circles: Array[Vector3]
var _reachable := PackedVector2Array()


func _init(cover: Array[Rect2], circles: Array[Vector3], destination: Vector2) -> void:
	_cover = cover
	_circles = circles
	var candidates := PackedVector2Array()
	for rectangle in _cover:
		var expanded := rectangle.grow(ROUTE_RADIUS + CORNER_MARGIN)
		for corner: Vector2 in [expanded.position, Vector2(expanded.end.x, expanded.position.y), expanded.end, Vector2(expanded.position.x, expanded.end.y)]:
			if segment_clear(corner, corner):
				candidates.append(corner)
	for circle in _circles:
		# Circumscribe the inflated circle, so adjacent chords also stay clear.
		var radius := (circle.z + ROUTE_RADIUS + CORNER_MARGIN) / cos(PI / CIRCLE_VERTICES)
		for index in CIRCLE_VERTICES:
			var point := Vector2(circle.x, circle.y) + Vector2.from_angle(TAU * index / CIRCLE_VERTICES) * radius
			if segment_clear(point, point):
				candidates.append(point)
	if not segment_clear(destination, destination):
		return
	_reachable.append(destination)
	var visited := PackedByteArray()
	visited.resize(candidates.size())
	var cursor := 0
	while cursor < _reachable.size():
		var current := _reachable[cursor]
		cursor += 1
		for index in candidates.size():
			if visited[index] == 0 and segment_clear(current, candidates[index]):
				visited[index] = 1
				_reachable.append(candidates[index])


func reaches_destination(point: Vector2) -> bool:
	for destination in _reachable:
		if segment_clear(point, destination):
			return true
	return false


## Two headings at least 90 degrees apart avoid counting adjacent rays through
## the same narrow mouth twice. Endpoints must join the objective component.
func has_spawn_exits(anchor: Vector2) -> bool:
	var headings := PackedInt32Array()
	for index in EXIT_HEADINGS:
		var endpoint := anchor + Vector2.from_angle(TAU * index / EXIT_HEADINGS) * EXIT_LENGTH
		if not segment_clear(anchor, endpoint, EXIT_RADIUS) or not reaches_destination(endpoint):
			continue
		for previous in headings:
			var separation := mini(index - previous, EXIT_HEADINGS - (index - previous))
			if separation >= EXIT_HEADINGS / 4:
				return true
		headings.append(index)
	return false


## A full ship must fit in the final non-hill overtime disk and be reachable.
## The center itself may legitimately be occupied by a reactor or black hole.
func reaches_overtime(minimum_radius: float) -> bool:
	var center := GameConstants.ARENA_SIZE * 0.5
	var safe_radius := minimum_radius - ROUTE_RADIUS
	if safe_radius <= 0.0:
		return false
	if reaches_destination(center):
		return true
	for fraction: float in [0.25, 0.5, 0.75, 1.0]:
		for index in CIRCLE_VERTICES:
			var point := center + Vector2.from_angle(TAU * index / CIRCLE_VERTICES) * (safe_radius - CORNER_MARGIN) * fraction
			if reaches_destination(point):
				return true
	return false


func segment_clear(from: Vector2, to: Vector2, radius: float = ROUTE_RADIUS) -> bool:
	var bounds := Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE).grow(-radius)
	if not bounds.has_point(from) or not bounds.has_point(to):
		return false
	for rectangle in _cover:
		if _intersects_rectangle(from, to, rectangle.grow(radius)):
			return false
	var motion := to - from
	var length_squared := motion.length_squared()
	for circle in _circles:
		var center := Vector2(circle.x, circle.y)
		var fraction := clampf((center - from).dot(motion) / length_squared, 0.0, 1.0) if length_squared > 0.0 else 0.0
		if (from + motion * fraction).distance_squared_to(center) <= pow(circle.z + radius, 2):
			return false
	return true


static func _intersects_rectangle(from: Vector2, to: Vector2, rectangle: Rect2) -> bool:
	var motion := to - from
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if is_zero_approx(motion[axis]):
			if from[axis] < rectangle.position[axis] or from[axis] > rectangle.end[axis]:
				return false
			continue
		var first: float = (rectangle.position[axis] - from[axis]) / motion[axis]
		var last: float = (rectangle.end[axis] - from[axis]) / motion[axis]
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
		if enter > leave:
			return false
	return true
