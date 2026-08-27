class_name DesignTokens
extends RefCounted

## Super Star Fighter's UI language: a quiet tactical surface with neon reserved
## for identity, interaction, and state. Keep domain colours (rarity/resources)
## separate from these semantic interface roles.

const BACKGROUND: Color = Color("05091b")
const SURFACE: Color = Color("071024")
const SURFACE_RAISED: Color = Color("0d1730")
const SURFACE_MUTED: Color = Color("101a36")

const TEXT_PRIMARY: Color = Color("f4fbff")
const TEXT_SECONDARY: Color = Color("aebbd4")
const TEXT_MUTED: Color = Color("8ba1c7")
const TEXT_DISABLED: Color = Color("687894")

const BRAND_CYAN: Color = Color("42e8ff")
const BRAND_MAGENTA: Color = Color("d39cff")
const INTERACTIVE: Color = Color("38d9ff")
const FOCUS: Color = Color("fff36a")
const SUCCESS: Color = Color("62ff9b")
const WARNING: Color = Color("ffbe55")
const DANGER: Color = Color("ff5f7f")
const DISABLED: Color = Color("53627d")

const HEALTH: Color = Color("54ff8b")
const SHIELD: Color = Color("5cf6ff")

const RADIUS_SMALL: int = 7
const RADIUS_CONTROL: int = 10
const RADIUS_PANEL: int = 16
const BORDER_SUBTLE: int = 1
const BORDER_CONTROL: int = 2
const BORDER_FOCUS: int = 3


static func create_interface_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	_configure_button_type(theme, &"Button", INTERACTIVE, 0.16)
	_configure_button_type(theme, &"OptionButton", INTERACTIVE, 0.16)
	_configure_button_type(theme, &"CheckButton", INTERACTIVE, 0.12)

	_register_button_variation(theme, &"PrimaryButton", INTERACTIVE, 0.32)
	_register_button_variation(theme, &"SecondaryButton", BRAND_MAGENTA, 0.17)
	_register_button_variation(theme, &"DangerButton", DANGER, 0.13)
	_register_button_variation(theme, &"QuietButton", DISABLED, 0.08)
	theme.set_type_variation(&"SettingToggle", &"CheckButton")
	_configure_button_type(theme, &"SettingToggle", INTERACTIVE, 0.12)
	theme.set_type_variation(&"SuccessToggle", &"CheckButton")
	_configure_button_type(theme, &"SuccessToggle", SUCCESS, 0.14)

	theme.set_stylebox(&"normal", &"LineEdit", input_style())
	theme.set_stylebox(&"focus", &"LineEdit", input_style(FOCUS, BORDER_FOCUS))
	theme.set_stylebox(&"read_only", &"LineEdit", input_style(DISABLED))
	theme.set_color(&"font_color", &"LineEdit", TEXT_PRIMARY)
	theme.set_color(&"font_uneditable_color", &"LineEdit", TEXT_DISABLED)
	theme.set_color(&"caret_color", &"LineEdit", INTERACTIVE)
	theme.set_color(&"selection_color", &"LineEdit", Color(INTERACTIVE, 0.34))

	_configure_tabs(theme)
	_configure_slider(theme)
	_configure_scrollbars(theme)
	_configure_progress_bar(theme)

	return theme


static func panel_style(accent: Color = BRAND_CYAN, opacity: float = 0.96) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(SURFACE, opacity)
	style.border_color = Color(accent, 0.86)
	style.set_border_width_all(BORDER_FOCUS)
	style.set_corner_radius_all(RADIUS_PANEL)
	style.shadow_color = Color(accent, 0.16)
	style.shadow_size = 12
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style


static func inset_style(accent: Color = INTERACTIVE, opacity: float = 0.5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.darkened(0.84), opacity)
	style.border_color = Color(accent, 0.32)
	style.set_border_width_all(BORDER_SUBTLE)
	style.set_corner_radius_all(RADIUS_SMALL)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


static func input_style(accent: Color = DISABLED, border_width: int = BORDER_CONTROL) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE_RAISED
	style.border_color = Color(accent, 0.84)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style


static func focus_style(accent: Color = FOCUS) -> StyleBoxFlat:
	return _button_style(accent, 0.18, 1.0, BORDER_FOCUS, 12)


static func _register_button_variation(theme: Theme, variation: StringName, accent: Color, fill_alpha: float) -> void:
	theme.set_type_variation(variation, &"Button")
	_configure_button_type(theme, variation, accent, fill_alpha)


static func _configure_button_type(theme: Theme, type_name: StringName, accent: Color, fill_alpha: float) -> void:
	theme.set_color(&"font_color", type_name, TEXT_PRIMARY)
	theme.set_color(&"font_hover_color", type_name, Color.WHITE)
	theme.set_color(&"font_pressed_color", type_name, FOCUS)
	theme.set_color(&"font_focus_color", type_name, Color.WHITE)
	theme.set_color(&"font_disabled_color", type_name, TEXT_DISABLED)
	theme.set_stylebox(&"normal", type_name, _button_style(accent, fill_alpha, 0.56))
	theme.set_stylebox(&"hover", type_name, _button_style(accent, fill_alpha + 0.14, 0.9, BORDER_CONTROL, 8))
	theme.set_stylebox(&"pressed", type_name, _button_style(accent, 0.34, 0.96, BORDER_CONTROL, 8))
	theme.set_stylebox(&"hover_pressed", type_name, _button_style(accent, 0.42, 1.0, BORDER_CONTROL, 10))
	theme.set_stylebox(&"focus", type_name, focus_style())
	theme.set_stylebox(&"disabled", type_name, _button_style(DISABLED, 0.08, 0.3))


static func _configure_tabs(theme: Theme) -> void:
	theme.set_color(&"font_unselected_color", &"TabBar", TEXT_SECONDARY)
	theme.set_color(&"font_hovered_color", &"TabBar", TEXT_PRIMARY)
	theme.set_color(&"font_selected_color", &"TabBar", Color.WHITE)
	theme.set_stylebox(&"tab_unselected", &"TabBar", _tab_style(DISABLED, 0.04, false))
	theme.set_stylebox(&"tab_hovered", &"TabBar", _tab_style(INTERACTIVE, 0.12, false))
	theme.set_stylebox(&"tab_selected", &"TabBar", _tab_style(INTERACTIVE, 0.2, true))
	theme.set_stylebox(&"tab_focus", &"TabBar", focus_style())
	var panel := inset_style(INTERACTIVE, 0.16)
	panel.content_margin_top = 10.0
	theme.set_stylebox(&"panel", &"TabContainer", panel)


static func _configure_slider(theme: Theme) -> void:
	theme.set_stylebox(&"slider", &"HSlider", _track_style(DISABLED, 0.48))
	theme.set_stylebox(&"grabber_area", &"HSlider", _track_style(INTERACTIVE, 0.72))
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", _track_style(FOCUS, 0.82))
	theme.set_stylebox(&"focus", &"HSlider", focus_style())


static func _configure_scrollbars(theme: Theme) -> void:
	for type_name in [&"VScrollBar", &"HScrollBar"]:
		theme.set_stylebox(&"scroll", type_name, _scroll_style(SURFACE_MUTED, 0.26))
		theme.set_stylebox(&"grabber", type_name, _scroll_style(DISABLED, 0.58))
		theme.set_stylebox(&"grabber_highlight", type_name, _scroll_style(INTERACTIVE, 0.74))
		theme.set_stylebox(&"grabber_pressed", type_name, _scroll_style(FOCUS, 0.82))


static func _configure_progress_bar(theme: Theme) -> void:
	theme.set_stylebox(&"background", &"ProgressBar", _track_style(SURFACE_MUTED, 0.68))
	theme.set_stylebox(&"fill", &"ProgressBar", _track_style(INTERACTIVE, 0.84))
	theme.set_color(&"font_color", &"ProgressBar", TEXT_PRIMARY)


static func _button_style(accent: Color, fill_alpha: float, border_alpha: float, border_width: int = BORDER_CONTROL, shadow_size: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.darkened(0.72), 0.72 + fill_alpha * 0.2)
	style.border_color = Color(accent, border_alpha)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(RADIUS_CONTROL)
	style.shadow_color = Color(accent, 0.2 if shadow_size > 0 else 0.0)
	style.shadow_size = shadow_size
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


static func _tab_style(accent: Color, fill_alpha: float, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.darkened(0.78), 0.5 + fill_alpha)
	style.border_color = Color(accent, 0.88 if selected else 0.24)
	style.border_width_bottom = 3 if selected else 1
	style.set_corner_radius_all(RADIUS_SMALL)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


static func _track_style(accent: Color, opacity: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, opacity)
	style.set_corner_radius_all(6)
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


static func _scroll_style(accent: Color, opacity: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, opacity)
	style.set_corner_radius_all(6)
	return style
