extends RefCounted
class_name DeckManager

## Implements the Multi-Deck System from GDD section 4.5:
## two draw piles are always on the table, players choose which to draw from,
## and Rotate Decks re-merges + reshuffles + redeals them.

var pile_a: Array[Card] = []
var pile_b: Array[Card] = []
var discard: Array[Card] = []

func setup(num_players: int) -> void:
	var safe_pool := CardDatabase.build_safe_pool(num_players)
	var threats := CardDatabase.build_threat_cards(num_players)

	# Exact chamber distribution: N players -> N Bomb cards in EACH deck
	# (2 per player total, one per deck). Diffuses are scattered at random.
	var bombs: Array[Card] = []
	var diffuses: Array[Card] = []
	for t in threats:
		if t.type == Card.CardType.BOMB:
			bombs.append(t)
		else:
			diffuses.append(t)

	# Strong shuffle: shuffle the whole safe pool, then DEAL it out card-by-card
	# alternating decks, so both piles get an even mix of numbers/actions/wilds
	# (no contiguous half-pile clumps). Each pile is shuffled once more.
	safe_pool.shuffle()
	pile_a.clear()
	pile_b.clear()
	for i in range(safe_pool.size()):
		if i % 2 == 0:
			pile_a.append(safe_pool[i])
		else:
			pile_b.append(safe_pool[i])
	pile_a.shuffle()
	pile_b.shuffle()

	bombs.shuffle()
	var bombs_per_deck := bombs.size() >> 1
	for i in range(bombs_per_deck):
		pile_a.insert(randi() % (pile_a.size() + 1), bombs[i])
		pile_b.insert(randi() % (pile_b.size() + 1), bombs[bombs_per_deck + i])

	diffuses.shuffle()
	for d in diffuses:
		var target: Array[Card] = pile_a if randi() % 2 == 0 else pile_b
		target.insert(randi() % (target.size() + 1), d)

func _pile(pile_id: String) -> Array[Card]:
	return pile_a if pile_id == "A" else pile_b

## Draws the top card from the named pile ("A" or "B").
## If the pile is empty, the discard is split between BOTH piles first.
func draw_from(pile_id: String) -> Card:
	var pile := _pile(pile_id)
	if pile.is_empty():
		_split_discard_into_piles()
		pile = _pile(pile_id)
	if pile.is_empty():
		return null  # both piles and discard are genuinely empty (shouldn't happen in normal play)
	return pile.pop_back()

## When a draw pile runs out, the discard is shuffled and dealt out alternating
## between both piles (an even mix) instead of being dumped into the exhausted
## deck or split into contiguous halves.
func _split_discard_into_piles() -> void:
	if discard.is_empty():
		return
	discard.shuffle()
	for i in range(discard.size()):
		if i % 2 == 0:
			pile_a.append(discard[i])
		else:
			pile_b.append(discard[i])
	discard.clear()

func discard_card(card: Card) -> void:
	discard.append(card)

## "Rotate Decks" card effect: merge both piles, reshuffle, redeal evenly.
func rotate_decks() -> void:
	var merged: Array[Card] = []
	merged.append_array(pile_a)
	merged.append_array(pile_b)
	merged.shuffle()
	pile_a.clear()
	pile_b.clear()
	for i in range(merged.size()):
		if i % 2 == 0:
			pile_a.append(merged[i])
		else:
			pile_b.append(merged[i])

## Returns the top N cards of a pile without removing them (for the Peek card).
func peek(pile_id: String, n: int) -> Array[Card]:
	var pile := _pile(pile_id)
	var count: int = min(n, pile.size())
	return pile.slice(pile.size() - count, pile.size())

## After a Peek, the player may submit a reordered version of the top N cards.
func reorder_top(pile_id: String, new_order: Array[Card]) -> void:
	var pile := _pile(pile_id)
	var base_count := pile.size() - new_order.size()
	var kept := pile.slice(0, base_count)
	kept.append_array(new_order)
	if pile_id == "A":
		pile_a = kept
	else:
		pile_b = kept

## Returns the Bomb card back into a random pile at a random position
## (used when a Diffuse cancels a Chamber Draw instead of removing the Bomb outright).
func return_bomb_randomly(bomb_card: Card) -> void:
	var pile_id := "A" if randi() % 2 == 0 else "B"
	var pile := _pile(pile_id)
	var index := randi() % (pile.size() + 1)
	pile.insert(index, bomb_card)

## Respawn cards exist ONLY while a player is eliminated. Adds `count` Respawn
## cards at random positions across both piles (called right after a player dies).
func add_respawn_cards(count: int) -> void:
	for _i in range(count):
		var card := CardDatabase._make(Card.CardType.RESPAWN, Card.CardColor.NONE, -1, "respawn", "RESPAWN")
		var target: Array[Card] = pile_a if randi() % 2 == 0 else pile_b
		target.insert(randi() % (target.size() + 1), card)

## Removes every Respawn card still in the piles (used when no eliminated player
## remains). Returns how many were removed. Cards already drawn into hands or the
## discard are left alone — they were consumed.
func remove_respawn_cards() -> int:
	var removed := 0
	var kept_a: Array[Card] = []
	for c in pile_a:
		if c.type == Card.CardType.RESPAWN:
			removed += 1
		else:
			kept_a.append(c)
	var kept_b: Array[Card] = []
	for c in pile_b:
		if c.type == Card.CardType.RESPAWN:
			removed += 1
		else:
			kept_b.append(c)
	pile_a = kept_a
	pile_b = kept_b
	return removed
