class_name OfflineSandbox
extends Node2D

const InputProfileManagerScript = preload("res://src/client/input/input_profile_manager.gd")
const KillFeedScript = preload("res://src/client/ui/kill_feed.gd")
const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")
const TARGET_COUNT: int = 5
const TARGET_COLORS: Array[Color] = [Color("ff4f78"), Color("ff9f43"), Color("b66cff"), Color("62ff9b"), Color("ffd95a")]
signal presentation_event(event_name: StringName, payload: Dictionary)

var catalog: CardCatalog = CardCatalog.create_default()
var build: Dictionary = {}
var selected_card_index: int = 0
var derived_stats: CombatStats = CombatStats.create_base()
var player: SandboxShip
var targets: Array[SandboxShip] = []
var ships_by_id: Dictionary = {}
var projectile_registry := ProjectileRegistry.new()
var projectile_layer: SandboxProjectileLayer
var effects_layer: CombatEffectsLayer
var arena: SandboxArena
var camera: Camera2D
var status_label: Label
var card_label: Label
var help_label: Label
var hud_canvas: CanvasLayer
var kill_feed: Control
var next_projectile_id: int = 1
var kill_feed_event_sequence: int = 0
var heat_elapsed: float = 0.0
var overtime_debug_stage: int = 0
var targets_shielding: bool = false
var targets_firing: bool = false
var input_profiles: Node
var camera_kick_remaining: float = 0.0
var camera_kick_duration: float = 0.0
var camera_kick_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	arena = SandboxArena.new()
	arena.name = "Arena"
	add_child(arena)
	projectile_layer = SandboxProjectileLayer.new()
	projectile_layer.name = "Projectiles"
	projectile_layer.registry = projectile_registry
	add_child(projectile_layer)
	effects_layer = CombatEffectsLayer.new()
	effects_layer.name = "CombatEffects"
	effects_layer.z_index = 5
	add_child(effects_layer)
	_create_ships()
	_create_camera()
	_create_hud()
	_update_card_label()
	print("SSF_SANDBOX_READY=offline_combat")


func _physics_process(delta: float) -> void:
	heat_elapsed += delta
	if player.combatant.alive:
		var aim_vector: Vector2 = input_profiles.aim_vector() if input_profiles != null and input_profiles.uses_controller() else get_global_mouse_position() - player.global_position
		var aim_angle := player.combatant.aim_angle
		if not aim_vector.is_zero_approx():
			aim_angle = aim_vector.angle()
		var ship_movement: Vector2 = input_profiles.movement_input_for_aim(aim_angle) if input_profiles != null else Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var movement := MovementSystem.ship_relative_to_world(ship_movement, aim_angle)
		player.set_thrust_input(ship_movement)
		player.simulate(movement, aim_angle, Input.is_action_pressed("shield"), delta)
		if Input.is_action_just_pressed("special"):
			if player.combatant.activate_special():
				player.velocity = player.combatant.velocity
				player.flash_afterburner(player.combatant.stats.afterburner_duration)
				_trigger_afterburner_feedback(Vector2.from_angle(aim_angle))
				presentation_event.emit(&"afterburner", {
					"peer_id": player.combatant.peer_id,
					"server_tick": roundi(heat_elapsed * GameConstants.PHYSICS_TICKS_PER_SECOND),
					"position": player.global_position,
					"listener_position": player.global_position,
					"local": true,
				})
			if player.combatant.deploy_mine():
				_spawn_mine(player.combatant)
			player.combatant.activate_cloak()
		elif not Input.is_action_pressed("special"):
			player.combatant.release_special_activation()
		if Input.is_action_pressed("manual_reload"):
			player.combatant.request_reload()
		if Input.is_action_pressed("fire") and player.combatant.try_fire():
			_spawn_shot(player)
	else:
		player.set_thrust_input(Vector2.ZERO)
	for target in targets:
		if target.combatant.alive:
			var aim_at_player := (player.global_position - target.global_position).angle()
			target.simulate(Vector2.ZERO, aim_at_player, targets_shielding, delta)
			if targets_firing and not player.combatant.is_cloaked() and target.combatant.try_fire():
				_spawn_shot(target)
	_resolve_sandbox_kinetic_vents()
	_simulate_projectiles(delta)
	_apply_overtime_damage(delta)
	projectile_registry.step_cleanup(delta)
	projectile_layer.queue_redraw()
	_update_camera(delta)
	_update_hud()
	arena.set_overtime(OvertimeSystem.is_active(heat_elapsed), OvertimeSystem.radius_at(heat_elapsed))


func set_sandbox_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if camera != null:
		camera.enabled = active
	if hud_canvas != null:
		hud_canvas.visible = active
	if not active and kill_feed != null:
		kill_feed.clear()


func set_input_profile_manager(profile_manager: Node) -> void:
	input_profiles = profile_manager
	if not input_profiles.scheme_changed.is_connected(_on_input_profile_changed):
		input_profiles.scheme_changed.connect(_on_input_profile_changed)
	if not input_profiles.bindings_changed.is_connected(_on_input_bindings_changed):
		input_profiles.bindings_changed.connect(_on_input_bindings_changed)
	_update_help_text()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_Q:
			selected_card_index = wrapi(selected_card_index - 1, 0, catalog.size())
			_update_card_label()
		KEY_E:
			selected_card_index = wrapi(selected_card_index + 1, 0, catalog.size())
			_update_card_label()
		KEY_G:
			_grant_selected_card()
		KEY_C:
			build.clear()
			_apply_build()
		KEY_T:
			targets_shielding = not targets_shielding
		KEY_B:
			targets_firing = not targets_firing
		KEY_Y:
			_reset_combatants()
		KEY_O:
			if event.shift_pressed:
				_cycle_overtime_debug()
			else:
				_toggle_overtime_debug()
		KEY_F1:
			help_label.visible = not help_label.visible


func _create_ships() -> void:
	var anchors := ArenaLayout.spawn_anchors()
	player = SandboxShip.new()
	player.setup(1, derived_stats, anchors[0], Color("42e8ff"), true)
	add_child(player)
	ships_by_id[player.combatant.peer_id] = player
	for index in TARGET_COUNT:
		var target := SandboxShip.new()
		target.setup(index + 2, CombatStats.create_base(), anchors[12 + index * 3], TARGET_COLORS[index])
		add_child(target)
		targets.append(target)
		ships_by_id[target.combatant.peer_id] = target


func _create_camera() -> void:
	camera = Camera2D.new()
	camera.name = "FollowCamera"
	camera.position = player.global_position
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameConstants.ARENA_SIZE.x)
	camera.limit_bottom = int(GameConstants.ARENA_SIZE.y)
	camera.limit_smoothed = true
	camera.enabled = true
	add_child(camera)


func _create_hud() -> void:
	hud_canvas = CanvasLayer.new()
	hud_canvas.name = "CombatHUD"
	add_child(hud_canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(26.0, 24.0)
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	hud_canvas.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := Label.new()
	title.text = "SUPER STAR FIGHTER · OFFLINE COMBAT LAB"
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 20)
	content.add_child(status_label)
	card_label = Label.new()
	card_label.add_theme_font_size_override("font_size", 20)
	content.add_child(card_label)
	help_label = Label.new()
	_update_help_text()
	help_label.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(help_label)
	kill_feed = KillFeedScript.new()
	kill_feed.name = "KillFeed"
	hud_canvas.add_child(kill_feed)
	kill_feed.set_match_state("ACTIVE_HEAT")


func _update_help_text() -> void:
	if help_label == null:
		return
	var combat_help := "W/S forward/back · A/D strafe · Mouse aim · LMB fire · RMB shield"
	if input_profiles != null:
		var aim_help := "Mouse"
		if input_profiles.uses_controller():
			aim_help = "%s/%s/%s/%s" % [
				input_profiles.binding_text(&"aim_up"),
				input_profiles.binding_text(&"aim_down"),
				input_profiles.binding_text(&"aim_left"),
				input_profiles.binding_text(&"aim_right"),
			]
		combat_help = "%s/%s forward/back · %s/%s strafe · %s aim · %s fire · %s shield" % [
			input_profiles.binding_text(&"move_up"),
			input_profiles.binding_text(&"move_down"),
			input_profiles.binding_text(&"move_left"),
			input_profiles.binding_text(&"move_right"),
			aim_help,
			input_profiles.binding_text(&"fire"),
			input_profiles.binding_text(&"shield"),
		]
	var special_help: String = input_profiles.binding_text(&"special") if input_profiles != null else "Shift"
	help_label.text = "%s · %s special\nQ/E select card · G grant stack · C clear build\nT target shields · B target fire · Y reset heat · O start/reset overtime · Shift+O cycle · F1 help" % [combat_help, special_help]


func _on_input_profile_changed(_scheme: int) -> void:
	_update_help_text()


func _on_input_bindings_changed() -> void:
	_update_help_text()


func _spawn_shot(ship: SandboxShip) -> void:
	var muzzle := ship.global_position + Vector2.from_angle(ship.combatant.aim_angle) * 31.0
	var audio_sequence := next_projectile_id
	var spawned_any := false
	for angle in MovementSystem.spread_angles(ship.combatant.aim_angle, ship.combatant.stats.projectile_count, ship.combatant.stats.projectile_spread_degrees):
		var projectile := ProjectileState.create(next_projectile_id, ship.combatant.peer_id, ship.combatant.weapon.shot_sequence, muzzle, angle, ship.combatant.stats)
		next_projectile_id += 1
		var spawn_normal := ArenaCollisionSystem.projectile_obstacle_normal(
			projectile.position,
			projectile.radius
		)
		if not spawn_normal.is_zero_approx():
			if not projectile.ricochet(spawn_normal):
				continue
			projectile.position = ship.global_position + spawn_normal * (
				GameConstants.SHIP_COLLISION_RADIUS + projectile.radius + 1.0
			)
		projectile_registry.add(projectile)
		spawned_any = true
	if spawned_any:
		var source_build := build if ship == player else {}
		presentation_event.emit(&"weapon_fire", {
			"profile": WeaponSoundProfileScript.from_stats(ship.combatant.stats, source_build, catalog),
			"owner_id": ship.combatant.peer_id,
			"shot_sequence": audio_sequence,
			"position": muzzle,
			"listener_position": player.global_position,
			"local": ship == player,
		})


func _spawn_mine(combatant: CombatantState) -> void:
	var mine := ProjectileState.create_mine(next_projectile_id, combatant.peer_id, combatant.position)
	next_projectile_id += 1
	projectile_registry.add(mine)


func _simulate_projectiles(delta: float) -> void:
	var damage_events: Array[Dictionary] = []
	_step_mine_magnetism(delta)
	_detonate_proximity_mines(damage_events)
	for projectile in projectile_registry.all_projectiles():
		if projectile.is_mine:
			continue
		var start := projectile.position
		if not projectile.step(delta):
			projectile_registry.remove(projectile.projectile_id)
			continue
		var mine := _nearest_sandbox_mine(start, projectile.position, projectile)
		if mine != null:
			projectile_registry.remove(projectile.projectile_id)
			_detonate_sandbox_mine(mine, damage_events)
			continue
		var query := PhysicsRayQueryParameters2D.create(start, projectile.position, 3)
		var exclusions: Array[RID] = []
		var owner_ship := ships_by_id.get(projectile.owner_id) as SandboxShip
		if owner_ship != null:
			exclusions.append(owner_ship.get_rid())
		for hit_value in projectile.hit_peer_ids:
			var hit_ship := ships_by_id.get(int(hit_value)) as SandboxShip
			if hit_ship != null:
				exclusions.append(hit_ship.get_rid())
		query.exclude = exclusions
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var impact_position: Vector2 = hit["position"]
		projectile.position = impact_position
		var collider := hit["collider"] as CollisionObject2D
		if collider is SandboxShip:
			var target := collider as SandboxShip
			if target.combatant.shield.try_block(target.combatant.aim_angle, impact_position - target.global_position, target.combatant.stats):
				target.combatant.shield.register_blocked_damage(projectile.damage, target.combatant.stats)
				_apply_projectile_knockback(target.combatant, projectile, 0.2)
				if target.combatant.stats.shield_damage_heal_fraction > 0.0:
					target.combatant.health = minf(
						target.combatant.health + projectile.damage * target.combatant.stats.shield_damage_heal_fraction,
						target.combatant.stats.max_health
					)
				var rebounded := false
				if target.combatant.stats.rebound_shield_enabled and not projectile.has_rebounded:
					var source_position := owner_ship.global_position if owner_ship != null else projectile.position - projectile.velocity
					var old_owner_id := projectile.owner_id
					if projectile.rebound_toward(target.combatant.peer_id, source_position):
						projectile.owner_id = old_owner_id
						projectile_registry.transfer_owner(projectile.projectile_id, target.combatant.peer_id)
						rebounded = projectile_registry.get_projectile(projectile.projectile_id) != null
				if rebounded:
					projectile.position += projectile.velocity.normalized() * 2.0
				else:
					projectile_registry.remove(projectile.projectile_id)
				presentation_event.emit(&"shield_block", {
					"peer_id": target.combatant.peer_id,
					"projectile_id": projectile.projectile_id,
					"position": impact_position,
					"listener_position": player.global_position,
				})
				if rebounded:
					presentation_event.emit(&"rebound", {
						"projectile_id": projectile.projectile_id,
						"owner_id": projectile.owner_id,
						"position": impact_position,
						"listener_position": player.global_position,
					})
				continue
			if projectile.can_hit(target.combatant.peer_id):
				_apply_projectile_knockback(target.combatant, projectile, 1.0)
				damage_events.append({"projectile_id": projectile.projectile_id, "attacker_id": projectile.owner_id, "target_id": target.combatant.peer_id, "damage": projectile.damage})
				if not projectile.register_hull_hit(target.combatant.peer_id):
					projectile_registry.remove(projectile.projectile_id)
				else:
					projectile.position += projectile.velocity.normalized() * 2.0
		else:
			var collision_normal: Vector2 = hit["normal"]
			if projectile.ricochet(collision_normal):
				presentation_event.emit(&"ricochet", {
					"projectile_id": projectile.projectile_id,
					"owner_id": projectile.owner_id,
					"ricochets_remaining": projectile.remaining_ricochets,
					"position": impact_position,
					"listener_position": player.global_position,
				})
				projectile.position += projectile.velocity.normalized() * 2.0
			else:
				presentation_event.emit(&"projectile_impact", {
					"projectile_id": projectile.projectile_id,
					"owner_id": projectile.owner_id,
					"position": impact_position,
					"listener_position": player.global_position,
				})
				projectile_registry.remove(projectile.projectile_id)
	_apply_damage_events(damage_events)
	for projectile in projectile_registry.all_projectiles():
		projectile.step_mine_activation(delta)


func _step_mine_magnetism(delta: float) -> void:
	for mine in projectile_registry.all_projectiles():
		if not mine.is_mine_armed():
			continue
		var displaced_by_vent := mine.step_kinetic_vent_displacement(delta)
		if not displaced_by_vent:
			var nearest: SandboxShip
			var nearest_distance_squared := GameConstants.MINE_MAGNETIC_RADIUS * GameConstants.MINE_MAGNETIC_RADIUS
			for ship_value in ships_by_id.values():
				var ship := ship_value as SandboxShip
				if not ship.combatant.alive or ship.combatant.peer_id == mine.owner_id:
					continue
				var distance_squared := ship.global_position.distance_squared_to(mine.position)
				if distance_squared > nearest_distance_squared:
					continue
				if nearest != null and is_equal_approx(distance_squared, nearest_distance_squared) and ship.combatant.peer_id > nearest.combatant.peer_id:
					continue
				nearest = ship
				nearest_distance_squared = distance_squared
			if nearest == null:
				mine.velocity = Vector2.ZERO
				continue
			var offset := nearest.global_position - mine.position
			if offset.is_zero_approx():
				mine.velocity = Vector2.ZERO
				continue
			mine.velocity = offset.normalized() * GameConstants.MINE_MAGNETIC_SPEED
		var finish := mine.position + mine.velocity * maxf(delta, 0.0)
		var obstacle_hit: Variant = ArenaCollisionSystem.projectile_obstacle_sweep_hit(
			mine.position,
			finish,
			mine.radius
		)
		if obstacle_hit == null:
			mine.position = finish
		else:
			mine.position = obstacle_hit.position as Vector2
			mine.velocity = Vector2.ZERO
			mine.kinetic_vent_displacement_remaining = 0.0


func _resolve_sandbox_kinetic_vents() -> void:
	var active_map_id := arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID
	for source_value in ships_by_id.values():
		var source := source_value as SandboxShip
		if not source.combatant.alive:
			continue
		var charge := source.combatant.shield.consume_kinetic_vent_release()
		if charge < GameConstants.KINETIC_VENT_MINIMUM_CHARGE:
			continue
		source.combatant.mark_kinetic_vent_release()
		if effects_layer != null:
			effects_layer.spawn_kinetic_vent(source.global_position)
		presentation_event.emit(&"kinetic_vent", {
			"peer_id": source.combatant.peer_id,
			"position": source.global_position,
			"listener_position": player.global_position,
		})
		var charge_fraction := clampf(charge / GameConstants.KINETIC_VENT_MAXIMUM_CHARGE, 0.0, 1.0)
		var impulse := source.combatant.stats.kinetic_vent_impulse * lerpf(0.65, 1.0, charge_fraction)
		for target_value in ships_by_id.values():
			var target := target_value as SandboxShip
			if target == source or not target.combatant.alive or target.global_position.distance_to(source.global_position) > GameConstants.KINETIC_VENT_RADIUS:
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(source.global_position, target.global_position, active_map_id):
				continue
			var outward := target.global_position - source.global_position
			if outward.is_zero_approx():
				outward = Vector2.from_angle(source.combatant.aim_angle)
			target.combatant.velocity = (target.combatant.velocity + outward.normalized() * impulse).limit_length(
				maxf(target.combatant.stats.max_speed * 2.5, 1.0)
			)
			target.velocity = target.combatant.velocity
		for projectile in projectile_registry.all_projectiles():
			if projectile.owner_id == source.combatant.peer_id or projectile.position.distance_to(source.global_position) > GameConstants.KINETIC_VENT_RADIUS:
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(source.global_position, projectile.position, active_map_id):
				continue
			var outward := projectile.position - source.global_position
			if outward.is_zero_approx():
				outward = Vector2.from_angle(source.combatant.aim_angle)
			if projectile.is_mine:
				projectile.apply_kinetic_vent(outward, impulse)
			elif not projectile.velocity.is_zero_approx():
				projectile.velocity = outward.normalized() * projectile.velocity.length()


func _detonate_proximity_mines(damage_events: Array[Dictionary]) -> void:
	for projectile in projectile_registry.all_projectiles():
		if not projectile.is_mine_armed():
			continue
		for ship_value in ships_by_id.values():
			var ship := ship_value as SandboxShip
			if not ship.combatant.alive or ship.combatant.peer_id == projectile.owner_id:
				continue
			if ship.global_position.distance_to(projectile.position) <= GameConstants.MINE_TRIGGER_RADIUS + GameConstants.SHIP_COLLISION_RADIUS:
				_detonate_sandbox_mine(projectile, damage_events)
				break


func _nearest_sandbox_mine(start: Vector2, finish: Vector2, projectile: ProjectileState) -> ProjectileState:
	var nearest: ProjectileState
	var nearest_fraction := INF
	for candidate in projectile_registry.all_projectiles():
		if not candidate.is_mine_armed():
			continue
		var fraction := AuthoritativeWorld._segment_circle_hit_fraction(
			start,
			finish,
			candidate.position,
			candidate.radius + projectile.radius
		)
		if fraction >= 0.0 and fraction < nearest_fraction:
			nearest = candidate
			nearest_fraction = fraction
	return nearest


func _detonate_sandbox_mine(mine: ProjectileState, damage_events: Array[Dictionary]) -> void:
	if mine == null or not mine.is_mine_armed() or projectile_registry.get_projectile(mine.projectile_id) == null:
		return
	var active_map_id := arena.map_id if arena != null else ArenaLayout.DEFAULT_MAP_ID
	var pending: Array[int] = [mine.projectile_id]
	var queued: Dictionary = {}
	queued[mine.projectile_id] = true
	while not pending.is_empty():
		var current_id: int = pending.pop_front()
		var current := projectile_registry.get_projectile(current_id)
		if current == null or not current.is_mine_armed():
			continue
		projectile_registry.remove(current.projectile_id)
		if effects_layer != null:
			effects_layer.spawn_mine_explosion(current.position)
		presentation_event.emit(&"mine_detonated", {
			"projectile_id": current.projectile_id,
			"owner_id": current.owner_id,
			"position": current.position,
			"listener_position": player.global_position,
		})
		for ship_value in ships_by_id.values():
			var ship := ship_value as SandboxShip
			if not ship.combatant.alive or ship.combatant.peer_id == current.owner_id:
				continue
			if ship.global_position.distance_to(current.position) <= GameConstants.MINE_BLAST_RADIUS + GameConstants.SHIP_COLLISION_RADIUS:
				if not ArenaCollisionSystem.has_clear_line_of_sight(current.position, ship.global_position, active_map_id):
					continue
				damage_events.append({
					"projectile_id": current.projectile_id,
					"attacker_id": current.owner_id,
					"target_id": ship.combatant.peer_id,
					"damage": current.damage,
				})
		for candidate in projectile_registry.all_projectiles():
			if queued.has(candidate.projectile_id) or not candidate.is_mine_armed():
				continue
			if candidate.position.distance_to(current.position) > GameConstants.MINE_BLAST_RADIUS + candidate.radius:
				continue
			if not ArenaCollisionSystem.has_clear_line_of_sight(current.position, candidate.position, active_map_id):
				continue
			queued[candidate.projectile_id] = true
			pending.append(candidate.projectile_id)


func _apply_projectile_knockback(target: CombatantState, projectile: ProjectileState, factor: float) -> void:
	if projectile.knockback <= 0.0 or projectile.velocity.is_zero_approx():
		return
	target.velocity = (
		target.velocity + projectile.velocity.normalized() * projectile.knockback * maxf(factor, 0.0)
	).limit_length(maxf(target.stats.max_speed * 2.5, 1.0))


func _apply_overtime_damage(delta: float) -> void:
	if not OvertimeSystem.is_active(heat_elapsed):
		return
	var damage_events: Array[Dictionary] = []
	for ship_value in ships_by_id.values():
		var ship := ship_value as SandboxShip
		if ship.combatant.alive:
			var damage := OvertimeSystem.damage_for_position(ship.global_position, heat_elapsed, delta)
			if damage > 0.0:
				damage_events.append({"projectile_id": 2_000_000_000 + ship.combatant.peer_id, "target_id": ship.combatant.peer_id, "damage": damage})
	_apply_damage_events(damage_events)


func _apply_damage_events(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	var combatants: Dictionary = {}
	for ship_value in ships_by_id.values():
		var ship := ship_value as SandboxShip
		combatants[ship.combatant.peer_id] = ship.combatant
	var eliminations: Array[Dictionary] = []
	for death in DamageResolver.resolve_tick_with_attribution(combatants, events):
		var victim_id := int(death.get("target_id", 0))
		var killer_id := int(death.get("killer_id", 0))
		var eliminated := ships_by_id[victim_id] as SandboxShip
		eliminated.set_eliminated()
		projectile_registry.schedule_owner_cleanup(victim_id)
		eliminations.append({
			"killer_id": killer_id,
			"victim_id": victim_id,
			"reason": "combat" if killer_id != 0 else "environment",
		})
	if not eliminations.is_empty() and kill_feed != null:
		kill_feed_event_sequence += 1
		kill_feed.add_eliminations(
			eliminations,
			kill_feed_event_sequence,
			player.combatant.peer_id,
			_kill_feed_identities()
		)


func _kill_feed_identities() -> Array[Dictionary]:
	var identities: Array[Dictionary] = []
	var peer_ids := ships_by_id.keys()
	peer_ids.sort()
	for peer_value in peer_ids:
		var ship := ships_by_id[peer_value] as SandboxShip
		identities.append({
			"peer_id": ship.combatant.peer_id,
			"display_name": ship.display_name,
			"ship_color": ship.ship_color.to_html(false),
		})
	return identities


func _update_camera(delta: float) -> void:
	var target_position := ArenaLayout.center()
	if player.combatant.alive:
		target_position = player.global_position
	else:
		for target in targets:
			if target.combatant.alive:
				target_position = target.global_position
				break
	camera.position = camera.position.lerp(target_position, 1.0 - exp(-8.0 * delta))
	if camera_kick_remaining > 0.0:
		var fraction := clampf(camera_kick_remaining / maxf(camera_kick_duration, 0.001), 0.0, 1.0)
		camera.offset = camera_kick_offset * fraction * fraction
		camera_kick_remaining = maxf(camera_kick_remaining - maxf(delta, 0.0), 0.0)
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))


func _trigger_afterburner_feedback(forward: Vector2) -> void:
	var direction := forward.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	camera_kick_duration = 0.18
	camera_kick_remaining = camera_kick_duration
	camera_kick_offset = -direction * 5.5


func _update_hud() -> void:
	var weapon := player.combatant.weapon
	var reload_text := " · RELOAD %.2fs" % weapon.reload_remaining if weapon.reloading else ""
	var overtime_text := ""
	if OvertimeSystem.is_warning(heat_elapsed):
		overtime_text = "\nOVERTIME IN %.1fs" % (GameConstants.OVERTIME_START_SECONDS - heat_elapsed)
	elif OvertimeSystem.is_active(heat_elapsed):
		overtime_text = "\nOVERTIME · radius %.0f · damage %.0f/s" % [OvertimeSystem.radius_at(heat_elapsed), OvertimeSystem.damage_rate_at(heat_elapsed)]
	var alive_count := 0
	for ship_value in ships_by_id.values():
		if (ship_value as SandboxShip).combatant.alive:
			alive_count += 1
	var sound_profile = WeaponSoundProfileScript.from_stats(derived_stats, build, catalog)
	var mine_text := ""
	if player.combatant.stats.mine_layer_enabled:
		mine_text = " · Mines %d" % player.combatant.mine_charges_remaining
		if player.combatant.mine_cooldown_remaining > 0.05:
			mine_text += " (%.1fs)" % player.combatant.mine_cooldown_remaining
	var cloak_text := ""
	if player.combatant.stats.cloak_enabled:
		cloak_text = " · Cloak %s" % ("ACTIVE" if player.combatant.is_cloaked() else str(player.combatant.cloak_charges_remaining))
		if not player.combatant.is_cloaked() and player.combatant.cloak_cooldown_remaining > 0.05:
			cloak_text += " (%.1fs)" % player.combatant.cloak_cooldown_remaining
	var vent_text := ""
	if player.combatant.stats.kinetic_vent_enabled:
		vent_text = " · Vent %.0f/%.0f" % [player.combatant.shield.kinetic_vent_charge, GameConstants.KINETIC_VENT_MAXIMUM_CHARGE]
	status_label.text = ("HP %.1f/%.1f · Shield %.1f/%.1f%s\n" + "Ammo %d/%d%s%s%s%s · Projectiles %d · Alive %d/%d · %.1fs%s\n" + "Weapon Audio · %s / %s") % [player.combatant.health, player.combatant.stats.max_health, player.combatant.shield.energy, player.combatant.stats.shield_capacity, " LOCKED" if player.combatant.shield.depletion_locked else "", weapon.ammunition, player.combatant.stats.magazine_size, reload_text, mine_text, cloak_text, vent_text, projectile_registry.size(), alive_count, ships_by_id.size(), heat_elapsed, overtime_text, sound_profile.display_name(), sound_profile.power_tier_name()]


func _update_card_label() -> void:
	var card_id := catalog.all_ids()[selected_card_index]
	var card := catalog.get_card(card_id)
	card_label.text = "Selected: %s [STACK %d] — %s" % [card.display_name, int(build.get(card_id, 0)), card.description]
	card_label.add_theme_color_override("font_color", card.rarity_color())


func _grant_selected_card() -> void:
	var card_id := catalog.all_ids()[selected_card_index]
	var card := catalog.get_card(card_id)
	build[card_id] = int(build.get(card_id, 0)) + 1
	_apply_build()


func _apply_build() -> void:
	var health_fraction := player.combatant.health_fraction()
	var previous_mine_capacity := player.combatant.stats.mine_capacity
	var previous_cloak_capacity := player.combatant.stats.cloak_capacity
	derived_stats = StatSystem.derive(build, catalog)
	projectile_layer.set_beam_builds({player.combatant.peer_id: build}, catalog)
	player.combatant.stats = derived_stats.duplicate_stats()
	if derived_stats.mine_capacity > previous_mine_capacity:
		player.combatant.mine_charges_remaining += derived_stats.mine_capacity - previous_mine_capacity
	if derived_stats.cloak_capacity > previous_cloak_capacity:
		player.combatant.cloak_charges_remaining += derived_stats.cloak_capacity - previous_cloak_capacity
	player.combatant.cloak_charges_remaining = mini(player.combatant.cloak_charges_remaining, derived_stats.cloak_capacity)
	player.combatant.health = derived_stats.max_health * health_fraction
	player.combatant.shield.energy = minf(player.combatant.shield.energy, derived_stats.shield_capacity)
	player.combatant.weapon.ammunition = mini(player.combatant.weapon.ammunition, derived_stats.magazine_size)
	_update_card_label()


func _reset_combatants() -> void:
	var anchors := ArenaLayout.spawn_anchors()
	player.reset_ship(derived_stats, anchors[0])
	for index in targets.size():
		targets[index].reset_ship(CombatStats.create_base(), anchors[12 + index * 3])
	for projectile in projectile_registry.all_projectiles():
		projectile_registry.remove(projectile.projectile_id)
	if effects_layer != null:
		effects_layer.clear_effects()
	if kill_feed != null:
		kill_feed.clear()
	kill_feed_event_sequence = 0
	heat_elapsed = 0.0
	overtime_debug_stage = 0


func _cycle_overtime_debug() -> void:
	overtime_debug_stage = (overtime_debug_stage + 1) % 4
	match overtime_debug_stage:
		0: heat_elapsed = 0.0
		1: heat_elapsed = GameConstants.OVERTIME_START_SECONDS - GameConstants.OVERTIME_WARNING_SECONDS
		2: heat_elapsed = GameConstants.OVERTIME_START_SECONDS
		3: heat_elapsed = GameConstants.OVERTIME_START_SECONDS + GameConstants.OVERTIME_SHRINK_SECONDS


func _toggle_overtime_debug() -> void:
	heat_elapsed = next_overtime_toggle_time(heat_elapsed)
	overtime_debug_stage = 0 if heat_elapsed == 0.0 else 2


static func next_overtime_toggle_time(current_heat_elapsed: float) -> float:
	var warning_start := (
		GameConstants.OVERTIME_START_SECONDS - GameConstants.OVERTIME_WARNING_SECONDS
	)
	return 0.0 if current_heat_elapsed >= warning_start else GameConstants.OVERTIME_START_SECONDS
