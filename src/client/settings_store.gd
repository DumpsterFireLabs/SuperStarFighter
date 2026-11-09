extends RefCounted

## Shared persistence boundary for all client preferences.
const PATH: String = "user://super_star_fighter_settings.cfg"


## Bump when a stored key is renamed or changes meaning, and add the upgrade
## step to migrate(). Every save records the version it was written with.
const SCHEMA_VERSION: int = 1
const META_SECTION: String = "meta"
const SCHEMA_KEY: String = "schema"


static func update(changes: Callable, path: String = PATH) -> Error:
	var config := ConfigFile.new()
	var error := load_into(config, path)
	if error not in [OK, ERR_FILE_NOT_FOUND]:
		push_warning("Could not read settings; existing file was preserved (error %d)." % error)
		return error
	changes.call(config)
	config.set_value(META_SECTION, SCHEMA_KEY, SCHEMA_VERSION)
	error = config.save(path)
	if error != OK:
		push_warning("Could not save settings (error %d)." % error)
	return error


## Loads a settings file and upgrades it to SCHEMA_VERSION in memory. Every
## preference owner reads through here so a migration runs in one place.
static func load_into(config: ConfigFile, path: String = PATH) -> Error:
	var error := config.load(path)
	if error == OK:
		migrate(config)
	return error


## The schema version a loaded file was written with. Files from before
## versioning carry no marker and are schema 1.
static func schema_of(config: ConfigFile) -> int:
	return int(config.get_value(META_SECTION, SCHEMA_KEY, 1))


## Upgrades an older file in place. There are no migrations yet; add one step
## per version, e.g. `if schema_of(config) < 2: <rename keys>`.
static func migrate(config: ConfigFile) -> void:
	var _schema := schema_of(config)
