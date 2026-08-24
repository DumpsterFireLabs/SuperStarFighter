class_name OfflineSandbox
extends Node2D

const TARGET_COUNT: int = 5
const TARGET_COLORS: Array[Color] = [Color("ff4f78"), Color("ff9f43"), Color("b66cff"), Color("62ff9b"), Color("ffd95a")]
const CROSSHAIR_TEXTURE: Texture2D = preload("res://assets/ui/crosshair.svg")

var catalog: CardCatalog = CardCatalog.create_default()
var build: Dictionary = {}
var selected_card_index: int = 0
var derived_stats: CombatStats = CombatStats.create_base()
var player: SandboxShip
var targets: Array[SandboxShip] = []
var ships_by_id: Dictionary = {}
var projectile_registry := ProjectileRegistry.new()
var projectile_layer: SandboxProjectileLayer
var arena: SandboxArena
var camera: Camera2D
var status_label: Label
var card_label: Label
var help_label: Label
var hud_canvas: CanvasLayer
var next_projectile_id: int = 1
var heat_elapsed: float = 0.0
var overtime_debug_stage: int = 0
var targets_shielding: bool = false
var targets_firing: bool = false


func _ready() -> void:
	Input.set_custom_mouse_cursor(CROSSHAIR_TEXTURE, Input.CURSOR_ARROW, Vector2(20.0, 20.0))
	arena = SandboxArena.new()
	arena.name = "Arena"
	add_child(arena)
	projectile_layer = SandboxProjectileLayer.new()
	projectile_layer.name = "Projectiles"
	projectile_layer.registry = projectile_registry
	add_child(projectile_layer)
	_create_ships()
	_create_camera()
	_create_hud()
	_update_card_label()
	print("SSF_SANDBOX_READY=offline_combat")


func _physics_process(delta: float) -> void:
	heat_elapsed += delta
	if player.combatant.alive:
		var local_movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var aim_vector := get_global_mouse_position() - player.global_position
		var aim_angle := player.combatant.aim_angle
		if not aim_vector.is_zero_approx():
			aim_angle = aim_vector.angle()
		var movement := MovementSystem.ship_relative_to_world(local_movement, aim_angle)
		player.simulate(movement, aim_angle, Input.is_action_pressed("shield"), delta)
		if Input.is_action_pressed("fire") and player.combatant.try_fire():
			_spawn_shot(player)
	for target in targets:
		if target.combatant.alive:
			var aim_at_player := (player.global_position - target.global_position).angle()
			target.simulate(Vector2.ZERO, aim_at_player, targets_shielding, delta)
			if targets_firing and target.combatant.try_fire():
				_spawn_shot(target)
	_simulate_projectiles(delta)
	_apply_overtime_damage(delta)
	projectile_registry.step_cleanup(delta)
	projectile_layer.queue_redraw()
	_update_camera(delta)
	_update_hud()
	arena.set_overtime(OvertimeSystem.is_active(heat_elapsed), OvertimeSystem.radius_at(heat_elapsed))


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)


func set_sandbox_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if hud_canvas != null:
		hud_canvas.visible = active


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
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(510.0, 0.0)
	hud_canvas.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := Label.new()
	title.text = "SUPER STAR FIGHTER · OFFLINE COMBAT LAB"
	title.add_theme_color_override("font_color", Color("42e8ff"))
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	content.add_child(status_label)
	card_label = Label.new()
	card_label.add_theme_color_override("font_color", Color("d39cff"))
	card_label.add_theme_font_size_override("font_size", 16)
	content.add_child(card_label)
	help_label = Label.new()
	help_label.text = "W/S forward/back · A/D strafe · Mouse aim · LMB fire · RMB shield\nQ/E select card · G grant stack · C clear build\nT target shields · B target fire · Y reset heat · O start/reset overtime · Shift+O cycle · F1 help"
	help_label.add_theme_color_override("font_color", Color("aebbd4"))
	content.add_child(help_label)


func _spawn_shot(ship: SandboxShip) -> void:
	var muzzle := ship.global_position + Vector2.from_angle(ship.combatant.aim_angle) * 31.0
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


func _simulate_projectiles(delta: float) -> void:
	var damage_events: Array[Dictionary] = []
	for projectile in projectile_registry.all_projectiles():
		var start := projectile.position
		if not projectile.step(delta):
			projectile_registry.remove(projectile.projectile_id)
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
				projectile_registry.remove(projectile.projectile_id)
				continue
			if projectile.can_hit(target.combatant.peer_id):
				damage_events.append({"projectile_id": projectile.projectile_id, "target_id": target.combatant.peer_id, "damage": projectile.damage})
				if not projectile.register_hull_hit(target.combatant.peer_id):
					projectile_registry.remove(projectile.projectile_id)
				else:
					projectile.position += projectile.velocity.normalized() * 2.0
		else:
			var collision_normal: Vector2 = hit["normal"]
			if projectile.ricochet(collision_normal):
				projectile.position += projectile.velocity.normalized() * 2.0
			else:
				projectile_registry.remove(projectile.projectile_id)
	_apply_damage_events(damage_events)


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
	for peer_id in DamageResolver.resolve_tick(combatants, events):
		var eliminated := ships_by_id[peer_id] as SandboxShip
		eliminated.set_eliminated()
		projectile_registry.schedule_owner_cleanup(peer_id)


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
	status_label.text = ("HP %.1f/%.1f · Shield %.1f/%.1f%s\n" + "Ammo %d/%d%s · Projectiles %d · Alive %d/%d · %.1fs%s") % [player.combatant.health, player.combatant.stats.max_health, player.combatant.shield.energy, player.combatant.stats.shield_capacity, " LOCKED" if player.combatant.shield.depletion_locked else "", weapon.ammunition, player.combatant.stats.magazine_size, reload_text, projectile_registry.size(), alive_count, ships_by_id.size(), heat_elapsed, overtime_text]


func _update_card_label() -> void:
	var card_id := catalog.all_ids()[selected_card_index]
	var card := catalog.get_card(card_id)
	card_label.text = "Selected: %s [%d/%d] — %s" % [card.display_name, int(build.get(card_id, 0)), card.max_stacks, card.description]


func _grant_selected_card() -> void:
	var card_id := catalog.all_ids()[selected_card_index]
	var card := catalog.get_card(card_id)
	build[card_id] = mini(int(build.get(card_id, 0)) + 1, card.max_stacks)
	_apply_build()


func _apply_build() -> void:
	var health_fraction := player.combatant.health_fraction()
	derived_stats = StatSystem.derive(build, catalog)
	player.combatant.stats = derived_stats.duplicate_stats()
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
	heat_elapsed = 0.0
	overtime_debug_stage = 0


func _cycle_overtime_debug() -> void:
	overtime_debug_stage = (overtime_debug_stage + 1) % 4
	match overtime_debug_stage:
		0: heat_elapsed = 0.0
		1: heat_elapsed = 85.0
		2: heat_elapsed = 90.0
		3: heat_elapsed = 135.0


func _toggle_overtime_debug() -> void:
	heat_elapsed = next_overtime_toggle_time(heat_elapsed)
	overtime_debug_stage = 0 if heat_elapsed == 0.0 else 2


static func next_overtime_toggle_time(current_heat_elapsed: float) -> float:
	var warning_start := (
		GameConstants.OVERTIME_START_SECONDS - GameConstants.OVERTIME_WARNING_SECONDS
	)
	return 0.0 if current_heat_elapsed >= warning_start else GameConstants.OVERTIME_START_SECONDS
