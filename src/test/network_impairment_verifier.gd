extends SceneTree

## Deterministic combat fixture; networking, input sampling, world stepping,
## snapshot reconciliation and projectile presentation use production code.
## A separate UDP proxy impairs actual ENet datagrams in both directions.
class FixtureMatch extends AuthoritativeMatchCoordinator:
	var probe_peer: int = 0
	var probe_last_press: int = -1
	var shield_probes: Array[Dictionary] = []

	func step(_delta: float) -> void:
		# Keep one controlled heat alive; match transitions have separate gates.
		if probe_peer == 0:
			return
		var defender := world.combatants[probe_peer] as CombatantState
		if defender.last_shield_press_sequence == probe_last_press:
			return
		probe_last_press = defender.last_shield_press_sequence
		var guarded := defender.shield.is_perfect_guard_active()
		var before := defender.shield.energy
		var damages: Array[Dictionary] = []
		for index in 3:
			var point := defender.position + Vector2.from_angle(defender.aim_angle) * 20.0
			var projectile := ProjectileState.create(900000 + index, 0, index, point, defender.aim_angle + PI, defender.stats)
			world.projectile_registry.add(projectile)
			world._resolve_projectile_ship_hit(projectile, probe_peer, damages)
		shield_probes.append({"press": probe_last_press, "received_ms": Time.get_ticks_msec(), "guarded": guarded, "energy_cost": before - defender.shield.energy, "hull_hits": damages.size()})

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
var final_input: PlayerInputFrame
var neutral_send_attempts: int = 0
var final_acknowledged: bool = false
var authority_reload_observed: bool = false
var authority_shield_observed: bool = false
var correction_errors: Array[float] = []
var shield_tap_attempts: int = 0
var shield_tap_latencies_ms: Array[int] = []
var shield_only: bool = false


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
		if argument == "--shield-only": shield_only = true
		if argument.begins_with("--server-port="): port = int(argument.get_slice("=", 1))
		if argument.begins_with("--proxy-port="): proxy_port = int(argument.get_slice("=", 1))
	server = _runtime("Server")
	client = _runtime("Client")
	view = NetworkWorldView.new()
	root.add_child(view)
	view.setup(client)
	client.client_snapshot_received.connect(_snapshot)
	client.client_connection_lost.connect(func(_message: String) -> void: _fail("unexpected disconnect"))
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
	for phase in (0 if shield_only else 12):
		var shots_before := ship.weapon.shot_sequence
		_release_inputs()
		await create_timer(0.05).timeout
		if phase in [0, 1, 8, 9]: Input.action_press("fire")
		if phase == 0: Input.action_press("move_right")
		if phase == 2: Input.action_press("manual_reload")
		if phase == 3: Input.action_press("shield")
		if phase >= 4 and phase <= 7:
			view.selected_special_slot = [SpecialAbilitySelection.Slot.MINE, SpecialAbilitySelection.Slot.MISSILE, SpecialAbilitySelection.Slot.CLOAK, SpecialAbilitySelection.Slot.AFTERBURNER][phase - 4]
			Input.action_press("special")
		await _until(func() -> bool: return false, 1.0)
		if not await _until(func() -> bool: return _phase_covered(phase, shots_before, ship), 2.0):
			_fail("delivery coverage missing in phase %d: %s" % [phase, _comparison()])
			return
		print("IMPAIRMENT_PHASE=%d shots=%d ammo=%d fire=%s shield=%s pending=%d" % [phase, ship.weapon.shot_sequence, ship.weapon.ammunition, str(Input.is_action_pressed("fire")), str(ship.shield.active), view.prediction.buffered_inputs.size()])
		if failed: return
	_release_inputs()
	if shield_only:
		# Keep enough traffic to exercise the proxy's scheduled blackout and
		# place short taps near it, rather than finishing before the fault starts.
		await _until(func() -> bool: return false, 3.0)
	if not await _verify_shield_taps(ship):
		return
	if shield_only:
		await _until(func() -> bool: return false, 2.0)
	# Stop sampling and create one neutral barrier. Retry that exact sequence at
	# the normal send cadence until authority acknowledges it; a lost final UDP
	# sample must not strand replay or be misreported as resource divergence.
	view.set_physics_process(false)
	final_input = PlayerInputFrame.new(SequenceMath.increment(view.input_sequence), SequenceMath.increment(view.client_tick), Vector2.ZERO, ship.aim_angle)
	view.prediction.push(final_input, 0.0)
	print("IMPAIRMENT_SETTLEMENT_BEGIN sequence=%d" % final_input.sequence)
	await create_timer(0.1).timeout
	var acknowledgment_deadline := Time.get_ticks_msec() + 8000
	while not final_acknowledged and Time.get_ticks_msec() < acknowledgment_deadline and not failed:
		client.send_input(final_input)
		neutral_send_attempts += 1
		await create_timer(1.0 / GameConstants.INPUT_SEND_RATE).timeout
	if not final_acknowledged:
		_fail("neutral input barrier was not acknowledged")
		return
	if not await _until(func() -> bool: return snapshots >= 30 and _settled(), 8.0):
		_fail("resources did not converge: %s" % _comparison())
		return
	if snapshots < 30 or (not shield_only and (not authority_reload_observed or not authority_shield_observed or ship.weapon.shot_sequence < 3)):
		_fail("missing delivery coverage")
		return
	if not shield_only and (ship.mine_charges_remaining != 2 or ship.missile_charges_remaining != 2 or ship.cloak_charges_remaining != 2):
		_fail("ability was lost or spent multiple charges: %s" % _comparison())
		return
	view.local_prediction._expire_unconfirmed_predicted_projectiles(view._now_seconds() + 2.0)
	if not view.predicted_projectile_ids.is_empty():
		_fail("unconfirmed predicted volleys leaked")
		return
	print("SSF_IMPAIRMENT_OK=%s" % JSON.stringify({"snapshots": snapshots, "max_buffered_inputs": max_buffer, "max_transient_ammo_difference": max_ammo_error, "reload_observed": observed_reload, "shield_observed": observed_shield, "shots": ship.weapon.shot_sequence, "mine_spent": 3 - ship.mine_charges_remaining, "missile_spent": 3 - ship.missile_charges_remaining, "cloak_spent": 3 - ship.cloak_charges_remaining, "comparison": _comparison(), "delivery": _delivery_diagnostics(), "movement": _movement_diagnostics(), "shield_taps": {"attempts": shield_tap_attempts, "delivery_ms": shield_tap_latencies_ms, "volleys": (server.match_coordinator as FixtureMatch).shield_probes}}))
	_cleanup()
	quit(0)


func _verify_shield_taps(ship: CombatantState) -> bool:
	var fixture := server.match_coordinator as FixtureMatch
	fixture.probe_peer = client.local_peer_id
	fixture.probe_last_press = ship.last_shield_press_sequence
	for attempt in 4:
		if shield_tap_latencies_ms.size() >= 2:
			break
		_release_inputs()
		await create_timer(0.3).timeout
		ship.shield.reset(stats)
		view.set_physics_process(false)
		var local_ship := view.ships[client.local_peer_id] as CombatShipView
		var began := Time.get_ticks_msec()
		Input.action_press("shield")
		view.local_prediction.step(1.0 / 60.0, local_ship)
		var press := view.prediction.simulated_combatant.last_shield_press_sequence
		Input.action_release("shield")
		view.local_prediction.step(1.0 / 60.0, local_ship)
		view.set_physics_process(true)
		shield_tap_attempts += 1
		# Retry coverage with a fresh player tap only after an expired attempt.
		# No acceptance requires resurrecting a tap through a long blackout.
		if await _until(func() -> bool: return ship.last_shield_press_sequence == press, 1.0):
			var result: Dictionary = fixture.shield_probes.back()
			if not bool(result.guarded) or not is_equal_approx(float(result.energy_cost), 55.0) or int(result.hull_hits) != 0:
				_fail("shield tap/volley timing: %s" % result)
				return false
			shield_tap_latencies_ms.append(int(result.received_ms) - began)
	fixture.probe_peer = 0
	_release_inputs()
	if shield_tap_latencies_ms.size() < 2:
		_fail("missing short shield tap delivery coverage")
		return false
	return true


func _snapshot(decoded: Dictionary) -> void:
	if failed: return
	var ack := int(decoded.acknowledged_input)
	var tick := int(decoded.server_tick)
	if snapshots > 0 and (not SequenceMath.is_newer(tick, previous_tick) or (ack != previous_ack and not SequenceMath.is_newer(ack, previous_ack))):
		_fail("snapshot or acknowledgement regressed")
		return
	previous_ack = ack
	if final_input != null:
		final_acknowledged = ack == final_input.sequence or SequenceMath.is_newer(ack, final_input.sequence)
	previous_tick = tick
	snapshots += 1
	latest_correction = decoded.local_state
	max_buffer = maxi(max_buffer, view.prediction.buffered_inputs.size())
	if max_buffer > ClientPredictionBuffer.MAX_BUFFERED_INPUTS:
		_fail("unbounded replay")
		return
	if not active: return
	correction_errors.append(view.prediction.last_reconciliation_error)
	var ship := server.world.combatants[client.local_peer_id] as CombatantState
	max_ammo_error = maxi(max_ammo_error, absi(ship.weapon.ammunition - view.local_weapon.ammunition))
	observed_reload = observed_reload or bool(decoded.local_state.get("reloading", false))
	for state in decoded.states:
		if int(state.peer_id) == client.local_peer_id:
			observed_shield = observed_shield or bool(state.shielding)


func _comparison() -> Dictionary:
	var authority := server.world.combatants[client.local_peer_id] as CombatantState
	var predicted := view.prediction.simulated_combatant
	return {"ammo": [authority.weapon.ammunition, predicted.weapon.ammunition], "shots": [authority.weapon.shot_sequence, predicted.weapon.shot_sequence], "reloading": [authority.weapon.reloading, predicted.weapon.reloading], "mines": [authority.mine_charges_remaining, predicted.mine_charges_remaining], "missiles": [authority.missile_charges_remaining, predicted.missile_charges_remaining], "cloak": [authority.cloak_charges_remaining, predicted.cloak_charges_remaining], "special_identity": [authority.last_special_sequence, predicted.last_special_sequence], "shield_identity": [authority.last_shield_press_sequence, predicted.last_shield_press_sequence], "shield_energy": [authority.shield.energy, predicted.shield.energy], "shield_locked": [authority.shield.depletion_locked, predicted.shield.depletion_locked], "shield_active": [authority.shield.active, predicted.shield.active], "guard_window": [authority.shield.perfect_guard_window_remaining, predicted.shield.perfect_guard_window_remaining]}


func _settled() -> bool:
	if not view.prediction.buffered_inputs.is_empty(): return false
	for values in _comparison().values():
		if values[0] != values[1]: return false
	var authority := server.world.combatants[client.local_peer_id] as CombatantState
	return not authority.weapon.reloading and not authority.shield.active and authority.weapon.cooldown_remaining <= 0.0


func _phase_covered(phase: int, shots_before: int, ship: CombatantState) -> bool:
	# The later fire phases intentionally overlap cloak, which inhibits weapons.
	# Establish shot coverage before cloak rather than demanding illegal fire.
	if phase in [0, 1]: return ship.weapon.shot_sequence >= shots_before + 2
	if phase == 2: return authority_reload_observed
	if phase == 3: return authority_shield_observed
	if phase == 4: return ship.mine_charges_remaining == 2
	if phase == 5: return ship.missile_charges_remaining == 2
	if phase == 6: return ship.cloak_charges_remaining == 2
	if phase == 7: return ship.afterburner_cooldown_remaining > 0.0
	return true


func _movement_diagnostics() -> Dictionary:
	var sorted := correction_errors.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "snap_count": view.prediction.snap_count,
		"correction_p95_pixels": sorted[clampi(ceili(sorted.size() * 0.95) - 1, 0, sorted.size() - 1)] if not sorted.is_empty() else 0.0,
		"correction_p99_pixels": sorted[clampi(ceili(sorted.size() * 0.99) - 1, 0, sorted.size() - 1)] if not sorted.is_empty() else 0.0,
		"max_correction_pixels": sorted.back() if not sorted.is_empty() else 0.0}


func _delivery_diagnostics() -> Dictionary:
	var buffered := view.prediction.buffered_inputs
	var authority := server.world.combatants.get(client.local_peer_id) as CombatantState
	return {"pending_count": buffered.size(),
		"final_sequence": final_input.sequence if final_input != null else -1,
		"neutral_send_attempts": neutral_send_attempts, "final_acknowledged": final_acknowledged,
		"oldest_sequence": buffered.front().frame.sequence if not buffered.is_empty() else -1,
		"newest_sequence": buffered.back().frame.sequence if not buffered.is_empty() else -1,
		"snapshot_ack": previous_ack, "server_ack": server.world.acknowledged_input(client.local_peer_id),
		"input_age": server.world.input_ages.get(client.local_peer_id, -1.0),
		"shield_active": authority.shield.active if authority != null else false,
		"weapon_cooldown": authority.weapon.cooldown_remaining if authority != null else -1.0,
		"snapshots": snapshots, "reload_observed": observed_reload, "shield_observed": observed_shield,
		"authority_reload_observed": authority_reload_observed, "authority_shield_observed": authority_shield_observed}


func _until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline and not failed:
		if active:
			var authority := server.world.combatants[client.local_peer_id] as CombatantState
			authority_reload_observed = authority_reload_observed or authority.weapon.reloading
			authority_shield_observed = authority_shield_observed or authority.shield.active
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
	if server != null and server.world != null and client != null and view != null:
		printerr("SSF_IMPAIRMENT_DIAGNOSTICS=%s" % JSON.stringify(_delivery_diagnostics()))
	_cleanup()
	quit(1)
