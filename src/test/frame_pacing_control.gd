extends SceneTree

## Empty-window control: isolate presentation pacing from simulation and UI.
var frames: Array[int] = []
var draw: Array[int] = []
var began: int = 0
var previous: int = 0
var pre_draw: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	began = Time.get_ticks_usec()
	previous = began
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)
	# Finish from the scene loop, not inside RenderingServer's signal dispatch.
	await create_timer(8.0).timeout
	RenderingServer.frame_pre_draw.disconnect(_before_draw)
	RenderingServer.frame_post_draw.disconnect(_after_draw)
	frames.sort()
	draw.sort()
	print("SSF_FRAME_CONTROL=%s" % JSON.stringify({
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"frame_cap": Engine.max_fps, "window_mode": DisplayServer.window_get_mode(),
		"viewport": str(root.size), "low_processor": OS.low_processor_usage_mode,
		"samples": frames.size(), "p50_usec": NetworkBridge.percentile_usec(frames, 0.5),
		"p95_usec": NetworkBridge.percentile_usec(frames, 0.95),
		"draw_p95_usec": NetworkBridge.percentile_usec(draw, 0.95),
		"scope": "Empty viewport, 7 measured seconds after 1s warmup; no gameplay, audio, physics actors or network. Draw includes presentation wait; not physical display latency."
	}))
	quit.call_deferred(0 if frames.size() >= 100 else 1)


func _before_draw() -> void:
	pre_draw = Time.get_ticks_usec()


func _after_draw() -> void:
	var now := Time.get_ticks_usec()
	if now - began > 1000000:
		frames.append(now - previous)
		draw.append(now - pre_draw)
	previous = now
