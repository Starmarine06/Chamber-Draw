extends Control

## Main menu for Chamber Draw. Selects player count and game mode,
## then loads either offline (vs AI) or online (EOS multiplayer lobby).

var num_players: int = 4
var game_mode: int = 0  # 0 = Shedding Race, 1 = Last One Standing

var player_count_label: Label
var mode_label: Label
var mode_desc: Label
var status_label: Label
var _menu_swatch_group: ButtonGroup

func _ready() -> void:
	_build_ui()
	var eos = get_node_or_null("/root/EOSManager")
	if eos:
		eos.login_state_changed.connect(_on_login_state_changed)
		eos.lobby_state_changed.connect(_on_lobby_state_changed)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var vignette := ColorRect.new()
	vignette.color = Color(0, 0, 0, 0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "CHAMBER DRAW"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Every draw could be your last."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	# Player count
	var pcount_label := Label.new()
	pcount_label.text = "PLAYERS"
	pcount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcount_label.add_theme_font_size_override("font_size", 16)
	pcount_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	vbox.add_child(pcount_label)

	var pcount_row := HBoxContainer.new()
	pcount_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pcount_row.add_theme_constant_override("separation", 20)
	vbox.add_child(pcount_row)

	var btn_minus := _make_button("-", Color(0.25, 0.2, 0.3), 50, 44)
	btn_minus.pressed.connect(func(): num_players = maxi(num_players - 1, 2); _refresh())
	pcount_row.add_child(btn_minus)

	player_count_label = Label.new()
	player_count_label.text = "4"
	player_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_count_label.custom_minimum_size = Vector2(60, 0)
	player_count_label.add_theme_font_size_override("font_size", 32)
	player_count_label.add_theme_color_override("font_color", Color.WHITE)
	pcount_row.add_child(player_count_label)

	var btn_plus := _make_button("+", Color(0.25, 0.2, 0.3), 50, 44)
	btn_plus.pressed.connect(func(): num_players = mini(num_players + 1, 6); _refresh())
	pcount_row.add_child(btn_plus)

	# Mode
	var mode_title := Label.new()
	mode_title.text = "GAME MODE"
	mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_title.add_theme_font_size_override("font_size", 16)
	mode_title.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	vbox.add_child(mode_title)

	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mode_row)

	var btn_prev := _make_button("<", Color(0.25, 0.2, 0.3), 50, 44)
	btn_prev.pressed.connect(func(): game_mode = (game_mode + 1) % 2; _refresh())
	mode_row.add_child(btn_prev)

	mode_label = Label.new()
	mode_label.text = "Shedding Race"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.custom_minimum_size = Vector2(200, 0)
	mode_label.add_theme_font_size_override("font_size", 20)
	mode_label.add_theme_color_override("font_color", Color.WHITE)
	mode_row.add_child(mode_label)

	var btn_next := _make_button(">", Color(0.25, 0.2, 0.3), 50, 44)
	btn_next.pressed.connect(func(): game_mode = (game_mode + 1) % 2; _refresh())
	mode_row.add_child(btn_next)

	mode_desc = Label.new()
	mode_desc.name = "ModeDesc"
	mode_desc.text = "First to empty hand wins. No elimination."
	mode_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_desc.add_theme_font_size_override("font_size", 13)
	mode_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	mode_desc.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(mode_desc)

	# Your color (offline: you pick, AI get random distinct colors)
	var color_title := Label.new()
	color_title.text = "YOUR COLOR"
	color_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_title.add_theme_font_size_override("font_size", 16)
	color_title.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	vbox.add_child(color_title)

	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", 6)
	vbox.add_child(color_row)

	_menu_swatch_group = ButtonGroup.new()
	_menu_swatch_group.allow_unpress = false
	for i in range(GameGlobals.PALETTE.size()):
		var swatch := _make_swatch_button(i)
		swatch.button_group = _menu_swatch_group
		swatch.button_pressed = i == GameGlobals.my_color_idx
		swatch.pressed.connect(_on_color_picked.bind(i))
		color_row.add_child(swatch)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)

	# Play buttons
	var play_row := HBoxContainer.new()
	play_row.alignment = BoxContainer.ALIGNMENT_CENTER
	play_row.add_theme_constant_override("separation", 20)
	vbox.add_child(play_row)

	var offline_btn := _make_button("OFFLINE", Color(0.18, 0.5, 0.55), 200, 50)
	offline_btn.add_theme_font_size_override("font_size", 24)
	offline_btn.pressed.connect(_on_offline)
	play_row.add_child(offline_btn)

	var online_btn := _make_button("ONLINE", Color(0.18, 0.55, 0.25), 200, 50)
	online_btn.add_theme_font_size_override("font_size", 24)
	online_btn.pressed.connect(_on_online)
	play_row.add_child(online_btn)

	var tutorial_btn := _make_button("TUTORIAL", Color(0.55, 0.45, 0.15), 200, 46)
	tutorial_btn.add_theme_font_size_override("font_size", 18)
	tutorial_btn.pressed.connect(_on_tutorial)
	vbox.add_child(tutorial_btn)

	var quit_btn := _make_button("EXIT GAME", Color(0.55, 0.16, 0.16), 200, 46)
	quit_btn.add_theme_font_size_override("font_size", 18)
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	# Status label
	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	status_label.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(status_label)

	_refresh()

func _make_button(text: String, col: Color, w: int, h: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(w, h)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = col
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.content_margin_left = 8
	style_normal.content_margin_right = 8
	style_normal.content_margin_top = 4
	style_normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

func _make_swatch_button(idx: int) -> Button:
	var col: Color = GameGlobals.PALETTE[idx]
	var btn := Button.new()
	btn.text = GameGlobals.PALETTE_NAMES[idx]
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(48, 34)
	btn.add_theme_font_size_override("font_size", 11)
	var font_col := Color.WHITE if col.get_luminance() < 0.5 else Color(0.12, 0.1, 0.06)
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", font_col)
	btn.add_theme_color_override("font_pressed_color", font_col)

	var normal := StyleBoxFlat.new()
	normal.bg_color = col.darkened(0.12)
	normal.border_color = col.darkened(0.3)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = col
	hover.border_color = col.lightened(0.35)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = col
	pressed.border_color = Color.WHITE
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn

func _on_color_picked(idx: int) -> void:
	GameGlobals.my_color_idx = idx

func _refresh() -> void:
	if player_count_label:
		player_count_label.text = str(num_players)
	if mode_label:
		mode_label.text = "Shedding Race" if game_mode == 0 else "Last One Standing"
		if mode_desc:
			if game_mode == 0:
				mode_desc.text = "First to empty hand wins. Live = penalty cards + skipped turn."
			else:
				mode_desc.text = "Last player alive wins. Live = elimination."

func _on_offline() -> void:
	var globals := get_node_or_null("/root/GameGlobals")
	if globals:
		globals.num_players = num_players
		globals.game_mode = game_mode
		globals.is_online = false
		globals.is_tutorial = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_online() -> void:
	var globals := get_node_or_null("/root/GameGlobals")
	if globals:
		globals.num_players = num_players
		globals.game_mode = game_mode
		globals.is_online = true
		globals.is_tutorial = false

	var eos = get_node_or_null("/root/EOSManager")
	if not eos:
		_set_status("EOSManager not available.", true)
		return

	if eos.logged_in:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		return

	_set_status("Logging in to Epic Online Services...", false)
	eos.request_login()

func _on_tutorial() -> void:
	var globals := get_node_or_null("/root/GameGlobals")
	if globals:
		globals.num_players = 4
		globals.game_mode = 0
		globals.is_online = false
		globals.is_tutorial = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit() -> void:
	get_tree().quit()

func _on_login_state_changed(login_state: String) -> void:
	match login_state:
		"logged_in":
			_set_status("Logged in. Loading lobby...", false)
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		"login_failed":
			_set_status("Login failed. Check your network and EOS config.", true)
		"logging_in":
			_set_status("Connecting to Epic Online Services...", false)

func _on_lobby_state_changed(_lobby_state: String) -> void:
	pass

func _set_status(text: String, is_error: bool) -> void:
	if status_label:
		status_label.text = text
		if is_error:
			status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.25))
		else:
			status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
