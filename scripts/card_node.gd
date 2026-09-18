extends Control
class_name CardNode

signal card_clicked(card_node: CardNode)

var card_data: Card = null
var face_up: bool = true
var playable: bool = false
var card_width: float = 80.0
var card_height: float = 120.0

var _base_y: float = 0.0
var _hovering: bool = false

# ── Kenney board game icons (white silhouettes, tinted at draw time) ──
const _ICONS := {
	"skip": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/pawn_skip.png"),
	"reverse": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/arrow_counterclockwise.png"),
	"draw_two": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/tag_2.png"),
	"draw_four": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/tag_4.png"),
	"draw_ten": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/tag_10.png"),
	"swap_hands": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/cards_shift.png"),
	"peek": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/cards_seek_top.png"),
	"extra_life": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/suit_hearts.png"),
	"choose_deck": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/card.png"),
	"rotate_decks": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/arrow_rotate.png"),
	"wild_color": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/cards_fan.png"),
	"wild_sabotage": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/cards_skull.png"),
	"bomb": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/skull.png"),
	"diffuse": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/shield.png"),
	"default": preload("res://assets/imported_assets/kenney_board-game-icons/PNG/Default (64px)/card_outline.png"),
}

func setup(data: Card, face: bool = true, w: float = 80.0, h: float = 120.0) -> CardNode:
	card_data = data
	face_up = face
	card_width = w
	card_height = h
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	_base_y = 0.0
	tooltip_text = data.display_name if data else ""
	return self

func _ready() -> void:
	_base_y = position.y
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	gui_input.connect(_on_input)
	_update_visual()

func set_playable(val: bool) -> void:
	playable = val
	queue_redraw()

func _on_hover() -> void:
	if face_up and playable:
		_hovering = true
		_animate_y(-8.0)
		queue_redraw()

func _on_unhover() -> void:
	_hovering = false
	_animate_y(0.0)
	queue_redraw()

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if face_up:
			card_clicked.emit(self)

func _animate_y(offset: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position:y", _base_y + offset, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func update_face(face: bool) -> void:
	face_up = face
	_update_visual()

func _update_visual() -> void:
	queue_redraw()

func _draw() -> void:
	if card_data == null:
		return
	if face_up:
		_draw_front()
	else:
		_draw_back()

func _draw_front() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(card_width, card_height))
	var c := card_data

	# Determine colors based on card type and color
	var bg_col: Color
	var border_col: Color
	var accent_col: Color

	match c.type:
		Card.CardType.NUMBER, Card.CardType.ACTION:
			match c.color:
				Card.CardColor.RED:
					bg_col = Color(0.85, 0.18, 0.18)
					border_col = Color(0.95, 0.3, 0.3)
					accent_col = Color.WHITE
				Card.CardColor.BLUE:
					bg_col = Color(0.15, 0.35, 0.82)
					border_col = Color(0.25, 0.5, 0.95)
					accent_col = Color.WHITE
				Card.CardColor.GREEN:
					bg_col = Color(0.15, 0.65, 0.28)
					border_col = Color(0.25, 0.78, 0.38)
					accent_col = Color.WHITE
				Card.CardColor.YELLOW:
					bg_col = Color(0.92, 0.78, 0.15)
					border_col = Color(1.0, 0.9, 0.3)
					accent_col = Color(0.15, 0.12, 0.05)
				Card.CardColor.ORANGE:
					bg_col = Color(0.95, 0.5, 0.12)
					border_col = Color(1.0, 0.64, 0.22)
					accent_col = Color.WHITE
				Card.CardColor.PURPLE:
					bg_col = Color(0.55, 0.2, 0.78)
					border_col = Color(0.66, 0.32, 0.92)
					accent_col = Color.WHITE
				_:
					bg_col = Color(0.35, 0.35, 0.4)
					border_col = Color(0.5, 0.5, 0.55)
					accent_col = Color.WHITE
		Card.CardType.WILD:
			bg_col = Color(0.15, 0.1, 0.25)
			border_col = Color(0.85, 0.65, 0.15)
			accent_col = Color(0.95, 0.85, 0.25)
		Card.CardType.BOMB:
			bg_col = Color(0.12, 0.08, 0.08)
			border_col = Color(0.9, 0.2, 0.1)
			accent_col = Color(0.95, 0.3, 0.15)
		Card.CardType.DIFFUSE:
			bg_col = Color(0.08, 0.18, 0.12)
			border_col = Color(0.2, 0.8, 0.4)
			accent_col = Color(0.3, 0.9, 0.5)
		Card.CardType.RESPAWN:
			bg_col = Color(0.28, 0.1, 0.38)
			border_col = Color(0.72, 0.35, 0.95)
			accent_col = Color(0.95, 0.7, 1.0)

	# Shadow
	draw_rect(Rect2(Vector2(3, 3), Vector2(card_width, card_height)), Color(0, 0, 0, 0.35))

	# Background
	draw_rect(r, bg_col)

	# Rounded border effect via inner border rect
	var bw := 2.5
	if playable:
		bw = 3.5
		border_col = Color(1.0, 0.92, 0.45)
	draw_rect(Rect2(Vector2(bw, bw), Vector2(card_width - bw * 2, card_height - bw * 2)), border_col)

	# Inner fill
	var iw := 1.0
	draw_rect(Rect2(Vector2(bw + iw, bw + iw), Vector2(card_width - (bw + iw) * 2, card_height - (bw + iw) * 2)), bg_col)

	# Wild card: draw rainbow gradient bands
	if c.type == Card.CardType.WILD:
		var colors = [Color(0.85, 0.18, 0.18), Color(0.15, 0.35, 0.82), Color(0.15, 0.65, 0.28), Color(0.92, 0.78, 0.15)]
		var band_h := (card_height - 20) / 4.0
		for i in range(4):
			var band_r := Rect2(Vector2(10, 10 + i * band_h), Vector2(card_width - 20, band_h))
			draw_rect(band_r, colors[i].lerp(bg_col, 0.5))

	# Bomb card: Kenney skull icon
	if c.type == Card.CardType.BOMB:
		var icon_size := int(min(card_width, card_height) * 0.5)
		var tex: Texture2D = _ICONS["bomb"]
		var rect := Rect2(Vector2(card_width / 2.0 - icon_size / 2.0, card_height / 2.0 - 8.0 - icon_size / 2.0), Vector2(icon_size, icon_size))
		draw_texture_rect(tex, rect, false, accent_col)

	# Diffuse card: Kenney shield icon
	if c.type == Card.CardType.DIFFUSE:
		var icon_size := int(min(card_width, card_height) * 0.5)
		var tex: Texture2D = _ICONS["diffuse"]
		var rect := Rect2(Vector2(card_width / 2.0 - icon_size / 2.0, card_height / 2.0 - 5.0 - icon_size / 2.0), Vector2(icon_size, icon_size))
		draw_texture_rect(tex, rect, false, accent_col)

	# Number text (for number cards)
	if c.type == Card.CardType.NUMBER:
		var num_text := str(c.number)
		var font_size := int(min(card_width, card_height) * 0.44)
		var corner_size := int(font_size * 0.42)

		# Center number (perfectly centered horizontally and vertically)
		draw_string(ThemeDB.fallback_font, Vector2(0, card_height / 2.0 + font_size * 0.34), num_text, HORIZONTAL_ALIGNMENT_CENTER, card_width, font_size, accent_col)

		# Top-left corner number
		draw_string(ThemeDB.fallback_font, Vector2(6, corner_size + 4), num_text, HORIZONTAL_ALIGNMENT_LEFT, 20, corner_size, accent_col)
		# Bottom-right corner number
		draw_string(ThemeDB.fallback_font, Vector2(card_width - 26, card_height - 6), num_text, HORIZONTAL_ALIGNMENT_RIGHT, 20, corner_size, accent_col)

		# Color symbol (diamond for visual distinction)
		var sym_y := card_height - 12.0
		_draw_color_symbol(Vector2(card_width / 2.0, sym_y), 4.5, c.color)

	# Action card: Kenney icon + text label
	if c.type == Card.CardType.ACTION:
		var action_text := ""
		match c.action_id:
			"skip": action_text = "SKIP"
			"reverse": action_text = "REV"
			"draw_two": action_text = "+2"
			"draw_four": action_text = "+4"
			"draw_ten": action_text = "+10"
			"swap_hands": action_text = "SWAP"
			"peek": action_text = "PEEK"
			"extra_life": action_text = "LIFE"
			"choose_deck": action_text = "DECK"
			"rotate_decks": action_text = "ROT"
			_: action_text = "?"
		_draw_labeled_icon(action_text, c.action_id, 0.16, 0.18, accent_col)

	# Wild card: Kenney icon + text label
	if c.type == Card.CardType.WILD:
		var wild_text := ""
		var icon_key := "wild_color"
		match c.action_id:
			"wild_sabotage":
				wild_text = "SABOTAGE"
				icon_key = "wild_sabotage"
			_:
				wild_text = "WILD"
				icon_key = "wild_color"
		_draw_labeled_icon(wild_text, icon_key, 0.16, 0.18, accent_col)

	# Respawn card: purple revival card
	if c.type == Card.CardType.RESPAWN:
		# Top-left corner mini label
		var corner_font_size := int(min(card_width, card_height) * 0.14)
		draw_string(ThemeDB.fallback_font, Vector2(6, corner_font_size + 4), "REVIVE", HORIZONTAL_ALIGNMENT_LEFT, card_width * 0.5, corner_font_size, accent_col)

		var icon_size := int(min(card_width, card_height) * 0.4)
		_draw_icon("default", card_width / 2.0, card_height * 0.40, icon_size, accent_col)
		var font_size := int(min(card_width, card_height) * 0.16)
		draw_string(ThemeDB.fallback_font, Vector2(0, card_height * 0.74), "RESPAWN", HORIZONTAL_ALIGNMENT_CENTER, card_width, font_size, accent_col)

	_draw_playable_glow()

## Draws a playable-glow ring around the card when it can be played.
func _draw_playable_glow() -> void:
	if playable:
		var glow_col := Color(1.0, 0.92, 0.45, 0.25 if _hovering else 0.12)
		draw_rect(Rect2(Vector2(-2, -2), Vector2(card_width + 4, card_height + 4)), glow_col, false, 3.0)

func _draw_back() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(card_width, card_height))

	# Shadow
	draw_rect(Rect2(Vector2(3, 3), Vector2(card_width, card_height)), Color(0, 0, 0, 0.35))

	# Outer border (gold-ish)
	draw_rect(r, Color(0.65, 0.5, 0.2))

	# Inner dark background
	var inset := 4.0
	draw_rect(Rect2(Vector2(inset, inset), Vector2(card_width - inset * 2, card_height - inset * 2)), Color(0.12, 0.1, 0.18))

	# Inner border pattern
	var p_inset := 7.0
	draw_rect(Rect2(Vector2(p_inset, p_inset), Vector2(card_width - p_inset * 2, card_height - p_inset * 2)), Color(0.35, 0.28, 0.15), false, 1.5)

	# Chamber icon (6-segment circle) in center
	var cx := card_width / 2
	var cy := card_height / 2
	var icon_r: float = min(card_width, card_height) * 0.2

	# Draw 6 pie segments
	for i in range(6):
		var angle_from := deg_to_rad(i * 60 - 90)
		var angle_to := deg_to_rad((i + 1) * 60 - 90)
		var col := Color(0.65, 0.2, 0.15) if i % 2 == 0 else Color(0.75, 0.6, 0.2)
		var pts := PackedVector2Array([Vector2(cx, cy)])
		var segments := 8
		for s in range(segments + 1):
			var a: float = lerp(angle_from, angle_to, float(s) / segments)
			pts.append(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * icon_r)
		draw_colored_polygon(pts, col)

	# Center dot
	draw_circle(Vector2(cx, cy), icon_r * 0.25, Color(0.12, 0.1, 0.18))

	# Top/bottom border accents
	var accent_w := card_width - 16
	draw_line(Vector2(8, 12), Vector2(8 + accent_w, 12), Color(0.45, 0.35, 0.15), 1.0)
	draw_line(Vector2(8, card_height - 12), Vector2(8 + accent_w, card_height - 12), Color(0.45, 0.35, 0.15), 1.0)

## Top-left corner mini-label + Kenney icon + bottom label for a card face.
func _draw_labeled_icon(label: String, icon_key: String, corner_scale: float, label_scale: float, accent: Color) -> void:
	var corner_font_size := int(min(card_width, card_height) * corner_scale)
	draw_string(ThemeDB.fallback_font, Vector2(6, corner_font_size + 4), label, HORIZONTAL_ALIGNMENT_LEFT, card_width * 0.5, corner_font_size, accent)
	var icon_size := int(min(card_width, card_height) * 0.4)
	_draw_icon(icon_key, card_width / 2.0, card_height * 0.40, icon_size, accent)
	var font_size := int(min(card_width, card_height) * label_scale)
	draw_string(ThemeDB.fallback_font, Vector2(0, card_height * 0.74), label, HORIZONTAL_ALIGNMENT_CENTER, card_width, font_size, accent)

## Draw a Kenney icon texture centered at (cx, cy) with the given size, tinted by col.
func _draw_icon(icon_key: String, cx: float, cy: float, size: int, col: Color) -> void:
	var tex: Texture2D = _ICONS.get(icon_key, _ICONS["default"])
	var half := float(size) / 2.0
	var rect := Rect2(Vector2(cx - half, cy - half), Vector2(size, size))
	draw_texture_rect(tex, rect, false, col)

func _draw_color_symbol(pos: Vector2, radius: float, color: int) -> void:
	var col: Color
	match color:
		Card.CardColor.RED: col = Color(1.0, 0.4, 0.35)
		Card.CardColor.BLUE: col = Color(0.4, 0.6, 1.0)
		Card.CardColor.GREEN: col = Color(0.35, 0.85, 0.45)
		Card.CardColor.YELLOW: col = Color(1.0, 0.9, 0.3)
		Card.CardColor.ORANGE: col = Color(1.0, 0.62, 0.2)
		Card.CardColor.PURPLE: col = Color(0.8, 0.5, 1.0)
		_: col = Color.WHITE

	# Diamond shape
	var pts := PackedVector2Array([
		pos + Vector2(0, -radius),
		pos + Vector2(radius, 0),
		pos + Vector2(0, radius),
		pos + Vector2(-radius, 0),
	])
	draw_colored_polygon(pts, col)
