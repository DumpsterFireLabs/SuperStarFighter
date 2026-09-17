class_name ArenaEffectState
extends RefCounted

# Per-world state; geometry variants are immutable and shared by mask.
const CARGO_HEALTH := 120.0
const WARNING_SECONDS := 3.0
const PULSE_SPEED := 650.0
const PULSE_LIMIT := 3600.0
const DOOR_MASK := 51 # Four horizontal barriers; the middle route stays open.
var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var settings: Dictionary = ArenaEffectRules.DEFAULT.duplicate()
var enabled := 0
var hidden_cover := 0
var cargo_health: Dictionary = {}
var elapsed := 0.0
var safe := false
var pulse_center := Vector2.ZERO
var pulse_radius := -1.0
var warning := false
var door_warning_mask := 0
var _pulse_cycle := -1
var _hit_lives: Dictionary = {}
var _grace_until: Dictionary = {}

func reset(selected_map: StringName, options: Dictionary) -> void:
	map_id = selected_map
	settings = options.duplicate()
	enabled = ArenaEffectRules.enabled(settings, map_id)
	hidden_cover = 0
	cargo_health.clear()
	elapsed = 0.0
	safe = false
	pulse_radius = -1.0
	warning = false
	door_warning_mask = 0
	_pulse_cycle = -1
	_hit_lives.clear()
	_grace_until.clear()
	if enabled & ArenaEffectRules.CARGO:
		for index in ArenaLayout.cover_rectangles(map_id).size(): cargo_health[index] = CARGO_HEALTH
	if enabled & ArenaEffectRules.DOORS: hidden_cover = DOOR_MASK

func protect_respawn(peer_id: int) -> void:
	_grace_until[peer_id] = elapsed + 3.0

func step(seconds: float, overtime_seconds: float, combatants: Dictionary) -> Array[Dictionary]:
	elapsed = maxf(seconds, 0.0)
	safe = elapsed >= maxf(overtime_seconds - 5.0, 0.0)
	var events: Array[Dictionary] = []
	warning = false
	pulse_radius = -1.0
	door_warning_mask = 0
	if enabled == 0: return events
	if safe:
		if enabled & ArenaEffectRules.DOORS: hidden_cover = DOOR_MASK
		if enabled & ArenaEffectRules.CARGO: hidden_cover = (1 << ArenaLayout.cover_rectangles(map_id).size()) - 1
		return events
	if enabled & ArenaEffectRules.DOORS:
		var phase := fmod(elapsed, ArenaEffectRules.interval(settings))
		var cycle := int(elapsed / ArenaEffectRules.interval(settings))
		var closing := 17 if cycle % 2 == 0 else 34
		# Open first, warn, then close only unoccupied doors. Never crush a ship.
		hidden_cover = DOOR_MASK
		if phase >= 3.0 and phase < 6.0: door_warning_mask = closing
		if phase >= 6.0:
			var rectangles := ArenaLayout.cover_rectangles(map_id)
			for index in rectangles.size():
				if not (closing & (1 << index)): continue
				var occupied := false
				for value in combatants.values():
					var ship := value as CombatantState
					if ship.alive and rectangles[index].grow(GameConstants.SHIP_COLLISION_RADIUS + 8.0).has_point(ship.position): occupied = true
				if occupied: door_warning_mask |= 1 << index
				else: hidden_cover &= ~(1 << index)
	if not (enabled & ArenaEffectRules.SOLAR) or elapsed < 3.0: return events
	var interval := ArenaEffectRules.interval(settings)
	var cycle := int((elapsed - 3.0) / interval)
	var phase := fmod(elapsed - 3.0, interval)
	var circles := ArenaLayout.circle_obstacles(map_id)
	if circles.is_empty(): return events
	var source := circles[cycle % circles.size()]
	pulse_center = source.center
	if cycle != _pulse_cycle:
		_pulse_cycle = cycle
		_hit_lives.clear()
	warning = phase < WARNING_SECONDS
	if warning: return events
	var radius := float(source.radius) + (phase - WARNING_SECONDS) * PULSE_SPEED
	if radius > PULSE_LIMIT: return events
	pulse_radius = radius
	for value in combatants.values():
		var ship := value as CombatantState
		if not ship.alive: continue
		var key := Vector2i(ship.peer_id, ship.life_generation)
		if _hit_lives.has(key) or ship.position.distance_to(pulse_center) > radius: continue
		_hit_lives[key] = true
		if elapsed < float(_grace_until.get(ship.peer_id, 0.0)): continue
		var direction := (ship.position - pulse_center).normalized()
		# Start outside the emitting reactor so it does not block its own wave.
		var start := pulse_center + direction * (float(source.radius) + 1.0)
		if not ArenaCollisionSystem.has_clear_line_of_sight(start, ship.position, map_id, hidden_cover): continue
		if ship.shield.try_block(ship.aim_angle, -direction, ship.stats): continue
		ship.velocity = (ship.velocity + direction * 150.0).limit_length(maxf(ship.velocity.length(), ship.stats.max_speed))
		events.append({"target_id": ship.peer_id, "damage": ArenaEffectRules.damage(settings), "source": "solar_pulse"})
	return events

func damage_cover(position: Vector2, radius: float, damage: float) -> bool:
	if not (enabled & ArenaEffectRules.CARGO) or safe or damage <= 0.0: return false
	var rectangles := ArenaLayout.cover_rectangles(map_id)
	for index in rectangles.size():
		if hidden_cover & (1 << index): continue
		if not rectangles[index].grow(radius + 1.0).has_point(position): continue
		cargo_health[index] = maxf(float(cargo_health[index]) - damage, 0.0)
		if float(cargo_health[index]) == 0.0: hidden_cover |= 1 << index
		return true
	return false

func snapshot() -> Dictionary:
	return {"enabled": enabled, "hidden_cover": hidden_cover, "cargo_health": cargo_health.duplicate(), "elapsed": elapsed, "safe": safe, "pulse_center": pulse_center, "pulse_radius": pulse_radius, "warning": warning, "door_warning_mask": door_warning_mask}
