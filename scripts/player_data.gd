extends RefCounted
class_name PlayerData

var id: int
var display_name: String
var color_idx: int = 0
var color: Color = GameGlobals.PALETTE[0]
var hand: Array[Card] = []
var banked_lives: int = 0        # from Extra Life cards, one-time-use consumable
var eliminated: bool = false
var skip_next_turn: bool = false

const MAX_BANKED_LIVES = 2       # a player can hold at most TWO banked lives (GDD: max 2)

func _init(p_id: int, p_name: String) -> void:
	id = p_id
	display_name = p_name

func bank_extra_life() -> void:
	banked_lives = mini(banked_lives + 1, MAX_BANKED_LIVES)

## Returns true if a banked life absorbed the elimination.
func try_absorb_elimination() -> bool:
	if banked_lives > 0:
		banked_lives -= 1
		return true
	return false

func hand_size() -> int:
	return hand.size()
