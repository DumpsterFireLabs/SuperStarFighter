class_name CardPowerupSystem
extends RefCounted

const DEFAULT_SPAWN_INTERVAL_SECONDS: float = 20.0
const SPAWN_INTERVAL_SECONDS: float = DEFAULT_SPAWN_INTERVAL_SECONDS
const POWERUP_RADIUS: float = 26.0
const SPAWN_MARGIN: float = 90.0
const SHIP_CLEARANCE: float = 180.0
const MAX_POSITION_ATTEMPTS: int = 64
const MAX_ACTIVE_POWERUPS: int = 8
const PICKUP_LIFETIME_SECONDS: float = 60.0

var enabled: bool = false
var map_id: StringName = ArenaLayout.DEFAULT_MAP_ID
var next_spawn_tick: int = -1
var next_powerup_id: int = 1
var active_powerups: Dictionary = {}
var spawn_interval_seconds: float = DEFAULT_SPAWN_INTERVAL_SECONDS
var permanent_drops: bool = false
var _current_tick: int = 0
var _safe_center: Vector2 = GameConstants.ARENA_SIZE * 0.5
var _safe_radius: float = INF

var _catalog: CardCatalog
var _rng := RandomNumberGenerator.new()


func _init(catalog: CardCatalog = null, seed_value: int = 1) -> void:
	_catalog = catalog if catalog != null else CardCatalog.create_default()
	_rng.seed = seed_value ^ 0x504F_5745


func begin_heat(
	start_tick: int,
	selected_map_id: StringName,
	powerups_enabled: bool,
	interval_seconds: float = DEFAULT_SPAWN_INTERVAL_SECONDS,
	permanent: bool = false
) -> void:
	clear()
	enabled = powerups_enabled
	map_id = ArenaLayout.normalized_map_id(selected_map_id)
	spawn_interval_seconds = clampf(interval_seconds, 5.0, 90.0)
	permanent_drops = permanent
	_current_tick = start_tick
	_safe_center = ArenaLayout.center(map_id)
	_safe_radius = INF
	next_spawn_tick = start_tick + roundi(spawn_interval_seconds * GameConstants.PHYSICS_TICKS_PER_SECOND) if enabled else -1


func clear() -> void:
	active_powerups.clear()
	next_spawn_tick = -1


func step(server_tick: int, world: AuthoritativeWorld, players: Dictionary, safe_center: Vector2 = GameConstants.ARENA_SIZE * 0.5, safe_radius: float = INF) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not enabled:
		return events
	_current_tick = server_tick
	_safe_center = safe_center
	_safe_radius = safe_radius
	for id in active_powerups.keys():
		var powerup := active_powerups[id] as Dictionary
		var expired := server_tick >= int(powerup.get("expires_tick", 0x7fffffffffffffff))
		if expired or (powerup.position as Vector2).distance_to(safe_center) + POWERUP_RADIUS > safe_radius:
			active_powerups.erase(id)
			events.append({"event_type": &"CARD_POWERUP_REMOVED", "payload": {"powerup_id": id, "reason": "expired" if expired else "overtime"}})
	if next_spawn_tick >= 0 and server_tick >= next_spawn_tick:
		if active_powerups.size() < MAX_ACTIVE_POWERUPS:
			var spawned := _spawn_powerup(world)
			if not spawned.is_empty():
				events.append({"event_type": &"CARD_POWERUP_SPAWNED", "payload": spawned})
		# Skip missed intervals instead of bursting an unbounded backlog after
		# a tick jump, debugger pause, or a long period at capacity.
		next_spawn_tick = server_tick + roundi(spawn_interval_seconds * GameConstants.PHYSICS_TICKS_PER_SECOND)
	if active_powerups.is_empty():
		return events
	events.append_array(_collect_powerups(world, players))
	return events


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := active_powerups.keys()
	ids.sort()
	for powerup_id in ids:
		result.append((active_powerups[powerup_id] as Dictionary).duplicate(true))
	return result


func _spawn_powerup(world: AuthoritativeWorld) -> Dictionary:
	if active_powerups.size() >= MAX_ACTIVE_POWERUPS:
		return {}
	var card := _roll_rare_or_better_card()
	if card == null:
		return {}
	var position := _random_legal_position(world)
	if not position.is_finite():
		return {}
	var powerup := {
		"powerup_id": next_powerup_id,
		"card_id": card.card_id,
		"position": position,
		"rarity": card.rarity,
		"expires_tick": _current_tick + roundi(PICKUP_LIFETIME_SECONDS * GameConstants.PHYSICS_TICKS_PER_SECOND),
	}
	active_powerups[next_powerup_id] = powerup
	next_powerup_id = SequenceMath.increment(next_powerup_id)
	return powerup.duplicate(true)


func _collect_powerups(world: AuthoritativeWorld, players: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var powerup_ids := active_powerups.keys()
	powerup_ids.sort()
	var peer_ids := world.combatants.keys()
	peer_ids.sort()
	for powerup_value in powerup_ids:
		var powerup_id := int(powerup_value)
		if not active_powerups.has(powerup_id):
			continue
		var powerup := active_powerups[powerup_id] as Dictionary
		for peer_value in peer_ids:
			var peer_id := int(peer_value)
			var combatant := world.combatants.get(peer_id) as CombatantState
			var player := players.get(peer_id) as PlayerMatchState
			if combatant == null or player == null or not combatant.alive or not player.participant:
				continue
			if combatant.position.distance_to(powerup.position as Vector2) > GameConstants.SHIP_COLLISION_RADIUS + POWERUP_RADIUS:
				continue
			var card := _catalog.get_card(StringName(powerup.card_id))
			if card == null:
				break
			var added := player.add_card(card) if permanent_drops else player.add_temporary_card(card)
			if not added:
				break
			_apply_updated_stats(combatant, StatSystem.derive(player.effective_card_stacks(), _catalog))
			active_powerups.erase(powerup_id)
			events.append({
				"event_type": &"CARD_POWERUP_COLLECTED",
				"payload": {
					"powerup_id": powerup_id,
					"card_id": card.card_id,
					"peer_id": peer_id,
					"position": powerup.position,
				},
			})
			break
	return events


func _roll_rare_or_better_card() -> CardDefinition:
	var cards_by_rarity: Dictionary = {}
	for card_id in _catalog.all_ids():
		var card := _catalog.get_card(card_id)
		if card == null or card.rarity < CardDefinition.Rarity.RARE:
			continue
		if not cards_by_rarity.has(card.rarity):
			cards_by_rarity[card.rarity] = []
		(cards_by_rarity[card.rarity] as Array).append(card)
	var total_weight := 0.0
	for rarity_value in cards_by_rarity:
		total_weight += float(CardDefinition.RARITY_DROP_CHANCES.get(int(rarity_value), 0.0))
	if total_weight <= 0.0:
		return null
	var roll := _rng.randf_range(0.0, total_weight)
	var selected_rarity := CardDefinition.Rarity.RARE
	var rarities := cards_by_rarity.keys()
	rarities.sort()
	for rarity_value in rarities:
		selected_rarity = int(rarity_value)
		roll -= float(CardDefinition.RARITY_DROP_CHANCES.get(selected_rarity, 0.0))
		if roll <= 0.0:
			break
	var candidates := cards_by_rarity.get(selected_rarity, []) as Array
	return candidates[_rng.randi_range(0, candidates.size() - 1)] as CardDefinition if not candidates.is_empty() else null


func _random_legal_position(world: AuthoritativeWorld) -> Vector2:
	var safe_bounds := ArenaLayout.arena_rect().grow(-SPAWN_MARGIN)
	if is_finite(_safe_radius):
		var radius := maxf(_safe_radius - POWERUP_RADIUS, 0.0)
		safe_bounds = safe_bounds.intersection(Rect2(_safe_center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
	if not safe_bounds.has_area():
		return Vector2.INF
	for _attempt in MAX_POSITION_ATTEMPTS:
		var candidate := Vector2(
			_rng.randf_range(safe_bounds.position.x, safe_bounds.end.x),
			_rng.randf_range(safe_bounds.position.y, safe_bounds.end.y)
		)
		if _is_legal_position(candidate, world):
			return candidate
	var best_anchor := Vector2.INF
	var best_clearance := -1.0
	for anchor in ArenaLayout.spawn_anchors(map_id):
		if not _is_legal_position(anchor, world):
			continue
		var nearest_ship := 1.0e20
		for combatant_value in world.combatants.values():
			var combatant := combatant_value as CombatantState
			if combatant.alive:
				nearest_ship = minf(nearest_ship, anchor.distance_to(combatant.position))
		if nearest_ship > best_clearance:
			best_clearance = nearest_ship
			best_anchor = anchor
	return best_anchor


func _is_legal_position(position: Vector2, world: AuthoritativeWorld) -> bool:
	if not ArenaLayout.arena_rect().grow(-POWERUP_RADIUS).has_point(position):
		return false
	if position.distance_to(_safe_center) + POWERUP_RADIUS > _safe_radius:
		return false
	if ArenaLayout.overlaps_obstacle(position, POWERUP_RADIUS + 12.0, map_id):
		return false
	for powerup in active_powerups.values():
		if position.distance_to((powerup as Dictionary).position as Vector2) < POWERUP_RADIUS * 3.0:
			return false
	for combatant_value in world.combatants.values():
		var combatant := combatant_value as CombatantState
		if combatant.alive and combatant.position.distance_to(position) < SHIP_CLEARANCE:
			return false
	return true


static func _apply_updated_stats(combatant: CombatantState, updated_stats: CombatStats) -> void:
	var previous := combatant.stats
	var health_gain := maxf(updated_stats.max_health - previous.max_health, 0.0)
	var shield_gain := maxf(updated_stats.shield_capacity - previous.shield_capacity, 0.0)
	var ammunition_gain := maxi(updated_stats.magazine_size - previous.magazine_size, 0)
	var mine_charge_gain := maxi(updated_stats.mine_capacity - previous.mine_capacity, 0)
	var missile_charge_gain := maxi(updated_stats.missile_capacity - previous.missile_capacity, 0)
	var cloak_charge_gain := maxi(updated_stats.cloak_capacity - previous.cloak_capacity, 0)
	combatant.stats = updated_stats.duplicate_stats()
	combatant.health = clampf(combatant.health + health_gain, 0.0, combatant.stats.max_health)
	combatant.shield.energy = clampf(combatant.shield.energy + shield_gain, 0.0, combatant.stats.shield_capacity)
	combatant.weapon.ammunition = clampi(combatant.weapon.ammunition + ammunition_gain, 0, combatant.stats.magazine_size)
	combatant.mine_charges_remaining = mini(
		combatant.mine_charges_remaining + mine_charge_gain,
		combatant.stats.mine_capacity
	)
	combatant.missile_charges_remaining = mini(
		combatant.missile_charges_remaining + missile_charge_gain,
		combatant.stats.missile_capacity
	)
	combatant.cloak_charges_remaining = mini(
		combatant.cloak_charges_remaining + cloak_charge_gain,
		combatant.stats.cloak_capacity
	)
