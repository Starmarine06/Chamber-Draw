extends RefCounted
class_name GameState

## The full core loop from the GDD: turn order, playing/drawing, the Multi-Deck
## System, and Chamber Draw resolution. This is engine-agnostic logic (no Node
## dependency) so it can be driven by a real UI later or, for now, by the
## simulate() harness in main.gd.

enum Mode { SHEDDING_RACE, LAST_ONE_STANDING }

signal log_event(text: String)

## Emitted when a played card can be answered out of turn ("jump in").
## The payload is the list of player indices holding an exact copy.
signal jump_in_available(candidates: Array)

## Emitted when a player respawns from a Respawn card.
signal player_respawned(player_index: int)

## Emitted when all bombs are diffused and voting begins.
signal bomb_vote_started()

## Emitted when the bomb vote concludes.
signal bomb_vote_finished(continued: bool)

var players: Array[PlayerData] = []
var deck: DeckManager
var chamber := ChamberDeck.new()
var mode: Mode = Mode.SHEDDING_RACE

var current_index: int = 0
var direction: int = 1  # +1 or -1

## Physical clockwise ring of seat indices, starting from seat 0 (local).
## direction=+1 walks this ring clockwise; -1 walks counter-clockwise.
## Built once in setup() from num_players.
var turn_order: Array[int] = []
var active_color: int = Card.CardColor.RED
var active_number: int = -1
var active_action_id: String = ""  # action_id of the current top-of-discard, when it's an ACTION card

## Respawn cards are NOT in the deck at setup. While a player is eliminated,
## RESPAWN_CARDS_PER_ELIMINATED cards sit in the deck for each dead player; an
## ALIVE player drawing one revives the most recently eliminated player.
const RESPAWN_CARDS_PER_ELIMINATED = 2
var last_eliminated_index: int = -1  # most recently eliminated seat, revived by a Respawn draw

var forced_pile_for_player: Dictionary = {}   # player_id -> "A"/"B", from Choose a Deck
var override_next_player_index = null         # from Wild Sabotage

# Exposed for the UI layer to handle diffuse/chamber decisions
var pending_bomb: Card = null                 # set when a bomb is drawn, cleared after resolution
var pending_diffuse_player_index: int = -1    # which player drew the bomb

# Forced draw state: when a Draw Two/Four/Ten is played, the TARGET chooses the deck.
var pending_forced_draw_count: int = 0           # how many cards the target must draw
var pending_forced_draw_player_index: int = -1   # which player must draw (the target)
var pending_forced_draw_amount: int = 0          # the +N value of the pile-top draw card (the stack reference)

var winner_name: String = ""
var game_over: bool = false

## Overcharge state (Shedding Race): drawing voluntarily grants a 2-card play burst if safe.
var overcharge_active: bool = false
var overcharge_plays_remaining: int = 0

## Last Shot state (Shedding Race): 1-card endgame requires surviving a chamber pull to win.
var pending_last_shot: bool = false
var last_shot_passed: bool = false

## Jump-in state: after any playable card is played, every player holding an
## exact copy (including the actor) may immediately play it out of turn.
var last_played_card: Card = null
var jump_in_open: bool = false
var jump_in_candidate_list: Array[int] = []

# Bomb voting state: when all bombs are diffused, players vote to continue or end.
var bomb_vote_active: bool = false
var bomb_votes: Dictionary = {}  # player_index -> true/false (true = continue)
var total_bombs_diffused: int = 0  # track how many bombs have been diffused

const STARTING_HAND_SIZE = 7
const PENALTY_HAND_SIZE_MODE_A = 4
const RESPAWN_HAND_SIZE = 4
const BOMBS_PER_PLAYER = 2

func setup(num_players: int, p_mode: Mode) -> void:
	mode = p_mode
	deck = DeckManager.new()
	deck.setup(num_players)

	players.clear()
	for i in range(num_players):
		players.append(PlayerData.new(i, "Player %d" % (i + 1)))

	# Deal starting hands, alternating piles so nobody's opening hand is
	# entirely dependent on one pile's shuffle.
	for p in players:
		for i in range(STARTING_HAND_SIZE):
			var pile_id := "A" if i % 2 == 0 else "B"
			var card := _draw_safe_from(pile_id)
			if card:
				p.hand.append(card)

	# Flip a starting card to establish the active color/number.
	var starter := _draw_safe_from("A")
	if starter:
		deck.discard_card(starter)
		if starter.type == Card.CardType.NUMBER:
			active_color = starter.color
			active_number = starter.number
			active_action_id = ""
		else:
			active_color = Card.CardColor.RED
			active_number = -1
			active_action_id = starter.action_id if starter.type == Card.CardType.ACTION else ""

	current_index = 0
	direction = 1 if randi() % 2 == 0 else -1
	_build_turn_order(num_players)
	_emit_log("Game started: %d players, mode=%s, direction=%s" % [num_players, Mode.keys()[mode], "clockwise" if direction == 1 else "counter-clockwise"])

## Assign each seat a color from the shared palette (by index). Caller decides
## who gets which index (offline: player picks, AI get random distinct ones;
## online: host maps seat -> lobby-chosen color, resolving duplicates).
func apply_seat_colors(seat_color_indices: Array) -> void:
	for i in range(players.size()):
		if i < seat_color_indices.size():
			var idx: int = seat_color_indices[i]
			players[i].color_idx = idx
			players[i].color = GameGlobals.PALETTE[idx % GameGlobals.PALETTE.size()]

func _emit_log(text: String) -> void:
	log_event.emit(text)
	print(text)

func current_player() -> PlayerData:
	return players[current_index]

## Returns hand indices of cards the current player may legally play.
func get_valid_plays(player_index: int) -> Array[int]:
	var p := players[player_index]
	var valid: Array[int] = []
	for i in range(p.hand.size()):
		if p.hand[i].matches(active_color, active_number, active_action_id):
			valid.append(i)
	return valid

## Canonical 6-seat clockwise ring traced around the poker table, starting at
## the local player (seat 0 = bottom). Player1=bottom, Player2=top,
## Player3=right, Player4=left, Player5=top-left, Player6=bottom-right.
## Ring order: bottom → left → top-left → top → right → bottom-right.
const _RING_6: Array[int] = [0, 3, 4, 1, 2, 5]

## Build the physical turn-order ring for `n` players (2–7).
## For 7 players, seat 6 wraps onto Player1 (same marker as seat 0),
## inserted adjacent to seat 0 in the ring.
func _build_turn_order(n: int) -> void:
	if n >= 7:
		turn_order = [0, 6, 3, 4, 1, 2, 5]
		return
	turn_order = []
	for s in _RING_6:
		if s < n:
			turn_order.append(s)

func _next_alive_index(from_index: int, step: int) -> int:
	var n := players.size()
	# Lazy fallback: if turn_order was never built (hand-built test states),
	# fall back to linear posmod traversal.
	if turn_order.is_empty():
		var idx := from_index
		for _i in range(n):
			idx = posmod(idx + step, n)
			if not players[idx].eliminated:
				return idx
		return from_index
	var pos := turn_order.find(from_index)
	if pos < 0:
		return from_index
	var ring_size := turn_order.size()
	for _i in range(ring_size):
		pos = posmod(pos + step, ring_size)
		var seat: int = turn_order[pos]
		if not players[seat].eliminated:
			return seat
	return from_index

## Advances current_index to the next player, respecting direction, skips,
## and any Wild Sabotage override.
func advance_turn() -> void:
	overcharge_active = false
	overcharge_plays_remaining = 0
	pending_last_shot = false
	last_shot_passed = false

	if override_next_player_index != null:
		current_index = override_next_player_index
		override_next_player_index = null
	else:
		current_index = _next_alive_index(current_index, direction)

	# A pending forced-draw target keeps their turn so they can choose a deck
	# and draw (their skip is consumed inside resolve_forced_draw after drawing).
	if players[current_index].skip_next_turn and not (pending_forced_draw_count > 0 and pending_forced_draw_player_index == current_index):
		players[current_index].skip_next_turn = false
		_emit_log("%s is skipped." % players[current_index].display_name)
		current_index = _next_alive_index(current_index, direction)

	# In SHEDDING_RACE, a player with 1 card must take the Last Shot before winning.
	if mode == Mode.SHEDDING_RACE and players[current_index].hand_size() == 1:
		pending_last_shot = true

## Uno-style stacking: when the current player is ALREADY the forced-draw target,
## playing another Draw card ADDS to the count and pushes the bigger punishment
## one seat further instead of overwriting it. The stacker's own pending skip
## (set when they were targeted) is consumed by the play, so it is cleared to
## avoid a phantom skip on the next lap.
func _start_or_stack_forced_draw(from_index: int, amount: int) -> void:
	var target := _next_alive_index(from_index, direction)
	if pending_forced_draw_count > 0 and pending_forced_draw_player_index == from_index:
		pending_forced_draw_count += amount
		pending_forced_draw_amount = amount
		players[from_index].skip_next_turn = false
		_emit_log("%s stacks a draw card — the forced draw rises to %d cards!" % [players[from_index].display_name, pending_forced_draw_count])
	else:
		pending_forced_draw_count = amount
		pending_forced_draw_amount = amount
	pending_forced_draw_player_index = target
	players[target].skip_next_turn = true

## The +N value a Draw card carries ("draw_two" → 2, "draw_four" → 4, "draw_ten" → 10).
func _draw_amount_for(action_id: String) -> int:
	match action_id:
		"draw_two":
			return 2
		"draw_four":
			return 4
		"draw_ten":
			return 10
		_:
			return 0

## True when `card` may be stacked onto the pending forced draw by
## `player_index`: the player is the current target and the card is a Draw card
## (Draw Two/Four/Ten). A stack is legal ONLY when the card's +N matches the
## pile's +N (cross-color, same value) OR the card's color matches the active
## color (same color, any value). Cross-color stacking with a DIFFERENT value
## is NOT allowed — a red +4 does NOT stack onto a green +2.
func is_draw_stack_candidate(player_index: int, card: Card) -> bool:
	if card == null:
		return false
	if pending_forced_draw_count <= 0 or pending_forced_draw_player_index != player_index:
		return false
	if card.type != Card.CardType.ACTION:
		return false
	if not (card.action_id in ["draw_two", "draw_four", "draw_ten"]):
		return false
	return card.color == active_color or _draw_amount_for(card.action_id) == pending_forced_draw_amount

## --- Playing a card ---
## options may include: chosen_color (Card.CardColor), target_player_index (int),
## chosen_pile ("A"/"B") for Choose a Deck.
func play_card(player_index: int, hand_index: int, options: Dictionary = {}) -> void:
	var p := players[player_index]
	if hand_index < 0 or hand_index >= p.hand.size():
		return
	var card: Card = p.hand[hand_index]
	# Stacking bypasses the color/number match: a forced-draw target may stack
	# any Draw Two/Four/Ten regardless of color or +N value.
	if not is_draw_stack_candidate(player_index, card) and not card.matches(active_color, active_number, active_action_id):
		_emit_log("Illegal play attempted by %s, ignored." % p.display_name)
		return

	p.hand.remove_at(hand_index)
	deck.discard_card(card)
	_emit_log("%s plays %s" % [p.display_name, card.display_name])

	match card.type:
		Card.CardType.NUMBER:
			active_color = card.color
			active_number = card.number
			active_action_id = ""
		Card.CardType.WILD:
			active_color = options.get("chosen_color", Card.CardColor.RED)
			active_number = -1
			active_action_id = ""
			if card.action_id == "wild_sabotage":
				override_next_player_index = options.get("target_player_index", null)
		Card.CardType.ACTION:
			_apply_action(p, card, options)

	_finish_play(card)

func _apply_action(p: PlayerData, card: Card, options: Dictionary) -> void:
	active_action_id = card.action_id
	match card.action_id:
		"skip":
			active_color = card.color
			active_number = -1
			var target := _next_alive_index(current_index, direction)
			players[target].skip_next_turn = true
		"reverse":
			active_color = card.color
			active_number = -1
			direction *= -1
		"draw_two":
			active_color = card.color
			active_number = -1
			_start_or_stack_forced_draw(current_index, 2)
		"draw_four":
			active_color = card.color
			active_number = -1
			_start_or_stack_forced_draw(current_index, 4)
		"draw_ten":
			_start_or_stack_forced_draw(current_index, 10)
		"swap_hands":
			var target_idx = options.get("target_player_index", _next_alive_index(current_index, direction))
			var tmp := p.hand
			p.hand = players[target_idx].hand
			players[target_idx].hand = tmp
			_emit_log("%s swaps hands with %s" % [p.display_name, players[target_idx].display_name])
		"peek":
			var pile_id: String = options.get("chosen_pile", "A")
			var top_cards := deck.peek(pile_id, 3)
			_emit_log("%s peeks at top of pile %s: %s" % [p.display_name, pile_id, _card_names(top_cards)])
		"extra_life":
			p.bank_extra_life()
			_emit_log("%s banks an Extra Life (now holding %d)." % [p.display_name, p.banked_lives])
		"choose_deck":
			var target_idx = options.get("target_player_index", _next_alive_index(current_index, direction))
			var chosen_pile: String = options.get("chosen_pile", "A")
			forced_pile_for_player[players[target_idx].id] = chosen_pile
			_emit_log("%s forces %s's next draw to come from Deck %s." % [p.display_name, players[target_idx].display_name, chosen_pile])
		"rotate_decks":
			deck.rotate_decks()
			_emit_log("%s rotates the decks! Both piles reshuffled and redealt." % p.display_name)

	# NONE-color action cards: the player chooses the active color for the next turn.
	if card.color == Card.CardColor.NONE and options.has("chosen_color"):
		active_color = options.chosen_color
		active_number = -1

## End-of-play funnel: opens the jump-in window when a copy of the played card
## exists in any hand (including the actor's), otherwise advances the turn.
func _finish_play(card: Card) -> void:
	# Overcharge handling in Shedding Race
	if mode == Mode.SHEDDING_RACE and overcharge_active and overcharge_plays_remaining > 1:
		overcharge_plays_remaining -= 1
		if current_player().hand.is_empty():
			overcharge_active = false
			overcharge_plays_remaining = 0
			_check_win_condition()
			return
		var next_valid := get_valid_plays(current_index)
		if next_valid.size() > 0:
			_emit_log("⚡ %s Overcharge: 1 play remaining!" % current_player().display_name)
			return
		else:
			_emit_log("⚡ %s has no matching card for 2nd Overcharge play." % current_player().display_name)
			overcharge_active = false
			overcharge_plays_remaining = 0

	last_played_card = card
	jump_in_candidate_list = _jump_in_candidates()
	if jump_in_candidate_list.is_empty():
		jump_in_open = false
		# Last Shot guard: a player under Last Shot who empties their hand
		# without clearing the chamber must NOT win this turn. This must run
		# BEFORE advance_turn(), which clears pending_last_shot (the gate in
		# _check_win_condition would otherwise never fire).
		if mode == Mode.SHEDDING_RACE and pending_last_shot and not last_shot_passed and current_player().hand.is_empty():
			_emit_log("%s must clear the Last Shot before winning!" % current_player().display_name)
			advance_turn()
			return
		advance_turn()
		_check_win_condition()
		return
	jump_in_open = true
	jump_in_available.emit(jump_in_candidate_list.duplicate())

## Players (alive) holding an exact copy of last_played_card. Only NUMBER cards
## and choice-free ACTION cards can be answered — wilds/swap/choose/peek/bomb/
## diffuse are excluded (they need a decision or aren't normal plays).
func _jump_in_candidates() -> Array[int]:
	var out: Array[int] = []
	if last_played_card == null:
		return out
	var lc := last_played_card
	if lc.type != Card.CardType.NUMBER and lc.type != Card.CardType.ACTION:
		return out
	if lc.type == Card.CardType.ACTION and lc.action_id in ["swap_hands", "choose_deck", "peek"]:
		return out
	for i in range(players.size()):
		if players[i].eliminated:
			continue
		for c in players[i].hand:
			if _same_card(c, lc):
				out.append(i)
				break
	return out

func _same_card(a: Card, b: Card) -> bool:
	return a.type == b.type and a.color == b.color and a.number == b.number and a.action_id == b.action_id

## Plays an exact copy of the last played card out of turn. Returns false if the
## window is closed or the player holds no copy.
func jump_in(player_index: int) -> bool:
	if not jump_in_open or last_played_card == null:
		return false
	if player_index < 0 or player_index >= players.size():
		return false
	var p := players[player_index]
	if p.eliminated:
		return false
	var lc := last_played_card
	var idx := -1
	for i in range(p.hand.size()):
		if _same_card(p.hand[i], lc):
			idx = i
			break
	if idx == -1:
		return false

	var card: Card = p.hand[idx]
	p.hand.remove_at(idx)
	deck.discard_card(card)
	_emit_log("%s jumps in with %s!" % [p.display_name, card.display_name])
	last_played_card = card

	match card.type:
		Card.CardType.NUMBER:
			active_color = card.color
			active_number = card.number
			active_action_id = ""
		Card.CardType.ACTION:
			active_color = card.color
			_apply_action(p, card, {})
		_:
			pass

	# Copies may chain: if another copy is still in play, the window stays open.
	jump_in_candidate_list = _jump_in_candidates()
	if jump_in_candidate_list.is_empty():
		jump_in_open = false
		advance_turn()
		_check_win_condition()
	else:
		jump_in_available.emit(jump_in_candidate_list.duplicate())
	return true

## Closes the jump-in window without anyone jumping and advances the turn.
func close_jump_in_window() -> void:
	if not jump_in_open:
		return
	jump_in_open = false
	last_played_card = null
	jump_in_candidate_list = []
	advance_turn()
	_check_win_condition()

func _card_names(cards: Array[Card]) -> String:
	var names: Array[String] = []
	for c in cards:
		names.append(c.display_name)
	return ", ".join(names)

## --- Drawing ---
## Voluntary draw (the player had no play, or chose to draw). Carries full Bomb risk.
## If defer_bomb is true, bombs are stored in pending_bomb for UI-layer handling.
## Draws a card for `player_index`.  `end_turn` defaults to true (forced draws,
## legacy callers).  Pass false for voluntary draws so the player can play
## the drawn card immediately — the caller must call advance_turn() itself.
func draw_card(player_index: int, pile_choice: String = "A", defer_bomb: bool = false, end_turn: bool = true) -> void:
	var p := players[player_index]
	var pile_id: String = forced_pile_for_player.get(p.id, pile_choice)
	forced_pile_for_player.erase(p.id)

	var card := deck.draw_from(pile_id)
	if card == null:
		_emit_log("Both piles are empty! Skipping draw.")
		if end_turn:
			advance_turn()
		return

	if card.type == Card.CardType.BOMB:
		if defer_bomb:
			pending_bomb = card
			pending_diffuse_player_index = player_index
			_emit_log("%s drew the BOMB!" % p.display_name)
			return
		else:
			_handle_bomb_drawn(p, card)
	elif card.type == Card.CardType.RESPAWN:
		# Respawn cards only exist while someone is eliminated, and only ALIVE
		# players draw (eliminated seats are skipped). Drawing one revives the
		# most recently eliminated player.
		deck.discard_card(card)
		if last_eliminated_index >= 0 and last_eliminated_index < players.size() and players[last_eliminated_index].eliminated:
			_handle_respawn(players[last_eliminated_index], last_eliminated_index)
		else:
			_emit_log("%s drew a Respawn card, but nobody is eliminated — wasted!" % p.display_name)
	else:
		p.hand.append(card)
		_emit_log("%s draws from Deck %s: %s" % [p.display_name, pile_id, card.display_name])

		if mode == Mode.SHEDDING_RACE and not end_turn:
			if p.hand_size() == 2 and pending_last_shot: # Was 1 card before drawing
				pending_last_shot = false # Consumed: don't re-target this visit
				last_shot_passed = true
				_emit_log("🎯 %s SURVIVED THE LAST SHOT! Final Chamber cleared!" % p.display_name)
			overcharge_active = true
			overcharge_plays_remaining = 2
			_emit_log("⚡ %s is OVERCHARGED! Can play up to 2 cards this turn." % p.display_name)

	if end_turn:
		advance_turn()
	_check_win_condition()

## Last Shot: player has 1 card and must survive a chamber pull before winning.
## Draws from the chosen pile. If a Bomb is drawn, it triggers a full chamber
## resolution (+4 penalty, lose turn). If safe, sets last_shot_passed = true
## and activates overcharge (2 plays) so the player can play their final card.
func trigger_last_shot(player_index: int, pile_id: String) -> void:
	pending_last_shot = true
	draw_card(player_index, pile_id, true, false)

## Called by the UI layer after the diffuse decision is made.
## use_diffuse: true = use a diffuse card (if available), false = proceed to chamber draw
func resolve_bomb(use_diffuse: bool) -> void:
	if pending_bomb == null:
		return

	var p := players[pending_diffuse_player_index]
	var bomb_card: Card = pending_bomb

	if use_diffuse:
		# Find and use a diffuse card
		var diffuse_index := -1
		for i in range(p.hand.size()):
			if p.hand[i].type == Card.CardType.DIFFUSE:
				diffuse_index = i
				break
		if diffuse_index != -1:
			var diffuse_card: Card = p.hand[diffuse_index]
			p.hand.remove_at(diffuse_index)
			deck.discard_card(diffuse_card)
			# Bomb is ONE-TIME: discard it, don't return to deck.
			deck.discard_card(bomb_card)
			_emit_log("%s uses a Diffuse card to cancel the Chamber Draw!" % p.display_name)
		else:
			# No diffuse found, proceed to chamber
			var result := chamber.draw()
			_emit_log("Chamber Draw result: %s" % ChamberDeck.result_name(result))
			_resolve_chamber_result(p, bomb_card, result)
	else:
		var result := chamber.draw()
		_emit_log("Chamber Draw result: %s" % ChamberDeck.result_name(result))
		_resolve_chamber_result(p, bomb_card, result)

	pending_bomb = null
	pending_diffuse_player_index = -1
	advance_turn()
	_check_win_condition()
	_check_all_bombs_diffused()

## Called by the UI layer when it has already shown the chamber result
## (after the dramatic reveal animation). result: ChamberDeck.Result value.
func resolve_bomb_with_result(result: int) -> void:
	if pending_bomb == null:
		return

	var p := players[pending_diffuse_player_index]
	var bomb_card: Card = pending_bomb
	_emit_log("Chamber Draw result: %s" % ChamberDeck.result_name(result))
	_resolve_chamber_result(p, bomb_card, result)

	pending_bomb = null
	pending_diffuse_player_index = -1
	advance_turn()
	_check_win_condition()

## Applies a single chamber result to the player who drew the bomb,
## then returns the bomb to the deck.
func _resolve_chamber_result(p: PlayerData, bomb_card: Card, result: int) -> void:
	_apply_chamber_result(p, result)

	# Bomb is ONE-TIME: discard it after chamber resolution.
	deck.discard_card(bomb_card)

## Applies the LIVE/BLANK/BACKFIRE/LUCKY_DRAW outcome of a chamber draw to
## the player who pulled the bomb. Shared by both the diffuse-decision and
## no-diffuse bomb-drawn paths.
func _apply_chamber_result(p: PlayerData, result: int) -> void:
	match result:
		ChamberDeck.Result.LIVE:
			_resolve_live(p)
		ChamberDeck.Result.BLANK:
			pass
		ChamberDeck.Result.BACKFIRE:
			var prev_index := _next_alive_index(current_index, -direction)
			var prev := players[prev_index]
			var pile_id := "A" if randi() % 2 == 0 else "B"
			var penalty := deck.draw_from(pile_id)
			if penalty:
				prev.hand.append(penalty)
				_emit_log("Backfire! %s draws a penalty card." % prev.display_name)
		ChamberDeck.Result.LUCKY_DRAW:
			var pile_id := "A" if randi() % 2 == 0 else "B"
			var bonus := deck.draw_from(pile_id)
			if bonus and bonus.type != Card.CardType.BOMB:
				p.hand.append(bonus)
				_emit_log("Lucky Draw! %s draws a bonus card: %s" % [p.display_name, bonus.display_name])

## Draws one card, re-drawing around any Bomb it finds (bombs are returned to
## the deck at random and redrawn), so opening deals, forced draws, respawns and
## penalties never hand a player a Bomb directly. Returns null on an empty pile.
func _draw_safe_from(pile_id: String) -> Card:
	var card := deck.draw_from(pile_id)
	var attempts := 0
	while card and card.type == Card.CardType.BOMB and attempts < 10:
		deck.return_bomb_randomly(card)
		card = deck.draw_from(pile_id)
		attempts += 1
	return card

## Forced draws (Draw Two/Four/Ten) are immune to Bomb risk per GDD 4.2 —
## if a Bomb comes up, it's reshuffled back in at random and redrawn.
## preferred_pile ("A"/"B") comes from the Draw card's deck choice; empty = random.
func _forced_draw(player_index: int, count: int, preferred_pile: String = "") -> void:
	var p := players[player_index]
	var drawn: Array[String] = []
	for _i in range(count):
		var pile_id: String = preferred_pile if preferred_pile != "" else ("A" if randi() % 2 == 0 else "B")
		var card := _draw_safe_from(pile_id)
		if card:
			p.hand.append(card)
			drawn.append(card.display_name)
	_emit_log("%s is forced to draw %d cards: %s" % [p.display_name, count, ", ".join(drawn)])

## Called by the UI after the target player chooses a deck for the forced draw.
func resolve_forced_draw(chosen_pile: String) -> void:
	if pending_forced_draw_count <= 0 or pending_forced_draw_player_index < 0:
		return
	var target := pending_forced_draw_player_index
	_forced_draw(target, pending_forced_draw_count, chosen_pile)
	pending_forced_draw_count = 0
	pending_forced_draw_player_index = -1
	pending_forced_draw_amount = 0
	# The forced draw replaces the target's turn: consume their skip and move on.
	if players[target].skip_next_turn:
		players[target].skip_next_turn = false
	advance_turn()
	_check_win_condition()

## Handles the Respawn card: brings an eliminated player back with a fresh hand.
func _handle_respawn(p: PlayerData, player_index: int) -> void:
	p.eliminated = false
	p.hand.clear()
	# Deal a fresh hand of 4 cards.
	for _i in range(RESPAWN_HAND_SIZE):
		var pile_id: String = "A" if randi() % 2 == 0 else "B"
		var card := _draw_safe_from(pile_id)
		if card:
			p.hand.append(card)
	_sync_respawn_cards()
	player_respawned.emit(player_index)
	_emit_log("🎉 %s RESPAWNED with %d cards!" % [p.display_name, p.hand.size()])

## Keeps the deck's Respawn cards exactly matched to dead players: none in the
## deck when nobody is eliminated, RESPAWN_CARDS_PER_ELIMINATED per dead player
## otherwise. Called after eliminations (UI layer) and after respawns.
func _sync_respawn_cards() -> void:
	var eliminated_count := 0
	for pl in players:
		if pl.eliminated:
			eliminated_count += 1
	deck.remove_respawn_cards()
	if eliminated_count > 0:
		deck.add_respawn_cards(RESPAWN_CARDS_PER_ELIMINATED * eliminated_count)

## Public entry for the UI layer to run _sync_respawn_cards (host/offline only).
func sync_respawn_cards() -> void:
	_sync_respawn_cards()

func _handle_bomb_drawn(p: PlayerData, bomb_card: Card) -> void:
	_emit_log("%s drew the BOMB!" % p.display_name)

	var diffuse_index := -1
	for i in range(p.hand.size()):
		if p.hand[i].type == Card.CardType.DIFFUSE:
			diffuse_index = i
			break

	if diffuse_index != -1:
		# Auto-use Diffuse to cancel the Chamber Draw entirely (AI default behavior;
		# a real UI would ask the human player whether to use it).
		var diffuse_card: Card = p.hand[diffuse_index]
		p.hand.remove_at(diffuse_index)
		deck.discard_card(diffuse_card)
		# Bomb is ONE-TIME: discard it.
		deck.discard_card(bomb_card)
		_emit_log("%s uses a Diffuse card to cancel the Chamber Draw!" % p.display_name)
		return

	var result := chamber.draw()
	_emit_log("Chamber Draw result: %s" % ChamberDeck.result_name(result))

	_apply_chamber_result(p, result)

	# Bomb is ONE-TIME: discard it after chamber resolution.
	deck.discard_card(bomb_card)

func _resolve_live(p: PlayerData) -> void:
	# A banked Extra Life absorbs the Live result in either mode.
	if p.try_absorb_elimination():
		_emit_log("%s's banked Extra Life absorbs the Live result!" % p.display_name)
		return
	if mode == Mode.LAST_ONE_STANDING:
		p.eliminated = true
		last_eliminated_index = players.find(p)
		for c in p.hand:
			deck.discard_card(c)
		p.hand.clear()
		_emit_log("%s is ELIMINATED." % p.display_name)
	else:
		# Shedding Race mode: no elimination, just a heavy penalty.
		for _i in range(PENALTY_HAND_SIZE_MODE_A):
			var pile_id := "A" if randi() % 2 == 0 else "B"
			var penalty := _draw_safe_from(pile_id)
			if penalty:
				p.hand.append(penalty)
		p.skip_next_turn = true
		_emit_log("%s draws %d penalty cards and loses their next turn." % [p.display_name, PENALTY_HAND_SIZE_MODE_A])

func _check_win_condition() -> void:
	if mode == Mode.SHEDDING_RACE:
		for p in players:
			if not p.eliminated and p.hand_size() == 0:
				# If this player started their turn with 1 card, they must have
				# cleared the Last Shot before winning.
				if pending_last_shot and not last_shot_passed:
					continue
				winner_name = p.display_name
				game_over = true
				return
	else:
		var alive: Array[PlayerData] = []
		for p in players:
			if not p.eliminated:
				alive.append(p)
		if alive.size() <= 1:
			winner_name = alive[0].display_name if alive.size() == 1 else "Nobody"
			game_over = true

## Counts the total number of Bomb cards remaining in both decks.
func _count_remaining_bombs() -> int:
	var count := 0
	for pile in [deck.pile_a, deck.pile_b]:
		for c in pile:
			if c.type == Card.CardType.BOMB:
				count += 1
	return count

## Checks if all bombs have been diffused. If so, triggers the voting phase.
func _check_all_bombs_diffused() -> void:
	if bomb_vote_active or game_over:
		return
	var remaining := _count_remaining_bombs()
	if remaining == 0:
		# All bombs diffused! Start voting.
		bomb_vote_active = true
		bomb_votes.clear()
		_emit_log("💣 All bombs have been diffused! Players vote to continue...")
		bomb_vote_started.emit()

## Cast a vote to continue (true) or end the game (false).
func cast_vote(player_index: int, continue_game: bool) -> void:
	if not bomb_vote_active:
		return
	bomb_votes[player_index] = continue_game
	var p := players[player_index]
	var vote_str := "CONTINUE" if continue_game else "END"
	_emit_log("%s votes to %s." % [p.display_name, vote_str])
	_check_vote_result()

## Checks if all alive players have voted and resolves the result.
func _check_vote_result() -> void:
	var alive_count := 0
	for p in players:
		if not p.eliminated:
			alive_count += 1
		
	# Check if all alive players have voted
	if bomb_votes.size() < alive_count:
		return
	
	# Count votes
	var continue_votes := 0
	var end_votes := 0
	for vote in bomb_votes.values():
		if vote:
			continue_votes += 1
		else:
			end_votes += 1
	
	bomb_vote_active = false
	
	if continue_votes > end_votes:
		# Majority wants to continue — redistribute bombs!
		_emit_log("🗳️ Vote passed: %d to continue, %d to end. Redistributing bombs!" % [continue_votes, end_votes])
		_redistribute_bombs()
		bomb_vote_finished.emit(true)
	else:
		# Majority wants to end — all remaining players win!
		var winners: Array[String] = []
		for p in players:
			if not p.eliminated:
				winners.append(p.display_name)
		winner_name = ", ".join(winners)
		game_over = true
		_emit_log("🗳️ Vote failed: %d to continue, %d to end. Game over! Winners: %s" % [continue_votes, end_votes, winner_name])
		bomb_vote_finished.emit(false)

## Redistributes bombs after a successful continue vote.
func _redistribute_bombs() -> void:
	var num_alive := 0
	for p in players:
		if not p.eliminated:
			num_alive += 1
	
	if num_alive == 0:
		return
	
	# Create new bombs based on alive players (2 per alive player)
	var new_bomb_count := num_alive * BOMBS_PER_PLAYER
	var bomb_cards: Array[Card] = []
	for _i in range(new_bomb_count):
		var c := Card.new()
		c.type = Card.CardType.BOMB
		c.color = Card.CardColor.NONE
		c.number = -1
		c.action_id = "bomb"
		c.display_name = "BOMB"
		bomb_cards.append(c)
	
	# Distribute bombs randomly across both decks
	for bomb in bomb_cards:
		var pile_id := "A" if randi() % 2 == 0 else "B"
		var pile := deck._pile(pile_id)
		var idx := randi() % (pile.size() + 1)
		pile.insert(idx, bomb)
	
	# Also add new diffuse cards (one more than bomb count)
	var new_diffuse_count := new_bomb_count + 1
	for _i in range(new_diffuse_count):
		var c := Card.new()
		c.type = Card.CardType.DIFFUSE
		c.color = Card.CardColor.NONE
		c.number = -1
		c.action_id = "diffuse"
		c.display_name = "Diffuse"
		var pile_id := "A" if randi() % 2 == 0 else "B"
		var pile := deck._pile(pile_id)
		var idx := randi() % (pile.size() + 1)
		pile.insert(idx, c)
	
	_emit_log("💣 %d new bombs and %d new diffuses added to the decks!" % [new_bomb_count, new_diffuse_count])
