extends Control
class_name CardNode

## A playable card, drawn procedurally in the "noir casino" style:
## cream card stock with rounded corners, a muted suit panel, a tilted cream
## oval carrying the number/icon, and mirrored corner indices. Backs show a
## revolver-cylinder emblem on a blood-red lattice.
##
## States: playable (pulsing brass glow), hover (lift + scale), selected,
## dimmed, and an invalid-play shake. The hand layout drives position through
## `place()` so cards glide instead of snapping.

signal card_clicked(card_node: CardNode)

var card_data: Card = null
var face_up: bool = true
var playable: bool = false
var selected: bool = false
var card_width: float = 80.0
var card_height: float = 120.0
## Optional pre-made art for this face (null = procedural). Hook for the
## reworked card art; see AGENTS.md "Custom card art round".
var face_texture: Texture2D = null

## Resting layout position/rotation (set by the hand layout via place()).
var rest_position: Vector2 = Vector2.ZERO
var _hovering: bool = false
var _glow_t: float = 0.0
var _hover_tw: Tween
var _place_tw: Tween

const FONT := preload("res://assets/imported_assets/kenney_ui-pack/Font/Kenney Future.ttf")
const FONT_NARROW := preload("res://assets/imported_assets/kenney_ui-pack/Font/Kenney Future Narrow.ttf")

# ── Noir palette for card suits ──
const INK := Color("141016")
const CARD_STOCK := Color("17131b")
const CREAM := Color("efe4cc")
const BRASS := Color("c9a45c")
const BRASS_LIGHT := Color("ecd394")
const BLOOD := Color("8e1622")
const SUIT_COLORS := {
	Card.CardColor.RED: Color("b3262f"),
	Card.CardColor.BLUE: Color("2d5a9e"),
	Card.CardColor.GREEN: Color("2e7d4f"),
	Card.CardColor.YELLOW: Color("cf9f22"),
	Card.CardColor.ORANGE: Color("d0741f"),
	Card.CardColor.PURPLE: Color("6b3a93"),
}

# ── Kenney board game icons (white silhouettes, tinted at draw time) ──
const _ICON_DIR := "res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/"
const _ICONS := {
	"skip": preload(_ICON_DIR + "pawn_skip.png"),
	"reverse": preload(_ICON_DIR + "arrow_counterclockwise.png"),
	"draw_two": preload(_ICON_DIR + "tag_2.png"),
	"draw_four": preload(_ICON_DIR + "tag_4.png"),
	"draw_ten": preload(_ICON_DIR + "tag_10.png"),
	"swap_hands": preload(_ICON_DIR + "cards_shift.png"),
	"peek": preload(_ICON_DIR + "cards_seek_top.png"),
	"extra_life": preload(_ICON_DIR + "suit_hearts.png"),
	"choose_deck": preload(_ICON_DIR + "card.png"),
	"rotate_decks": preload(_ICON_DIR + "arrow_rotate.png"),
	"wild_color": preload(_ICON_DIR + "cards_fan.png"),
	"wild_sabotage": preload(_ICON_DIR + "cards_skull.png"),
	"bomb": preload(_ICON_DIR + "skull.png"),
	"diffuse": preload(_ICON_DIR + "shield.png"),
	"respawn": preload(_ICON_DIR + "suit_hearts.png"),
	"default": preload(_ICON_DIR + "card_outline.png"),
}

const ACTION_LABELS := {
	"skip": "SKIP", "reverse": "REVERSE", "draw_two": "+2", "draw_four": "+4",
	"draw_ten": "+10", "swap_hands": "SWAP", "peek": "PEEK", "extra_life": "LIFE",
	"choose_deck": "DECK", "rotate_decks": "ROTATE",
}
const ACTION_CORNERS := {
	"skip": "S", "reverse": "R", "draw_two": "+2", "draw_four": "+4",
	"draw_ten": "+10", "swap_hands": "SW", "peek": "PK", "extra_life": "L",
	"choose_deck": "D", "rotate_decks": "RT",
}

func setup(data: Card, face: bool = true, w: float = 80.0, h: float = 120.0) -> CardNode:
	card_data = data
	face_up = face
	card_width = w
	card_height = h
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	selected = false
	_hovering = false
	scale = Vector2.ONE
	modulate = Color.WHITE
	self_modulate = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = data.display_name if data else ""
	queue_redraw()
	return self

func _ready() -> void:
	rest_position = position
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	gui_input.connect(_on_input)
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	_glow_t += delta
	queue_redraw()

# ── State API ─────────────────────────────────────────────────────────

func set_playable(val: bool) -> void:
	playable = val
	set_process(val and face_up)
	queue_redraw()

func set_selected(val: bool) -> void:
	selected = val
	_apply_hover_pose()
	queue_redraw()

## Greys a card that can't be played right now (still readable).
func set_dimmed(val: bool) -> void:
	self_modulate = Color(0.6, 0.58, 0.62) if val else Color.WHITE

## Moves the card to its resting layout slot; animated glides when `dur` > 0.
func place(pos: Vector2, rot_deg: float, dur: float = 0.0) -> void:
	rest_position = pos
	if _place_tw and _place_tw.is_valid():
		_place_tw.kill()
	var target := pos + Vector2(0, _lift_amount())
	if dur <= 0.0 or not is_inside_tree():
		position = target
		rotation_degrees = rot_deg
		return
	_place_tw = create_tween().set_parallel()
	_place_tw.tween_property(self, "position", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_place_tw.tween_property(self, "rotation_degrees", rot_deg, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Quick horizontal wiggle for a rejected play.
func shake_invalid() -> void:
	if not is_inside_tree():
		return
	var x0 := rest_position.x
	var tw := create_tween()
	for k: float in [7.0, -6.0, 4.0, -2.0, 0.0]:
		tw.tween_property(self, "position:x", x0 + k, 0.04)

func update_face(face: bool) -> void:
	face_up = face
	set_process(playable and face_up)
	queue_redraw()

# ── Hover / input ─────────────────────────────────────────────────────

func _on_hover() -> void:
	if not face_up:
		return
	_hovering = true
	z_index = 20
	_apply_hover_pose()
	if playable:
		var am := get_node_or_null("/root/AudioManager")
		if am:
			am.play(&"hover")

func _on_unhover() -> void:
	_hovering = false
	z_index = 0
	_apply_hover_pose()

func _lift_amount() -> float:
	if selected:
		return -18.0
	if _hovering:
		return -16.0 if playable else -6.0
	return 0.0

func _apply_hover_pose() -> void:
	if not is_inside_tree():
		return
	if _hover_tw and _hover_tw.is_valid():
		_hover_tw.kill()
	var s := 1.1 if (_hovering and playable) or selected else (1.03 if _hovering else 1.0)
	_hover_tw = create_tween().set_parallel()
	_hover_tw.tween_property(self, "position:y", rest_position.y + _lift_amount(), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tw.tween_property(self, "scale", Vector2(s, s), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if face_up:
			card_clicked.emit(self)

# ── Drawing ───────────────────────────────────────────────────────────

func _draw() -> void:
	if card_data == null:
		return
	if face_up:
		_draw_front()
	else:
		_draw_back()

## Radius of the outer card corners.
func _radius() -> float:
	return card_width * 0.1

func _box(fill: Color, radius: float, border: Color = Color(0, 0, 0, 0), border_w: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(int(radius))
	s.corner_detail = 6
	s.anti_aliasing = true
	if border_w > 0.0:
		s.border_color = border
		s.set_border_width_all(int(border_w))
	return s

func _draw_shadow() -> void:
	var sh := _box(Color(0, 0, 0, 0.0), _radius())
	sh.shadow_color = Color(0, 0, 0, 0.45)
	sh.shadow_size = int(maxf(3.0, card_width * 0.06))
	sh.shadow_offset = Vector2(1, 3)
	draw_style_box(sh, Rect2(Vector2.ZERO, size_vec()))

func size_vec() -> Vector2:
	return Vector2(card_width, card_height)

func _suit_color(c: Card) -> Color:
	return SUIT_COLORS.get(c.color, Color("4a4550"))

## Suit color lifted slightly so it reads against the dark card stock.
func _accent(c: Card) -> Color:
	return _suit_color(c).lightened(0.14)

func _draw_front() -> void:
	var c := card_data
	var w := card_width
	var h := card_height
	var r := _radius()
	_draw_shadow()

	if face_texture:
		draw_style_box(_box(INK, r), Rect2(Vector2.ZERO, size_vec()))
		draw_texture_rect(face_texture, Rect2(Vector2(2, 2), size_vec() - Vector2(4, 4)), false)
		_draw_state_rings()
		return

	# Dark casino stock: the suit shows up as a lit accent, not a flat color slab.
	var stock := CARD_STOCK
	var accent := _accent(c)
	var medal := accent.darkened(0.62)
	match c.type:
		Card.CardType.WILD:
			accent = BRASS_LIGHT
			medal = Color("221a10")
		Card.CardType.BOMB:
			stock = Color("1d0a0d")
			accent = Color("e0505a")
			medal = Color("4a0d14")
		Card.CardType.DIFFUSE:
			stock = Color("0e1f19")
			accent = BRASS_LIGHT
			medal = Color("174634")
		Card.CardType.RESPAWN:
			stock = Color("1a1024")
			accent = Color("d9b8ff")
			medal = Color("3e2159")
		Card.CardType.ACTION:
			if c.color == Card.CardColor.NONE:
				# Colorless actions (Draw Ten) are "anytime" cards: all brass.
				accent = BRASS_LIGHT
				medal = Color("2a2230")

	# Card body with a thin brass edge.
	draw_style_box(_box(stock, r, BRASS.darkened(0.15), maxf(1.0, w * 0.014)), Rect2(Vector2.ZERO, size_vec()))
	var inset := w * 0.05
	var pr := Rect2(Vector2(inset, inset), size_vec() - Vector2(inset, inset) * 2.0)
	# Faint pinstripe wallpaper + chamfered art-deco frame.
	_draw_hatch(pr, Color(accent, 0.07))
	_draw_frame(pr, accent)

	var center := size_vec() * 0.5
	var mr := w * 0.3
	match c.type:
		Card.CardType.NUMBER:
			_draw_medallion(center, mr, medal, accent)
			var txt := str(c.number)
			var fs := int(h * 0.34)
			_draw_text_centered(txt, center + Vector2(0, fs * 0.36), fs, CREAM, INK, maxi(2, int(fs * 0.07)))
			_draw_corners(txt, CREAM, int(h * 0.14), true, c, accent)
			if c.number == 6 or c.number == 9:
				# Underline 6/9 so they read unambiguously when upside down.
				draw_line(center + Vector2(-fs * 0.18, fs * 0.46), center + Vector2(fs * 0.18, fs * 0.46), CREAM, maxf(1.5, fs * 0.06))
		Card.CardType.ACTION:
			_draw_medallion(center, mr, medal, accent)
			var id := c.action_id
			if id in ["draw_two", "draw_four", "draw_ten"]:
				var txt: String = ACTION_LABELS.get(id, "?")
				var fs := int(h * (0.24 if id == "draw_ten" else 0.3))
				_draw_text_centered(txt, center + Vector2(0, fs * 0.36), fs, CREAM, INK, maxi(2, int(fs * 0.07)))
			else:
				_draw_icon(id, center, h * 0.28, CREAM)
			_draw_corners(ACTION_CORNERS.get(id, "?"), CREAM, int(h * 0.12), false, c, accent)
			_draw_caption(ACTION_LABELS.get(id, "?"), accent, pr)
		Card.CardType.WILD:
			var sab := c.action_id == "wild_sabotage"
			if sab:
				_draw_medallion(center, mr, BLOOD.darkened(0.3), Color("e0505a"))
				_draw_icon("wild_sabotage", center, h * 0.28, CREAM)
			else:
				_draw_wild_medallion(center, mr)
				_draw_icon("wild_color", center, h * 0.24, CREAM)
			_draw_corners("W", BRASS_LIGHT, int(h * 0.12), false)
			_draw_caption("SABOTAGE" if sab else "WILD", BRASS_LIGHT, pr)
		Card.CardType.BOMB:
			_draw_hatch(pr, Color(BLOOD, 0.35))
			_draw_medallion(center, mr, medal, accent)
			_draw_icon("bomb", center, h * 0.28, CREAM)
			_draw_caption("CHAMBER", accent, pr)
		Card.CardType.DIFFUSE:
			_draw_medallion(center, mr, medal, accent)
			_draw_icon("diffuse", center, h * 0.28, BRASS_LIGHT)
			_draw_caption("DIFFUSE", BRASS_LIGHT, pr)
		Card.CardType.RESPAWN:
			_draw_medallion(center, mr, medal, accent)
			_draw_icon("respawn", center, h * 0.26, Color("f1dcff"))
			_draw_caption("RESPAWN", Color("f1dcff"), pr)
		_:
			_draw_icon("default", center, h * 0.3, CREAM)

	_draw_state_rings()

## Chamfered (cut-corner) hairline frame — art-deco border inside the card edge.
func _draw_frame(pr: Rect2, col: Color) -> void:
	var cc := card_width * 0.07
	var l := pr.position.x
	var t := pr.position.y
	var rt := pr.end.x
	var b := pr.end.y
	var pts := PackedVector2Array([
		Vector2(l + cc, t), Vector2(rt - cc, t), Vector2(rt, t + cc), Vector2(rt, b - cc),
		Vector2(rt - cc, b), Vector2(l + cc, b), Vector2(l, b - cc), Vector2(l, t + cc),
		Vector2(l + cc, t)])
	draw_polyline(pts, Color(col, 0.85), maxf(1.0, card_width * 0.016), true)

## Revolver-cylinder medallion: brass rim, six lit "chambers" in the suit color.
func _draw_medallion(center: Vector2, radius: float, fill: Color, accent: Color) -> void:
	draw_circle(center + Vector2(1, 2), radius, Color(0, 0, 0, 0.4))
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0, TAU, 40, BRASS, maxf(1.2, radius * 0.07), true)
	draw_arc(center, radius * 0.8, 0, TAU, 36, Color(accent, 0.45), 1.0, true)
	for i in range(6):
		var a := -PI / 2.0 + TAU * float(i) / 6.0
		draw_circle(center + Vector2(cos(a), sin(a)) * radius * 0.9, radius * 0.06, accent)

## Wild medallion: the four suit colors as cylinder wedges under a brass rim.
func _draw_wild_medallion(center: Vector2, radius: float) -> void:
	var quads := [SUIT_COLORS[Card.CardColor.RED], SUIT_COLORS[Card.CardColor.GREEN],
		SUIT_COLORS[Card.CardColor.ORANGE], SUIT_COLORS[Card.CardColor.PURPLE]]
	draw_circle(center + Vector2(1, 2), radius, Color(0, 0, 0, 0.4))
	draw_circle(center, radius, Color("221a10"))
	for q in range(4):
		var pts := PackedVector2Array([center])
		var a0 := q * PI / 2.0
		for sidx in range(13):
			var a := a0 + (PI / 2.0) * float(sidx) / 12.0
			pts.append(center + Vector2(cos(a), sin(a)) * radius * 0.84)
		draw_colored_polygon(pts, quads[q])
	draw_arc(center, radius, 0, TAU, 40, BRASS_LIGHT, maxf(1.2, radius * 0.07), true)

## Suit pip — a distinct SHAPE per color so suits read without relying on hue alone.
func _draw_pip(c: Card, center: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	match c.color:
		Card.CardColor.RED:
			pts = PackedVector2Array([center + Vector2(0, -s), center + Vector2(s * 0.75, 0), center + Vector2(0, s), center + Vector2(-s * 0.75, 0)])
		Card.CardColor.GREEN:
			draw_circle(center, s * 0.75, col)
			return
		Card.CardColor.ORANGE:
			pts = PackedVector2Array([center + Vector2(0, -s * 0.9), center + Vector2(s * 0.9, s * 0.7), center + Vector2(-s * 0.9, s * 0.7)])
		Card.CardColor.PURPLE:
			for i in range(6):
				var a := TAU * float(i) / 6.0
				pts.append(center + Vector2(cos(a), sin(a)) * s * 0.85)
		Card.CardColor.BLUE:
			pts = PackedVector2Array([center + Vector2(-s * 0.7, -s * 0.7), center + Vector2(s * 0.7, -s * 0.7), center + Vector2(s * 0.7, s * 0.7), center + Vector2(-s * 0.7, s * 0.7)])
		Card.CardColor.YELLOW:
			pts = PackedVector2Array([center + Vector2(-s * 0.9, -s * 0.7), center + Vector2(s * 0.9, -s * 0.7), center + Vector2(0, s * 0.9)])
		_:
			return
	draw_colored_polygon(pts, col)

func _draw_hatch(rect: Rect2, col: Color) -> void:
	var step := card_width * 0.14
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		var a := Vector2(x, rect.end.y)
		var b := Vector2(x + rect.size.y, rect.position.y)
		# Clip segment to rect horizontally.
		if a.x < rect.position.x:
			a = Vector2(rect.position.x, a.y - (rect.position.x - a.x))
		if b.x > rect.end.x:
			b = Vector2(rect.end.x, b.y + (b.x - rect.end.x))
		if a.x < b.x:
			draw_line(a, b, col, 1.0, true)
		x += step

func _ellipse_point(rx: float, ry: float, rot: float, a: float) -> Vector2:
	return Vector2(cos(a) * rx, sin(a) * ry).rotated(rot)

func _draw_text_centered(txt: String, baseline_center: Vector2, fs: int, col: Color, outline_col: Color = Color(0, 0, 0, 0), outline: int = 0) -> void:
	var pos := Vector2(0, baseline_center.y)
	if outline > 0:
		draw_string_outline(FONT, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, card_width, fs, outline, Color(outline_col, 0.35))
	draw_string(FONT, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, card_width, fs, col)

## Top-left index (with suit pip) plus an optional 180°-rotated copy bottom-right.
func _draw_corners(txt: String, col: Color, fs: int, mirrored: bool = true, pip_card: Card = null, pip_col: Color = Color.WHITE) -> void:
	_draw_corner_once(txt, col, fs, pip_card, pip_col)
	if not mirrored:
		return
	draw_set_transform(size_vec(), PI, Vector2.ONE)
	_draw_corner_once(txt, col, fs, pip_card, pip_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_corner_once(txt: String, col: Color, fs: int, pip_card: Card, pip_col: Color) -> void:
	var pad := card_width * 0.1
	var box_w := card_width * 0.5
	draw_string(FONT_NARROW, Vector2(pad, pad + fs * 0.82), txt, HORIZONTAL_ALIGNMENT_LEFT, box_w, fs, col)
	if pip_card != null:
		_draw_pip(pip_card, Vector2(pad + fs * 0.3, pad + fs * 1.3), fs * 0.24, pip_col)

## Small caption along the bottom of the panel (action / special names).
func _draw_caption(txt: String, col: Color, panel: Rect2) -> void:
	var fs := int(card_height * 0.095)
	draw_string(FONT_NARROW, Vector2(0, panel.end.y - fs * 0.45), txt, HORIZONTAL_ALIGNMENT_CENTER, card_width, fs, col)

## Kenney icon centered at `center`, `px` tall, tinted `col`.
func _draw_icon(icon_key: String, center: Vector2, px: float, col: Color) -> void:
	var tex: Texture2D = _ICONS.get(icon_key, _ICONS["default"])
	var half := px / 2.0
	draw_texture_rect(tex, Rect2(center - Vector2(half, half), Vector2(px, px)), false, col)

## Playable glow (pulsing brass) and selection ring, drawn outside the card.
func _draw_state_rings() -> void:
	var r := _radius()
	if playable:
		var pulse := 0.5 + 0.5 * sin(_glow_t * 4.0)
		var glow := _box(Color(0, 0, 0, 0), r + 3, Color(BRASS_LIGHT, 0.55 + 0.35 * pulse), 2.5)
		glow.draw_center = false
		glow.shadow_color = Color(BRASS, 0.35 + 0.25 * pulse + (0.2 if _hovering else 0.0))
		glow.shadow_size = int(6 + 4 * pulse)
		draw_style_box(glow, Rect2(Vector2(-3, -3), size_vec() + Vector2(6, 6)))
	if selected:
		var ring := _box(Color(0, 0, 0, 0), r + 4, Color.WHITE, 3.0)
		ring.draw_center = false
		draw_style_box(ring, Rect2(Vector2(-4, -4), size_vec() + Vector2(8, 8)))

func _draw_back() -> void:
	var w := card_width
	var h := card_height
	var r := _radius()
	_draw_shadow()
	draw_style_box(_box(BRASS, r, BRASS.darkened(0.3), 1.0), Rect2(Vector2.ZERO, size_vec()))
	var inset := w * 0.07
	var pr := Rect2(Vector2(inset, inset), size_vec() - Vector2(inset, inset) * 2.0)
	var deep := Color("4d0e16")
	draw_style_box(_box(deep, r * 0.7), pr)

	# Diamond lattice (only whole diamonds inside the panel).
	var cell := w * 0.16
	var lattice_col := Color("6b1822")
	var y := pr.position.y + cell * 0.5
	var row := 0
	while y < pr.end.y - cell * 0.4:
		var x := pr.position.x + cell * (0.5 if row % 2 == 0 else 1.0)
		while x < pr.end.x - cell * 0.4:
			var d := cell * 0.42
			draw_colored_polygon(PackedVector2Array([Vector2(x, y - d), Vector2(x + d, y), Vector2(x, y + d), Vector2(x - d, y)]), lattice_col)
			x += cell
		y += cell * 0.5
		row += 1
	# Inner brass hairline.
	var hair := _box(Color(0, 0, 0, 0), r * 0.5, Color(BRASS, 0.7), 1.0)
	hair.draw_center = false
	draw_style_box(hair, pr.grow(-w * 0.04))

	# Revolver-cylinder emblem.
	var c := size_vec() * 0.5
	var rad := minf(w, h) * 0.26
	draw_circle(c, rad * 1.12, deep)
	draw_circle(c, rad, BRASS)
	draw_arc(c, rad, 0, TAU, 40, BRASS_LIGHT, 1.2, true)
	for i in range(6):
		var a := -PI / 2.0 + TAU * float(i) / 6.0
		var hc := c + Vector2(cos(a), sin(a)) * rad * 0.58
		draw_circle(hc, rad * 0.22, INK)
		draw_arc(hc, rad * 0.22, 0, TAU, 16, BRASS.darkened(0.35), 1.0, true)
	draw_circle(c, rad * 0.16, BRASS.darkened(0.3))
	draw_circle(c, rad * 0.07, INK)
