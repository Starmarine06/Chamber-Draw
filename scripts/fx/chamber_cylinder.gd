extends Control

## A revolver cylinder drawn procedurally (brass body, six chambers, a hammer
## marker at 12 o'clock). `spin()` rotates it with a decelerating ease and
## emits `chamber_passed` every time a chamber crosses the hammer (hook the
## click sound to it). `reveal()` paints the fired chamber by result.

signal chamber_passed(index: int)

const BRASS := Color("c9a45c")
const BRASS_LIGHT := Color("ecd394")
const BRASS_DARK := Color("6e5528")
const INK := Color("100c12")
const BLOOD := Color("b3262f")

var angle: float = 0.0:
	set(v):
		var before := chamber_at_hammer(angle)
		angle = v
		var after := chamber_at_hammer(angle)
		if after != before:
			chamber_passed.emit(after)
		queue_redraw()

## 0 = none yet; otherwise ChamberDeck.Result-like tag set by reveal().
var _revealed: StringName = &""
var _glow: float = 0.0:
	set(v):
		_glow = v
		queue_redraw()

## Index (0..5) of the chamber currently under the hammer for a rotation.
static func chamber_at_hammer(a: float) -> int:
	var step := TAU / 6.0
	return posmod(roundi(-a / step), 6)

## Rotation that parks chamber `index` under the hammer after `turns` full
## turns from `from_angle` (always spins forward / clockwise).
static func target_angle(from_angle: float, turns: int, index: int) -> float:
	var step := TAU / 6.0
	var base := from_angle + TAU * float(turns)
	var want := -float(index) * step
	var k := ceilf((base - want) / TAU)
	return want + k * TAU

func spin(turns: int, dur: float, land_index: int = -1) -> Tween:
	var idx := land_index if land_index >= 0 else randi() % 6
	var to := target_angle(angle, turns, idx)
	var tw := create_tween()
	tw.tween_property(self, "angle", to, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return tw

## kind: &"live", &"blank", &"backfire", &"lucky"
func reveal(kind: StringName) -> void:
	_revealed = kind
	_glow = 1.0
	var tw := create_tween()
	tw.tween_property(self, "_glow", 0.35, 0.8)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	# Drop shadow + body.
	draw_circle(c + Vector2(0, 6), r * 1.02, Color(0, 0, 0, 0.45))
	draw_circle(c, r, BRASS_DARK)
	draw_circle(c, r * 0.96, BRASS)
	# Machined rings.
	draw_arc(c, r * 0.96, 0, TAU, 64, BRASS_LIGHT, 2.0, true)
	draw_arc(c, r * 0.8, 0, TAU, 64, Color(BRASS_DARK, 0.6), 1.5, true)
	# Flutes between chambers.
	for i in range(6):
		var a := angle + TAU * (float(i) + 0.5) / 6.0 - PI / 2.0
		var fp := c + Vector2(cos(a), sin(a)) * r * 0.93
		draw_circle(fp, r * 0.11, BRASS_DARK)
	# Chambers.
	var hammer_idx := chamber_at_hammer(angle)
	for i in range(6):
		var a := angle + TAU * float(i) / 6.0 - PI / 2.0
		var hp := c + Vector2(cos(a), sin(a)) * r * 0.56
		var hr := r * 0.2
		draw_circle(hp, hr * 1.12, BRASS_DARK)
		var fill := INK
		if _revealed != &"" and i == hammer_idx:
			match _revealed:
				&"live": fill = BLOOD.lerp(Color(1, 0.8, 0.4), _glow * 0.5)
				&"backfire": fill = Color("d0741f")
				&"lucky": fill = BRASS_LIGHT
				_: fill = Color(0.18, 0.16, 0.2)
		draw_circle(hp, hr, fill)
		draw_arc(hp, hr, 0, TAU, 20, Color(0, 0, 0, 0.6), 1.5, true)
		if _revealed == &"live" and i == hammer_idx:
			# Spent primer ring.
			draw_circle(hp, hr * 0.45, BRASS_LIGHT)
			draw_circle(hp, hr * 0.18, BRASS_DARK)
	# Center pin.
	draw_circle(c, r * 0.14, BRASS_DARK)
	draw_circle(c, r * 0.07, INK)
	# Hammer / firing marker at 12 o'clock.
	var top := c + Vector2(0, -r * 1.08)
	var tri := PackedVector2Array([top + Vector2(-r * 0.12, -r * 0.14), top + Vector2(r * 0.12, -r * 0.14), top + Vector2(0, r * 0.06)])
	var marker := BLOOD if _revealed == &"" else BLOOD.lerp(Color(1, 0.9, 0.6), _glow)
	draw_colored_polygon(tri, marker)
	if _glow > 0.0 and _revealed != &"":
		var gcol := Color(1, 0.6, 0.2, 0.35 * _glow) if _revealed in [&"live", &"backfire"] else Color(1, 0.9, 0.5, 0.3 * _glow)
		draw_circle(c + Vector2(0, -r * 0.56), r * 0.45 * (1.0 + _glow * 0.3), gcol)
