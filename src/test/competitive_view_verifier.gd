extends SceneTree

const Policy = preload("res://src/client/presentation/competitive_view_policy.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var policy = Policy.new()
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.position = Vector2(1600, 900)
	var previous_size := root.size
	for physical in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(2880, 1920), Vector2i(3440, 1440), Vector2i(5120, 1440)]:
		root.size = physical
		policy.apply(root, true)
		await process_frame
		await process_frame
		camera.force_update_scroll()
		var visible := root.get_visible_rect().size
		if not visible.is_equal_approx(Vector2(1920, 1080)):
			_fail("visible_extent:%s:%s" % [physical, visible])
			return
		var to_world := root.get_canvas_transform().affine_inverse()
		var top_left := to_world * Vector2.ZERO
		var bottom_right := to_world * visible
		if not (bottom_right - top_left).is_equal_approx(Vector2(1920, 1080)):
			_fail("camera_extent:%s" % physical)
			return
		if not (to_world * (visible * 0.5)).is_equal_approx(camera.position):
			_fail("aim_center:%s" % physical)
			return
		print("COMPETITIVE_VIEW_RESIZE_OK physical=%s visible=%s world=%s..%s" % [physical, visible, top_left, bottom_right])
	policy.restore()
	await process_frame
	var expanded := root.get_visible_rect().size
	if expanded.x <= 1920:
		_fail("ultrawide_restore:%s" % expanded)
		return
	root.size = previous_size
	print("SSF_COMPETITIVE_VIEW_OK=resize_camera_extent_aim_center_restore")
	quit(0)


func _fail(reason: String) -> void:
	printerr("SSF_COMPETITIVE_VIEW_ERROR=%s" % reason)
	quit(1)
