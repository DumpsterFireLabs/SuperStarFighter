class_name ProjectileLayer
extends Node2D

const DEFAULT_BEAM_COLOR: Color = Color("42e8ff")
const REBOUNDED_BEAM_COLOR: Color = Color("ff4fd8")
const SIMPLIFY_PROJECTILE_THRESHOLD: int = 160

var registry: ProjectileRegistry
var visible_world_rect: Rect2 = Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)
var projectile_colors_by_owner: Dictionary = {}
var high_tier_beam_colors_by_owner: Dictionary = {}
var teams: Dictionary = {}
var local_team_id: int = 0
var team_mode: bool = false
var last_drawn_projectiles: int = 0


func set_team_identity(assignments: Dictionary, local_team: int, enabled: bool) -> void:
	teams.clear()
	for peer in assignments:
		teams[int(peer)] = int(assignments[peer])
	local_team_id = local_team
	team_mode = enabled
	queue_redraw()


func has_team_marker(owner_id: int) -> bool:
	return team_mode and int(teams.get(owner_id, 0)) > 0


func is_friendly_owner(owner_id: int) -> bool:
	return has_team_marker(owner_id) and local_team_id > 0 and int(teams[owner_id]) == local_team_id


func set_beam_builds(builds: Dictionary, catalog: CardCatalog) -> void:
	projectile_colors_by_owner.clear()
	high_tier_beam_colors_by_owner.clear()
	for peer_value in builds:
		var build_value: Variant = builds[peer_value]
		if not build_value is Dictionary:
			continue
		var build := build_value as Dictionary
		var highest_weapon_card: CardDefinition
		var highest_beam_card: CardDefinition
		for card_value in build:
			if int(build[card_value]) <= 0:
				continue
			var card := catalog.get_card(StringName(card_value))
			if card == null or card.category != CardDefinition.Category.WEAPON:
				continue
			if card.special_behavior_id.is_empty() and (highest_weapon_card == null or card.rarity > highest_weapon_card.rarity):
				highest_weapon_card = card
			if card.special_behavior_id != &"beam_weapon":
				continue
			if highest_beam_card == null or card.rarity > highest_beam_card.rarity:
				highest_beam_card = card
		if highest_weapon_card != null:
			projectile_colors_by_owner[int(peer_value)] = highest_weapon_card.rarity_color()
		if highest_beam_card != null and highest_beam_card.rarity >= CardDefinition.Rarity.LEGENDARY:
			high_tier_beam_colors_by_owner[int(peer_value)] = highest_beam_card.rarity_color()
	queue_redraw()


func beam_color_for_owner(owner_id: int) -> Color:
	if has_team_marker(owner_id):
		return GameModeRules.team_color(int(teams[owner_id]))
	return high_tier_beam_colors_by_owner.get(owner_id, DEFAULT_BEAM_COLOR) as Color


func projectile_color_for_owner(owner_id: int) -> Color:
	if has_team_marker(owner_id):
		return GameModeRules.team_color(int(teams[owner_id]))
	return projectile_colors_by_owner.get(owner_id, DEFAULT_BEAM_COLOR) as Color


func _beam_color(projectile: ProjectileState) -> Color:
	if has_team_marker(projectile.owner_id):
		return projectile_color_for_owner(projectile.owner_id)
	if high_tier_beam_colors_by_owner.has(projectile.owner_id):
		return high_tier_beam_colors_by_owner[projectile.owner_id] as Color
	return REBOUNDED_BEAM_COLOR if projectile.has_rebounded else DEFAULT_BEAM_COLOR


func _draw() -> void:
	last_drawn_projectiles = 0
	if registry == null:
		return
	var simplified := registry.size() >= SIMPLIFY_PROJECTILE_THRESHOLD
	var cull_rect := visible_world_rect.grow(260.0)
	for projectile_id in registry.ordered_ids_view():
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := registry.get_projectile(projectile_id)
		if projectile == null or not cull_rect.has_point(projectile.position):
			continue
		last_drawn_projectiles += 1
		var friendly_alpha := 0.5 if simplified and is_friendly_owner(projectile.owner_id) else 1.0
		if projectile.is_mine:
			var mine_color := projectile_color_for_owner(projectile.owner_id) if has_team_marker(projectile.owner_id) else Color("ff4f78")
			var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.008 + projectile.projectile_id) * 0.5
			var armed := projectile.is_mine_armed()
			if armed:
				if not simplified:
					draw_circle(projectile.position, GameConstants.MINE_TRIGGER_RADIUS, Color(mine_color, 0.035 + pulse * 0.025))
				draw_arc(projectile.position, GameConstants.MINE_TRIGGER_RADIUS, 0.0, TAU, 40, Color(mine_color, 0.18 + pulse * 0.12), 2.0)
			if not simplified:
				draw_circle(projectile.position, projectile.radius + 7.0, Color(1.0, 0.95, 0.42, 0.12 + pulse * 0.08))
			draw_circle(projectile.position, projectile.radius, mine_color if armed else Color("7b8496"))
			draw_circle(projectile.position, 5.0, Color("fff36a"))
			for spoke in 4:
				var direction := Vector2.from_angle(TAU * spoke / 4.0 + PI * 0.25)
				draw_line(projectile.position + direction * 7.0, projectile.position + direction * 20.0, Color("ff9f43"), 4.0)
			_draw_team_marker(projectile)
			continue
		var direction := projectile.velocity.normalized()
		var trail_color := projectile_color_for_owner(projectile.owner_id) if has_team_marker(projectile.owner_id) else (REBOUNDED_BEAM_COLOR if projectile.has_rebounded else projectile_color_for_owner(projectile.owner_id))
		if projectile.is_missile:
			var side := direction.orthogonal()
			var tail := projectile.position - direction * (36.0 if simplified else 52.0)
			if not simplified:
				draw_line(projectile.position - direction * 9.0, tail, Color(0.75, 0.82, 0.92, 0.12), 17.0)
			draw_line(projectile.position - direction * 9.0, tail, trail_color if has_team_marker(projectile.owner_id) else Color("ff9f43"), 7.0)
			draw_line(projectile.position - direction * 7.0, tail + direction * 12.0, Color("fff36a"), 3.0)
			var nose := projectile.position + direction * 13.0
			var rear := projectile.position - direction * 11.0
			var body := PackedVector2Array([nose, rear + side * 7.0, rear - side * 7.0])
			draw_colored_polygon(body, Color("e8f2ff"))
			draw_polyline(PackedVector2Array([nose, rear + side * 7.0, rear - side * 7.0, nose]), Color("42e8ff"), 2.0)
			_draw_team_marker(projectile)
			continue
		if projectile.is_beam:
			trail_color = _beam_color(projectile)
			var tail := projectile.position - direction * (150.0 if simplified else 230.0)
			if not simplified:
				draw_line(projectile.position, tail, Color(trail_color, 0.16), 22.0)
			draw_line(projectile.position, tail, Color(trail_color, 0.68 * friendly_alpha), 6.0 if simplified else 10.0)
			draw_line(projectile.position, tail, Color(trail_color.lightened(0.82), 0.98 * friendly_alpha), 2.0 if simplified else 3.0)
			if not simplified:
				draw_circle(projectile.position, 12.0, Color(trail_color, 0.35))
			_draw_team_marker(projectile)
			continue
		if not simplified:
			draw_line(projectile.position, projectile.position - direction * 32.0, Color(trail_color, 0.16), 9.0)
			draw_circle(projectile.position, projectile.radius + 7.0, Color(trail_color, 0.12))
		draw_circle(projectile.position, projectile.radius, Color(trail_color.lightened(0.72), friendly_alpha))
		draw_line(projectile.position, projectile.position - direction * (14.0 if simplified else 25.0), Color(trail_color, 0.82 * friendly_alpha), 3.0)
		_draw_team_marker(projectile)


func _draw_team_marker(projectile: ProjectileState) -> void:
	if not has_team_marker(projectile.owner_id):
		return
	var point := projectile.position
	var radius := projectile.radius + 5.0
	var color := projectile_color_for_owner(projectile.owner_id)
	if is_friendly_owner(projectile.owner_id) or local_team_id == 0:
		draw_arc(point, radius, 0.0, TAU, 16, color, 2.0)
	else:
		draw_polyline(PackedVector2Array([point + Vector2(0, -radius), point + Vector2(radius, 0), point + Vector2(0, radius), point + Vector2(-radius, 0), point + Vector2(0, -radius)]), color, 2.0)
