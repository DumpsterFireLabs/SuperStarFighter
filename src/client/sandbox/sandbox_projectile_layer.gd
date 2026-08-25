class_name SandboxProjectileLayer
extends Node2D

var registry: ProjectileRegistry


func _draw() -> void:
	if registry == null:
		return
	for projectile in registry.all_projectiles():
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
