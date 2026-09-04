extends RefCounted

const MINIMUM_TEXT_SIZE: int = 21


static func apply(root: Node, high_contrast: bool) -> void:
	if root is Control:
		var control := root as Control
		var font_size := control.get_theme_font_size("font_size")
		# A 1px native button label deliberately yields to its custom card content.
		if font_size > 1 and font_size < MINIMUM_TEXT_SIZE:
			control.add_theme_font_size_override("font_size", MINIMUM_TEXT_SIZE)
		for key in [&"font_color", &"font_disabled_color", &"font_unselected_color", &"font_placeholder_color"]:
			var meta_key := StringName("accessible_original_" + str(key))
			if high_contrast:
				if not control.has_meta(meta_key):
					control.set_meta(meta_key, {"override": control.has_theme_color_override(key), "color": control.get_theme_color(key)})
				var original: Color = control.get_meta(meta_key).color
				# Preserve rarity/resource hues while raising text luminance and opacity.
				control.add_theme_color_override(key, Color(original.lightened(0.65), 1.0) if original.a > 0.0 else original)
			elif control.has_meta(meta_key):
				var original: Dictionary = control.get_meta(meta_key)
				if bool(original.override):
					control.add_theme_color_override(key, original.color)
				else:
					control.remove_theme_color_override(key)
				control.remove_meta(meta_key)
		for key in [&"panel", &"normal", &"hover", &"pressed", &"focus", &"disabled", &"tab_selected", &"tab_unselected"]:
			if not control.has_theme_stylebox(key):
				continue
			var meta_key := StringName("accessible_style_" + str(key))
			if high_contrast and not control.has_meta(meta_key):
				var original := control.get_theme_stylebox(key)
				if original is StyleBoxFlat:
					control.set_meta(meta_key, {"override": control.has_theme_stylebox_override(key), "style": original})
					var stronger := original.duplicate() as StyleBoxFlat
					stronger.bg_color = Color(stronger.bg_color.darkened(0.35), 1.0) if stronger.bg_color.a > 0.0 else stronger.bg_color
					stronger.border_color = Color(stronger.border_color.lightened(0.4), 1.0)
					control.add_theme_stylebox_override(key, stronger)
			elif not high_contrast and control.has_meta(meta_key):
				var original: Dictionary = control.get_meta(meta_key)
				if bool(original.override):
					control.add_theme_stylebox_override(key, original.style)
				else:
					control.remove_theme_stylebox_override(key)
				control.remove_meta(meta_key)
	for child in root.get_children():
		apply(child, high_contrast)
