extends SceneTree

## Actual ClientMain screen flow/audio and shared ServerRuntime over real TCP.
var duration := 45.0
var expected_fps := 60.0
var app: Node
var server: NetworkBridge
var runtime := preload("res://src/server/server_runtime.gd").new()
var samples: Array[int] = []
var snapshots := 0
var peak_ships := 0
var peak_projectiles := 0
var audio_events := 0
var states := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="): duration = clampf(float(arg.get_slice("=", 1)), 30, 300)
		if arg.begins_with("--expected-fps="): expected_fps = clampf(float(arg.get_slice("=", 1)), 1, 240)
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		push_error("Production presentation acceptance requires a rendered window and real audio driver.")
		quit(1)
		return
	var branch := Node.new()
	branch.name = "Server"
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var main := Node.new()
	main.name = "Main"
	branch.add_child(main)
	server = runtime.attach(main)
	app = load("res://scenes/client/client_main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._dismiss_splash(true)
	# ClientMain loads the user's video preferences. Apply fixture settings after
	# that load, in memory only, so control/live runs use the same dimensions.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	app.bridge.client_lobby_updated.connect(_lobby)
	app.bridge.client_match_event_received.connect(_event)
	app.bridge.client_snapshot_received.connect(func(_snapshot: Dictionary) -> void: snapshots += 1)
	app.network_world.presentation_event.connect(func(_kind: StringName, _payload: Dictionary) -> void: audio_events += 1)
	if server.start_server({"port": 17842, "max_players": 32, "ban_file": "", "lobby_password": "performance", "test_match_seed": 731901, "test_fast_match": true}) != OK:
		push_error("Production fixture could not bind loopback server.")
		runtime.stop()
		quit(1)
		return
	app.bridge.start_client("127.0.0.1", 17842, "PerformancePilot", GameConstants.PROTOCOL_VERSION, "performance")
	var started := Time.get_ticks_usec()
	var previous := started
	Input.action_press("fire")
	while Time.get_ticks_usec() - started < duration * 1000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if now - started > 5000000 and app.network_world.controls_enabled:
			samples.append(now - previous)
		peak_ships = maxi(peak_ships, app.network_world.replicated_visuals.ships.size())
		peak_projectiles = maxi(peak_projectiles, app.network_world.replicated_visuals.authoritative_projectiles.size())
		previous = now
	await process_frame
	Input.action_release("fire")
	var pacing := preload("res://src/test/frame_timing_summary.gd").summarize(samples, expected_fps)
	var valid: bool = samples.size() >= 600 and snapshots >= 100 and peak_ships == 32 and peak_projectiles > 0 and audio_events > 0 and app.audio_director.peak_active_voices > 0 and states.has("DRAFT") and states.has("ACTIVE_HEAT")
	print("SSF_PRODUCTION_RENDER=" + JSON.stringify({"valid": valid, "samples": samples.size(), "pacing": pacing, "audio_driver": AudioServer.get_driver_name(), "audio_events": audio_events, "peak_audio_voices": app.audio_director.peak_active_voices, "audio_muted": app.audio_director.muted, "states": states.keys(), "snapshots": snapshots, "peak_ships": peak_ships, "peak_projectiles": peak_projectiles, "viewport": str(root.size), "frame_cap": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(), "scope": "actual ClientMain with real audio driver, screen/event handlers and shared ServerRuntime; TCP loopback plus 31 NPCs; active heat frames after 5s warmup; cadence diagnostic, no pure GPU/audio execution timer"}))
	app.bridge.stop()
	runtime.stop()
	quit(0 if valid else 1)

func _lobby(state: Dictionary) -> void:
	if bool(state.get("match_active", false)): return
	if not bool(state.get("npcs_enabled", false)):
		app.bridge.send_npcs_enabled(true)
	elif not bool(state.get("all_humans_ready", false)):
		app.bridge.send_ready_state(true)
	else:
		app.bridge.send_start_match()

func _event(kind: StringName, _tick: int, payload: Dictionary) -> void:
	if kind == &"DRAFT_OFFER":
		app.bridge.send_card_selection(String(payload.offer_token), StringName(payload.card_ids[0]))
	elif kind == &"STATE_CHANGED":
		states[String(payload.get("state_name", ""))] = true
		if payload.get("state_name", "") == "MATCH_RESULT": app.bridge.send_return_to_lobby()
