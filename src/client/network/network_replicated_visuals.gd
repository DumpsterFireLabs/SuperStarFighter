class_name NetworkReplicatedVisuals
extends RefCounted

const PowerupLayerScript = preload("res://src/client/presentation/powerup_layer.gd")

## Owns replicated ships, projectiles, interpolation and world feedback.

const ShipAppearanceScript = preload("res://src/shared/models/ship_appearance.gd")
const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")
const PROJECTILE_COLLISION_ITERATIONS: int = 16
const COLLISION_SURFACE_EPSILON: float = 0.35

var view: NetworkWorldView
var arena: ArenaView
var ships: Dictionary = {}
var authoritative_projectiles := ProjectileRegistry.new()
var projectile_layer: ProjectileLayer
var effects_layer: CombatEffectsLayer
var powerup_layer: Node2D
var interpolation := RemoteInterpolator.new()
var presentation_states: Dictionary = {}
var last_snapshot_receive_time: float = -1.0
var snapshot_jitter_ms: float = 0.0
var snapshot_gap_count: int = 0
var interpolation_sample_count: int = 0
var interpolation_extrapolated_count: int = 0


func _on_projectile_batch(decoded: Dictionary) -> void:
	var emitted_shots: Dictionary = {}
	for projectile_value in decoded.spawned:
		var projectile := projectile_value as ProjectileState
		if not projectile.is_mine:
			view.local_prediction._reconcile_predicted_projectile(projectile)
		var existing := authoritative_projectiles.get_projectile(projectile.projectile_id)
		if existing == null:
			authoritative_projectiles.add(projectile)
			if projectile.has_rebounded:
				_emit_rebound_feedback(projectile)
		else:
			var newly_rebounded := _synchronize_projectile(existing, projectile)
			if newly_rebounded:
				_emit_rebound_feedback(projectile)
		if projectile.is_mine or existing != null or projectile.has_rebounded:
			continue
		if projectile.is_missile:
			view.presentation_event.emit(&"missile_launch", {
				"projectile_id": projectile.projectile_id,
				"owner_id": projectile.owner_id,
				"position": projectile.position,
				"listener_position": view.hud_camera._audio_listener_position(),
				"server_tick": view.latest_server_tick,
			})
			continue
		var shot_key := "%d:%d" % [projectile.owner_id, projectile.shot_sequence]
		if not emitted_shots.has(shot_key):
			emitted_shots[shot_key] = true
			_emit_weapon_shot(projectile.owner_id, projectile.shot_sequence, projectile.position, projectile)
	for projectile_id in decoded.removed:
		var projectile := authoritative_projectiles.get_projectile(int(projectile_id))
		if projectile != null and effects_layer != null and not projectile.is_mine:
			effects_layer.spawn_impact(projectile.position)
		if projectile != null and not projectile.is_mine:
			view.presentation_event.emit(&"projectile_impact", {
				"projectile_id": projectile.projectile_id,
				"owner_id": projectile.owner_id,
				"position": projectile.position,
				"listener_position": view.hud_camera._audio_listener_position(),
				"server_tick": view.latest_server_tick,
			})
		authoritative_projectiles.remove(int(projectile_id))


func _on_projectile_correction(decoded: Dictionary) -> void:
	var authoritative_ids: Dictionary = {}
	for projectile_value in decoded.spawned:
		var projectile := projectile_value as ProjectileState
		# A correction can be the first authoritative evidence of a shot when its
		# unreliable delta was lost. Promote it immediately instead of rendering
		# the authoritative and predicted copies together until the timeout.
		if not projectile.is_mine:
			view.local_prediction._reconcile_predicted_projectile(projectile)
		authoritative_ids[projectile.projectile_id] = true
		var existing := authoritative_projectiles.get_projectile(projectile.projectile_id)
		if existing == null:
			authoritative_projectiles.add(projectile)
			if projectile.has_rebounded:
				_emit_rebound_feedback(projectile)
		else:
			var newly_rebounded := _synchronize_projectile(existing, projectile)
			if newly_rebounded:
				_emit_rebound_feedback(projectile)
	if bool(decoded.get("complete_snapshot", true)):
		for projectile in authoritative_projectiles.all_projectiles():
			if projectile.projectile_id > 0 and not authoritative_ids.has(projectile.projectile_id):
				authoritative_projectiles.remove(projectile.projectile_id)


func _ensure_ship(peer_id: int, state: Dictionary) -> CombatShipView:
	if ships.has(peer_id):
		var existing := ships[peer_id] as CombatShipView
		existing.display_name = _display_name(peer_id)
		# Lobby state and snapshots use independent ENet channels. A guest can
		# receive the first snapshot before the final reliable lobby update, so
		# refresh identity data instead of freezing whatever was available when
		# the presentation node happened to be created.
		existing.set_ship_appearance(_player_color(peer_id), _player_pattern(peer_id))
		return existing
	var ship := CombatShipView.new()
	ship.reduced_flashes = bool(view.accessibility_settings.reduced_flashes)
	ship.high_contrast = bool(view.accessibility_settings.high_contrast)
	var color := _player_color(peer_id)
	ship.setup(peer_id, _stats_for_peer(peer_id), state.position, color, peer_id == view.local_peer_id, _display_name(peer_id), _player_pattern(peer_id))
	ship.set_team_identity(team_for_peer(peer_id), team_for_peer(view.local_peer_id))
	ship.set_shield_build(_build_for_peer(peer_id), view.card_catalog)
	view.add_child(ship)
	ships[peer_id] = ship
	return ship


func _apply_snapshot_resources(ship: CombatShipView, state: Dictionary) -> void:
	var was_alive := ship.combatant.alive
	if bool(state.alive) and not was_alive:
		ship.reset_ship(_stats_for_peer(ship.combatant.peer_id), state.position)
	ship.combatant.position = state.position
	ship.combatant.velocity = state.velocity
	ship.combatant.aim_angle = state.aim_angle
	ship.combatant.health = state.health
	ship.combatant.shield.energy = state.shield
	ship.combatant.shield.active = state.shielding
	ship.combatant.afterburner_remaining = 0.1 if bool(state.get("afterburner_active", false)) else 0.0
	ship.combatant.mine_charges_remaining = int(state.get("mine_charges", 0))
	ship.combatant.mine_cooldown_remaining = float(state.get("mine_cooldown", 0.0))
	ship.combatant.missile_charges_remaining = int(state.get("missile_charges", 0))
	ship.combatant.missile_cooldown_remaining = float(state.get("missile_cooldown", 0.0))
	ship.combatant.cloak_remaining = maxf(ship.combatant.cloak_remaining, 0.1) if bool(state.get("cloaked", false)) else 0.0
	ship.combatant.cloak_charges_remaining = int(state.get("cloak_charges", 0))
	ship.combatant.cloak_cooldown_remaining = float(state.get("cloak_cooldown", 0.0))
	ship.combatant.shield.perfect_guard_window_remaining = 0.1 if bool(state.get("perfect_guard_active", false)) else 0.0
	ship.combatant.breakaway_remaining = 0.1 if bool(state.get("breakaway_active", false)) else 0.0
	ship.combatant.kinetic_vent_feedback_remaining = 0.1 if bool(state.get("kinetic_vent_active", false)) else 0.0
	ship.combatant.shield.kinetic_vent_charge = float(state.get("kinetic_vent_charge", 0.0))
	ship.combatant.breakaway_cooldown_remaining = float(state.get("breakaway_cooldown", 0.0))
	if ship.combatant.peer_id == view.local_peer_id:
		view.local_prediction.local_mine_charges_remaining = ship.combatant.mine_charges_remaining
		view.local_prediction.local_mine_cooldown_remaining = ship.combatant.mine_cooldown_remaining
		view.local_prediction.local_missile_charges_remaining = ship.combatant.missile_charges_remaining
		view.local_prediction.local_missile_cooldown_remaining = ship.combatant.missile_cooldown_remaining
		view.local_prediction.local_cloak_charges_remaining = ship.combatant.cloak_charges_remaining
		view.local_prediction.local_cloak_remaining = maxf(view.local_prediction.local_cloak_remaining, 0.1) if bool(state.get("cloaked", false)) else 0.0
		view.local_prediction.local_cloak_cooldown_remaining = ship.combatant.cloak_cooldown_remaining
		view.local_prediction.local_breakaway_remaining = maxf(view.local_prediction.local_breakaway_remaining, 0.1) if bool(state.get("breakaway_active", false)) else 0.0
		view.local_prediction.local_kinetic_vent_charge = ship.combatant.shield.kinetic_vent_charge
		view.local_prediction.local_breakaway_cooldown_remaining = ship.combatant.breakaway_cooldown_remaining
	if bool(state.get("afterburner_active", false)):
		ship.sustain_afterburner(0.14)
	ship.combatant.weapon.ammunition = state.ammunition
	ship.combatant.alive = state.alive
	if not state.alive:
		ship.set_eliminated()
	ship.queue_redraw()


func _emit_weapon_shot(
	owner_id: int,
	shot_sequence: int,
	position: Vector2,
	projectile: ProjectileState = null
) -> void:
	var stats := view.local_prediction.local_stats.duplicate_stats() if owner_id == view.local_peer_id else _stats_for_peer(owner_id).duplicate_stats()
	if projectile != null:
		stats.projectile_damage = projectile.damage
		stats.projectile_speed = projectile.velocity.length()
		stats.pierce_count = projectile.remaining_pierces
		stats.ricochet_count = projectile.remaining_ricochets
		stats.beam_weapon = projectile.is_beam
	var profile = WeaponSoundProfileScript.from_stats(stats, _build_for_peer(owner_id), view.card_catalog)
	view.presentation_event.emit(&"weapon_fire", {
		"profile": profile,
		"owner_id": owner_id,
		"shot_sequence": shot_sequence,
		"position": position,
		"listener_position": view.hud_camera._audio_listener_position(),
		"local": owner_id == view.local_peer_id,
	})


func _update_remote_ships() -> void:
	var now := view._now_seconds()
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if peer_id == view.local_peer_id:
			continue
		var sample := interpolation.sample(peer_id, now)
		if sample.ok:
			interpolation_sample_count += 1
			if bool(sample.extrapolated):
				interpolation_extrapolated_count += 1
			var ship := ships[peer_id] as CombatShipView
			ship.global_position = sample.position
			ship.combatant.position = sample.position
			ship.combatant.velocity = sample.velocity
			ship.combatant.aim_angle = sample.aim_angle
			ship.set_movement_field_strength(ArenaMovementSystem.influence_at(
				sample.position,
				arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID
			))
			ship.queue_redraw()


func _step_projectile_visuals(delta: float) -> void:
	for projectile_id in authoritative_projectiles.ordered_ids_view():
		if projectile_id == ProjectileRegistry.REMOVED_ID:
			continue
		var projectile := authoritative_projectiles.get_projectile(projectile_id)
		if projectile == null:
			continue
		if projectile.is_mine:
			projectile.step_mine_activation(delta)
			projectile.position += projectile.velocity * maxf(delta, 0.0)
			continue
		var safe_delta := maxf(delta, 0.0)
		projectile.lifetime_remaining -= safe_delta
		if projectile.lifetime_remaining <= 0.0:
			authoritative_projectiles.remove(projectile.projectile_id)
			continue
		var travel_remaining := projectile.velocity.length() * safe_delta
		var collision_iterations := 0
		while travel_remaining > 0.001 and collision_iterations < PROJECTILE_COLLISION_ITERATIONS:
			if authoritative_projectiles.get_projectile(projectile.projectile_id) == null or projectile.velocity.is_zero_approx():
				break
			collision_iterations += 1
			var direction := projectile.velocity.normalized()
			var start := projectile.position
			var finish := start + direction * travel_remaining
			var obstacle_hit: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(
				start,
				finish,
				projectile.radius,
				arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID
			)
			if obstacle_hit == null:
				projectile.position = finish
				break
			var collision_fraction := clampf(float(obstacle_hit.get("fraction", 0.0)), 0.0, 1.0)
			projectile.position = obstacle_hit.position as Vector2
			travel_remaining *= maxf(1.0 - collision_fraction, 0.0)
			var obstacle_normal := obstacle_hit.normal as Vector2
			if projectile.ricochet(obstacle_normal):
				view.presentation_event.emit(&"ricochet", {
					"projectile_id": projectile.projectile_id,
					"owner_id": projectile.owner_id,
					"ricochets_remaining": projectile.remaining_ricochets,
					"position": projectile.position,
					"listener_position": view.hud_camera._audio_listener_position(),
				})
				projectile.position += obstacle_normal * COLLISION_SURFACE_EPSILON
				travel_remaining = maxf(travel_remaining - COLLISION_SURFACE_EPSILON, 0.0)
				continue
			view.presentation_event.emit(&"projectile_impact", {
				"projectile_id": projectile.projectile_id,
				"owner_id": projectile.owner_id,
				"position": projectile.position,
				"listener_position": view.hud_camera._audio_listener_position(),
				"server_tick": view.latest_server_tick,
			})
			authoritative_projectiles.remove(projectile.projectile_id)
			break
	if projectile_layer != null:
		projectile_layer.visible_world_rect = view.hud_camera._visible_world_rect()
		projectile_layer.queue_redraw()
	if effects_layer != null:
		effects_layer.visible_world_rect = view.hud_camera._visible_world_rect()


func _synchronize_projectile(existing: ProjectileState, incoming: ProjectileState) -> bool:
	var newly_rebounded := incoming.has_rebounded and not existing.has_rebounded
	existing.owner_id = incoming.owner_id
	existing.position = incoming.position
	existing.velocity = incoming.velocity
	existing.damage = incoming.damage
	existing.remaining_pierces = incoming.remaining_pierces
	existing.remaining_ricochets = incoming.remaining_ricochets
	existing.lifetime_remaining = incoming.lifetime_remaining
	existing.is_beam = incoming.is_beam
	existing.is_mine = incoming.is_mine
	existing.is_missile = incoming.is_missile
	existing.mine_activation_remaining = incoming.mine_activation_remaining
	existing.has_rebounded = incoming.has_rebounded
	existing.radius = incoming.radius
	return newly_rebounded


func _emit_rebound_feedback(projectile: ProjectileState) -> void:
	if effects_layer != null:
		effects_layer.spawn_rebound(projectile.position)
	view.presentation_event.emit(&"rebound", {
		"projectile_id": projectile.projectile_id,
		"owner_id": projectile.owner_id,
		"position": projectile.position,
		"listener_position": view.hud_camera._audio_listener_position(),
		"server_tick": view.latest_server_tick,
	})


func _handle_snapshot_feedback(peer_id: int, state: Dictionary, ship: CombatShipView) -> void:
	if not presentation_states.has(peer_id):
		presentation_states[peer_id] = state.duplicate(true)
		return
	var previous := presentation_states[peer_id] as Dictionary
	var health_drop := float(previous.get("health", 0.0)) - float(state.get("health", 0.0))
	var shield_drop := float(previous.get("shield", 0.0)) - float(state.get("shield", 0.0))
	if health_drop > 0.05:
		ship.flash_damage()
		var direction := -(state.get("velocity", Vector2.ZERO) as Vector2).normalized()
		if direction.is_zero_approx():
			direction = Vector2.from_angle(float(state.get("aim_angle", 0.0)) + PI)
		if effects_layer != null:
			effects_layer.spawn_damage(state.position, direction, peer_id == view.local_peer_id)
		view.presentation_event.emit(&"damage", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
		if peer_id == view.local_peer_id:
			view.hud_camera.trigger_camera_shake(5.0, 0.16)
	if not bool(previous.get("shielding", false)) and bool(state.get("shielding", false)):
		view.presentation_event.emit(&"shield_on", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
	if shield_drop > 2.0 and bool(previous.get("shielding", false)):
		ship.flash_shield_block()
		view.presentation_event.emit(&"shield_block", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
	var depletion_threshold := (
		view.local_prediction.local_stats.shield_depletion_threshold
		if peer_id == view.local_peer_id
		else GameConstants.SHIELD_DEPLETION_THRESHOLD
	)
	if float(previous.get("shield", 0.0)) >= depletion_threshold and float(state.get("shield", 0.0)) < depletion_threshold:
		view.presentation_event.emit(&"shield_break", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
	if not bool(previous.get("kinetic_vent_active", false)) and bool(state.get("kinetic_vent_active", false)):
		if effects_layer != null:
			effects_layer.spawn_kinetic_vent(state.position)
		view.presentation_event.emit(&"kinetic_vent", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
		if peer_id == view.local_peer_id:
			view.hud_camera.trigger_camera_shake(3.0, 0.12)
	if not bool(previous.get("afterburner_active", false)) and bool(state.get("afterburner_active", false)):
		ship.flash_afterburner(ship.combatant.stats.afterburner_duration)
		if peer_id != view.local_peer_id:
			view.presentation_event.emit(&"afterburner", {
				"peer_id": peer_id,
				"server_tick": view.latest_server_tick,
				"position": state.get("position", Vector2.ZERO),
				"listener_position": view.hud_camera._audio_listener_position(),
				"local": false,
			})
	if not bool(previous.get("breakaway_active", false)) and bool(state.get("breakaway_active", false)):
		view.presentation_event.emit(&"breakaway", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
	if bool(previous.get("alive", true)) and not bool(state.get("alive", true)):
		if effects_layer != null:
			effects_layer.spawn_elimination(state.position, ship.ship_color, peer_id == view.local_peer_id)
		view.presentation_event.emit(&"elimination", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
		if peer_id == view.local_peer_id:
			view.hud_camera.trigger_camera_shake(9.0, 0.3)
	if peer_id == view.local_peer_id and int(state.get("ammunition", 0)) > int(previous.get("ammunition", 0)) + 1:
		view.presentation_event.emit(&"reload", {"peer_id": peer_id, "server_tick": view.latest_server_tick})
	presentation_states[peer_id] = state.duplicate(true)


func _update_overtime_presentation() -> void:
	if arena == null:
		return
	var overtime_tick := int(view.match_payload.get("overtime_start_tick", -1))
	var active := view.controls_enabled and overtime_tick >= 0 and view.latest_server_tick >= overtime_tick
	var center := view.match_payload.get("overtime_center", ArenaLayout.center(arena.map_id)) as Vector2
	var minimum_radius := float(view.match_payload.get("overtime_minimum_radius", GameConstants.OVERTIME_MINIMUM_RADIUS))
	var radius := OvertimeSystem.initial_radius(center)
	if active:
		var elapsed := GameConstants.OVERTIME_START_SECONDS + float(view.latest_server_tick - overtime_tick) / GameConstants.PHYSICS_TICKS_PER_SECOND
		radius = OvertimeSystem.radius_at(elapsed, center, minimum_radius)
	arena.set_overtime(active, radius, center)


func _player_color(peer_id: int) -> Color:
	var player := _player_identity(peer_id)
	if not player.is_empty():
		return Color.from_string("#%s" % String(player.get("ship_color", "42e8ff")), Color("42e8ff"))
	return Color("42e8ff")


func _player_pattern(peer_id: int) -> StringName:
	var player := _player_identity(peer_id)
	if not player.is_empty():
		var pattern := ShipAppearanceScript.normalized_pattern(String(player.get("ship_pattern", ShipAppearanceScript.SOLID)))
		return pattern if not pattern.is_empty() else ShipAppearanceScript.SOLID
	return ShipAppearanceScript.SOLID


func team_for_peer(peer_id: int) -> int:
	if not GameModeRules.is_team_mode(int(view.match_payload.get("game_mode", 0))):
		return 0
	var teams := view.match_payload.get("teams", {}) as Dictionary
	return int(teams.get(peer_id, teams.get(str(peer_id), 0)))


func is_friendly_peer(peer_id: int) -> bool:
	var local_team := team_for_peer(view.local_peer_id)
	return peer_id == view.local_peer_id or local_team > 0 and team_for_peer(peer_id) == local_team


func _display_name(peer_id: int) -> String:
	var player := _player_identity(peer_id)
	if not player.is_empty():
		return String(player.get("display_name", "Pilot %d" % peer_id))
	return "Pilot %d" % peer_id


func _player_identity(peer_id: int) -> Dictionary:
	var identity_sources: Array = [view.match_payload.get("players", [])]
	if view.bridge != null:
		identity_sources.append(view.bridge.latest_lobby_state.get("players", []))
	for players_value in identity_sources:
		for player_value in players_value as Array:
			var player := player_value as Dictionary
			if int(player.get("peer_id", 0)) == peer_id:
				return player
	return {}


func _record_snapshot_arrival(server_tick: int, receive_time: float) -> void:
	if last_snapshot_receive_time >= 0.0:
		var expected_interval := 1.0 / GameConstants.PLAYER_SNAPSHOT_RATE
		var arrival_deviation := absf(receive_time - last_snapshot_receive_time - expected_interval)
		snapshot_jitter_ms = lerpf(snapshot_jitter_ms, arrival_deviation * 1000.0, 0.1)
	if view.latest_server_tick != 0:
		var tick_delta := (server_tick - view.latest_server_tick) & SequenceMath.UINT32_MASK
		var expected_tick_delta := GameConstants.PHYSICS_TICKS_PER_SECOND / GameConstants.PLAYER_SNAPSHOT_RATE
		if tick_delta > expected_tick_delta and tick_delta < GameConstants.PHYSICS_TICKS_PER_SECOND * 5:
			snapshot_gap_count += maxi(floori(float(tick_delta) / expected_tick_delta) - 1, 0)
	last_snapshot_receive_time = receive_time


func add_card_powerup(payload: Dictionary) -> void:
	if powerup_layer != null:
		powerup_layer.add_powerup(payload)


func collect_card_powerup(payload: Dictionary) -> void:
	if powerup_layer != null:
		powerup_layer.remove_powerup(int(payload.get("powerup_id", 0)))
	if effects_layer != null:
		var card := view.card_catalog.get_card(StringName(payload.get("card_id", &"")))
		effects_layer.spawn_impact(payload.get("position", Vector2.ZERO) as Vector2, card.rarity_color() if card != null else Color("42e8ff"))


func apply_mine_detonations(server_tick: int, events: Array) -> void:
	if server_tick + GameConstants.PHYSICS_TICKS_PER_SECOND < view.latest_server_tick:
		return
	for event in events:
		if effects_layer != null:
			effects_layer.spawn_mine_explosion(event.position as Vector2)
		var payload := (event as Dictionary).duplicate()
		payload["server_tick"] = server_tick
		payload["listener_position"] = view.hud_camera._audio_listener_position()
		view.presentation_event.emit(&"mine_detonated", payload)


func reset_session() -> void:
	for ship_value in ships.values():
		(ship_value as CombatShipView).queue_free()
	ships.clear()
	for projectile in authoritative_projectiles.all_projectiles():
		authoritative_projectiles.remove(projectile.projectile_id)
	presentation_states.clear()
	last_snapshot_receive_time = -1.0
	snapshot_jitter_ms = 0.0
	snapshot_gap_count = 0
	interpolation_sample_count = 0
	interpolation_extrapolated_count = 0
	interpolation = RemoteInterpolator.new()
	if projectile_layer != null:
		projectile_layer.set_beam_builds({}, view.card_catalog)
		projectile_layer.set_team_identity({}, 0, false)
	if effects_layer != null:
		effects_layer.clear_effects()
	if powerup_layer != null:
		powerup_layer.clear_powerups()
	if arena != null:
		arena.set_map_id(ArenaLayout.DEFAULT_MAP_ID)
		arena.set_overtime(false, OvertimeSystem.initial_radius())
		arena.set_objective({})


func create_layers() -> void:
	arena = ArenaView.new()
	arena.name = "Arena"
	view.add_child(arena)
	powerup_layer = PowerupLayerScript.new()
	powerup_layer.name = "CardPowerups"
	powerup_layer.z_index = 1
	view.add_child(powerup_layer)
	projectile_layer = ProjectileLayer.new()
	projectile_layer.registry = authoritative_projectiles
	projectile_layer.z_index = 2
	view.add_child(projectile_layer)
	effects_layer = CombatEffectsLayer.new()
	effects_layer.name = "CombatEffects"
	effects_layer.z_index = 5
	view.add_child(effects_layer)


func apply_match_state(payload: Dictionary, state_name: String) -> void:
	var payload_map_id := StringName(payload.get("map_id", ArenaLayout.DEFAULT_MAP_ID))
	if arena != null:
		arena.set_map_id(payload_map_id)
		arena.local_peer_id = view.local_peer_id
		arena.local_team_id = team_for_peer(view.local_peer_id)
		arena.pilot_names.clear()
		for player in payload.get("players", []):
			var peer_id := int(player.get("peer_id", 0))
			arena.pilot_names[peer_id] = _display_name(peer_id)
		arena.set_objective(payload.get("objective", {}) as Dictionary)
	for ship_value in ships.values():
		var ship := ship_value as CombatShipView
		ship.visible = state_name != "DRAFT"
		ship.display_name = _display_name(ship.combatant.peer_id)
		ship.set_ship_appearance(_player_color(ship.combatant.peer_id), _player_pattern(ship.combatant.peer_id))
		ship.set_team_identity(team_for_peer(ship.combatant.peer_id), team_for_peer(view.local_peer_id))
	if projectile_layer != null:
		projectile_layer.set_team_identity(view.match_payload.get("teams", {}) as Dictionary, team_for_peer(view.local_peer_id), GameModeRules.is_team_mode(int(view.match_payload.get("game_mode", 0))))
	if powerup_layer != null:
		powerup_layer.set_powerups(payload.get("powerups", []) as Array)


func remove_missing_ships(present_ids: Dictionary) -> void:
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		if not present_ids.has(peer_id):
			(ships[peer_id] as CombatShipView).queue_free()
			ships.erase(peer_id)
			interpolation.remove_peer(peer_id)
			# A cloak disappearance is not a death. Forget prior feedback as well
			# as interpolation so reappearance cannot flash stale damage/guard FX.
			presentation_states.erase(peer_id)


func apply_builds(builds: Dictionary) -> void:
	if projectile_layer != null:
		projectile_layer.set_beam_builds(builds, view.card_catalog)
	for peer_value in ships.keys():
		var peer_id := int(peer_value)
		var ship := ships[peer_id] as CombatShipView
		ship.combatant.stats = _stats_for_peer(peer_id, builds).duplicate_stats()
		ship.set_shield_build(builds.get(peer_id, builds.get(str(peer_id), {})) as Dictionary, view.card_catalog)


func _stats_for_peer(peer_id: int, builds: Dictionary = {}) -> CombatStats:
	var source_builds := builds if not builds.is_empty() else view.match_payload.get("builds", {}) as Dictionary
	var build := source_builds.get(peer_id, source_builds.get(str(peer_id), {})) as Dictionary
	return StatSystem.derive(build, view.card_catalog)


func _build_for_peer(peer_id: int) -> Dictionary:
	var builds := view.match_payload.get("builds", {}) as Dictionary
	return builds.get(peer_id, builds.get(str(peer_id), {})) as Dictionary

func reset_for_countdown() -> void:
	# New heat positions must never interpolate from the preceding heat.
	interpolation.clear()
	presentation_states.clear()
	if effects_layer != null:
		effects_layer.clear_effects()


func apply_accessibility_settings(settings: Dictionary) -> void:
	if arena != null:
		arena.set_high_contrast(bool(settings.high_contrast))
	if effects_layer != null:
		effects_layer.reduced_flashes = bool(settings.reduced_flashes)
	for ship_value in ships.values():
		var ship := ship_value as CombatShipView
		ship.high_contrast = bool(settings.high_contrast)
		ship.reduced_flashes = bool(settings.reduced_flashes)
		ship.queue_redraw()
