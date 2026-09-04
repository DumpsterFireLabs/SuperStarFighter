extends SceneTree

# Deterministic exploratory fixtures, not a human win-rate or release gate.
# Run through tools/measure-gameplay.ps1; raw rows retain seeds and censoring.
const BUILDS: Dictionary = {
	"sustain": {&"auto_repair": 1, &"reinforced_hull": 1, &"quick_loader": 1},
	"burst": {&"heavy_rounds": 1, &"twin_shot": 1, &"extended_magazine": 1},
	"shield": {&"capacitor_bank": 1, &"quick_charge": 1, &"wide_emitter": 1},
	"multishot": {&"twin_shot": 1, &"scatter_array": 1, &"rapid_cycling": 1},
	"ram": {&"ramming_shields": 1, &"phase_thrusters": 1, &"capacitor_bank": 1},
	"mobility": {&"afterburner": 1, &"lightweight_frame": 1, &"vector_jets": 1},
	"range": {&"rangefinder": 1, &"long_fuse_rounds": 1, &"heavy_rounds": 1},
	"cover": {&"ricochet_rounds": 1, &"quick_loader": 1, &"reinforced_hull": 1},
}
var catalog: CardCatalog
var seed_count: int = 3
var section: String = "all"
var output_path: String = "res://reports/gameplay-study.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): seed_count = clampi(int(arg.trim_prefix("--seeds=")), 1, 100)
		if arg.begins_with("--section="): section = arg.trim_prefix("--section=")
		if arg.begins_with("--output="): output_path = arg.trim_prefix("--output=")
	if section not in ["all", "pacing", "balance", "fairness"]:
		push_error("Study section must be all, pacing, balance, or fairness")
		quit(1)
		return
	catalog = CardCatalog.create_default()
	var report := {"schema": 1, "protocol": GameConstants.PROTOCOL_VERSION,
		"seed_count": seed_count, "builds": BUILDS,
		"limitations": "Deterministic skilled bots; seeded maps/spawns and both sides. Censored bouts are draws, not wins. Draft timing is automatic, not human decision time. Three-card matchup builds are prescribed; availability is measured separately. No population fairness inference."}
	if section in ["all", "balance"]:
		report["availability"] = _availability()
		report["saturation"] = _saturation()
		report["matchups"] = _matchups()
		report["comeback"] = _comeback()
	if section in ["all", "pacing"]:
		report["pacing"] = _pacing()
	if section in ["all", "fairness"]:
		report["natural_pickups"] = _natural_pickups()
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write study: %s" % output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("SSF_GAMEPLAY_STUDY_COMPLETE output=%s" % output_path)
	quit(0)


func _availability() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	# Target-aware selection gives a reproducible opportunity ceiling for these
	# exact recipes; byes and intervening generic picks use production rules.
	for family in BUILDS:
		for seed_index in seed_count * 20:
			var player := PlayerMatchState.new(2, "Study", 1)
			var players := {2: player}
			var draft := DraftManager.new(catalog, 6100 + seed_index)
			for round_number in range(1, 9):
				var byes: Array[int] = []
				if round_number in [3, 6]: byes.append(2)
				draft.start_draft(players, round_number, byes)
				var offer := draft.get_offer(2)
				if not offer.locked:
					var choices := draft.automatic_card_ids(2)
					var selected := choices[0]
					for id in choices:
						if BUILDS[family].has(id) and player.card_stack(id) < int(BUILDS[family][id]):
							selected = id
							break
					draft.select_card(2, offer.token, selected)
				draft.apply_locked_selections(players)
				var acquired := 0
				for id in BUILDS[family]:
					acquired += mini(player.card_stack(id), int(BUILDS[family][id]))
				rows.append({"family": family, "seed": 6100 + seed_index, "round": round_number,
					"recipe_cards": acquired, "complete": acquired == 3, "bye": not byes.is_empty()})
	return rows


func _saturation() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in catalog.all_ids():
		var card := catalog.get_card(id)
		for count in [1, 3, 10, 100]:
			var before := StatSystem.derive({id: count}, catalog)
			var after := StatSystem.derive({id: count + 1}, catalog)
			var changes: Dictionary = {}
			for stat in StatSystem.FLOAT_STATS + StatSystem.INTEGER_STATS:
				if not is_equal_approx(float(before.get(stat)), float(after.get(stat))):
					changes[String(stat)] = {"before": before.get(stat), "after": after.get(stat)}
			rows.append({"card": String(id), "stacks": count,
				"benefit": StatSystem.has_effective_benefit({id: count}, card, catalog), "changes": changes})
	return rows


func _matchups() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for pair in [["sustain", "burst"], ["shield", "multishot"], ["ram", "mobility"], ["range", "cover"]]:
		for map_id in [&"core_arena", &"prism_array"]:
			for seed_index in seed_count:
				for swap in [false, true]:
					var row := _bout(BUILDS[pair[0]], BUILDS[pair[1]], map_id, seed_index, swap)
					row["left"] = pair[0]
					row["right"] = pair[1]
					rows.append(row)
		print("SSF_STUDY_PROGRESS matchup=%s" % str(pair))
	return rows


func _comeback() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for family in ["burst", "shield", "mobility", "sustain"]:
		for condition in ["equal_builds", "leader_bye", "permanent_pickup", "temporary_pickup_expired"]:
			var leader: Dictionary = BUILDS[family].duplicate()
			var challenger: Dictionary = BUILDS[family].duplicate()
			# Controlled next-heat comparison: production add/clear semantics.
			var player := PlayerMatchState.new(2, "Prior winner", 1)
			player.card_stacks = leader
			if condition == "leader_bye":
				challenger[&"heavy_rounds"] = int(challenger.get(&"heavy_rounds", 0)) + 1
			elif condition == "permanent_pickup":
				player.add_card(catalog.get_card(&"capacitor_bank"))
			elif condition == "temporary_pickup_expired":
				player.add_temporary_card(catalog.get_card(&"capacitor_bank"))
				player.clear_temporary_cards()
			for seed_index in seed_count:
				for swap in [false, true]:
					var row := _bout(player.effective_card_stacks(), challenger, &"core_arena", seed_index, swap)
					row["family"] = family
					row["condition"] = condition
					rows.append(row)
		print("SSF_STUDY_PROGRESS comeback=%s" % family)
	return rows


func _bout(left: Dictionary, right: Dictionary, map_id: StringName, seed_index: int, swap: bool) -> Dictionary:
	var world := AuthoritativeWorld.new()
	world.set_map_id(map_id)
	var anchors := ArenaLayout.spawn_anchors(map_id)
	var index := posmod(seed_index * 5, anchors.size())
	var positions := [anchors[index], anchors[posmod(index + anchors.size() / 2, anchors.size())]]
	world.add_peer(2)
	world.add_peer(3)
	var left_id := 3 if swap else 2
	var right_id := 2 if swap else 3
	world.prepare_heat({left_id: StatSystem.derive(left, catalog), right_id: StatSystem.derive(right, catalog)},
		{2: positions[0], 3: positions[1]})
	var npc := NpcPilotController.new()
	var ids: Array[int] = [2, 3]
	var difficulties := {2: NpcPilotController.Difficulty.SKILLED, 3: NpcPilotController.Difficulty.SKILLED}
	var first_contact: Variant = null
	var elapsed := 0.0
	for tick in 3600:
		npc.submit_inputs(world, ids, difficulties)
		world.step(1.0 / 60.0)
		elapsed = float(tick + 1) / 60.0
		if first_contact == null and world.combat_contact_serial > 0:
			first_contact = elapsed
		world.drain_projectile_batch()
		world.drain_combat_feedback()
		if not (world.combatants[2] as CombatantState).alive or not (world.combatants[3] as CombatantState).alive:
			break
	var left_alive := (world.combatants[left_id] as CombatantState).alive
	var right_alive := (world.combatants[right_id] as CombatantState).alive
	return {"map": String(map_id), "seed": seed_index, "swapped": swap, "seconds": elapsed,
		"first_contact_seconds": first_contact, "hull_damage": world.combat_hull_damage,
		"winner": "left" if left_alive and not right_alive else ("right" if right_alive and not left_alive else "draw"),
		"censored": left_alive and right_alive, "left_build": left, "right_build": right}


func _pacing() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for mode in [GameModeRules.Mode.DEATH_MATCH, GameModeRules.Mode.TEAM_DEATH_MATCH,
		GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG, GameModeRules.Mode.TEAM_CAPTURE_THE_FLAG]:
		for count in [2, 8, 32]:
			for seed_index in seed_count:
				rows.append(_pacing_case(mode, count, seed_index))
				print("SSF_STUDY_PROGRESS pacing=%s players=%d seed=%d" % [GameModeRules.mode_name(mode), count, seed_index])
	return rows


func _natural_pickups() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for permanent in [false, true]:
		for seed_index in seed_count:
			rows.append(_pacing_case(GameModeRules.Mode.DEATH_MATCH, 8, seed_index, true, permanent, 5))
			print("SSF_STUDY_PROGRESS pickups_permanent=%s seed=%d" % [str(permanent), seed_index])
	return rows


func _pacing_case(mode: int, count: int, seed_index: int, pickups: bool = false, permanent: bool = false, target_heats: int = 3) -> Dictionary:
	var config := MatchConfig.new()
	config.max_players = count
	config.game_mode = mode
	config.random_spawn_powerups = pickups
	config.random_powerups_permanent = permanent
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	var ids: Array[int] = []
	var difficulties: Dictionary = {}
	for peer_id in range(2, count + 2):
		lobby.admit(peer_id, "Study%d" % peer_id)
		var player := lobby.players[peer_id] as PlayerMatchState
		player.is_npc = true
		player.npc_difficulty = NpcPilotController.Difficulty.SKILLED
		player.lobby_ready = true
		world.add_peer(peer_id)
		ids.append(peer_id)
		difficulties[peer_id] = player.npc_difficulty
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 7100 + seed_index)
	coordinator.start(0)
	var npc := NpcPilotController.new()
	for tick in 42000:
		if coordinator.controls_enabled():
			npc.submit_inputs(world, ids, difficulties, coordinator.npc_overtime_elapsed(), coordinator.npc_objective_state())
		world.step(1.0 / 60.0, coordinator.controls_enabled())
		coordinator.step(1.0 / 60.0)
		world.drain_projectile_batch()
		world.drain_combat_feedback()
		coordinator.drain_events()
		if coordinator.observations.heats.size() >= target_heats:
			break
	return {"seed": 7100 + seed_index, "mode": GameModeRules.mode_name(mode), "players": count,
		"incomplete": coordinator.observations.heats.size() < target_heats,
		"powerups": lobby.config.random_spawn_powerups, "permanent": lobby.config.random_powerups_permanent,
		"heats": coordinator.observations.heats.duplicate(true)}
