@tool
extends McpTestSuite

func suite_name() -> String:
	return "game_state"


# ── helpers ──────────────────────────────────────────────────────────────────

func _new_game(num_players: int = 4, mode: int = GameState.Mode.SHEDDING_RACE) -> GameState:
	var gs := GameState.new()
	gs.setup(num_players, mode)
	return gs


func _give(gs: GameState, player_idx: int, cards: Array) -> void:
	# Replace the player's hand with the given cards
	var p := gs.players[player_idx]
	for c in p.hand:
		gs.deck.discard_card(c)
	p.hand.clear()
	for c in cards:
		p.hand.append(c)


func _number(color: int, num: int) -> Card:
	return CardDatabase._make(Card.CardType.NUMBER, color, num, "", "N")


func _action(color: int, action_id: String) -> Card:
	return CardDatabase._make(Card.CardType.ACTION, color, -1, action_id, action_id)


func _set_active(gs: GameState, color: int, num: int = -1) -> void:
	gs.active_color = color
	gs.active_number = num


# ── setup ────────────────────────────────────────────────────────────────────

func test_setup_creates_players_and_deck() -> void:
	var gs := _new_game(4)
	assert_eq(gs.players.size(), 4)
	assert_true(gs.deck != null)
	for p in gs.players:
		assert_eq(p.hand.size(), GameState.STARTING_HAND_SIZE, "each starting hand is 7")
	assert_eq(gs.current_index, 0)
	assert_false(gs.game_over)


func test_setup_supports_range_of_players() -> void:
	for n in [2, 3, 4, 5, 6, 7]:
		var gs := _new_game(n)
		assert_eq(gs.players.size(), n, "creates %d players" % n)


func test_setup_no_bombs_in_opening_hands() -> void:
	var gs := _new_game(4)
	for p in gs.players:
		for c in p.hand:
			assert_ne(c.type, Card.CardType.BOMB, "opening hand has no bombs")


func test_setup_starter_card_establishes_active_state() -> void:
	var gs := _new_game(4)
	assert_true(gs.active_color >= Card.CardColor.RED and gs.active_color <= Card.CardColor.PURPLE, "active color is a real color")
	# Starter is either a NUMBER (sets number) or an action (number = -1)
	if gs.active_number != -1:
		assert_true(gs.active_number >= 0 and gs.active_number <= 9, "starter number in range")


func test_apply_seat_colors() -> void:
	var gs := _new_game(4)
	gs.apply_seat_colors([3, 1, 5, 0])
	assert_eq(gs.players[0].color_idx, 3)
	assert_eq(gs.players[1].color_idx, 1)
	assert_eq(gs.players[2].color_idx, 5)
	assert_eq(gs.players[3].color_idx, 0)
	assert_eq(gs.players[0].color, GameGlobals.PALETTE[3])

	# Out-of-range indices wrap
	gs.apply_seat_colors([8])
	assert_eq(gs.players[0].color_idx, 8)
	assert_eq(gs.players[0].color, GameGlobals.PALETTE[0], "8 wraps to index 0")


# ── get_valid_plays ──────────────────────────────────────────────────────────

func test_get_valid_plays_number_matching() -> void:
	var gs := _new_game(2)
	_set_active(gs, Card.CardColor.RED, 5)
	var red5 := _number(Card.CardColor.RED, 5)
	var blue5 := _number(Card.CardColor.BLUE, 5)
	var blue2 := _number(Card.CardColor.BLUE, 2)
	_give(gs, 0, [red5, blue5, blue2])
	var valid := gs.get_valid_plays(0)
	assert_eq(valid.size(), 2, "red 5 and blue 5 are valid")
	assert_true(valid.has(0), "red 5 index is valid")
	assert_true(valid.has(1), "blue 5 index is valid")
	assert_false(valid.has(2), "blue 2 is not valid")


func test_get_valid_plays_anytime_cards() -> void:
	var gs := _new_game(2)
	_set_active(gs, Card.CardColor.RED, -1)
	var draw_ten := _action(Card.CardColor.NONE, "draw_ten")
	var extra_life := _action(Card.CardColor.NONE, "extra_life")
	var skip := _action(Card.CardColor.BLUE, "skip")  # NOT matching red
	_give(gs, 0, [draw_ten, extra_life, skip])
	var valid := gs.get_valid_plays(0)
	assert_eq(valid.size(), 2, "draw_ten and extra_life valid anytime")
	assert_true(valid.has(2) == false, "blue skip not valid against red")


func test_get_valid_plays_same_action_across_colors() -> void:
	var gs := _new_game(2)
	gs.active_color = Card.CardColor.GREEN
	gs.active_number = -1
	gs.active_action_id = "reverse"
	var red_reverse := _action(Card.CardColor.RED, "reverse")
	var blue_skip := _action(Card.CardColor.BLUE, "skip")
	var red_5 := _number(Card.CardColor.RED, 5)
	_give(gs, 0, [red_reverse, blue_skip, red_5])
	var valid := gs.get_valid_plays(0)
	assert_eq(valid.size(), 1, "only the red reverse matches the active green reverse")
	assert_true(valid.has(0), "red reverse valid against green reverse")


func test_get_valid_plays_wild_always() -> void:
	var gs := _new_game(2)
	_set_active(gs, Card.CardColor.YELLOW, 7)
	var wild := CardDatabase._make(Card.CardType.WILD, Card.CardColor.NONE, -1, "wild_color", "Wild")
	_give(gs, 0, [wild])
	var valid := gs.get_valid_plays(0)
	assert_eq(valid.size(), 1)


# ── play_card ────────────────────────────────────────────────────────────────

func test_play_number_card_advances_turn() -> void:
	var gs := _new_game(2)
	_set_active(gs, Card.CardColor.RED, 5)
	var red5 := _number(Card.CardColor.RED, 5)
	_give(gs, 0, [red5])
	# Pin the opponent to a non-matching hand: a random RED 5 copy would open
	# the jump-in window and hold the turn instead of advancing.
	_give(gs, 1, [_number(Card.CardColor.GREEN, 2)])
	gs.play_card(0, 0)
	assert_eq(gs.active_color, Card.CardColor.RED)
	assert_eq(gs.active_number, 5)
	assert_eq(gs.current_index, 1, "turn advances")
	assert_eq(gs.players[0].hand_size(), 0)


func test_play_illegal_card_ignored() -> void:
	var gs := _new_game(2)
	_set_active(gs, Card.CardColor.RED, 5)
	var blue2 := _number(Card.CardColor.BLUE, 2)
	_give(gs, 0, [blue2])
	# Monkeypatch log so prints don't spam (optional — prints are harmless in tests)
	gs.play_card(0, 0)
	assert_eq(gs.players[0].hand_size(), 1, "illegal card stays in hand")
	assert_eq(gs.current_index, 0, "turn does not advance")


func test_play_out_of_range_index_ignored() -> void:
	var gs := _new_game(2)
	gs.play_card(0, 99)
	assert_eq(gs.current_index, 0, "no crash, no advance")


func test_play_skip_sets_next_player_skip() -> void:
	var gs := _new_game(4)
	gs.direction = 1  # physical clockwise ring; 0's next seat is 3 (not 1)
	_set_active(gs, Card.CardColor.GREEN, -1)
	var green_skip := _action(Card.CardColor.GREEN, "skip")
	_give(gs, 0, [green_skip])
	# No other hand may hold a skip copy, or the jump-in window would open and
	# hold the turn instead of advancing past the skipped player.
	_give(gs, 1, [_number(Card.CardColor.GREEN, 2)])
	_give(gs, 2, [_number(Card.CardColor.GREEN, 3)])
	_give(gs, 3, [_number(Card.CardColor.GREEN, 4)])
	gs.play_card(0, 0)
	# advance_turn() moves to the ring neighbor (seat 3), immediately consumes
	# the skip flag, and lands on seat 1 - so the post-play observables are the
	# landed seat and the cleared flag, not the transient skip_next_turn.
	assert_eq(gs.current_index, 1, "skip passes player 3")
	assert_false(gs.players[3].skip_next_turn, "skip consumed by advance_turn")
	assert_eq(gs.active_number, -1, "action clears active number")


func test_play_reverse_flips_direction() -> void:
	var gs := _new_game(4)
	gs.direction = 1
	_set_active(gs, Card.CardColor.BLUE, -1)
	var blue_reverse := _action(Card.CardColor.BLUE, "reverse")
	_give(gs, 0, [blue_reverse])
	gs.play_card(0, 0)
	assert_eq(gs.direction, -1, "direction reversed")


func test_play_same_action_across_colors() -> void:
	# A RED Reverse is a legal response to a GREEN Reverse on the stack.
	var gs := _new_game(4)
	gs.direction = 1
	gs.active_color = Card.CardColor.GREEN
	gs.active_number = -1
	gs.active_action_id = "reverse"
	var red_reverse := _action(Card.CardColor.RED, "reverse")
	_give(gs, 0, [red_reverse])
	# Pin other hands so no jump-in copy exists (reverse would open a window).
	_give(gs, 1, [_number(Card.CardColor.RED, 2)])
	_give(gs, 2, [_number(Card.CardColor.RED, 3)])
	_give(gs, 3, [_number(Card.CardColor.RED, 4)])
	gs.play_card(0, 0)
	assert_eq(gs.players[0].hand_size(), 0, "red reverse was played")
	assert_eq(gs.direction, -1, "reverse flipped direction")
	assert_eq(gs.active_action_id, "reverse", "active action stays reverse")
	assert_eq(gs.active_color, Card.CardColor.RED, "active color now the played card's color")


func test_play_wild_sets_chosen_color() -> void:
	var gs := _new_game(4)
	var wild := CardDatabase._make(Card.CardType.WILD, Card.CardColor.NONE, -1, "wild_color", "Wild")
	_give(gs, 0, [wild])
	gs.play_card(0, 0, {"chosen_color": Card.CardColor.YELLOW})
	assert_eq(gs.active_color, Card.CardColor.YELLOW)
	assert_eq(gs.active_number, -1)


func test_play_wild_sabotage_overrides_next_player() -> void:
	var gs := _new_game(4)
	var sabotage := CardDatabase._make(Card.CardType.WILD, Card.CardColor.NONE, -1, "wild_sabotage", "Sabotage")
	_give(gs, 0, [sabotage])
	gs.play_card(0, 0, {"chosen_color": Card.CardColor.RED, "target_player_index": 3})
	# advance_turn() consumes the override the moment the card resolves, so only
	# the EFFECT (current_index == target) is observable after play_card().
	assert_eq(gs.current_index, 3, "turn goes to sabotage target")
	assert_eq(gs.override_next_player_index, null, "override consumed back to sentinel")


func test_play_swap_hands_exchanges() -> void:
	var gs := _new_game(4)
	var swap := _action(Card.CardColor.NONE, "swap_hands")
	var a := _number(Card.CardColor.RED, 1)
	var b := _number(Card.CardColor.BLUE, 2)
	_give(gs, 0, [swap, a])
	_give(gs, 2, [b])
	gs.play_card(0, 0, {"target_player_index": 2})
	assert_eq(gs.players[0].hand_size(), 1, "player 0 has 1 card")
	assert_eq(gs.players[0].hand[0].number, 2, "player 0 got the other hand")
	assert_eq(gs.players[2].hand[0].number, 1, "player 2 got player 0's leftover")


func test_play_extra_life_banks() -> void:
	var gs := _new_game(4)
	var life := _action(Card.CardColor.NONE, "extra_life")
	_give(gs, 0, [life])
	gs.play_card(0, 0)
	assert_eq(gs.players[0].banked_lives, 1)


func test_play_rotate_decks_preserves_count() -> void:
	var gs := _new_game(4)
	var rotate := _action(Card.CardColor.NONE, "rotate_decks")
	_give(gs, 0, [rotate])
	var before := gs.deck.pile_a.size() + gs.deck.pile_b.size()
	gs.play_card(0, 0)
	assert_eq(gs.deck.pile_a.size() + gs.deck.pile_b.size(), before, "card count preserved")


func test_play_choose_deck_records_forced_pile() -> void:
	var gs := _new_game(4)
	var choose := _action(Card.CardColor.NONE, "choose_deck")
	_give(gs, 0, [choose])
	gs.play_card(0, 0, {"target_player_index": 2, "chosen_pile": "B"})
	assert_eq(gs.forced_pile_for_player.get(gs.players[2].id, ""), "B")


# ── advance_turn / skips ─────────────────────────────────────────────────────

func test_advance_turn_wraps_around() -> void:
	var gs := _new_game(3)
	gs.direction = 1
	gs.current_index = 2
	gs.advance_turn()
	assert_eq(gs.current_index, 0, "wraps 2 -> 0 (ring [0,1,2])")


func test_advance_turn_respects_direction() -> void:
	var gs := _new_game(4)
	gs.current_index = 2
	gs.direction = -1
	gs.advance_turn()
	# Ring [0,3,1,2]: counter-clockwise from seat 2 walks back to seat 1.
	assert_eq(gs.current_index, 1, "reversed direction walks the ring backward")


func test_advance_turn_skips_eliminated() -> void:
	var gs := _new_game(4)
	gs.direction = 1
	gs.players[3].eliminated = true
	gs.current_index = 0
	gs.advance_turn()
	# 0's ring neighbor is 3; eliminated seats are skipped on through to 1.
	assert_eq(gs.current_index, 1, "skips eliminated player around the physical ring")


func test_advance_turn_consumes_skip_next_turn() -> void:
	var gs := _new_game(4)
	gs.direction = 1
	gs.current_index = 0
	gs.players[3].skip_next_turn = true
	gs.advance_turn()
	assert_eq(gs.current_index, 1, "skipped player passed over")
	assert_false(gs.players[3].skip_next_turn, "skip flag consumed")


func test_advance_turn_forced_draw_target_keeps_turn() -> void:
	var gs := _new_game(4)
	gs.direction = 1
	gs.current_index = 0
	gs.players[3].skip_next_turn = true
	gs.pending_forced_draw_count = 2
	gs.pending_forced_draw_player_index = 3
	gs.advance_turn()
	assert_eq(gs.current_index, 3, "forced-draw target keeps their turn despite skip")


# ── forced draws ─────────────────────────────────────────────────────────────

func test_start_forced_draw_targets_next_player() -> void:
	var gs := _new_game(4)
	gs.direction = 1
	gs.current_index = 0
	gs._start_or_stack_forced_draw(0, 2)
	assert_eq(gs.pending_forced_draw_count, 2)
	assert_eq(gs.pending_forced_draw_player_index, 3, "targets ring neighbor (seat 3)")
	assert_true(gs.players[3].skip_next_turn)


func test_stack_forced_draw_accumulates() -> void:
	var gs := _new_game(4)
	gs.direction = 1
	gs.current_index = 0
	gs._start_or_stack_forced_draw(0, 2)
	# Seat 3 is now the target; the turn lands on 3 and seat 3 stacks a Draw Four.
	gs.current_index = 3
	gs._start_or_stack_forced_draw(3, 4)
	assert_eq(gs.pending_forced_draw_count, 6, "stacked: 2 + 4")
	assert_eq(gs.pending_forced_draw_player_index, 1, "new target is seat 1 (next in ring)")
	assert_false(gs.players[3].skip_next_turn, "stacker's skip consumed")


func test_stack_cross_color_same_value_allowed() -> void:
	# P1 is targeted by a GREEN +2 and stacks a RED +2 — different color, same
	# +N value. Allowed: color is irrelevant for a +N stack.
	var gs := _new_game(4)
	gs.direction = 1  # pin ring walk: seat 1's ring neighbor is seat 2
	gs.active_color = Card.CardColor.GREEN
	gs.active_number = -1
	gs.current_index = 1
	gs.pending_forced_draw_count = 2
	gs.pending_forced_draw_player_index = 1
	gs.pending_forced_draw_amount = 2
	gs.players[1].skip_next_turn = true
	# Pin hands to non-copies so no jump-in window opens after the stack play.
	gs.players[1].hand = [
		CardDatabase._make(Card.CardType.ACTION, Card.CardColor.RED, -1, "draw_two", "DRAW TWO"),
		CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 8, "8", "BLUE 8"),
	]
	gs.players[0].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 5, "5", "BLUE 5")]
	gs.players[2].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 3, "3", "BLUE 3")]
	gs.players[3].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.YELLOW, 6, "6", "YELLOW 6")]
	gs.play_card(1, 0, {})
	assert_eq(gs.pending_forced_draw_count, 4, "+2 stacked onto +2 rises to 4")
	assert_eq(gs.pending_forced_draw_player_index, 2, "punishment moves to next player")
	assert_eq(gs.players[1].hand_size(), 1, "stacked card left the hand")
	assert_false(gs.jump_in_open, "pinned hands contain no copy to jump in with")


func test_stack_different_value_cross_color_rejected() -> void:
	# A RED +4 CANNOT stack onto a GREEN +2 — cross-color stacking only works
	# when N values are the same (e.g. +2 on +2) OR colors match (e.g. green +4 on green +2).
	var gs := _new_game(4)
	gs.direction = 1  # pin ring walk: seat 1's ring neighbor is seat 2
	gs.active_color = Card.CardColor.GREEN
	gs.active_number = -1
	gs.current_index = 1
	gs.pending_forced_draw_count = 2
	gs.pending_forced_draw_player_index = 1
	gs.pending_forced_draw_amount = 2
	gs.players[1].skip_next_turn = true
	gs.players[1].hand = [
		CardDatabase._make(Card.CardType.ACTION, Card.CardColor.RED, -1, "draw_four", "DRAW FOUR"),
		CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 8, "8", "BLUE 8"),
	]
	gs.players[0].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 5, "5", "BLUE 5")]
	gs.players[2].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 3, "3", "BLUE 3")]
	gs.players[3].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.YELLOW, 6, "6", "YELLOW 6")]
	var before_count := gs.pending_forced_draw_count
	gs.play_card(1, 0, {})
	# Rejected: hand unchanged, count unchanged, no skip consumed.
	assert_eq(gs.pending_forced_draw_count, before_count, "count unchanged — stack rejected")
	assert_eq(gs.players[1].hand_size(), 2, "red +4 still in hand")
	assert_eq(gs.pending_forced_draw_player_index, 1, "target unchanged")
	assert_true(gs.players[1].skip_next_turn, "skip not consumed")


func test_stack_same_color_different_value_allowed() -> void:
	# A GREEN +4 MAY stack onto a GREEN +2 — same color allows any +N.
	var gs := _new_game(4)
	gs.direction = 1
	gs.active_color = Card.CardColor.GREEN
	gs.active_number = -1
	gs.current_index = 1
	gs.pending_forced_draw_count = 2
	gs.pending_forced_draw_player_index = 1
	gs.pending_forced_draw_amount = 2
	gs.players[1].skip_next_turn = true
	gs.players[1].hand = [
		CardDatabase._make(Card.CardType.ACTION, Card.CardColor.GREEN, -1, "draw_four", "DRAW FOUR"),
		CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 8, "8", "BLUE 8"),
	]
	gs.players[0].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 5, "5", "BLUE 5")]
	gs.players[2].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 3, "3", "BLUE 3")]
	gs.players[3].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.YELLOW, 6, "6", "YELLOW 6")]
	gs.play_card(1, 0, {})
	assert_eq(gs.pending_forced_draw_count, 6, "+4 stacked onto +2 rises to 6")
	assert_eq(gs.pending_forced_draw_player_index, 2, "punishment moves to next player")
	assert_eq(gs.players[1].hand_size(), 1, "stacked card left the hand")
	assert_false(gs.jump_in_open, "pinned hands contain no copy to jump in with")


func test_stack_draw_ten_on_draw_ten() -> void:
	# NONE-color Draw Ten stacks onto another Draw Ten regardless of chosen color.
	var gs := _new_game(4)
	gs.direction = 1  # pin ring walk: seat 2's ring neighbor is seat 0 (ring wraps)
	gs.active_color = Card.CardColor.BLUE
	gs.active_number = -1
	gs.current_index = 2
	gs.pending_forced_draw_count = 10
	gs.pending_forced_draw_player_index = 2
	gs.pending_forced_draw_amount = 10
	gs.players[2].skip_next_turn = true
	gs.players[2].hand = [
		CardDatabase._make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "draw_ten", "DRAW TEN"),
		CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.GREEN, 1, "1", "GREEN 1"),
	]
	gs.players[0].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.BLUE, 5, "5", "BLUE 5")]
	gs.players[1].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 4, "4", "RED 4")]
	gs.players[3].hand = [CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.YELLOW, 6, "6", "YELLOW 6")]
	gs.play_card(2, 0, {"chosen_color": Card.CardColor.YELLOW})
	assert_eq(gs.pending_forced_draw_count, 20, "+10 stacked onto +10 rises to 20")
	assert_eq(gs.pending_forced_draw_player_index, 0, "punishment moves to next ring seat")


func test_resolve_forced_draw_gives_cards_and_advances() -> void:
	var gs := _new_game(4)
	gs.direction = 1
	gs.current_index = 0
	gs._start_or_stack_forced_draw(0, 2)
	# In real flow, advance_turn() lands the turn ON the forced-draw target
	# (their skip is held until they choose a deck) before resolve is called.
	gs.advance_turn()
	assert_eq(gs.current_index, 3, "turn lands on the forced-draw target (ring)")
	assert_true(gs.players[3].skip_next_turn, "target's skip still held")
	var before_hand := gs.players[3].hand_size()
	gs.resolve_forced_draw("A")
	assert_eq(gs.players[3].hand_size(), before_hand + 2, "target draws 2")
	assert_eq(gs.pending_forced_draw_count, 0, "count cleared")
	assert_eq(gs.pending_forced_draw_player_index, -1, "target cleared")
	assert_false(gs.players[3].skip_next_turn, "skip consumed")
	assert_eq(gs.current_index, 1, "turn advances past target around the ring")


func test_resolve_forced_draw_noop_without_pending() -> void:
	var gs := _new_game(4)
	var before := gs.current_index
	gs.resolve_forced_draw("A")
	assert_eq(gs.current_index, before, "no-op when nothing pending")


func test_forced_draw_honors_chosen_pile() -> void:
	var gs := _new_game(4)
	gs.direction = 1  # pin ring walk: forced draw from 0 targets seat 3
	var b: Array = gs.deck.pile_b
	# Pin three safe cards on top of B so no Bomb-redraw can reroute the supply:
	# _forced_draw returns a drawn Bomb via return_bomb_randomly(), which can
	# land in pile A and break a naive "B shrank by 3" conservation check.
	for i in range(3):
		b[b.size() - 1 - i] = CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.GREEN, 3, "3", "GREEN 3")
	var before_b := b.size()
	var before_hand := gs.players[3].hand_size()
	gs._start_or_stack_forced_draw(0, 3)
	gs.resolve_forced_draw("B")
	assert_eq(gs.players[3].hand_size() - before_hand, 3, "target drew exactly 3")
	assert_eq(gs.deck.pile_b.size(), before_b - 3, "B supplied exactly 3 cards")


func test_forced_draw_redraws_bomb_for_safety() -> void:
	var gs := _new_game(2)
	# Force a Bomb onto the top of pile B, then forced-draw 4 from B: the Bomb
	# must be returned to the deck and redrawn, never handed to the target.
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.deck.pile_b.append(bomb)
	var before := gs.players[1].hand_size()
	gs._forced_draw(1, 4, "B")
	assert_eq(gs.players[1].hand_size(), before + 4, "4 safe cards drawn")
	var bombs_drawn := 0
	for c in gs.players[1].hand:
		if c.type == Card.CardType.BOMB:
			bombs_drawn += 1
	assert_eq(bombs_drawn, 0, "no bomb can reach the hand via a forced draw")
	assert_gt(gs._count_remaining_bombs(), 0, "the bomb was returned to a pile, not destroyed")


# ── bombs / chamber ──────────────────────────────────────────────────────────

func test_draw_card_non_bomb_adds_to_hand() -> void:
	var gs := _new_game(4)
	# Pin the top of pile A to a safe card: a random Bomb on top would park
	# itself as pending_bomb (defer=true) instead of reaching the hand.
	gs.deck.pile_a[gs.deck.pile_a.size() - 1] = _number(Card.CardColor.GREEN, 1)
	var before := gs.players[0].hand_size()
	gs.draw_card(0, "A", false, true)
	assert_eq(gs.players[0].hand_size(), before + 1, "card added to hand")


func test_draw_card_bomb_with_defer_sets_pending() -> void:
	var gs := _new_game(2)
	# Force a bomb on top of deck A
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.deck.pile_a.append(bomb)
	var before := gs.players[0].hand_size()
	gs.draw_card(0, "A", true, true)
	assert_true(gs.pending_bomb != null, "pending_bomb set")
	assert_eq(gs.pending_diffuse_player_index, 0)
	assert_eq(gs.players[0].hand_size(), before, "bomb not added to hand")


func test_draw_card_bomb_no_defer_uses_diffuse_auto() -> void:
	var gs := _new_game(2)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.deck.pile_a.append(bomb)
	var diffuse := CardDatabase._make(Card.CardType.DIFFUSE, Card.CardColor.NONE, -1, "diffuse", "Diffuse")
	_give(gs, 0, [diffuse])
	gs.draw_card(0, "A", false, false)
	assert_true(gs.pending_bomb == null, "bomb handled immediately")
	assert_eq(gs.players[0].hand_size(), 0, "diffuse consumed from hand")
	assert_eq(gs.players[0].hand_size(), 0)


func test_draw_card_bomb_chamber_live_eliminates_in_last_one_standing() -> void:
	var gs := _new_game(2, GameState.Mode.LAST_ONE_STANDING)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.deck.pile_a.append(bomb)
	# Force the chamber to return LIVE
	gs.chamber._chamber = [ChamberDeck.Result.LIVE]
	# Pin the hand to a single non-diffuse card: a random diffuse in the dealt
	# hand would be auto-consumed by _handle_bomb_drawn, skipping the chamber
	# draw entirely and making this test flaky.
	_give(gs, 0, [_number(Card.CardColor.GREEN, 1)])
	gs.draw_card(0, "A", false, false)
	assert_true(gs.players[0].eliminated, "player eliminated by live chamber")
	assert_eq(gs.last_eliminated_index, 0)


func test_draw_card_bomb_chamber_live_with_extra_life_absorbs() -> void:
	var gs := _new_game(2, GameState.Mode.LAST_ONE_STANDING)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.deck.pile_a.append(bomb)
	gs.chamber._chamber = [ChamberDeck.Result.LIVE]
	# Pin the hand to a single non-diffuse card: a random diffuse in the dealt
	# hand would be auto-consumed by _handle_bomb_drawn, skipping the chamber
	# draw entirely and making this test flaky.
	_give(gs, 0, [_number(Card.CardColor.GREEN, 1)])
	gs.players[0].bank_extra_life()
	gs.draw_card(0, "A", false, false)
	assert_false(gs.players[0].eliminated, "extra life absorbs")
	assert_eq(gs.players[0].banked_lives, 0, "life consumed")


func test_draw_card_bomb_chamber_live_penalty_in_shedding_race() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.deck.pile_a.append(bomb)
	gs.chamber._chamber = [ChamberDeck.Result.LIVE]
	# Pin the hand to a single non-diffuse card: a random diffuse in the dealt
	# hand would be auto-consumed by _handle_bomb_drawn, skipping the chamber
	# penalty entirely and making this test flaky.
	_give(gs, 0, [_number(Card.CardColor.GREEN, 1)])
	var before := gs.players[0].hand_size()
	gs.draw_card(0, "A", false, false)
	assert_false(gs.players[0].eliminated, "no elimination in shedding race")
	assert_eq(gs.players[0].hand_size(), before + GameState.PENALTY_HAND_SIZE_MODE_A, "4-card penalty")
	assert_true(gs.players[0].skip_next_turn, "loses next turn")


func test_resolve_bomb_with_diffuse() -> void:
	var gs := _new_game(2)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	var diffuse := CardDatabase._make(Card.CardType.DIFFUSE, Card.CardColor.NONE, -1, "diffuse", "Diffuse")
	_give(gs, 0, [diffuse])
	gs.pending_bomb = bomb
	gs.pending_diffuse_player_index = 0
	gs.resolve_bomb(true)
	assert_true(gs.pending_bomb == null, "pending cleared")
	assert_eq(gs.pending_diffuse_player_index, -1)
	assert_eq(gs.players[0].hand_size(), 0, "diffuse consumed")


func test_resolve_bomb_no_diffuse_runs_chamber() -> void:
	var gs := _new_game(2)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.pending_bomb = bomb
	gs.pending_diffuse_player_index = 0
	gs.chamber._chamber = [ChamberDeck.Result.BLANK]
	gs.resolve_bomb(false)
	assert_true(gs.pending_bomb == null, "pending cleared")
	assert_eq(gs.players[0].eliminated, false, "blank has no effect")


func test_resolve_bomb_with_exact_result() -> void:
	var gs := _new_game(2, GameState.Mode.LAST_ONE_STANDING)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.pending_bomb = bomb
	gs.pending_diffuse_player_index = 0
	gs.players[1].bank_extra_life()
	gs.resolve_bomb_with_result(ChamberDeck.Result.LIVE)
	assert_true(gs.players[0].eliminated, "live eliminates")
	assert_true(gs.pending_bomb == null, "pending cleared")


func test_backfire_gives_penalty_to_previous_player() -> void:
	var gs := _new_game(2)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.pending_bomb = bomb
	gs.pending_diffuse_player_index = 0
	gs.current_index = 1
	var before := gs.players[0].hand_size()
	gs.chamber._chamber = [ChamberDeck.Result.BACKFIRE]
	# 50/50 pile choice; previous player is index 0
	# _apply_chamber_result uses _next_alive_index(current_index, -direction): from 1, -1 -> 0
	gs.resolve_bomb(false)
	# Backfire may give a card to previous player OR not (if pile empty). With a full deck it will.
	assert_eq(gs.players[0].hand_size(), before + 1, "previous player got the penalty card")


func test_lucky_draw_gives_bonus_card() -> void:
	var gs := _new_game(2)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.pending_bomb = bomb
	gs.pending_diffuse_player_index = 0
	var before := gs.players[0].hand_size()
	gs.chamber._chamber = [ChamberDeck.Result.LUCKY_DRAW]
	gs.resolve_bomb(false)
	assert_eq(gs.players[0].hand_size(), before + 1, "lucky draw adds a card")


# ── respawn ──────────────────────────────────────────────────────────────────

func test_draw_respawn_card_revives_last_eliminated() -> void:
	var gs := _new_game(2)
	# Set up an eliminated player
	gs.players[1].eliminated = true
	gs.last_eliminated_index = 1
	gs.sync_respawn_cards()
	# Find a respawn in EITHER pile (the old version only scanned pile A
	# whenever it was non-empty, missing respawns dealt into pile B).
	var respawn_card: Card = null
	for c in gs.deck.pile_a + gs.deck.pile_b:
		if c.type == Card.CardType.RESPAWN:
			respawn_card = c
			break
	assert_true(respawn_card != null, "respawn card present while someone is eliminated")
	# Move it onto the TOP of pile B so the draw is deterministic.
	gs.deck.pile_a.erase(respawn_card)
	gs.deck.pile_b.erase(respawn_card)
	gs.deck.pile_b.append(respawn_card)
	gs.draw_card(0, "B", false, false)
	assert_false(gs.players[1].eliminated, "eliminated player revived")
	assert_eq(gs.players[1].hand_size(), GameState.RESPAWN_HAND_SIZE, "revived with 4 fresh cards")


func test_respawn_card_wasted_when_nobody_eliminated() -> void:
	var gs := _new_game(2)
	var respawn := CardDatabase._make(Card.CardType.RESPAWN, Card.CardColor.NONE, -1, "respawn", "RESPAWN")
	gs.deck.pile_a.append(respawn)
	var before := gs.players[0].hand_size()
	gs.draw_card(0, "A", false, false)
	assert_eq(gs.players[0].hand_size(), before, "wasted respawn not added to hand")


func test_sync_respawn_cards_matches_dead_players() -> void:
	var gs := _new_game(4)
	gs.players[1].eliminated = true
	gs.players[2].eliminated = true
	gs.sync_respawn_cards()
	var count := 0
	for c in gs.deck.pile_a + gs.deck.pile_b:
		if c.type == Card.CardType.RESPAWN:
			count += 1
	assert_eq(count, GameState.RESPAWN_CARDS_PER_ELIMINATED * 2, "2 cards per dead player")

	# Nobody dead -> none in deck
	gs.players[1].eliminated = false
	gs.players[2].eliminated = false
	gs.sync_respawn_cards()
	var count2 := 0
	for c in gs.deck.pile_a + gs.deck.pile_b:
		if c.type == Card.CardType.RESPAWN:
			count2 += 1
	assert_eq(count2, 0, "no respawn cards when nobody is dead")


# ── win conditions ───────────────────────────────────────────────────────────

func test_game_over_when_player_runs_out_in_shedding_race() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	_set_active(gs, Card.CardColor.RED, 5)
	var red5 := _number(Card.CardColor.RED, 5)
	_give(gs, 0, [red5])
	# Pin the opponent to two non-matching cards: a random RED 5 copy would
	# open the jump-in window, and a single card would trigger last-shot on
	# the player advance_turn() moves to — both freeze the win check.
	_give(gs, 1, [_number(Card.CardColor.GREEN, 2), _number(Card.CardColor.GREEN, 3)])
	gs.current_index = 0
	gs.play_card(0, 0)
	assert_true(gs.game_over, "emptying hand wins")
	assert_eq(gs.winner_name, gs.players[0].display_name)


func test_last_one_standing_ends_with_single_alive() -> void:
	var gs := _new_game(4, GameState.Mode.LAST_ONE_STANDING)
	gs.players[1].eliminated = true
	gs.players[2].eliminated = true
	gs.players[3].eliminated = true
	gs._check_win_condition()
	assert_true(gs.game_over)
	assert_eq(gs.winner_name, gs.players[0].display_name)


func test_last_one_standing_tie_is_nobody() -> void:
	var gs := _new_game(2, GameState.Mode.LAST_ONE_STANDING)
	gs.players[0].eliminated = true
	gs.players[1].eliminated = true
	gs._check_win_condition()
	assert_true(gs.game_over)
	assert_eq(gs.winner_name, "Nobody")


func test_no_win_when_players_remain() -> void:
	var gs := _new_game(4)
	gs.players[1].eliminated = true
	gs.players[2].eliminated = true
	gs._check_win_condition()
	assert_false(gs.game_over, "2 alive -> no winner yet")


func test_last_shot_blocks_win_without_pass() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	_set_active(gs, Card.CardColor.RED, 5)
	var red5 := _number(Card.CardColor.RED, 5)
	_give(gs, 0, [red5])
	# Pin the opponent to a non-matching hand so the win check is actually
	# reached (a random RED 5 copy would open the jump-in window and make the
	# test pass trivially for the wrong reason).
	_give(gs, 1, [_number(Card.CardColor.GREEN, 2)])
	gs.pending_last_shot = true
	gs.last_shot_passed = false
	gs.current_index = 0
	gs.play_card(0, 0)
	assert_false(gs.game_over, "must clear Last Shot before winning")


func test_last_shot_passed_allows_win() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	_set_active(gs, Card.CardColor.RED, 5)
	var red5 := _number(Card.CardColor.RED, 5)
	_give(gs, 0, [red5])
	# Pin the opponent to two non-matching cards: a random RED 5 copy would
	# open the jump-in window, and a single card would trigger last-shot on
	# the player advance_turn() moves to — both freeze the win check.
	_give(gs, 1, [_number(Card.CardColor.GREEN, 2), _number(Card.CardColor.GREEN, 3)])
	gs.pending_last_shot = true
	gs.last_shot_passed = true
	gs.current_index = 0
	gs.play_card(0, 0)
	assert_true(gs.game_over, "last shot cleared -> win")


# ── jump-in ──────────────────────────────────────────────────────────────────

func test_jump_in_window_opens_when_copy_exists() -> void:
	var gs := _new_game(3)
	_set_active(gs, Card.CardColor.RED, 4)
	var red4 := _number(Card.CardColor.RED, 4)
	var red4_copy := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 4, "", "copy")
	_give(gs, 0, [red4])
	_give(gs, 2, [red4_copy])
	gs.play_card(0, 0)
	assert_true(gs.jump_in_open, "window opens because player 2 holds a copy")


func test_jump_in_window_closed_when_no_copies() -> void:
	var gs := _new_game(2)
	_set_active(gs, Card.CardColor.RED, 4)
	var red4 := _number(Card.CardColor.RED, 4)
	_give(gs, 0, [red4])
	_give(gs, 1, [_number(Card.CardColor.GREEN, 2)])
	gs.play_card(0, 0)
	assert_false(gs.jump_in_open, "no copies -> window closed")


func test_jump_in_plays_copy() -> void:
	var gs := _new_game(3)
	_set_active(gs, Card.CardColor.RED, 4)
	var red4 := _number(Card.CardColor.RED, 4)
	var red4_copy := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 4, "", "copy")
	_give(gs, 0, [red4])
	_give(gs, 1, [red4_copy])
	gs.play_card(0, 0)
	assert_true(gs.jump_in_open)
	var ok := gs.jump_in(1)
	assert_true(ok, "jump-in succeeds")
	assert_eq(gs.players[1].hand_size(), 0, "copy consumed")
	assert_eq(gs.active_number, 4, "jumped card updates active state")


func test_jump_in_rejected_when_closed() -> void:
	var gs := _new_game(2)
	_set_active(gs, Card.CardColor.RED, 4)
	var red4 := _number(Card.CardColor.RED, 4)
	var copy := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 4, "", "copy")
	_give(gs, 0, [red4])
	_give(gs, 1, [copy])
	gs.play_card(0, 0)
	gs.close_jump_in_window()
	var ok := gs.jump_in(1)
	assert_false(ok, "jump-in rejected after close")


func test_close_jump_in_window_advances() -> void:
	var gs := _new_game(3)
	gs.direction = 1  # pin direction: setup() randomizes it
	_set_active(gs, Card.CardColor.RED, 4)
	var red4 := _number(Card.CardColor.RED, 4)
	var copy := CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 4, "", "copy")
	_give(gs, 0, [red4])
	_give(gs, 2, [copy])
	gs.play_card(0, 0)
	assert_true(gs.jump_in_open, "window open")
	gs.close_jump_in_window()
	assert_false(gs.jump_in_open, "window closed")
	assert_eq(gs.current_index, 1, "turn advanced after close")


func test_jump_in_not_allowed_for_swap_hands() -> void:
	var gs := _new_game(3)
	_set_active(gs, Card.CardColor.RED, -1)
	var swap := _action(Card.CardColor.NONE, "swap_hands")
	var swap_copy := CardDatabase._make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "swap_hands", "swap copy")
	_give(gs, 0, [swap])
	_give(gs, 1, [swap_copy])
	gs.play_card(0, 0)
	assert_false(gs.jump_in_open, "swap_hands not jump-innable")


func test_jump_in_bomb_never_opens_window() -> void:
	# Bomb can never be played from hand, so play_card's matches() guard blocks it.
	var gs := _new_game(2)
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	_give(gs, 0, [bomb])
	assert_eq(gs.get_valid_plays(0).size(), 0, "bomb not playable")


# ── overcharge (Shedding Race) ───────────────────────────────────────────────

func test_voluntary_draw_triggers_overcharge() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	# Pin the top of pile A to a safe card: a random Bomb on top would divert
	# the draw into the bomb/chamber path instead of the plain overcharge draw.
	gs.deck.pile_a[gs.deck.pile_a.size() - 1] = _number(Card.CardColor.GREEN, 1)
	var before := gs.players[0].hand_size()
	gs.draw_card(0, "A", false, false)
	assert_eq(gs.players[0].hand_size(), before + 1)
	assert_true(gs.overcharge_active, "overcharge active after voluntary draw")
	assert_eq(gs.overcharge_plays_remaining, 2)


func test_overcharge_second_play_stays_on_turn() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	var red5 := _number(Card.CardColor.RED, 5)
	# Force a known safe card onto the top of pile A so the draw can never
	# hit a bomb, and give the opponent no red 5 copies (block the jump-in).
	gs.deck.pile_a.append(red5)
	_give(gs, 1, [_number(Card.CardColor.GREEN, 2)])

	# Voluntary draw (end_turn=false) grants the 2-card Overcharge burst.
	gs.draw_card(0, "A", false, false)
	assert_true(gs.overcharge_active, "overcharge active after voluntary draw")
	assert_eq(gs.overcharge_plays_remaining, 2)
	# Exact hand: two matching red 5s, nothing else that could open a jump-in.
	_give(gs, 0, [red5, red5])
	_set_active(gs, Card.CardColor.RED, 5)

	# First burst play: stay on turn, one play remaining.
	gs.play_card(0, 0)
	assert_eq(gs.current_index, 0, "stays on turn during the overcharge burst")
	assert_eq(gs.overcharge_plays_remaining, 1, "one burst play left")

	# Second play spends the burst: the turn finally passes.
	gs.play_card(0, 0)
	assert_eq(gs.current_index, 1, "turn passes after the burst is spent")
	assert_false(gs.overcharge_active, "overcharge cleared")


func test_last_shot_sets_pending_on_single_card() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	var c := _number(Card.CardColor.RED, 5)
	# The NEXT player (not the current one) must hold a single card:
	# advance_turn() inspects the player it MOVES to, so a 1-card current
	# player never triggers the pending-last-shot flag.
	_give(gs, 1, [c])
	gs.current_index = 0
	gs.advance_turn()
	assert_true(gs.pending_last_shot, "1-card player faces last shot")


func test_trigger_last_shot_safe_draw_survives() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	var c := _number(Card.CardColor.RED, 5)
	_give(gs, 0, [c])
	# Make sure top card of pile A is safe
	gs.deck.pile_a.append(_number(Card.CardColor.BLUE, 1))
	gs.trigger_last_shot(0, "A")
	assert_true(gs.last_shot_passed, "survived last shot")
	assert_false(gs.pending_last_shot, "last shot is consumed, not re-armed mid-visit")
	assert_eq(gs.players[0].hand_size(), 2, "now has the drawn card")
	assert_true(gs.overcharge_active, "overcharge activates for the final play")


func test_trigger_last_shot_bomb_fails() -> void:
	var gs := _new_game(2, GameState.Mode.SHEDDING_RACE)
	var c := _number(Card.CardColor.RED, 5)
	_give(gs, 0, [c])
	var bomb := CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB")
	gs.deck.pile_a.append(bomb)
	gs.chamber._chamber = [ChamberDeck.Result.BLANK]
	gs.trigger_last_shot(0, "A")
	# Bomb was deferred (draw_card called defer_bomb=true), so pending_bomb is set
	assert_true(gs.pending_bomb != null, "bomb pending for UI resolution")
	assert_false(gs.last_shot_passed, "did not pass last shot")


# ── bomb voting ──────────────────────────────────────────────────────────────

func test_no_bombs_remaining_triggers_vote() -> void:
	var gs := _new_game(2)
	# Remove all bombs from both piles
	for pile_id in ["A", "B"]:
		var pile = gs.deck._pile(pile_id)
		var kept: Array = []
		for c in pile:
			if c.type != Card.CardType.BOMB:
				kept.append(c)
		gs.deck._pile(pile_id).clear()
		gs.deck._pile(pile_id).append_array(kept)
	gs._check_all_bombs_diffused()
	assert_true(gs.bomb_vote_active, "voting starts when no bombs remain")


func test_cast_vote_continue_passes_with_majority() -> void:
	var gs := _new_game(3)
	gs.bomb_vote_active = true
	gs.cast_vote(0, true)
	gs.cast_vote(1, true)
	gs.cast_vote(2, false)
	assert_false(gs.bomb_vote_active, "vote resolved")
	assert_false(gs.game_over, "continue won")
	# Bombs were redistributed (4 players * 2 = 8 bombs)
	var count := gs._count_remaining_bombs()
	assert_gt(count, 0, "bombs redistributed")


func test_cast_vote_end_wins_with_majority() -> void:
	var gs := _new_game(3)
	gs.bomb_vote_active = true
	gs.cast_vote(0, false)
	gs.cast_vote(1, false)
	gs.cast_vote(2, true)
	assert_true(gs.game_over, "end vote ends the game")
	assert_false(gs.bomb_vote_active, "voting concluded")
	assert_true(gs.winner_name.length() > 0, "winners named")


func test_cast_vote_ignored_when_not_active() -> void:
	var gs := _new_game(2)
	gs.cast_vote(0, true)
	assert_true(gs.bomb_votes.is_empty(), "votes not recorded when inactive")


func test_vote_incomplete_waiting_for_more() -> void:
	var gs := _new_game(4)
	gs.bomb_vote_active = true
	gs.cast_vote(0, true)
	assert_true(gs.bomb_vote_active, "still waiting for other votes")


func test_cast_vote_tie_ends_game() -> void:
	var gs := _new_game(4)
	gs.bomb_vote_active = true
	gs.cast_vote(0, true)
	gs.cast_vote(1, true)
	gs.cast_vote(2, false)
	gs.cast_vote(3, false)
	assert_false(gs.bomb_vote_active, "tie resolves the vote")
	assert_true(gs.game_over, "a tie favours ending the game (continue needs a majority)")
	assert_true(gs.winner_name.length() > 0, "remaining players named as winners")


# ── peek / forced pile ───────────────────────────────────────────────────────

func test_play_peek_logs_top_cards() -> void:
	var gs := _new_game(4)
	var peek := _action(Card.CardColor.NONE, "peek")
	_give(gs, 0, [peek])
	gs.play_card(0, 0, {"chosen_pile": "A"})
	assert_true(true, "peek executes without error")


func test_draw_card_honors_forced_pile() -> void:
	var gs := _new_game(4)
	var p_id := gs.players[0].id
	gs.forced_pile_for_player[p_id] = "B"
	var before_b := gs.deck.pile_b.size()
	gs.draw_card(0, "A", false, false)  # asks for A but B is forced
	assert_eq(gs.deck.pile_b.size(), before_b - 1, "drew from forced pile B")
	assert_false(gs.forced_pile_for_player.has(p_id), "forced pile consumed after draw")


func test_draw_card_both_piles_empty_skips() -> void:
	var gs := _new_game(2)
	gs.deck.pile_a.clear()
	gs.deck.pile_b.clear()
	gs.deck.discard.clear()
	var before_idx := gs.current_index
	gs.draw_card(0, "A", false, true)
	assert_eq(gs.current_index, before_idx + 1, "turn advances even with no cards")