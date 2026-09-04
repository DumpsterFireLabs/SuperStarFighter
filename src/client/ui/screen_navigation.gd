extends RefCounted

## Joypad tab selection stays scoped to the focused tab bar.

static func handle_tab_bar_input(event: InputEvent, tabs: TabContainer) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	var direction := 0
	if event.is_action_pressed(&"ui_left"):
		direction = -1
	elif event.is_action_pressed(&"ui_right"):
		direction = 1
	if direction != 0:
		tabs.current_tab = clampi(tabs.current_tab + direction, 0, tabs.get_tab_count() - 1)
		tabs.get_tab_bar().accept_event()
