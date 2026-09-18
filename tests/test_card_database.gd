@tool
extends McpTestSuite

func suite_name() -> String:
	return "card_database"


func test_bomb_count_scales_2_per_player() -> void:
	assert_eq(CardDatabase.bomb_count_for(2), 4)
	assert_eq(CardDatabase.bomb_count_for(4), 8)
	assert_eq(CardDatabase.bomb_count_for(7), 14)


func test_diffuse_count_is_bomb_count_plus_one() -> void:
	for n in [2, 3, 4, 5, 6, 7]:
		assert_eq(CardDatabase.diffuse_count_for(n), CardDatabase.bomb_count_for(n) + 1)


func test_extra_life_count_is_2_per_player() -> void:
	assert_eq(CardDatabase.extra_life_count_for(2), 4)
	assert_eq(CardDatabase.extra_life_count_for(4), 8)
	assert_eq(CardDatabase.extra_life_count_for(7), 14)


func test_safe_pool_contains_expected_counts() -> void:
	var pool := CardDatabase.build_safe_pool(4)

	# Numbers: 4 colors * (1 zero + 9 numbers * 2 copies)
	assert_eq(_count_type(pool, Card.CardType.NUMBER, ""), 4 * (1 + 9 * 2), "number card count")

	# Colored actions: 4 colors * (2 skip + 2 reverse + 2 draw_two + 1 draw_four)
	assert_eq(_count_action(pool, "skip"), 4 * 2, "skip count")
	assert_eq(_count_action(pool, "reverse"), 4 * 2, "reverse count")
	assert_eq(_count_action(pool, "draw_two"), 4 * 2, "draw_two count")
	assert_eq(_count_action(pool, "draw_four"), 4 * 1, "draw_four count")

	# Colorless actions (fixed counts)
	assert_eq(_count_action(pool, "swap_hands"), 4, "swap_hands count")
	assert_eq(_count_action(pool, "peek"), 4, "peek count")
	assert_eq(_count_action(pool, "choose_deck"), 4, "choose_deck count")
	assert_eq(_count_action(pool, "rotate_decks"), 3, "rotate_decks count")
	assert_eq(_count_action(pool, "draw_ten"), 1, "draw_ten count")

	# Extra life scales with players
	assert_eq(_count_action(pool, "extra_life"), CardDatabase.extra_life_count_for(4), "extra_life count")

	# Wilds
	assert_eq(_count_action(pool, "wild_color"), 4, "wild_color count")
	assert_eq(_count_action(pool, "wild_sabotage"), 2, "wild_sabotage count")

	# No bombs or diffuses in safe pool
	assert_eq(_count_type(pool, Card.CardType.BOMB, ""), 0, "no bombs in safe pool")


func test_safe_pool_scales_extra_life_with_players() -> void:
	var pool_2 := CardDatabase.build_safe_pool(2)
	var pool_7 := CardDatabase.build_safe_pool(7)
	assert_eq(_count_action(pool_2, "extra_life"), 4, "2 players get 4 extra lives")
	assert_eq(_count_action(pool_7, "extra_life"), 14, "7 players get 14 extra lives")


func test_threat_cards_match_counts() -> void:
	for n in [2, 4, 7]:
		var threats := CardDatabase.build_threat_cards(n)
		assert_eq(_count_type(threats, Card.CardType.BOMB, ""), CardDatabase.bomb_count_for(n), "bomb count for %d players" % n)
		assert_eq(_count_type(threats, Card.CardType.DIFFUSE, ""), CardDatabase.diffuse_count_for(n), "diffuse count for %d players" % n)


func test_threat_cards_are_properly_flagged() -> void:
	var threats := CardDatabase.build_threat_cards(4)
	for t in threats:
		if t.type == Card.CardType.BOMB:
			assert_eq(t.action_id, "bomb")
			assert_eq(t.color, Card.CardColor.NONE)
			assert_eq(t.number, -1)
		else:
			assert_eq(t.type, Card.CardType.DIFFUSE)
			assert_eq(t.action_id, "diffuse")


func test_safe_pool_cards_have_valid_display_names() -> void:
	var pool := CardDatabase.build_safe_pool(4)
	for c in pool:
		assert_false(c.display_name.is_empty(), "card display name: %s" % str(c.type))
		if c.type == Card.CardType.NUMBER:
			assert_true(c.number >= 0 and c.number <= 9, "number card number in range")


func test_safe_pool_no_duplicate_object_refs() -> void:
	var pool := CardDatabase.build_safe_pool(4)
	# Ensure every card is a distinct instance
	var seen: Dictionary = {}
	for c in pool:
		assert_false(seen.has(c), "duplicate Card instance %s" % str(c))
		seen[c] = true


func _count_type(cards: Array, card_type: int, _action: String) -> int:
	var n := 0
	for c in cards:
		if c.type == card_type:
			n += 1
	return n


func _count_action(cards: Array, action_id: String) -> int:
	var n := 0
	for c in cards:
		if c.action_id == action_id:
			n += 1
	return n