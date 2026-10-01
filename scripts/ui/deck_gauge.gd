extends Control

## HUD badge pinned above a 3D draw pile: the deck's name, its card count and
## the CHAMBER ODDS (chance the next card from this deck is a Bomb), shown as a
## big risk-colored percentage plus a mini revolver cylinder whose loaded
## chambers track the risk. Replaces the old 3D text label that got buried
## behind the deck slab / characters. Purely informational (ignores the mouse).

const UIStyle := preload("res://scripts/ui_style.gd")
const W := 176.0
const H := 64.0

var deck_name := "DECK"
var count := 0
var pct := 0
var active := false          # glows while the local player may draw from it
var _flash := 0.0
var _t := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5

func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 1.6, 0.0)
	if active or _flash > 0.0:
		queue_redraw()

## Risk color: felt green (safe) → brass → ember → blood (deadly).
static func risk_color(p: int) -> Color:
	if p <= 0:
		return Color(0.55, 0.8, 0.62)
	if p < 5:
		return Color(0.45, 0.82, 0.55)
	if p < 10:
		return UIStyle.BRASS_LIGHT
	if p < 20:
		return Color(1.0, 0.58, 0.22)
	return UIStyle.BLOOD_LIGHT

## Loaded chambers (0..6) shown on the mini cylinder for a given risk.
static func loaded_chambers(p: int) -> int:
	if p <= 0:
		return 0
	return clampi(ceili(float(p) / 100.0 * 6.0 * 2.0), 1, 6)  # ×2: small odds still read

func set_data(n: String, c: int, p: int) -> void:
	var changed := p != pct and is_inside_tree()
	deck_name = n
	count = c
	pct = p
	if changed:
		_flash = 1.0
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.08)
		tw.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

func set_active(on: bool) -> void:
	if on != active:
		active = on
		queue_redraw()

func _draw() -> void:
	var rc := risk_color(pct)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UIStyle.INK, 0.86)
	box.set_corner_radius_all(12)
	box.border_color = rc.lerp(UIStyle.BRASS_DIM, 0.55) if not active else rc
	box.set_border_width_all(2)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 8
	if active:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		box.shadow_color = Color(rc, 0.25 + 0.3 * pulse)
		box.shadow_size = int(10 + 6 * pulse)
	if _flash > 0.0:
		box.bg_color = box.bg_color.lerp(Color(rc, 0.9), _flash * 0.35)
	draw_style_box(box, Rect2(Vector2.ZERO, size))

	# Mini cylinder (left).
	var c := Vector2(32, H * 0.5)
	var r := 22.0
	draw_circle(c, r, Color("6e5528"))
	draw_circle(c, r * 0.9, UIStyle.BRASS)
	var loaded := loaded_chambers(pct)
	for i in range(6):
		var a := -PI / 2.0 + TAU * float(i) / 6.0
		var hp := c + Vector2(cos(a), sin(a)) * r * 0.55
		var live := i < loaded
		draw_circle(hp, r * 0.2, UIStyle.BLOOD_LIGHT if live else UIStyle.INK)  # loaded = a round
		if live:
			draw_circle(hp, r * 0.09, Color(1, 1, 1, 0.5))
	draw_circle(c, r * 0.14, Color("6e5528"))

	# Text (right).
	var font := UIStyle.title_font()
	var body := UIStyle.body_font()
	var x := 62.0
	draw_string(body, Vector2(x, 20), deck_name, HORIZONTAL_ALIGNMENT_LEFT, W - x - 8, 13, UIStyle.MUTED)
	# Number in the title face; "%" in a plain face (Kenney's % reads like an X).
	var num := str(pct)
	draw_string(font, Vector2(x, 45), num, HORIZONTAL_ALIGNMENT_LEFT, 70, 26, rc)
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(ThemeDB.fallback_font, Vector2(x + nw + 2, 44), "%", HORIZONTAL_ALIGNMENT_LEFT, 30, 22, rc)
	draw_string(body, Vector2(x + nw + 22, 44), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, 44, 11, Color(rc, 0.8))
	draw_string(body, Vector2(x, 58), "%d cards" % count, HORIZONTAL_ALIGNMENT_LEFT, W - x - 8, 11, UIStyle.MUTED)
