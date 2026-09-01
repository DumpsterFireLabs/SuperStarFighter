class_name SandboxProjectileLayer
extends Node2D

const DEFAULT_BEAM_COLOR: Color = Color("42e8ff")
const REBOUNDED_BEAM_COLOR: Color = Color("ff4fd8")

var registry: ProjectileRegistry
var visible_world_rect: Rect2 = Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)
var projectile_colors_by_owner: Dictionary = {}
var high_tier_beam_colors_by_owner: Dictionary = {}


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
	return high_tier_beam_colors_by_owner.get(owner_id, DEFAULT_BEAM_COLOR) as Color


func projectile_color_for_owner(owner_id: int) -> Color:
	return projectile_colors_by_owner.get(owner_id, DEFAULT_BEAM_COLOR) as Color


func _beam_color(projectile: ProjectileState) -> Color:
	if high_tier_beam_colors_by_owner.has(projectile.owner_id):
		return high_tier_beam_colors_by_owner[projectile.owner_id] as Color
	return REBOUNDED_BEAM_COLOR if projectile.has_rebounded else DEFAULT_BEAM_COLOR


func _draw() -> void:
	if registry == null:
		return
	var cull_rect := visible_world_rect.grow(260.0)
	for projectile_id in registry.ordered_ids_view():
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := registry.get_projectile(projectile_id)
		if projectile == null or not cull_rect.has_point(projectile.position):
			continue
		if projectile.is_mine:
			var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.008 + projectile.projectile_id) * 0.5
			var armed := projectile.is_mine_armed()
			if armed:
				draw_circle(projectile.position, GameConstants.MINE_TRIGGER_RADIUS, Color(1.0, 0.31, 0.47, 0.035 + pulse * 0.025))
				draw_arc(projectile.position, GameConstants.MINE_TRIGGER_RADIUS, 0.0, TAU, 40, Color(1.0, 0.31, 0.47, 0.18 + pulse * 0.12), 2.0)
			draw_circle(projectile.position, projectile.radius + 7.0, Color(1.0, 0.95, 0.42, 0.12 + pulse * 0.08))
			draw_circle(projectile.position, projectile.radius, Color("ff4f78") if armed else Color("7b8496"))
			draw_circle(projectile.position, 5.0, Color("fff36a"))
			for spoke in 4:
				var direction := Vector2.from_angle(TAU * spoke / 4.0 + PI * 0.25)
				draw_line(projectile.position + direction * 7.0, projectile.position + direction * 20.0, Color("ff9f43"), 4.0)
			continue
		var direction := projectile.velocity.normalized()
		var trail_color := REBOUNDED_BEAM_COLOR if projectile.has_rebounded else projectile_color_for_owner(projectile.owner_id)
		if projectile.is_missile:
			var side := direction.orthogonal()
			var tail := projectile.position - direction * 52.0
			draw_line(projectile.position - direction * 9.0, tail, Color(0.75, 0.82, 0.92, 0.12), 17.0)
			draw_line(projectile.position - direction * 9.0, tail, Color("ff9f43"), 7.0)
			draw_line(projectile.position - direction * 7.0, tail + direction * 12.0, Color("fff36a"), 3.0)
			var nose := projectile.position + direction * 13.0
			var rear := projectile.position - direction * 11.0
			var body := PackedVector2Array([nose, rear + side * 7.0, rear - side * 7.0])
			draw_colored_polygon(body, Color("e8f2ff"))
			draw_polyline(PackedVector2Array([nose, rear + side * 7.0, rear - side * 7.0, nose]), Color("42e8ff"), 2.0)
			continue
		if projectile.is_beam:
			trail_color = _beam_color(projectile)
			var tail := projectile.position - direction * 230.0
			draw_line(projectile.position, tail, Color(trail_color, 0.16), 22.0)
			draw_line(projectile.position, tail, Color(trail_color, 0.68), 10.0)
			draw_line(projectile.position, tail, Color(trail_color.lightened(0.82), 0.98), 3.0)
			draw_circle(projectile.position, 12.0, Color(trail_color, 0.35))
			continue
		draw_line(projectile.position, projectile.position - direction * 32.0, Color(trail_color, 0.16), 9.0)
		draw_circle(projectile.position, projectile.radius + 7.0, Color(trail_color, 0.12))
		draw_circle(projectile.position, projectile.radius, trail_color.lightened(0.72))
		draw_line(projectile.position, projectile.position - direction * 25.0, Color(trail_color, 0.82), 3.0)
