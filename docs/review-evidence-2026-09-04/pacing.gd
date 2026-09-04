extends "res://src/test/gameplay_study.gd"

func _run() -> void:
	catalog = CardCatalog.create_default()
	var rows: Array[Dictionary] = []
	for mode in [GameModeRules.Mode.DEATH_MATCH, GameModeRules.Mode.TEAM_DEATH_MATCH, GameModeRules.Mode.KING_OF_THE_HILL]:
		for count in [2, 8, 32]:
			rows.append(_pacing_case(mode, count, 0))
			print("REVIEW_PACING mode=%d count=%d" % [mode, count])
	var file := FileAccess.open("res://reports/fresh-review-2026-09-04/pacing.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	print("REVIEW_PACING_COMPLETE")
	quit()
