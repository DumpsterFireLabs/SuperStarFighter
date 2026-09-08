extends SceneTree


func _initialize() -> void:
	var catalog := CardCatalog.create_default()
	var rows: Array[Dictionary] = []
	var totals: Dictionary = {}
	for mode in [GameModeRules.Mode.DEATH_MATCH, GameModeRules.Mode.KING_OF_THE_HILL, GameModeRules.Mode.CAPTURE_THE_FLAG]:
		for seed_index in 40:
			var player := PlayerMatchState.new(2, "Draft sampler", 1)
			var players := {2: player}
			var draft := DraftManager.new(catalog, 92000 + seed_index)
			for round_number in range(1, 9):
				draft.start_draft(players, round_number)
				var offer := draft.get_offer(2)
				var chosen := NpcDraftPolicy.choose_card(player, draft.automatic_card_ids(2), catalog, mode, players)
				for id in offer.card_ids:
					var key := "%s/%s" % [GameModeRules.mode_name(mode), id]
					if not totals.has(key):
						totals[key] = {"mode": GameModeRules.mode_name(mode), "card": id, "offered": 0, "picked": 0}
					totals[key].offered += 1
					if id == chosen:
						totals[key].picked += 1
				rows.append({"seed": 92000 + seed_index, "mode": GameModeRules.mode_name(mode), "round": round_number, "build_before": player.card_stacks.duplicate(), "offered": offer.card_ids.duplicate(), "chosen": chosen})
				if chosen not in offer.card_ids or draft.select_card(2, offer.token, chosen) != 0:
					printerr("NPC failed to select from its offered cards")
					quit(1)
					return
				draft.apply_locked_selections(players)
	var output := FileAccess.open("res://docs/npc-draft-sampling-2026-09-07.json", FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify({"limitations": "40 fixed seeds per mode, eight sequential drafts each, no match wins or byes. Same offer seeds across modes, differing acquired builds. Measures this NPC heuristic's preferences, not player preferences or card power. Rare-card samples are small.", "totals": totals.values(), "drafts": rows}, "\t") + "\n")
	output.close()
	print("NPC_DRAFT_SAMPLING_COMPLETE drafts=%d" % rows.size())
	quit(0)
