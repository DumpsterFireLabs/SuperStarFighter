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
		if not await _verify_lobby_requests(client):
			client._disconnect_online()
			quit(4)
			return
		if not await _verify_global_pause(client):
			client._disconnect_online()
			quit(4)
			return
		var runtime_path: NodePath = client.connection_controller.hosted_session.runtime_root.get_path()
		client._disconnect_online()
		await process_frame
		if get_multiplayer(runtime_path) != get_multiplayer():
			printerr("SSF_LOCAL_HOST_ERROR=custom multiplayer registration survived teardown")
			quit(4)
			return
		if client.bridge.multiplayer.connected_to_server.is_connected(client.bridge.session._on_client_transport_connected):
			printerr("SSF_LOCAL_HOST_ERROR=transport callback survived teardown")
			quit(4)
			return
	print("SSF_LOCAL_HOST_OK=connected_admitted_discovered port=%d reconnects=1 lobby_requests=verified global_pause=verified" % verification_port)
	quit(0)


func _host_once(client: Node) -> bool:
	client.connection_controller._host_online()
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
		var connected: bool = client.bridge.local_peer_id != 0
		var admitted: bool = (
			client.connection_controller.hosted_session.server_bridge != null and
			client.connection_controller.hosted_session.server_bridge.lobby != null and
			client.connection_controller.hosted_session.server_bridge.lobby.human_count() == 1
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


func _verify_lobby_requests(client: Node) -> bool:
	var lobby_screen = client.connection_controller.lobby
	lobby_screen.rounds_control.value = 4
	lobby_screen.ready_button.button_pressed = true
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
		var state: Dictionary = client.bridge.latest_lobby_state
		if int(state.get("rounds_to_win", 0)) == 4 and bool(state.get("all_humans_ready", false)):
			return true
	printerr("SSF_LOCAL_HOST_ERROR=lobby requests did not return through authority")
	return false


func _verify_global_pause(client: Node) -> bool:
	var server: NetworkBridge = client.connection_controller.hosted_session.server_bridge
	client.bridge.send_player_limit(2)
	client.bridge.send_npcs_enabled(true)
	var started_at := Time.get_ticks_msec()
	while server.lobby.participant_count() < 2 and Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
	client.bridge.send_ready_state(true)
	client.bridge.send_start_match()
	started_at = Time.get_ticks_msec()
	while client.latest_match_payload.is_empty() and Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
	if server.match_coordinator == null:
		printerr("SSF_LOCAL_HOST_ERROR=pause fixture did not start a match")
		return false
	client._toggle_pause_overlay()
	client._update_global_pause_ui()
	if not client.global_pause_button.visible:
		printerr("SSF_LOCAL_HOST_ERROR=host pause action is missing")
		return false
	client.global_pause_button.pressed.emit()
	started_at = Time.get_ticks_msec()
	while not client.network_world.match_paused and Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
	if not client.network_world.match_paused or not client.global_pause_notice.visible:
		printerr("SSF_LOCAL_HOST_ERROR=pause did not replicate to the host UI")
		return false
	var tick: int = server.world.server_tick
	client._hide_pause_overlay()
	await create_timer(0.25).timeout
	if server.world.server_tick != tick or not client.network_world.match_paused:
		printerr("SSF_LOCAL_HOST_ERROR=closing the menu resumed or advanced the match")
		return false
	client._toggle_pause_overlay()
	client.input_profiles.set_scheme(InputProfileManager.Scheme.KEYBOARD_MOUSE, false)
	var pause_key := InputEventKey.new()
	pause_key.physical_keycode = KEY_F10
	pause_key.pressed = true
	client.input_profiles.rebind(&"global_pause", pause_key, false)
	client._input(pause_key)
	started_at = Time.get_ticks_msec()
	while client.network_world.match_paused and Time.get_ticks_msec() - started_at < TIMEOUT_MSEC:
		await process_frame
	await create_timer(0.1).timeout
	if client.network_world.match_paused or server.world.server_tick <= tick:
		printerr("SSF_LOCAL_HOST_ERROR=resume did not restart simulation")
		return false
	return true
