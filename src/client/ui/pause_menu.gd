extends Node

## The in-game pilot menu (Escape) and the match-wide intermission notice.
## Buttons only emit intent; the client decides what each one does.

signal resume_requested
signal global_pause_requested
signal settings_requested
signal admin_requested
signal disconnect_requested
signal quit_requested

const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")

var overlay: PanelContainer
var title: Label
var note: Label
var global_pause_button: Button
var resume_button: Button
var disconnect_button: Button
var global_pause_notice: Label


func is_open() -> bool:
	return overlay != null and overlay.visible


## `notice_parent` receives the always-on-top canvas for the intermission notice.
func create_ui(canvas: CanvasLayer, notice_parent: Node, theme: Theme, panel_style: StyleBox) -> void:
	overlay = PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_CENTER)
	overlay.position = Vector2(-320.0, -220.0)
	overlay.custom_minimum_size = Vector2(640.0, 440.0)
	overlay.theme = theme
	overlay.add_theme_stylebox_override("panel", panel_style)
	overlay.visible = false
	canvas.add_child(overlay)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	overlay.add_child(content)
	title = Label.new()
	title.text = "PILOT MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"ScreenTitle"
	content.add_child(title)
	note = Label.new()
	note.text = "Online combat continues while this menu is open."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.theme_type_variation = &"HintLabel"
	content.add_child(note)
	global_pause_button = Button.new()
	global_pause_button.name = "GlobalPauseButton"
	global_pause_button.custom_minimum_size.y = 58.0
	# Resume is the one primary action here; pausing everyone is an alternate.
	global_pause_button.theme_type_variation = &"SecondaryButton"
	global_pause_button.visible = false
	global_pause_button.pressed.connect(global_pause_requested.emit)
	content.add_child(global_pause_button)
	resume_button = _add_button(content, "RESUME", &"PrimaryButton", resume_requested)
	_add_button(content, "SETTINGS", &"SecondaryButton", settings_requested)
	_add_button(content, "SERVER ADMIN", &"SecondaryButton", admin_requested).name = "PauseAdminButton"
	disconnect_button = _add_button(content, "DISCONNECT / RETURN TO MENU", &"DangerButton", disconnect_requested)
	disconnect_button.name = "PauseDisconnectButton"
	_add_button(content, "QUIT GAME", &"DangerButton", quit_requested)
	var notice_canvas := CanvasLayer.new()
	notice_canvas.layer = 21
	notice_parent.add_child(notice_canvas)
	global_pause_notice = Label.new()
	global_pause_notice.name = "GlobalPauseNotice"
	global_pause_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	global_pause_notice.add_theme_font_size_override("font_size", 26)
	global_pause_notice.add_theme_color_override("font_color", DesignTokensScript.WARNING)
	global_pause_notice.add_theme_color_override("font_outline_color", Color("02040d"))
	global_pause_notice.add_theme_constant_override("outline_size", 10)
	global_pause_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_pause_notice.visible = false
	notice_canvas.add_child(global_pause_notice)
	global_pause_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	global_pause_notice.offset_top = 12.0


## Refreshes the menu and notice for the match-wide pause. `binding` is the
## global-pause shortcut's display text ("Unbound" when none); `awaiting` lists
## pilots the server is holding seats for.
func show_global_pause(paused: bool, is_host: bool, can_toggle: bool, binding: String, awaiting: Array) -> void:
	global_pause_button.visible = can_toggle
	global_pause_button.text = "RESUME MATCH FOR EVERYONE" if paused else "PAUSE MATCH FOR EVERYONE"
	if binding != "Unbound":
		global_pause_button.text += " · " + binding
	resume_button.text = "CLOSE MENU" if paused else "RESUME"
	note.text = "Match and timers are paused for everyone." if paused else "Online combat continues while this menu is open."
	global_pause_notice.visible = paused
	var resume_hint := "%s to resume for everyone." % binding if binding != "Unbound" else "Open the pilot menu to resume for everyone."
	global_pause_notice.text = "INTERMISSION · MATCH PAUSED\n" + (resume_hint if is_host else "Waiting for the host to resume.")
	if paused and not awaiting.is_empty():
		global_pause_notice.text = "MATCH PAUSED · PILOT DISCONNECTED\nWaiting for %s to reconnect." % ", ".join(PackedStringArray(awaiting))


func _add_button(parent: Container, text: String, variation: StringName, intent: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size.y = 58.0
	button.pressed.connect(intent.emit)
	parent.add_child(button)
	return button
