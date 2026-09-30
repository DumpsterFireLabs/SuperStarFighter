extends SceneTree

## Hosts a real local session with one NPC, gives both pilots an Escort Wing on
## the authority, and checks the wing crosses the live transport, stays near
## authority, disappears while its owner is cloaked and returns afterwards.
const TIMEOUT_MSEC: int = 20000
var failures: PackedStringArray = []
var verification_port: int = 17671


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--verification-port=") and argument.trim_prefix("--verification-port=").is_valid_int():
			verification_port = int(argument.trim_prefix("--verification-port="))
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	print("%s %s" % ["LIVE_PASS" if condition else "LIVE_FAIL", label])
	if not condition:
		failures.append(label)


func _run() -> void:
	var client := (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
	client.name = "Main"
	root.add_child(client)
	await process_frame
	await process_frame
	client._dismiss_splash(true)
	client.connection_controller.name_field.text = "DroneHost"
	client.connection_controller.server_name_field.text = "Drone Arena"
	client.connection_controller.host_port_field.text = str(verification_port)
	client.connection_controller.host_password_field.text = "drones"
	client.bridge.client_match_event_received.connect(func(event_type: StringName, _tick: int, payload: Dictionary) -> void:
		if event_type == &"DRAFT_OFFER":
			var ids := payload.get("card_ids", []) as Array
			if not ids.is_empty():
				client.bridge.send_card_selection(String(payload.get("offer_token", "")), StringName(ids[0])))
	client.connection_controller._host_online()
	var started := Time.get_ticks_msec()
	while client.bridge.local_peer_id == 0 and Time.get_ticks_msec() - started < TIMEOUT_MSEC:
		await process_frame
	var server: NetworkBridge = client.connection_controller.hosted_session.server_bridge
	client.bridge.send_player_limit(2)
	client.bridge.send_npcs_enabled(true)
	while server.lobby.participant_count() < 2 and Time.get_ticks_msec() - started < TIMEOUT_MSEC:
		await process_frame
	client.bridge.send_ready_state(true)
	client.bridge.send_start_match()
	while (server.match_coordinator == null or server.match_coordinator.machine.state != MatchStateMachine.State.ACTIVE_HEAT) and Time.get_ticks_msec() - started < TIMEOUT_MSEC:
		await process_frame
	_check(server.match_coordinator != null and server.match_coordinator.machine.state == MatchStateMachine.State.ACTIVE_HEAT, "hosted match reached an active heat")
	var world: AuthoritativeWorld = server.world
	var host_id: int = client.bridge.local_peer_id
	var npc_id := 0
	for peer_id in world.ordered_peer_ids_view():
		if peer_id != host_id:
			npc_id = peer_id
	var npc := world.combatants[npc_id] as CombatantState
	world._spawn_drone_wing(npc)
	world._spawn_drone_wing(world.combatants[host_id] as CombatantState)
	await create_timer(1.0).timeout
	var visuals: NetworkReplicatedVisuals = client.network_world.replicated_visuals
	var counts := _client_counts(visuals, npc_id, host_id)
	_check(counts.npc == GameConstants.DRONE_WING_SIZE, "host client received the NPC's wing over the transport (%d)" % counts.npc)
	_check(counts.own == GameConstants.DRONE_WING_SIZE, "host client received its own wing (%d)" % counts.own)
	var worst := 0.0
	for sample in 30:
		await process_frame
		worst = maxf(worst, _worst_error(visuals, world, npc_id))
	# Remote ships render ~100 ms behind authority and drones fly beside them.
	_check(worst < 60.0, "client NPC drones stay near authority under live interpolation (worst %.1f px)" % worst)
	npc.cloak_remaining = 3.0
	await create_timer(0.4).timeout
	counts = _client_counts(visuals, npc_id, host_id)
	_check(counts.npc == 0, "cloaked NPC's wing vanished for the host (%d)" % counts.npc)
	_check(counts.own == GameConstants.DRONE_WING_SIZE, "the host's own wing is unaffected by the NPC cloak")
	await create_timer(3.2).timeout
	counts = _client_counts(visuals, npc_id, host_id)
	var alive_on_server := 0
	for projectile in world.active_projectiles():
		if projectile.is_drone and projectile.owner_id == npc_id:
			alive_on_server += 1
	_check(counts.npc == alive_on_server and alive_on_server > 0, "NPC wing reappeared after cloak (client %d, server %d)" % [counts.npc, alive_on_server])
	print("LIVE_SUMMARY failures=%d" % failures.size())
	client._disconnect_online()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _client_counts(visuals: NetworkReplicatedVisuals, npc_id: int, host_id: int) -> Dictionary:
	var result := {"npc": 0, "own": 0}
	for projectile in visuals.authoritative_projectiles.all_projectiles():
		if not projectile.is_drone:
			continue
		if projectile.owner_id == npc_id:
			result.npc += 1
		elif projectile.owner_id == host_id:
			result.own += 1
	return result


func _worst_error(visuals: NetworkReplicatedVisuals, world: AuthoritativeWorld, owner_id: int) -> float:
	var worst := 0.0
	for projectile in visuals.authoritative_projectiles.all_projectiles():
		if projectile.is_drone and projectile.owner_id == owner_id:
			var authority := world.projectile_registry.get_projectile(projectile.projectile_id)
			if authority != null:
				worst = maxf(worst, projectile.position.distance_to(authority.position))
	return worst
