extends SceneTree

## Paired deterministic rendering: identical frozen state, legacy vertex writer
## versus production draw transform. Both viewports render on the same frame.
class MeasuredShip extends CombatShipView:
	var pattern_usec: Array[int] = []
	func _draw_pattern_polygons(polygons: Array, forward: Vector2, side: Vector2, color: Color) -> void:
		var start := Time.get_ticks_usec()
		super._draw_pattern_polygons(polygons, forward, side, color)
		pattern_usec.append(Time.get_ticks_usec() - start)

class LegacyShip extends MeasuredShip:
	func _draw_pattern_polygons(polygons: Array, forward: Vector2, side: Vector2, color: Color) -> void:
		var start := Time.get_ticks_usec()
		for polygon: PackedVector2Array in polygons:
			var transformed := PackedVector2Array()
			for point in polygon:
				transformed.append(_ship_local(point, forward, side))
			draw_colored_polygon(transformed, color)
		pattern_usec.append(Time.get_ticks_usec() - start)

var views: Array[SubViewport] = []
var ships: Array = [[], []]
var valid := true
const OUTPUT := "res://.tools/performance-patterns"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for variant in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 1080)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views.append(viewport)
		var display := Sprite2D.new()
		display.texture = viewport.get_texture()
		display.centered = false
		display.position.x = variant * 960
		root.add_child(display)
		for index in 24:
			var ship: MeasuredShip = LegacyShip.new() if variant == 0 else MeasuredShip.new()
			ship.setup(index + 1, CombatStats.create_base(), Vector2(80 + (index % 6) * 160, 160 + (index / 6) * 240), Color("42e8ff"), false, "Pilot", ShipAppearance.PATTERNS[index % 6])
			viewport.add_child(ship)
			ship.set_process(false)
			ship.thruster_particles.emitting = false
			ship.reduced_flashes = true
			ships[variant].append(ship)
	var comparisons := []
	for local in [false, true]:
		for contrast in [false, true]:
			for mode in ["normal", "shield", "cloak", "effects"]:
				for variant in 2:
					for index in 24:
						var ship := ships[variant][index] as MeasuredShip
						ship.local_control = local
						ship.high_contrast = contrast
						ship.combatant.aim_angle = [0.0, PI / 4.0, PI * 0.5, PI * 1.37][index / 6]
						ship.combatant.shield.active = mode == "shield" or mode == "effects"
						ship.combatant.cloak_remaining = 1.0 if mode == "cloak" else 0.0
						ship.combatant.breakaway_remaining = 0.3 if mode == "effects" else 0.0
						ship.afterburner_bloom_remaining = 0.2 if mode == "effects" else 0.0
						ship.afterburner_duration = 0.4
						ship.movement_field_strength = 0.7 if mode == "effects" else 0.0
						ship.combatant.velocity = Vector2(300, 100)
						ship.set_team_identity(1, 1 if local else 2)
						ship.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var a := views[0].get_texture().get_image()
				var b := views[1].get_texture().get_image()
				var comparison := _difference(a, b)
				comparison["case"] = "%s-local%s-contrast%s" % [mode, local, contrast]
				comparisons.append(comparison)
				valid = valid and float(comparison.mean_channel_error) < 0.001 and float(comparison.changed_pixel_fraction) < 0.003
				var capture := Image.create(1920, 1080, false, a.get_format())
				capture.blit_rect(a, Rect2i(0, 0, 960, 1080), Vector2i.ZERO)
				capture.blit_rect(b, Rect2i(0, 0, 960, 1080), Vector2i(960, 0))
				capture.save_png(OUTPUT + "/" + comparison.case + ".png")
	# Replay the same angle sequence; alternate tree order to reduce order bias.
	var draw_calls: Array = [[], []]
	for variant in 2:
		for ship: MeasuredShip in ships[variant]: ship.pattern_usec.clear()
	for tick in 240:
		root.move_child(views[tick % 2], 0)
		for variant in 2:
			for index in 24:
				var ship := ships[variant][index] as MeasuredShip
				ship.combatant.cloak_remaining = 0.0
				ship.combatant.aim_angle = tick * 0.025 + index * 0.2
				ship.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		for variant in 2:
			draw_calls[variant].append(views[variant].get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
	var timing := []
	for variant in 2:
		var samples: Array[int] = []
		for ship: MeasuredShip in ships[variant]: samples.append_array(ship.pattern_usec)
		var total := 0
		for sample in samples: total += sample
		samples.sort()
		timing.append({"variant": "legacy" if variant == 0 else "production", "calls": samples.size(), "mean_usec": float(total) / maxi(1, samples.size()), "p95_usec": NetworkBridge.percentile_usec(samples, 0.95), "draw_calls_min": draw_calls[variant].min(), "draw_calls_max": draw_calls[variant].max()})
	var result := {"valid": valid, "comparisons": comparisons, "timing": timing, "scope": "24 ships, six patterns, four angles, both pilot roles/contrast modes, shields/cloak/effects; 240 alternating-order paired replay frames; callback instrumentation enabled"}
	var file := FileAccess.open(OUTPUT + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("SSF_PATTERN_RENDER=" + JSON.stringify(result))
	quit(0 if valid else 1)

func _difference(a: Image, b: Image) -> Dictionary:
	var left := a.get_data()
	var right := b.get_data()
	var total_error := 0
	var changed := 0
	for offset in range(0, left.size(), 4):
		var pixel_error := 0
		for channel in 3:
			pixel_error += absi(left[offset + channel] - right[offset + channel])
		total_error += pixel_error
		if pixel_error > 6: changed += 1
	return {"mean_channel_error": float(total_error) / (a.get_width() * a.get_height() * 3 * 255), "changed_pixel_fraction": float(changed) / (a.get_width() * a.get_height())}
