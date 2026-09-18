extends RefCounted
class_name CardDatabase

## Builds the full, tunable card pool described in the Chamber Draw GDD.
## All counts below are constants so they're easy to rebalance later —
## nothing else in the codebase needs to change if you tweak these numbers.

const COLORS = [Card.CardColor.RED, Card.CardColor.GREEN, Card.CardColor.ORANGE, Card.CardColor.PURPLE]

# --- Number cards ---
const COPIES_PER_NUMBER = 2      # numbers 1-9 get this many copies per color
const COPIES_OF_ZERO = 1         # zero gets fewer copies per color

# --- Colored action cards (per color) ---
const SKIP_PER_COLOR = 2
const REVERSE_PER_COLOR = 2
const DRAW_TWO_PER_COLOR = 2
const DRAW_FOUR_PER_COLOR = 1    # rarer than Draw Two

# --- Colorless / "anytime" special cards (total counts, not per color) ---
const SWAP_HANDS_COUNT = 4
const PEEK_COUNT = 4
const CHOOSE_DECK_COUNT = 4
const ROTATE_DECKS_COUNT = 3
const DRAW_TEN_COUNT = 1         # intentionally a single rare copy, see GDD section 4.2

# --- Wild cards ---
const WILD_COLOR_COUNT = 4
const WILD_SABOTAGE_COUNT = 2

## Returns the number of Bomb (chamber) cards for a given player count.
## 2 per player total: one destined for Deck A, one for Deck B (see
## DeckManager.setup for the exact per-deck placement).
static func bomb_count_for(num_players: int) -> int:
	return num_players * 2

## Diffuse cards scale alongside bombs, always one more than the bomb count.
static func diffuse_count_for(num_players: int) -> int:
	return bomb_count_for(num_players) + 1

## Extra Life cards scale with players: 2 per player (each is a one-time-use
## consumable that banks up to 2 lives — see PlayerData.MAX_BANKED_LIVES).
static func extra_life_count_for(num_players: int) -> int:
	return num_players * 2

static func _make(type: Card.CardType, color: int, number: int, action_id: String, display_name: String) -> Card:
	var c := Card.new()
	c.type = type
	c.color = color as Card.CardColor
	c.number = number
	c.action_id = action_id
	c.display_name = display_name
	return c

## Builds the "safe" pool: numbers + actions + wilds (everything except Bomb/Diffuse).
## This pool gets split across Deck A and Deck B by DeckManager, along with the
## bombs/diffuses returned separately by build_threat_cards().
static func build_safe_pool(num_players: int = 4) -> Array[Card]:
	var pool: Array[Card] = []

	# Numbers
	for color in COLORS:
		var color_name = Card.CardColor.keys()[color]
		pool.append(_make(Card.CardType.NUMBER, color, 0, "", "%s 0" % color_name))
		for _i in range(COPIES_OF_ZERO - 1):
			pool.append(_make(Card.CardType.NUMBER, color, 0, "", "%s 0" % color_name))
		for n in range(1, 10):
			for _i in range(COPIES_PER_NUMBER):
				pool.append(_make(Card.CardType.NUMBER, color, n, "", "%s %d" % [color_name, n]))

	# Colored action cards
	for color in COLORS:
		var color_name = Card.CardColor.keys()[color]
		for _i in range(SKIP_PER_COLOR):
			pool.append(_make(Card.CardType.ACTION, color, -1, "skip", "%s Skip" % color_name))
		for _i in range(REVERSE_PER_COLOR):
			pool.append(_make(Card.CardType.ACTION, color, -1, "reverse", "%s Reverse" % color_name))
		for _i in range(DRAW_TWO_PER_COLOR):
			pool.append(_make(Card.CardType.ACTION, color, -1, "draw_two", "%s Draw Two" % color_name))
		for _i in range(DRAW_FOUR_PER_COLOR):
			pool.append(_make(Card.CardType.ACTION, color, -1, "draw_four", "%s Draw Four" % color_name))

	# Colorless special action cards
	for _i in range(SWAP_HANDS_COUNT):
		pool.append(_make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "swap_hands", "Swap Hands"))
	for _i in range(PEEK_COUNT):
		pool.append(_make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "peek", "Peek"))
	for _i in range(extra_life_count_for(num_players)):
		pool.append(_make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "extra_life", "Extra Life"))
	for _i in range(CHOOSE_DECK_COUNT):
		pool.append(_make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "choose_deck", "Choose a Deck"))
	for _i in range(ROTATE_DECKS_COUNT):
		pool.append(_make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "rotate_decks", "Rotate Decks"))
	for _i in range(DRAW_TEN_COUNT):
		pool.append(_make(Card.CardType.ACTION, Card.CardColor.NONE, -1, "draw_ten", "Draw Ten"))

	# Wild cards
	for _i in range(WILD_COLOR_COUNT):
		pool.append(_make(Card.CardType.WILD, Card.CardColor.NONE, -1, "wild_color", "Wild Color"))
	for _i in range(WILD_SABOTAGE_COUNT):
		pool.append(_make(Card.CardType.WILD, Card.CardColor.NONE, -1, "wild_sabotage", "Wild Sabotage"))

	# Respawn cards are NOT seeded at setup. They enter the deck only while a
	# player is eliminated and are removed again when nobody is dead (see
	# DeckManager.add/remove_respawn_cards + game_state.gd sync_respawn_cards).

	return pool

## Builds the threat cards (Bombs + Diffuses) for a given player count.
static func build_threat_cards(num_players: int) -> Array[Card]:
	var threats: Array[Card] = []
	for _i in range(bomb_count_for(num_players)):
		threats.append(_make(Card.CardType.BOMB, Card.CardColor.NONE, -1, "bomb", "BOMB"))
	for _i in range(diffuse_count_for(num_players)):
		threats.append(_make(Card.CardType.DIFFUSE, Card.CardColor.NONE, -1, "diffuse", "Diffuse"))
	return threats
