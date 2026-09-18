@tool
extends McpTestSuite

func suite_name() -> String:
	return "player_data"


func test_init_sets_id_and_name() -> void:
	var p := PlayerData.new(3, "Test Player")
	assert_eq(p.id, 3)
	assert_eq(p.display_name, "Test Player")
	assert_eq(p.hand_size(), 0, "starts with empty hand")
	assert_false(p.eliminated, "starts alive")
	assert_eq(p.banked_lives, 0, "starts with no banked lives")


func test_bank_extra_life_increments() -> void:
	var p := PlayerData.new(0, "P")
	p.bank_extra_life()
	assert_eq(p.banked_lives, 1)
	p.bank_extra_life()
	assert_eq(p.banked_lives, 2, "second life banks")
	p.bank_extra_life()
	assert_eq(p.banked_lives, 2, "banked lives cap at MAX_BANKED_LIVES")


func test_try_absorb_elimination_consumes_life() -> void:
	var p := PlayerData.new(0, "P")
	p.bank_extra_life()
	p.bank_extra_life()
	assert_true(p.try_absorb_elimination(), "absorbs first elimination")
	assert_eq(p.banked_lives, 1)
	assert_true(p.try_absorb_elimination(), "absorbs second elimination")
	assert_eq(p.banked_lives, 0)
	assert_false(p.try_absorb_elimination(), "no lives left, cannot absorb")
	assert_eq(p.banked_lives, 0, "lives never go negative")


func test_hand_size_tracks_hand() -> void:
	var p := PlayerData.new(0, "P")
	var card_a := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 1, "", "A")
	var card_b := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 2, "", "B")
	p.hand.append(card_a)
	assert_eq(p.hand_size(), 1)
	p.hand.append(card_b)
	assert_eq(p.hand_size(), 2)
	p.hand.remove_at(0)
	assert_eq(p.hand_size(), 1)