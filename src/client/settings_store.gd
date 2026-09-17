extends RefCounted

## Shared persistence boundary for all client preferences.
const PATH: String = "user://super_star_fighter_settings.cfg"


static func update(changes: Callable, path: String = PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error not in [OK, ERR_FILE_NOT_FOUND]:
		push_warning("Could not read settings; existing file was preserved (error %d)." % error)
		return error
	changes.call(config)
	error = config.save(path)
	if error != OK:
		push_warning("Could not save settings (error %d)." % error)
	return error
