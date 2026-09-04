extends RefCounted

## Hold/toggle translation stays local; the server receives ordinary held input.
var active: Dictionary = {}
var previous: Dictionary = {}
var needs_release: Dictionary = {}


func reset() -> void:
	active.clear()
	previous.clear()
	needs_release = {&"fire": true, &"shield": true}


func sample(action: StringName, held: bool, toggle: bool, enabled: bool) -> bool:
	if not enabled:
		active[action] = false
		previous[action] = held
		needs_release[action] = held
		return false
	if bool(needs_release.get(action, false)):
		needs_release[action] = held
		previous[action] = held
		return false
	if toggle and held and not bool(previous.get(action, false)):
		active[action] = not bool(active.get(action, false))
	previous[action] = held
	if not toggle:
		active[action] = false
	return bool(active.get(action, false)) if toggle else held


func status(preferences: Dictionary) -> String:
	var parts := PackedStringArray()
	for action in [&"fire", &"shield"]:
		if bool(preferences.get("toggle_" + str(action), false)):
			parts.append("%s %s" % [str(action).to_upper(), "ON" if bool(active.get(action, false)) else "OFF"])
	return "TOGGLE · " + " · ".join(parts) if not parts.is_empty() else ""


static func create_status_label(parent: Control) -> Label:
	var label := Label.new()
	label.name = "ToggleStatus"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color("fff36a"))
	label.add_theme_color_override("font_outline_color", Color("02040d"))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -530.0
	label.offset_top = -38.0
	label.offset_right = -20.0
	label.offset_bottom = -6.0
	return label
