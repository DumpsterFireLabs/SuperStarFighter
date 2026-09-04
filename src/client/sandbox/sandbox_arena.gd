class_name SandboxArena
extends Node2D

var overtime_visible: bool = false
var overtime_radius: float = OvertimeSystem.initial_radius()
var overtime_center: Vector2 = ArenaLayout.center()
var show_spawn_anchors: bool = false:
	set(value):
		show_spawn_anchors = value
		if static_layer != null:
			static_layer.show_spawn_anchors = value
			static_layer.queue_redraw()
var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var obstacle_root: Node2D
var objective_state: Dictionary = {}
var local_peer_id: int = 0
var local_team_id: int = 0
var pilot_names: Dictionary = {}
var static_layer: ArenaStaticLayer


func _ready() -> void:
	static_layer = ArenaStaticLayer.new()
	static_layer.name = "StaticMap"
	static_layer.show_behind_parent = true
	static_layer.map_id = map_id
	static_layer.show_spawn_anchors = show_spawn_anchors
	add_child(static_layer)
	_create_outer_walls()
	_rebuild_map_collision()
	queue_redraw()


func set_map_id(value: StringName) -> void:
	var normalized := ArenaLayout.normalized_map_id(value)
	if normalized == map_id and obstacle_root != null:
		return
	map_id = normalized
	if static_layer != null:
		static_layer.map_id = map_id
		static_layer.queue_redraw()
	if is_inside_tree():
		_rebuild_map_collision()
	queue_redraw()


func set_overtime(
	active: bool,
	radius: float,
	center: Vector2 = ArenaLayout.center()
) -> void:
	overtime_visible = active
	overtime_radius = radius
	overtime_center = center
	queue_redraw()


func set_objective(state: Dictionary) -> void:
	objective_state = state.duplicate(true)
	queue_redraw()


func _draw() -> void:
	_draw_objective()
	if overtime_visible:
		var pulse := 0.72 + sin(Time.get_ticks_msec() * 0.008) * 0.2
		draw_circle(overtime_center, overtime_radius, Color(1.0, 0.2, 0.42, 0.1))
		draw_arc(overtime_center, overtime_radius, 0.0, TAU, 160, Color("ff315f", pulse * 0.2), 22.0)
		draw_arc(overtime_center, overtime_radius, 0.0, TAU, 160, Color("ff315f", pulse), 8.0)
		queue_redraw()
	elif not objective_state.is_empty() and bool(objective_state.get("active", false)):
		queue_redraw()


func _draw_objective() -> void:
	if objective_state.is_empty() or not bool(objective_state.get("active", false)):
		return
	var mode := int(objective_state.get("mode", GameModeRules.Mode.DEATH_MATCH))
	var pulse := 0.78 + sin(Time.get_ticks_msec() * 0.006) * 0.18
	var radius := float(objective_state.get("zone_radius", GameModeRules.OBJECTIVE_ZONE_RADIUS))
	if mode == GameModeRules.Mode.KING_OF_THE_HILL:
		var position := objective_state.get("position", ArenaLayout.center(map_id)) as Vector2
		var status := hill_status()
		var color := status.color as Color
		draw_circle(position, radius, Color(color, 0.10))
		for segment in 12:
			var angle := TAU * segment / 12.0
			draw_arc(position, radius, angle, angle + TAU / 16.0, 8, Color(color, pulse), 5.0)
		if float(status.progress) > 0.0:
			draw_arc(position, radius + 12.0, -PI / 2.0, -PI / 2.0 + TAU * float(status.progress), 64, color, 7.0)
		draw_string(ThemeDB.fallback_font, position + Vector2(-140.0, -radius - 34.0), status.label, HORIZONTAL_ALIGNMENT_CENTER, 280.0, 22, color)
	elif GameModeRules.uses_flag(mode):
		var zones := objective_state.get("capture_zones", {}) as Dictionary
		var zone_ids := zones.keys()
		zone_ids.sort()
		for zone_value in zone_ids:
			var zone_id := int(zone_value)
			var position := zones.get(zone_value, Vector2.ZERO) as Vector2
			if position.is_zero_approx():
				continue
			var color := GameModeRules.team_color(zone_id) if GameModeRules.is_team_mode(mode) else Color("fff36a")
			draw_circle(position, radius, Color(color, 0.09))
			draw_arc(position, radius, 0.0, TAU, 96, Color(color, pulse), 7.0)
			var zone_label := base_label(zone_id)
			draw_rect(Rect2(position - Vector2(25, 25), Vector2(50, 50)), color, false, 4.0)
			draw_string(ThemeDB.fallback_font, position + Vector2(-150.0, -radius - 20.0), zone_label, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 22, color)
		var flag_position := objective_state.get("flag_position", objective_state.get("position", ArenaLayout.center(map_id))) as Vector2
		var flag_points := PackedVector2Array([
			flag_position + Vector2(0.0, -25.0),
			flag_position + Vector2(20.0, 0.0),
			flag_position + Vector2(0.0, 25.0),
			flag_position + Vector2(-20.0, 0.0),
		])
		draw_colored_polygon(flag_points, Color(Color("fff36a"), pulse))
		draw_polyline(PackedVector2Array([flag_points[0], flag_points[1], flag_points[2], flag_points[3], flag_points[0]]), Color.WHITE, 3.0)


func hill_status() -> Dictionary:
	var controller := int(objective_state.get("controller_id", 0))
	var progress := objective_state.get("progress", {}) as Dictionary
	var held := float(progress.get(controller, progress.get(str(controller), 0.0)))
	var target := maxf(float(objective_state.get("target_seconds", GameModeRules.HILL_HOLD_SECONDS)), 0.001)
	var label := "HILL · NEUTRAL"
	var color := Color("fff36a")
	if bool(objective_state.get("contested", false)):
		label = "HILL · CONTESTED"
		color = Color("ffb454")
	elif controller > 0:
		label = "HILL · YOU" if controller == local_peer_id else "HILL · %s" % pilot_label(controller)
		color = Color("62ff9b") if controller == local_peer_id else Color("ff547c")
		label += " · %.1f / %.0fs" % [held, target]
	return {"label": label, "color": color, "progress": clampf(held / target, 0.0, 1.0)}


func base_label(zone_id: int) -> String:
	var team_mode := GameModeRules.is_team_mode(int(objective_state.get("mode", 0)))
	if zone_id == (local_team_id if team_mode else local_peer_id) and local_peer_id > 0:
		return "YOUR TEAM BASE" if team_mode else "YOUR BASE"
	return "TEAM %d BASE" % zone_id if team_mode else "%s BASE" % pilot_label(zone_id)


func pilot_label(peer_id: int) -> String:
	var label := String(pilot_names.get(peer_id, "PILOT %d" % peer_id)).to_upper()
	return label if label.length() <= 14 else label.left(13) + "…"


func navigation_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if not bool(objective_state.get("active", false)):
		return targets
	var mode := int(objective_state.get("mode", 0))
	if GameModeRules.uses_hill(mode):
		var status := hill_status()
		targets.append({"position": objective_state.get("position", ArenaLayout.center(map_id)), "label": "HILL", "color": status.color, "kind": "hill"})
	elif GameModeRules.uses_flag(mode):
		var carrier := int(objective_state.get("flag_carrier_id", 0))
		if carrier != local_peer_id or local_peer_id == 0:
			targets.append({"position": objective_state.get("flag_position", objective_state.get("position", ArenaLayout.center(map_id))), "label": "FLAG" if carrier == 0 else "FLAG · %s" % pilot_label(carrier), "color": Color("fff36a"), "kind": "flag"})
		var zones := objective_state.get("capture_zones", {}) as Dictionary
		var zone_id := local_team_id if GameModeRules.is_team_mode(mode) else local_peer_id
		var position := zones.get(zone_id, zones.get(str(zone_id), Vector2.INF)) as Vector2
		if zone_id > 0 and position.is_finite():
			targets.append({"position": position, "label": "RETURN FLAG" if carrier == local_peer_id else base_label(zone_id), "color": Color("42e8ff"), "kind": "base"})
	return targets


func _create_outer_walls() -> void:
	var thickness := 60.0
	_create_rectangle_body(Vector2(GameConstants.ARENA_SIZE.x * 0.5, -thickness * 0.5), Vector2(GameConstants.ARENA_SIZE.x + thickness * 2.0, thickness))
	_create_rectangle_body(Vector2(GameConstants.ARENA_SIZE.x * 0.5, GameConstants.ARENA_SIZE.y + thickness * 0.5), Vector2(GameConstants.ARENA_SIZE.x + thickness * 2.0, thickness))
	_create_rectangle_body(Vector2(-thickness * 0.5, GameConstants.ARENA_SIZE.y * 0.5), Vector2(thickness, GameConstants.ARENA_SIZE.y))
	_create_rectangle_body(Vector2(GameConstants.ARENA_SIZE.x + thickness * 0.5, GameConstants.ARENA_SIZE.y * 0.5), Vector2(thickness, GameConstants.ARENA_SIZE.y))


func _rebuild_map_collision() -> void:
	if obstacle_root != null:
		remove_child(obstacle_root)
		obstacle_root.free()
	obstacle_root = Node2D.new()
	obstacle_root.name = "MapObstacles"
	add_child(obstacle_root)
	var index := 0
	for rectangle in ArenaLayout.cover_rectangles(map_id):
		_create_rectangle_body(rectangle.get_center(), rectangle.size, "Cover%d" % index, obstacle_root)
		index += 1
	index = 0
	for circle in ArenaLayout.circle_obstacles(map_id):
		_create_circle_body(circle.center, float(circle.radius), "Circle%d" % index)
		index += 1


func _create_rectangle_body(body_position: Vector2, size: Vector2, body_name: String = "Boundary", parent: Node = null) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = body_position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	(parent if parent != null else self).add_child(body)


func _create_circle_body(body_position: Vector2, radius: float, body_name: String) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = body_position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	body.add_child(collision)
	obstacle_root.add_child(body)
