@tool
extends McpTestSuite

func suite_name() -> String:
	return "chamber_deck"


func test_initial_composition_is_valid() -> void:
	var cd := ChamberDeck.new()
	assert_eq(cd._chamber.size(), 6, "6 cards in chamber")
	assert_eq(_count_result(cd._chamber, ChamberDeck.Result.LIVE), 1)
	assert_eq(_count_result(cd._chamber, ChamberDeck.Result.BLANK), 3)
	assert_eq(_count_result(cd._chamber, ChamberDeck.Result.BACKFIRE), 1)
	assert_eq(_count_result(cd._chamber, ChamberDeck.Result.LUCKY_DRAW), 1)


func test_draw_returns_valid_result() -> void:
	var cd := ChamberDeck.new()
	for _i in range(50):
		var result := cd.draw()
		assert_true(result in [ChamberDeck.Result.LIVE, ChamberDeck.Result.BLANK, ChamberDeck.Result.BACKFIRE, ChamberDeck.Result.LUCKY_DRAW], "valid result %s" % str(result))


func test_deck_reshuffles_after_each_draw() -> void:
	var cd := ChamberDeck.new()
	var first_draw := cd.draw()
	# After a draw, the chamber must be fully repopulated (GDD: reshuffled each time)
	assert_eq(cd._chamber.size(), 6, "chamber repopulated after draw")
	assert_true(first_draw in [ChamberDeck.Result.LIVE, ChamberDeck.Result.BLANK, ChamberDeck.Result.BACKFIRE, ChamberDeck.Result.LUCKY_DRAW])


func test_deck_recovers_after_single_draw() -> void:
	var cd := ChamberDeck.new()
	cd._chamber = [ChamberDeck.Result.LIVE]  # simulate drained
	var result := cd.draw()
	assert_eq(result, ChamberDeck.Result.LIVE, "draws the remaining card")
	assert_eq(cd._chamber.size(), 6, "deck reshuffled after drain")


func test_result_name_mapping() -> void:
	assert_eq(ChamberDeck.result_name(ChamberDeck.Result.LIVE), "LIVE")
	assert_eq(ChamberDeck.result_name(ChamberDeck.Result.BLANK), "Blank")
	assert_eq(ChamberDeck.result_name(ChamberDeck.Result.BACKFIRE), "Backfire")
	assert_eq(ChamberDeck.result_name(ChamberDeck.Result.LUCKY_DRAW), "Lucky Draw")


func test_result_name_unknown() -> void:
	assert_eq(ChamberDeck.result_name(99), "Unknown")


func test_draws_are_reasonably_distributed() -> void:
	# Over 300 draws (50 full resets), each outcome should appear at least a few times.
	var cd := ChamberDeck.new()
	var counts := {ChamberDeck.Result.LIVE: 0, ChamberDeck.Result.BLANK: 0, ChamberDeck.Result.BACKFIRE: 0, ChamberDeck.Result.LUCKY_DRAW: 0}
	for _i in range(300):
		counts[cd.draw()] += 1
	assert_gt(counts[ChamberDeck.Result.LIVE], 0, "LIVE drawn at least once")
	assert_gt(counts[ChamberDeck.Result.BLANK], 0, "BLANK drawn at least once")
	assert_gt(counts[ChamberDeck.Result.BACKFIRE], 0, "BACKFIRE drawn at least once")
	assert_gt(counts[ChamberDeck.Result.LUCKY_DRAW], 0, "LUCKY_DRAW drawn at least once")


func _count_result(chamber: Array, result: int) -> int:
	var n := 0
	for r in chamber:
		if r == result:
			n += 1
	return n