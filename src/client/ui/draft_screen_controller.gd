extends Node

## Owns draft controls, offer state, confirmation and rejection recovery.

const CardHoverButtonScript = preload("res://src/client/ui/card_hover_button.gd")
const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const CardDetailsText = preload("res://src/client/ui/card_details_text.gd")

signal inspection_requested(button: CardHoverButton)
signal presentation_changed
var bridge: NetworkBridge
var audio_director: AudioDirector
var card_catalog: CardCatalog
var interface_theme: Theme
var _canvas: CanvasLayer
var _context: Callable


var draft_panel: PanelContainer
var draft_title: Label
var draft_cards: HBoxContainer
var draft_buttons: Array[Button] = []
var draft_rarity_labels: Array[Label] = []
var draft_bye_label: Label
var draft_confirmation_row: HBoxContainer
var draft_confirmation_label: Label
var draft_confirm_button: Button
var draft_change_button: Button
var active_offer_token: String = ""
var active_offer_deadline: int = -1
var pending_draft_index: int = -1
var inspected_index: int = 0
var inspect_button: Button
var comparison_hint: Label
var _draft_layout_pending: bool = false


func configure(network: NetworkBridge, audio: AudioDirector, catalog: CardCatalog, theme: Theme, canvas: CanvasLayer, context: Callable) -> void:
	bridge = network
	audio_director = audio
	card_catalog = catalog
	interface_theme = theme
	_canvas = canvas
	_context = context


func create_ui() -> void:
	if is_instance_valid(draft_panel):
		return
	draft_panel = PanelContainer.new()
	draft_panel.name = "DraftScreen"
	draft_panel.set_anchors_preset(Control.PRESET_CENTER)
	draft_panel.position = Vector2(-600.0, -280.0)
	draft_panel.custom_minimum_size = Vector2(1200.0, 560.0)
	draft_panel.theme = interface_theme
	draft_panel.add_theme_stylebox_override("panel", _panel_style(DesignTokensScript.BRAND_MAGENTA, 0.98))
	draft_panel.visible = false
	draft_panel.resized.connect(_queue_draft_layout)
	draft_panel.minimum_size_changed.connect(_queue_draft_layout)
	get_viewport().size_changed.connect(_queue_draft_layout)
	_canvas.add_child(draft_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	draft_panel.add_child(content)
	draft_title = Label.new()
	draft_title.text = "CHOOSE YOUR UPGRADE"
	draft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_title.add_theme_font_size_override("font_size", 34)
	draft_title.add_theme_color_override("font_color", Color("d39cff"))
	content.add_child(draft_title)
	comparison_hint = Label.new()
	comparison_hint.text = "YOUR BUILD · BEFORE → AFTER   |   Amber values show drawbacks"
	comparison_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	comparison_hint.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
	content.add_child(comparison_hint)
	var cards := HBoxContainer.new()
	draft_cards = cards
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	content.add_child(cards)
	for index in GameConstants.CARD_OFFER_SIZE:
		var button := CardHoverButtonScript.new()
		button.custom_minimum_size = Vector2(224.0, 700.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.add_theme_font_size_override("font_size", 1)
		button.add_theme_color_override("font_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)
		button.pressed.connect(select_draft_card.bind(index))
		button.inspection_requested.connect(inspection_requested.emit)
		button.focus_entered.connect(_set_inspected_card.bind(index))
		button.mouse_entered.connect(_set_inspected_card.bind(index))
		cards.add_child(button)
		draft_buttons.append(button)
		_create_draft_card_content(button, index)
		var rarity_label := Label.new()
		rarity_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		rarity_label.offset_left = 10.0
		rarity_label.offset_top = -72.0
		rarity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rarity_label.offset_right = -10.0
		rarity_label.offset_bottom = -10.0
		rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rarity_label.add_theme_font_size_override("font_size", 14)
		rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(rarity_label)
		draft_rarity_labels.append(rarity_label)
	inspect_button = Button.new()
	inspect_button.name = "InspectDraftCard"
	inspect_button.theme_type_variation = &"QuietButton"
	inspect_button.custom_minimum_size.y = 48.0
	inspect_button.pressed.connect(func() -> void: (draft_buttons[inspected_index] as CardHoverButton).request_inspection())
	content.add_child(inspect_button)
	draft_bye_label = Label.new()
	draft_bye_label.text = "You keep the build that won the round.\nEveryone else gets an upgrade this time.\n\nHold the lead."
	draft_bye_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_bye_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	draft_bye_label.add_theme_font_size_override("font_size", 24)
	draft_bye_label.add_theme_color_override("font_color", Color("fff36a"))
	draft_bye_label.visible = false
	content.add_child(draft_bye_label)
	draft_confirmation_row = HBoxContainer.new()
	draft_confirmation_row.alignment = BoxContainer.ALIGNMENT_CENTER
	draft_confirmation_row.add_theme_constant_override("separation", 12)
	draft_confirmation_row.visible = false
	content.add_child(draft_confirmation_row)
	draft_confirmation_label = Label.new()
	draft_confirmation_label.add_theme_font_size_override("font_size", 18)
	draft_confirmation_label.add_theme_color_override("font_color", Color("fff36a"))
	draft_confirmation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Give wrapping a valid width before the initially hidden row is laid out.
	draft_confirmation_label.custom_minimum_size.x = 480.0
	draft_confirmation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draft_confirmation_row.add_child(draft_confirmation_label)
	draft_change_button = Button.new()
	draft_change_button.text = "CHOOSE ANOTHER"
	draft_change_button.theme_type_variation = &"QuietButton"
	draft_change_button.custom_minimum_size = Vector2(180.0, 48.0)
	draft_change_button.pressed.connect(cancel_draft_confirmation)
	draft_confirmation_row.add_child(draft_change_button)
	draft_confirm_button = Button.new()
	draft_confirm_button.text = "CONFIRM PICK"
	draft_confirm_button.theme_type_variation = &"PrimaryButton"
	draft_confirm_button.custom_minimum_size = Vector2(180.0, 48.0)
	draft_confirm_button.pressed.connect(_confirm_draft_card)
	draft_confirmation_row.add_child(draft_confirm_button)


func _create_draft_card_content(button: Button, index: int) -> void:
	var margin := MarginContainer.new()
	margin.name = "CardContent"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 82)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Details"
	column.add_theme_constant_override("separation", 7)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var choice_key := Label.new()
	choice_key.name = "ChoiceKey"
	choice_key.text = "CHOICE %d" % (index + 1)
	choice_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_key.add_theme_font_size_override("font_size", 13)
	choice_key.add_theme_color_override("font_color", DesignTokensScript.FOCUS)
	column.add_child(choice_key)
	var card_name := Label.new()
	card_name.name = "CardName"
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_name.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_SECTION_SIZE)
	card_name.custom_minimum_size.y = 76.0
	card_name.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
	column.add_child(card_name)
	var category := Label.new()
	category.name = "Category"
	category.custom_minimum_size.y = 60.0
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category.add_theme_font_size_override("font_size", 13)
	column.add_child(category)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.custom_minimum_size.y = 2.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var description := Label.new()
	description.name = "Description"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	description.custom_minimum_size.y = 54.0
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
	column.add_child(description)
	var stack := Label.new()
	stack.name = "Stack"
	stack.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_theme_font_size_override("font_size", 15)
	stack.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
	column.add_child(stack)
	var state := Label.new()
	state.name = "State"
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 14)
	state.add_theme_color_override("font_color", DesignTokensScript.SUCCESS)
	column.add_child(state)

func show_draft_offer(payload: Dictionary) -> void:
	draft_panel.custom_minimum_size = Vector2(1200.0, 560.0)
	draft_title.add_theme_font_size_override("font_size", 34)
	draft_title.text = "CHOOSE YOUR UPGRADE"
	draft_cards.show()
	inspect_button.show()
	comparison_hint.show()
	active_offer_token = String(payload.get("offer_token", ""))
	active_offer_deadline = int(payload.get("deadline_tick", -1))
	pending_draft_index = -1
	draft_confirmation_row.visible = false
	draft_bye_label.visible = false
	var card_ids := payload.get("card_ids", []) as Array
	for index in draft_buttons.size():
		var button := draft_buttons[index]
		button.visible = index < card_ids.size()
		draft_rarity_labels[index].visible = button.visible
		button.disabled = false
		button.set_meta("card_id", StringName(card_ids[index]) if index < card_ids.size() else &"")
		if index >= card_ids.size():
			continue
		var card := card_catalog.get_card(StringName(card_ids[index]))
		var current_stacks := _local_build_stack(card.card_id) if card != null else 0
		button.text = "%d\n\n%s\n%s\n\n%s\n\nSTACK %d → %d" % [
			index + 1,
			card.display_name,
			card.category_name().to_upper(),
			card.description,
			current_stacks,
			current_stacks + 1,
		] if card != null else String(card_ids[index])
		if card != null:
			var rarity_color := card.rarity_color()
			var category_color := _draft_category_color(card.category)
			(button.get_node("CardContent/Details/CardName") as Label).text = card.display_name.to_upper()
			var category_label := button.get_node("CardContent/Details/Category") as Label
			category_label.text = card.category_name().to_upper()
			category_label.add_theme_color_override("font_color", category_color)
			(button.get_node("CardContent/Details/Rule") as ColorRect).color = Color(rarity_color, 0.68)
			(button.get_node("CardContent/Details/Description") as Label).text = card.description
			(button.get_node("CardContent/Details/Stack") as Label).text = "STACKS  %d → %d" % [current_stacks, current_stacks + 1]
			(button.get_node("CardContent/Details/State") as Label).text = ""
			button.set_meta("rarity_color", rarity_color)
			button.add_theme_stylebox_override("normal", _draft_card_style(rarity_color, false))
			button.add_theme_stylebox_override("hover", _draft_card_style(rarity_color.lightened(0.12), true))
			button.add_theme_stylebox_override("pressed", _draft_card_style(rarity_color.lightened(0.22), true))
			button.add_theme_stylebox_override("focus", _draft_card_focus_style(rarity_color))
			button.add_theme_stylebox_override("disabled", _draft_card_style(rarity_color.darkened(0.25), false))
			var rarity_label := draft_rarity_labels[index]
			rarity_label.text = "%s  ·  %s TIER DROP" % [card.rarity_name().to_upper(), card.rarity_drop_chance_text()]
			rarity_label.add_theme_color_override("font_color", rarity_color.lightened(0.12))
			button.configure(card, current_stacks + 1, CardDetailsText.tooltip(card, current_stacks + 1, "STACKS AFTER PICK"), "AFTER PICK")
			button.configure_build_comparison(_local_build(), card_catalog)
			if not button.output_warning.is_empty():
				button.text += "\n" + button.output_warning
			if button.no_effective_benefit:
				(button.get_node("CardContent/Details/Stack") as Label).text += "\nNO BENEFIT"
				button.text += "\nNO EFFECTIVE BENEFIT"
			elif button.has_limited_effect():
				(button.get_node("CardContent/Details/Stack") as Label).text += "\nAT LIMIT"
				button.text += "\nAT LIMIT · VIEW DETAILS"
	draft_panel.visible = true
	_queue_draft_layout()
	for button in draft_buttons:
		if button.visible and not button.disabled:
			button.grab_focus()
			break
	presentation_changed.emit()


func _set_inspected_card(index: int) -> void:
	inspected_index = index
	if inspect_button == null:
		return
	var card := (draft_buttons[index] as CardHoverButton).card_definition
	inspect_button.text = "Inspect %s · I / Y" % card.display_name if card != null else "Inspect card · I / Y"


func select_draft_card(index: int) -> void:
	if index < 0 or index >= draft_buttons.size():
		return
	var button := draft_buttons[index]
	if not button.visible or button.disabled:
		return
	var card_id := button.get_meta("card_id", &"") as StringName
	if card_id.is_empty():
		return
	pending_draft_index = index
	var card := card_catalog.get_card(card_id)
	_set_inspected_card(index)
	var card_name := card.display_name.to_upper() if card != null else String(card_id).to_upper()
	draft_confirmation_label.text = "LOCK IN %s?" % card_name
	if not button.output_warning.is_empty():
		draft_confirmation_label.text += "  " + button.output_warning
	if button.no_effective_benefit:
		draft_confirmation_label.text += "  NO EFFECTIVE BENEFIT · CHECK DRAWBACKS"
	elif button.has_limited_effect():
		draft_confirmation_label.text += "  SOME STATS ARE AT THEIR LIMIT"
	draft_confirmation_row.visible = true
	for button_index in draft_buttons.size():
		var draft_button := draft_buttons[button_index]
		if not draft_button.visible:
			continue
		var rarity_color: Color = draft_button.get_meta("rarity_color", Color("42e8ff"))
		draft_button.add_theme_stylebox_override("normal", _draft_card_style(rarity_color, button_index == index))
		var state := draft_button.get_node("CardContent/Details/State") as Label
		state.text = "PENDING" if button_index == index else ""
		state.add_theme_color_override("font_color", DesignTokensScript.WARNING)
	draft_confirm_button.grab_focus()


func _confirm_draft_card() -> void:
	if pending_draft_index < 0 or pending_draft_index >= draft_buttons.size():
		return
	var button := draft_buttons[pending_draft_index]
	if not button.visible or button.disabled or active_offer_token.is_empty():
		return
	var card_id := button.get_meta("card_id", &"") as StringName
	if card_id.is_empty():
		return
	bridge.send_card_selection(active_offer_token, card_id)
	audio_director.play_sfx(&"card_lock", "%s:%s" % [active_offer_token, card_id])
	for draft_button in draft_buttons:
		draft_button.disabled = true
	button.text += "\n\nSELECTED"
	(button.get_node("CardContent/Details/State") as Label).text = "SELECTED  ✓"
	(button.get_node("CardContent/Details/State") as Label).add_theme_color_override("font_color", DesignTokensScript.SUCCESS)
	var selected_color: Color = button.get_meta("rarity_color", Color("42e8ff"))
	button.add_theme_stylebox_override("disabled", _draft_card_style(selected_color, true))
	pending_draft_index = -1
	draft_confirmation_row.visible = false


func cancel_draft_confirmation() -> void:
	var previous_index := pending_draft_index
	pending_draft_index = -1
	draft_confirmation_row.visible = false
	for draft_button in draft_buttons:
		if not draft_button.visible or draft_button.disabled:
			continue
		var rarity_color: Color = draft_button.get_meta("rarity_color", Color("42e8ff"))
		draft_button.add_theme_stylebox_override("normal", _draft_card_style(rarity_color, false))
		(draft_button.get_node("CardContent/Details/State") as Label).text = ""
	if previous_index >= 0 and previous_index < draft_buttons.size():
		var previous_button := draft_buttons[previous_index]
		if previous_button.visible and not previous_button.disabled:
			previous_button.grab_focus()


func _show_draft_bye(deadline_tick: int) -> void:
	draft_panel.custom_minimum_size = Vector2(820.0, 0.0)
	draft_title.add_theme_font_size_override("font_size", 28)
	draft_title.text = "ROUND WINNER — SKIPS THIS DRAFT"
	draft_cards.hide()
	inspect_button.hide()
	comparison_hint.hide()
	active_offer_token = ""
	active_offer_deadline = deadline_tick
	pending_draft_index = -1
	draft_confirmation_row.visible = false
	for index in draft_buttons.size():
		draft_buttons[index].visible = false
		draft_rarity_labels[index].visible = false
	draft_bye_label.visible = true
	draft_panel.visible = true
	# Let the containers drop the previous offer's minimum before shrinking.
	_queue_draft_layout()


func _queue_draft_layout() -> void:
	if _draft_layout_pending:
		return
	_draft_layout_pending = true
	_fit_draft_panel.call_deferred()


func _fit_draft_panel() -> void:
	_draft_layout_pending = false
	if not is_instance_valid(draft_panel):
		return
	# Containers grow for transient wrapped-label minima but do not shrink again.
	# Refit after each minimum change, including hiding/cancelling confirmation.
	var minimum := draft_panel.get_combined_minimum_size()
	if not draft_panel.size.is_equal_approx(minimum):
		draft_panel.size = minimum
	_center_draft_panel()


func _center_draft_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var available := (viewport_size - Vector2(64.0, 64.0)).max(Vector2.ONE)
	var fit := minf(1.0, minf(available.x / maxf(draft_panel.size.x, 1.0), available.y / maxf(draft_panel.size.y, 1.0)))
	draft_panel.scale = Vector2.ONE * fit
	draft_panel.position = (viewport_size - draft_panel.size * fit) * 0.5


func _draft_category_color(category: int) -> Color:
	match category:
		CardDefinition.Category.SHIP:
			return Color("38d9ff")
		CardDefinition.Category.SHIELD:
			return Color("ae7cff")
		_:
			return Color("ff4fd8")


func _draft_card_style(color: Color, emphasized: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(DesignTokensScript.SURFACE_RAISED if emphasized else DesignTokensScript.SURFACE, 0.98)
	style.border_color = Color(color, 0.95 if emphasized else 0.62)
	style.set_border_width_all(3 if emphasized else 2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


func _draft_card_focus_style(rarity_color: Color) -> StyleBoxFlat:
	var style := _draft_card_style(rarity_color, true)
	style.border_color = DesignTokensScript.FOCUS
	style.set_border_width_all(4)
	style.shadow_color = Color(DesignTokensScript.FOCUS, 0.34)
	style.shadow_size = 14
	style.draw_center = false
	return style


func _local_build_stack(card_id: StringName) -> int:
	return int(_local_build().get(card_id, 0))


func _local_build() -> Dictionary:
	return (_context.call() as Dictionary).get("build", {}) as Dictionary


func _panel_style(accent: Color, opacity: float) -> StyleBoxFlat:
	return DesignTokensScript.panel_style(accent, opacity)


func clear_offer() -> void:
	active_offer_token = ""
	active_offer_deadline = -1
	pending_draft_index = -1
	draft_confirmation_row.hide()
	draft_panel.hide()


func recover_rejected_offer() -> void:
	if draft_panel.visible and not active_offer_token.is_empty():
		for draft_button in draft_buttons:
			if draft_button.visible:
				draft_button.disabled = false
				draft_button.text = draft_button.text.trim_suffix("\n\nSELECTED")
				var rarity_color: Color = draft_button.get_meta("rarity_color", Color("42e8ff"))
				draft_button.add_theme_stylebox_override("normal", _draft_card_style(rarity_color, false))
				(draft_button.get_node("CardContent/Details/State") as Label).text = ""
		pending_draft_index = -1
		draft_confirmation_row.visible = false


func update_countdown(deadline: int, seconds_left: float) -> void:
	if bool((_context.call() as Dictionary).get("bye", false)):
		if not draft_bye_label.visible or not draft_panel.visible:
			_show_draft_bye(deadline)
		draft_title.text = "ROUND WINNER — SKIPS THIS DRAFT · %.1fs" % seconds_left
	elif not draft_bye_label.visible:
		draft_title.text = "CHOOSE 1 OF 5 UPGRADES · %.1fs · PICK, THEN CONFIRM" % seconds_left
