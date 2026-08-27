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
		var direction := projectile.velocity.normalized()
		if projectile.is_beam:
			var tail := projectile.position - direction * 230.0
			draw_line(projectile.position, tail, Color(0.42, 0.08, 1.0, 0.16), 22.0)
			draw_line(projectile.position, tail, Color(0.1, 0.88, 1.0, 0.68), 10.0)
			draw_line(projectile.position, tail, Color(1.0, 0.94, 1.0, 0.98), 3.0)
			draw_circle(projectile.position, 12.0, Color(0.45, 0.9, 1.0, 0.35))
			continue
		draw_line(projectile.position, projectile.position - direction * 32.0, Color(0.15, 0.75, 1.0, 0.16), 9.0)
		draw_circle(projectile.position, projectile.radius + 7.0, Color(0.2, 0.9, 1.0, 0.12))
		draw_circle(projectile.position, projectile.radius, Color("f4fbff"))
		draw_line(projectile.position, projectile.position - direction * 25.0, Color(0.25, 0.85, 1.0, 0.82), 3.0)
