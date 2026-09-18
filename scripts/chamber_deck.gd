extends RefCounted
class_name ChamberDeck

## Implements the "Chamber Draw" mini-deck from GDD section 6.
## 6 cards: 1 Live, 3 Blank, 1 Backfire, 1 Lucky Draw.
## The deck is reshuffled after every single draw, so odds reset each time.

enum Result { LIVE, BLANK, BACKFIRE, LUCKY_DRAW }

const COMPOSITION = {
	Result.LIVE: 1,
	Result.BLANK: 3,
	Result.BACKFIRE: 1,
	Result.LUCKY_DRAW: 1,
}

var _chamber: Array = []

func _init() -> void:
	_reshuffle()

func _reshuffle() -> void:
	_chamber.clear()
	for result in COMPOSITION.keys():
		for _i in range(COMPOSITION[result]):
			_chamber.append(result)
	_chamber.shuffle()

## Draws one outcome from the chamber, then reshuffles for next time
## (per GDD: "the Chamber Deck is reshuffled for next time").
func draw() -> Result:
	if _chamber.is_empty():
		_reshuffle()
	var result = _chamber.pop_back()
	_reshuffle()
	return result

static func result_name(result: Result) -> String:
	match result:
		Result.LIVE: return "LIVE"
		Result.BLANK: return "Blank"
		Result.BACKFIRE: return "Backfire"
		Result.LUCKY_DRAW: return "Lucky Draw"
	return "Unknown"
