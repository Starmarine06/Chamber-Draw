extends RefCounted

## Texas Hold'em rules engine (no UI). One instance per table.
## Players are Dictionaries: name, chips, hole[], bet (this street), total (this hand),
## folded, all_in, in_hand, human, style (AI: "tight" | "loose" | "wild" | "balanced").

const Eval := preload("res://scripts/poker/poker_eval.gd")

enum Stage { PREFLOP, FLOP, TURN, RIVER, SHOWDOWN }

var players: Array[Dictionary] = []
var board: Array[int] = []
var deck: Array[int] = []
var stage: int = Stage.PREFLOP
var dealer: int = -1
var current: int = -1
var current_bet: int = 0
var min_raise: int = 20
var small_blind: int = 10
var big_blind: int = 20
var hand_over: bool = true
var hand_number: int = 0
var results: Array[Dictionary] = []       # [{winners:[idx], amount, hand:String, best:Array}]
var showdown_reached: bool = false
var log_lines: Array[String] = []
var sb_index: int = -1
var bb_index: int = -1
var _acted: Dictionary = {}
var _rigged_board: Array = []

func setup(names: Array, chips: int, human_index: int, styles: Array = []) -> void:
	players.clear()
	for i in range(names.size()):
		players.append({
			"name": names[i], "chips": chips, "hole": [] as Array[int], "bet": 0, "total": 0,
			"folded": false, "all_in": false, "in_hand": true, "human": i == human_index,
			"style": styles[i] if i < styles.size() else "balanced",
		})
	dealer = names.size() - 1

func alive_count() -> int:
	var n := 0
	for p in players:
		if p.chips > 0:
			n += 1
	return n

func pot() -> int:
	var t := 0
	for p in players:
		t += int(p.total)
	return t

func _next_seat(from: int, pred: Callable) -> int:
	var n := players.size()
	for step in range(1, n + 1):
		var i := (from + step) % n
		if pred.call(players[i]):
			return i
	return -1

## rig: optional {dealer:int, hole:{seat:[a,b]}, board:[5 cards]} for scripted hands (tutorial).
func start_hand(rig: Dictionary = {}) -> void:
	hand_number += 1
	hand_over = false
	showdown_reached = false
	results.clear()
	board.clear()
	stage = Stage.PREFLOP
	for p in players:
		p.hole = [] as Array[int]
		p.bet = 0
		p.total = 0
		p.folded = false
		p.all_in = false
		p.in_hand = p.chips > 0
	# Fresh shuffled deck minus any rigged cards.
	deck.clear()
	var reserved: Dictionary = {}
	if rig.has("hole"):
		for s in rig.hole:
			for c in rig.hole[s]:
				reserved[c] = true
	if rig.has("board"):
		for c in rig.board:
			reserved[c] = true
	for c in range(52):
		if not reserved.has(c):
			deck.append(c)
	deck.shuffle()
	if rig.has("dealer"):
		dealer = int(rig.dealer)
	else:
		dealer = _next_seat(dealer, func(p): return p.in_hand)
	var heads_up := _in_hand_count() == 2
	if heads_up:
		sb_index = dealer
		bb_index = _next_seat(dealer, func(p): return p.in_hand)
	else:
		sb_index = _next_seat(dealer, func(p): return p.in_hand)
		bb_index = _next_seat(sb_index, func(p): return p.in_hand)
	for i in range(players.size()):
		if not players[i].in_hand:
			continue
		if rig.has("hole") and rig.hole.has(i):
			players[i].hole = (rig.hole[i] as Array).duplicate()
		else:
			players[i].hole = [_draw(), _draw()] as Array[int]
	_rigged_board = (rig.board as Array).duplicate() if rig.has("board") else []
	_post(sb_index, small_blind)
	_post(bb_index, big_blind)
	current_bet = big_blind
	min_raise = big_blind
	_acted.clear()
	current = _first_to_act_preflop(heads_up)
	log_lines.append("— Hand %d —" % hand_number)
	_skip_if_nobody_can_act()

func _in_hand_count() -> int:
	var n := 0
	for p in players:
		if p.in_hand:
			n += 1
	return n

func _draw() -> int:
	return deck.pop_back()

func _post(i: int, amount: int) -> void:
	var p := players[i]
	var a: int = mini(amount, int(p.chips))
	p.chips -= a
	p.bet += a
	p.total += a
	if p.chips == 0:
		p.all_in = true

func _first_to_act_preflop(heads_up: bool) -> int:
	if heads_up:
		return sb_index if _can_act(players[sb_index]) else _next_actor(sb_index)
	return _next_actor(bb_index)

func _can_act(p: Dictionary) -> bool:
	return p.in_hand and not p.folded and not p.all_in

func _next_actor(from: int) -> int:
	return _next_seat(from, func(p): return _can_act(p))

func _live_count() -> int:
	var n := 0
	for p in players:
		if p.in_hand and not p.folded:
			n += 1
	return n

func _actor_count() -> int:
	var n := 0
	for p in players:
		if _can_act(p):
			n += 1
	return n

# ── Legal actions ─────────────────────────────────────────────────────

func to_call(i: int) -> int:
	return mini(maxi(current_bet - int(players[i].bet), 0), int(players[i].chips))

func can_check(i: int) -> bool:
	return int(players[i].bet) >= current_bet

## Smallest legal "raise to" total for this street (or the all-in amount if shorter).
func min_raise_to(i: int) -> int:
	var p := players[i]
	return mini(current_bet + min_raise, int(p.bet) + int(p.chips))

func max_raise_to(i: int) -> int:
	return int(players[i].bet) + int(players[i].chips)

func can_raise(i: int) -> bool:
	return int(players[i].chips) > to_call(i)

# ── Acting ────────────────────────────────────────────────────────────

## kind: "fold" | "check" | "call" | "raise". raise_to = total bet for the street.
## Returns a short description of what happened (for logs and banners).
func act(kind: String, raise_to: int = 0) -> String:
	if hand_over or current < 0:
		return ""
	var i := current
	var p := players[i]
	var msg := ""
	match kind:
		"fold":
			p.folded = true
			msg = "%s folds" % p.name
		"check", "call":
			var a := to_call(i)
			p.chips -= a
			p.bet += a
			p.total += a
			if p.chips == 0:
				p.all_in = true
			msg = "%s calls %d" % [p.name, a] if a > 0 else "%s checks" % p.name
			if p.all_in:
				msg += " (all-in)"
		"raise":
			var target := clampi(raise_to, min_raise_to(i), max_raise_to(i))
			var add: int = target - int(p.bet)
			if target > current_bet and target - current_bet >= min_raise:
				min_raise = target - current_bet
				_acted.clear()
			p.chips -= add
			p.bet += add
			p.total += add
			if p.chips == 0:
				p.all_in = true
			var verb := "bets" if current_bet == 0 else "raises to"
			current_bet = maxi(current_bet, target)
			msg = "%s %s %d" % [p.name, verb, target]
			if p.all_in:
				msg += " (all-in)"
	_acted[i] = true
	log_lines.append(msg)
	_after_action(i)
	return msg

func _after_action(i: int) -> void:
	if _live_count() == 1:
		_award_uncontested()
		return
	if _round_done():
		_advance_street()
	else:
		current = _next_actor(i)
		if current == -1:
			_advance_street()

func _round_done() -> bool:
	for k in range(players.size()):
		var p := players[k]
		if not _can_act(p):
			continue
		if not _acted.has(k) or int(p.bet) != current_bet:
			return false
	return true

func _advance_street() -> void:
	for p in players:
		p.bet = 0
	current_bet = 0
	min_raise = big_blind
	_acted.clear()
	match stage:
		Stage.PREFLOP:
			stage = Stage.FLOP
			_deal_board(3)
		Stage.FLOP:
			stage = Stage.TURN
			_deal_board(1)
		Stage.TURN:
			stage = Stage.RIVER
			_deal_board(1)
		_:
			_showdown()
			return
	current = _next_actor(dealer)
	_skip_if_nobody_can_act()

## If at most one player can still bet, no more betting happens: run the board out.
func _skip_if_nobody_can_act() -> void:
	if hand_over or _actor_count() > 1 or _someone_owes_call():
		return
	if stage == Stage.RIVER:
		_showdown()
	else:
		_advance_street()

func _someone_owes_call() -> bool:
	for p in players:
		if _can_act(p) and int(p.bet) < current_bet:
			return true
	return false

func _deal_board(n: int) -> void:
	for _k in range(n):
		if _rigged_board.size() > board.size():
			board.append(_rigged_board[board.size()])
		else:
			board.append(_draw())
	log_lines.append("Board: %s" % ", ".join(board.map(func(c): return Eval.card_name(c))))

# ── Ending a hand ─────────────────────────────────────────────────────

func _award_uncontested() -> void:
	var winner := -1
	for k in range(players.size()):
		if players[k].in_hand and not players[k].folded:
			winner = k
	var amt := pot()
	players[winner].chips += amt
	results = [{"winners": [winner], "amount": amt, "hand": "", "best": []}]
	log_lines.append("%s wins %d" % [players[winner].name, amt])
	hand_over = true
	current = -1

func _showdown() -> void:
	while board.size() < 5:
		if _rigged_board.size() > board.size():
			board.append(_rigged_board[board.size()])
		else:
			board.append(_draw())
	stage = Stage.SHOWDOWN
	showdown_reached = true
	var scores: Dictionary = {}
	for k in range(players.size()):
		var p := players[k]
		if p.in_hand and not p.folded:
			scores[k] = Eval.evaluate(p.hole + board)
	# Side pots from contribution levels.
	var levels: Array = []
	for p in players:
		if int(p.total) > 0 and not levels.has(int(p.total)):
			levels.append(int(p.total))
	levels.sort()
	var prev := 0
	results.clear()
	for lvl in levels:
		var amount := 0
		for p in players:
			amount += maxi(mini(int(p.total), lvl) - prev, 0)
		var elig: Array = []
		for k in range(players.size()):
			if scores.has(k) and int(players[k].total) >= lvl:
				elig.append(k)
		prev = lvl
		if amount == 0 or elig.is_empty():
			continue
		var best := -1
		for k in elig:
			best = maxi(best, int(scores[k].score))
		var wins: Array = []
		for k in elig:
			if int(scores[k].score) == best:
				wins.append(k)
		var share: int = int(float(amount) / float(wins.size()))
		var rem: int = amount - share * wins.size()
		for w in wins:
			players[w].chips += share
		players[wins[0]].chips += rem
		results.append({"winners": wins, "amount": amount, "hand": scores[wins[0]].name, "best": scores[wins[0]].best})
		log_lines.append("%s wins %d with %s" % [", ".join(wins.map(func(w): return players[w].name)), amount, scores[wins[0]].name])
	hand_over = true
	current = -1

# ── Strength + advice (used by the coach and the computer players) ────

## Rough 0..1 strength of a 2-card starting hand.
static func preflop_strength(hole: Array) -> float:
	var r1: int = Eval.rank_of(hole[0])
	var r2: int = Eval.rank_of(hole[1])
	var hi: int = maxi(r1, r2)
	var lo: int = mini(r1, r2)
	var pts: float = float(hi) / 2.0
	match hi:
		14: pts = 10.0
		13: pts = 8.0
		12: pts = 7.0
		11: pts = 6.0
	if r1 == r2:
		pts = maxf(pts * 2.0, 5.0)
	else:
		if Eval.suit_of(hole[0]) == Eval.suit_of(hole[1]):
			pts += 2.0
		var gap: int = hi - lo - 1
		var penalty: Array = [0.0, 1.0, 2.0, 4.0, 5.0]
		pts -= float(penalty[mini(gap, 4)])
		if gap <= 1 and hi < 12:
			pts += 1.0
	return clampf(pts / 20.0, 0.0, 1.0)

## 0..1 strength of the hand on the current board, counting simple draws.
static func postflop_strength(hole: Array, board_cards: Array) -> float:
	var all: Array = hole + board_cards
	var r: Dictionary = Eval.evaluate(all)
	var base: Array = [0.12, 0.42, 0.68, 0.78, 0.86, 0.9, 0.95, 0.98, 1.0, 1.0]
	var s: float = base[int(r.cat)]
	if int(r.cat) == Eval.HIGH_CARD:
		s += (float(Eval.rank_of(hole[0]) + Eval.rank_of(hole[1])) - 10.0) / 120.0
	elif int(r.cat) == Eval.PAIR:
		# A pair that lives entirely on the board is weak.
		var pr: int = int(r.ranks[0])
		var mine: bool = Eval.rank_of(hole[0]) == pr or Eval.rank_of(hole[1]) == pr
		if not mine:
			s = 0.2
		else:
			var top := 0
			for c in board_cards:
				top = maxi(top, Eval.rank_of(c))
			s = 0.5 if pr >= top else 0.38
	if board_cards.size() < 5 and int(r.cat) < Eval.STRAIGHT:
		var suit_n: Dictionary = {}
		for c in all:
			suit_n[Eval.suit_of(c)] = int(suit_n.get(Eval.suit_of(c), 0)) + 1
		for k in suit_n:
			if suit_n[k] == 4:
				s += 0.14
		var outs := 0
		for rk in range(2, 15):
			var test: Array = all + [Eval.make(rk, 0)]
			if int(Eval.evaluate(test).cat) >= Eval.STRAIGHT:
				outs += 1
		if outs >= 2:
			s += 0.12
		elif outs == 1:
			s += 0.06
	return clampf(s, 0.0, 1.0)

func strength_of(i: int) -> float:
	var p := players[i]
	if board.size() == 0:
		return preflop_strength(p.hole)
	return postflop_strength(p.hole, board)

## Suggested move for any seat. Returns {kind:String, raise_to:int, why:String}.
func advise(i: int, noise: float = 0.0, aggression: float = 0.0) -> Dictionary:
	var s: float = strength_of(i) + noise
	var owe := to_call(i)
	var pot_now := pot()
	var bb := big_blind
	var odds := float(owe) / float(maxi(pot_now + owe, 1))
	var pre := board.size() == 0
	var want_raise: bool = s > 0.72 - aggression and can_raise(i)
	if pre and current_bet > 6 * bb and s < 0.88:
		want_raise = false
	if want_raise:
		var size := int(pot_now * (0.5 + s * 0.5))
		if pre:
			size = int(bb * (2.5 + s * 1.5))
		var lo := min_raise_to(i)
		var to := clampi(maxi(current_bet + maxi(size, min_raise), lo), lo, max_raise_to(i))
		if s > 0.95 and randf() < 0.3:
			to = max_raise_to(i)
		return {"kind": "raise", "raise_to": to, "why": "Your hand is strong. Betting builds the pot while you are ahead."}
	if can_check(i):
		return {"kind": "check", "raise_to": 0, "why": "Checking is free. See the next card without risking chips."}
	if s >= odds + 0.08 or (pre and owe <= bb and s > 0.22) or owe <= int(bb * 0.5):
		return {"kind": "call", "raise_to": 0, "why": "The price (%d) is fair for what your hand is worth." % owe}
	return {"kind": "fold", "raise_to": 0, "why": "The hand is weak and it costs %d to continue. Folding saves chips." % owe}

func ai_decide(i: int) -> Dictionary:
	var p := players[i]
	var noise := randf_range(-0.07, 0.07)
	var agg := 0.0
	match String(p.style):
		"tight":
			noise -= 0.05
			agg = -0.04
		"loose":
			noise += 0.06
		"wild":
			noise += randf_range(-0.1, 0.12)
			agg = 0.08
	var d := advise(i, noise, agg)
	var bluff_chance: float = 0.10 if p.style == "wild" else 0.04
	if d.kind != "raise" and can_raise(i) and randf() < bluff_chance and to_call(i) <= big_blind * 3:
		var to := clampi(current_bet + maxi(pot(), min_raise), min_raise_to(i), max_raise_to(i))
		d = {"kind": "raise", "raise_to": to, "why": "bluff"}
	return d
