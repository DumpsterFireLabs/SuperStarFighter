extends Node


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	print(
		"SSF_MODE_READY=client port=%d sandbox=offline_combat" % configuration.get(
			"port",
			GameConstants.DEFAULT_PORT
		)
	)
