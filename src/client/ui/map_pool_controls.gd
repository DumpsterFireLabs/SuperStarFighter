extends VBoxContainer

signal pool_changed(pool: Array)
var toggles: Dictionary = {}
var descriptions: Dictionary = {}
var _updating := false


func _ready() -> void:
	var note := Label.new()
	note.text = "Select at least one map. The server shuffles this pool once per match; every heat in a round uses the same map. Intrinsic mechanics stay active even when optional effects are Off."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	for map_id in ArenaLayout.map_ids():
		var toggle := CheckButton.new()
		toggle.text = ArenaLayout.display_name(map_id)
		toggle.theme_type_variation = &"SettingToggle"
		toggle.custom_minimum_size.y = 42
		toggle.toggled.connect(_changed)
		toggle.focus_entered.connect(func() -> void: _reveal_description.call_deferred(map_id))
		toggles[map_id] = toggle
		add_child(toggle)
		var description := Label.new()
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		descriptions[map_id] = description
		add_child(description)


func refresh(pool: Array, settings: Dictionary, editable: bool) -> void:
	_updating = true
	for map_id in toggles:
		var selected := pool.has(map_id)
		(toggles[map_id] as CheckButton).set_pressed_no_signal(selected)
		(toggles[map_id] as CheckButton).disabled = not editable or (selected and pool.size() == 1)
		(descriptions[map_id] as Label).text = ArenaEffectRules.mechanics_summary(settings, map_id)
	_updating = false


func _changed(_pressed: bool) -> void:
	if _updating: return
	var pool: Array[StringName] = []
	for map_id in toggles:
		if (toggles[map_id] as CheckButton).button_pressed: pool.append(map_id)
	pool_changed.emit(pool)


func first_editable_control() -> Control:
	for toggle in toggles.values():
		if not toggle.disabled: return toggle
	return toggles.values()[0]


func _reveal_description(map_id: StringName) -> void:
	# Keyboard navigation must reveal the mechanic below the toggle as well.
	var ancestor := get_parent_control()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent_control()
	if ancestor is ScrollContainer:
		(ancestor as ScrollContainer).ensure_control_visible(descriptions[map_id])


static func summary(pool: Array, settings: Dictionary) -> String:
	var intrinsic := PackedStringArray()
	for value in pool:
		var map_id := StringName(value)
		if not ArenaLayout.movement_fields(map_id).is_empty() or ArenaLayout.intrinsic_effects(map_id) != 0 or ArenaLayout.contact_damage(map_id) > 0:
			intrinsic.append(ArenaLayout.display_name(map_id))
	return "%d maps · Optional effects: %s\nIntrinsic mechanics: %s" % [pool.size(), ["Off", "Map signature", "Custom"][int(settings.mode)], ", ".join(intrinsic) if not intrinsic.is_empty() else "none"]
