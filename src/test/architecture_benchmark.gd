extends SceneTree

## Paired deterministic workloads; measures these changes, not complete server FPS.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var worlds: Array[AuthoritativeWorld] = []
	for enabled in [false, true]:
		var world := AuthoritativeWorld.new()
		world.set_silly_mode(enabled)
		for peer_id in range(1, 33):
			var pilot := world.add_peer(peer_id)
			pilot.health = 14.0
		worlds.append(world)
	var samples: Array = [[], []]
	for tick in range(1, 721):
		# Alternate execution order to reduce warm-cache bias.
		for index in [tick % 2, (tick + 1) % 2]:
			var world := worlds[index]
			for peer_id in range(1, 33):
				var direction := Vector2.from_angle(float(peer_id) * 0.73 + float(tick) * 0.005)
				world.submit_input(peer_id, PlayerInputFrame.new(tick, tick, direction, direction.angle()))
			var began := Time.get_ticks_usec()
			world.step(1.0 / 60.0)
			if tick > 120:
				samples[index].append(Time.get_ticks_usec() - began)
	var equivalent := worlds[0].snapshot_states() == worlds[1].snapshot_states()
	print("SSF_OPTIONAL_OBSERVER_BENCHMARK=" + JSON.stringify({
		"pilots": 32, "measured_ticks": 600, "gameplay_equivalent": equivalent,
		"disabled": _summary(samples[0]), "enabled": _summary(samples[1]),
		"scope": "paired moving ships at low health; no NPC decisions or network/render work",
	}))
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
	quit(0 if equivalent else 1)


func _summary(samples: Array) -> Dictionary:
	var total := 0
	for value in samples:
		total += int(value)
	return {"mean_usec": float(total) / samples.size(),
		"p50_usec": NetworkBridge.percentile_usec(samples, 0.5),
		"p95_usec": NetworkBridge.percentile_usec(samples, 0.95)}
