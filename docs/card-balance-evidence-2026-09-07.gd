extends SceneTree


func _initialize() -> void:
	var catalog := CardCatalog.create_default()
	var errors := catalog.validate_default_catalog()
	if not errors.is_empty():
		printerr(errors)
		quit(1)
		return
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {}
	for id in catalog.all_ids():
		var card := catalog.get_card(id)
		counts[card.rarity_name()] = int(counts.get(card.rarity_name(), 0)) + 1
		var samples: Dictionary = {}
		for count in [1, 3, 5]:
			samples[str(count)] = measure(StatSystem.derive({id: count}, catalog))
		rows.append({"id": id, "name": card.display_name, "rarity": card.rarity_name(), "description": card.description, "stacks": samples})
	var report := {"date": "2026-09-07", "card_count": catalog.size(), "tier_counts": counts, "base": measure(CombatStats.create_base()), "cards": rows}
	# Preserve the dated pre-pass snapshot; reruns measure the current working tree.
	var file := FileAccess.open("res://.tools/card-balance-current.json", FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("BALANCE_SNAPSHOT cards=%d samples=%d" % [catalog.size(), rows.size() * 3])
	quit(0)


func measure(stats: CombatStats) -> Dictionary:
	var weapon := WeaponState.new()
	weapon.reset(stats)
	var shots := 0
	var duration := 120.0
	var delta := 1.0 / GameConstants.PHYSICS_TICKS_PER_SECOND
	for tick in roundi(duration / delta):
		weapon.step(stats, delta)
		if weapon.try_fire(stats, false):
			shots += 1
	var values: Dictionary = {}
	for property in CombatStats.get_stat_property_names():
		values[property] = stats.get(property)
	for property in StatSystem.SPECIAL_FLAGS:
		values[property] = stats.get(property)
	var projectile := ProjectileState.create(1, 1, 1, Vector2.ZERO, 0.0, stats)
	return {
		"stats": values,
		"shielded_acceleration": stats.acceleration * stats.shield_acceleration_factor,
		"seconds_to_max_speed": stats.max_speed / stats.acceleration,
		"shielded_seconds_to_max_speed": stats.max_speed / (stats.acceleration * stats.shield_acceleration_factor),
		"no_hit_shield_hold_seconds": stats.shield_capacity / stats.shield_continuous_drain,
		"shield_unlock_seconds_from_zero": stats.shield_regeneration_delay + stats.shield_depletion_threshold / stats.shield_regeneration,
		"raw_burst_dps": stats.projectile_damage * stats.projectile_count * stats.fire_rate,
		"all_projectiles_hit_dps_120s": shots * stats.projectile_damage * stats.projectile_count / duration,
		"shots_120s": shots,
		"nominal_projectile_range": stats.projectile_speed * stats.projectile_lifetime,
		"actual_projectile_speed": projectile.velocity.length(),
		"actual_projectile_range": projectile.velocity.length() * projectile.lifetime_remaining,
	}
