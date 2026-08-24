class_name DraftManagerTests
extends RefCounted


static func run(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	_validate_seeded_offers(context, catalog)
	_validate_selection_and_timeout(context, catalog)
	_validate_reduced_and_complete_offers(context, catalog)


static func _validate_seeded_offers(context: TestContext, catalog: CardCatalog) -> void:
	var first_players := _create_players(3)
	var second_players := _create_players(3)
	var first := DraftManager.new(catalog, 424242)
	var second := DraftManager.new(catalog, 424242)
	first.start_draft(first_players, 1)
	second.start_draft(second_players, 1)
	for peer_id in first_players:
		var first_offer := first.get_offer(peer_id)
		var second_offer := second.get_offer(peer_id)
		context.expect_equal(first_offer.token, second_offer.token, "fixed seed reproduces offer token for peer %d" % peer_id)
		context.expect_equal(first_offer.card_ids, second_offer.card_ids, "fixed seed reproduces cards for peer %d" % peer_id)
		context.expect_equal(first_offer.card_ids.size(), GameConstants.CARD_OFFER_SIZE, "peer %d receives five eligible cards" % peer_id)
		var unique_cards: Dictionary = {}
		for card_id in first_offer.card_ids:
			unique_cards[card_id] = true
			context.expect_true(catalog.has_card(card_id), "offer card %s exists in catalog" % card_id)
		context.expect_equal(unique_cards.size(), first_offer.card_ids.size(), "peer %d offer contains no duplicate card IDs" % peer_id)


static func _validate_selection_and_timeout(context: TestContext, catalog: CardCatalog) -> void:
	var players := _create_players(3)
	var manager := DraftManager.new(catalog, 9001)
	manager.start_draft(players, 2)
	var first_offer := manager.get_offer(1)
	context.expect_equal(
		manager.select_card(1, "stale-token", first_offer.card_ids[0]),
		DraftManager.SelectionResult.STALE_TOKEN,
		"stale draft token is rejected"
	)
	var unoffered_id: StringName
	for card_id in catalog.all_ids():
		if card_id not in first_offer.card_ids:
			unoffered_id = card_id
			break
	context.expect_equal(
		manager.select_card(1, first_offer.token, unoffered_id),
		DraftManager.SelectionResult.CARD_NOT_OFFERED,
		"card outside the private offer is rejected"
	)
	var chosen_card := first_offer.card_ids[0]
	context.expect_equal(
		manager.select_card(1, first_offer.token, chosen_card),
		DraftManager.SelectionResult.ACCEPTED,
		"valid card selection locks"
	)
	context.expect_equal(
		manager.select_card(1, first_offer.token, first_offer.card_ids[1]),
		DraftManager.SelectionResult.ALREADY_LOCKED,
		"locked selection cannot be changed"
	)
	context.expect_false(manager.all_locked(), "draft remains open while other players have not selected")
	for player in players.values():
		context.expect_equal((player as PlayerMatchState).card_stacks.size(), 0, "locked choices do not apply before draft resolution")
	manager.resolve_timeout()
	context.expect_true(manager.all_locked(), "timeout locks every remaining offer")
	for peer_id in players:
		var offer := manager.get_offer(peer_id)
		context.expect_true(offer.selected_card_id in offer.card_ids, "timeout selection for peer %d comes from its offer" % peer_id)
	var applied := manager.apply_locked_selections(players)
	context.expect_equal(applied.size(), players.size(), "all locked choices apply simultaneously")
	for player in players.values():
		var typed_player := player as PlayerMatchState
		context.expect_equal(typed_player.card_stacks.size(), 1, "each player gains exactly one card")
	context.expect_false(manager.is_active(), "draft closes after applying selections")
	context.expect_equal(
		manager.select_card(1, first_offer.token, chosen_card),
		DraftManager.SelectionResult.NO_ACTIVE_DRAFT,
		"selection after draft resolution is rejected"
	)


static func _validate_reduced_and_complete_offers(context: TestContext, catalog: CardCatalog) -> void:
	var reduced_player := PlayerMatchState.new(1, "Reduced", 1)
	var remaining_ids: Array[StringName] = [
		&"reinforced_hull",
		&"quick_charge",
		&"heavy_rounds",
	]
	for card_id in catalog.all_ids():
		var card := catalog.get_card(card_id)
		reduced_player.card_stacks[card_id] = card.max_stacks if card_id not in remaining_ids else card.max_stacks - 1
	var reduced_players := {1: reduced_player}
	var reduced_manager := DraftManager.new(catalog, 77)
	reduced_manager.start_draft(reduced_players, 10)
	var reduced_offer := reduced_manager.get_offer(1)
	context.expect_equal(reduced_offer.card_ids.size(), 3, "draft offers every eligible card when fewer than five remain")
	for card_id in reduced_offer.card_ids:
		context.expect_true(card_id in remaining_ids, "reduced offer contains only eligible cards")

	var complete_player := PlayerMatchState.new(2, "Complete", 2)
	for card_id in catalog.all_ids():
		complete_player.card_stacks[card_id] = catalog.get_card(card_id).max_stacks
	var complete_players := {2: complete_player}
	var complete_manager := DraftManager.new(catalog, 77)
	complete_manager.start_draft(complete_players, 10)
	var complete_offer := complete_manager.get_offer(2)
	context.expect_true(complete_offer.build_complete, "fully capped build is marked complete")
	context.expect_true(complete_offer.locked, "fully capped build requires no selection")
	context.expect_empty(complete_offer.card_ids, "fully capped build receives no inert choices")
	context.expect_true(complete_manager.all_locked(), "build-complete-only draft is immediately locked")
	var applied := complete_manager.apply_locked_selections(complete_players)
	context.expect_true(applied.has(2), "build-complete resolution records the player")
	context.expect_equal(applied[2], &"", "build-complete resolution applies no card")


static func _create_players(count: int) -> Dictionary:
	var players: Dictionary = {}
	for peer_id in range(1, count + 1):
		players[peer_id] = PlayerMatchState.new(peer_id, "Player%d" % peer_id, peer_id)
	return players
