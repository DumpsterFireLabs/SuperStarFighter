class_name SandboxProjectileLayer
extends Node2D

var registry: ProjectileRegistry


func _draw() -> void:
	if registry == null:
		return
	for projectile in registry.all_projectiles():
		var direction := projectile.velocity.normalized()
		draw_line(projectile.position, projectile.position - direction * 32.0, Color(0.15, 0.75, 1.0, 0.16), 9.0)
		draw_circle(projectile.position, projectile.radius + 7.0, Color(0.2, 0.9, 1.0, 0.12))
		draw_circle(projectile.position, projectile.radius, Color("f4fbff"))
		draw_line(projectile.position, projectile.position - direction * 25.0, Color(0.25, 0.85, 1.0, 0.82), 3.0)
