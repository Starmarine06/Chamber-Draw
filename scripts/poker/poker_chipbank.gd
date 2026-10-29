extends RefCounted

## A seat's chips as REAL chips: counts per denomination. Every operation keeps the exact total,
## so a tower of chips on the table is always the player's real money (a bet takes actual chips
## out of the stack, a pot adds actual chips to it).

const DENOMS: Array = [500, 100, 25, 5, 1]   # largest first
const SHARES: Array = [[500, 0.30], [100, 0.30], [25, 0.22], [5, 0.12]]

var counts: Dictionary = {500: 0, 100: 0, 25: 0, 5: 0, 1: 0}

## A readable mix of chips worth exactly `v` (big denominations take a share, the rest is greedy).
static func mixed(v: int) -> Dictionary:
	var out: Dictionary = {500: 0, 100: 0, 25: 0, 5: 0, 1: 0}
	var left: int = maxi(v, 0)
	# A real stack always has some small change in it.
	if left >= 100:
		out[5] = 4
		out[1] = 5
		left -= 25
	for pair in SHARES:
		var d: int = pair[0]
		var n: int = mini(int(round(float(v) * float(pair[1]) / float(d))), int(left / d))
		out[d] = int(out[d]) + n
		left -= n * d
	for d in DENOMS:
		var n2: int = int(left / d)
		out[d] = int(out[d]) + n2
		left -= n2 * d
	return out

static func value_of(c: Dictionary) -> int:
	var t := 0
	for d in c:
		t += int(d) * int(c[d])
	return t

func from_value(v: int) -> void:
	counts = mixed(v)

func value() -> int:
	return value_of(counts)

func chip_count() -> int:
	var n := 0
	for d in counts:
		n += int(counts[d])
	return n

## Breaks one chip of denomination `d` into smaller chips (greedy) so change is available.
func _break(d: int) -> void:
	counts[d] = int(counts[d]) - 1
	var left := d
	for s in DENOMS:
		if s >= d:
			continue
		var n: int = int(left / s)
		counts[s] = int(counts[s]) + n
		left -= n * s

## Removes chips worth `amount` and returns the chips actually removed (their value is `amount`
## unless the bank holds less). Exact-fit chips are spent first, then a larger chip is broken.
func take(amount: int) -> Dictionary:
	var removed: Dictionary = {500: 0, 100: 0, 25: 0, 5: 0, 1: 0}
	var remaining: int = amount
	for _guard in range(20):
		for d in DENOMS:
			if remaining <= 0:
				break
			var n: int = mini(int(counts[d]), int(remaining / d))
			if n > 0:
				counts[d] = int(counts[d]) - n
				removed[d] = int(removed[d]) + n
				remaining -= n * d
		if remaining <= 0:
			break
		# Not payable with what is on hand: break the smallest chip bigger than the remainder.
		var found := -1
		for d in DENOMS:
			if int(counts[d]) > 0 and d > remaining:
				found = d
		if found < 0:
			break
		_break(found)
	return removed

## Takes one chip of denomination `d` (breaking a bigger chip when there is none). False if impossible.
func take_denom(d: int) -> bool:
	for _guard in range(8):
		if int(counts[d]) > 0:
			counts[d] = int(counts[d]) - 1
			return true
		var found := -1
		for s in DENOMS:
			if s > d and int(counts[s]) > 0:
				found = s
		if found < 0:
			return false
		_break(found)
	return false

func give(d: int, n: int = 1) -> void:
	counts[d] = int(counts[d]) + n

func give_counts(c: Dictionary) -> void:
	for d in c:
		give(int(d), int(c[d]))

## Adds chips worth `v` (a mixed set, like a dealer paying out a pot). Returns the chips added.
func add_value(v: int) -> Dictionary:
	var c := mixed(v)
	give_counts(c)
	return c

## Reconciles to the engine's integer chip total. Returns {removed: counts, added: counts}.
func sync(target: int) -> Dictionary:
	var diff: int = target - value()
	if diff < 0:
		return {"removed": take(-diff), "added": {}}
	if diff > 0:
		return {"removed": {}, "added": add_value(diff)}
	return {"removed": {}, "added": {}}
