extends RefCounted


static func summary(payload: Dictionary, peer_id: int) -> String:
	var mode := int(payload.get("game_mode", GameModeRules.Mode.DEATH_MATCH))
	var entries: Dictionary = payload.get("objective_contributions", {})
	var contribution: Dictionary = entries.get(peer_id, entries.get(str(peer_id), {}))
	if mode == GameModeRules.Mode.KING_OF_THE_HILL:
		return "HILL  %.1fs controlled · %.1fs contested" % [float(contribution.get("hill_control_seconds", 0.0)), float(contribution.get("hill_contest_seconds", 0.0))]
	if GameModeRules.uses_flag(mode):
		return "FLAG  %d captures · %d carrier stops · %.1fs carrying · %d pickups" % [int(contribution.get("flag_captures", 0)), int(contribution.get("carrier_stops", 0)), float(contribution.get("flag_carry_seconds", 0.0)), int(contribution.get("flag_pickups", 0))]
	return ""
