extends RefCounted

const DEFAULTS: Dictionary = {
	"hud_scale": 1.0,
	"reduced_shake": false,
	"reduced_flashes": false,
	"constrain_hud": true,
	"high_contrast": false,
	"toggle_fire": false,
	"toggle_shield": false,
}

var values: Dictionary = DEFAULTS.duplicate()
var settings_path: String = AudioDirector.SETTINGS_PATH


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	var loaded := {}
	for key in DEFAULTS:
		loaded[key] = config.get_value("accessibility", key, DEFAULTS[key])
	set_values(loaded)


func set_values(changes: Dictionary) -> void:
	for key in DEFAULTS:
		if changes.has(key):
			values[key] = changes[key]
	var requested_scale := float(values.hud_scale)
	values.hud_scale = clampf(requested_scale, 1.0, 1.5) if is_finite(requested_scale) else 1.0
	for key in ["reduced_shake", "reduced_flashes", "constrain_hud", "high_contrast", "toggle_fire", "toggle_shield"]:
		values[key] = bool(values[key])


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.load(settings_path)
	for key in DEFAULTS:
		config.set_value("accessibility", key, values[key])
	return config.save(settings_path)


static func hud_safe_rect(viewport_size: Vector2, constrained: bool = true) -> Rect2:
	var safe_width := minf(viewport_size.x, viewport_size.y * 16.0 / 9.0) if constrained else viewport_size.x
	return Rect2(Vector2((viewport_size.x - safe_width) * 0.5, 0.0), Vector2(safe_width, viewport_size.y))
