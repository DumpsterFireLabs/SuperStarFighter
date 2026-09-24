extends SceneTree

## Paired deterministic workloads; measures these changes, not complete server FPS.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lobby := ServerLobby.new()
	var world := AuthoritativeWorld.new()
	for peer_id in range(2, 34):
		lobby.admit(peer_id, "Pilot%d" % peer_id)
		world.add_peer(peer_id)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 4242)
	coordinator.machine.state = MatchStateMachine.State.ACTIVE_HEAT
	for player in coordinator.machine.players.values():
		for card_id in coordinator.catalog.all_ids().slice(0, 16):
			player.card_stacks[card_id] = 1
	var bridge := NetworkBridge.new()
	bridge.match_coordinator = coordinator
	bridge.world = world
	var full_samples: Array[int] = []
	var small_samples: Array[int] = []
	for index in 1000:
		var began := Time.get_ticks_usec()
		coordinator.current_state_payload()
		full_samples.append(Time.get_ticks_usec() - began)
		began = Time.get_ticks_usec()
		bridge._log_overtime_if_needed()
		small_samples.append(Time.get_ticks_usec() - began)
	print("SSF_OVERTIME_OBSERVATION_BENCHMARK=" + JSON.stringify({
		"players": 32, "cards_per_player": 16, "samples": 1000,
		"previous_full_payload": _summary(full_samples), "current_logger": _summary(small_samples),
	}))
	bridge.free()
	quit(0)


func _summary(samples: Array) -> Dictionary:
	var total := 0
	for value in samples:
		total += int(value)
	return {"mean_usec": float(total) / samples.size(),
		"p50_usec": NetworkBridge.percentile_usec(samples, 0.5),
		"p95_usec": NetworkBridge.percentile_usec(samples, 0.95)}
