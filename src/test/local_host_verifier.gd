extends SceneTree

const TIMEOUT_MSEC: int = 10000

var verification_port: int = 17659


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--verification-port="):
			var value := argument.trim_prefix("--verification-port=")
			if value.is_valid_int():
				verification_port = int(value)
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://scenes/client/client_main.tscn") as PackedScene
	var client := packed_scene.instantiate()
	client.name = "Main"
	root.add_child(client)
	await process_frame
	await process_frame
	client._dismiss_splash(true)
	client.name_field.text = "HostVerifier"
	client.server_name_field.text = "Verified Local Arena"
	client.host_port_field.text = str(verification_port)
	client._host_online()
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
		var connected: bool = client.bridge.local_peer_id != 0
		var admitted: bool = (
			client._hosted_server_bridge != null and
			client._hosted_server_bridge.lobby != null and
			client._hosted_server_bridge.lobby.human_count() == 1
		)
		var discovered := false
		for server in client._lan_servers:
			if String(server.get("server_name", "")) == "Verified Local Arena" and int(server.get("game_port", 0)) == verification_port:
				discovered = true
				break
		if connected and admitted and discovered:
			print("SSF_LOCAL_HOST_OK=connected_admitted_discovered port=%d" % verification_port)
			client._disconnect_online()
			await process_frame
			quit(0)
			return
	printerr("SSF_LOCAL_HOST_ERROR=timeout status=%s connected=%s servers=%s" % [
		client.connection_status.text,
		str(client.bridge.local_peer_id != 0),
		str(client._lan_servers),
	])
	client._disconnect_online()
	await process_frame
	quit(4)
