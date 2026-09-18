@tool
extends McpTestSuite

func suite_name() -> String:
	return "card"


func test_card_defaults() -> void:
	var c: Card = Card.new()
	assert_eq(c.type, Card.CardType.NUMBER, "default type should be NUMBER")
	assert_eq(c.color, Card.CardColor.NONE, "default color should be NONE")
	assert_eq(c.number, -1, "default number should be -1")
	assert_eq(c.action_id, "", "default action_id empty")
	assert_eq(c.display_name, "", "default display_name empty")


func test_number_card_matches_color_or_number() -> void:
	var red5 := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 5, "", "RED 5")
	assert_true(red5.matches(Card.CardColor.RED, 3), "matches active color")
	assert_true(red5.matches(Card.CardColor.BLUE, 5), "matches active number")
	assert_false(red5.matches(Card.CardColor.BLUE, 3), "does not match unrelated color/number")


func test_number_card_zero_only_matches_its_color_or_zero() -> void:
	var blue0 := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 0, "", "BLUE 0")
	assert_true(blue0.matches(Card.CardColor.BLUE, 7), "zero matches its color")
	assert_true(blue0.matches(Card.CardColor.RED, 0), "zero matches number 0")
	assert_false(blue0.matches(Card.CardColor.RED, 7), "zero does not match unrelated")


func test_action_card_matches_color() -> void:
	var green_skip := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.GREEN, -1, "skip", "GREEN Skip")
	assert_true(green_skip.matches(Card.CardColor.GREEN, -1), "matches active color")
	assert_false(green_skip.matches(Card.CardColor.RED, -1), "does not match different color")


func test_action_card_matches_same_action_across_colors() -> void:
	# A Red Reverse is playable on a Green Reverse (same action, different color).
	var red_reverse := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.RED, -1, "reverse", "RED Reverse")
	assert_true(red_reverse.matches(Card.CardColor.GREEN, -1, "reverse"), "red reverse on green reverse")
	# And the reverse direction too.
	var green_reverse := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.GREEN, -1, "reverse", "GREEN Reverse")
	assert_true(green_reverse.matches(Card.CardColor.RED, -1, "reverse"), "green reverse on red reverse")


func test_action_card_no_cross_action_match() -> void:
	# Same color, but a DIFFERENT action still needs its own color match logic:
	# a blue skip must NOT match red active via a red skip's action_id.
	var blue_skip := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.BLUE, -1, "skip", "BLUE Skip")
	assert_false(blue_skip.matches(Card.CardColor.RED, -1, "draw_two"), "blue skip not a draw_two stack")
	assert_false(blue_skip.matches(Card.CardColor.RED, -1, "reverse"), "blue skip not matchable via reverse action")


func test_draw_cards_color_locked_in_normal_play() -> void:
	# A RED Draw Two must NOT be playable on a GREEN Draw Two in normal play:
	# cross-color +N plays only exist through the forced-draw stacking bypass.
	var red_draw_two := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.RED, -1, "draw_two", "RED Draw Two")
	assert_false(red_draw_two.matches(Card.CardColor.GREEN, -1, "draw_two"), "red +2 not playable on green +2")
	# Same color +N still matches.
	assert_true(red_draw_two.matches(Card.CardColor.RED, -1, "draw_two"), "red +2 matches red +2")
	# Same-color different +N value does NOT match (no free stacking outside forced draws).
	var red_draw_four := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.RED, -1, "draw_four", "RED Draw Four")
	assert_false(red_draw_four.matches(Card.CardColor.RED, -1, "draw_two"), "red +4 not playable on red +2")


func test_action_card_matches_own_action_with_empty_active() -> void:
	# Default active_action_id "" -> only color matching applies (backwards compatible).
	var blue_reverse := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.BLUE, -1, "reverse", "BLUE Reverse")
	assert_false(blue_reverse.matches(Card.CardColor.RED, -1), "no action id -> color only")


func test_anytime_action_cards_always_match() -> void:
	var anytime_ids := ["swap_hands", "peek", "extra_life", "choose_deck", "rotate_decks", "draw_ten"]
	for aid in anytime_ids:
		var card := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.NONE, -1, aid, aid)
		assert_true(card.matches(Card.CardColor.RED, 3), "%s should always match" % aid)


func test_wild_always_matches() -> void:
	var wild := CardDatabase._make(Card.CardType.WILD, Card.CardColor.NONE, -1, "wild_color", "Wild")
	assert_true(wild.matches(Card.CardColor.RED, -1), "wild matches any active state")
	assert_true(wild.matches(Card.CardColor.BLUE, 5), "wild matches color+number too")


func test_respawn_always_matches() -> void:
	var respawn := CardDatabase._make(Card.CardType.RESPAWN, Card.CardColor.NONE, -1, "respawn", "RESPAWN")
	assert_true(respawn.matches(Card.CardColor.YELLOW, 8), "respawn plays anytime")


func test_bomb_never_matches() -> void:
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	assert_false(bomb.matches(Card.CardColor.RED, -1), "bomb is never playable from hand")


func test_diffuse_never_matches() -> void:
	var diffuse := CardDatabase._make(Card.CardType.DIFFUSE, Card.CardColor.NONE, -1, "diffuse", "Diffuse")
	assert_false(diffuse.matches(Card.CardColor.RED, -1), "diffuse is never a normal play")


func test_to_dict_roundtrip() -> void:
	var c := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.BLUE, -1, "reverse", "BLUE Reverse")
	var d: Dictionary = c.to_dict()
	assert_eq(d["type"], Card.CardType.ACTION)
	assert_eq(d["color"], Card.CardColor.BLUE)
	assert_eq(d["action_id"], "reverse")
	assert_eq(d["display_name"], "BLUE Reverse")

	var rebuilt: Card = Card.from_dict(d)
	assert_eq(rebuilt.type, Card.CardType.ACTION, "type survives roundtrip")
	assert_eq(rebuilt.color, Card.CardColor.BLUE, "color survives roundtrip")
	assert_eq(rebuilt.number, -1, "number survives roundtrip")
	assert_eq(rebuilt.action_id, "reverse", "action_id survives roundtrip")
	assert_eq(rebuilt.display_name, "BLUE Reverse", "display_name survives roundtrip")


func test_from_dict_missing_keys_get_defaults() -> void:
	var c: Card = Card.from_dict({})
	assert_eq(c.type, Card.CardType.NUMBER, "missing type defaults to NUMBER")
	assert_eq(c.color, Card.CardColor.NONE, "missing color defaults to NONE")
	assert_eq(c.number, -1, "missing number defaults to -1")
	assert_eq(c.action_id, "", "missing action_id defaults to empty")
	assert_eq(c.display_name, "", "missing display_name defaults to empty")


func test_from_dict_wrong_types_coerced() -> void:
	var c: Card = Card.from_dict({
		"type": "5",
		"color": 2.7,
		"number": "42",
		"action_id": 123,
		"display_name": true,
	})
	# int() coercion
	assert_eq(c.type, 5, "string type coerced to int")
	assert_eq(c.color, 2, "float color truncated to int")
	assert_eq(c.number, 42, "string number coerced")
	assert_eq(c.action_id, "123", "int action_id stringified")
	assert_eq(c.display_name, "true", "bool display_name stringified")


func test_to_string_returns_display_name() -> void:
	var c := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 7, "", "RED 7")
	assert_eq(str(c), "RED 7")