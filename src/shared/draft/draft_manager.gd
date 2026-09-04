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
var _active: bool = false


func _init(catalog: CardCatalog, match_seed: int) -> void:
	_catalog = catalog
	_match_seed = match_seed
	_rng.seed = match_seed


func start_draft(players: Dictionary, round_number: int, skipped_peer_ids: Array[int] = []) -> Dictionary:
	_offers.clear()
	_automatic_choices.clear()
	_active = true
	var peer_ids := players.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var player := players[peer_id] as PlayerMatchState
		if not player.connected or not player.participant:
			continue
		_token_serial += 1
		var token_material := "ssf-draft-token-v1\u001f%d\u001f%d\u001f%d\u001f%d" % [
			_match_seed,
			round_number,
			peer_id,
			_token_serial,
		]
		var offer := DraftOffer.new(
			peer_id,
			token_material.sha256_text()
		)
		if int(peer_id) in skipped_peer_ids:
			offer.skipped = true
			offer.locked = true
			_offers[peer_id] = offer
			continue
		var eligible := _catalog.eligible_ids(player.card_stacks)
		var offer_count := mini(GameConstants.CARD_OFFER_SIZE, eligible.size())
		offer.card_ids = _weighted_cards_without_replacement(eligible, offer_count)
		var useful: Array[StringName] = []
		for card_id in offer.card_ids:
			if StatSystem.has_effective_benefit(player.card_stacks, _catalog.get_card(card_id), _catalog):
				useful.append(card_id)
		_automatic_choices[peer_id] = useful if not useful.is_empty() else offer.card_ids.duplicate()
		if offer.card_ids.is_empty():
			offer.build_complete = true
			offer.locked = true
		_offers[peer_id] = offer
	return _offers


func get_offer(peer_id: int) -> DraftOffer:
	return _offers.get(peer_id) as DraftOffer


func automatic_card_ids(peer_id: int) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_automatic_choices.get(peer_id, []))
	return result


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
	if not _active or _offers.is_empty():
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
	var available := eligible.duplicate()
	var selected: Array[StringName] = []
	while selected.size() < count and not available.is_empty():
		var available_rarities: Dictionary = {}
		var total_weight := 0.0
		for card_id in available:
			var rarity := _catalog.get_card(card_id).rarity
			if not available_rarities.has(rarity):
				available_rarities[rarity] = []
			(available_rarities[rarity] as Array).append(card_id)
		for rarity_value in available_rarities:
			total_weight += float(CardDefinition.RARITY_DROP_CHANCES.get(rarity_value, 0.0))
		var roll := _rng.randf() * total_weight
		var chosen_rarity: int = int(available_rarities.keys()[0])
		for rarity_value in available_rarities:
			roll -= float(CardDefinition.RARITY_DROP_CHANCES.get(rarity_value, 0.0))
			if roll <= 0.0:
				chosen_rarity = int(rarity_value)
				break
		var rarity_cards := available_rarities[chosen_rarity] as Array
		var chosen_id := StringName(rarity_cards[_rng.randi_range(0, rarity_cards.size() - 1)])
		selected.append(chosen_id)
		available.erase(chosen_id)
	return selected
