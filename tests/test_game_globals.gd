@tool
extends McpTestSuite

func suite_name() -> String:
	return "game_globals"


func test_palette_has_8_distinct_colors() -> void:
	assert_eq(GameGlobals.PALETTE.size(), 8, "8 seat colors")
	assert_eq(GameGlobals.PALETTE_NAMES.size(), 8, "8 color names")


func test_palette_names_match_indices() -> void:
	assert_eq(GameGlobals.PALETTE_NAMES[0], "Red")
	assert_eq(GameGlobals.PALETTE_NAMES[1], "Blue")
	assert_eq(GameGlobals.PALETTE_NAMES[2], "Green")
	assert_eq(GameGlobals.PALETTE_NAMES[3], "Yellow")
	assert_eq(GameGlobals.PALETTE_NAMES[4], "Purple")
	assert_eq(GameGlobals.PALETTE_NAMES[5], "Orange")
	assert_eq(GameGlobals.PALETTE_NAMES[6], "Cyan")
	assert_eq(GameGlobals.PALETTE_NAMES[7], "Pink")


func test_defaults() -> void:
	# Autoload singletons aren't safely instance-accessible from editor/test
	# tool scope, so construct a fresh copy and let the framework free it.
	var g: Variant = (load("res://scripts/game_globals.gd") as GDScript).new()
	track(g)
	assert_eq(g.num_players, 4, "default 4 players")
	assert_eq(g.game_mode, 0, "default Shedding Race")
	assert_false(g.is_online, "defaults offline")
	assert_eq(g.own_seat, 0, "host/local seat 0")
	assert_eq(g.my_color_idx, 0, "default color index 0")