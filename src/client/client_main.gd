extends Control


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	$Center/Panel/Content/Version.text = "Foundation build · Protocol %d · Godot %s" % [
		GameConstants.PROTOCOL_VERSION,
		GameConstants.ENGINE_VERSION,
	]
	$Center/Panel/Content/Status.text = "Client entry path ready on UDP port %d" % configuration.get(
		"port",
		GameConstants.DEFAULT_PORT
	)
	print("SSF_MODE_READY=client")

