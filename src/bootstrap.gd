extends Node

const MODE_SCENES := {
	"client": "res://scenes/client/client_main.tscn",
	"server": "res://scenes/server/server_main.tscn",
	"bot_client": "res://scenes/test/bot_client_main.tscn",
	"tests": "res://scenes/test/test_runner.tscn",
}


func _ready() -> void:
	var configuration := CommandLineConfig.parse(
		OS.get_cmdline_user_args(),
		OS.has_feature("dedicated_server")
	)
	if not configuration.ok:
		push_error(configuration.error)
		print("SSF_STARTUP_ERROR=%s" % configuration.error)
		get_tree().quit(configuration.exit_code)
		return

	get_tree().root.set_meta("ssf_command_line", configuration)
	if OS.has_feature("ssf_shipping") and (configuration.mode in ["tests", "bot_client"] or (OS.has_feature("dedicated_server") and configuration.mode != "server")):
		print("SSF_STARTUP_ERROR=This mode is not included in this shipping package.")
		get_tree().quit(2)
		return
	var scene_path: String = MODE_SCENES[configuration.mode]
	_change_scene.call_deferred(scene_path)


func _change_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Failed to load startup scene %s (error %d)." % [scene_path, error])
		get_tree().quit(1)
