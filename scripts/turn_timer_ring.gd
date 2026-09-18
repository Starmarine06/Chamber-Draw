extends Control
## Circular turn timer: draws a ring that depletes clockwise as the clock runs.
## Color matches the current player's seat color; blends toward red when time
## is critical (< 25%).

var _pct: float = 1.0
var _color: Color = Color(0.2, 0.8, 0.3)

## Set the remaining fraction (0..1); 1 = full, 0 = empty.
func set_pct(p: float) -> void:
	_pct = clampf(p, 0.0, 1.0)
	queue_redraw()

func get_pct() -> float:
	return _pct

## Set the player's color for this turn's ring.
func set_color(c: Color) -> void:
	_color = c
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius: float = min(size.x, size.y) * 0.5 - 5.0
	if radius <= 1.0:
		return
	# Faint full-track ring in the player's color.
	draw_arc(center, radius, 0.0, TAU, 48, Color(_color.r, _color.g, _color.b, 0.12), 5.0, true)
	# Remaining time, starting at 12 o'clock and rotating clockwise.
	draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * _pct, 48, _color_for_pct(_pct), 5.0, true)

func _color_for_pct(p: float) -> Color:
	if p > 0.25:
		return _color
	# Blend from player color → red when under 25% for urgency.
	return _color.lerp(Color(0.9, 0.2, 0.2), 1.0 - p / 0.25)