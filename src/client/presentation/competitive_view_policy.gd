extends RefCounted

## A single native viewport: fixed combat space without an extra render target.
## This is display parity for standard clients, not a network anti-cheat boundary.
const REFERENCE_SIZE := Vector2i(1920, 1080)
var active: bool = false
var _window: Window
var _original_size: Vector2i
var _original_mode: int
var _original_aspect: int


func apply(window: Window, enabled: bool) -> void:
	if not enabled:
		restore()
		return
	if active and _window == window:
		return
	restore()
	_window = window
	_original_size = window.content_scale_size
	_original_mode = window.content_scale_mode
	_original_aspect = window.content_scale_aspect
	active = true
	window.content_scale_size = REFERENCE_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func restore() -> void:
	if active and is_instance_valid(_window):
		_window.content_scale_size = _original_size
		_window.content_scale_mode = _original_mode
		_window.content_scale_aspect = _original_aspect
	active = false
	_window = null


func gameplay_point(point: Vector2) -> Vector2:
	# Native pointer confinement covers the whole window, including black bars.
	# Share one logical point between cursor presentation and weapon aiming.
	return point.clamp(Vector2.ONE, Vector2(REFERENCE_SIZE) - Vector2.ONE) if active else point


static func physical_content_rect(window_size: Vector2) -> Rect2:
	var reference := Vector2(REFERENCE_SIZE)
	var scale_factor := minf(window_size.x / reference.x, window_size.y / reference.y)
	var fitted := reference * maxf(scale_factor, 0.0)
	return Rect2((window_size - fitted) * 0.5, fitted)
