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
var _active: bool = false


func _init(catalog: CardCatalog, match_seed: int) -> void:
	_catalog = catalog
	_match_seed = match_seed
	_rng.seed = match_seed


func start_draft(players: Dictionary, round_number: int) -> Dictionary:
	_offers.clear()
	_active = true
	var peer_ids := players.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var player := players[peer_id] as PlayerMatchState
		if not player.connected or not player.participant:
			continue
		_token_serial += 1
		var offer := DraftOffer.new(
			peer_id,
			"%d:%d:%d:%d" % [_match_seed, round_number, peer_id, _token_serial]
		)
		var eligible := _catalog.eligible_ids(player.card_stacks)
		_shuffle(eligible)
		var offer_count := mini(GameConstants.CARD_OFFER_SIZE, eligible.size())
		for index in range(offer_count):
			offer.card_ids.append(eligible[index])
		if offer.card_ids.is_empty():
			offer.build_complete = true
			offer.locked = true
		_offers[peer_id] = offer
	return _offers


func get_offer(peer_id: int) -> DraftOffer:
	return _offers.get(peer_id) as DraftOffer


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
		offer.selected_card_id = offer.card_ids[_rng.randi_range(0, offer.card_ids.size() - 1)]
		offer.locked = true


func apply_locked_selections(players: Dictionary) -> Dictionary:
	var applied: Dictionary = {}
	if not all_locked():
		return applied
	var peer_ids := _offers.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var offer := get_offer(peer_id)
		if offer.build_complete:
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


func _shuffle(values: Array[StringName]) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary

