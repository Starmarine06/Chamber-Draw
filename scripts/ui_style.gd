extends RefCounted

## Shared "noir casino" look for every screen. A STATIC library — scripts use
## `const UIStyle := preload("res://scripts/ui_style.gd")` (no autoload name, so
## the editor never needs a restart to resolve it). Owns the palette, fonts, a
## root Theme and the widget builders menu / lobby / game all share.
## `install()` applies the theme once; `audio()` / `settings()` return the
## AudioManager / Settings nodes, creating them if the autoload is missing.

# ── Palette ───────────────────────────────────────────────────────────
const INK := Color("0e0b10")          # near-black background
const SMOKE := Color("221d27")        # panel fill
const SMOKE_LIGHT := Color("352d3b")
const BRASS := Color("c9a45c")        # primary accent
const BRASS_LIGHT := Color("ecd394")
const BRASS_DIM := Color("7d6538")
const BLOOD := Color("9e1b2a")        # danger / chamber
const BLOOD_LIGHT := Color("d23a45")
const FELT := Color("1d5a43")         # confirm / table green
const CREAM := Color("efe6d2")        # primary text
const MUTED := Color("9c917f")        # secondary text
const SHADOW := Color(0, 0, 0, 0.55)

const FONT_TITLE_PATH := "res://assets/imported_assets/kenney_ui-pack/Font/Kenney Future.ttf"
const FONT_BODY_PATH := "res://assets/imported_assets/kenney_ui-pack/Font/Kenney Future Narrow.ttf"
const AUDIO_SCRIPT := "res://scripts/audio_manager.gd"
const SETTINGS_SCRIPT := "res://scripts/settings.gd"

static var font_title: Font
static var font_body: Font
static var theme: Theme

static func _root() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree else null

## Applies the noir Theme + clear color to the window once (idempotent).
## Call from each screen's _ready before building UI.
static func install() -> void:
	settings()
	audio()
	var root := _root()
	if root == null:
		return
	if theme == null:
		theme = build_theme()
	root.theme = theme
	RenderingServer.set_default_clear_color(INK)

## Returns the node at /root/<node_name>, creating it from `script_path` if the
## autoload isn't registered (e.g. the editor dropped it from project.godot).
## Created nodes are cached and added DEFERRED — the root is usually "busy
## setting up children" while a scene's _ready runs, and a direct add_child
## there fails (which used to leave half-built UI behind).
static var _services: Dictionary = {}

static func _service(node_name: String, script_path: String) -> Node:
	var root := _root()
	if root == null:
		return null
	var n := root.get_node_or_null(node_name)
	if n != null:
		return n
	var cached: Node = _services.get(node_name, null)
	if cached != null and is_instance_valid(cached):
		return cached
	n = (load(script_path) as Script).new() as Node
	n.name = node_name
	_services[node_name] = n
	root.add_child.call_deferred(n)
	return n

static func audio() -> Node:
	return _service("AudioManager", AUDIO_SCRIPT)

static func settings() -> Node:
	return _service("Settings", SETTINGS_SCRIPT)

static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var f := load(path) as FontFile
	if f == null:
		return ThemeDB.fallback_font
	# Kenney Future lacks symbols (❚❚ ● ♥ …) — let the OS font fill them in.
	f.allow_system_fallback = true
	return f

## Title font (falls back to the engine font when not yet loaded, e.g. in tests).
static func title_font() -> Font:
	if font_title == null:
		font_title = _load_font(FONT_TITLE_PATH)
	return font_title

static func body_font() -> Font:
	if font_body == null:
		font_body = _load_font(FONT_BODY_PATH)
	return font_body

# ── Theme ─────────────────────────────────────────────────────────────

static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))
	t.set_color("default_color", "RichTextLabel", CREAM)

	_apply_button_styles_to_theme(t, SMOKE, BRASS_DIM)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", BRASS_LIGHT)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_focus_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(CREAM, 0.4))

	# CheckBox inherits Button styles — give it a bare row so the tick shows.
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var cb := StyleBoxEmpty.new()
		cb.content_margin_left = 4
		cb.content_margin_top = 4
		cb.content_margin_bottom = 4
		t.set_stylebox(st, "CheckBox", cb)

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "TooltipPanel", panel_style(Color(INK, 0.95), BRASS_DIM, 6, 1))
	t.set_color("font_color", "TooltipLabel", CREAM)

	var le := flat_box(Color(INK, 0.85), BRASS_DIM, 6, 2)
	le.content_margin_left = 12
	le.content_margin_right = 12
	var le_focus := flat_box(Color(INK, 0.9), BRASS, 6, 2)
	le_focus.content_margin_left = 12
	le_focus.content_margin_right = 12
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("caret_color", "LineEdit", BRASS_LIGHT)

	var track := flat_box(Color(INK, 0.9), BRASS_DIM, 4, 1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := flat_box(BRASS, BRASS, 4, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t

static func _apply_button_styles_to_theme(t: Theme, fill: Color, border: Color) -> void:
	var boxes := button_boxes(fill, border)
	for state in boxes:
		t.set_stylebox(state, "Button", boxes[state])

# ── StyleBoxes ────────────────────────────────────────────────────────

static func flat_box(fill: Color, border: Color, radius: int = 8, border_w: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s

## Framed smoked-glass panel with a brass hairline and soft drop shadow.
static func panel_style(fill: Color = Color(SMOKE, 0.94), border: Color = BRASS_DIM, radius: int = 12, border_w: int = 2) -> StyleBoxFlat:
	var s := flat_box(fill, border, radius, border_w)
	s.shadow_color = SHADOW
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	return s

## Fresh StyleBoxFlat per state (never shared — see AGENTS.md fixed bug #8).
static func button_boxes(fill: Color, border: Color) -> Dictionary:
	var normal := flat_box(fill, border, 8, 2)
	normal.shadow_color = SHADOW
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 3)
	_button_margins(normal, 0)

	var hover := flat_box(fill.lightened(0.12), BRASS_LIGHT, 8, 2)
	hover.shadow_color = SHADOW
	hover.shadow_size = 6
	hover.shadow_offset = Vector2(0, 4)
	_button_margins(hover, 0)

	var pressed := flat_box(fill.darkened(0.18), border, 8, 2)
	pressed.shadow_color = SHADOW
	pressed.shadow_size = 1
	pressed.shadow_offset = Vector2(0, 1)
	_button_margins(pressed, 2)

	var disabled := flat_box(Color(fill.darkened(0.35), 0.7), Color(border, 0.35), 8, 2)
	_button_margins(disabled, 0)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"hover_pressed": pressed.duplicate(),
		"disabled": disabled,
		"focus": StyleBoxEmpty.new(),
	}

static func _button_margins(s: StyleBoxFlat, press_shift: int) -> void:
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 6 + press_shift
	s.content_margin_bottom = 6 - press_shift

# ── Widgets ───────────────────────────────────────────────────────────

## Variants: &"primary" (brass), &"secondary" (smoke), &"danger" (blood),
## &"confirm" (felt green).
static func variant_fill(variant: StringName) -> Color:
	match variant:
		&"primary": return BRASS
		&"danger": return BLOOD
		&"confirm": return FELT
		_: return SMOKE_LIGHT

static func make_button(text: String, variant: StringName = &"secondary", min_size: Vector2 = Vector2.ZERO, font_size: int = 18) -> Button:
	return make_tinted_button(text, variant_fill(variant), min_size, font_size)

## Button filled with an arbitrary color (text auto dark/light by luminance).
static func make_tinted_button(text: String, fill: Color, min_size: Vector2 = Vector2.ZERO, font_size: int = 18) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_override("font", title_font())
	btn.add_theme_font_size_override("font_size", font_size)
	var border := BRASS if fill.get_luminance() < 0.45 else BRASS_LIGHT
	var boxes := button_boxes(fill, border)
	for state in boxes:
		btn.add_theme_stylebox_override(state, boxes[state])
	var font_col := CREAM if fill.get_luminance() < 0.5 else INK
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", font_col.lerp(BRASS_LIGHT, 0.5) if font_col == CREAM else INK)
	btn.add_theme_color_override("font_pressed_color", font_col)
	btn.add_theme_color_override("font_focus_color", font_col)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("outline_size", 2 if font_col == CREAM else 0)
	add_juice(btn)
	return btn

## Toggle swatch for seat-color pickers (menu + lobby).
static func make_swatch(col: Color, text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(52, 34)
	btn.add_theme_font_override("font", body_font())
	btn.add_theme_font_size_override("font_size", 12)
	var font_col := CREAM if col.get_luminance() < 0.5 else INK
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(k, font_col)
	var normal := flat_box(col.darkened(0.25), col.darkened(0.45), 17, 2)
	var hover := flat_box(col.darkened(0.05), BRASS_LIGHT, 17, 2)
	var pressed := flat_box(col, CREAM, 17, 3)
	pressed.shadow_color = Color(col, 0.6)
	pressed.shadow_size = 8
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed.duplicate())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_juice(btn)
	return btn

## Big flat card-color button for the color picker popup.
static func make_color_button(text: String, color: Color, min_size: Vector2, font_size: int = 18) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_override("font", title_font())
	btn.add_theme_font_size_override("font_size", font_size)
	var font_col := CREAM if color.get_luminance() < 0.5 else INK
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(k, font_col)
	var normal := flat_box(color, CREAM.darkened(0.25), 14, 3)
	normal.shadow_color = SHADOW
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 4)
	var hover := flat_box(color.lightened(0.12), BRASS_LIGHT, 14, 4)
	hover.shadow_color = Color(color, 0.55)
	hover.shadow_size = 14
	var pressed := flat_box(color.darkened(0.18), CREAM, 14, 3)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_juice(btn)
	return btn

static func make_label(text: String, font_size: int = 17, color: Color = CREAM, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font())
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 3)
	return l

## Small caps section header ("PLAYERS", "GAME MODE" …).
static func make_caption(text: String) -> Label:
	var l := make_label(text, 14, MUTED, true)
	return l

static func make_panel(fill: Color = Color(SMOKE, 0.94)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(fill))
	return p

## Hover scale + sounds. Scale pivots on the center (kept in sync on resize).
static func add_juice(btn: BaseButton) -> void:
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	btn.mouse_entered.connect(func() -> void:
		if btn.disabled:
			return
		_sfx(&"hover")
		_tween_scale(btn, 1.045))
	btn.mouse_exited.connect(func() -> void: _tween_scale(btn, 1.0))
	btn.button_down.connect(func() -> void: _tween_scale(btn, 0.96))
	btn.button_up.connect(func() -> void: _tween_scale(btn, 1.045 if btn.is_hovered() else 1.0))
	btn.pressed.connect(func() -> void: _sfx(&"button"))

static func _tween_scale(c: Control, s: float) -> void:
	if not c.is_inside_tree():
		return
	var prev: Variant = c.get_meta(&"_juice_tw") if c.has_meta(&"_juice_tw") else null
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(s, s), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.set_meta(&"_juice_tw", tw)

static func _sfx(event: StringName) -> void:
	var am: Node = audio()
	if am:
		am.call("play", event, 0.0, 1.0)
