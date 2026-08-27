class_name CardHoverButton
extends Button

var card_definition: CardDefinition
var stack_count: int = 1
var footer_context: String = "CURRENT BUILD"


func configure(card: CardDefinition, stacks: int, accessible_text: String, context: String = "CURRENT BUILD") -> void:
	card_definition = card
	stack_count = maxi(stacks, 1)
	footer_context = context
	tooltip_text = accessible_text


func _make_custom_tooltip(_for_text: String) -> Object:
	if card_definition == null:
		return null
	var rarity_color := card_definition.rarity_color()
	var category_color := _category_color(card_definition.category)
	var card := PanelContainer.new()
	card.name = "CardPreview"
	card.custom_minimum_size = Vector2(390.0, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta("card_id", card_definition.card_id)
	card.set_meta("rarity", card_definition.rarity)
	card.add_theme_stylebox_override("panel", _card_style(rarity_color))

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	card.add_child(content)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 12)
	content.add_child(identity)
	var crest := PanelContainer.new()
	crest.custom_minimum_size = Vector2(54.0, 54.0)
	crest.add_theme_stylebox_override("panel", _crest_style(category_color))
	identity.add_child(crest)
	var crest_label := Label.new()
	crest_label.text = _category_glyph(card_definition.category)
	crest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crest_label.add_theme_font_size_override("font_size", 28)
	crest_label.add_theme_color_override("font_color", category_color.lightened(0.2))
	crest.add_child(crest_label)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 2)
	identity.add_child(title_column)
	var title := Label.new()
	title.text = card_definition.display_name.to_upper()
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("f8fcff"))
	title_column.add_child(title)
	var tier := Label.new()
	tier.text = "%s  •  %s  •  %s TIER DROP" % [
		card_definition.rarity_name().to_upper(),
		card_definition.category_name().to_upper(),
		card_definition.rarity_drop_chance_text(),
	]
	tier.add_theme_font_size_override("font_size", 13)
	tier.add_theme_color_override("font_color", rarity_color.lightened(0.18))
	title_column.add_child(tier)

	var stack_badge := Label.new()
	stack_badge.text = "×%d" % stack_count
	stack_badge.custom_minimum_size = Vector2(46.0, 34.0)
	stack_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack_badge.add_theme_font_size_override("font_size", 18)
	stack_badge.add_theme_color_override("font_color", rarity_color.lightened(0.25))
	stack_badge.add_theme_stylebox_override("normal", _badge_style(rarity_color))
	identity.add_child(stack_badge)

	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 2.0
	rule.color = Color(rarity_color, 0.65)
	content.add_child(rule)

	var description := Label.new()
	description.text = card_definition.description
	description.custom_minimum_size.x = 344.0
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override("font_color", Color("d9e6f5"))
	content.add_child(description)

	var effects_heading := Label.new()
	effects_heading.text = "STACKED CARD EFFECTS"
	effects_heading.add_theme_font_size_override("font_size", 12)
	effects_heading.add_theme_color_override("font_color", Color("8ba1c7"))
	content.add_child(effects_heading)
	for effect in _effect_rows():
		content.add_child(_effect_panel(effect, category_color))

	var footer := Label.new()
	footer.text = "%s  •  %d %s" % [footer_context, stack_count, "COPY" if stack_count == 1 else "COPIES"]
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(rarity_color, 0.85))
	content.add_child(footer)
	return card


func _effect_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var names := card_definition.additive_modifiers.keys()
	names.sort()
	for property_value in names:
		var per_stack := float(card_definition.additive_modifiers[property_value])
		rows.append({
			"name": _stat_name(String(property_value)),
			"each": "%+.2f each" % per_stack,
			"total": "%+.2f total" % (per_stack * stack_count),
		})
	names = card_definition.multiplicative_modifiers.keys()
	names.sort()
	for property_value in names:
		var per_stack := float(card_definition.multiplicative_modifiers[property_value])
		rows.append({
			"name": _stat_name(String(property_value)),
			"each": "×%.2f each" % per_stack,
			"total": "×%.2f total" % pow(per_stack, stack_count),
		})
	names = card_definition.integer_modifiers.keys()
	names.sort()
	for property_value in names:
		var per_stack := int(card_definition.integer_modifiers[property_value])
		rows.append({
			"name": _stat_name(String(property_value)),
			"each": "%+d each" % per_stack,
			"total": "%+d total" % (per_stack * stack_count),
		})
	if card_definition.special_behavior_id == &"beam_weapon":
		rows.append({"name": "Weapon Form", "each": "Pulse beam", "total": "TRANSFORMED"})
	elif card_definition.special_behavior_id == &"auto_repair":
		rows.append({"name": "Special", "each": "Hull repair", "total": "ENABLED"})
	elif card_definition.special_behavior_id == &"afterburner":
		rows.append({"name": "Special", "each": "Forward burst", "total": "SHIFT / BINDING"})
	if rows.is_empty():
		rows.append({"name": "Special", "each": "Unique behavior", "total": "ACTIVE"})
	return rows


func _effect_panel(effect: Dictionary, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _effect_style(accent))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var stat := Label.new()
	stat.text = String(effect["name"])
	stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat.add_theme_font_size_override("font_size", 14)
	stat.add_theme_color_override("font_color", Color("f0f7ff"))
	row.add_child(stat)
	var each := Label.new()
	each.text = String(effect["each"])
	each.custom_minimum_size.x = 92.0
	each.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	each.add_theme_font_size_override("font_size", 13)
	each.add_theme_color_override("font_color", Color("aebbd4"))
	row.add_child(each)
	var total := Label.new()
	total.text = String(effect["total"])
	total.custom_minimum_size.x = 92.0
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_theme_font_size_override("font_size", 13)
	total.add_theme_color_override("font_color", accent.lightened(0.18))
	row.add_child(total)
	return panel


func _card_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("071024f7")
	style.border_color = Color(color, 0.96)
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(color, 0.28)
	style.shadow_size = 16
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 16.0
	return style


func _crest_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.72), 0.9)
	style.border_color = Color(color, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	return style


func _badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.72), 0.85)
	style.border_color = Color(color, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	return style


func _effect_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.86), 0.7)
	style.border_color = Color(color, 0.28)
	style.border_width_left = 3
	style.set_corner_radius_all(6)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _category_color(category: int) -> Color:
	match category:
		CardDefinition.Category.SHIP:
			return Color("38d9ff")
		CardDefinition.Category.SHIELD:
			return Color("ae7cff")
		_:
			return Color("ff4fd8")


func _category_glyph(category: int) -> String:
	match category:
		CardDefinition.Category.SHIP:
			return "◇"
		CardDefinition.Category.SHIELD:
			return "⬡"
		_:
			return "✦"


func _stat_name(property_name: String) -> String:
	return property_name.replace("_", " ").capitalize()
