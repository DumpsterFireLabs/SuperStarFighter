extends Node


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	print(
		"SSF_MODE_READY=bot_client name=%s port=%d" % [
			configuration.get("bot_name", "FoundationBot"),
			configuration.get("port", GameConstants.DEFAULT_PORT),
		]
	)

