extends "res://docs/card-balance-focused-2026-09-07.gd"


func _run() -> void:
	var current := CardCatalog.create_default()
	var report := {"duels": [], "objectives": [], "source_hashes": {}, "card_signatures": {}, "limitations": "Exploratory in-memory variants only. Same deterministic Skilled pilot and prescribed builds as focused study. Not independent human samples or an automatic tuning optimizer."}
	for path in ["docs/card-balance-trials-2026-09-07.gd", "docs/card-balance-focused-2026-09-07.gd", "docs/card-balance-validation-2026-09-07.gd", "src/test/gameplay_study.gd", "src/shared/combat/npc_pilot_controller.gd", "src/shared/combat/authoritative_world.gd", "src/shared/combat/shield_state.gd", "src/shared/game_constants.gd"]:
		report.source_hashes[path] = FileAccess.get_sha256("res://" + path)
	for id in current.all_ids():
		report.card_signatures[id] = {"mechanics": CardCatalog.mechanical_signature(current.get_card(id)), "rarity": current.get_card(id).rarity}
	for trial in ["twin_epic_peers", "twin_damage_065", "mobile_thrust_145"]:
		catalog = _catalog_revision(current, "current")
		var group := "twin"
		var pairs: Array = []
		match trial:
			"twin_epic_peers":
				for peer in ["micro_barrage", "needle_storm", "scatter_array", "trident_array", "laser_repeater"]:
					pairs.append(["twin_shot", peer])
			"twin_damage_065":
				catalog.get_card(&"twin_shot").multiplicative_modifiers["projectile_damage"] = 0.65
				pairs = GROUPS.twin
			"mobile_thrust_145":
				group = "mobility"
				catalog.get_card(&"mobile_bulwark").multiplicative_modifiers["shield_acceleration_factor"] = 1.45
				pairs = [["mobile_bulwark", "pursuit_screen"], ["mobile_bulwark", "shielded_drive"], ["mobile_bulwark", "plasma_thrusters"]]
		for pair in pairs:
			for context in ["single", "supported"]:
				for map_id in [&"core_arena", &"prism_array"]:
					for seed_index in 3:
						for swap in [false, true]:
							var row := _bout(_focused_build(pair[0], group, context), _focused_build(pair[1], group, context), map_id, seed_index, swap)
							row.merge({"trial": trial, "pair": pair, "context": context})
							report.duels.append(row)
			if group == "mobility":
				for mode in [GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG]:
					for map_id in [&"core_arena", &"prism_array"]:
						for seed_index in 3:
							for swap in [false, true]:
								var row := _objective_bout({StringName(pair[0]): 1}, {StringName(pair[1]): 1}, map_id, seed_index, swap, mode)
								row.merge({"trial": trial, "pair": pair})
								report.objectives.append(row)
			print("BALANCE_TRIAL trial=%s pair=%s" % [trial, str(pair)])
	var output := FileAccess.open("res://docs/card-balance-trials-2026-09-07.json", FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("BALANCE_TRIAL_COMPLETE duels=%d objectives=%d" % [report.duels.size(), report.objectives.size()])
	quit(0)
