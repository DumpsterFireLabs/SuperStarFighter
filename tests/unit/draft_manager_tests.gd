class_name DraftManagerTests
extends RefCounted


static func run(context: TestContext) -> void:
	var catalog := CardCatalog.create_default()
	_validate_seeded_offers(context, catalog)
	_validate_selection_and_timeout(context, catalog)
	_validate_unlimited_stack_offers(context, catalog)
	_validate_skipped_winner(context, catalog)


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
		context.expect_equal(first_offer.token.length(), NetworkProtocol.AUTH_PROOF_HEX_LENGTH, "draft offer token uses a bounded opaque digest for peer %d" % peer_id)
		context.expect_false("424242" in first_offer.token, "draft offer token does not disclose the match seed for peer %d" % peer_id)
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


static func _validate_unlimited_stack_offers(context: TestContext, catalog: CardCatalog) -> void:
	var stacked_player := PlayerMatchState.new(1, "Unbounded", 1)
	for card_id in catalog.all_ids():
		stacked_player.card_stacks[card_id] = 999
	var players := {1: stacked_player}
	var manager := DraftManager.new(catalog, 77)
	manager.start_draft(players, 10)
	var offer := manager.get_offer(1)
	context.expect_equal(offer.card_ids.size(), GameConstants.CARD_OFFER_SIZE, "even massively stacked builds still receive five cards")
	context.expect_false(offer.build_complete, "builds never become complete from stacking")
	context.expect_false(offer.locked, "unlimited stacks still require a draft selection")
	var selected_card := offer.card_ids[0]
	context.expect_equal(manager.select_card(1, offer.token, selected_card), DraftManager.SelectionResult.ACCEPTED, "an already heavily stacked card remains selectable")
	manager.apply_locked_selections(players)
	context.expect_equal(stacked_player.card_stack(selected_card), 1000, "draft resolution increments a card beyond every former cap")


static func _validate_skipped_winner(context: TestContext, catalog: CardCatalog) -> void:
	var players := _create_players(3)
	var manager := DraftManager.new(catalog, 31337)
	manager.start_draft(players, 2, [2])
	var winner_offer := manager.get_offer(2)
	context.expect_true(winner_offer.skipped, "previous round winner is marked as skipping the draft")
	context.expect_true(winner_offer.locked, "round-winner draft bye never blocks other players")
	context.expect_empty(winner_offer.card_ids, "round winner receives no card offer")
	context.expect_equal(manager.get_offer(1).card_ids.size(), 5, "non-winner still receives five cards")
	manager.resolve_timeout()
	var applied := manager.apply_locked_selections(players)
	context.expect_equal(applied[2], &"", "round-winner draft bye applies no card")
	context.expect_empty((players[2] as PlayerMatchState).card_stacks, "round winner gains no stack")
	context.expect_equal((players[1] as PlayerMatchState).card_stacks.size(), 1, "non-winner gains an upgrade")


static func _create_players(count: int) -> Dictionary:
	var players: Dictionary = {}
	for peer_id in range(1, count + 1):
		players[peer_id] = PlayerMatchState.new(peer_id, "Player%d" % peer_id, peer_id)
	return players
