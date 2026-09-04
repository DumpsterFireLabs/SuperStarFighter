extends RefCounted

## Persistence boundary for connection UI. No node, control or bridge dependency.
## Pending credentials are committed only after admission succeeds.
const Appearance = preload("res://src/shared/models/ship_appearance.gd")
var settings_path: String
var random_color: bool = true
var ship_color: Color = Color("42e8ff")
var ship_pattern: StringName = Appearance.SOLID
var _pending_key: String = ""
var _pending_password: String = ""
var _pending_remember: bool = false


func _init(path: String = AudioDirector.SETTINGS_PATH) -> void:
	settings_path = path


func load_appearance() -> Error:
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error != OK: return error
	random_color = bool(config.get_value("appearance", "random_ship_color", true))
	var color := String(config.get_value("appearance", "ship_color", ship_color.to_html(false)))
	if not ServerLobby._normalized_ship_color(color).is_empty():
		ship_color = Color.from_string("#%s" % color.trim_prefix("#"), ship_color)
	var pattern := Appearance.normalized_pattern(String(config.get_value("appearance", "ship_pattern", Appearance.SOLID)))
	if not pattern.is_empty(): ship_pattern = pattern
	return OK


func save_appearance(random_value: bool, color: Color, pattern: StringName) -> Error:
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error not in [OK, ERR_FILE_NOT_FOUND]: return error
	random_color = random_value
	ship_color = color
	ship_pattern = pattern
	config.set_value("appearance", "random_ship_color", random_color)
	config.set_value("appearance", "ship_color", ship_color.to_html(false))
	config.set_value("appearance", "ship_pattern", String(ship_pattern))
	return config.save(settings_path)


func password_for_endpoint(address: String, port: int) -> String:
	var key := endpoint_key(address, port)
	if key.is_empty(): return ""
	var config := ConfigFile.new()
	if config.load(settings_path) != OK: return ""
	var password := String(config.get_value("lobby_passwords", key, ""))
	return password if NetworkProtocol.is_valid_lobby_password(password) else ""


func begin_attempt(address: String, port: int, password: String, remember: bool) -> void:
	_pending_key = endpoint_key(address, port)
	_pending_password = password
	_pending_remember = remember


func discard_attempt() -> void:
	_pending_key = ""
	_pending_password = ""
	_pending_remember = false


func confirm_connected() -> Error:
	var key := _pending_key
	var password := _pending_password
	var remember := _pending_remember
	discard_attempt()
	if key.is_empty(): return OK
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error not in [OK, ERR_FILE_NOT_FOUND]: return error
	if remember and NetworkProtocol.is_valid_lobby_password(password):
		config.set_value("lobby_passwords", key, password)
	elif config.has_section_key("lobby_passwords", key):
		config.erase_section_key("lobby_passwords", key)
	return config.save(settings_path)


static func endpoint_key(address: String, port: int) -> String:
	var normalized := address.strip_edges().to_lower()
	if normalized.begins_with("[") and normalized.ends_with("]"):
		normalized = normalized.substr(1, normalized.length() - 2)
	if normalized.is_empty() or port < GameConstants.MIN_PORT or port > GameConstants.MAX_PORT:
		return ""
	return ("%s:%d" % [normalized, port]).sha256_text()
