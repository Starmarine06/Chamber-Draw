extends Control

## Tutorial HUD: a docked "coach" panel (chapter · step · progress, title,
## color-coded body, Continue / your-move hint, Exit) plus a SPOTLIGHT pointer —
## a pulsing brass ring around the thing to click with a bouncing arrow — that
## tracks its target every frame. The table stays fully visible and playable.
##
## Body text supports [b], [color=…] etc. (RichTextLabel BBCode) and these
## shorthand tags: [key]…[/key] (brass), [bad]…[/bad] (blood), [good]…[/good].

signal continued
signal exit_requested

const UIStyle := preload("res://scripts/ui_style.gd")
const Juice := preload("res://scripts/fx/juice.gd")

const PANEL_W := 340.0

var _panel: PanelContainer
var _chapter: Label
var _counter: Label
var _progress_fill: ColorRect
var _title: Label
var _body: RichTextLabel
var _continue_btn: Button
var _hint: Label
var _pointer: Control
var _target: Callable = Callable()   # () -> Rect2 in this control's coords
var _waiting := false
var _t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80

	_pointer = Pointer.new()
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pointer)

	_panel = UIStyle.make_panel(Color(UIStyle.INK, 0.9))
	_panel.position = Vector2(14, 56)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)

	_chapter = UIStyle.make_caption("")
	_chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_chapter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_chapter)
	_counter = UIStyle.make_label("", 11, UIStyle.MUTED)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_counter)

	var track := ColorRect.new()
	track.color = Color(UIStyle.BRASS_DIM, 0.35)
	track.custom_minimum_size = Vector2(0, 4)
	v.add_child(track)
	_progress_fill = ColorRect.new()
	_progress_fill.color = UIStyle.BRASS
	_progress_fill.size = Vector2(0, 4)
	track.add_child(_progress_fill)

	_title = UIStyle.make_label("", 20, UIStyle.BRASS_LIGHT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(PANEL_W - 44, 0)
	_body.add_theme_font_override("normal_font", UIStyle.body_font())
	_body.add_theme_font_size_override("normal_font_size", 14)
	_body.add_theme_font_size_override("bold_font_size", 14)
	_body.add_theme_color_override("default_color", UIStyle.CREAM)
	_body.add_theme_constant_override("line_separation", 3)
	v.add_child(_body)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	_continue_btn = UIStyle.make_button("CONTINUE  ▸", &"primary", Vector2(170, 40), 15)
	_continue_btn.pressed.connect(_on_continue)
	foot.add_child(_continue_btn)
	_hint = UIStyle.make_label("▶ YOUR MOVE", 15, UIStyle.BRASS_LIGHT, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.visible = false
	foot.add_child(_hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var exit_btn := UIStyle.make_button("EXIT", &"secondary", Vector2(70, 40), 13)
	exit_btn.pressed.connect(func() -> void: exit_requested.emit())
	foot.add_child(exit_btn)

func _process(delta: float) -> void:
	_t += delta
	if _hint.visible:
		_hint.modulate.a = 0.65 + 0.35 * sin(_t * 5.0)
	var r := Rect2()
	if _target.is_valid():
		var v: Variant = _target.call()
		if v is Rect2:
			r = v
	_pointer.set("target", r)
	_dock_away_from(r)
	_pointer.set("t", _t)
	_pointer.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _waiting or not event.pressed:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_on_continue()

func _on_continue() -> void:
	if not _waiting:
		return
	_waiting = false
	continued.emit()

var _dock_right := false

## Slides the coach to the right edge when the spotlight target sits under it
## on the left (and back when it doesn't).
func _dock_away_from(r: Rect2) -> void:
	var left_rect := Rect2(Vector2(14, 56), _panel.size)
	var want_right := r.size != Vector2.ZERO and left_rect.grow(12.0).intersects(r)
	if want_right == _dock_right:
		return
	_dock_right = want_right
	var x := size.x - _panel.size.x - 14.0 if want_right else 14.0
	create_tween().tween_property(_panel, "position:x", x, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Shows a step. `wait_continue`: show CONTINUE (info step) vs. the pulsing
## "YOUR MOVE" hint (action step). `target`: () -> Rect2 to spotlight.
func show_step(chapter: String, step: int, progress: float, title: String, body: String,
		wait_continue: bool, target: Callable = Callable()) -> void:
	_chapter.text = chapter
	_counter.text = "STEP %d" % step
	_title.text = title
	_body.text = _markup(body)
	_continue_btn.visible = wait_continue
	_hint.visible = not wait_continue
	_waiting = wait_continue
	_target = target
	var track := _progress_fill.get_parent() as Control
	var tw := create_tween()
	tw.tween_property(_progress_fill, "size:x", maxf(track.size.x, PANEL_W - 44) * clampf(progress, 0.0, 1.0), 0.35)
	_panel.reset_size()
	_panel.pivot_offset = Vector2(0, 0)
	_panel.modulate.a = 0.0
	var ap := create_tween()
	ap.tween_property(_panel, "modulate:a", 1.0, 0.18)
	var home := size.x - PANEL_W - 14.0 if _dock_right else 14.0
	ap.parallel().tween_property(_panel, "position:x", home, 0.22).from(home - 20.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_target(target: Callable) -> void:
	_target = target

## Small celebratory stamp next to the panel + sound + sparkle.
func cheer(text: String = "NICE!") -> void:
	var l := UIStyle.make_label(text, 30, UIStyle.BRASS_LIGHT, true)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.reset_size()
	l.position = _panel.position + Vector2(PANEL_W + 18, 10)
	l.pivot_offset = l.size * 0.5
	l.rotation_degrees = -8.0
	l.scale = Vector2(2.0, 2.0)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)
	Juice.burst(self, l.position + l.size * 0.5, &"gold", 1.0)

func _markup(s: String) -> String:
	return s.replace("[key]", "[color=#ecd394][b]").replace("[/key]", "[/b][/color]") \
		.replace("[bad]", "[color=#e0505a][b]").replace("[/bad]", "[/b][/color]") \
		.replace("[good]", "[color=#7fd49a][b]").replace("[/good]", "[/b][/color]")

## Pulsing ring around the target + a bouncing arrow pointing at it.
class Pointer extends Control:
	var target := Rect2()
	var t := 0.0

	func _draw() -> void:
		if target.size == Vector2.ZERO:
			return
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		var r := target.grow(6.0 + pulse * 5.0)
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = Color(0.93, 0.83, 0.58, 0.65 + 0.35 * pulse)
		box.set_border_width_all(3)
		box.set_corner_radius_all(12)
		box.shadow_color = Color(0.79, 0.64, 0.36, 0.35 + 0.3 * pulse)
		box.shadow_size = int(10 + 8 * pulse)
		draw_style_box(box, r)
		# Arrow comes from above (or below when the target is near the top).
		var from_above := r.position.y > 120.0
		var bob := sin(t * 6.0) * 8.0
		var tip := Vector2(r.get_center().x, r.position.y - 8.0 - bob) if from_above \
			else Vector2(r.get_center().x, r.end.y + 8.0 + bob)
		var dirv := -1.0 if from_above else 1.0
		var head := PackedVector2Array([tip, tip + Vector2(-14, 20 * dirv), tip + Vector2(14, 20 * dirv)])
		draw_colored_polygon(head, Color(0.93, 0.83, 0.58))
		draw_line(tip + Vector2(0, 18 * dirv), tip + Vector2(0, 46 * dirv), Color(0.93, 0.83, 0.58), 6.0, true)
