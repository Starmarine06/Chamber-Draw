extends Control

## Online lobby. Entry point for EOS multiplayer: host or join by 6-char code.
## Features an Among Us style room code generation, copy button, and live roster.
## Depends on the EOSManager autoload (login + lobby + P2P transport).

enum LobbyView { CONNECTING, LOGIN_FAILED, CHOOSE, HOSTING, JOINING, WAITING }

var view: int = LobbyView.CONNECTING

# UI references
var status_label: Label
var choose_panel: VBoxContainer
var room_panel: VBoxContainer
var code_field: LineEdit
var room_code_label: Label
var copy_btn: Button
var mode_button: Button
var mode_label_client: Label
var roster_label: RichTextLabel
var start_button: Button
var back_button: Button
var color_panel: VBoxContainer
var _swatch_group: ButtonGroup
var session_mode: int = 0
var _copy_timer: SceneTreeTimer = null

func _ready() -> void:
	_build_ui()
	EOSManager.login_state_changed.connect(_on_login_state)
	EOSManager.lobby_state_changed.connect(_on_lobby_state)
	EOSManager.lobby_updated.connect(_refresh_roster)
	EOSManager.roster_updated.connect(_refresh_roster)
	if not EOSManager.logged_in:
		_set_view(LobbyView.CONNECTING)
		EOSManager.request_login()
	else:
		_set_view(LobbyView.CHOOSE)

func _exit_tree() -> void:
	if EOSManager.login_state_changed.is_connected(_on_login_state):
		EOSManager.login_state_changed.disconnect(_on_login_state)
	if EOSManager.lobby_state_changed.is_connected(_on_lobby_state):
		EOSManager.lobby_state_changed.disconnect(_on_lobby_state)
	if EOSManager.lobby_updated.is_connected(_refresh_roster):
		EOSManager.lobby_updated.disconnect(_refresh_roster)
	if EOSManager.roster_updated.is_connected(_refresh_roster):
		EOSManager.roster_updated.disconnect(_refresh_roster)

#region UI Construction

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	main_vbox.custom_minimum_size = Vector2(460, 0)
	center.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "ONLINE LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	main_vbox.add_child(title)

	# Status Label
	status_label = Label.new()
	status_label.text = "Connecting to Epic Online Services..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	main_vbox.add_child(status_label)

	# ─────────────────────────────────────────────────────────────────────────────
	# VIEW 1: CHOOSE PANEL (Host Game / Join Game)
	# ─────────────────────────────────────────────────────────────────────────────
	choose_panel = VBoxContainer.new()
	choose_panel.add_theme_constant_override("separation", 14)
	main_vbox.add_child(choose_panel)

	# Host Box
	var host_card := _make_panel_container(Color(0.12, 0.09, 0.18))
	var host_box := VBoxContainer.new()
	host_box.add_theme_constant_override("separation", 8)
	host_card.add_child(host_box)

	var host_title := Label.new()
	host_title.text = "HOST A NEW GAME"
	host_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_title.add_theme_font_size_override("font_size", 15)
	host_title.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	host_box.add_child(host_title)

	var host_btn := _make_button("CREATE ROOM", Color(0.18, 0.55, 0.25), -1, 46)
	host_btn.pressed.connect(_on_host_pressed)
	host_box.add_child(host_btn)
	choose_panel.add_child(host_card)

	# Join Box
	var join_card := _make_panel_container(Color(0.12, 0.09, 0.18))
	var join_box := VBoxContainer.new()
	join_box.add_theme_constant_override("separation", 8)
	join_card.add_child(join_box)

	var join_title := Label.new()
	join_title.text = "JOIN PRIVATE ROOM"
	join_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_title.add_theme_font_size_override("font_size", 15)
	join_title.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	join_box.add_child(join_title)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	join_box.add_child(join_row)

	code_field = LineEdit.new()
	code_field.placeholder_text = "ENTER 6-LETTER CODE"
	code_field.text = ""
	code_field.max_length = 6
	code_field.custom_minimum_size = Vector2(260, 44)
	code_field.add_theme_font_size_override("font_size", 18)
	code_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_field.text_changed.connect(func(t: String):
		code_field.text = t.to_upper()
		code_field.caret_column = code_field.text.length()
	)
	code_field.text_submitted.connect(func(_t: String): _on_join_pressed())
	join_row.add_child(code_field)

	var join_btn := _make_button("JOIN", Color(0.2, 0.45, 0.7), 120, 44)
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)
	choose_panel.add_child(join_card)

	# ─────────────────────────────────────────────────────────────────────────────
	# VIEW 2: ROOM PANEL (Inside Room / Waiting for Players)
	# ─────────────────────────────────────────────────────────────────────────────
	room_panel = VBoxContainer.new()
	room_panel.add_theme_constant_override("separation", 12)
	room_panel.visible = false
	main_vbox.add_child(room_panel)

	# Code Banner Card (Among Us style)
	var code_card := _make_panel_container(Color(0.15, 0.12, 0.22))
	var code_box := VBoxContainer.new()
	code_box.add_theme_constant_override("separation", 4)
	code_card.add_child(code_box)

	var room_title := Label.new()
	room_title.text = "ROOM CODE"
	room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_title.add_theme_font_size_override("font_size", 13)
	room_title.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	code_box.add_child(room_title)

	var code_display_row := HBoxContainer.new()
	code_display_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_display_row.add_theme_constant_override("separation", 12)
	code_box.add_child(code_display_row)

	room_code_label = Label.new()
	room_code_label.text = "------"
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code_label.add_theme_font_size_override("font_size", 38)
	room_code_label.add_theme_color_override("font_color", Color(0.98, 0.9, 0.4))
	room_code_label.add_theme_constant_override("outline_size", 4)
	room_code_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	code_display_row.add_child(room_code_label)

	copy_btn = _make_button("COPY", Color(0.3, 0.3, 0.4), 80, 36)
	copy_btn.add_theme_font_size_override("font_size", 14)
	copy_btn.pressed.connect(_on_copy_code_pressed)
	code_display_row.add_child(copy_btn)

	room_panel.add_child(code_card)

	# Game Mode
	mode_button = _make_button("MODE: Shedding Race", Color(0.25, 0.2, 0.3), -1, 38)
	mode_button.add_theme_font_size_override("font_size", 16)
	mode_button.pressed.connect(func():
		session_mode = (session_mode + 1) % 2
		mode_button.text = "MODE: Shedding Race" if session_mode == 0 else "MODE: Last One Standing"
	)
	room_panel.add_child(mode_button)

	mode_label_client = Label.new()
	mode_label_client.text = "MODE: Shedding Race"
	mode_label_client.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label_client.add_theme_font_size_override("font_size", 15)
	mode_label_client.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	room_panel.add_child(mode_label_client)

	# Roster Box
	var roster_card := _make_panel_container(Color(0.1, 0.08, 0.15))
	var roster_box := VBoxContainer.new()
	roster_card.add_child(roster_box)

	roster_label = RichTextLabel.new()
	roster_label.bbcode_enabled = true
	roster_label.scroll_active = false
	roster_label.fit_content = true
	roster_label.add_theme_font_size_override("normal_font_size", 15)
	roster_label.custom_minimum_size = Vector2(400, 0)
	roster_box.add_child(roster_label)
	room_panel.add_child(roster_card)

	# Start Button (Host only)
	start_button = _make_button("START GAME", Color(0.85, 0.55, 0.12), -1, 48)
	start_button.disabled = true
	start_button.pressed.connect(_on_start_pressed)
	room_panel.add_child(start_button)

	# ─────────────────────────────────────────────────────────────────────────────
	# YOUR COLOR PICKER (Common to both screens)
	# ─────────────────────────────────────────────────────────────────────────────
	color_panel = VBoxContainer.new()
	color_panel.add_theme_constant_override("separation", 6)
	main_vbox.add_child(color_panel)

	var color_title := Label.new()
	color_title.text = "YOUR COLOR"
	color_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_title.add_theme_font_size_override("font_size", 13)
	color_title.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	color_panel.add_child(color_title)

	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", 6)
	color_panel.add_child(color_row)

	_swatch_group = ButtonGroup.new()
	_swatch_group.allow_unpress = false
	for i in range(GameGlobals.PALETTE.size()):
		var swatch := _make_swatch_button(i)
		swatch.button_group = _swatch_group
		swatch.button_pressed = i == GameGlobals.my_color_idx
		swatch.pressed.connect(_on_color_picked.bind(i))
		color_row.add_child(swatch)

	# Back / Leave Button
	back_button = _make_button("BACK", Color(0.35, 0.18, 0.2), -1, 40)
	back_button.add_theme_font_size_override("font_size", 16)
	back_button.pressed.connect(_on_back_pressed)
	main_vbox.add_child(back_button)

	_set_view(view)

func _make_panel_container(bg_color: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", style)
	return pc

func _make_button(text: String, col: Color, w: int, h: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(w if w > 0 else 200, h)
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = col
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style_normal)
	var style_hover := style_normal.duplicate()
	style_hover.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", style_hover)
	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	var style_disabled := StyleBoxFlat.new()
	style_disabled.bg_color = Color(0.15, 0.15, 0.17)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

func _make_swatch_button(idx: int) -> Button:
	var col: Color = GameGlobals.PALETTE[idx]
	var btn := Button.new()
	btn.text = GameGlobals.PALETTE_NAMES[idx]
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(48, 32)
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

#endregion

#region View State Management

func _set_view(new_view: int) -> void:
	view = new_view
	if not is_node_ready():
		return

	var is_in_room := (view == LobbyView.HOSTING or view == LobbyView.WAITING)
	choose_panel.visible = (view == LobbyView.CHOOSE)
	room_panel.visible = is_in_room
	if code_field:
		code_field.editable = (view == LobbyView.CHOOSE)

	if is_in_room:
		back_button.text = "LEAVE ROOM"
		room_code_label.text = EOSManager.join_code if not EOSManager.join_code.is_empty() else "------"
		var is_host := (view == LobbyView.HOSTING)
		mode_button.visible = is_host
		mode_label_client.visible = not is_host
		start_button.visible = is_host
	else:
		back_button.text = "BACK TO MENU"

	match new_view:
		LobbyView.CONNECTING:
			status_label.text = "Connecting to Epic Online Services..."
		LobbyView.LOGIN_FAILED:
			status_label.text = "Epic login failed. Check EOS credentials and network connection."
		LobbyView.CHOOSE:
			status_label.text = "Logged in as: %s" % EOSManager.get_display_name()
		LobbyView.HOSTING:
			status_label.text = "Room created! Share the code with your friends."
		LobbyView.JOINING:
			status_label.text = "Joining room..."
		LobbyView.WAITING:
			status_label.text = "In room! Waiting for host to start the game..."

	_refresh_roster()

#endregion

#region Event Handlers

func _on_login_state(state: String) -> void:
	match state:
		"logged_in":
			_set_view(LobbyView.CHOOSE)
		"login_failed":
			_set_view(LobbyView.LOGIN_FAILED)

func _on_lobby_state(state: String) -> void:
	match state:
		"created":
			_set_view(LobbyView.HOSTING)
		"joined":
			_set_view(LobbyView.WAITING)
		"started":
			get_tree().change_scene_to_file("res://scenes/game.tscn")
		"left":
			_set_view(LobbyView.CHOOSE if EOSManager.logged_in else LobbyView.LOGIN_FAILED)
		"error":
			_set_view(LobbyView.CHOOSE if EOSManager.logged_in else LobbyView.LOGIN_FAILED)
			status_label.text = "Room error or room not found. Check code and try again."

func _on_host_pressed() -> void:
	status_label.text = "Creating room..."
	EOSManager.create_lobby()

func _on_join_pressed() -> void:
	var code := code_field.text.strip_edges().to_upper()
	if code.length() < 4:
		status_label.text = "Please enter a valid room code (at least 4 characters)."
		return
	status_label.text = "Searching for room '%s'..." % code
	_set_view(LobbyView.JOINING)
	EOSManager.join_lobby(code)

func _on_copy_code_pressed() -> void:
	if EOSManager.join_code.is_empty():
		return
	DisplayServer.clipboard_set(EOSManager.join_code)
	copy_btn.text = "✓ COPIED"
	if _copy_timer:
		_copy_timer.timeout.disconnect(_reset_copy_btn)
	_copy_timer = get_tree().create_timer(1.8)
	_copy_timer.timeout.connect(_reset_copy_btn)

func _reset_copy_btn() -> void:
	if is_instance_valid(copy_btn):
		copy_btn.text = "COPY"

func _on_color_picked(idx: int) -> void:
	GameGlobals.my_color_idx = idx
	EOSManager.set_my_color(idx)
	_refresh_roster()

func _on_start_pressed() -> void:
	start_button.disabled = true
	status_label.text = "Starting game..."
	if not EOSManager.host_start_game(session_mode):
		status_label.text = "Cannot start: need at least 2 connected players."
		start_button.disabled = not _host_can_start()
		_refresh_roster()

func _on_back_pressed() -> void:
	if view == LobbyView.HOSTING or view == LobbyView.WAITING:
		EOSManager.leave_lobby()
		_set_view(LobbyView.CHOOSE)
	else:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _refresh_roster() -> void:
	if not is_node_ready() or not room_panel.visible:
		return

	if EOSManager.is_host and EOSManager.roster.size() > 0:
		var lines: Array[String] = []
		lines.append("[b]Players in Room (%d/%s)[/b]" % [EOSManager.roster.size(), EOSManager.max_members])
		for entry in EOSManager.roster:
			var mark := "[color=#4caf50]● Connected[/color]" if entry.connected else "[color=#e57373]○ Offline[/color]"
			var who: String = entry.display_name
			if entry.is_host:
				who += " [color=#f0a020][HOST][/color]"
			if entry.puid == EOSManager.get_product_user_id():
				who += " (You)"
			var col_html: String = EOSManager.color_for_entry(entry).to_html(false)
			lines.append("  [color=#%s]■[/color] %s  —  %s" % [col_html, who, mark])
		roster_label.text = "\n".join(lines)
		start_button.disabled = not _host_can_start()
		if not _host_can_start():
			status_label.text = "Waiting for at least 1 more player to join (2 players minimum)..."
		else:
			status_label.text = "All players ready! You can start the game."
	elif EOSManager.lobby != null and EOSManager.lobby.members.size() > 0:
		var lines: Array[String] = []
		lines.append("[b]Players in Room (%d/%s)[/b]" % [EOSManager.lobby.members.size(), EOSManager.max_members])
		for member in EOSManager.lobby.members:
			var name := member.display_name
			if name.is_empty():
				name = member.product_user_id.substr(0, 8)
			if member.is_owner():
				name += " [color=#f0a020][HOST][/color]"
			if member.product_user_id == EOSManager.get_product_user_id():
				name += " (You)"
			var col_html: String = EOSManager.member_color(member).to_html(false)
			lines.append("  [color=#%s]■[/color] %s" % [col_html, name])
		roster_label.text = "\n".join(lines)

func _host_can_start() -> bool:
	if EOSManager.roster.size() < 2:
		return false
	for entry in EOSManager.roster:
		if not entry.connected:
			return false
	return true

#endregion