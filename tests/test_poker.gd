@tool
extends McpTestSuite

const Eval := preload("res://scripts/poker/poker_eval.gd")
const Table := preload("res://scripts/poker/poker_table.gd")
const Bank := preload("res://scripts/poker/poker_chipbank.gd")

func suite_name() -> String:
	return "poker"


func _c(rank: int, suit: int) -> int:
	return Eval.make(rank, suit)


func test_hand_categories() -> void:
	var cases: Array = [
		[[_c(14, 3), _c(13, 3), _c(12, 3), _c(11, 3), _c(10, 3), _c(2, 0), _c(3, 1)], Eval.ROYAL_FLUSH],
		[[_c(9, 1), _c(8, 1), _c(7, 1), _c(6, 1), _c(5, 1), _c(2, 0), _c(3, 2)], Eval.STRAIGHT_FLUSH],
		[[_c(9, 1), _c(9, 0), _c(9, 2), _c(9, 3), _c(5, 1), _c(2, 0), _c(3, 2)], Eval.QUADS],
		[[_c(9, 1), _c(9, 0), _c(9, 2), _c(5, 3), _c(5, 1), _c(2, 0), _c(3, 2)], Eval.FULL_HOUSE],
		[[_c(14, 1), _c(10, 1), _c(7, 1), _c(5, 3), _c(4, 1), _c(2, 1), _c(3, 2)], Eval.FLUSH],
		[[_c(14, 1), _c(2, 0), _c(3, 1), _c(4, 3), _c(5, 1), _c(13, 0), _c(9, 2)], Eval.STRAIGHT],
		[[_c(9, 1), _c(9, 0), _c(9, 2), _c(5, 3), _c(6, 1), _c(2, 0), _c(3, 2)], Eval.TRIPS],
		[[_c(9, 1), _c(9, 0), _c(4, 2), _c(4, 3), _c(6, 1), _c(2, 0), _c(13, 2)], Eval.TWO_PAIR],
		[[_c(9, 1), _c(9, 0), _c(11, 2), _c(4, 3), _c(6, 1), _c(2, 0), _c(13, 2)], Eval.PAIR],
		[[_c(14, 1), _c(10, 0), _c(11, 2), _c(4, 3), _c(6, 1), _c(2, 0), _c(13, 2)], Eval.HIGH_CARD],
	]
	for cs in cases:
		var r: Dictionary = Eval.evaluate(cs[0])
		assert_eq(r.cat, cs[1], "category for %s" % r.name)


func test_kicker_breaks_ties() -> void:
	var a: Dictionary = Eval.evaluate([_c(9, 1), _c(9, 0), _c(14, 2), _c(4, 3), _c(6, 1)])
	var b: Dictionary = Eval.evaluate([_c(9, 2), _c(9, 3), _c(13, 2), _c(4, 1), _c(6, 0)])
	assert_true(a.score > b.score, "ace kicker beats king kicker")


func test_wheel_is_lowest_straight() -> void:
	var wheel: Dictionary = Eval.evaluate([_c(14, 0), _c(2, 1), _c(3, 2), _c(4, 3), _c(5, 0)])
	var six: Dictionary = Eval.evaluate([_c(2, 0), _c(3, 1), _c(4, 2), _c(5, 3), _c(6, 0)])
	assert_eq(wheel.cat, Eval.STRAIGHT, "A-5 is a straight")
	assert_true(six.score > wheel.score, "6-high beats the wheel")


func test_chips_conserved_over_random_games() -> void:
	for _g in range(10):
		var t := Table.new()
		var n: int = randi_range(2, 8)
		var names: Array = []
		for i in range(n):
			names.append("P%d" % i)
		t.setup(names, 1000, 0)
		for _h in range(30):
			if t.alive_count() < 2:
				break
			t.start_hand()
			var guard := 0
			while not t.hand_over and guard < 300:
				guard += 1
				var d: Dictionary = t.ai_decide(t.current)
				t.act(d.kind, d.raise_to)
			assert_true(guard < 300, "hand terminates")
			var total := 0
			for p in t.players:
				total += int(p.chips)
			assert_eq(total, n * 1000, "chips conserved")


func test_rigged_hand_pays_best_hand() -> void:
	var t := Table.new()
	t.setup(["You", "Bot"], 1000, 0)
	t.start_hand({
		"dealer": 0,
		"hole": {0: [_c(14, 3), _c(13, 3)], 1: [_c(12, 1), _c(11, 0)]},
		"board": [_c(14, 2), _c(7, 0), _c(2, 1), _c(9, 3), _c(13, 1)],
	})
	assert_eq(t.current, 0, "dealer/small blind acts first heads-up")
	t.act("call")
	t.act("check")
	while not t.hand_over:
		t.act("check" if t.can_check(t.current) else "call")
	assert_eq(int(t.players[0].chips), 1020, "You win the 40 chip pot")
	assert_eq(int(t.players[1].chips), 980, "Bot loses 20")


func test_fold_awards_pot() -> void:
	var t := Table.new()
	t.setup(["A", "B", "C"], 1000, 0)
	t.start_hand()
	t.act("fold")
	t.act("fold")
	assert_true(t.hand_over, "hand over when all but one fold")
	var total := 0
	for p in t.players:
		total += int(p.chips)
	assert_eq(total, 3000, "chips conserved")


func test_bank_start_is_exact_and_mixed() -> void:
	var b := Bank.new()
	b.from_value(1000)
	assert_eq(b.value(), 1000, "starting rack is worth 1000")
	assert_true(b.chip_count() > 8, "mixed chips, not two big ones")


func test_bank_take_returns_real_chips_and_keeps_total() -> void:
	var b := Bank.new()
	b.from_value(1000)
	for amount in [20, 5, 1, 100, 135, 7, 250]:
		var before: int = b.value()
		var removed: Dictionary = b.take(amount)
		assert_eq(Bank.value_of(removed), amount, "removed chips are worth %d" % amount)
		assert_eq(b.value(), before - amount, "bank dropped by %d" % amount)
		for d in b.counts:
			assert_true(int(b.counts[d]) >= 0, "no negative chip counts")


func test_bank_change_making() -> void:
	var b := Bank.new()
	b.counts = {500: 0, 100: 3, 25: 0, 5: 0, 1: 0}
	var removed: Dictionary = b.take(20)
	assert_eq(Bank.value_of(removed), 20, "20 paid out of 100s")
	assert_eq(b.value(), 280, "change stays in the bank")


func test_bank_take_denom_breaks_bigger_chip() -> void:
	var b := Bank.new()
	b.counts = {500: 0, 100: 1, 25: 0, 5: 0, 1: 0}
	assert_true(b.take_denom(5), "a 5 chip can be taken by breaking a 100")
	assert_eq(b.value(), 95, "value drops by exactly 5")


func test_bank_sync_both_ways() -> void:
	var b := Bank.new()
	b.from_value(1000)
	var r: Dictionary = b.sync(930)
	assert_eq(Bank.value_of(r.removed), 70, "sync down removes 70")
	assert_eq(b.value(), 930, "now 930")
	var a: Dictionary = b.sync(1240)
	assert_eq(Bank.value_of(a.added), 310, "sync up adds 310")
	assert_eq(b.value(), 1240, "now 1240")


func test_bank_cannot_overdraw() -> void:
	var b := Bank.new()
	b.from_value(30)
	var removed: Dictionary = b.take(100)
	assert_eq(Bank.value_of(removed), 30, "only what it holds")
	assert_eq(b.value(), 0, "empty")

