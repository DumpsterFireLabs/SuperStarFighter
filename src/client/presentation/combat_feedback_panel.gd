class_name CombatFeedbackPanel
extends PanelContainer

var hit_label: Label
var block_label: Label
var death_label: Label
var _remaining: float = 0.0
var _life_generation: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("071020", 0.94)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	add_child(column)
	hit_label = _label(column, Color("62ff9b"))
	block_label = _label(column, Color("fff36a"))
	death_label = _label(column, Color("ff869d"))
	clear_feedback()


func _label(parent: Node, color: Color) -> Label:
	var result := Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 18)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result


func apply_feedback(payload: Dictionary, peer_id: int, names: Dictionary = {}) -> void:
	if hit_label == null:
		return
	if payload.has("death"):
		var generation := int(payload.death.get("life_generation", _life_generation))
		if generation > _life_generation:
			# Reliable death feedback may arrive before this life's snapshot.
			reset_for_life(generation)
	var hit := CombatFeedbackPresentation.hit_text(payload)
	var blocked := CombatFeedbackPresentation.block_text(payload)
	var guard := CombatFeedbackPresentation.guard_text(payload)
	if not hit.is_empty():
		hit_label.text = hit
	if not blocked.is_empty() or not guard.is_empty():
		block_label.text = " · ".join(PackedStringArray([blocked, guard])).trim_prefix(" · ").trim_suffix(" · ")
	if payload.has("death"):
		var death := payload.death as Dictionary
		if int(death.get("life_generation", _life_generation)) >= _life_generation:
			death_label.text = CombatFeedbackPresentation.death_text(death, peer_id, names)
	_remaining = 1.2
	_refresh_visibility()


func reset_for_life(generation: int) -> void:
	if generation > _life_generation:
		_life_generation = generation
		clear_feedback()


func clear_feedback(reset_life: bool = false) -> void:
	if reset_life:
		_life_generation = -1
	_remaining = 0.0
	if hit_label != null:
		hit_label.text = ""
		block_label.text = ""
		death_label.text = ""
	visible = false


func _process(delta: float) -> void:
	_remaining = maxf(_remaining - maxf(delta, 0.0), 0.0)
	if _remaining <= 0.0 and hit_label != null:
		hit_label.text = ""
		block_label.text = ""
	_refresh_visibility()


func _refresh_visibility() -> void:
	if hit_label == null:
		return
	hit_label.visible = not hit_label.text.is_empty()
	block_label.visible = not block_label.text.is_empty()
	death_label.visible = not death_label.text.is_empty()
	visible = hit_label.visible or block_label.visible or death_label.visible
