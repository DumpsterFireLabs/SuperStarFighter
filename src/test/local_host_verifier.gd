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
	client.connection_controller.name_field.text = "HostVerifier"
	client.connection_controller.server_name_field.text = "Verified Local Arena"
	client.connection_controller.host_port_field.text = str(verification_port)
	client.connection_controller.host_password_field.text = "test-lobby"
	for attempt in 2:
		client.connection_controller.host_password_field.text = "test-lobby"
		if not await _host_once(client):
			quit(4)
			return
		client._disconnect_online()
		await process_frame
		if client.bridge.multiplayer.connected_to_server.is_connected(client.bridge.session._on_client_transport_connected):
			printerr("SSF_LOCAL_HOST_ERROR=transport callback survived teardown")
			quit(4)
			return
	print("SSF_LOCAL_HOST_OK=connected_admitted_discovered port=%d reconnects=1" % verification_port)
	quit(0)


func _host_once(client: Node) -> bool:
	client.connection_controller._host_online()
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
		var connected: bool = client.bridge.local_peer_id != 0
		var admitted: bool = (
			client.connection_controller._hosted_server_bridge != null and
			client.connection_controller._hosted_server_bridge.lobby != null and
			client.connection_controller._hosted_server_bridge.lobby.human_count() == 1
		)
		var discovered := false
		for server in client.connection_controller._lan_servers:
			if String(server.get("server_name", "")) == "Verified Local Arena" and int(server.get("game_port", 0)) == verification_port:
				discovered = true
				break
		if connected and admitted and discovered:
			return true
	printerr("SSF_LOCAL_HOST_ERROR=timeout status=%s connected=%s servers=%s" % [
		client.connection_controller.connection_status.text,
		str(client.bridge.local_peer_id != 0),
		str(client.connection_controller._lan_servers),
	])
	client._disconnect_online()
	await process_frame
	return false
