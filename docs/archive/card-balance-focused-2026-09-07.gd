extends "res://docs/archive/card-balance-validation-2026-09-07.gd"

const GROUPS := {
	"twin": [["twin_shot", "heavy_rounds"], ["twin_shot", "siege_cannon"], ["twin_shot", "rail_accelerant"], ["twin_shot", "piercing_rounds"], ["twin_shot", "sustained_barrage"]],
	"adaptive": [["adaptive_chassis", "overcharged_thrusters"], ["adaptive_chassis", "phase_thrusters"], ["adaptive_chassis", "vector_jets"], ["adaptive_chassis", "plasma_thrusters"], ["adaptive_chassis", "reinforced_hull"]],
	"mobility": [["pursuit_screen", "mobile_bulwark"], ["pursuit_screen", "shielded_drive"], ["pursuit_screen", "plasma_thrusters"], ["mobile_bulwark", "shielded_drive"], ["mobile_bulwark", "plasma_thrusters"]],
	"mythical": [["storm_of_one", "causality_cannon"], ["storm_of_one", "sunbeam_core"], ["storm_of_one", "horizon_round"], ["causality_cannon", "sunbeam_core"], ["causality_cannon", "horizon_round"], ["sunbeam_core", "horizon_round"]],
}
const TEAM_PAIRS := [["twin_shot", "piercing_rounds"], ["twin_shot", "heavy_rounds"], ["storm_of_one", "causality_cannon"], ["storm_of_one", "sunbeam_core"], ["causality_cannon", "sunbeam_core"], ["causality_cannon", "horizon_round"]]


func _run() -> void:
	catalog = CardCatalog.create_default()
	if not catalog.validate_default_catalog().is_empty():
		quit(1)
		return
	var report := {"duels": [], "teams": [], "objectives": [], "lanes": [], "stats": {}, "card_signatures": {}, "source_hashes": {}, "limitations": "Deterministic Skilled NPCs, prescribed equal-pick builds, mirrored peer/spawn assignments; three configurations and two maps. Duels and 2v2 end at elimination or 60s. Objective skirmishes use real objective placement and handlers but one life and a 45s cutoff. No pickups, respawns, drafting, or human win-rate inference. Geometry fixtures are deliberately controlled, not averages over combat."}
	for path in ["src/shared/combat/npc_pilot_controller.gd", "src/shared/combat/projectile_state.gd", "src/shared/combat/authoritative_world.gd", "src/shared/game_constants.gd", "docs/archive/card-balance-focused-2026-09-07.gd", "src/test/gameplay_study.gd"]:
		report.source_hashes[path] = FileAccess.get_sha256("res://" + path)
	for id in catalog.all_ids():
		report.card_signatures[id] = {"mechanics": CardCatalog.mechanical_signature(catalog.get_card(id)), "rarity": catalog.get_card(id).rarity}
	for group in GROUPS:
		var contexts := ["single", "supported", "multishot"] if group == "mythical" else ["single", "supported"]
		for pair in GROUPS[group]:
			for context in contexts:
				var left := _focused_build(pair[0], group, context)
				var right := _focused_build(pair[1], group, context)
				for map_id in [&"core_arena", &"prism_array"]:
					for seed_index in 3:
						for swap in [false, true]:
							var row := _bout(left, right, map_id, seed_index, swap)
							row.merge({"pair": pair, "group": group, "context": context})
							report.duels.append(row)
			print("FOCUSED_DUELS group=%s pair=%s" % [group, str(pair)])
	for pair in TEAM_PAIRS:
		var group := "twin" if pair[0] == "twin_shot" else "mythical"
		for context in ["single", "supported"]:
			for map_id in [&"core_arena", &"prism_array"]:
				for seed_index in 2:
					for swap in [false, true]:
						var row := _team_bout(_focused_build(pair[0], group, context), _focused_build(pair[1], group, context), map_id, seed_index, swap)
						row.merge({"pair": pair, "context": context})
						report.teams.append(row)
		print("FOCUSED_TEAMS pair=%s" % str(pair))
	var objective_pairs: Array = GROUPS.mobility.duplicate()
	objective_pairs.append(["adaptive_chassis", "plasma_thrusters"])
	objective_pairs.append(["adaptive_chassis", "overcharged_thrusters"])
	for pair in objective_pairs:
		for mode in [GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG]:
			for map_id in [&"core_arena", &"prism_array"]:
				for seed_index in 3:
					for swap in [false, true]:
						var row := _objective_bout({StringName(pair[0]): 1}, {StringName(pair[1]): 1}, map_id, seed_index, swap, mode)
						row["pair"] = pair
						report.objectives.append(row)
		print("FOCUSED_OBJECTIVES pair=%s" % str(pair))
	for id in [&"twin_shot", &"piercing_rounds", &"heavy_rounds", &"storm_of_one", &"causality_cannon", &"sunbeam_core", &"horizon_round"]:
		for layout in ["near", "far", "column", "fan"]:
			report.lanes.append(_lane(id, layout))
	for id in [&"twin_shot", &"adaptive_chassis", &"pursuit_screen", &"mobile_bulwark", &"storm_of_one", &"causality_cannon", &"sunbeam_core", &"horizon_round"]:
		var samples := {}
		for count in [1, 3, 5]:
			var stats := StatSystem.derive({id: count}, catalog)
			var fields := {}
			for property in CombatStats.get_stat_property_names():
				fields[property] = stats.get(property)
			samples[str(count)] = {"stats": fields, "potential_output": StatSystem.weapon_output(stats), "shield_hold_seconds": stats.shield_capacity / stats.shield_continuous_drain, "shielded_acceleration": stats.acceleration * stats.shield_acceleration_factor}
		report.stats[id] = samples
	var output := FileAccess.open("res://docs/archive/card-balance-focused-2026-09-07.json", FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("FOCUSED_COMPLETE duels=%d teams=%d objectives=%d lanes=%d" % [report.duels.size(), report.teams.size(), report.objectives.size(), report.lanes.size()])
	quit(0)


func _focused_build(id: String, group: String, context: String) -> Dictionary:
	var build := {StringName(id): 1}
	if context == "multishot":
		build[&"twin_shot"] = 1
		build[&"heavy_rounds"] = 1
	elif context == "supported":
		match group:
			"twin":
				build[&"heavy_rounds"] = int(build.get(&"heavy_rounds", 0)) + 1
				build[&"extended_magazine"] = 1
			"adaptive": build[&"ablative_shell"] = 2
			"mobility":
				build[&"capacitor_bank"] = 1
				build[&"efficient_field"] = 1
			"mythical":
				build[&"endless_belt"] = 1
				build[&"extended_magazine"] = 1
	return build


func _team_bout(left: Dictionary, right: Dictionary, map_id: StringName, seed_index: int, swap: bool) -> Dictionary:
	var world := AuthoritativeWorld.new()
	world.set_map_id(map_id)
	var anchors := ArenaLayout.spawn_anchors(map_id)
	var ids: Array[int] = [2, 3, 4, 5]
	var positions := {}
	var stats := {}
	for index in ids.size():
		var id := ids[index]
		world.add_peer(id)
		var side_left := index < 2
		var build := left if side_left != swap else right
		stats[id] = StatSystem.derive(build, catalog)
		positions[id] = anchors[posmod(seed_index * 3 + (index if side_left else index - 2 + anchors.size() / 2), anchors.size())]
	world.set_team_assignments({2: 1, 3: 1, 4: 2, 5: 2})
	world.prepare_heat(stats, positions)
	var npc := NpcPilotController.new()
	var counts := [2, 2]
	var elapsed := 0.0
	for tick in 3600:
		npc.submit_inputs(world, ids, {2: NpcPilotController.Difficulty.SKILLED, 3: NpcPilotController.Difficulty.SKILLED, 4: NpcPilotController.Difficulty.SKILLED, 5: NpcPilotController.Difficulty.SKILLED})
		world.step(1.0 / 60.0)
		world.drain_projectile_batch()
		world.drain_combat_feedback()
		counts = [0, 0]
		for id in ids:
			if (world.combatants[id] as CombatantState).alive:
				counts[0 if id < 4 else 1] += 1
		elapsed = float(tick + 1) / 60.0
		if counts[0] == 0 or counts[1] == 0:
			break
	var left_alive := int(counts[1 if swap else 0])
	var right_alive := int(counts[0 if swap else 1])
	return {"map": map_id, "seed": seed_index, "swapped": swap, "seconds": elapsed, "winner": "left" if left_alive > 0 and right_alive == 0 else ("right" if right_alive > 0 and left_alive == 0 else "draw"), "censored": left_alive > 0 and right_alive > 0, "left_alive": left_alive, "right_alive": right_alive, "left_build": left, "right_build": right}


func _lane(id: StringName, layout: String) -> Dictionary:
	var stats := StatSystem.derive({id: 1}, catalog)
	var world := AuthoritativeWorld.new()
	var origin := Vector2(400, 150)
	world.add_peer(2, stats).position = origin
	var positions: Array[Vector2] = [origin + Vector2(200, 0)]
	match layout:
		"far": positions = [origin + Vector2(600, 0)]
		"column": positions = [origin + Vector2(300, 0), origin + Vector2(420, 0), origin + Vector2(540, 0)]
		"fan": positions = [origin + Vector2.from_angle(deg_to_rad(-5.0)) * 600.0, origin + Vector2.from_angle(deg_to_rad(5.0)) * 600.0]
	var targets: Array[CombatantState] = []
	for index in positions.size():
		var target := world.add_peer(3 + index)
		target.position = positions[index]
		targets.append(target)
	var index := 1
	for angle in MovementSystem.spread_angles(0.0, stats.projectile_count, stats.projectile_spread_degrees):
		world.projectile_registry.add(ProjectileState.create(index, 2, 1, origin, angle, stats))
		index += 1
	for tick in 120:
		world.step(1.0 / 60.0)
		world.drain_projectile_batch()
		world.drain_combat_feedback()
	var damage: Array[float] = []
	for target in targets:
		damage.append(target.stats.max_health - target.health)
	return {"card": id, "layout": layout, "damage_by_target": damage, "total_damage": damage.reduce(func(a: float, b: float) -> float: return a + b, 0.0)}
