extends Control
const UIStyle := preload("res://scripts/ui_style.gd")
const Sound := preload("res://scripts/sound.gd")
const Keybinds := preload("res://scripts/keybinds.gd")
const VoiceChat := preload("res://scripts/voice_chat.gd")

## Modal settings overlay (audio / display / motion). Built in code; opened
## from the main menu and the in-game pause overlay. Changes apply live and
## are saved on close.

signal closed

var _settings: Node
var _panel: PanelContainer
var _listening: StringName = &""          # action waiting for its new key
var _key_buttons: Dictionary = {}          # action id -> Button
var _note: Label
var _general_box: VBoxContainer
var _controls_box: VBoxContainer
var _tab_general_btn: Button
var _tab_controls_btn: Button

func _ready() -> void:
	_settings = UIStyle.settings()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = UIStyle.make_panel()
	_panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)

	v.add_child(UIStyle.make_label("SETTINGS", 30, UIStyle.BRASS, true))

	# Tab bar.
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	v.add_child(tabs)
	_tab_general_btn = UIStyle.make_button("GENERAL", &"primary", Vector2(170, 40), 16)
	_tab_controls_btn = UIStyle.make_button("CONTROLS", &"secondary", Vector2(170, 40), 16)
	tabs.add_child(_tab_general_btn)
	tabs.add_child(_tab_controls_btn)
	v.add_child(_divider())

	# ── GENERAL tab ──
	_general_box = VBoxContainer.new()
	_general_box.add_theme_constant_override("separation", 10)
	v.add_child(_general_box)
	_general_box.add_child(UIStyle.make_caption("AUDIO"))
	_general_box.add_child(_slider_row("Master", "master_volume", 0.0, 1.0))
	_general_box.add_child(_slider_row("Music", "music_volume", 0.0, 1.0))
	_general_box.add_child(_slider_row("Effects", "sfx_volume", 0.0, 1.0))
	_general_box.add_child(_slider_row("Interface", "ui_volume", 0.0, 1.0))
	_general_box.add_child(_divider())
	_general_box.add_child(UIStyle.make_caption("VOICE CHAT"))
	_general_box.add_child(_voice_mode_row())
	_general_box.add_child(_voice_slider_row("Voice volume", true))
	_general_box.add_child(_voice_slider_row("Mic volume", false))
	_general_box.add_child(_divider())
	_general_box.add_child(UIStyle.make_caption("MOTION"))
	_general_box.add_child(_check_row("Reduced motion (no shake / flashes)", "reduced_motion"))
	_general_box.add_child(_slider_row("Screen shake", "shake_strength", 0.0, 1.0))
	_general_box.add_child(_slider_row("Animation speed", "anim_speed", 0.75, 1.5))

	# ── CONTROLS tab ──
	_controls_box = VBoxContainer.new()
	_controls_box.add_theme_constant_override("separation", 10)
	_controls_box.visible = false
	v.add_child(_controls_box)
	_controls_box.add_child(UIStyle.make_caption("CLICK A KEY, THEN PRESS THE NEW ONE"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	scroll.add_child(rows)
	rows.add_child(_sens_row())
	for a in Keybinds.ACTIONS:
		if a.shown:
			rows.add_child(_key_row(a.id))
	_note = Label.new()
	_note.add_theme_color_override("font_color", UIStyle.MUTED)
	_note.text = "Hand cards: 1-9  ·  Scroll picks a card  ·  Esc: pause"
	_controls_box.add_child(_note)
	var reset := UIStyle.make_button("Reset controls", &"secondary", Vector2(180, 36), 15)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func() -> void:
		Keybinds.reset_defaults()
		_listening = &""
		_refresh_keys()
		_note.text = "Controls reset to defaults.")
	_controls_box.add_child(reset)

	_tab_general_btn.pressed.connect(_show_tab.bind(false))
	_tab_controls_btn.pressed.connect(_show_tab.bind(true))

	v.add_child(_divider())
	var close := UIStyle.make_button("DONE", &"primary", Vector2(180, 44), 18)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close)
	v.add_child(close)

	# Entrance: pop the panel in.
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.9, 0.9)
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)

## Switches between the GENERAL and CONTROLS tabs.
func _show_tab(controls: bool) -> void:
	_listening = &""
	_refresh_keys()
	_general_box.visible = not controls
	_controls_box.visible = controls
	# The active tab is drawn as the primary button.
	var g := UIStyle.make_button("", &"primary" if not controls else &"secondary", Vector2(1, 1), 14)
	var k := UIStyle.make_button("", &"primary" if controls else &"secondary", Vector2(1, 1), 14)
	for state in ["normal", "hover", "pressed"]:
		_tab_general_btn.add_theme_stylebox_override(state, g.get_theme_stylebox(state))
		_tab_controls_btn.add_theme_stylebox_override(state, k.get_theme_stylebox(state))
	g.queue_free()
	k.queue_free()
	_panel.reset_size()

## Captures the next key press while a control is waiting to be rebound.
func _input(event: InputEvent) -> void:
	if _listening == &"":
		return
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	get_viewport().set_input_as_handled()
	if ke.keycode == KEY_ESCAPE:
		_listening = &""
		_note.text = "Rebind cancelled."
		_refresh_keys()
		return
	var displaced := Keybinds.set_key(_listening, ke.keycode)
	_note.text = "%s -> %s" % [Keybinds.label_of_action(_listening), Keybinds.key_name(ke.keycode)]
	if displaced != &"":
		_note.text += "   (%s is now unbound)" % Keybinds.label_of_action(displaced)
	_listening = &""
	_refresh_keys()

func _key_row(id: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = Keybinds.label_of_action(id)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var b := UIStyle.make_button(Keybinds.label(id), &"secondary", Vector2(110, 34), 15)
	b.pressed.connect(func() -> void:
		_listening = id
		_note.text = "Press a key for: %s   (Esc cancels)" % Keybinds.label_of_action(id)
		_refresh_keys())
	_key_buttons[id] = b
	row.add_child(b)
	return row

func _refresh_keys() -> void:
	for id in _key_buttons.keys():
		var b: Button = _key_buttons[id]
		b.text = "press..." if _listening == id else Keybinds.label(id)

func _sens_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = "Mouse sensitivity"
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.03
	s.max_value = 0.3
	s.step = 0.01
	s.value = Keybinds.sens()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(150, 20)
	var val := Label.new()
	val.custom_minimum_size = Vector2(48, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", UIStyle.MUTED)
	val.text = "%.2f" % s.value
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%.2f" % x
		Keybinds.set_sensitivity(x))
	row.add_child(s)
	row.add_child(val)
	return row

## Open mic vs push-to-talk (the key itself is rebound on the CONTROLS tab).
func _voice_mode_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = "Microphone"
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var opt := OptionButton.new()
	opt.add_item("Push to talk (hold %s)" % Keybinds.label(&"ptt"), 1)
	opt.add_item("Open mic", 0)
	opt.selected = opt.get_item_index(int(VoiceChat.mode))
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.item_selected.connect(func(i: int) -> void:
		VoiceChat.mode = opt.get_item_id(i)
		VoiceChat.save()
		var v: Node = EOSManager.voice
		if v != null:
			v.state_changed.emit())
	row.add_child(opt)
	return row

func _voice_slider_row(label: String, output: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 2.0
	s.step = 0.05
	s.value = VoiceChat.output_gain if output else VoiceChat.mic_gain
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(180, 20)
	var val := Label.new()
	val.custom_minimum_size = Vector2(48, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", UIStyle.MUTED)
	val.add_theme_font_override("font", ThemeDB.fallback_font)
	val.text = "%d%%" % int(round(s.value * 100.0))
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%d%%" % int(round(x * 100.0))
		var v: Node = EOSManager.voice
		if v != null:
			if output:
				v.set_output_gain(x)
			else:
				v.set_mic_gain(x)
		else:
			if output:
				VoiceChat.output_gain = x
			else:
				VoiceChat.mic_gain = x
			VoiceChat.save())
	row.add_child(s)
	row.add_child(val)
	return row

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(UIStyle.BRASS_DIM, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _slider_row(label: String, prop: String, lo: float, hi: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(180, 20)
	if _settings:
		s.value = float(_settings.get(prop))
	var val := Label.new()
	val.custom_minimum_size = Vector2(48, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", UIStyle.MUTED)
	val.add_theme_font_override("font", ThemeDB.fallback_font)  # Kenney's "%" reads like an X
	val.text = _fmt(prop, s.value)
	s.value_changed.connect(func(x: float) -> void:
		val.text = _fmt(prop, x)
		if _settings:
			_settings.set(prop, x)
			_settings.changed.emit())
	s.drag_ended.connect(func(_c: bool) -> void:
		var am := get_node_or_null("/root/AudioManager")
		if am:
			am.play(&"card_play"))
	row.add_child(s)
	row.add_child(val)
	return row

func _fmt(prop: String, x: float) -> String:
	if prop == "anim_speed":
		return "%.2fx" % x
	return "%d%%" % int(round(x * 100.0))

func _check_row(label: String, prop: String) -> Control:
	var c := CheckBox.new()
	c.text = label
	c.add_theme_color_override("font_color", UIStyle.CREAM)
	c.add_theme_color_override("font_hover_color", UIStyle.BRASS_LIGHT)
	c.add_theme_color_override("font_pressed_color", UIStyle.CREAM)
	if _settings:
		c.button_pressed = bool(_settings.get(prop))
	c.toggled.connect(func(on: bool) -> void:
		var am := get_node_or_null("/root/AudioManager")
		if am:
			am.play(&"toggle")
		if _settings:
			_settings.set(prop, on)
			if prop == "fullscreen":
				_settings.apply_display()
			_settings.changed.emit())
	return c

func _close() -> void:
	if _settings:
		_settings.commit()
	closed.emit()
	var tw := create_tween().set_parallel()
	tw.tween_property(_panel, "scale", Vector2(0.94, 0.94), 0.12)
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(queue_free)
