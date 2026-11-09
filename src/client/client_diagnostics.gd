extends RefCounted

## Client-side diagnostic lines for bug reports. Each is one JSON object on
## standard output, which Godot's file logging also writes to
## user://logs/godot.log, in the style of the server's structured log.
##
## Never pass passwords, reconnect tokens, admin proofs or server addresses a
## player typed: the log is meant to be attached to public bug reports.

const LOG_DIRECTORY := "user://logs"


static func log_event(event: String, fields: Dictionary = {}) -> void:
	var entry := {"timestamp": Time.get_datetime_string_from_system(true), "event": event}
	entry.merge(fields)
	print(JSON.stringify(entry))


## Build identity and the machine facts most bug reports need.
static func startup_fields() -> Dictionary:
	var window := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	return {
		"game_version": GameConstants.GAME_VERSION,
		"protocol_version": GameConstants.PROTOCOL_VERSION,
		"packet_version": NetworkProtocol.PACKET_VERSION,
		"engine": Engine.get_version_info().string,
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"renderer": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"window_size": [window.x, window.y],
	}


static func log_folder() -> String:
	return ProjectSettings.globalize_path(LOG_DIRECTORY)


## Opens the client log folder in the system file browser.
static func open_log_folder() -> Error:
	var folder := log_folder()
	DirAccess.make_dir_recursive_absolute(folder)
	return OS.shell_open(folder)
