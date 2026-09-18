extends Resource
class_name Card

## A single playing card. Numbers, Action cards, Wild cards, and the special
## Bomb / Diffuse cards all use this same Resource with different fields set.

enum CardType { NUMBER, ACTION, WILD, BOMB, DIFFUSE, RESPAWN }

# Renamed to CardColor (not "Color") so we don't shadow Godot's built-in Color type.
# Values are stable network ids: ORANGE/PURPLE are appended AFTER NONE so any
# serialized/saved color index keeps its meaning.
enum CardColor { RED, BLUE, GREEN, YELLOW, NONE, ORANGE, PURPLE }

@export var type: CardType = CardType.NUMBER
@export var color: CardColor = CardColor.NONE
@export var number: int = -1          # only meaningful for NUMBER cards
@export var action_id: String = ""    # e.g. "skip", "reverse", "draw_two", "draw_four",
									   # "draw_ten", "swap_hands", "peek", "extra_life",
									   # "choose_deck", "rotate_decks",
									   # "wild_color", "wild_sabotage"
@export var display_name: String = ""

func _to_string() -> String:
	return display_name

## Serialize to a plain Dictionary for network transfer / snapshot.
func to_dict() -> Dictionary:
	return {
		"type": type,
		"color": color,
		"number": number,
		"action_id": action_id,
		"display_name": display_name,
	}

## Rebuild a Card from a Dictionary produced by to_dict().
static func from_dict(d: Dictionary) -> Card:
	var card := Card.new()
	card.type = int(d.get("type", CardType.NUMBER)) as CardType
	card.color = int(d.get("color", CardColor.NONE)) as CardColor
	card.number = int(d.get("number", -1))
	card.action_id = str(d.get("action_id", ""))
	card.display_name = str(d.get("display_name", ""))
	return card

## Whether this card can be legally played on top of the given active state.
## Wild, Choose a Deck, Rotate Decks, Extra Life, Draw Ten, Swap Hands, Peek, and
## Respawn are treated as "anytime" cards (playable regardless of active state).
## SKIP and REVERSE also match ANY card with the same action_id — a Red Reverse
## plays on a Green Reverse regardless of color. The +N Draw cards (Draw Two/Four)
## stay COLOR-locked in normal play; cross-color +N plays happen ONLY through the
## forced-draw stacking bypass (is_draw_stack_candidate).
func matches(active_color: int, active_number: int, active_action_id: String = "") -> bool:
	match type:
		CardType.NUMBER:
			return color == active_color or number == active_number
		CardType.ACTION:
			if action_id in ["swap_hands", "peek", "extra_life", "choose_deck", "rotate_decks", "draw_ten"]:
				return true
			if action_id in ["skip", "reverse"] and active_action_id != "" and action_id == active_action_id:
				return true
			return color == active_color
		CardType.WILD:
			return true
		CardType.RESPAWN:
			return true
		_:
			return false
