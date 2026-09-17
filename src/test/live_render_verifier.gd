extends SceneTree

## Real ENet loopback, production server/NPC stepping and client rendering in one
## process. Frame intervals include their combined work; this is not remote RTT.
class MeasuredWorldView extends NetworkWorldFixture:
	var snapshot_usec: Array[int] = []
	var physics_usec: Array[int] = []
	var measuring: bool = false
	var operations: Dictionary = {}

	func record_operation(operation: StringName, began: int) -> void:
		if not measuring: return
		if not operations.has(operation): operations[operation] = []
		operations[operation].append(Time.get_ticks_usec() - began)

	func operation_summary() -> Dictionary:
		var result := {}
		for operation in operations:
			var times: Array[int] = []
			times.assign(operations[operation])
			times.sort()
			var total := 0
			for time in times: total += time
			result[operation] = {"calls": times.size(), "total_usec": total,
				"p95_usec": NetworkBridge.percentile_usec(times, 0.95), "max_usec": times.back()}
		return result

	func _on_snapshot(decoded: Dictionary) -> void:
		var began := Time.get_ticks_usec()
		super._on_snapshot(decoded)
		if measuring: snapshot_usec.append(Time.get_ticks_usec() - began)

	func _physics_process(delta: float) -> void:
		var began := Time.get_ticks_usec()
		super._physics_process(delta)
		if measuring: physics_usec.append(Time.get_ticks_usec() - began)

class MeasuredVisuals extends NetworkReplicatedVisuals:
	func _ensure_ship_from_identity(peer_id: int, state: Dictionary, identity: Dictionary) -> CombatShipView:
		var began := Time.get_ticks_usec()
		var result := super._ensure_ship_from_identity(peer_id, state, identity)
		(context.surface as MeasuredWorldView).record_operation(&"ship_identity", began)
		return result

	func _apply_snapshot_resources(ship: CombatShipView, state: Dictionary) -> void:
		var began := Time.get_ticks_usec()
		super._apply_snapshot_resources(ship, state)
		(context.surface as MeasuredWorldView).record_operation(&"ship_resources", began)

	func _update_remote_ships() -> void:
		var began := Time.get_ticks_usec()
		super._update_remote_ships()
		(context.surface as MeasuredWorldView).record_operation(&"remote_motion", began)

	func _step_projectile_visuals(delta: float) -> void:
		var began := Time.get_ticks_usec()
		super._step_projectile_visuals(delta)
		(context.surface as MeasuredWorldView).record_operation(&"projectile_motion", began)

class MeasuredPrediction extends NetworkLocalPrediction:
	func step(delta: float, ship: CombatShipView, mouse_world_position: Vector2) -> void:
		var began := Time.get_ticks_usec()
		super.step(delta, ship, mouse_world_position)
		(context.surface as MeasuredWorldView).record_operation(&"local_prediction", began)

	func apply_local_snapshot(decoded: Dictionary, state: Dictionary, ship: CombatShipView, revived: bool) -> void:
		var began := Time.get_ticks_usec()
		super.apply_local_snapshot(decoded, state, ship, revived)
		(context.surface as MeasuredWorldView).record_operation(&"local_reconciliation", began)

class MeasuredHud extends NetworkHudCamera:
	func _update_diagnostics(delta: float = 0.0) -> void:
		var began := Time.get_ticks_usec()
		super._update_diagnostics(delta)
		(context.surface as MeasuredWorldView).record_operation(&"hud", began)

var server: NetworkBridge
var client: NetworkBridge
var view: MeasuredWorldView
var samples: Array[int] = []
var snapshots: int = 0
var peak_projectiles: int = 0
var peak_ships: int = 0
var duration: float = 90.0
var frame_cap: int = 120
var expected_fps: float = 60.0
var hide_world: bool = false
var pre_draw_usec: int = 0
var draw_samples: Array[int] = []
var process_samples: Array[int] = []
var physics_samples: Array[int] = []
var draw_calls: Array[int] = []


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
		if arg.begins_with("--frame-cap="): frame_cap = clampi(int(arg.get_slice("=", 1)), 0, 240)
		if arg.begins_with("--expected-fps="): expected_fps = clampf(float(arg.get_slice("=", 1)), 1.0, 240.0)
		if arg == "--hide-world": hide_world = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = frame_cap
	RenderingServer.frame_pre_draw.connect(_before_draw)
	server = _runtime("Server")
	client = _runtime("Client")
	view = MeasuredWorldView.new()
	view.replicated_visuals = MeasuredVisuals.new()
	view.local_prediction = MeasuredPrediction.new()
	view.hud_camera = MeasuredHud.new()
	view.configure_owners()
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
		view.measuring = now - started > 5000000 and view.controls_enabled
		if now - started > 5000000 and view.controls_enabled:
			samples.append(now - previous)
			draw_samples.append(now - pre_draw_usec)
			process_samples.append(roundi(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000))
			physics_samples.append(roundi(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000))
			draw_calls.append(roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if hide_world: view.hide()
		peak_projectiles = maxi(peak_projectiles, view.replicated_visuals.authoritative_projectiles.size())
		peak_ships = maxi(peak_ships, view.replicated_visuals.ships.size())
		previous = now
	# Leave render-signal dispatch before tearing down presentation/transport.
	await process_frame
	RenderingServer.frame_pre_draw.disconnect(_before_draw)
	Input.action_release("fire")
	var pacing := preload("res://src/test/frame_timing_summary.gd").summarize(samples, expected_fps)
	samples.sort()
	draw_samples.sort()
	process_samples.sort()
	physics_samples.sort()
	draw_calls.sort()
	view.snapshot_usec.sort()
	view.physics_usec.sort()
	var over_budget := 0
	for interval in samples:
		if interval > 16667: over_budget += 1
	print("SSF_LIVE_RENDER_RESULT=%s" % JSON.stringify({"samples": samples.size(), "duration_seconds": duration,
		"viewport": str(root.size), "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"frame_cap": frame_cap, "hide_world": hide_world,
		"pacing": pacing, "client_operations": view.operation_summary(),
		"pre_to_post_draw_p95_usec": NetworkBridge.percentile_usec(draw_samples, 0.95),
		"engine_process_p95_usec": NetworkBridge.percentile_usec(process_samples, 0.95),
		"engine_physics_p95_usec": NetworkBridge.percentile_usec(physics_samples, 0.95),
		"draw_calls_p95": NetworkBridge.percentile_usec(draw_calls, 0.95),
		"client_snapshot_p95_usec": NetworkBridge.percentile_usec(view.snapshot_usec, 0.95),
		"client_physics_p95_usec": NetworkBridge.percentile_usec(view.physics_usec, 0.95),
		"p50_usec": NetworkBridge.percentile_usec(samples, 0.5), "p95_usec": NetworkBridge.percentile_usec(samples, 0.95),
		"p99_usec": NetworkBridge.percentile_usec(samples, 0.99), "over_16ms_percent": 100.0 * over_budget / maxi(samples.size(), 1),
		"snapshots": snapshots, "peak_ships": peak_ships, "peak_projectiles": peak_projectiles,
		"scope": "Post-draw wall-clock intervals during active heats after 5s warmup; same-process ENet server, 31 NPCs and client; vsync off; excludes physical display latency. Engine process/physics monitors and pre-to-post draw intervals overlap; do not sum their percentiles."}))
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


func _before_draw() -> void:
	pre_draw_usec = Time.get_ticks_usec()


func _event(kind: StringName, _tick: int, payload: Dictionary) -> void:
	if kind == &"DRAFT_OFFER":
		client.send_card_selection(String(payload.offer_token), StringName(payload.card_ids[0]))
	elif kind == &"STATE_CHANGED":
		view.apply_match_state(payload)
		if payload.get("state_name", "") == "MATCH_RESULT": client.send_return_to_lobby()
	elif kind == &"COMBAT_FEEDBACK":
		view.apply_combat_feedback(payload)
