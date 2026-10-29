extends RefCounted

## Texas Hold'em hand evaluation. Cards are ints 0..51:
## rank = c % 13 + 2 (2..14, 14 = Ace), suit = c / 13 (0 clubs, 1 diamonds, 2 hearts, 3 spades).

const HIGH_CARD := 0
const PAIR := 1
const TWO_PAIR := 2
const TRIPS := 3
const STRAIGHT := 4
const FLUSH := 5
const FULL_HOUSE := 6
const QUADS := 7
const STRAIGHT_FLUSH := 8
const ROYAL_FLUSH := 9

const RANK_CHARS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const RANK_NAMES := ["Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace"]
const RANK_PLURAL := ["Twos", "Threes", "Fours", "Fives", "Sixes", "Sevens", "Eights", "Nines", "Tens", "Jacks", "Queens", "Kings", "Aces"]
const SUIT_NAMES := ["Clubs", "Diamonds", "Hearts", "Spades"]

## Rankings shown to the player, strongest first.
const TIERS := [
	{"cat": 9, "name": "Royal Flush", "desc": "A K Q J 10, all one suit", "example": [12 + 26, 11 + 26, 10 + 26, 9 + 26, 8 + 26]},
	{"cat": 8, "name": "Straight Flush", "desc": "Five in a row, one suit", "example": [7 + 13, 6 + 13, 5 + 13, 4 + 13, 3 + 13]},
	{"cat": 7, "name": "Four of a Kind", "desc": "Four cards of one rank", "example": [8, 8 + 13, 8 + 26, 8 + 39, 0]},
	{"cat": 6, "name": "Full House", "desc": "Three of a kind + a pair", "example": [10, 10 + 13, 10 + 26, 4 + 39, 4]},
	{"cat": 5, "name": "Flush", "desc": "Five cards of one suit", "example": [12 + 13, 9 + 13, 7 + 13, 4 + 13, 1 + 13]},
	{"cat": 4, "name": "Straight", "desc": "Five in a row, any suits", "example": [6, 5 + 13, 4 + 26, 3 + 39, 2]},
	{"cat": 3, "name": "Three of a Kind", "desc": "Three cards of one rank", "example": [9, 9 + 13, 9 + 26, 12, 3 + 13]},
	{"cat": 2, "name": "Two Pair", "desc": "Two different pairs", "example": [11, 11 + 39, 5 + 13, 5 + 26, 0]},
	{"cat": 1, "name": "One Pair", "desc": "Two cards of one rank", "example": [12, 12 + 13, 7 + 26, 4, 2 + 39]},
	{"cat": 0, "name": "High Card", "desc": "No pair. Highest card plays", "example": [12 + 26, 9, 7 + 13, 4 + 39, 1 + 26]},
]

static func rank_of(c: int) -> int:
	return c % 13 + 2

static func suit_of(c: int) -> int:
	return int(float(c) / 13.0)

static func card_name(c: int) -> String:
	return "%s of %s" % [RANK_NAMES[rank_of(c) - 2], SUIT_NAMES[suit_of(c)]]

static func make(rank: int, suit: int) -> int:
	return suit * 13 + (rank - 2)

## Best 5-card hand from 5-7 cards.
## Returns {score:int, cat:int, ranks:Array[int], best:Array[int], name:String}.
static func evaluate(cards: Array) -> Dictionary:
	var n: int = cards.size()
	var best: Dictionary = {}
	if n < 5:
		return _partial(cards)
	for a in range(n - 4):
		for b in range(a + 1, n - 3):
			for c in range(b + 1, n - 2):
				for d in range(c + 1, n - 1):
					for e in range(d + 1, n):
						var hand: Array = [cards[a], cards[b], cards[c], cards[d], cards[e]]
						var r: Dictionary = _eval5(hand)
						if best.is_empty() or r.score > best.score:
							best = r
	best["name"] = describe(best)
	return best

## Fewer than 5 cards (pre-flop / flop with 2 cards): a pair or high card only.
static func _partial(cards: Array) -> Dictionary:
	var counts: Dictionary = {}
	for c in cards:
		counts[rank_of(c)] = int(counts.get(rank_of(c), 0)) + 1
	var cat: int = HIGH_CARD
	var ranks: Array = []
	for r in counts:
		ranks.append(r)
	ranks.sort_custom(func(x, y): return x > y)
	var paired: int = 0
	for r in ranks:
		if counts[r] >= 2:
			paired = r
			cat = PAIR
	var score: int = cat * 759375
	var ordered: Array = ranks.duplicate()
	if paired > 0:
		ordered.erase(paired)
		ordered.push_front(paired)
	for i in range(mini(5, ordered.size())):
		score += int(ordered[i]) * int(pow(15, 4 - i))
	var res: Dictionary = {"score": score, "cat": cat, "ranks": ordered, "best": cards.duplicate()}
	res["name"] = describe(res)
	return res

static func _eval5(h: Array) -> Dictionary:
	var counts: Dictionary = {}
	var suits: Dictionary = {}
	for c in h:
		var r: int = rank_of(c)
		counts[r] = int(counts.get(r, 0)) + 1
		suits[suit_of(c)] = true
	var is_flush: bool = suits.size() == 1
	# Groups sorted by (count desc, rank desc).
	var groups: Array = []
	for r in counts:
		groups.append([counts[r], r])
	groups.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] > y[1]))
	var ranks: Array = []
	for g in groups:
		ranks.append(g[1])
	var straight_high: int = 0
	if groups.size() == 5:
		if int(ranks[0]) - int(ranks[4]) == 4:
			straight_high = ranks[0]
		elif ranks[0] == 14 and ranks[1] == 5 and ranks[2] == 4 and ranks[3] == 3 and ranks[4] == 2:
			straight_high = 5
			ranks = [5, 4, 3, 2, 1]
	var cat: int = HIGH_CARD
	if straight_high > 0 and is_flush:
		cat = ROYAL_FLUSH if straight_high == 14 else STRAIGHT_FLUSH
	elif groups[0][0] == 4:
		cat = QUADS
	elif groups[0][0] == 3 and groups.size() > 1 and groups[1][0] == 2:
		cat = FULL_HOUSE
	elif is_flush:
		cat = FLUSH
	elif straight_high > 0:
		cat = STRAIGHT
	elif groups[0][0] == 3:
		cat = TRIPS
	elif groups[0][0] == 2 and groups.size() > 1 and groups[1][0] == 2:
		cat = TWO_PAIR
	elif groups[0][0] == 2:
		cat = PAIR
	var score: int = cat * 759375
	for i in range(ranks.size()):
		score += int(ranks[i]) * int(pow(15, 4 - i))
	return {"score": score, "cat": cat, "ranks": ranks, "best": h.duplicate()}

## Friendly one-line name, e.g. "Pair of Kings", "Two Pair, Aces and Fours".
static func describe(r: Dictionary) -> String:
	var ranks: Array = r.ranks
	match int(r.cat):
		ROYAL_FLUSH: return "Royal Flush"
		STRAIGHT_FLUSH: return "Straight Flush, %s high" % RANK_NAMES[maxi(int(ranks[0]), 2) - 2]
		QUADS: return "Four of a Kind, %s" % RANK_PLURAL[int(ranks[0]) - 2]
		FULL_HOUSE: return "Full House, %s over %s" % [RANK_PLURAL[int(ranks[0]) - 2], RANK_PLURAL[int(ranks[1]) - 2]]
		FLUSH: return "Flush, %s high" % RANK_NAMES[int(ranks[0]) - 2]
		STRAIGHT: return "Straight, %s high" % RANK_NAMES[maxi(int(ranks[0]), 2) - 2]
		TRIPS: return "Three of a Kind, %s" % RANK_PLURAL[int(ranks[0]) - 2]
		TWO_PAIR: return "Two Pair, %s and %s" % [RANK_PLURAL[int(ranks[0]) - 2], RANK_PLURAL[int(ranks[1]) - 2]]
		PAIR: return "Pair of %s" % RANK_PLURAL[int(ranks[0]) - 2]
		_: return "%s High" % RANK_NAMES[int(ranks[0]) - 2]

## Plain-English line for a category, used by the coach.
static func explain(cat: int) -> String:
	match cat:
		ROYAL_FLUSH: return "The best hand in poker. Almost nothing beats this."
		STRAIGHT_FLUSH: return "Five in a row, all the same suit. Monster hand."
		QUADS: return "Four matching cards. Extremely strong."
		FULL_HOUSE: return "Three of one rank plus a pair. Very strong."
		FLUSH: return "Five cards of one suit. Strong."
		STRAIGHT: return "Five cards in a row. Strong."
		TRIPS: return "Three matching cards. Good, usually worth betting."
		TWO_PAIR: return "Two pairs. A solid hand."
		PAIR: return "A pair. Okay, but it can lose to better hands."
		_: return "No pair yet. This is the weakest kind of hand."
