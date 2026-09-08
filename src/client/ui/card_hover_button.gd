class_name CardHoverButton
extends Button

signal inspection_requested(button: CardHoverButton)

const Metadata = preload("res://src/shared/models/stat_metadata.gd")
const CardDetailsText = preload("res://src/client/ui/card_details_text.gd")

const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const IdentityScript = preload("res://src/client/ui/card_identity.gd")
const MechanicIconScript = preload("res://src/client/ui/card_mechanic_icon.gd")

var card_definition: CardDefinition
var stack_count: int = 1
var footer_context: String = "CURRENT BUILD"
var comparison_rows: Array[StatChange] = []
var no_effective_benefit: bool = false
var effective_summary: Dictionary = {}
var output_warning: String = ""
var output_comparison: Array[Dictionary] = []


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_I) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y):
		request_inspection()
		accept_event()


func request_inspection() -> void:
	if card_definition != null:
		inspection_requested.emit(self)


func configure(card: CardDefinition, stacks: int, accessible_text: String, context: String = "CURRENT BUILD") -> void:
	card_definition = card
	stack_count = maxi(stacks, 1)
	footer_context = context
	tooltip_text = accessible_text
	comparison_rows.clear()
	effective_summary.clear()
	no_effective_benefit = false
	output_warning = ""
	output_comparison.clear()


func configure_build_comparison(build: Dictionary, catalog: CardCatalog) -> void:
	comparison_rows = StatSystem.compare_pick_typed(build, card_definition, catalog)
	no_effective_benefit = not StatSystem.has_effective_benefit(build, card_definition, catalog)
	tooltip_text += "\n\nACTUAL BUILD: BEFORE → AFTER"
	if no_effective_benefit:
		tooltip_text += "\nNO EFFECTIVE BENEFIT · Existing drawbacks still apply."
	for row in comparison_rows:
		tooltip_text += "\n%s: %s → %s%s" % [_stat_name(row.property), _stat_value(row.before, row.property), _stat_value(row.after, row.property), " (AT LIMIT)" if row.limited else ""]
	effective_summary = IdentityScript.summarize_typed(build, card_definition, catalog, comparison_rows)
	_configure_output_comparison(build, catalog)
	_update_draft_identity()


func _configure_output_comparison(build: Dictionary, catalog: CardCatalog) -> void:
	output_warning = ""
	output_comparison.clear()
	var next_build := build.duplicate()
	next_build[card_definition.card_id] = int(next_build.get(card_definition.card_id, 0)) + 1
	var before := StatSystem.weapon_output(StatSystem.derive(build, catalog))
	var after := StatSystem.weapon_output(StatSystem.derive(next_build, catalog))
	# Prefer the sustained warning when both fall, but retain both in details.
	for metric in ["sustained", "burst"]:
		if float(after[metric]) >= float(before[metric]) or is_equal_approx(float(after[metric]), float(before[metric])):
			continue
		var name := "Potential sustained DPS" if metric == "sustained" else "Potential burst DPS"
		var loss := 100.0 * (1.0 - float(after[metric]) / float(before[metric]))
		var change := "-%.1f%%" % loss
		if output_warning.is_empty():
			output_warning = "%s DPS %s" % ["SUSTAINED" if metric == "sustained" else "BURST", change]
		output_comparison.append({"name": name, "each": "%.1f → %.1f" % [before[metric], after[metric]], "total": change})
		tooltip_text += "\n%s: %.1f → %.1f (%s)" % [name, before[metric], after[metric], change]
	if not output_comparison.is_empty():
		tooltip_text += "\nPotential DPS assumes every projectile hits one target. Sustained includes reloads; estimates exclude accuracy, range and multi-target hits."


func _update_draft_identity() -> void:
	var details := get_node_or_null("CardContent/Details") as VBoxContainer
	if details == null:
		return
	var icon := details.get_node_or_null("MechanicIcon") as Control
	if icon == null:
		icon = MechanicIconScript.new()
		icon.name = "MechanicIcon"
		details.add_child(icon)
		details.move_child(icon, 1)
	icon.family = IdentityScript.family(card_definition)
	icon.accent = _category_color(card_definition.category)
	icon.queue_redraw()
	var category := details.get_node("Category") as Label
	category.text = IdentityScript.role(card_definition).to_upper()
	category.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var description := details.get_node("Description") as Label
	description.visible = true
	description.text = IdentityScript.summary(card_definition)
	var summary := details.get_node_or_null("EffectiveSummary") as VBoxContainer
	if summary == null:
		summary = VBoxContainer.new()
		summary.name = "EffectiveSummary"
		summary.add_theme_constant_override("separation", 5)
		summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
		summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_child(summary)
		details.move_child(summary, description.get_index() + 1)
	for child in summary.get_children():
		summary.remove_child(child)
		child.queue_free()
	var headline_rows: Array = effective_summary.rows.duplicate()
	if headline_rows.size() > 2:
		var second: Dictionary = headline_rows[1]
		for item in headline_rows.slice(1):
			if item.kind == &"drawback":
				second = item
				break
		headline_rows = [headline_rows[0], second]
	for row in headline_rows:
		var group := VBoxContainer.new()
		group.custom_minimum_size.y = 70.0
		group.add_theme_constant_override("separation", 2)
		summary.add_child(group)
		var change: StatChange = null
		for candidate in comparison_rows:
			if candidate.property == row.property:
				change = candidate
				break
		var heading := Label.new()
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
		heading.text = Metadata.label(change.property, true) if change != null else "New mechanic"
		group.add_child(heading)
		var after := Label.new()
		if change != null:
			var unit: String = Metadata.descriptor(change.property).unit
			var before := _stat_value(change.before, change.property).trim_suffix(unit).strip_edges() if not unit.is_empty() else _stat_value(change.before, change.property)
			after.text = before + " → " + _keep_unit_together(_stat_value(change.after, change.property)) + (" *" if change.limited else "")
		else:
			after.text = String(row.text).trim_prefix("Unlock: ")
		after.autowrap_mode = TextServer.AUTOWRAP_WORD
		after.add_theme_color_override("font_color", DesignTokensScript.WARNING if row.kind == &"drawback" else DesignTokensScript.TEXT_PRIMARY)
		group.add_child(after)
	var note := Label.new()
	var note_parts := PackedStringArray()
	if not output_warning.is_empty():
		note_parts.append(output_warning.replace("SUSTAINED ", "").replace("BURST ", ""))
	var omitted: int = int(effective_summary.get("omitted", 0)) + effective_summary.rows.size() - headline_rows.size()
	# Keep the warning in the existing note slot so the selection/footer fit.
	# Full effects remain available through the always-visible Inspect control.
	if omitted > 0 and output_warning.is_empty():
		note_parts.append("+%d IN DETAILS" % omitted)
	note.text = "\n".join(note_parts)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", DesignTokensScript.WARNING)
	note.visible = not note.text.is_empty()
	summary.add_child(note)
	tooltip_text += "\nROLE: %s" % IdentityScript.role(card_definition)


func _keep_unit_together(value: String) -> String:
	return value.replace(" ", "\u00a0").replace("/", "\u2060/\u2060")


func has_limited_effect() -> bool:
	for row in comparison_rows:
		if row.limited:
			return true
	return false


func _stat_value(value: float, property: StringName = &"") -> String:
	return Metadata.format_value(property, value)


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
	var crest_icon := MechanicIconScript.new()
	crest_icon.family = IdentityScript.family(card_definition)
	crest_icon.accent = category_color.lightened(0.2)
	crest.add_child(crest_icon)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 2)
	identity.add_child(title_column)
	var title := Label.new()
	title.text = card_definition.display_name.to_upper()
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
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
	var role_label := Label.new()
	role_label.text = IdentityScript.role(card_definition).to_upper()
	role_label.add_theme_font_size_override("font_size", 13)
	role_label.add_theme_color_override("font_color", category_color)
	title_column.add_child(role_label)

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
	description.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
	content.add_child(description)

	var effects_heading := Label.new()
	effects_heading.text = "ACTUAL BUILD: BEFORE → AFTER" if not comparison_rows.is_empty() else "STACKED CARD EFFECTS"
	effects_heading.add_theme_font_size_override("font_size", 12)
	effects_heading.add_theme_color_override("font_color", DesignTokensScript.TEXT_MUTED)
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
	rows.append_array(output_comparison)
	if not comparison_rows.is_empty():
		for comparison in comparison_rows:
			rows.append({
				"name": _stat_name(comparison.property),
				"each": "%s → %s" % [_stat_value(comparison.before, comparison.property), _stat_value(comparison.after, comparison.property)],
				"total": "AT LIMIT" if comparison.limited else ("UNCHANGED" if comparison.unchanged else Metadata.format_value(comparison.property, float(comparison.after) - float(comparison.before), true)),
			})
	if comparison_rows.is_empty():
		rows.append_array(CardDetailsText.modifier_rows(card_definition, stack_count))
	if card_definition.special_behavior_id == &"beam_weapon":
		rows.append({"name": "Weapon Form", "each": "Pulse beam", "total": "TRANSFORMED"})
	elif card_definition.special_behavior_id == &"auto_repair":
		rows.append({"name": "Special", "each": "Hull repair", "total": "ENABLED"})
	elif card_definition.special_behavior_id == &"afterburner":
		rows.append({"name": "Special", "each": "Forward burst", "total": "SHIFT / BINDING"})
	elif card_definition.special_behavior_id == &"mine_layer":
		rows.append({"name": "Special", "each": "Drop mine", "total": "SHIFT / BINDING"})
	elif card_definition.special_behavior_id == &"missile_launcher":
		rows.append({"name": "Special", "each": "Launch seeker", "total": "SHIFT / BINDING"})
	elif card_definition.special_behavior_id == &"cloak":
		rows.append({"name": "Special", "each": "5s invisibility", "total": "SHIFT / BINDING"})
	elif card_definition.special_behavior_id == &"rebound_shield":
		rows.append({"name": "Shield Form", "each": "Scaling return", "total": "ENABLED"})
	elif card_definition.special_behavior_id == &"kinetic_vent":
		rows.append({"name": "Shield Form", "each": "Release stored pulse", "total": "ENABLED"})
	elif card_definition.special_behavior_id == &"breakaway_thrusters":
		rows.append({"name": "Escape System", "each": "Break-triggered thrust", "total": "ENABLED"})
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
	stat.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
	row.add_child(stat)
	var each := Label.new()
	each.text = String(effect["each"])
	each.custom_minimum_size.x = 92.0
	each.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	each.add_theme_font_size_override("font_size", 13)
	each.add_theme_color_override("font_color", DesignTokensScript.TEXT_SECONDARY)
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
	style.bg_color = Color(DesignTokensScript.SURFACE, 0.97)
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


func _stat_name(property_name: String) -> String:
	return Metadata.label(StringName(property_name))
