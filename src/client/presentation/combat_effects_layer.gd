class_name CombatEffectsLayer
extends Node2D

var effects: Array[Dictionary] = []


func _process(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		var effect := effects[index]
		effect.remaining = float(effect.remaining) - delta
		if float(effect.remaining) <= 0.0:
			effects.remove_at(index)
	queue_redraw()


func spawn_impact(position: Vector2, color: Color = Color("f4fbff")) -> void:
	effects.append({"kind": &"impact", "position": position, "color": color, "remaining": 0.22, "duration": 0.22})


func spawn_elimination(position: Vector2, color: Color) -> void:
	effects.append({"kind": &"elimination", "position": position, "color": color, "remaining": 0.65, "duration": 0.65})


func spawn_damage(position: Vector2, direction: Vector2) -> void:
	effects.append({"kind": &"damage", "position": position, "direction": direction, "color": Color("ff4f78"), "remaining": 0.3, "duration": 0.3})


func clear_effects() -> void:
	effects.clear()
	queue_redraw()


func _draw() -> void:
	for effect in effects:
		var progress := 1.0 - float(effect.remaining) / float(effect.duration)
		var alpha := 1.0 - progress
		var position := effect.position as Vector2
		var color := effect.color as Color
		match StringName(effect.kind):
			&"impact":
				draw_circle(position, lerpf(5.0, 24.0, progress), Color(color, alpha * 0.24))
				for ray in 6:
					var direction := Vector2.from_angle(TAU * ray / 6.0)
					draw_line(position + direction * 5.0, position + direction * lerpf(8.0, 34.0, progress), Color(color, alpha), 3.0)
			&"elimination":
				draw_circle(position, lerpf(18.0, 86.0, progress), Color(color, alpha * 0.12))
				draw_arc(position, lerpf(20.0, 96.0, progress), 0.0, TAU, 40, Color(color, alpha), 5.0)
				for ray in 10:
					var direction := Vector2.from_angle(TAU * ray / 10.0 + 0.2)
					draw_line(position + direction * 22.0, position + direction * lerpf(30.0, 110.0, progress), Color(color, alpha), 4.0)
			&"damage":
				var direction := (effect.direction as Vector2).normalized()
				var side := direction.orthogonal()
				var tip := position + direction * lerpf(36.0, 64.0, progress)
				draw_colored_polygon(PackedVector2Array([tip, tip - direction * 18.0 + side * 10.0, tip - direction * 18.0 - side * 10.0]), Color(color, alpha))
