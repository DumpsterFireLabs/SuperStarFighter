extends Node

var bridge: NetworkBridge


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	bridge = NetworkBridge.new()
	bridge.name = "NetworkBridge"
	add_child(bridge)
	var error := bridge.start_server(configuration)
	if error != OK:
		push_error(bridge.last_error)
		get_tree().quit(3)
		return
	print(
		"SSF_MODE_READY=server port=%d max_players=%d rounds_to_win=%d auto_start=%s" % [
			configuration.get("port", GameConstants.DEFAULT_PORT),
			configuration.get("max_players", GameConstants.DEFAULT_MAX_PLAYERS),
			configuration.get("rounds_to_win", GameConstants.DEFAULT_ROUNDS_TO_WIN),
			str(configuration.get("auto_start", false)).to_lower(),
		]
	)
	var test_duration := int(configuration.get("test_server_duration", 0))
	if test_duration > 0:
		get_tree().create_timer(test_duration).timeout.connect(_on_test_duration_elapsed)


func _on_test_duration_elapsed() -> void:
	if bridge != null:
		bridge.flush_metrics()
		bridge.stop()
	print("SSF_SERVER_GRACEFUL_SHUTDOWN=test_duration")
	get_tree().quit(0)


func _exit_tree() -> void:
	if bridge != null:
		bridge.stop()
