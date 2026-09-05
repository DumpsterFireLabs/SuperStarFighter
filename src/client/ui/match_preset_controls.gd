extends RefCounted

## Shared preset selector construction for hosting and lobby setup.
const MatchPresetsScript = preload("res://src/shared/lobby/match_presets.gd")


static func create_picker(parent: VBoxContainer) -> OptionButton:
	var label := Label.new()
	label.text = "SOLO OR PARTY PRESET"
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)
	var picker := OptionButton.new()
	picker.name = "MatchPreset"
	picker.custom_minimum_size.y = 42.0
	picker.add_item("Custom · configure in the lobby")
	picker.set_item_metadata(0, "")
	for preset in MatchPresetsScript.PRESETS:
		picker.add_item(String(preset.name))
		picker.set_item_metadata(picker.item_count - 1, String(preset.id))
	parent.add_child(picker)
	return picker


static func create_note(parent: VBoxContainer) -> Label:
	var note := Label.new()
	note.text = description(0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	parent.add_child(note)
	return note


static func description(index: int) -> String:
	return "Choose a quick setup or adjust every rule in Advanced settings. All presets can be edited before launch." if index == 0 else String(MatchPresetsScript.PRESETS[index - 1].description)
