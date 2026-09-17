class_name ArenaEffectControls
extends VBoxContainer

signal settings_changed(settings: Dictionary)
var selectors: Dictionary = {}
var toggles: Array[CheckButton] = []
var updating := false

func _ready() -> void:
	for entry in [["mode", "Arena effects", ["Off", "Map signature", "Custom"]], ["frequency", "Event frequency", ["Low", "Normal", "High"]], ["strength", "Hazard strength", ["Gentle", "Standard", "Brutal"]]]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = entry[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var selector := OptionButton.new()
		selector.custom_minimum_size = Vector2(190, 42)
		for choice in entry[2]: selector.add_item(choice)
		selector.item_selected.connect(func(_index: int) -> void: _changed())
		selectors[entry[0]] = selector
		row.add_child(selector)
		add_child(row)
	for label in ["Solar pulses · Twin Suns", "Destructible cargo · Dead Freight", "Blast doors · Switchyard"]:
		var toggle := CheckButton.new()
		toggle.text = label
		toggle.theme_type_variation = &"SettingToggle"
		toggle.toggled.connect(func(_pressed: bool) -> void: _changed())
		toggles.append(toggle)
		add_child(toggle)
	var note := Label.new()
	note.text = "Effects run on compatible maps. Terrain resets each heat.\nPulses stop and doors open before overtime."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)

func refresh(settings: Dictionary, editable: bool) -> void:
	updating = true
	for key in selectors:
		(selectors[key] as OptionButton).select(int(settings.get(key, ArenaEffectRules.DEFAULT[key])))
		(selectors[key] as OptionButton).disabled = not editable or (key != "mode" and int(settings.get("mode", 0)) == 0)
	for index in toggles.size():
		toggles[index].set_pressed_no_signal((int(settings.get("mask", 7)) & (1 << index)) != 0)
		toggles[index].visible = int(settings.get("mode", 0)) == ArenaEffectRules.CUSTOM
		toggles[index].disabled = not editable
	updating = false

func _changed() -> void:
	if updating: return
	var settings := ArenaEffectRules.DEFAULT.duplicate()
	for key in selectors: settings[key] = (selectors[key] as OptionButton).selected
	settings.mask = 0
	for index in toggles.size():
		if toggles[index].button_pressed: settings.mask |= 1 << index
	settings_changed.emit(settings)
