extends "res://src/test/gameplay_study.gd"

# Exploratory controlled comparisons, not a human win-rate or release gate.
const PAIRS := [
	["vectored_nozzles", "lightweight_frame"],
	["pursuit_screen", "shielded_drive"],
	["pursuit_screen", "mobile_bulwark"],
	["twin_shot", "piercing_rounds"],
	["beam_emitter", "prismatic_lance"],
	["storm_of_one", "causality_cannon"],
	["fortress_emitter", "shield_siphon"],
	["adaptive_chassis", "phase_thrusters"],
]


func _run() -> void:
	var report := {"seeds": 3, "maps": ["core_arena", "prism_array"],
		"limitations": "Prescribed equal-pick builds; both peer/spawn assignments; deterministic Skilled bots; no pickups or draft availability model. Duel cutoff 60s. Objective skirmishes have one life and a 45s cutoff, not full match respawn rules. Draws remain draws. Before/current card comparisons both use corrected beam aiming. Synthetic scenarios are not independent human samples.",
		"duels": [], "objectives": [], "draft_choices": [], "card_signatures": {}, "source_hashes": {}}
	for path in ["src/shared/combat/npc_pilot_controller.gd", "src/shared/combat/npc_draft_policy.gd", "src/shared/combat/projectile_state.gd", "src/shared/combat/authoritative_world.gd", "src/shared/game_constants.gd"]:
		report.source_hashes[path] = FileAccess.get_sha256("res://" + path)
	var current := CardCatalog.create_default()
	var objectives_only := "--objectives-only" in OS.get_cmdline_user_args()
	if objectives_only:
		report = JSON.parse_string(FileAccess.get_file_as_string("res://docs/card-balance-validation-2026-09-07.json"))
		report.objectives = []
	catalog = current
	for id in current.all_ids():
		report.card_signatures[id] = {"mechanics": CardCatalog.mechanical_signature(current.get_card(id)), "rarity": current.get_card(id).rarity}
	for revision in ([] if objectives_only else ["before", "current"]):
		catalog = _catalog_revision(current, revision)
		if not catalog.validate_default_catalog().is_empty():
			printerr(catalog.validate_default_catalog())
			quit(1)
			return
		for pair in PAIRS:
			for supported in [false, true]:
				var left := _build(pair[0], supported)
				var right := _build(pair[1], supported)
				for map_id in [&"core_arena", &"prism_array"]:
					for seed_index in 3:
						for swap in [false, true]:
							var row := _bout(left, right, map_id, seed_index, swap)
							row.merge({"revision": revision, "pair": pair, "supported": supported})
							report.duels.append(row)
				if revision == "current":
					var player := PlayerMatchState.new(2, "Study", 1)
					player.card_stacks = _build("", supported)
					for mode in [GameModeRules.Mode.DEATH_MATCH, GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG]:
						var choices: Array[StringName] = [StringName(pair[0]), StringName(pair[1])]
						report.draft_choices.append({"pair": pair, "supported": supported, "mode": GameModeRules.mode_name(mode), "choice": NpcDraftPolicy.choose_card(player, choices, catalog, mode, {2: player})})
			print("BALANCE_VALIDATION revision=%s pair=%s" % [revision, str(pair)])
	# Objective samples focus on mobility and shield durability, with current cards.
	for pair_index in [0, 1, 2, 6]:
		var pair: Array = PAIRS[pair_index]
		for mode in [GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG]:
			for map_id in [&"core_arena", &"prism_array"]:
				for seed_index in 3:
					for swap in [false, true]:
						var row := _objective_bout(_build(pair[0], false), _build(pair[1], false), map_id, seed_index, swap, mode)
						row["pair"] = pair
						report.objectives.append(row)
		print("BALANCE_VALIDATION objectives=%s" % str(pair))
	report["range_checks"] = _range_checks(current)
	for row in report.range_checks:
		if row.hit != row.expected_hit:
			printerr("Controlled beam range check failed: ", row)
			quit(3)
			return
	var file := FileAccess.open("res://docs/card-balance-validation-2026-09-07.json", FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("BALANCE_VALIDATION_COMPLETE duels=%d objectives=%d draft_choices=%d" % [report.duels.size(), report.objectives.size(), report.draft_choices.size()])
	quit(0)


func _build(id: String, supported: bool) -> Dictionary:
	var build: Dictionary = {&"capacitor_bank": 1, &"extended_magazine": 1} if supported else {}
	if not id.is_empty():
		build[StringName(id)] = 1
	return build


func _catalog_revision(current: CardCatalog, revision: String) -> CardCatalog:
	var result := CardCatalog.new()
	for id in current.all_ids():
		var card := current.get_card(id).duplicate(true) as CardDefinition
		if revision == "before":
			match String(id):
				"vectored_nozzles": card.multiplicative_modifiers = {"acceleration": 1.12, "shield_acceleration_factor": 1.08}
				"pursuit_screen": card.multiplicative_modifiers["shield_acceleration_factor"] = 1.18
				"beam_emitter": card.multiplicative_modifiers = {"projectile_damage": 1.05, "projectile_speed": 2.5}
				"storm_of_one": card.integer_modifiers["magazine_size"] = -5
				"twin_shot", "fortress_emitter": card.rarity = CardDefinition.Rarity.EPIC
				"adaptive_chassis": card.rarity = CardDefinition.Rarity.RARE
		result.add_card(card)
	return result


func _objective_bout(left: Dictionary, right: Dictionary, map_id: StringName, seed_index: int, swap: bool, mode: int) -> Dictionary:
	var world := AuthoritativeWorld.new()
	world.set_map_id(map_id)
	var anchors := ArenaLayout.spawn_anchors(map_id)
	var index := posmod(seed_index * 5, anchors.size())
	var positions := {2: anchors[index], 3: anchors[posmod(index + anchors.size() / 2, anchors.size())]}
	var left_id := 3 if swap else 2
	var right_id := 2 if swap else 3
	world.add_peer(2)
	world.add_peer(3)
	world.prepare_heat({left_id: StatSystem.derive(left, catalog), right_id: StatSystem.derive(right, catalog)}, positions)
	var ids: Array[int] = [2, 3]
	var hill := HillModeHandler.new()
	var flag := FlagModeHandler.new()
	var objective_position := GameModeRules.objective_spawn(map_id, seed_index + 1 if GameModeRules.uses_hill(mode) else 0)
	hill.reset(objective_position, ids)
	flag.reset(objective_position)
	flag.configure(mode, map_id, 2, ids, {}, positions)
	var objective := hill.state if GameModeRules.uses_hill(mode) else flag.state
	objective.active = true
	var observations := MatchObservations.new()
	var npc := NpcPilotController.new()
	var winner := 0
	var elapsed := 0.0
	for tick in 2700:
		npc.submit_inputs(world, ids, {2: NpcPilotController.Difficulty.SKILLED, 3: NpcPilotController.Difficulty.SKILLED}, -1.0, objective)
		world.step(1.0 / 60.0)
		var alive: Array[int] = []
		for id in ids:
			if (world.combatants[id] as CombatantState).alive:
				alive.append(id)
		var result := hill.step(1.0 / 60.0, world, alive, observations) if GameModeRules.uses_hill(mode) else flag.step(1.0 / 60.0, world, alive, observations)
		elapsed = float(tick + 1) / 60.0
		world.drain_projectile_batch()
		world.drain_combat_feedback()
		if result.winner_peer_id != 0:
			winner = result.winner_peer_id
			break
	return {"map": map_id, "seed": seed_index, "swapped": swap, "objective_position": objective_position, "mode": GameModeRules.mode_name(mode), "seconds": elapsed, "winner": "left" if winner == left_id else ("right" if winner == right_id else "draw"), "censored": winner == 0, "left_contribution": observations.contributions.get(left_id, {}), "right_contribution": observations.contributions.get(right_id, {}), "left_alive": (world.combatants[left_id] as CombatantState).alive, "right_alive": (world.combatants[right_id] as CombatantState).alive}


func _range_checks(current: CardCatalog) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for revision in ["before", "current"]:
		var stats := StatSystem.derive({&"beam_emitter": 1}, _catalog_revision(current, revision))
		for distance in [600, 900, 1200]:
			var world := AuthoritativeWorld.new()
			world.add_peer(2, stats).position = Vector2(400, 100)
			var target := world.add_peer(3)
			target.position = Vector2(400 + distance, 100)
			world.projectile_registry.add(ProjectileState.create(1, 2, 1, Vector2(400, 100), 0.0, stats))
			for tick in 60:
				world.step(1.0 / 60.0)
				world.drain_projectile_batch()
				world.drain_combat_feedback()
			rows.append({"revision": revision, "distance": distance, "hit": target.health < target.stats.max_health, "expected_hit": distance <= (1080 if revision == "current" else 720)})
	return rows
