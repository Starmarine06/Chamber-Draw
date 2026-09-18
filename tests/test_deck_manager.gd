@tool
extends McpTestSuite

func suite_name() -> String:
	return "deck_manager"


func _make_number(color: int, number: int) -> Card:
	return CardDatabase._make(Card.CardType.NUMBER, color, number, "", "N")


func test_setup_distributes_cards_evenly() -> void:
	var dm := DeckManager.new()
	dm.setup(4)
	var total := dm.pile_a.size() + dm.pile_b.size()
	# 4 players -> 8 bombs, 9 diffuses; safe pool = numbers(76) + colored actions(28) + colorless(16+8 extra lives) + wilds(6)
	var expected := CardDatabase.build_safe_pool(4).size() + CardDatabase.bomb_count_for(4) + CardDatabase.diffuse_count_for(4)
	assert_eq(total, expected, "setup deals the full pool")
	# Safe pool and bombs are dealt evenly; the only allowed imbalance is the
	# random scatter of Diffuse cards into either pile, so bound by that count.
	assert_true(abs(dm.pile_a.size() - dm.pile_b.size()) <= CardDatabase.diffuse_count_for(4), "piles are roughly even (diffuse scatter bound)")


func test_setup_places_bombs_in_both_decks() -> void:
	var dm := DeckManager.new()
	dm.setup(4)
	var bombs_a := 0
	for c in dm.pile_a:
		if c.type == Card.CardType.BOMB:
			bombs_a += 1
	var bombs_b := 0
	for c in dm.pile_b:
		if c.type == Card.CardType.BOMB:
			bombs_b += 1
	assert_eq(bombs_a, 4, "deck A holds 4 bombs for 4 players")
	assert_eq(bombs_b, 4, "deck B holds 4 bombs for 4 players")


func test_draw_from_empty_pile_splits_discard() -> void:
	var dm := DeckManager.new()
	dm.setup(4)
	# Seed the discard pile with played cards.
	for _i in range(6):
		dm.discard_card(dm.draw_from("A"))

	# Empty pile A WITHOUT drawing it dry: draw_from() splits the discard the
	# moment A runs out of cards, which would consume it mid-drain.
	dm.pile_a.clear()
	dm.pile_b.clear()
	assert_eq(dm.discard.size(), 6, "discard holds the played cards")
	assert_true(dm.pile_a.is_empty(), "pile A is empty")

	# Draw from the empty pile -> discard is split between both piles
	var card := dm.draw_from("A")
	assert_true(card != null, "draws from the freshly built pile")
	assert_true(dm.discard.is_empty(), "discard was consumed by the split")
	assert_eq(dm.pile_a.size() + dm.pile_b.size(), 5, "6 redealt, one already drawn")


func test_draw_from_truly_empty_returns_null() -> void:
	var dm := DeckManager.new()
	# No cards anywhere
	var card := dm.draw_from("A")
	assert_eq(card, null)


func test_discard_card_appends() -> void:
	var dm := DeckManager.new()
	var card := _make_number(Card.CardColor.RED, 3)
	dm.discard_card(card)
	assert_eq(dm.discard.size(), 1)
	assert_eq(dm.discard[0], card)


func test_rotate_decks_preserves_card_set() -> void:
	var dm := DeckManager.new()
	dm.setup(4)
	var before_a: Array = dm.pile_a.duplicate()
	var before_b: Array = dm.pile_b.duplicate()
	var before_total := before_a.size() + before_b.size()

	dm.rotate_decks()
	assert_eq(dm.pile_a.size() + dm.pile_b.size(), before_total, "total preserved")
	assert_true(abs(dm.pile_a.size() - dm.pile_b.size()) <= 1, "evenly redealt")

	# Set membership preserved (same Card instances)
	var all_after: Array = []
	all_after.append_array(dm.pile_a)
	all_after.append_array(dm.pile_b)
	for c in before_a + before_b:
		assert_true(all_after.has(c), "card still present after rotate")


func test_peek_returns_top_n_without_removing() -> void:
	var dm := DeckManager.new()
	dm.pile_a.append(_make_number(Card.CardColor.RED, 1))
	dm.pile_a.append(_make_number(Card.CardColor.BLUE, 2))
	dm.pile_a.append(_make_number(Card.CardColor.GREEN, 3))
	var before_size := dm.pile_a.size()
	var top := dm.peek("A", 2)
	assert_eq(top.size(), 2, "returns 2 cards")
	assert_eq(top[0].number, 2, "second-from-top first in peek result")
	assert_eq(top[1].number, 3, "top card last in peek result")
	assert_eq(dm.pile_a.size(), before_size, "peek does not remove")


func test_peek_clamps_to_pile_size() -> void:
	var dm := DeckManager.new()
	dm.pile_a.append(_make_number(Card.CardColor.RED, 1))
	var top := dm.peek("A", 50)
	assert_eq(top.size(), 1, "peek clamps to available cards")


func test_reorder_top_orders_requested_slice() -> void:
	var dm := DeckManager.new()
	var c1 := _make_number(Card.CardColor.RED, 1)
	var c2 := _make_number(Card.CardColor.BLUE, 2)
	var c3 := _make_number(Card.CardColor.GREEN, 3)
	dm.pile_a.append(c1)
	dm.pile_a.append(c2)
	dm.pile_a.append(c3)

	# Swap top two: [c1, c3, c2]
	dm.reorder_top("A", [c3, c2])
	assert_eq(dm.pile_a[0], c1, "bottom card untouched")
	assert_eq(dm.pile_a[1], c3, "reordered top first")
	assert_eq(dm.pile_a[2], c2, "reordered top second")


func test_return_bomb_randomly_inserts_card() -> void:
	var dm := DeckManager.new()
	dm.setup(2)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	var before_a := dm.pile_a.size()
	var before_b := dm.pile_b.size()
	dm.return_bomb_randomly(bomb)
	assert_eq(dm.pile_a.size() + dm.pile_b.size(), before_a + before_b + 1, "one card added across piles")
	assert_true(dm.pile_a.has(bomb) or dm.pile_b.has(bomb), "bomb returned to a pile")


func test_add_respawn_cards_places_exact_count() -> void:
	var dm := DeckManager.new()
	dm.setup(2)
	var before := dm.pile_a.size() + dm.pile_b.size()
	dm.add_respawn_cards(4)
	assert_eq(dm.pile_a.size() + dm.pile_b.size(), before + 4, "4 respawn cards added")
	var count := 0
	for c in dm.pile_a + dm.pile_b:
		if c.type == Card.CardType.RESPAWN:
			count += 1
	assert_eq(count, 4)


func test_remove_respawn_cards_removes_exact_count() -> void:
	var dm := DeckManager.new()
	dm.setup(2)
	dm.add_respawn_cards(3)
	var removed := dm.remove_respawn_cards()
	assert_eq(removed, 3, "removes the 3 that were added")
	var count := 0
	for c in dm.pile_a + dm.pile_b:
		if c.type == Card.CardType.RESPAWN:
			count += 1
	assert_eq(count, 0, "no respawn cards remain")


func test_remove_respawn_cards_with_none_returns_zero() -> void:
	var dm := DeckManager.new()
	dm.setup(2)
	assert_eq(dm.remove_respawn_cards(), 0, "no respawns to remove")


func test_draw_from_alternates_properly() -> void:
	var dm := DeckManager.new()
	dm.setup(4)
	var start_total := dm.pile_a.size() + dm.pile_b.size()
	# Drawing pops from the END of each pile
	var from_a: Card = dm.draw_from("A")
	var from_b: Card = dm.draw_from("B")
	assert_true(from_a != null, "draws from A")
	assert_true(from_b != null, "draws from B")
	assert_eq(dm.pile_a.size() + dm.pile_b.size(), start_total - 2, "draws reduce the pool")