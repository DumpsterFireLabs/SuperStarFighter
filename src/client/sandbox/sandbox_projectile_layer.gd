class_name SandboxProjectileLayer
extends Node2D

var registry: ProjectileRegistry
var visible_world_rect: Rect2 = Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)


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
			draw_circle(projectile.position, GameConstants.MINE_TRIGGER_RADIUS, Color(1.0, 0.31, 0.47, 0.035 + pulse * 0.025))
			draw_arc(projectile.position, GameConstants.MINE_TRIGGER_RADIUS, 0.0, TAU, 40, Color(1.0, 0.31, 0.47, 0.18 + pulse * 0.12), 2.0)
			draw_circle(projectile.position, projectile.radius + 7.0, Color(1.0, 0.95, 0.42, 0.12 + pulse * 0.08))
			draw_circle(projectile.position, projectile.radius, Color("ff4f78"))
			draw_circle(projectile.position, 5.0, Color("fff36a"))
			for spoke in 4:
				var direction := Vector2.from_angle(TAU * spoke / 4.0 + PI * 0.25)
				draw_line(projectile.position + direction * 7.0, projectile.position + direction * 20.0, Color("ff9f43"), 4.0)
			continue
		var direction := projectile.velocity.normalized()
		var trail_color := Color("ff4fd8") if projectile.has_rebounded else Color("42e8ff")
		if projectile.is_beam:
			var tail := projectile.position - direction * 230.0
			draw_line(projectile.position, tail, Color(0.42, 0.08, 1.0, 0.16), 22.0)
			draw_line(projectile.position, tail, Color(trail_color, 0.68), 10.0)
			draw_line(projectile.position, tail, Color(1.0, 0.94, 1.0, 0.98), 3.0)
			draw_circle(projectile.position, 12.0, Color(0.45, 0.9, 1.0, 0.35))
			continue
		draw_line(projectile.position, projectile.position - direction * 32.0, Color(trail_color, 0.16), 9.0)
		draw_circle(projectile.position, projectile.radius + 7.0, Color(trail_color, 0.12))
		draw_circle(projectile.position, projectile.radius, Color("f4fbff"))
		draw_line(projectile.position, projectile.position - direction * 25.0, Color(trail_color, 0.82), 3.0)
