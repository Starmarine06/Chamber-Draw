@tool
extends McpTestSuite

func suite_name() -> String:
	return "turn_timer_ring"


func _make_ring() -> Variant:
	# new() off-tree avoids _ready side effects; set_pct/set_color only
	# queue_redraw(), which is a safe no-op on a node that is not in the tree.
	return load("res://scripts/turn_timer_ring.gd").new()


func test_set_pct_clamps_high() -> void:
	var ring: Variant = _make_ring()
	ring.set_pct(1.5)
	assert_eq(ring.get_pct(), 1.0, "clamped to 1.0")


func test_set_pct_clamps_low() -> void:
	var ring: Variant = _make_ring()
	ring.set_pct(-0.5)
	assert_eq(ring.get_pct(), 0.0, "clamped to 0.0")


func test_set_pct_preserves_valid_value() -> void:
	var ring: Variant = _make_ring()
	ring.set_pct(0.6)
	assert_eq(ring.get_pct(), 0.6, "mid values pass through")


func test_set_color_stores_player_color() -> void:
	var ring: Variant = _make_ring()
	var c := Color(0.0, 0.0, 1.0)
	ring.set_color(c)
	assert_eq(ring._color, c, "color stored for the ring")


func test_color_for_pct_above_critical_is_player_color() -> void:
	var ring: Variant = _make_ring()
	ring.set_color(Color(0.0, 0.0, 1.0))
	assert_eq(ring._color_for_pct(0.5), ring._color, "healthy time keeps the seat color")
	assert_eq(ring._color_for_pct(0.26), ring._color, "just above 25% is still the seat color")


func test_color_for_pct_at_critical_boundary_is_player_color() -> void:
	var ring: Variant = _make_ring()
	ring.set_color(Color(0.0, 0.0, 1.0))
	# > 0.25 gates the blend, so exactly 25% evaluates to the player color.
	assert_eq(ring._color_for_pct(0.25), ring._color, "exactly 25% is still the seat color")


func test_color_for_pct_empty_is_pure_red() -> void:
	var ring: Variant = _make_ring()
	ring.set_color(Color(0.0, 0.0, 1.0))
	# Exact == on the lerp result is float-noise-prone; compare approximately.
	var target := Color(0.9, 0.2, 0.2)
	var got: Color = ring._color_for_pct(0.0)
	assert_true(got.is_equal_approx(target), "0%% is the emergency red: got %s" % [str(got)])


func test_color_for_pct_partial_blend_between_color_and_red() -> void:
	var ring: Variant = _make_ring()
	ring.set_color(Color(0.0, 0.0, 1.0))
	# p := 0.125 -> blend weight 1 - 0.125 / 0.25 = 0.5
	var mid: Color = ring._color_for_pct(0.125)
	assert_true(mid.r > 0.0 and mid.b < 1.0, "mid critical blend sits between seat color and red")