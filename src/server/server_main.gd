extends Node


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	print(
		"SSF_MODE_READY=server port=%d max_players=%d rounds_to_win=%d auto_start=%s" % [
			configuration.get("port", GameConstants.DEFAULT_PORT),
			configuration.get("max_players", GameConstants.DEFAULT_MAX_PLAYERS),
			configuration.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN),
			str(configuration.get("auto_start", false)).to_lower(),
		]
	)

