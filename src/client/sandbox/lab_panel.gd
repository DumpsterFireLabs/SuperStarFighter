extends PanelContainer

var lab: OfflineSandbox
var search: LineEdit
var cards: ItemList
var card_description: Label
var build_label: Label
var stats_label: Label
var telemetry_label: Label
var help_label: Label
var add_button: Button
var remove_button: Button
var filtered_ids: Array[StringName] = []
var count_control: SpinBox
var health_control: SpinBox
var distance_control: SpinBox
var shield_control: CheckBox
var fire_control: CheckBox
var move_control: CheckBox
var preset_control: OptionButton
var map_control: OptionButton


func configure(sandbox: OfflineSandbox) -> void:
	lab = sandbox
	add_theme_stylebox_override("panel", DesignTokens.quiet_panel_style())
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", DesignTokens.SPACE_MEDIUM)
	add_child(layout)
	_label(layout, "COMBAT LAB", DesignTokens.TEXT_TITLE_SIZE)
	_button(layout, "Learn to play", lab.start_tutorial)
	var tabs := TabContainer.new()
	tabs.name = "LabTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)
	tabs.get_tab_bar().gui_input.connect(preload("res://src/client/ui/screen_navigation.gd").handle_tab_bar_input.bind(tabs))
	var content := _tab(tabs, "Build")
	var presets := OptionButton.new()
	preset_control = presets
	presets.name = "BuildPreset"
	for preset_name in lab.PRESET_NAMES:
		presets.add_item(preset_name)
	presets.add_item("Custom build")
	presets.set_item_disabled(lab.PRESET_NAMES.size(), true)
	presets.item_selected.connect(lab.load_preset)
	content.add_child(presets)
	search = LineEdit.new()
	search.name = "CardSearch"
	search.placeholder_text = "Search cards…"
	search.custom_minimum_size.y = DesignTokens.CONTROL_HEIGHT
	search.clear_button_enabled = true
	search.text_changed.connect(_refresh_cards)
	content.add_child(search)
	cards = ItemList.new()
	cards.name = "CardResults"
	cards.custom_minimum_size.y = 150.0
	cards.item_selected.connect(_select_card)
	cards.item_activated.connect(func(_index: int) -> void: lab._grant_selected_card())
	content.add_child(cards)
	card_description = _label(content, "", 16)
	card_description.name = "CardDescription"
	var card_actions := HBoxContainer.new()
	layout.add_child(card_actions)
	tabs.tab_changed.connect(func(index: int) -> void: card_actions.visible = index == 0)
	add_button = _button(card_actions, "+ Stack", lab._grant_selected_card)
	remove_button = _button(card_actions, "− Stack", lab.remove_selected_card)
	_button(content, "Clear build", func() -> void: lab.load_preset(0)).theme_type_variation = &"DangerButton"
	content = _tab(tabs, "Targets")
	_label(content, "TARGETS", DesignTokens.TEXT_SECTION_SIZE)
	map_control = OptionButton.new()
	map_control.name = "ArenaSelection"
	for map_id in lab.LAB_MAP_IDS:
		var suffix := " · Solar Current trial" if map_id == &"solar_tide" else ""
		map_control.add_item("%s%s" % [ArenaLayout.display_name(map_id), suffix])
	map_control.item_selected.connect(lab.set_lab_map)
	content.add_child(map_control)
	count_control = _spin(content, "Count", 1.0, 5.0, 1.0, lab.target_count)
	health_control = _spin(content, "Hull HP", 10.0, 600.0, 10.0, lab.target_health)
	distance_control = _spin(content, "Distance", 160.0, 900.0, 20.0, lab.target_distance)
	shield_control = _check(content, "Face player and shield", lab.targets_shielding)
	fire_control = _check(content, "Return fire", lab.targets_firing)
	move_control = _check(content, "Strafe", lab.targets_moving)
	for control in [count_control, health_control, distance_control]:
		control.value_changed.connect(func(_value: float) -> void: _targets_changed())
	for control in [shield_control, fire_control, move_control]:
		control.toggled.connect(func(_value: bool) -> void: _targets_changed())
	_button(content, "Reset encounter · Y", lab._reset_combatants)
	content = _tab(tabs, "Stats")
	_label(content, "BUILD & MEASUREMENTS", DesignTokens.TEXT_SECTION_SIZE)
	build_label = _label(content, "", DesignTokens.TEXT_BODY_SIZE)
	stats_label = _label(content, "", DesignTokens.TEXT_BODY_SIZE)
	_button(content, "Reset measurements", lab.reset_measurements)
	telemetry_label = _label(content, "", 16)
	help_label = _label(content, "", 15)
	_refresh_cards("")
	refresh_build()


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", DesignTokens.SPACE_MEDIUM)
	scroll.add_child(content)
	return content


func focus_search() -> void:
	(find_child("LabTabs", true, false) as TabContainer).current_tab = 0
	search.grab_focus()


func matching_card_ids(query: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var needle := query.strip_edges().to_lower()
	for card_id in lab.catalog.all_ids():
		var card := lab.catalog.get_card(card_id)
		var haystack := "%s %s %s %s" % [card_id, card.display_name, card.description, CardDefinition.Rarity.keys()[card.rarity]]
		if needle.is_empty() or haystack.to_lower().contains(needle):
			result.append(card_id)
	return result


func _refresh_cards(query: String) -> void:
	filtered_ids = matching_card_ids(query)
	cards.clear()
	var current_id := lab.catalog.all_ids()[lab.selected_card_index]
	for card_id in filtered_ids:
		var card := lab.catalog.get_card(card_id)
		var index := cards.add_item("%s · ×%d" % [card.display_name, int(lab.build.get(card_id, 0))])
		cards.set_item_custom_fg_color(index, card.rarity_color())
		if card_id == current_id:
			cards.select(index)
	add_button.disabled = filtered_ids.is_empty()
	remove_button.disabled = filtered_ids.is_empty()
	if filtered_ids.is_empty():
		card_description.text = "No matching cards. Clear or change the search."
	elif not current_id in filtered_ids:
		cards.select(0)
		_select_card(0)
	elif lab.card_label != null:
		lab._update_card_label()


func _select_card(index: int) -> void:
	if index < 0 or index >= filtered_ids.size():
		return
	lab.selected_card_index = lab.catalog.all_ids().find(filtered_ids[index])
	lab._update_card_label()


func refresh_build() -> void:
	var selected_preset := lab.PRESET_BUILDS.find(lab.build)
	preset_control.select(selected_preset if selected_preset >= 0 else lab.PRESET_NAMES.size())
	var names := PackedStringArray()
	for card_id in lab.catalog.all_ids():
		if int(lab.build.get(card_id, 0)) > 0:
			names.append("%s ×%d" % [lab.catalog.get_card(card_id).display_name, lab.build[card_id]])
	build_label.text = "BUILD · " + (", ".join(names) if not names.is_empty() else "Base ship")
	var stats := lab.derived_stats
	var stat_lines := PackedStringArray(["DERIVED STATS"])
	for properties in [[&"max_health", &"max_speed", &"acceleration"], [&"projectile_damage", &"projectile_count", &"fire_rate"], [&"magazine_size", &"reload_duration"], [&"shield_capacity", &"shield_regeneration", &"shield_arc_degrees"], [&"pierce_count", &"ricochet_count"], [&"mine_capacity", &"missile_capacity", &"cloak_capacity"]]:
		var parts := PackedStringArray()
		for property in properties:
			parts.append("%s %s" % [StatMetadata.label(property, true), StatMetadata.format_value(property, float(stats.get(property)))])
		stat_lines.append(" · ".join(parts))
	stat_lines.append("Beam weapon" if stats.beam_weapon else "Projectile weapon")
	stats_label.text = "\n".join(stat_lines)
	_refresh_cards(search.text)


func refresh_telemetry() -> void:
	if telemetry_label == null:
		return
	telemetry_label.text = "MEASURED · last source: %s\nDPS uses active time since first shot or hit.\nPauses are excluded; misses and reloads count.\nDamage is HP removed after shields and overkill.\nTargets stay down until Reset encounter." % lab.last_damage_source


func _targets_changed() -> void:
	lab.set_target_settings(roundi(count_control.value), health_control.value, distance_control.value, shield_control.button_pressed, fire_control.button_pressed, move_control.button_pressed)


func sync_target_controls() -> void:
	count_control.set_value_no_signal(lab.target_count)
	health_control.set_value_no_signal(lab.target_health)
	distance_control.set_value_no_signal(lab.target_distance)
	shield_control.set_pressed_no_signal(lab.targets_shielding)
	fire_control.set_pressed_no_signal(lab.targets_firing)
	move_control.set_pressed_no_signal(lab.targets_moving)


func _label(parent: Node, value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.theme_type_variation = &"SecondaryButton"
	button.custom_minimum_size.y = DesignTokens.CONTROL_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _spin(parent: Node, title: String, minimum: float, maximum: float, step_value: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, title, 16)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = value
	var handle_controller := func(event: InputEvent) -> void:
		if event is InputEventJoypadButton and event.pressed:
			if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
				spin.value += spin.step * (-1.0 if event.is_action_pressed("ui_left") else 1.0)
				spin.accept_event()
	spin.gui_input.connect(handle_controller)
	spin.get_line_edit().gui_input.connect(handle_controller)
	row.add_child(spin)
	return spin


func _check(parent: Node, title: String, value: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = title
	check.custom_minimum_size.y = DesignTokens.CONTROL_HEIGHT
	check.button_pressed = value
	parent.add_child(check)
	return check
