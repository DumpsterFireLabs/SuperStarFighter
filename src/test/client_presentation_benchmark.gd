extends SceneTree

## Fixed 32-pilot workload. Measures CPU callbacks, not display frame cadence.
var view: NetworkWorldFixture
var emitted_shots: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bridge := NetworkBridge.new()
	root.add_child(bridge)
	view = NetworkWorldFixture.new()
	root.add_child(view)
	view.setup(bridge)
	view.local_peer_id = 1
	view.set_network_active(true)
	view.set_physics_process(false)
	var authority := AuthoritativeWorld.new()
	var players: Array = []
	var builds := {}
	for peer in range(1, 33):
		authority.add_peer(peer)
		players.append({"peer_id": peer, "display_name": "Pilot %02d" % peer, "ship_color": "42e8ff", "ship_pattern": "zebra"})
		builds[peer] = {&"heavy_rounds": 2, &"rapid_cycling": 2, &"twin_shot": 1}
	view.apply_match_state({"state_name": "ACTIVE_HEAT", "players": players, "builds": builds})
	var snapshot := PlayerSnapshotCodec.decode(PlayerSnapshotCodec.encode(3, 0, authority.snapshot_states()))
	view._on_snapshot(snapshot)
	view.presentation_event.connect(func(event: StringName, _payload: Dictionary) -> void:
		if event == &"weapon_fire": emitted_shots += 1
	)
	var snapshot_times: Array[int] = []
	var shot_times: Array[int] = []
	for tick in 340:
		snapshot.server_tick = (tick + 2) * 3
		var began := Time.get_ticks_usec()
		view._on_snapshot(snapshot)
		if tick >= 40: snapshot_times.append(Time.get_ticks_usec() - began)
		began = Time.get_ticks_usec()
		for peer in range(1, 33):
			view.replicated_visuals._emit_weapon_shot(peer, tick, Vector2(500, 500))
		if tick >= 40: shot_times.append(Time.get_ticks_usec() - began)
	snapshot_times.sort()
	shot_times.sort()
	print("SSF_CLIENT_PRESENTATION_BENCHMARK=%s" % JSON.stringify({
		"snapshot_p50_usec": NetworkBridge.percentile_usec(snapshot_times, 0.5),
		"snapshot_p95_usec": NetworkBridge.percentile_usec(snapshot_times, 0.95),
		"shot_batch_p50_usec": NetworkBridge.percentile_usec(shot_times, 0.5),
		"shot_batch_p95_usec": NetworkBridge.percentile_usec(shot_times, 0.95),
		"measured_batches": snapshot_times.size(), "ships": view.replicated_visuals.ships.size(), "shot_events": emitted_shots,
		"scope": "300 fixed 32-player snapshot and 32-shot sound-profile batches after 40 warmup batches; headless CPU work only, no audio mixing or frame rendering."
	}))
	var valid := emitted_shots == 340 * 32 and view.replicated_visuals.ships.size() == 32
	view.free()
	bridge.free()
	quit(0 if valid else 1)
