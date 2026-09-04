extends SceneTree

## Deterministic combat fixture; networking, input sampling, world stepping,
## snapshot reconciliation and projectile presentation use production code.
## A separate UDP proxy impairs actual ENet datagrams in both directions.
class FixtureMatch extends AuthoritativeMatchCoordinator:

	func step(_delta: float) -> void:
		pass # Keep one controlled heat alive; match transitions have separate gates.

var server: NetworkBridge
var client: NetworkBridge
var view: NetworkWorldView
var stats := CombatStats.create_base()
var snapshots: int = 0
var previous_ack: int = 0
var previous_tick: int = 0
var max_buffer: int = 0
var max_ammo_error: int = 0
var observed_reload: bool = false
var observed_shield: bool = false
var observed_timeout: bool = false
var active: bool = false
var failed: bool = false
var latest_correction: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _runtime(runtime_name: String) -> NetworkBridge:
	var branch := Node.new()
	branch.name = runtime_name
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
	var port := 17780
	var proxy_port := 17781
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-port="): port = int(argument.get_slice("=", 1))
		if argument.begins_with("--proxy-port="): proxy_port = int(argument.get_slice("=", 1))
	server = _runtime("Server")
	client = _runtime("Client")
	view = NetworkWorldView.new()
	root.add_child(view)
	view.setup(client)
	client.client_snapshot_received.connect(_snapshot)
	client.client_connection_lost.connect(func() -> void: _fail("unexpected disconnect"))
	if server.start_server({"port": port, "max_players": 2, "ban_file": "", "lobby_password": "impairment-fixture"}) != OK:
		_fail("server start: %s" % server.last_error)
		return
	client.start_client("127.0.0.1", proxy_port, "ImpairedPilot", GameConstants.PROTOCOL_VERSION, "impairment-fixture")
	if not await _until(func() -> bool: return client.local_peer_id != 0, 12.0):
		_fail("admission")
		return
	stats.mine_layer_enabled = true
	stats.mine_capacity = 3
	stats.missile_launcher_enabled = true
	stats.missile_capacity = 3
	stats.cloak_enabled = true
	stats.cloak_capacity = 3
	stats.afterburner_enabled = true
	stats.afterburner_cooldown = 2.0
	stats.magazine_size = 16
	var ship := server.world.add_peer(client.local_peer_id, stats)
	ship.reset_for_heat(stats, Vector2(700, 1100))
	server.lobby.match_active = true
	server.match_coordinator = FixtureMatch.new(server.lobby, server.world, 230926)
	server.match_coordinator.machine.state = MatchStateMachine.State.ACTIVE_HEAT
	view.local_stats = stats
	view.controls_enabled = true
	if not await _until(func() -> bool: return view.prediction_initialized, 8.0):
		_fail("first snapshot")
		return
	active = true
	_release_inputs()
	await create_timer(0.1).timeout
	# Long held actions, manual reload, shield, each selected ability, then idle.
	# The normal client retries one identity until consumed or its deadline.
	for phase in 12:
		_release_inputs()
		await create_timer(0.05).timeout
		if phase in [0, 1, 8, 9]: Input.action_press("fire")
		if phase == 0: Input.action_press("move_right")
		if phase == 2: Input.action_press("manual_reload")
		if phase == 3: Input.action_press("shield")
		if phase >= 4 and phase <= 7:
			view.selected_special_slot = [SpecialAbilitySelection.Slot.MINE, SpecialAbilitySelection.Slot.MISSILE, SpecialAbilitySelection.Slot.CLOAK, SpecialAbilitySelection.Slot.AFTERBURNER][phase - 4]
			Input.action_press("special")
		await create_timer(1.0).timeout
		print("IMPAIRMENT_PHASE=%d shots=%d ammo=%d fire=%s shield=%s pending=%d" % [phase, ship.weapon.shot_sequence, ship.weapon.ammunition, str(Input.is_action_pressed("fire")), str(ship.shield.active), view.prediction.buffered_inputs.size()])
		if failed: return
	_release_inputs()
	# Explicitly stop producing inputs. Server neutralizes stale held actions;
	# final snapshots must prune all replay and agree on durable resources.
	view.set_physics_process(false)
	# Flush the last 60 Hz sample that may fall between the 30 Hz sends.
	if not view.prediction.buffered_inputs.is_empty():
		client.send_input(view.prediction.buffered_inputs.back().frame)
	if not await _until(_settled, 8.0):
		_fail("resources did not converge: %s" % _comparison())
		return
	if snapshots < 30 or not observed_reload or not observed_shield or ship.weapon.shot_sequence < 3:
		_fail("missing combat coverage")
		return
	if ship.mine_charges_remaining != 2 or ship.missile_charges_remaining != 2 or ship.cloak_charges_remaining != 2:
		_fail("ability was lost or spent multiple charges: %s" % _comparison())
		return
	view.local_prediction._expire_unconfirmed_predicted_projectiles(view._now_seconds() + 2.0)
	if not view.predicted_projectile_ids.is_empty():
		_fail("unconfirmed predicted volleys leaked")
		return
	print("SSF_IMPAIRMENT_OK=%s" % JSON.stringify({"snapshots": snapshots, "max_buffered_inputs": max_buffer, "max_transient_ammo_difference": max_ammo_error, "reload_observed": observed_reload, "shield_observed": observed_shield, "shots": ship.weapon.shot_sequence, "mine_spent": 3 - ship.mine_charges_remaining, "missile_spent": 3 - ship.missile_charges_remaining, "cloak_spent": 3 - ship.cloak_charges_remaining, "comparison": _comparison()}))
	_cleanup()
	quit(0)


func _snapshot(decoded: Dictionary) -> void:
	if failed: return
	var ack := int(decoded.acknowledged_input)
	var tick := int(decoded.server_tick)
	if snapshots > 0 and (not SequenceMath.is_newer(tick, previous_tick) or (ack != previous_ack and not SequenceMath.is_newer(ack, previous_ack))):
		_fail("snapshot or acknowledgement regressed")
		return
	previous_ack = ack
	previous_tick = tick
	snapshots += 1
	latest_correction = decoded.local_state
	max_buffer = maxi(max_buffer, view.prediction.buffered_inputs.size())
	if max_buffer > ClientPredictionBuffer.MAX_BUFFERED_INPUTS:
		_fail("unbounded replay")
		return
	if not active: return
	var ship := server.world.combatants[client.local_peer_id] as CombatantState
	max_ammo_error = maxi(max_ammo_error, absi(ship.weapon.ammunition - view.local_weapon.ammunition))
	observed_reload = observed_reload or bool(decoded.local_state.get("reloading", false))
	for state in decoded.states:
		if int(state.peer_id) == client.local_peer_id:
			observed_shield = observed_shield or bool(state.shielding)


func _comparison() -> Dictionary:
	var authority := server.world.combatants[client.local_peer_id] as CombatantState
	var predicted := view.prediction.simulated_combatant
	return {"ammo": [authority.weapon.ammunition, predicted.weapon.ammunition], "shots": [authority.weapon.shot_sequence, predicted.weapon.shot_sequence], "reloading": [authority.weapon.reloading, predicted.weapon.reloading], "mines": [authority.mine_charges_remaining, predicted.mine_charges_remaining], "missiles": [authority.missile_charges_remaining, predicted.missile_charges_remaining], "cloak": [authority.cloak_charges_remaining, predicted.cloak_charges_remaining], "special_identity": [authority.last_special_sequence, predicted.last_special_sequence]}


func _settled() -> bool:
	if not view.prediction.buffered_inputs.is_empty(): return false
	for values in _comparison().values():
		if values[0] != values[1]: return false
	var authority := server.world.combatants[client.local_peer_id] as CombatantState
	return not authority.weapon.reloading and not authority.shield.active and authority.weapon.cooldown_remaining <= 0.0


func _until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline and not failed:
		if predicate.call(): return true
		await process_frame
	return false


func _release_inputs() -> void:
	for action in ["fire", "shield", "manual_reload", "special", "move_right"]:
		Input.action_release(action)


func _cleanup() -> void:
	_release_inputs()
	active = false
	if view != null: view.set_physics_process(false)
	if client != null:
		client.client_connection_lost.disconnect(client.client_connection_lost.get_connections()[0].callable)
		client.stop()
	if server != null: server.stop()


func _fail(reason: String) -> void:
	if failed: return
	failed = true
	printerr("SSF_IMPAIRMENT_ERROR=%s" % reason)
	_cleanup()
	quit(1)
