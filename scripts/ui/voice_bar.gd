extends HBoxContainer

## Compact voice-chat control strip, used in the online lobby and the in-game HUD.
## Shows the mic state, who is talking, and buttons for mute / deafen / open-mic vs
## push-to-talk / per-player mute. Hidden entirely when there is no voice room.

const UIStyle := preload("res://scripts/ui_style.gd")
const Keybinds := preload("res://scripts/keybinds.gd")

var _voice: Node
var _mic_btn: Button
var _deaf_btn: Button
var _mode_btn: Button
var _players_btn: MenuButton
var _talk_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_voice = EOSManager.voice
	if _voice == null:
		visible = false
		return
	_mic_btn = UIStyle.make_button("", &"secondary", Vector2(170, 32), 13)
	_mic_btn.pressed.connect(func() -> void: _voice.toggle_mic_mute())
	add_child(_mic_btn)
	_deaf_btn = UIStyle.make_button("DEAFEN", &"secondary", Vector2(86, 32), 12)
	_deaf_btn.tooltip_text = "Silence everyone else and your mic (%s)" % Keybinds.label(&"deafen")
	_deaf_btn.pressed.connect(func() -> void: _voice.toggle_deafen())
	add_child(_deaf_btn)
	_mode_btn = UIStyle.make_button("", &"secondary", Vector2(104, 32), 12)
	_mode_btn.pressed.connect(func() -> void:
		_voice.set_mode(0 if int(_voice.mode) == 1 else 1))
	add_child(_mode_btn)
	_players_btn = MenuButton.new()
	_players_btn.text = "PLAYERS"
	_players_btn.custom_minimum_size = Vector2(86, 32)
	_players_btn.add_theme_font_size_override("font_size", 12)
	_players_btn.tooltip_text = "Mute individual players (only for you)"
	_players_btn.get_popup().id_pressed.connect(_on_player_pressed)
	add_child(_players_btn)
	_talk_label = UIStyle.make_label("", 13, UIStyle.BRASS_LIGHT)
	add_child(_talk_label)

	_voice.state_changed.connect(_refresh)
	_voice.speaking_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _voice != null and is_instance_valid(_voice):
		if _voice.state_changed.is_connected(_refresh):
			_voice.state_changed.disconnect(_refresh)
		if _voice.speaking_changed.is_connected(_refresh):
			_voice.speaking_changed.disconnect(_refresh)


func _others() -> Array:
	var out: Array = []
	var l: HLobby = EOSManager.lobby
	if l == null:
		return out
	for m in l.members:
		if m.product_user_id != HAuth.product_user_id:
			out.append(m)
	return out


func _refresh() -> void:
	if _voice == null:
		return
	visible = _voice.available
	if not visible:
		return
	_mic_btn.text = _voice.status_text()
	_mic_btn.tooltip_text = "Click or press %s to mute / unmute your mic" % Keybinds.label(&"mute_mic")
	_deaf_btn.text = "HEAR" if _voice.deafened else "DEAFEN"
	_mode_btn.text = "OPEN MIC" if int(_voice.mode) == 0 else "PUSH TO TALK"
	_mode_btn.tooltip_text = "Switch between open mic and push-to-talk (hold %s)" % Keybinds.label(&"ptt")

	var names: PackedStringArray = []
	for m in (EOSManager.lobby.members if EOSManager.lobby != null else []):
		if _voice.is_speaking(m.product_user_id):
			names.append("you" if m.product_user_id == HAuth.product_user_id else EOSManager._member_display_name(m))
	_talk_label.text = ("🔊 " + ", ".join(names)) if not names.is_empty() else ""

	var popup := _players_btn.get_popup()
	popup.clear()
	var i := 0
	for m in _others():
		popup.add_check_item(EOSManager._member_display_name(m) + "  (muted)" if _voice.is_player_muted(m.product_user_id) else EOSManager._member_display_name(m), i)
		popup.set_item_checked(i, _voice.is_player_muted(m.product_user_id))
		popup.set_item_metadata(i, m.product_user_id)
		i += 1
	_players_btn.disabled = i == 0


func _on_player_pressed(idx: int) -> void:
	var popup := _players_btn.get_popup()
	var item := popup.get_item_index(idx)
	_voice.toggle_player_mute(str(popup.get_item_metadata(item)))
