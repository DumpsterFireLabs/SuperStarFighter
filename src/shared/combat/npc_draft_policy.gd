class_name NpcDraftPolicy
extends RefCounted


static func team_role(peer_id: int, members: Array[int]) -> StringName:
	var index := members.find(peer_id)
	if members.size() >= 3 and index == members.size() - 1:
		return &"defend"
	if members.size() >= 2 and index == 1:
		return &"escort"
	return &"assault"


static func draft_role(player: PlayerMatchState, mode: int, players: Dictionary) -> StringName:
	if GameModeRules.uses_hill(mode):
		return &"defend"
	if not GameModeRules.uses_flag(mode):
		return &"assault"
	if not GameModeRules.is_team_mode(mode):
		return &"runner"
	var members: Array[int] = []
	for value in players.values():
		var member := value as PlayerMatchState
		if member.connected and member.participant and member.team_id == player.team_id:
			members.append(member.peer_id)
	members.sort()
	return team_role(player.peer_id, members)


static func choose_card(player: PlayerMatchState, choices: Array[StringName], catalog: CardCatalog, mode: int, players: Dictionary) -> StringName:
	var role := draft_role(player, mode, players)
	var before := StatSystem.derive(player.card_stacks, catalog)
	var before_utility := utility(before, role)
	var best_id: StringName = &""
	var best_score := -INF
	for card_id in choices:
		var build := player.card_stacks.duplicate()
		build[card_id] = int(build.get(card_id, 0)) + 1
		var after := StatSystem.derive(build, catalog)
		var score := utility(after, role) - before_utility
		# New active tools receive credit once; repeated unlocks are evaluated only
		# through their effective stats. Role tradeoffs remain in the utility delta.
		for flag in StatSystem.SPECIAL_FLAGS:
			if bool(after.get(flag)) and not bool(before.get(flag)):
				score += 0.12
		if after.mine_layer_enabled and not before.mine_layer_enabled and role == &"defend":
			score += 0.18
		if after.afterburner_enabled and not before.afterburner_enabled and role in [&"runner", &"assault", &"escort"]:
			score += 0.18
		if score > best_score:
			best_score = score
			best_id = card_id
	return best_id


static func utility(stats: CombatStats, role: StringName) -> float:
	var base := CombatStats.create_base()
	var mobile := role in [&"runner", &"assault"]
	var defensive := role == &"defend"
	var sustain := stats.max_health / base.max_health + _shield_utility(stats, base)
	# Shield thrust compounds with acceleration; drag only helps after input release.
	var shielded_acceleration := stats.acceleration * stats.shield_acceleration_factor
	var base_shielded_acceleration := base.acceleration * base.shield_acceleration_factor
	var mobility := (
		stats.max_speed / base.max_speed * 0.7
		+ stats.acceleration / base.acceleration * 0.125
		+ shielded_acceleration / base_shielded_acceleration * 0.125
		+ sqrt(stats.drag / base.drag) * 0.05
	)
	var damage := float(StatSystem.weapon_output(stats).sustained)
	var base_damage := float(StatSystem.weapon_output(base).sustained)
	# Diminishing utility avoids treating another damage multiplier as infinitely
	# more valuable than repairing a glass build's survival or movement weakness.
	var offense := sqrt(maxf(damage / base_damage, 0.0))
	# Use created projectiles so fixed beam speed and shortened beam lifetime
	# cannot drift from combat. Delivery speed and reach are separate advantages.
	var projectile := ProjectileState.create(0, 0, 0, Vector2.ZERO, 0.0, stats)
	var projectile_speed := projectile.velocity.length()
	var range_value := sqrt(projectile_speed * projectile.lifetime_remaining / (base.projectile_speed * base.projectile_lifetime))
	var delivery := sqrt(projectile_speed / base.projectile_speed)
	var repair := stats.auto_repair_rate / base.max_health if stats.auto_repair_enabled else 0.0
	return (
		sustain * (1.25 if defensive else 0.8)
		+ mobility * (1.4 if mobile else 0.75)
		+ offense * (0.65 if role == &"runner" else 1.0)
		+ range_value * 0.15 + delivery * 0.1
		+ repair * (3.0 if defensive else 1.5)
	)


static func _shield_utility(stats: CombatStats, base: CombatStats) -> float:
	# Approximate distinct shield strengths without assuming an incoming hit rate:
	# hit budget, no-hit hold time, recovery from depletion, and refill throughput.
	# These are comparative scores, not exact block counts or shield uptime.
	var hit_budget := (stats.shield_capacity / stats.shield_block_cost) / (base.shield_capacity / base.shield_block_cost)
	var hold_time := (stats.shield_capacity / stats.shield_continuous_drain) / (base.shield_capacity / base.shield_continuous_drain)
	var unlock_time := stats.shield_regeneration_delay + minf(stats.shield_depletion_threshold, stats.shield_capacity) / stats.shield_regeneration
	var base_unlock_time := base.shield_regeneration_delay + base.shield_depletion_threshold / base.shield_regeneration
	var coverage := sqrt(stats.shield_arc_degrees / base.shield_arc_degrees)
	# Diminishing returns keep efficiency stacks from overwhelming every role.
	return coverage * (
		sqrt(hit_budget) * 0.25
		+ sqrt(hold_time) * 0.2
		+ sqrt(base_unlock_time / unlock_time) * 0.1
		+ sqrt(stats.shield_regeneration / base.shield_regeneration) * 0.1
	)
