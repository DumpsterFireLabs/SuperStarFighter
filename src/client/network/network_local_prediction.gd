class_name NetworkLocalPrediction
extends RefCounted

## Owns sampled input, replay state, local resource prediction and shot reconciliation.

const LOCAL_CONTACT_ESCAPE_SPEED: float = 180.0
const MIN_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS: float = 0.4
const MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS: float = 1.25
const PROJECTILE_CONFIRMATION_RTT_MULTIPLIER: float = 2.0
const PROJECTILE_CONFIRMATION_GRACE_SECONDS: float = 0.2
const SPECIAL_ACTIVATION_RETRY_SECONDS: float = 1.25

var view: NetworkWorldView
var prediction := ClientPredictionBuffer.new()
var predicted_tracker := PredictedProjectileTracker.new()
var predicted_projectile_ids: Dictionary = {}
var local_weapon := WeaponState.new()
var local_stats := CombatStats.create_base()
var input_sequence: int = 0
var client_tick: int = 0
var input_send_accumulator: float = 0.0
var prediction_initialized: bool = false
var next_predicted_id: int = -1
var latest_acknowledged_input: int = 0
var action_latch = preload("res://src/client/input/combat_action_latch.gd").new()
var input_blocked: bool = false:
	set(value):
		input_blocked = value
		if value:
			action_latch.reset()
var special_activation_sends_remaining: int = 0
var special_activation_sequence: int = 0
var special_activation_deadline_msec: int = 0
var selected_special_slot: int = -1
var special_activation_slot: int = -1
var local_active_ordnance: int = 0
var local_active_mines: int = 0
var local_budget_evictions: int = 0
var budget_warning_remaining: float = 0.0
var local_special_cooldown_remaining: float = 0.0
var local_mine_charges_remaining: int = 0
var local_mine_cooldown_remaining: float = 0.0
var local_missile_charges_remaining: int = 0
var local_missile_cooldown_remaining: float = 0.0
var local_cloak_charges_remaining: int = 0
var local_cloak_remaining: float = 0.0
var local_cloak_cooldown_remaining: float = 0.0
var local_breakaway_remaining: float = 0.0
var local_kinetic_vent_charge: float = 0.0
var local_breakaway_cooldown_remaining: float = 0.0
var expired_predicted_volleys: int = 0


func _advance_input_clock() -> void:
	client_tick = SequenceMath.increment(client_tick)
	# Every predicted physics frame needs its own sequence, including frames
	# between the 30 Hz network sends. Otherwise an acknowledgement for the
	# previous send can incorrectly prune newer local movement from replay.
	input_sequence = SequenceMath.increment(input_sequence)


func _sync_predicted_resources(ship: CombatShipView) -> void:
	var simulated := prediction.simulated_combatant
	if simulated == null:
		return
	local_weapon = simulated.weapon
	local_special_cooldown_remaining = simulated.afterburner_cooldown_remaining
	local_mine_charges_remaining = simulated.mine_charges_remaining
	local_mine_cooldown_remaining = simulated.mine_cooldown_remaining
	local_missile_charges_remaining = simulated.missile_charges_remaining
	local_missile_cooldown_remaining = simulated.missile_cooldown_remaining
	local_cloak_charges_remaining = simulated.cloak_charges_remaining
	local_cloak_remaining = simulated.cloak_remaining
	local_cloak_cooldown_remaining = simulated.cloak_cooldown_remaining
	local_breakaway_remaining = simulated.breakaway_remaining
	local_breakaway_cooldown_remaining = simulated.breakaway_cooldown_remaining
	local_kinetic_vent_charge = simulated.shield.kinetic_vent_charge
	ship.combatant.weapon = local_weapon
	# Keep presentation resources separate from the replay state: snapshots
	# update the visual ship before the buffered inputs have been replayed.
	ship.combatant.shield.energy = simulated.shield.energy
	ship.combatant.shield.active = simulated.shield.active
	ship.combatant.cloak_remaining = simulated.cloak_remaining
	ship.combatant.breakaway_remaining = simulated.breakaway_remaining


func _spawn_predicted_projectile(ship: CombatShipView, aim_angle: float) -> void:
	var muzzle := ship.global_position + Vector2.from_angle(aim_angle) * 31.0
	var predicted_ids: Array[int] = []
	for angle in MovementSystem.spread_angles(aim_angle, local_stats.projectile_count, local_stats.projectile_spread_degrees):
		var projectile := ProjectileState.create(next_predicted_id, view.local_peer_id, local_weapon.shot_sequence, muzzle, angle, local_stats)
		view.replicated_visuals.authoritative_projectiles.add(projectile)
		predicted_ids.append(next_predicted_id)
		next_predicted_id -= 1
	predicted_projectile_ids[local_weapon.shot_sequence] = predicted_ids
	predicted_tracker.add(view.local_peer_id, local_weapon.shot_sequence, view._now_seconds())
	view.replicated_visuals._emit_weapon_shot(view.local_peer_id, local_weapon.shot_sequence, muzzle)


func _expire_unconfirmed_predicted_projectiles(now_seconds: float) -> void:
	for key in predicted_tracker.step(now_seconds, _projectile_confirmation_timeout_seconds()):
		var parts := key.split(":", false, 1)
		if parts.size() != 2 or int(parts[0]) != view.local_peer_id:
			continue
		_remove_predicted_volley(int(parts[1]))
		expired_predicted_volleys += 1


func _remove_predicted_volley(shot_sequence: int) -> void:
	if not predicted_projectile_ids.has(shot_sequence):
		return
	for predicted_id in predicted_projectile_ids[shot_sequence] as Array:
		view.replicated_visuals.authoritative_projectiles.remove(int(predicted_id))
	predicted_projectile_ids.erase(shot_sequence)


func _reconcile_predicted_projectile(projectile: ProjectileState) -> void:
	if projectile.owner_id != view.local_peer_id or not predicted_projectile_ids.has(projectile.shot_sequence):
		return
	_remove_predicted_volley(projectile.shot_sequence)
	predicted_tracker.reconcile(projectile.owner_id, projectile.shot_sequence)


func _projectile_confirmation_timeout_seconds() -> float:
	var rtt_seconds := 0.0
	if view.bridge != null:
		rtt_seconds = maxf(float(view.bridge.get_round_trip_time_ms()), 0.0) / 1000.0
	return clampf(
		maxf(
			MIN_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS,
			rtt_seconds * PROJECTILE_CONFIRMATION_RTT_MULTIPLIER + PROJECTILE_CONFIRMATION_GRACE_SECONDS
		),
		MIN_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS,
		MAX_PROJECTILE_CONFIRMATION_TIMEOUT_SECONDS
	)


func _separate_local_visual_from_remote(local_ship: CombatShipView) -> void:
	if not prediction_initialized or not local_ship.combatant.alive:
		return
	var target_distance := GameConstants.SHIP_COLLISION_RADIUS * 2.0 + 1.0
	for peer_value in view.replicated_visuals.ships.keys():
		var peer_id := int(peer_value)
		if peer_id == view.local_peer_id:
			continue
		var remote := view.replicated_visuals.ships[peer_id] as CombatShipView
		if not remote.combatant.alive:
			continue
		var difference := prediction.predicted_position - remote.global_position
		if difference.length_squared() >= target_distance * target_distance:
			continue
		var preferred := difference.normalized()
		if preferred.is_zero_approx():
			preferred = Vector2.from_angle(float(posmod(view.local_peer_id * 31 + peer_id * 17, 360)) * PI / 180.0)
		var candidate := Vector2.INF
		var best_cost := INF
		for sample_index in 24:
			var direction := preferred.rotated(TAU * float(sample_index) / 24.0)
			var proposed := remote.global_position + direction * target_distance
			if not _local_visual_candidate_available(proposed, peer_id, target_distance):
				continue
			var cost := prediction.predicted_position.distance_squared_to(proposed) + float(sample_index) * 0.001
			if cost < best_cost:
				candidate = proposed
				best_cost = cost
		if candidate == Vector2.INF:
			continue
		var separation_normal := (candidate - remote.global_position).normalized()
		var inward_speed := minf(prediction.predicted_velocity.dot(separation_normal), 0.0)
		prediction.predicted_velocity -= separation_normal * inward_speed
		prediction.predicted_velocity += separation_normal * LOCAL_CONTACT_ESCAPE_SPEED
		prediction.predicted_velocity = prediction.predicted_velocity.limit_length(maxf(local_stats.max_speed * 2.5, 1.0))
		prediction.predicted_position = candidate
		prediction.smoothing_offset = Vector2.ZERO
		prediction.smoothing_remaining = 0.0
		local_ship.global_position = candidate
		local_ship.combatant.position = candidate
		local_ship.combatant.velocity = prediction.predicted_velocity


func _local_visual_candidate_available(position: Vector2, contacted_peer_id: int, minimum_distance: float) -> bool:
	var selected_map := view.replicated_visuals.arena.map_id if view.replicated_visuals.arena != null else ArenaLayout.DEFAULT_MAP_ID
	if not ArenaCollisionSystem.is_ship_position_clear(position, selected_map, 1.0):
		return false
	for peer_value in view.replicated_visuals.ships.keys():
		var peer_id := int(peer_value)
		if peer_id == view.local_peer_id or peer_id == contacted_peer_id:
			continue
		var other := view.replicated_visuals.ships[peer_id] as CombatShipView
		if other.combatant.alive and position.distance_to(other.global_position) < minimum_distance:
			return false
	return true


func step(delta: float, local_ship: CombatShipView) -> void:
	_advance_input_clock()
	_expire_special_activation(Time.get_ticks_msec())
	input_send_accumulator += delta
	local_special_cooldown_remaining = maxf(local_special_cooldown_remaining - maxf(delta, 0.0), 0.0)
	budget_warning_remaining = maxf(budget_warning_remaining - maxf(delta, 0.0), 0.0)
	local_mine_cooldown_remaining = maxf(local_mine_cooldown_remaining - maxf(delta, 0.0), 0.0)
	local_missile_cooldown_remaining = maxf(local_missile_cooldown_remaining - maxf(delta, 0.0), 0.0)
	local_cloak_remaining = maxf(local_cloak_remaining - maxf(delta, 0.0), 0.0)
	local_cloak_cooldown_remaining = maxf(local_cloak_cooldown_remaining - maxf(delta, 0.0), 0.0)
	local_breakaway_remaining = maxf(local_breakaway_remaining - maxf(delta, 0.0), 0.0)
	local_breakaway_cooldown_remaining = maxf(local_breakaway_cooldown_remaining - maxf(delta, 0.0), 0.0)
	var aim_vector: Vector2 = view.input_profiles.aim_vector() if view.input_profiles != null and view.input_profiles.uses_controller() else view.hud_camera._unshaken_mouse_world_position() - local_ship.global_position
	var aim_angle := local_ship.combatant.aim_angle
	if not aim_vector.is_zero_approx():
		aim_angle = aim_vector.angle()
	var local_movement: Vector2 = view.input_profiles.movement_input_for_aim(aim_angle) if view.input_profiles != null else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var local_alive := local_ship.combatant.alive
	if not view.controls_enabled or input_blocked:
		local_movement = Vector2.ZERO
	local_ship.set_thrust_input(local_movement)
	var afterburner_ready := local_stats.afterburner_enabled and local_special_cooldown_remaining <= 0.0
	var mine_ready := local_stats.mine_layer_enabled and local_mine_charges_remaining > 0 and local_mine_cooldown_remaining <= 0.0
	var missile_ready := local_stats.missile_launcher_enabled and local_missile_charges_remaining > 0 and local_missile_cooldown_remaining <= 0.0
	var cloak_ready := local_stats.cloak_enabled and local_cloak_charges_remaining > 0 and local_cloak_remaining <= 0.0 and local_cloak_cooldown_remaining <= 0.0
	selected_special_slot = SpecialAbilitySelection.ensure_owned(selected_special_slot, local_stats)
	if view.controls_enabled and not input_blocked and local_alive:
		if Input.is_action_just_pressed("special_previous"):
			selected_special_slot = SpecialAbilitySelection.cycle(selected_special_slot, local_stats, -1)
		if Input.is_action_just_pressed("special_next"):
			selected_special_slot = SpecialAbilitySelection.cycle(selected_special_slot, local_stats, 1)
	var readiness := [afterburner_ready, mine_ready, missile_ready, cloak_ready]
	var special_just_pressed := (
		view.controls_enabled
		and not input_blocked
		and local_alive
		and selected_special_slot >= 0 and bool(readiness[selected_special_slot])
		and Input.is_action_just_pressed("special")
	)
	if special_just_pressed:
		# Retain one press identity until authority consumes it. Three sends can
		# all vanish during ENet throttling, jitter or a short delivery outage.
		# Existing snapshot corrections acknowledge consumption, so no extra RPC
		# or reliable channel backlog is needed. Expire rather than act much later.
		special_activation_sends_remaining = ceili(SPECIAL_ACTIVATION_RETRY_SECONDS * GameConstants.INPUT_SEND_RATE)
		special_activation_deadline_msec = Time.get_ticks_msec() + int(SPECIAL_ACTIVATION_RETRY_SECONDS * 1000)
		special_activation_sequence = input_sequence
		special_activation_slot = selected_special_slot
	elif not view.controls_enabled or input_blocked or not local_alive:
		special_activation_sends_remaining = 0
	var frame := PlayerInputFrame.new(
		input_sequence,
		client_tick,
		local_movement,
		aim_angle,
		action_latch.sample(&"fire", Input.is_action_pressed("fire"), bool(view.accessibility_settings.toggle_fire), view.controls_enabled and not input_blocked and local_alive and local_cloak_remaining <= 0.0),
		action_latch.sample(&"shield", Input.is_action_pressed("shield"), bool(view.accessibility_settings.toggle_shield), view.controls_enabled and not input_blocked and local_alive),
		view.controls_enabled and not input_blocked and local_alive and Input.is_action_pressed("manual_reload"),
		special_activation_sends_remaining > 0,
		special_activation_sequence,
		special_activation_slot
	)
	var send_interval := 1.0 / GameConstants.INPUT_SEND_RATE
	if input_send_accumulator >= send_interval:
		input_send_accumulator = fmod(input_send_accumulator, send_interval)
		view.bridge.send_input(frame)
		special_activation_sends_remaining = maxi(special_activation_sends_remaining - 1, 0)
	if prediction_initialized and local_alive and view.controls_enabled:
		prediction.predict(frame, local_stats, delta, view.replicated_visuals.arena.map_id if view.replicated_visuals.arena != null else ArenaLayout.DEFAULT_MAP_ID, local_breakaway_remaining > 0.0)
		_sync_predicted_resources(local_ship)
		if prediction.last_actions & CombatantState.ACTION_BOOST:
			local_ship.flash_afterburner(local_stats.afterburner_duration)
			view.hud_camera.trigger_afterburner_feedback(Vector2.from_angle(aim_angle))
			view.presentation_event.emit(&"afterburner", {
				"peer_id": view.local_peer_id,
				"server_tick": client_tick,
				"position": local_ship.global_position,
				"listener_position": local_ship.global_position,
				"local": true,
			})
		local_ship.global_position = prediction.visual_position(delta)
		local_ship.combatant.position = local_ship.global_position
		local_ship.combatant.velocity = prediction.predicted_velocity
		local_ship.combatant.aim_angle = aim_angle
		local_ship.set_movement_field_strength(ArenaMovementSystem.influence_at(
			local_ship.global_position,
			view.replicated_visuals.arena.map_id if view.replicated_visuals.arena != null else ArenaLayout.DEFAULT_MAP_ID
		))
		local_ship.queue_redraw()
		if prediction.last_actions & CombatantState.ACTION_SHOT:
			_spawn_predicted_projectile(local_ship, aim_angle)
	local_ship.combatant.weapon.ammunition = local_weapon.ammunition
	local_ship.combatant.weapon.reloading = local_weapon.reloading
	local_ship.combatant.weapon.reload_remaining = local_weapon.reload_remaining
	local_ship.queue_redraw()


func apply_local_snapshot(decoded: Dictionary, state: Dictionary, ship: CombatShipView, revived: bool) -> void:
	var correction := state.duplicate()
	var local_state := decoded.get("local_state", {}) as Dictionary
	if int(local_state.get("peer_id", 0)) == view.local_peer_id:
		correction.merge(local_state, true)
		_acknowledge_special_activation(int(local_state.get("last_special_sequence", -1)))
		local_active_ordnance = int(local_state.get("active_ordnance", 0))
		local_active_mines = int(local_state.get("active_mines", 0))
		var evictions := int(local_state.get("budget_evictions", 0))
		if evictions > local_budget_evictions:
			budget_warning_remaining = 2.0
		local_budget_evictions = evictions
	var new_life := prediction.simulated_combatant != null and int(correction.get("life_generation", prediction.simulated_combatant.life_generation)) != prediction.simulated_combatant.life_generation
	if not prediction_initialized or revived or new_life or not bool(state.alive):
		if view.hud_camera.combat_feedback_panel != null:
			view.hud_camera.combat_feedback_panel.reset_for_life(int(correction.get("life_generation", 0)))
		prediction.reset_to_snapshot(correction, local_stats)
		if revived or new_life or not bool(state.alive):
			special_activation_sends_remaining = 0
			for shot_sequence in predicted_projectile_ids.keys():
				_remove_predicted_volley(int(shot_sequence))
			predicted_tracker = PredictedProjectileTracker.new()
		ship.global_position = state.position
		view.hud_camera.camera.position = state.position
		prediction_initialized = true
	else:
		prediction.reconcile(
			state.position,
			state.velocity,
			decoded.acknowledged_input,
			local_stats,
			view.replicated_visuals.arena.map_id if view.replicated_visuals.arena != null else ArenaLayout.DEFAULT_MAP_ID,
			local_breakaway_remaining > 0.0,
			correction
		)
	_sync_predicted_resources(ship)


func _acknowledge_special_activation(consumed_sequence: int) -> void:
	# Input acknowledgements alone are insufficient: the server may have seen
	# a later neutral sample after every packet carrying the press was lost.
	if consumed_sequence >= 0 and (consumed_sequence == special_activation_sequence or SequenceMath.is_newer(consumed_sequence, special_activation_sequence)):
		special_activation_sends_remaining = 0


func _expire_special_activation(now_msec: int) -> void:
	if special_activation_sends_remaining > 0 and now_msec >= special_activation_deadline_msec:
		special_activation_sends_remaining = 0


func reset_session() -> void:
	action_latch.reset()
	input_sequence = 0
	client_tick = 0
	input_send_accumulator = 0.0
	prediction_initialized = false
	latest_acknowledged_input = 0
	next_predicted_id = -1
	predicted_projectile_ids.clear()
	special_activation_sends_remaining = 0
	special_activation_sequence = 0
	special_activation_deadline_msec = 0
	selected_special_slot = -1
	special_activation_slot = -1
	local_active_ordnance = 0
	local_active_mines = 0
	local_budget_evictions = 0
	budget_warning_remaining = 0.0
	local_special_cooldown_remaining = 0.0
	local_mine_charges_remaining = 0
	local_mine_cooldown_remaining = 0.0
	local_missile_charges_remaining = 0
	local_missile_cooldown_remaining = 0.0
	local_cloak_charges_remaining = 0
	local_cloak_remaining = 0.0
	local_cloak_cooldown_remaining = 0.0
	local_breakaway_remaining = 0.0
	local_kinetic_vent_charge = 0.0
	local_breakaway_cooldown_remaining = 0.0
	expired_predicted_volleys = 0
	prediction = ClientPredictionBuffer.new()
	predicted_tracker = PredictedProjectileTracker.new()
	local_weapon = WeaponState.new()
	local_weapon.reset(local_stats)


func reset_for_countdown() -> void:
	local_weapon.reset(local_stats)
	prediction_initialized = false
	special_activation_sends_remaining = 0
	special_activation_deadline_msec = 0
