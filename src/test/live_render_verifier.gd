extends SceneTree

## Real ENet loopback, production server/NPC stepping and client rendering in one
## process. Frame intervals include their combined work; this is not remote RTT.
var server: NetworkBridge
var client: NetworkBridge
var view: NetworkWorldView
var samples: Array[int] = []
var snapshots: int = 0
var peak_projectiles: int = 0
var peak_ships: int = 0
var duration: float = 90.0


func _initialize() -> void:
	_run.call_deferred()


func _runtime(label: String) -> NetworkBridge:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var main := Node.new()
	main.name = "Main"
	branch.add_child(main)
	var bridge := NetworkBridge.new()
	bridge.name = "NetworkBridge"
	main.add_child(bridge)
	return bridge


func _run() -> void:
	for action in ["special_previous", "special_next"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="): duration = clampf(float(arg.get_slice("=", 1)), 30.0, 300.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	server = _runtime("Server")
	client = _runtime("Client")
	view = NetworkWorldView.new()
	root.add_child(view)
	view.setup(client)
	client.client_snapshot_received.connect(func(_snapshot: Dictionary) -> void: snapshots += 1)
	client.client_lobby_updated.connect(_lobby)
	client.client_match_event_received.connect(_event)
	if server.start_server({"port": 17840, "max_players": 32, "ban_file": "", "lobby_password": "render-fixture", "test_match_seed": 731901}) != OK:
		quit(1)
		return
	client.start_client("127.0.0.1", 17840, "RenderedPilot", GameConstants.PROTOCOL_VERSION, "render-fixture")
	Input.action_press("fire")
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < duration * 1000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if now - started > 5000000 and view.controls_enabled:
			samples.append(now - previous)
		peak_projectiles = maxi(peak_projectiles, view.authoritative_projectiles.size())
		peak_ships = maxi(peak_ships, view.ships.size())
		previous = now
	Input.action_release("fire")
	samples.sort()
	var over_budget := 0
	for interval in samples:
		if interval > 16667: over_budget += 1
	print("SSF_LIVE_RENDER_RESULT=%s" % JSON.stringify({"samples": samples.size(), "duration_seconds": duration,
		"viewport": str(root.size), "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"p50_usec": NetworkBridge.percentile_usec(samples, 0.5), "p95_usec": NetworkBridge.percentile_usec(samples, 0.95),
		"p99_usec": NetworkBridge.percentile_usec(samples, 0.99), "over_16ms_percent": 100.0 * over_budget / maxi(samples.size(), 1),
		"snapshots": snapshots, "peak_ships": peak_ships, "peak_projectiles": peak_projectiles,
		"scope": "Post-draw wall-clock intervals during active heats after 5s warmup; same-process ENet server, 31 NPCs and client; vsync off, 120fps cap; excludes physical display latency."}))
	view.set_network_active(false)
	client.stop()
	server.stop()
	quit(0 if samples.size() >= 600 and snapshots >= 100 and peak_ships == 32 and peak_projectiles > 0 else 1)


func _lobby(state: Dictionary) -> void:
	if bool(state.get("match_active", false)): return
	if not bool(state.get("npcs_enabled", false)):
		client.send_npcs_enabled(true)
	elif not bool(state.get("all_humans_ready", false)):
		client.send_ready_state(true)
	else:
		client.send_start_match()


func _event(kind: StringName, _tick: int, payload: Dictionary) -> void:
	if kind == &"DRAFT_OFFER":
		client.send_card_selection(String(payload.offer_token), StringName(payload.card_ids[0]))
	elif kind == &"STATE_CHANGED":
		view.apply_match_state(payload)
		if payload.get("state_name", "") == "MATCH_RESULT": client.send_return_to_lobby()
	elif kind == &"COMBAT_FEEDBACK":
		view.apply_combat_feedback(payload)
