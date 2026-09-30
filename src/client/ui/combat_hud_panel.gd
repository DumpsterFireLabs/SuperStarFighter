class_name CombatHudPanel
extends PanelContainer

## The framed combat HUD shared by online matches, the Combat Lab, and Learn to
## Play, so the HUD a new pilot learns is the one they fight with. Scan order
## follows DESIGN_LANGUAGE.md: status lines, vitals and loadout, bars, hints.

const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const WIDTH: float = 430.0

var match_status_label: Label
var resources_label: Label
var health_bar: ProgressBar
var shield_bar: ProgressBar
var combat_status_label: Label


func _init() -> void:
	name = "CombatHudPanel"
	custom_minimum_size = Vector2(WIDTH, 148.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", _panel_style())
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	match_status_label = _label(DesignTokensScript.INTERACTIVE)
	match_status_label.custom_minimum_size.x = WIDTH - 40.0
	content.add_child(match_status_label)
	resources_label = _label(DesignTokensScript.TEXT_PRIMARY)
	content.add_child(resources_label)
	health_bar = _resource_bar(DesignTokensScript.HEALTH)
	content.add_child(health_bar)
	shield_bar = _resource_bar(DesignTokensScript.SHIELD)
	content.add_child(shield_bar)
	combat_status_label = _label(DesignTokensScript.TEXT_SECONDARY)
	content.add_child(combat_status_label)


## Hull and shield share one line; compact HUDs drop the maxima.
static func vitals_text(health: float, max_health: float, shield: float, shield_capacity: float, compact: bool = false) -> String:
	if compact:
		return "HULL %.0f  ·  SHIELD %.0f" % [health, shield]
	return "HULL %.0f/%.0f  ·  SHIELD %.0f/%.0f" % [health, max_health, shield, shield_capacity]


## Vitals and loadout sit on fixed lines so values never wrap away from their
## labels at the minimum interface text size.
static func resources_text(vitals: String, loadout: PackedStringArray) -> String:
	return vitals + "\n" + "  ·  ".join(loadout)


func set_width(width: float) -> void:
	custom_minimum_size.x = width
	size.x = width
	match_status_label.custom_minimum_size.x = maxf(width - 40.0, 100.0)


func set_vitals(health: float, max_health: float, shield: float, shield_capacity: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	shield_bar.max_value = shield_capacity
	shield_bar.value = shield


func set_hints(text: String) -> void:
	combat_status_label.text = text.strip_edges()
	combat_status_label.visible = not combat_status_label.text.is_empty()


## Containers grow but never shrink on their own; return to the content height
## after text changes so the frame does not keep stale empty space.
func fit_height() -> void:
	size.y = 0.0


func _label(color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_BODY_SIZE)
	label.add_theme_color_override("font_color", color)
	return label


func _resource_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(WIDTH - 40.0, 12.0)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _flat_style(DesignTokensScript.SURFACE_MUTED, Color("31466c"), 1))
	bar.add_theme_stylebox_override("fill", _flat_style(Color(color.darkened(0.45), 0.94), color, 1))
	return bar


func _panel_style() -> StyleBoxFlat:
	var style := _flat_style(Color(DesignTokensScript.SURFACE, 0.9), Color(DesignTokensScript.INTERACTIVE, 0.75), 2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


static func _flat_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(10)
	return style
