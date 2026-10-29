extends Control

## The "Noir Deck": poker playing cards drawn entirely in code (no textures).
## Cream stock with a brass hairline frame, real pip layouts (2-10), framed court cards,
## and a midnight back with a brass revolver-drum medallion.

const Eval := preload("res://scripts/poker/poker_eval.gd")
const UIStyle := preload("res://scripts/ui_style.gd")

const STOCK := Color("f1e8d4")
const STOCK_SHADE := Color("e2d6bb")
const STOCK_EDGE := Color("b9ab8c")
const INK := Color("17121c")
const EMBER := Color("b3202f")
const FOUR_GREEN := Color("2f7d4f")
const FOUR_BLUE := Color("2a5fa8")
const BACK_FILL := Color("1d0a14")
const BACK_MID := Color("3a0f1e")
const BACK_DARK := Color("12060c")
const BRASS := Color("c9a45c")
const BRASS_LIGHT := Color("ecd394")

## Pip positions (x, y as fractions of the pip area) for each rank.
const PIPS := {
	2: [[0.5, 0.0], [0.5, 1.0]],
	3: [[0.5, 0.0], [0.5, 0.5], [0.5, 1.0]],
	4: [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]],
	5: [[0.0, 0.0], [1.0, 0.0], [0.5, 0.5], [0.0, 1.0], [1.0, 1.0]],
	6: [[0.0, 0.0], [1.0, 0.0], [0.0, 0.5], [1.0, 0.5], [0.0, 1.0], [1.0, 1.0]],
	7: [[0.0, 0.0], [1.0, 0.0], [0.5, 0.25], [0.0, 0.5], [1.0, 0.5], [0.0, 1.0], [1.0, 1.0]],
	8: [[0.0, 0.0], [1.0, 0.0], [0.5, 0.25], [0.0, 0.5], [1.0, 0.5], [0.5, 0.75], [0.0, 1.0], [1.0, 1.0]],
	9: [[0.0, 0.0], [1.0, 0.0], [0.0, 0.333], [1.0, 0.333], [0.5, 0.5], [0.0, 0.667], [1.0, 0.667], [0.0, 1.0], [1.0, 1.0]],
	10: [[0.0, 0.0], [1.0, 0.0], [0.5, 0.167], [0.0, 0.333], [1.0, 0.333], [0.0, 0.667], [1.0, 0.667], [0.5, 0.833], [0.0, 1.0], [1.0, 1.0]],
}

## Four-colour deck (clubs green, diamonds blue) is easier for beginners to read.
static var four_color: bool = false

var card: int = -1
var face_up: bool = false
var lit: bool = false          # gold outline (part of the winning hand)
var dimmed: bool = false       # faded (not part of the winning hand)
var mini: bool = false         # tiny sidebar card: big rank + pip only
var flat3d: bool = false       # rendered into a 3D card texture: no drop shadow

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func show_card(c: int, up: bool) -> void:
	card = c
	face_up = up and c >= 0
	queue_redraw()

func set_lit(on: bool) -> void:
	lit = on
	queue_redraw()

func set_dimmed(on: bool) -> void:
	dimmed = on
	modulate = Color(0.55, 0.55, 0.6, 0.9) if on else Color.WHITE

static func suit_color(suit: int) -> Color:
	if four_color:
		match suit:
			0: return FOUR_GREEN
			1: return FOUR_BLUE
			2: return EMBER
			_: return INK
	return EMBER if suit == 1 or suit == 2 else INK

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var radius := int(minf(size.x, size.y) * 0.08)
	if not flat3d:
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0.35)
		sh.set_corner_radius_all(radius)
		draw_style_box(sh, Rect2(Vector2(1.5, 2.5), size))
	if not face_up:
		_draw_back(r, radius)
	else:
		_draw_face(r, radius)
	if lit:
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(0, 0, 0, 0)
		ring.border_color = Color("ffd877")
		ring.set_border_width_all(maxi(2, int(size.x * 0.05)))
		ring.set_corner_radius_all(radius)
		ring.shadow_color = Color(1.0, 0.82, 0.35, 0.55)
		ring.shadow_size = 8
		draw_style_box(ring, r)

# ── Back ──────────────────────────────────────────────────────────────

func _draw_back(r: Rect2, radius: int) -> void:
	var edge := maxf(2.0, size.x * 0.045)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BACK_FILL
	sb.border_color = STOCK
	sb.set_border_width_all(int(edge))
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)
	var frame := r.grow(-size.x * 0.085)
	# Two-tone field: a lighter diamond lattice inside a brass double frame.
	var field := StyleBoxFlat.new()
	field.bg_color = BACK_MID
	field.set_corner_radius_all(maxi(2, radius - 2))
	draw_style_box(field, frame)
	var step := size.x * 0.17
	var col := Color(BRASS, 0.22)
	var x := frame.position.x - frame.size.y
	while x < frame.end.x:
		var ca := _clip_line(Vector2(x, frame.end.y), Vector2(x + frame.size.y, frame.position.y), frame)
		if ca.size() == 2:
			draw_line(ca[0], ca[1], col, 1.0)
		var cb := _clip_line(Vector2(x, frame.position.y), Vector2(x + frame.size.y, frame.end.y), frame)
		if cb.size() == 2:
			draw_line(cb[0], cb[1], col, 1.0)
		x += step
	draw_rect(frame, Color(BRASS, 0.9), false, maxf(1.5, size.x * 0.012))
	draw_rect(frame.grow(-size.x * 0.03), Color(BRASS, 0.45), false, 1.0)
	var c := r.get_center()
	var m := minf(size.x, size.y)
	# Starburst behind the drum
	for i in range(16):
		var a := TAU * float(i) / 16.0
		draw_line(c + Vector2(cos(a), sin(a)) * m * 0.3, c + Vector2(cos(a), sin(a)) * m * (0.38 if i % 2 == 0 else 0.34), Color(BRASS, 0.6), 1.5)
	_draw_drum(c, m * 0.27)
	# Corner mini drums
	for corner in [Vector2(0.17, 0.12), Vector2(0.83, 0.12), Vector2(0.17, 0.88), Vector2(0.83, 0.88)]:
		_draw_drum(Vector2(size.x * corner.x, size.y * corner.y), m * 0.055)

func _draw_drum(c: Vector2, rad: float) -> void:
	draw_circle(c, rad, BACK_DARK)
	draw_arc(c, rad, 0, TAU, 40, BRASS, maxf(1.5, rad * 0.1))
	draw_arc(c, rad * 0.86, 0, TAU, 40, Color(BRASS, 0.5), 1.0)
	draw_circle(c, rad * 0.16, BRASS)
	for i in range(6):
		var ang := TAU * float(i) / 6.0 - PI / 2.0
		var p := c + Vector2(cos(ang), sin(ang)) * rad * 0.58
		draw_circle(p, rad * 0.19, Color("050204"))
		draw_arc(p, rad * 0.19, 0, TAU, 12, BRASS_LIGHT, maxf(1.0, rad * 0.05))

## Clip a segment to a rect (Liang-Barsky); returns [] when fully outside.
func _clip_line(a: Vector2, b: Vector2, rc: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p: Array = [-d.x, d.x, -d.y, d.y]
	var q: Array = [a.x - rc.position.x, rc.end.x - a.x, a.y - rc.position.y, rc.end.y - a.y]
	for i in range(4):
		var pi_: float = p[i]
		var qi: float = q[i]
		if absf(pi_) < 0.00001:
			if qi < 0.0:
				return []
		else:
			var t := qi / pi_
			if pi_ < 0.0:
				if t > t1:
					return []
				t0 = maxf(t0, t)
			else:
				if t < t0:
					return []
				t1 = minf(t1, t)
	return [a + d * t0, a + d * t1]

# ── Face ──────────────────────────────────────────────────────────────

## Faint paper fibres (deterministic per card).
func _draw_grain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = card * 131 + 7
	for i in range(150):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var len_ := rng.randf_range(2.0, 7.0) * (size.x / 256.0)
		var dark: bool = rng.randf() < 0.6
		draw_line(p, p + Vector2(len_, rng.randf_range(-1.0, 1.0)), Color(0.35, 0.28, 0.2, 0.05) if dark else Color(1, 1, 1, 0.07), 1.0)

## Brass double frame with small diamonds in the corners.
func _draw_foil_frame(r: Rect2) -> void:
	var inset := r.grow(-size.x * 0.05)
	draw_rect(inset, Color(BRASS, 0.85), false, maxf(1.5, size.x * 0.008))
	draw_rect(inset.grow(-size.x * 0.018), Color(BRASS, 0.35), false, 1.0)
	for corner in [inset.position, Vector2(inset.end.x, inset.position.y), Vector2(inset.position.x, inset.end.y), inset.end]:
		var d := size.x * 0.018
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -d), corner + Vector2(d, 0), corner + Vector2(0, d), corner + Vector2(-d, 0)]), Color(BRASS_LIGHT, 0.95))

func _draw_face(r: Rect2, radius: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = STOCK
	sb.border_color = STOCK_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)
	var rank: int = Eval.rank_of(card)
	var suit: int = Eval.suit_of(card)
	var col := suit_color(suit)
	var label: String = Eval.RANK_CHARS[rank - 2]
	var font := UIStyle.title_font()
	if mini:
		var mfs := int(size.y * 0.4)
		draw_string(font, Vector2(0, size.y * 0.45), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, mfs, col)
		draw_suit(self, suit, Vector2(size.x * 0.5, size.y * 0.74), size.y * 0.3, col)
		return
	# Warm shade toward the bottom, paper grain, foil frame.
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(STOCK_SHADE, 0.5)
	shade.corner_radius_bottom_left = radius
	shade.corner_radius_bottom_right = radius
	draw_style_box(shade, Rect2(0, size.y * 0.72, size.x, size.y * 0.28))
	_draw_grain()
	_draw_foil_frame(r)
	# Big, bold corner indices
	var fs := int(size.y * 0.2)
	if label.length() > 1:
		fs = int(size.y * 0.16)
	var padx := size.x * 0.085
	var pady := size.y * 0.042
	_draw_index(font, label, suit, col, fs, Vector2(padx, pady), false)
	_draw_index(font, label, suit, col, fs, Vector2(size.x - padx, size.y - pady), true)
	var area := Rect2(size.x * 0.365, size.y * 0.18, size.x * 0.27, size.y * 0.64)
	if rank == 14:
		_draw_ace(suit, col)
	elif rank >= 11:
		_draw_court(rank, suit, col)
	else:
		var ps: float = size.x * (0.2 if rank <= 6 else 0.17)
		for pp in PIPS[rank]:
			var pos := Vector2(area.position.x + float(pp[0]) * area.size.x, area.position.y + float(pp[1]) * area.size.y)
			if float(pp[1]) > 0.5:
				draw_set_transform(pos, PI, Vector2.ONE)
				draw_suit(self, suit, Vector2.ZERO, ps, col)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_suit(self, suit, pos, ps, col)
	# Gloss streak
	draw_colored_polygon(PackedVector2Array([Vector2(radius, 1), Vector2(size.x * 0.55, 1), Vector2(1, size.y * 0.3), Vector2(1, radius)]), Color(1, 1, 1, 0.08))

func _draw_index(font: Font, label: String, suit: int, col: Color, fs: int, at: Vector2, flipped: bool) -> void:
	draw_set_transform(at, PI if flipped else 0.0, Vector2.ONE)
	# Faux bold: the rank is drawn twice, a hair apart.
	draw_string(font, Vector2(0, fs * 0.85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(font, Vector2(fs * 0.035, fs * 0.85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_suit(self, suit, Vector2(fs * 0.4, fs * 1.58), fs * 0.74, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_court(rank: int, suit: int, col: Color) -> void:
	var frame := Rect2(size.x * 0.27, size.y * 0.15, size.x * 0.46, size.y * 0.7)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(col, 0.07)
	panel.border_color = Color(BRASS, 0.9)
	panel.set_border_width_all(maxi(1, int(size.x * 0.012)))
	panel.set_corner_radius_all(int(size.x * 0.03))
	draw_style_box(panel, frame)
	# Diagonal banner behind the figure
	draw_colored_polygon(PackedVector2Array([frame.position, frame.position + Vector2(frame.size.x * 0.55, 0), frame.position + Vector2(0, frame.size.y * 0.55)]), Color(col, 0.08))
	var half := Rect2(frame.position, Vector2(frame.size.x, frame.size.y * 0.5))
	_draw_court_half(rank, suit, col, half)
	# Mirrored copy for the bottom half, like a real court card.
	draw_set_transform(frame.get_center() * 2.0, PI, Vector2.ONE)
	_draw_court_half(rank, suit, col, half)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(Vector2(frame.position.x, frame.get_center().y), Vector2(frame.end.x, frame.get_center().y), Color(BRASS, 0.9), maxf(1.5, size.x * 0.012))

## One blocky court figure (matches the Kenney giants): robe, head, hair, crown / cap / tiara and a prop.
func _draw_court_half(rank: int, suit: int, col: Color, h: Rect2) -> void:
	var W := h.size.x
	var H := h.size.y
	var cx := h.position.x + W * 0.5
	var floor_y := h.end.y
	var skin := Color("e2b08a")
	var skin_dark := Color("b8825e")
	var hair := Color("3d2a22")
	if rank == 12:
		hair = Color("d8b25a")
	elif rank == 13:
		hair = Color("8d8a86")
	var robe := col.lightened(0.05) if col != INK else Color("2b2433")
	if suit == 0 and four_color:
		robe = FOUR_GREEN
	elif suit == 1 and four_color:
		robe = FOUR_BLUE
	var neck_y := floor_y - H * 0.34
	# Robe with gold trim
	draw_colored_polygon(PackedVector2Array([Vector2(cx - W * 0.42, floor_y), Vector2(cx - W * 0.2, neck_y), Vector2(cx + W * 0.2, neck_y), Vector2(cx + W * 0.42, floor_y)]), robe)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - W * 0.05, neck_y), Vector2(cx + W * 0.05, neck_y), Vector2(cx + W * 0.12, floor_y), Vector2(cx - W * 0.12, floor_y)]), Color(BRASS, 0.95))
	draw_line(Vector2(cx - W * 0.42, floor_y), Vector2(cx - W * 0.2, neck_y), Color(BRASS, 0.9), maxf(1.5, size.x * 0.012))
	draw_line(Vector2(cx + W * 0.42, floor_y), Vector2(cx + W * 0.2, neck_y), Color(BRASS, 0.9), maxf(1.5, size.x * 0.012))
	# Head
	var hw := W * 0.3
	var hh := H * 0.3
	var head := Rect2(cx - hw * 0.5, neck_y - hh, hw, hh)
	# Hair behind the head (long for the queen)
	if rank == 12:
		draw_rect(Rect2(head.position.x - hw * 0.18, head.position.y - hh * 0.08, hw * 1.36, hh * 1.5), hair)
	draw_rect(head, skin)
	draw_rect(Rect2(head.position.x, head.end.y - hh * 0.12, hw, hh * 0.12), skin_dark)
	# Hair / hat on top
	draw_rect(Rect2(head.position.x - hw * 0.04, head.position.y - hh * 0.06, hw * 1.08, hh * 0.28), hair)
	# Face
	var ey := head.position.y + hh * 0.42
	draw_rect(Rect2(head.position.x + hw * 0.2, ey, hw * 0.14, hh * 0.14), INK)
	draw_rect(Rect2(head.end.x - hw * 0.34, ey, hw * 0.14, hh * 0.14), INK)
	draw_rect(Rect2(cx - hw * 0.06, ey + hh * 0.2, hw * 0.12, hh * 0.18), skin_dark)
	draw_rect(Rect2(cx - hw * 0.16, head.position.y + hh * 0.78, hw * 0.32, hh * 0.07), Color("7a3a34"))
	var gold := Color("e3b94d")
	if rank == 13:
		# Beard + crown
		draw_rect(Rect2(head.position.x + hw * 0.05, head.position.y + hh * 0.7, hw * 0.9, hh * 0.38), hair)
		var by := head.position.y - hh * 0.06
		draw_colored_polygon(PackedVector2Array([Vector2(cx - hw * 0.55, by), Vector2(cx - hw * 0.55, by - hh * 0.55), Vector2(cx - hw * 0.28, by - hh * 0.28), Vector2(cx, by - hh * 0.7), Vector2(cx + hw * 0.28, by - hh * 0.28), Vector2(cx + hw * 0.55, by - hh * 0.55), Vector2(cx + hw * 0.55, by)]), gold)
		draw_circle(Vector2(cx, by - hh * 0.62), hw * 0.07, EMBER)
		# Sword
		draw_line(Vector2(cx + W * 0.36, floor_y), Vector2(cx + W * 0.36, floor_y - H * 0.72), Color("c8ccd2"), maxf(2.0, size.x * 0.018))
		draw_line(Vector2(cx + W * 0.29, floor_y - H * 0.2), Vector2(cx + W * 0.43, floor_y - H * 0.2), gold, maxf(2.0, size.x * 0.02))
	elif rank == 12:
		# Tiara + flower
		var ty := head.position.y - hh * 0.08
		draw_colored_polygon(PackedVector2Array([Vector2(cx - hw * 0.42, ty), Vector2(cx - hw * 0.3, ty - hh * 0.32), Vector2(cx - hw * 0.1, ty - hh * 0.08), Vector2(cx, ty - hh * 0.4), Vector2(cx + hw * 0.1, ty - hh * 0.08), Vector2(cx + hw * 0.3, ty - hh * 0.32), Vector2(cx + hw * 0.42, ty)]), gold)
		draw_circle(Vector2(cx + W * 0.34, floor_y - H * 0.28), W * 0.07, EMBER)
		draw_circle(Vector2(cx + W * 0.34, floor_y - H * 0.28), W * 0.03, gold)
		draw_line(Vector2(cx + W * 0.34, floor_y - H * 0.21), Vector2(cx + W * 0.34, floor_y), Color("2f7d4f"), maxf(1.5, size.x * 0.012))
	else:
		# Jack: cap in the suit colour with a feather, and a halberd
		var cy := head.position.y - hh * 0.04
		draw_colored_polygon(PackedVector2Array([Vector2(cx - hw * 0.56, cy + hh * 0.2), Vector2(cx - hw * 0.4, cy - hh * 0.36), Vector2(cx + hw * 0.4, cy - hh * 0.36), Vector2(cx + hw * 0.56, cy + hh * 0.2)]), robe)
		draw_line(Vector2(cx + hw * 0.2, cy - hh * 0.3), Vector2(cx + hw * 0.7, cy - hh * 0.8), gold, maxf(2.0, size.x * 0.016))
		draw_line(Vector2(cx + W * 0.36, floor_y), Vector2(cx + W * 0.36, floor_y - H * 0.7), Color("a07f4d"), maxf(2.0, size.x * 0.016))
		draw_colored_polygon(PackedVector2Array([Vector2(cx + W * 0.36, floor_y - H * 0.78), Vector2(cx + W * 0.31, floor_y - H * 0.6), Vector2(cx + W * 0.41, floor_y - H * 0.6)]), Color("c8ccd2"))
	# Little suit pips either side of the shoulders
	draw_suit(self, suit, Vector2(h.position.x + W * 0.12, h.position.y + H * 0.2), W * 0.15, suit_color(suit))

func _draw_ace(suit: int, col: Color) -> void:
	var c := size * 0.5
	var m := minf(size.x, size.y)
	# Starburst + drum ring (the Chamber Draw crest), bigger and richer on the Ace of spades
	var spade := suit == 3
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var r0 := m * (0.34 if spade else 0.3)
		var r1 := m * (0.44 if i % 2 == 0 else 0.39) if spade else m * (0.37 if i % 2 == 0 else 0.33)
		draw_line(c + Vector2(cos(a), sin(a)) * r0, c + Vector2(cos(a), sin(a)) * r1, Color(BRASS, 0.55), 1.5)
	draw_arc(c, m * 0.33, 0, TAU, 56, Color(BRASS, 0.85), maxf(2.0, size.x * 0.014))
	if spade:
		for i in range(6):
			var a2 := TAU * float(i) / 6.0 - PI / 2.0
			draw_circle(c + Vector2(cos(a2), sin(a2)) * m * 0.3, m * 0.025, Color(BRASS, 0.9))
	draw_suit(self, suit, c + Vector2(0, m * 0.015), m * (0.52 if spade else 0.44), col)

## Draws one suit pip centred on `c`, roughly `s` pixels tall.
static func draw_suit(ci: CanvasItem, suit: int, c: Vector2, s: float, col: Color) -> void:
	match suit:
		1:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.6), c + Vector2(s * 0.42, 0), c + Vector2(0, s * 0.6), c + Vector2(-s * 0.42, 0)]), col)
		2:
			ci.draw_colored_polygon(_heart(c + Vector2(0, s * 0.04), s, false), col)
		3:
			ci.draw_colored_polygon(_heart(c + Vector2(0, -s * 0.1), s * 0.92, true), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.1), c + Vector2(s * 0.2, s * 0.62), c + Vector2(-s * 0.2, s * 0.62)]), col)
		_:
			var rr := s * 0.2
			ci.draw_circle(c + Vector2(0, -s * 0.22), rr, col)
			ci.draw_circle(c + Vector2(-s * 0.23, s * 0.1), rr, col)
			ci.draw_circle(c + Vector2(s * 0.23, s * 0.1), rr, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.12), c + Vector2(s * 0.12, s * 0.62), c + Vector2(-s * 0.12, s * 0.62)]), col)

static func _heart(c: Vector2, s: float, flip: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var k := s / 34.0
	for i in range(0, 40):
		var t := TAU * float(i) / 40.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		if flip:
			y = -y
		pts.append(c + Vector2(x, y + (2.0 if not flip else -2.0)) * k)
	return pts
