extends CanvasLayer

signal closed

var source: CardHoverButton
var surface: Control
var panel: PanelContainer
var scroll: ScrollContainer
var close_button: Button
var preview: Control
var preview_signature: String


func _ready() -> void:
	layer = 100
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.theme = DesignTokens.create_interface_theme()
	add_child(surface)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(DesignTokens.BACKGROUND, 0.9)
	surface.add_child(dim)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", DesignTokens.quiet_panel_style())
	surface.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var hint := Label.new()
	hint.text = "↑ / ↓ scroll · Enter / A or Back to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	column.add_child(hint)
	close_button = Button.new()
	close_button.text = "Close details"
	close_button.theme_type_variation = &"QuietButton"
	close_button.pressed.connect(close)
	column.add_child(close_button)
	get_viewport().size_changed.connect(_layout)
	hide()


func open(button: CardHoverButton) -> void:
	if preview != null:
		scroll.remove_child(preview)
		preview.queue_free()
	source = button
	preview_signature = button.tooltip_text
	preview = button._make_custom_tooltip(button.tooltip_text) as Control
	if preview == null:
		return
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(preview)
	preview.minimum_size_changed.connect(_layout)
	scroll.scroll_vertical = 0
	show()
	_layout()
	_layout.call_deferred()
	close_button.grab_focus()


func close(restore_focus: bool = true) -> void:
	if not visible:
		return
	hide()
	if restore_focus and is_instance_valid(source) and source.is_visible_in_tree() and not source.disabled:
		source.grab_focus()
	source = null
	closed.emit()


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_overlay") or event.is_action_pressed(&"ui_accept"):
		close()
	elif event.is_action_pressed(&"ui_down"):
		scroll.scroll_vertical += 60
	elif event.is_action_pressed(&"ui_up"):
		scroll.scroll_vertical -= 60
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_PAGEDOWN:
			scroll.scroll_vertical += int(scroll.size.y * 0.8)
		elif event.keycode == KEY_PAGEUP:
			scroll.scroll_vertical -= int(scroll.size.y * 0.8)
	# Keep all keyboard/controller actions inside the modal, including Tab,
	# draft shortcuts and gameplay bindings. Pointer input reaches its controls.
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction:
		get_viewport().set_input_as_handled()


func _layout() -> void:
	if panel == null:
		return
	var available := get_viewport().get_visible_rect().size
	var content_height := preview.get_combined_minimum_size().y + 140.0 if is_instance_valid(preview) else 400.0
	panel.size = Vector2(minf(1040.0, available.x - 64.0), minf(clampf(content_height, 380.0, 850.0), available.y - 64.0))
	panel.position = (available - panel.size) * 0.5


func _process(_delta: float) -> void:
	if visible and (not is_instance_valid(source) or not source.is_visible_in_tree() or source.tooltip_text != preview_signature):
		close(false)
