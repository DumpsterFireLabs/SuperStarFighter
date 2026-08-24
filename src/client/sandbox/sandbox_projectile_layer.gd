class_name SandboxProjectileLayer
extends Node2D

var registry: ProjectileRegistry


func _draw() -> void:
	if registry == null:
		return
	for projectile in registry.all_projectiles():
		draw_circle(projectile.position, projectile.radius + 4.0, Color(0.2, 0.9, 1.0, 0.13))
		draw_circle(projectile.position, projectile.radius, Color("f4fbff"))
		draw_line(projectile.position, projectile.position - projectile.velocity.normalized() * 20.0, Color(0.25, 0.85, 1.0, 0.7), 3.0)
