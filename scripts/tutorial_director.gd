extends Node
## Fully scripted guided tutorial. Seeded by game.gd (_start_tutorial), which sets
## `g` then add_child()s this node and call_deferred()s _run_tutorial(). The director
## builds every board from scratch (no RNG, no game.setup()), scripts all AI seats,
## and gates the human's allowed inputs via game.gd's _tut_* flags.

var g

var _proceed := false
var _events: Array = []

func _make_number(col: int, n: int) -> Card:
	return CardDatabase._make(Card.CardType.NUMBER, col, n, "", "%s %d" % [_color_name(col), n])

func _color_name(col: int) -> String:
	match col:
		Card.CardColor.RED:
			return "RED"
		Card.CardColor.ORANGE:
			return "ORANGE"
		Card.CardColor.GREEN:
			return "GREEN"
		Card.CardColor.PURPLE:
			return "PURPLE"
		_:
			return "WILD"

func _make_action(col: int, type: Card.CardType, action_id: String, name: String) -> Card:
	return CardDatabase._make(type, col, -1, action_id, name)

func _make_diffuse() -> Card:
	return CardDatabase._make(Card.CardType.DIFFUSE, Card.CardColor.GREEN, -1, "", "DIFFUSE")

func _make_bomb() -> Card:
	return CardDatabase._make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "", "BOMB")

var _filler_colors: Array = [Card.CardColor.RED, Card.CardColor.ORANGE, Card.CardColor.GREEN, Card.CardColor.PURPLE]
var _filler_numbers: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9]
var _filler_n: int = 0

## Build a pile of `count` throwaway number cards (distinct value/color combos so
## they never accidentally match a highlighted play or spawn jump windows).
func _filler(count: int) -> Array[Card]:
	var out: Array[Card] = []
	for i in range(count):
		var col: int = _filler_colors[_filler_n % 4]
		var num: int = _filler_numbers[_filler_n % 9]
		_filler_n += 1
		out.append(_make_number(col, num))
	return out

## --- tutorial signal plumbing ---

func _on_action_done(kind: String, details: Dictionary) -> void:
	_events.append([kind, details])

func _await(kind: String) -> Dictionary:
	return await _await_any([kind])

func _await_any(kinds: Array) -> Dictionary:
	var match_idx := -1
	while match_idx < 0:
		for i in range(_events.size()):
			if _events[i][0] in kinds:
				match_idx = i
				break
		if match_idx < 0:
			await g.tutorial_action_done
	var ev: Array = _events.pop_at(match_idx)
	return {"kind": ev[0], "details": ev[1]}

## --- overlay helper ---

func _ensure_overlay_vbox() -> void:
	if g.overlay_vbox != null and is_instance_valid(g.overlay_vbox) and g.overlay_vbox.get_parent() == g.overlay:
		return
	g.overlay_vbox = VBoxContainer.new()
	g.overlay_vbox.set_anchors_preset(Control.PRESET_CENTER)
	g.overlay_vbox.offset_left = -200
	g.overlay_vbox.offset_right = 200
	g.overlay_vbox.offset_top = -120
	g.overlay_vbox.offset_bottom = 120
	g.overlay_vbox.add_theme_constant_override("separation", 15)
	g.overlay.add_child(g.overlay_vbox)

## Blocking narrated popup. Mouse is captured while it's up; all _tut_* gates
## stay off until it closes, so the player can't act underneath.
func _say(title: String, body: String) -> void:
	g.overlay.visible = true
	g.overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_overlay_vbox()
	g._clear_overlay()
	g._prepare_overlay_popup()

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	g.overlay_vbox.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(560, 0)
	body_label.add_theme_font_size_override("font_size", 18)
	body_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	g.overlay_vbox.add_child(body_label)

	var ok: Button = g._make_kenney_button("Continue", Vector2(180, 54), 18)
	g.overlay_vbox.add_child(ok)
	g._center_overlay_vbox()

	_proceed = false
	ok.pressed.connect(func() -> void: _proceed = true)
	g._play_sfx(g._sfx_button)
	while not _proceed:
		await get_tree().process_frame
	g.overlay.visible = false
	g._clear_overlay()

## --- input gating helpers ---

func _lock_input() -> void:
	var blocked: Array[int] = [-1]
	g._tut_input_hands = blocked
	g._tut_allow_draw = false
	g._tut_allow_end_turn = false

func _allow_hands(indexes: Array[int]) -> void:
	_lock_input()
	g._tut_input_hands = indexes

func _allow_draw() -> void:
	_lock_input()
	g._tut_allow_draw = true

## --- board builder ---

func _seed(me: Array[Card], rex: Array[Card], nia: Array[Card], zed: Array[Card],
		active_color: int, active_number: int, current: int, dir: int,
		da: Array[Card], db: Array[Card], discard: Array[Card]) -> void:
	_events.clear()
	g._dismiss_all_overlays()
	g._paused = false
	g._jump_in_window = false
	g._pending_ai_jump_index = -1
	g._ai_jump_delay = 0.0
	g._pending_card = null
	g._pending_options = {}
	g._pending_next_step = ""
	g._was_my_turn = true
	g._drew_this_turn = false
	_lock_input()
	g.state = g.State.WAITING
	g._hide_timer_ui()

	var st: GameState = g.game
	for i in range(4):
		var p: PlayerData = st.players[i]
		p.hand = [me, rex, nia, zed][i].duplicate()
		p.skip_next_turn = false
		p.banked_lives = 1
		p.eliminated = false
	st.deck.pile_a = da.duplicate()
	st.deck.pile_b = db.duplicate()
	st.deck.discard = discard.duplicate()
	st.active_color = active_color
	st.active_number = active_number
	st.active_action_id = ""
	st.current_index = current
	st.direction = dir
	st._build_turn_order(4)
	st.mode = GameState.Mode.SHEDDING_RACE
	st.pending_bomb = null
	st.pending_forced_draw_count = 0
	st.pending_forced_draw_player_index = -1
	st.pending_forced_draw_amount = 0
	st.pending_diffuse_player_index = -1
	st.pending_last_shot = false
	st.last_shot_passed = false
	st.jump_in_open = false
	st.last_played_card = null
	st.last_eliminated_index = -1
	st.forced_pile_for_player = {}
	st.override_next_player_index = null
	st.bomb_vote_active = false
	st.bomb_votes = {}
	st.overcharge_active = false
	st.overcharge_plays_remaining = 0
	st.game_over = false
	st.winner_name = ""
	st.chamber = ChamberDeck.new()

	g._refresh_all()
	g._check_turn()

func _ai_play(seat: int, hand_index: int, note: String) -> void:
	var st: GameState = g.game
	st.play_card(seat, hand_index, {})
	if note != "":
		g._show_notification(note, 3.0)
	g._refresh_all()
	g._check_turn()

func _bomb_on_both_piles() -> void:
	var st: GameState = g.game
	st.deck.pile_a.append(_make_bomb())
	st.deck.pile_b.append(_make_bomb())

func _prefill_chamber_blank() -> void:
	g.game.chamber._chamber = [ChamberDeck.Result.BLANK]

## --- the tutorial ---

func _run_tutorial() -> void:
	g.tutorial_action_done.connect(_on_action_done)
	await get_tree().process_frame

	# --- 1. Welcome + play a RED 5 ---
	_seed(
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.ORANGE, 7),
			_make_number(Card.CardColor.PURPLE, 2), _make_number(Card.CardColor.GREEN, 3)],
		[_make_number(Card.CardColor.ORANGE, 5), _make_number(Card.CardColor.GREEN, 7),
			_make_number(Card.CardColor.PURPLE, 8), _make_number(Card.CardColor.RED, 2)],
		[_make_number(Card.CardColor.GREEN, 6), _make_number(Card.CardColor.RED, 3),
			_make_number(Card.CardColor.ORANGE, 2), _make_number(Card.CardColor.PURPLE, 7)],
		[_make_number(Card.CardColor.ORANGE, 9), _make_number(Card.CardColor.PURPLE, 3),
			_make_number(Card.CardColor.RED, 7), _make_number(Card.CardColor.GREEN, 5)],
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Welcome to Chamber Draw!",
		"Shedding Race with four seats: you, Rex, Nia and Zed.\n\nEmpty your hand first to win (UNO-style). The top card of the discard (RED 4) sets what's playable: match its COLOR or its NUMBER.\n\nThe RED 5 in your hand matches the color, and playable cards light up.")
	_allow_hands([0])
	await _say("Your move",
		"Click the RED 5 to play it. Rex sits next in line.")
	await _await("card")
	_lock_input()

	# --- 2. Skip ---
	_seed(
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "skip", "ORANGE SKIP"),
			_make_number(Card.CardColor.PURPLE, 6), _make_number(Card.CardColor.GREEN, 2),
			_make_number(Card.CardColor.RED, 7)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.ORANGE, 3, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.ORANGE, 3)],
	)
	await _say("Skip",
		"Action cards bend the rules. This ORANGE SKIP matches the active color and makes the NEXT player lose a turn.")
	_allow_hands([0])
	await _say("Play the Skip",
		"Click ORANGE SKIP - Rex just got skipped.")
	await _await("card")
	_lock_input()

	# --- 3. Wild color ---
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.WILD, "wild_color", "WILD"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2),
			_make_number(Card.CardColor.GREEN, 3)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 3, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 3)],
	)
	await _say("Wild Color",
		"A WILD card plays on absolutely anything. The catch: you must pick a new active color first - a color picker pops up.")
	_allow_hands([0])
	await _say("Pick a color",
		"Click the WILD, then confirm a color. The next turn must match it.")
	await _await("card")
	_lock_input()

	# --- 4. Voluntary draw + End Turn ---
	_seed(
		[_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 6),
			_make_number(Card.CardColor.RED, 9), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.PURPLE, 8), _make_number(Card.CardColor.RED, 5)],
		_filler(6), _filler(6), _filler(6),
		Card.CardColor.GREEN, 2, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.GREEN, 2)],
	)
	await _say("Nothing to play?",
		"Green is active but you hold no green and no 2. Nothing lights up - so rummage a deck instead!\n\nClick on Deck A or Deck B (the glowing piles on the table top) to draw a card.")
	_allow_draw()
	await _await("draw")
	_lock_input()
	await _say("Drawn a card",
		"You keep your turn after drawing - you may play the new card, or pass the turn with END TURN (bottom right).")
	g._tut_allow_end_turn = true
	await _await("end_turn")
	_lock_input()

	# --- 5. Reverse ---
	_seed(
		[_make_action(Card.CardColor.GREEN, Card.CardType.ACTION, "reverse", "GREEN REVERSE"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.GREEN, 3, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.GREEN, 3)],
	)
	await _say("Reverse",
		"REVERSE flips the direction of play. With three opponents, one reversal swings the turn order completely.")
	_allow_hands([0])
	await _say("Play the Reverse",
		"Click GREEN REVERSE. It matches the green 3.")
	await _await("card")
	_lock_input()

	# --- 6. Forced draw at you (Draw Two) ---
	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.GREEN, 4),
			_make_number(Card.CardColor.RED, 7), _make_number(Card.CardColor.PURPLE, 9)],
		_filler(4), _filler(4),
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "draw_two", "ORANGE DRAW 2"),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.ORANGE, 8, 3, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.ORANGE, 8)],
	)
	await _say("Draw Two incoming",
		"Zed is up and matches ORANGE with a ORANGE DRAW 2... aimed right at you.")
	_ai_play(3, 0, "Zed played a ORANGE Draw Two at you!")
	await _say("You must draw 2 cards",
		"The TARGET of a draw chooses which deck to take them from - here that's you.\n\nClick Deck A or Deck B. A lightning bar shows you must draw 2 from the pile you pick.")
	await _await("forced_draw_choice")
	_lock_input()
	await _say("Took your medicine",
		"That's the Draw Two rule: the attacker plays, the victim draws.")
	_seed(
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "draw_four", "ORANGE DRAW 4"),
			_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.RED, 7)],
		_filler(4), _filler(4),
		[_make_action(Card.CardColor.GREEN, Card.CardType.ACTION, "draw_four", "GREEN DRAW 4"),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.GREEN, 8, 3, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.GREEN, 8)],
	)
	await _say("Now it stacks",
		"Zed plays a GREEN DRAW 4 at you (4 cards). But on your forced turn you hold a matching ORANGE DRAW 4...\n\nTwo options:\n- Click the ORANGE DRAW 4 to STACK: 4 + 4 = 8 cards for the next player.\n- Or click a deck to eat the 4 yourself.")
	_ai_play(3, 0, "Zed played a GREEN Draw Four at you!")
	_allow_hands([0])
	var stack_res := await _await_any(["card", "forced_draw_choice"])
	_lock_input()
	if stack_res.kind == "card":
		var total: int = g.game.pending_forced_draw_count
		await _say("STACKED!",
			"The punishment rises to %d cards and the target moves past the stacker. Rex now eats all %d from Deck A." % [total, total])
		g._animate_forced_draw("A", 1, total)
		g.game.resolve_forced_draw("A")
		g._refresh_all()
		g.game.current_index = 0
		g._check_turn()
		await _say("Rex pays the price",
			"Stacking is the snarkiest rule in Chamber Draw - pile it on!")
		# Fall through into the next step's own seed.
	else:
		await _say("You ate the 4",
			"Sometimes discretion is the better part of valor. Either way, your turn is consumed by the draw.")

	# --- 8. Swap hands ---
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "swap_hands", "SWAP HANDS"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.GREEN, 6),
			_make_number(Card.CardColor.ORANGE, 3)],
		_filler(3), _filler(3),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Swap Hands",
		"SWAP HANDS is an anytime card: it plays on any active color. After you confirm a color, pick a TARGET to trade entire hands with.\n\nChaos, but occasionally genius.")
	_allow_hands([0])
	await _say("Pick your victim",
		"Play it, confirm the color, then click the seat you want to swap with.")
	await _await("card")
	_lock_input()

	# --- 9. Peek ---
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "peek", "PEEK"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Peek",
		"PEEK lets you spy the top 3 cards of a deck - priceless intel on which pile hides the bombs.\n\nPlay it, pick a color, then choose a pile. Close the result window when you've seen enough.")
	_allow_hands([0])
	await _await_any(["card", "peek"])
	_lock_input()
	await _say("Forewarned is forearmed",
		"Those three cards are exactly what you'll draw next. Use it, then plan around it.")

	# --- 10. Choose a Deck ---
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "choose_deck", "CHOOSE A DECK"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Choose a Deck",
		"CHOOSE A DECK is the reverse of drawing at a victim: it FORCES another player's next draw to come from a specific pile.\n\nPlay it, confirm a color, pick a target, pick a pile.")
	_allow_hands([0])
	await _await("card")
	_lock_input()
	await _say("Locked in",
		"Whenever that player next draws, the game pulls from the pile you locked. Dictator-level control.")

	# --- 11. Extra Life ---
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "extra_life", "EXTRA LIFE"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2),
			_make_number(Card.CardColor.GREEN, 3)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Extra Life",
		"EXTRA LIFE banks a consumable life (you can hold up to two). When a bomb fires at you, an Extra Life is spent automatically to keep you in the game.\n\nIt plays anytime - choose a color first.")
	_allow_hands([0])
	await _await("card")
	_lock_input()
	await _say("Fully banked",
		"Your seat now holds an extra life. Remember: it's one-use, and the second life only kicks in once you've been eliminated once.")

	# --- 12. Bomb + Diffuse ---
	_seed(
		[_make_diffuse(), _make_number(Card.CardColor.PURPLE, 3),
			_make_number(Card.CardColor.ORANGE, 4), _make_number(Card.CardColor.RED, 7)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	_prefill_chamber_blank()
	_bomb_on_both_piles()
	await _say("THE BOMB",
		"Some piles carry BOMBS. Both decks' top cards are armed - you'll hit one no matter which you draw.\n\nLuckily you're holding a DIFFUSE card. Draw from Deck A and see what happens when the fuse is pulled.")
	_allow_draw()
	var bomb_res := await _await_any(["draw", "diffuse_use", "chamber_done"])
	while bomb_res.kind == "draw":
		g._show_notification("Deck A has the Bomb - draw from the middle of the pile if you dare. (Any draw fires it!)", 3.0)
		_allow_draw()
		bomb_res = await _await_any(["draw", "diffuse_use", "chamber_done"])
	_lock_input()
	if bomb_res.kind == "diffuse_use":
		await _say("Diffused!",
			"Boom averted - the DIFFUSE is consumed and discarded for good. Without it you'd have drawn from the CHAMBER...")
	else:
		await _say("You pulled the trigger",
			"Since no Diffuse was used, the chamber spins. It landed BLANK this time - but a live chamber eliminates you outright.")

	# --- 13. Bomb, no Diffuse -> Chamber ---
	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.RED, 7), _make_number(Card.CardColor.GREEN, 9)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	_prefill_chamber_blank()
	_bomb_on_both_piles()
	await _say("No Diffuse? Take the ride",
		"This time your hand holds no Diffuse. Both decks are still armed - draw from Deck A to see what the CHAMBER does to a bomber without protection.")
	_allow_draw()
	var chamber_res := await _await_any(["draw", "chamber_done"])
	while chamber_res.kind == "draw":
		g._show_notification("Both decks are armed - the Bomb fires on whichever pile you draw!", 3.0)
		_allow_draw()
		chamber_res = await _await_any(["draw", "chamber_done"])
	_lock_input()
	await _say("BLANK - you live",
		"The chamber was empty. But ELECTRIFY (live) eliminates you, LUCKY DRAW spits cards your way, and BACKFIRE makes the attacker draw instead. Only one way to find out which...")

	# --- 14. Jump-In: AI acts, you answer ---
	_seed(
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.ORANGE, 7),
			_make_number(Card.CardColor.PURPLE, 2), _make_number(Card.CardColor.GREEN, 3)],
		_filler(4),
		_filler(4),
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.GREEN, 9),
			_make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.RED, 4, 3, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Jump-In",
		"Every once in a while the tables turn. Zed is about to play a RED 5 - and you are holding the EXACT same card.\n\nAny player (you included) with a copy may answer out of turn: JUMP IN!")
	_ai_play(3, 0, "Zed played a RED 5!")
	await _await("jump_in_window")
	await _say("Your copy reacts!",
		"Zed's RED 5 opened a short Jump-In window - and you hold a copy.")
	g._show_jump_in_prompt()
	g._show_notification("You hold the exact match - click JUMP IN! (or Pass).", 4.0)
	var jump_res := await _await_any(["jump_done", "jump_pass"])
	if jump_res.kind == "jump_done":
		await _say("JUMPED IN!",
			"Your same-number card slapped down on Zed's pile, out of turn. Jump chains keep the window open while copies keep answering.")
	else:
		g._close_jump_window()
		await _say("Passed",
			"No drama - Zed's play simply stands. But you never had to skip that chance...")

	# --- 15. Jump-In: you act, AI answers ---
	_seed(
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.ORANGE, 7),
			_make_number(Card.CardColor.PURPLE, 2)],
		_filler(3),
		_filler(3),
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.GREEN, 9)],
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Now you're the target",
		"Same trick, mirrored: you play a RED 5 while Zed holds the other copy. Play it - then watch Zed steal the spotlight.")
	_allow_hands([0])
	await _await("jump_in_window")
	_lock_input()
	var zed_seat := 3
	g._show_notification("Zed holds your exact card - he jumps in out of turn!", 3.0)
	if g._jump_in_window:
		g._ai_jump_in(zed_seat)
	await _await("jump_done")
	await _say("Copies duel",
		"Zed consumed his copy in the window. Whoever answers with a copy keeps the window open; a pass closes it and play moves on.")

	# --- 16. Rotate decks ---
	_seed(
		[_make_action(Card.CardColor.RED, Card.CardType.ACTION, "rotate_decks", "RED ROTATE"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.RED, 2, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 2)],
	)
	await _say("Rotate the Decks",
		"ROTATE makes both piles dump into one, reshuffle, and split 50/50 - mid-game. It scrambles everything you thought you knew about the bomb piles.\n\nThis one's red, so no color picker.")
	_allow_hands([0])
	await _await("card")
	_lock_input()
	await _say("Shuffled",
		"Piles are bigger, cleaner and freshly dealt. Bomb probabilities just got rewritten.")

	# --- 17. Draw Ten, the dinosaur ---
	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.RED, 7), _make_number(Card.CardColor.GREEN, 9)],
		_filler(4), _filler(4),
		[_make_action(Card.CardColor.RED, Card.CardType.ACTION, "draw_ten", "RED DRAW 10"),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.RED, 3, 3, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 3)],
	)
	await _say("DRAW TEN",
		"The heavyweight. Zed matches RED and drops a DRAW 10 at you - a full ten-card punishment, same deck-choice rule as before.")
	_ai_play(3, 0, "Zed played a RED Draw Ten at you!")
	await _say("Ten cards to take",
		"Click a deck to take the ten. (In theory you can stack a DRAW 10 onto a DRAW 10 for double the pain - but your hand holds no draw card right now, so eat the ten.)")
	await _await("forced_draw_choice")
	_lock_input()
	await _say("That's a monster hand",
		"Ten cards is rough. This is exactly why stocking DIFFUSE and EXTRA LIFE matters in the real game.")

	# --- Finale ---
	await _say("Everything's covered!",
		"You've seen it all:\n\n- UNO shedding, Skip, Reverse, Wild Color\n- Draw Two / Four / Ten with stacking\n- Swap Hands, Peek, Choose a Deck, Rotate Decks\n- Extra Life, Diffuse & the Chamber, Jump-In\n\nStill unshown (and waiting in a real match): eliminated players add RESPAWN cards that revive the last one out, a 1-card inhibitor called the LAST SHOT, and when every bomb is gone the survivors VOTE to continue or end the round.")
	await _say("Go win one",
		"Head to the main menu and start a real match against the AI - favours are paid back in full.")
	await get_tree().create_timer(0.6).timeout
	GameGlobals.is_tutorial = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")