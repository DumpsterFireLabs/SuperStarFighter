class_name DraftManager
extends RefCounted

enum SelectionResult {
	ACCEPTED,
	NO_ACTIVE_DRAFT,
	NO_OFFER,
	STALE_TOKEN,
	ALREADY_LOCKED,
	CARD_NOT_OFFERED,
}

var _catalog: CardCatalog
var _rng := RandomNumberGenerator.new()
var _match_seed: int
var _token_serial: int = 0
var _offers: Dictionary = {}
var _automatic_choices: Dictionary = {}
var _baseline_stats: Dictionary = {}
var _candidate_stats: Dictionary = {}
var _active: bool = false
var _pending_peers: Array[int] = []
var _preparing_players: Dictionary = {}
var _preparing_round: int = 0
var _preparing_skipped: Array[int] = []


func _init(catalog: CardCatalog, match_seed: int) -> void:
	_catalog = catalog
	_match_seed = match_seed
	_rng.seed = match_seed


func start_draft(players: Dictionary, round_number: int, skipped_peer_ids: Array[int] = []) -> Dictionary:
	begin_draft(players, round_number, skipped_peer_ids)
	while is_preparing():
		prepare_next_player()
	return _offers


func begin_draft(players: Dictionary, round_number: int, skipped_peer_ids: Array[int] = []) -> void:
	_offers.clear()
	_automatic_choices.clear()
	_baseline_stats.clear()
	_candidate_stats.clear()
	_active = true
	var peer_ids := players.keys()
	peer_ids.sort()
	_pending_peers.assign(peer_ids)
	_preparing_players = players
	_preparing_round = round_number
	_preparing_skipped = skipped_peer_ids.duplicate()


func is_preparing() -> bool:
	return not _pending_peers.is_empty()


func prepare_next_player() -> int:
	if _pending_peers.is_empty():
		return 0
	var peer_id: int = _pending_peers.pop_front()
	var player := _preparing_players.get(peer_id) as PlayerMatchState
	if player == null or not player.connected or not player.participant:
		return peer_id
	_token_serial += 1
	var token_material := "ssf-draft-token-v1\u001f%d\u001f%d\u001f%d\u001f%d" % [
		_match_seed,
		_preparing_round,
		peer_id,
		_token_serial,
	]
	var offer := DraftOffer.new(
		peer_id,
		token_material.sha256_text()
	)
	if int(peer_id) in _preparing_skipped:
		offer.skipped = true
		offer.locked = true
		_offers[peer_id] = offer
		return peer_id
	var eligible := _catalog.eligible_ids(player.card_stacks)
	var offer_count := mini(GameConstants.CARD_OFFER_SIZE, eligible.size())
	offer.card_ids = _weighted_cards_without_replacement(eligible, offer_count)
	var useful: Array[StringName] = []
	var before := StatSystem.derive(player.card_stacks, _catalog)
	_baseline_stats[peer_id] = before
	var candidates: Dictionary = {}
	for card_id in offer.card_ids:
		var next_build := player.card_stacks.duplicate()
		next_build[card_id] = int(next_build.get(card_id, 0)) + 1
		var after := StatSystem.derive(next_build, _catalog)
		candidates[card_id] = after
		if StatSystem.has_derived_benefit(before, after):
			useful.append(card_id)
	_candidate_stats[peer_id] = candidates
	_automatic_choices[peer_id] = useful if not useful.is_empty() else offer.card_ids.duplicate()
	if offer.card_ids.is_empty():
		offer.build_complete = true
		offer.locked = true
	_offers[peer_id] = offer
	return peer_id


func get_offer(peer_id: int) -> DraftOffer:
	return _offers.get(peer_id) as DraftOffer


func automatic_card_ids(peer_id: int) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_automatic_choices.get(peer_id, []))
	return result


func choose_npc_card(player: PlayerMatchState, mode: int, players: Dictionary) -> StringName:
	# Cache ownership is scoped to this draft (at most 32 x 6 stat records).
	return NpcDraftPolicy.choose_card(player, automatic_card_ids(player.peer_id), _catalog, mode, players, _baseline_stats.get(player.peer_id), _candidate_stats.get(player.peer_id, {}))


func select_card(peer_id: int, token: String, card_id: StringName) -> SelectionResult:
	if not _active:
		return SelectionResult.NO_ACTIVE_DRAFT
	var offer := get_offer(peer_id)
	if offer == null:
		return SelectionResult.NO_OFFER
	if offer.token != token:
		return SelectionResult.STALE_TOKEN
	if offer.locked:
		return SelectionResult.ALREADY_LOCKED
	if card_id not in offer.card_ids:
		return SelectionResult.CARD_NOT_OFFERED
	offer.selected_card_id = card_id
	offer.locked = true
	return SelectionResult.ACCEPTED


func all_locked() -> bool:
	if not _active or is_preparing() or _offers.is_empty():
		return false
	for offer in _offers.values():
		if not (offer as DraftOffer).locked:
			return false
	return true


func resolve_timeout() -> void:
	if not _active:
		return
	var peer_ids := _offers.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var offer := get_offer(peer_id)
		if offer.locked:
			continue
		var choices := automatic_card_ids(peer_id)
		offer.selected_card_id = choices[_rng.randi_range(0, choices.size() - 1)]
		offer.locked = true


func apply_locked_selections(players: Dictionary) -> Dictionary:
	var applied: Dictionary = {}
	if not all_locked():
		return applied
	var peer_ids := _offers.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var offer := get_offer(peer_id)
		if offer.build_complete or offer.skipped:
			applied[peer_id] = &""
			continue
		var player := players.get(peer_id) as PlayerMatchState
		var card := _catalog.get_card(offer.selected_card_id)
		if player != null and card != null and player.add_card(card):
			applied[peer_id] = offer.selected_card_id
	_active = false
	_preparing_players = {}
	_baseline_stats.clear()
	_candidate_stats.clear()
	return applied


func is_active() -> bool:
	return _active


func withdraw_player(peer_id: int) -> void:
	var offer := get_offer(peer_id)
	if offer == null:
		return
	offer.selected_card_id = &""
	offer.build_complete = true
	offer.locked = true


func _shuffle(values: Array[StringName]) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary


func _weighted_cards_without_replacement(eligible: Array[StringName], count: int) -> Array[StringName]:
	var selected: Array[StringName] = []
	var available_rarities: Dictionary = {}
	var positions: Dictionary = {}
	for index in eligible.size():
		var card_id := eligible[index]
		positions[card_id] = index
		var rarity := _catalog.get_card(card_id).rarity
		if not available_rarities.has(rarity):
			available_rarities[rarity] = []
		(available_rarities[rarity] as Array).append(card_id)
	while selected.size() < count and not available_rarities.is_empty():
		# Match the old first-remaining-card order, even after the first card of
		# a rarity is removed. RNG draws and cumulative weight order stay exact.
		var rarities := available_rarities.keys()
		rarities.sort_custom(func(left: int, right: int) -> bool: return int(positions[available_rarities[left][0]]) < int(positions[available_rarities[right][0]]))
		var total_weight := 0.0
		for rarity_value in rarities:
			total_weight += float(CardDefinition.RARITY_DROP_CHANCES.get(rarity_value, 0.0))
		var roll := _rng.randf() * total_weight
		var chosen_rarity: int = int(rarities[0])
		for rarity_value in rarities:
			roll -= float(CardDefinition.RARITY_DROP_CHANCES.get(rarity_value, 0.0))
			if roll <= 0.0:
				chosen_rarity = int(rarity_value)
				break
		var rarity_cards := available_rarities[chosen_rarity] as Array
		var chosen_id := StringName(rarity_cards[_rng.randi_range(0, rarity_cards.size() - 1)])
		selected.append(chosen_id)
		rarity_cards.erase(chosen_id)
		if rarity_cards.is_empty():
			available_rarities.erase(chosen_rarity)
	return selected
