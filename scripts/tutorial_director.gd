extends Node
## Guided tutorial, in seven chapters. game.gd (_start_tutorial) sets `g`, adds
## this node and call_deferred()s _run_tutorial(). Every board is scripted from
## scratch (no RNG, no game.setup()), AI seats are driven here, and the human's
## inputs are gated through game.gd's _tut_* flags.
##
## Presentation: a docked coach panel (scripts/ui/tutorial_coach.gd) narrates
## while the table stays visible, and a spotlight pointer rings exactly what to
## click. A chapter picker lets players start anywhere.

const Coach := preload("res://scripts/ui/tutorial_coach.gd")
const UIStyle := preload("res://scripts/ui_style.gd")

var g

var coach: Control
var _events: Array = []
var _step := 0
var _chapter := 0
var _chapter_steps := 0

const CHAPTERS := [
	["BASICS", "Matching, drawing, ending your turn"],
	["ACTION CARDS", "Skip, Reverse, Wild, Swap, Peek, Choose a Deck, Extra Life, Rotate"],
	["DRAW ATTACKS", "Draw Two / Four / Ten, stacking the pile"],
	["BOMBS & THE CHAMBER", "Reading the odds, Diffuse, pulling the trigger"],
	["JUMP-IN", "Slapping down copies out of turn"],
	["TABLE LIFE", "Smoke a cigarette, pour a whiskey"],
	["ENDGAME", "Last Shot, Overcharge, Respawn, the Vote"],
]

# ── Card factories ────────────────────────────────────────────────────

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

## `count` throwaway number cards (distinct combos so they never accidentally
## match a highlighted play or open a jump-in window).
func _filler(count: int) -> Array[Card]:
	var out: Array[Card] = []
	for i in range(count):
		var col: int = _filler_colors[_filler_n % 4]
		var num: int = _filler_numbers[_filler_n % 9]
		_filler_n += 1
		out.append(_make_number(col, num))
	return out

# ── Signal plumbing ───────────────────────────────────────────────────

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

# ── Coach helpers ─────────────────────────────────────────────────────

func _chapter_label() -> String:
	return "CHAPTER %d · %s" % [_chapter + 1, CHAPTERS[_chapter][0]]

func _progress() -> float:
	var within := minf(float(_chapter_steps) / 12.0, 0.95)
	return (float(_chapter) + within) / float(CHAPTERS.size())

## Info step: narrate and wait for CONTINUE (or Enter/Space). Input stays locked.
func _say(title: String, body: String, target: Callable = Callable()) -> void:
	_step += 1
	_chapter_steps += 1
	_lock_input()
	coach.show_step(_chapter_label(), _step, _progress(), title, body, true, target)
	await coach.continued
	g._sfx(&"button")

## Action step: narrate + spotlight; the caller unlocks input and awaits the event.
func _task(title: String, body: String, target: Callable = Callable()) -> void:
	_step += 1
	_chapter_steps += 1
	coach.show_step(_chapter_label(), _step, _progress(), title, body, false, target)

func _cheer(text: String = "NICE!") -> void:
	coach.set_target(Callable())
	coach.cheer(text)
	g._sfx(&"banner")
	await get_tree().create_timer(0.7).timeout

# ── Spotlight targets (each returns a Rect2 in game-canvas space) ─────

func _rect_of(c: Control) -> Rect2:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return Rect2()
	return Rect2(c.global_position - g.global_position, c.size * c.scale)

func _t_hand(i: int) -> Callable:
	return func() -> Rect2:
		return _rect_of(g.card_nodes[i]) if i < g.card_nodes.size() else Rect2()

func _t_both_decks() -> Callable:
	return func() -> Rect2:
		var a: Control = g._draw_btn_a
		var b: Control = g._draw_btn_b
		if a == null or b == null:
			return Rect2()
		return Rect2(a.position, a.size).merge(Rect2(b.position, b.size))

func _t_gauge(pile: String) -> Callable:
	return func() -> Rect2:
		return _rect_of(g._gauge_a if pile == "A" else g._gauge_b)

func _t_node(getter: Callable) -> Callable:
	return func() -> Rect2:
		var n: Variant = getter.call()
		return _rect_of(n as Control) if n is Control else Rect2()

func _t_seat(i: int) -> Callable:
	return func() -> Rect2:
		var t: Variant = g._seat_tags.get(i, null)
		return _rect_of(t as Control) if t is Control else Rect2()

func _t_discard() -> Callable:
	return func() -> Rect2:
		var c: Vector2 = g._discard_screen_pos()
		return Rect2(c - Vector2(46, 64), Vector2(92, 128))

func _t_vice(idx: int) -> Callable:
	return func() -> Rect2:
		var row: Node = g.get_node_or_null("ViceRow")
		if row == null or row.get_child_count() <= idx:
			return Rect2()
		return _rect_of(row.get_child(idx) as Control)

func _t_glass() -> Callable:
	return func() -> Rect2:
		var gl: Variant = g._table_glass
		if gl == null or not is_instance_valid(gl):
			return Rect2()
		var c: Vector2 = g._unproject((gl as Node3D).global_position)
		return Rect2(c - Vector2(34, 58), Vector2(68, 70))

# ── Input gating ──────────────────────────────────────────────────────

func _lock_input() -> void:
	var blocked: Array[int] = [-1]
	g._tut_input_hands = blocked
	g._tut_allow_draw = false
	g._tut_allow_end_turn = false
	g._tut_allow_vice = false

func _allow_hands(indexes: Array[int]) -> void:
	_lock_input()
	g._tut_input_hands = indexes

func _allow_draw() -> void:
	_lock_input()
	g._tut_allow_draw = true

# ── Board builder ─────────────────────────────────────────────────────

func _seed(me: Array[Card], rex: Array[Card], nia: Array[Card], zed: Array[Card],
		active_color: int, active_number: int, current: int, dir: int,
		da: Array[Card], db: Array[Card], discard: Array[Card]) -> void:
	_events.clear()
	g._force_end_vice()
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
	g._reposition_draw_zones()
	g._notification_timer = 0.0
	if g.notification_label:
		g.notification_label.visible = false

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

## Resolves a pending forced draw aimed at an AI seat (the director drives AIs).
func _ai_eats_forced_draw(pile: String) -> void:
	var st: GameState = g.game
	if st.pending_forced_draw_count <= 0:
		return
	g._animate_forced_draw(pile, st.pending_forced_draw_player_index, st.pending_forced_draw_count)
	st.resolve_forced_draw(pile)
	g._refresh_all()

# ── Entry point ───────────────────────────────────────────────────────

func _run_tutorial() -> void:
	g.tutorial_action_done.connect(_on_action_done)
	coach = Coach.new()
	g.add_child(coach)
	coach.exit_requested.connect(_exit_to_menu)
	await get_tree().process_frame

	var start := await _pick_chapter()
	for i in range(start, CHAPTERS.size()):
		_chapter = i
		_chapter_steps = 0
		match i:
			0: await _ch_basics()
			1: await _ch_actions()
			2: await _ch_draws()
			3: await _ch_chamber()
			4: await _ch_jump()
			5: await _ch_table_life()
			6: await _ch_endgame()
	await _finale()

## Title card + chapter picker. Returns the chapter index to start from.
func _pick_chapter() -> int:
	coach.visible = false
	var dim := ColorRect.new()
	dim.color = Color(UIStyle.INK, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 90
	g.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := UIStyle.make_panel()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UIStyle.make_label("THE TUTORIAL", 36, UIStyle.BRASS, true))
	v.add_child(UIStyle.make_label("Learn the table in seven short chapters - or jump to the one you need.", 14, UIStyle.MUTED))
	var picked := [-1]
	var go_all := UIStyle.make_button("START FROM THE TOP", &"primary", Vector2(610, 46), 17)
	go_all.pressed.connect(func() -> void: picked[0] = 0)
	v.add_child(go_all)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for i in range(CHAPTERS.size()):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var b := UIStyle.make_button("%d · %s" % [i + 1, CHAPTERS[i][0]], &"secondary", Vector2(300, 38), 13)
		b.tooltip_text = CHAPTERS[i][1]
		b.pressed.connect(func() -> void: picked[0] = i)
		cell.add_child(b)
		var d := UIStyle.make_label(CHAPTERS[i][1], 10, UIStyle.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		cell.add_child(d)
		grid.add_child(cell)
	var back := UIStyle.make_button("BACK TO MENU", &"danger", Vector2(200, 36), 13)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_exit_to_menu)
	v.add_child(back)
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = Vector2(230, 260)
	g.create_tween().tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	while picked[0] < 0:
		await get_tree().process_frame
	dim.queue_free()
	coach.visible = true
	return picked[0]

func _exit_to_menu() -> void:
	GameGlobals.is_tutorial = false
	g._force_end_vice()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

# ═══ CHAPTER 1 · BASICS ═══════════════════════════════════════════════

func _ch_basics() -> void:
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
	await _say("Welcome to the back room",
		"Four seats: [key]you[/key], [key]Rex[/key], [key]Nia[/key] and [key]Zed[/key]. Their tags show each player's cards and banked lives; the [key]▶[/key] marks whose turn it is.\n\nGoal: [good]empty your hand first[/good].")
	await _say("The pile sets the rules",
		"The card face-up in the middle is the [key]discard pile[/key]. To play, match its [key]COLOR[/key] or its [key]NUMBER[/key]. The top bar also shows the active color.",
		_t_discard())
	_allow_hands([0])
	await _task("Play a card",
		"Your playable cards glow brass; the rest dim. Click the [key]RED 5[/key] - it matches the red.",
		_t_hand(0))
	await _await("card")
	await _cheer()

	_seed(
		[_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 6),
			_make_number(Card.CardColor.RED, 9), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.PURPLE, 8), _make_number(Card.CardColor.RED, 5)],
		_filler(6), _filler(6), _filler(6),
		Card.CardColor.GREEN, 2, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.GREEN, 2)],
	)
	await _say("Nothing to play?",
		"[key]GREEN 2[/key] is up and you hold no green and no 2 - nothing glows. Then you [key]draw[/key] from one of the two decks.")
	_allow_draw()
	await _task("Draw a card",
		"Click [key]Deck A[/key] or [key]Deck B[/key] (or press [key]A[/key] / [key]B[/key]).",
		_t_both_decks())
	await _await("draw")
	await _cheer("DRAWN!")
	await _say("After drawing",
		"You keep your turn: play the new card if it fits, or pass with [key]END TURN[/key].")
	g._tut_allow_end_turn = true
	await _task("End your turn", "Click [key]END TURN[/key].", _t_node(func() -> Variant: return g._end_turn_btn))
	await _await("end_turn")
	await _cheer()
	await _say("Mind the clock",
		"In real games every turn has a [key]30-second timer[/key] (the ring on the left). Let it run out and you [bad]draw 4[/bad]. The tutorial pauses it for you.\n\nKeyboard: [key]1-9[/key] play a hand card, [key]A/B[/key] draw, [key]Esc[/key] pauses.")

# ═══ CHAPTER 2 · ACTION CARDS ═════════════════════════════════════════

func _ch_actions() -> void:
	# Skip
	_seed(
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "skip", "ORANGE SKIP"),
			_make_number(Card.CardColor.PURPLE, 6), _make_number(Card.CardColor.GREEN, 2),
			_make_number(Card.CardColor.RED, 7)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.ORANGE, 3, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.ORANGE, 3)],
	)
	await _say("Skip",
		"Action cards bend the rules. [key]SKIP[/key] makes the NEXT player lose their turn. A Skip also plays on any other Skip, whatever the color.")
	_allow_hands([0])
	await _task("Skip Zed", "Click [key]ORANGE SKIP[/key]. Zed sits next to you.", _t_hand(0))
	await _await("card")
	await _cheer("SKIPPED!")

	# Reverse
	_seed(
		[_make_action(Card.CardColor.GREEN, Card.CardType.ACTION, "reverse", "GREEN REVERSE"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.GREEN, 3, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.GREEN, 3)],
	)
	_allow_hands([0])
	await _task("Reverse",
		"[key]REVERSE[/key] flips the direction of play (the arrow in the top bar). Click [key]GREEN REVERSE[/key].",
		_t_hand(0))
	await _await("card")
	await _cheer()

	# Wild
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.WILD, "wild_color", "WILD"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2),
			_make_number(Card.CardColor.GREEN, 3)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 3, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 3)],
	)
	_allow_hands([0])
	await _task("Wild",
		"A [key]WILD[/key] plays on anything - then YOU pick the new color. Click the WILD, then choose a color.",
		_t_hand(0))
	await _await("card")
	await _cheer()

	# Swap hands
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "swap_hands", "SWAP HANDS"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.GREEN, 6)],
		_filler(3), _filler(3),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Swap Hands",
		"[key]SWAP HANDS[/key] is an anytime card: pick a color, then a player - you trade [key]entire hands[/key]. Rex holds only 2 cards... you hold 3.",
		_t_seat(1))
	_allow_hands([0])
	await _task("Steal the small hand", "Play [key]SWAP HANDS[/key], pick a color, then pick [key]Rex[/key].", _t_hand(0))
	await _await("card")
	await _cheer("SWAPPED!")

	# Peek
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "peek", "PEEK"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	_allow_hands([0])
	await _task("Peek",
		"[key]PEEK[/key] shows the top 3 cards of a deck - the best way to dodge a bomb. Play it, pick a color and a deck, then close the window.",
		_t_hand(0))
	await _await_any(["card", "peek"])
	await _cheer("INTEL!")

	# Choose a Deck (attack)
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "choose_deck", "CHOOSE A DECK"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Choose a Deck",
		"An attack. You pick the [key]color[/key], a [key]victim[/key] and a [key]deck[/key]: the victim [bad]draws a card from THAT deck right now[/bad] and [bad]loses their next turn[/bad].")
	_allow_hands([0])
	await _task("Make someone draw", "Play [key]CHOOSE A DECK[/key] → color → victim → deck.", _t_hand(0))
	await _await("card")
	await _cheer("GOTCHA!")

	# Extra Life
	_seed(
		[_make_action(Card.CardColor.NONE, Card.CardType.ACTION, "extra_life", "EXTRA LIFE"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	_allow_hands([0])
	await _task("Extra Life",
		"[key]EXTRA LIFE[/key] banks a life (hold up to [key]2[/key]). If the Chamber ever fires [bad]LIVE[/bad] at you, a banked life is spent instead of you. Play it.",
		_t_hand(0))
	await _await("card")
	await _cheer("♥ BANKED")

	# Rotate
	_seed(
		[_make_action(Card.CardColor.RED, Card.CardType.ACTION, "rotate_decks", "RED ROTATE"),
			_make_number(Card.CardColor.ORANGE, 7), _make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3), _filler(3),
		Card.CardColor.RED, 2, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 2)],
	)
	_allow_hands([0])
	await _task("Rotate the Decks",
		"[key]ROTATE[/key] reshuffles both decks together and redeals them - bomb odds get rewritten. Watch the gauges change. Play it.",
		_t_hand(0))
	await _await("card")
	await _cheer("SHUFFLED!")

# ═══ CHAPTER 3 · DRAW ATTACKS ═════════════════════════════════════════

func _ch_draws() -> void:
	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.GREEN, 4),
			_make_number(Card.CardColor.RED, 7), _make_number(Card.CardColor.PURPLE, 9)],
		_filler(4), _filler(4),
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "draw_two", "ORANGE DRAW 2"),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.ORANGE, 8, 3, -1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.ORANGE, 8)],
	)
	await _say("Incoming!",
		"[key]DRAW 2 / 4 / 10[/key] make the next player draw. Zed is about to hit you with a Draw Two...",
		_t_seat(3))
	_ai_play(3, 0, "Zed played an ORANGE Draw Two at you!")
	await _task("You choose the deck",
		"The [key]victim[/key] picks which deck the cards come from. Check the odds gauges, then click a deck. (Drawing uses up your turn.)",
		_t_both_decks())
	await _await("forced_draw_choice")
	await _cheer("TAKEN")

	_seed(
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "draw_four", "ORANGE DRAW 4"),
			_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.RED, 7)],
		_filler(4), _filler(4),
		[_make_action(Card.CardColor.GREEN, Card.CardType.ACTION, "draw_four", "GREEN DRAW 4"),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.GREEN, 8, 3, -1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.GREEN, 8)],
	)
	await _say("Stacking",
		"When you're the victim you can [good]STACK[/good]: play ANY Draw card (any color, any +N) and the total [key]adds up[/key] and passes to the next player.")
	_ai_play(3, 0, "Zed played a GREEN Draw Four at you!")
	_allow_hands([0])
	await _task("Pass it on",
		"Click your [key]ORANGE DRAW 4[/key] to stack (4 + 4 = 8 for the next player) - or click a deck to eat the 4.",
		_t_hand(0))
	var res := await _await_any(["card", "forced_draw_choice"])
	_lock_input()
	if res.kind == "card":
		var total: int = g.game.pending_forced_draw_count
		await _cheer("+%d STACKED!" % total)
		var victim: int = g.game.pending_forced_draw_player_index
		await _say("%s pays" % g.game.players[victim].display_name,
			"The pile grew to [bad]%d cards[/bad] and moved past you. %s eats them all." % [total, g.game.players[victim].display_name], _t_seat(victim))
		_ai_eats_forced_draw("A")
	else:
		await _say("You ate the 4", "Also fine - but stacking is how the pros stay light. Next time, pile it on!")

	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.RED, 7), _make_number(Card.CardColor.GREEN, 9)],
		_filler(4), _filler(4),
		[_make_action(Card.CardColor.RED, Card.CardType.ACTION, "draw_ten", "DRAW 10"),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.RED, 3, 3, -1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 3)],
	)
	await _say("The heavyweight",
		"[key]DRAW 10[/key] is colorless - it plays anytime. No Draw card to stack this time...")
	_ai_play(3, 0, "Zed dropped a DRAW TEN on you!")
	await _task("Take the ten", "Pick a deck to draw your 10.", _t_both_decks())
	await _await("forced_draw_choice")
	await _cheer("OUCH")

# ═══ CHAPTER 4 · BOMBS & THE CHAMBER ══════════════════════════════════

func _ch_chamber() -> void:
	# Reading the odds: Deck A hides bombs deep down, Deck B is clean.
	var risky: Array[Card] = _filler(8)
	risky.insert(0, _make_bomb())
	risky.insert(3, _make_bomb())
	risky.insert(5, _make_bomb())
	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.GREEN, 9)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 2, 0, 1,
		risky, _filler(11), [_make_number(Card.CardColor.RED, 2)],
	)
	await _say("Every deck is loaded",
		"Some cards in the decks are [bad]BOMBS[/bad]. Draw one and you face [bad]THE CHAMBER[/bad].\n\nEach deck's gauge shows its [key]odds[/key]: the percent chance its next card is live, with a cylinder of red rounds.",
		_t_gauge("A"))
	await _say("Compare", "Deck A's odds are high. Deck B is clean - [good]0%[/good].", _t_gauge("B"))
	_allow_draw()
	await _task("Play the odds", "You have nothing to play. Draw from the [good]safer deck[/good].", _t_both_decks())
	var pick := await _await("draw")
	if str(pick.details.get("pile", "")) == "B":
		await _cheer("SMART!")
	else:
		await _say("Lucky this time", "Deck A was the risky one - read the gauges before every draw!")

	# Diffuse
	_seed(
		[_make_diffuse(), _make_number(Card.CardColor.PURPLE, 3),
			_make_number(Card.CardColor.ORANGE, 4), _make_number(Card.CardColor.RED, 7)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	_prefill_chamber_blank()
	_bomb_on_both_piles()
	await _say("Diffuse",
		"Both decks now have a bomb on top. You're holding a [good]DIFFUSE[/good] - it cancels a bomb (and is used up).",
		_t_hand(0))
	_allow_draw()
	await _task("Draw the bomb", "Draw from either deck, then choose [key]Use Diffuse[/key].", _t_both_decks())
	var b := await _await_any(["diffuse_use", "chamber_done"])
	_lock_input()
	if b.kind == "diffuse_use":
		await _cheer("DEFUSED!")
	else:
		await _say("Brave", "You took the risk instead of the Diffuse. It came up BLANK - this time.")

	# The Chamber
	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.RED, 7), _make_number(Card.CardColor.GREEN, 9)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	_prefill_chamber_blank()
	_bomb_on_both_piles()
	await _say("No Diffuse",
		"Without a Diffuse, a bomb means [bad]THE CHAMBER[/bad]: a revolver cylinder spins and fires one of:\n[bad]LIVE[/bad] - penalty (or elimination in Last One Standing)\n[key]BLANK[/key] - nothing happens\n[bad]BACKFIRE[/bad] - it kicks back\n[good]LUCKY DRAW[/good] - fortune favors you")
	_allow_draw()
	await _task("Pull the trigger", "Draw from a deck and face the Chamber.", _t_both_decks())
	await _await("chamber_done")
	await _cheer("STILL HERE")
	await _say("Know your odds",
		"Bombs are one-time: once used they're gone. A banked [key]Extra Life[/key] absorbs a LIVE. Keep an eye on the gauges - they update after every draw.")

# ═══ CHAPTER 5 · JUMP-IN ══════════════════════════════════════════════

func _ch_jump() -> void:
	# AI plays, you jump.
	_seed(
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.ORANGE, 7),
			_make_number(Card.CardColor.PURPLE, 2), _make_number(Card.CardColor.GREEN, 3)],
		_filler(4), _filler(4),
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.GREEN, 9),
			_make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.RED, 4, 3, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	await _say("Jump-In",
		"If someone plays a card and you hold the [key]EXACT same card[/key] (same color and value), you can slap yours down [good]out of turn[/good].\n\nZed is about to play a RED 5 - and you hold one too.",
		_t_seat(3))
	_ai_play(3, 0, "Zed played a RED 5!")
	await _await("jump_in_window")
	g._show_jump_in_prompt()
	await _task("JUMP IN!", "Click [key]JUMP IN![/key] before the window closes.", _t_node(func() -> Variant: return g._jump_prompt))
	var jr := await _await_any(["jump_done", "jump_pass"])
	if jr.kind == "jump_done":
		await _cheer("JUMPED!")
		await _say("Play continues from YOU",
			"A jump-in [key]moves the turn to the jumper[/key]: everyone in between is skipped and play carries on from your seat.",
			_t_seat(3))
	else:
		g._close_jump_window()
		await _say("Passed", "No drama - Zed's play stands. Next time, jump!")

	# Jump-in on a +2 adds to the pile.
	_seed(
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "draw_two", "ORANGE DRAW 2"),
			_make_number(Card.CardColor.PURPLE, 2), _make_number(Card.CardColor.GREEN, 3)],
		_filler(3), _filler(3),
		[_make_action(Card.CardColor.ORANGE, Card.CardType.ACTION, "draw_two", "ORANGE DRAW 2"),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.PURPLE, 5)],
		Card.CardColor.ORANGE, 6, 3, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.ORANGE, 6)],
	)
	await _say("Jumping a Draw card",
		"Zed is about to fire a +2 at Rex - and you hold the same [key]ORANGE DRAW 2[/key]. Jumping in on a Draw card [good]ADDS to the pile[/good]...")
	_ai_play(3, 0, "Zed played an ORANGE Draw Two at Rex!")
	await _await("jump_in_window")
	g._show_jump_in_prompt()
	await _task("Pile it on", "Click [key]JUMP IN![/key]", _t_node(func() -> Variant: return g._jump_prompt))
	var jr2 := await _await_any(["jump_done", "jump_pass"])
	if jr2.kind == "jump_done":
		var total: int = g.game.pending_forced_draw_count
		await _cheer("+%d!" % total)
		var victim: int = g.game.pending_forced_draw_player_index
		await _say("It bounced!",
			"The pile is now [bad]%d cards[/bad], and since play continues from you, it lands on the player [key]after you[/key] - Zed himself!" % total,
			_t_seat(victim))
		_ai_eats_forced_draw("B")
	else:
		g._close_jump_window()
		await _say("Passed", "Rex takes the 2. Jumping would have doubled it.")

	# You play, Zed jumps.
	_seed(
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.ORANGE, 7),
			_make_number(Card.CardColor.PURPLE, 2)],
		_filler(3), _filler(3),
		[_make_number(Card.CardColor.RED, 5), _make_number(Card.CardColor.GREEN, 9)],
		Card.CardColor.RED, 4, 0, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 4)],
	)
	_allow_hands([0])
	await _task("It works both ways", "Play your [key]RED 5[/key] - Zed holds the other one...", _t_hand(0))
	await _await("jump_in_window")
	_lock_input()
	if g._jump_in_window:
		g._ai_jump_in(3)
	await _await("jump_done")
	await _say("Zed jumped you",
		"Zed slapped his copy down, so play now continues from [key]Zed[/key]. Watch for copies in YOUR hand every time a card hits the pile.",
		_t_seat(3))

# ═══ CHAPTER 6 · TABLE LIFE ═══════════════════════════════════════════

func _ch_table_life() -> void:
	_seed(
		[_make_number(Card.CardColor.PURPLE, 3), _make_number(Card.CardColor.ORANGE, 4),
			_make_number(Card.CardColor.GREEN, 9), _make_number(Card.CardColor.RED, 1)],
		_filler(4), _filler(4), _filler(4),
		Card.CardColor.RED, 2, 1, 1,
		_filler(15), _filler(15), [_make_number(Card.CardColor.RED, 2)],
	)
	await _say("Settle in",
		"Long night? You can [key]smoke[/key] and [key]drink[/key] at the table - between turns or while you think. You'll [key]set your cards face-down[/key] first; you can't play while your hands are busy (and the clock keeps running on your turn).")

	# Smoke
	g._tut_allow_vice = true
	await _task("Light up", "Press [key]S[/key] or click [key]SMOKE[/key].", _t_vice(0))
	await _await("vice_start")
	g._tut_allow_vice = false
	await _say("A fresh one",
		"No cigarette yet, so you take one from the [key]pack[/key] and [key]light it[/key]. Watch...")
	var fps: Script = g.FirstPersonSmoke
	var smoke_start: float = fps.burn
	while g._smoke_session != null and is_instance_valid(g._smoke_session) and int(g._smoke_session.phase) == 0:
		await get_tree().process_frame  # wait out the pack + lighter intro
	smoke_start = fps.burn
	await _task("Take a drag",
		"[key]Scroll the mouse wheel[/key] to pull on it - the longer you scroll, the bigger the drag. Stop to exhale.")
	while g._smoke_session != null and is_instance_valid(g._smoke_session) and float(fps.burn) - smoke_start < 0.1:
		await get_tree().process_frame
	await _cheer("SMOOTH")
	await _say("It burns down",
		"Every pull burns tobacco - the cigarette gets shorter and [key]stays that length[/key] next time. Smoke it to the filter and you flick the butt; the next one comes from the pack.")
	g._tut_allow_vice = true
	await _task("Put it out", "Press [key]S[/key] again.", _t_vice(0))
	if g._smoke_session != null and is_instance_valid(g._smoke_session):
		await _await("vice_end")
	else:
		_events.clear()
	g._tut_allow_vice = false
	await _cheer()

	# Whiskey
	g._tut_allow_vice = true
	await _task("Pour one", "Press [key]W[/key] or click [key]WHISKEY[/key].", _t_vice(1))
	await _await("vice_start")
	g._tut_allow_vice = false
	var fpd: Script = g.FirstPersonDrink
	while g._drink_session != null and is_instance_valid(g._drink_session) and int(g._drink_session.phase) == 0:
		await get_tree().process_frame
	var lvl: float = fpd.level
	await _task("Sip", "[key]Scroll[/key] to sip. Each scroll is a mouthful - hear the ice?")
	while g._drink_session != null and is_instance_valid(g._drink_session) and lvl - float(fpd.level) < 0.14:
		await get_tree().process_frame
	await _cheer("CHEERS")
	g._tut_allow_vice = true
	await _task("Set it down", "Press [key]W[/key] to put the glass back on the table.", _t_vice(1))
	if g._drink_session != null and is_instance_valid(g._drink_session):
		await _await("vice_end")
	else:
		_events.clear()
	g._tut_allow_vice = false
	await _say("It stays on the table",
		"Your glass waits on the felt; next time your hand reaches for it. Drain it and the [key]bartender refills[/key] it.",
		_t_glass())
	await _say("Don't wait for the pour",
		"While the bartender pours, press [key]W[/key]: your hand lets go and your cards come back up, so you can [key]keep playing[/key]. The moment he's done, your cards go back down and the glass is in your hand again.")
	await _say("Know your limit",
		"Drinks differ: [key]beer[/key] is mild, [key]wine[/key] and champagne medium, whiskey standard, [key]vodka[/key] hits harder and [key]absinthe[/key] is brutal. Drink too much and you [bad]PASS OUT[/bad]: the rest of your turn is lost, your next turn is skipped, and you wake with [bad]3 extra cards[/bad] - still a little drunk.")

# ═══ CHAPTER 7 · ENDGAME ══════════════════════════════════════════════

func _ch_endgame() -> void:
	await _say("The Last Shot",
		"With [key]one card left[/key] you can't just win - first you must take the [bad]LAST SHOT[/bad]: draw from a deck and survive whatever you pull.")
	await _say("Overcharged",
		"Survive the Last Shot and you're [good]OVERCHARGED[/good]: you may play [key]up to 2 cards[/key] that turn - often enough to win on the spot. Two Draw cards in one Overcharged turn [key]add together[/key]: Draw 10 + Draw 4 makes the next player draw 14.")
	await _say("Respawn",
		"When a player is knocked out, [key]RESPAWN[/key] cards are shuffled into the decks. Draw one and the most recently eliminated player comes back with a fresh hand.")
	await _say("The Vote",
		"Once every bomb has been used, the survivors [key]vote[/key]: reload the decks and keep playing, or end it and all share the win.")
	await _say("Your color and your voice",
		"No two players ever share a [key]color[/key] - online lobbies grey out the ones already taken. Online games also have [key]voice chat[/key]: hold [key]V[/key] to talk (or switch to open mic in Settings), [key]M[/key] mutes your mic, [key]N[/key] deafens you, and the voice bar lets you mute any one player.")
	await _say("Two ways to play",
		"[key]Shedding Race[/key]: first to empty their hand wins; LIVE = penalty.\n[key]Last One Standing[/key]: LIVE eliminates - last player alive wins.")

func _finale() -> void:
	_chapter = CHAPTERS.size() - 1
	_chapter_steps = 99
	await _say("You're ready",
		"You've learned the whole table: matching, action cards, draw attacks and stacking, bombs and the Chamber, jump-ins, and how to enjoy a smoke and a drink while you're at it.\n\nPick a mode in the menu and [good]go win one[/good].")
	await get_tree().create_timer(0.3).timeout
	_exit_to_menu()
