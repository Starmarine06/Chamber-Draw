extends Control
const UIStyle := preload("res://scripts/ui_style.gd")
const Sound := preload("res://scripts/sound.gd")

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
	UIStyle.install()
	_build_ui()
	var eos = get_node_or_null("/root/EOSManager")
	if eos:
		eos.login_state_changed.connect(_on_login_state_changed)
		eos.lobby_state_changed.connect(_on_lobby_state_changed)

func _build_ui() -> void:
	var bg := preload("res://scripts/noir_background.gd").new()
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)

	# Title
	var title := UIStyle.make_label("CHAMBER DRAW", 48, UIStyle.BRASS, true)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)
	_flicker(title)

	var subtitle := UIStyle.make_label("Every draw could be your last.", 16, UIStyle.MUTED)
	vbox.add_child(subtitle)
	var version := UIStyle.make_label("v%s" % str(ProjectSettings.get_setting("application/config/version", "")), 12, UIStyle.MUTED)
	vbox.add_child(version)

	var rule := ColorRect.new()
	rule.color = Color(UIStyle.BRASS_DIM, 0.8)
	rule.custom_minimum_size = Vector2(260, 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	# Player count
	vbox.add_child(UIStyle.make_caption("PLAYERS"))

	var pcount_row := HBoxContainer.new()
	pcount_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pcount_row.add_theme_constant_override("separation", 20)
	vbox.add_child(pcount_row)

	var btn_minus := UIStyle.make_button("-", &"secondary", Vector2(50, 42), 22)
	btn_minus.pressed.connect(func(): num_players = maxi(num_players - 1, 2); _refresh())
	pcount_row.add_child(btn_minus)

	player_count_label = UIStyle.make_label("4", 32, UIStyle.CREAM, true)
	player_count_label.custom_minimum_size = Vector2(60, 0)
	pcount_row.add_child(player_count_label)

	var btn_plus := UIStyle.make_button("+", &"secondary", Vector2(50, 42), 22)
	btn_plus.pressed.connect(func(): num_players = mini(num_players + 1, 6); _refresh())
	pcount_row.add_child(btn_plus)

	# Mode
	vbox.add_child(UIStyle.make_caption("GAME MODE"))

	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mode_row)

	var btn_prev := UIStyle.make_button("◀", &"secondary", Vector2(50, 42), 18)
	btn_prev.pressed.connect(func(): game_mode = (game_mode + 1) % 2; _refresh())
	mode_row.add_child(btn_prev)

	mode_label = UIStyle.make_label("Shedding Race", 20, UIStyle.CREAM, true)
	mode_label.custom_minimum_size = Vector2(260, 0)
	mode_row.add_child(mode_label)

	var btn_next := UIStyle.make_button("▶", &"secondary", Vector2(50, 42), 18)
	btn_next.pressed.connect(func(): game_mode = (game_mode + 1) % 2; _refresh())
	mode_row.add_child(btn_next)

	mode_desc = UIStyle.make_label("First to empty hand wins. No elimination.", 14, UIStyle.MUTED)
	mode_desc.name = "ModeDesc"
	mode_desc.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(mode_desc)

	# Your color (offline: you pick, AI get random distinct colors)
	vbox.add_child(UIStyle.make_caption("YOUR COLOR"))

	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", 6)
	vbox.add_child(color_row)

	_menu_swatch_group = ButtonGroup.new()
	_menu_swatch_group.allow_unpress = false
	for i in range(GameGlobals.PALETTE.size()):
		var swatch := UIStyle.make_swatch(GameGlobals.PALETTE[i], GameGlobals.PALETTE_NAMES[i])
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

	var offline_btn := UIStyle.make_button("OFFLINE", &"primary", Vector2(200, 50), 22)
	offline_btn.pressed.connect(_on_offline)
	play_row.add_child(offline_btn)

	var online_btn := UIStyle.make_button("ONLINE", &"confirm", Vector2(200, 50), 22)
	online_btn.pressed.connect(_on_online)
	play_row.add_child(online_btn)

	var aux_row := HBoxContainer.new()
	aux_row.alignment = BoxContainer.ALIGNMENT_CENTER
	aux_row.add_theme_constant_override("separation", 20)
	vbox.add_child(aux_row)

	var tutorial_btn := UIStyle.make_button("TUTORIAL", &"secondary", Vector2(200, 44), 17)
	tutorial_btn.pressed.connect(_on_tutorial)
	aux_row.add_child(tutorial_btn)

	var settings_btn := UIStyle.make_button("SETTINGS", &"secondary", Vector2(200, 44), 17)
	settings_btn.pressed.connect(_on_settings)
	aux_row.add_child(settings_btn)

	var quit_btn := UIStyle.make_button("EXIT GAME", &"danger", Vector2(200, 44), 17)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	# Status label
	status_label = UIStyle.make_label("", 14, UIStyle.MUTED)
	status_label.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(status_label)

	_refresh()
	Sound.play_music(&"menu")

	# Entrance: fade + rise.
	vbox.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(vbox, "modulate:a", 1.0, 0.5)
	tw.tween_property(center, "position:y", 0.0, 0.55).from(24.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Old-neon flicker on the title: mostly steady, occasional quick dips.
func _flicker(l: Label) -> void:
	var tw := create_tween().set_loops()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.55, 0.05)
	tw.tween_property(l, "modulate:a", 1.0, 0.07)
	tw.tween_interval(0.12)
	tw.tween_property(l, "modulate:a", 0.75, 0.04)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.tween_interval(4.1)

func _on_settings() -> void:
	var panel := preload("res://scripts/settings_panel.gd").new()
	add_child(panel)

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
			status_label.add_theme_color_override("font_color", UIStyle.BLOOD_LIGHT)
		else:
			status_label.add_theme_color_override("font_color", UIStyle.MUTED)
