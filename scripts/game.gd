extends Control

## Full game board for Chamber Draw (3D table edition).
## The 3D world is the editor-built scene `scenes/game_3d.tscn` (poker table +
## Marker3D nodes for decks and player seats), rendered full-screen in a
## SubViewport. The local player's hand is summoned at the CenterCards marker
## of `scenes/player_ui.tscn`. Opponent seats show a Kenney character model at
## their marker — only the local player's cards are ever rendered (Uno-style).
## All UI chrome uses the Kenney UI pack textures and sounds.

# ── State machine ──
## Game UI state machine. WAITING = idling between turns / awaiting network
## snapshots; HUMAN_(COLOR|TARGET|PILE|DECK|PEEK) selects popups; AI_THINKING
## and the rest are self-explanatory transitions driven by _check_turn().
enum State { WAITING, HUMAN_TURN, HUMAN_COLOR_SELECT, HUMAN_TARGET_SELECT,
		 HUMAN_PILE_SELECT, HUMAN_DECK_CHOICE, HUMAN_PEEK_SELECT,
		 AI_THINKING, CHAMBER_REVEAL, DIFFUSE_DECISION, GAME_OVER, JUMP_IN,
		 DEALING, FORCED_DRAW_DECK_CHOICE, SPECTATING, BOMB_VOTE, LAST_SHOT }

var state: State = State.WAITING
var game: GameState
var card_nodes: Array[CardNode] = []
var _card_node_pool: Array[CardNode] = []  # Reusable CardNodes to avoid allocation churn
var _pending_card: Card = null
var _pending_options: Dictionary = {}
var _pending_next_step: String = ""  # after color choice: "stack", "target", or "peek"
var _ai_timer: float = 0.0

# ── Online state ──
var own_index: int = 0          ## Local player index in game.players
var is_online: bool = false     ## True when connected via EOS
var _eos = null                 ## Cached EOSManager autoload reference
var _got_first_snapshot := false
var _hello_timer := 0.0
var _pending_chamber_reveal: Dictionary = {}
var _last_intent_time: float = 0.0  ## For send_intent RPC rate limiting
const INTENT_COOLDOWN: float = 0.1

# ── UI references ──
var turn_label: Label
var active_display: Label
var overlay: ColorRect
var overlay_vbox: VBoxContainer
var chamber_text: Label
var chamber_count: Label
var notification_label: Label
var _notification_timer: float = 0.0
var _turn_border: Panel
var _turn_border_style: StyleBoxFlat

# ── Jump-in window (matching-card response) ──
var _jump_in_window := false
var _jump_in_timer := 0.0
var _pending_ai_jump_index := -1
var _ai_jump_delay := 0.0
var _jump_prompt: VBoxContainer
const JUMP_WINDOW_TIME := 4.0

# ── Pause (offline only) ──
var _paused := false
var _pause_overlay: ColorRect

# ── Guided tutorial (driven by tutorial_director.gd) ──
## Emitted after each tutorial-relevant player action completes, so the
## director can await the exact step it programmed. kind: "card", "draw",
## "forced_draw_choice", "diffuse_use", "chamber_done", "end_turn",
## "jump_in_window", "jump_pass", "jump_done".
signal tutorial_action_done(kind: String, details: Dictionary)
var is_tutorial := false
var _tut_input_hands: Array[int] = []  # empty = any hand card playable
var _tut_allow_draw := false
var _tut_allow_end_turn := false

# ── Sound effects (Kenney UI pack) ──
var _sfx_card_play: AudioStreamPlayer
var _sfx_card_draw: AudioStreamPlayer
var _sfx_button: AudioStreamPlayer
var _sfx_click_b: AudioStreamPlayer
var _sfx_switch_a: AudioStreamPlayer
var _sfx_switch_b: AudioStreamPlayer
var _sfx_tap_b: AudioStreamPlayer

# ── 3D table view (instanced game_3d.tscn inside a SubViewport) ──
var _viewport_container: SubViewportContainer
var _viewport_3d: SubViewport
var _camera_3d: Camera3D
var _world_root_3d: Node3D
var _table_center: Vector3 = Vector3.ZERO
var _char_scale: float = 0.3
var _player_cameras: Array[Camera3D] = []  # Camera for each player seat

# Markers read from game_3d.tscn
var _marker_deck_a: Marker3D
var _marker_deck_b: Marker3D
var _marker_discard: Marker3D
var _marker_players: Array[Marker3D] = []

# 3D piles / labels
var _pile_a_mesh: MeshInstance3D
var _pile_b_mesh: MeshInstance3D
var _discard_sprite: Sprite3D
var _discard_vp: SubViewport       # renders the top discard card like a hand UI card
var _discard_card_node: CardNode
var _pile_a_mat: StandardMaterial3D
var _pile_b_mat: StandardMaterial3D
var _snapshot_bombs_a: int = -1
var _snapshot_bombs_b: int = -1
var _pile_a_count_label: Label3D
var _pile_b_count_label: Label3D
var _opponent_nodes_3d: Array[Node3D] = []
var _char_node_by_index: Dictionary = {}  # seat -> Node3D (for respawn pop-in)

# ── Local player hand (player_ui.tscn) ──
var _player_ui: Control
var _hand_marker: Marker2D
var _own_label: Label
var _draw_btn_a: Button
var _draw_btn_b: Button
var _draw_zones_init := false
var _last_zone_size: Vector2i = Vector2i.ZERO

const HANDCARD_W := 72.0
const HANDCARD_H := 108.0
const PLAYABLE_LIFT := 16.0 ## Pixels a playable card sits above the rest of the hand
const CHAR_SEAT_OFFSET := 1.15  # fraction of char scale to lower onto the table felt

# ── Draw-then-play state ──
var _drew_this_turn := false  # true after a voluntary draw; turn ends on play or End Turn
var _was_my_turn := false     # guards the "YOUR TURN" banner against re-triggering
var _end_turn_btn: Button = null  # "End Turn" button shown after drawing

# ── Overcharge state ──
var _overcharge_notified := false  # true after showing the overcharge activation banner

# ── Dealing animation state ──
var _deal_timer: float = 0.0
var _deal_phase: int = 0  # 0 = dealing cards, 1 = flipping starter, 2 = picking first player
var _deal_player_idx: int = 0  # which player we're dealing to
var _deal_card_idx: int = 0   # which card in their hand we're dealing
var _deal_total_cards: int = 0  # total cards to deal (STARTING_HAND_SIZE * num_players)
var _deal_cards_dealt: int = 0  # cards dealt so far
var _deal_card_delay: float = 0.08  # seconds between each card

# ── Turn timer ──
const TURN_TIME_LIMIT := 30.0  # seconds per turn
var _turn_timer: float = TURN_TIME_LIMIT
var _turn_timer_ring: Control = null  # Visual circular timer
var _turn_timer_label: Label = null  # Timer text

# ── Forced draw (Draw Two/Four/Ten) ──
var _pending_ai_forced_draw_pile: String = ""  # AI's choice for forced draw

# ── Kenney UI pack textures ──
const KENNEY_UI := "res://assets/imported_assets/kenney_ui-pack/PNG/Blue/Default/"
const _UI_TEX := {
	"button": preload(KENNEY_UI + "button_rectangle_depth_flat.png"),
	"button_hover": preload(KENNEY_UI + "button_rectangle_gloss.png"),
	"button_pressed": preload(KENNEY_UI + "button_rectangle_depth_flat.png"),
}


func _ready() -> void:
	_eos = get_node_or_null("/root/EOSManager")
	_build_ui()
	_start_game()

func _process(delta: float) -> void:
	if _paused:
		return  # all timers/animations frozen while paused

	if _turn_border and _turn_border.visible:
		_update_turn_border()

	if state == State.DEALING:
		_process_dealing(delta)
		return

	if state == State.AI_THINKING:
		_ai_timer -= delta
		if _ai_timer <= 0:
			_process_ai_turn()

	# AI bomb voting: AI players vote randomly after a short delay.
	if game.bomb_vote_active and not is_online and not is_tutorial:
		for i in range(game.players.size()):
			if i != own_index and not game.players[i].eliminated and not game.bomb_votes.has(i):
				# AI votes randomly (60% chance to continue)
				if randf() < 0.6:
					game.cast_vote(i, true)
				else:
					game.cast_vote(i, false)

	# Turn timer countdown (only during active turns, not jump-ins or popups).
	var timer_active := state == State.HUMAN_TURN or state == State.AI_THINKING
	if is_tutorial:
		timer_active = false
	if timer_active and not game.game_over and not game.jump_in_open:
		_turn_timer -= delta
		_update_timer_ui()
		if _turn_timer <= 0:
			_on_turn_timer_expired()
	elif state != State.DEALING and state != State.WAITING:
		# In popups (color select, target select, etc.) — hide the timer visually
		# but don't reset it (it resumes when the popup closes).
		_hide_timer_ui()

	# Online clients resend a "hello" intent until the first snapshot lands.
	if is_online and not is_host_here() and not _got_first_snapshot:
		_hello_timer -= delta
		if _hello_timer <= 0:
			_hello_timer = 0.6
			send_intent({"kind": "hello"})

	if _notification_timer > 0:
		_notification_timer -= delta
		if _notification_timer <= 0 and notification_label:
			notification_label.visible = false
			notification_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))  # Reset to yellow

	# Jump-in window: AI (offline) answers on a delay; the window times out.
	if _jump_in_window:
		_jump_in_timer += delta
		if _pending_ai_jump_index >= 0 and _jump_in_timer >= _ai_jump_delay:
			var ai_who := _pending_ai_jump_index
			_pending_ai_jump_index = -1
			_ai_jump_in(ai_who)
		elif (not is_online or is_host_here()) and not is_tutorial and _jump_in_timer >= JUMP_WINDOW_TIME:
			_close_jump_window()

	# Once the viewport has a size, position the invisible deck click zones;
	# re-project them if the window resizes. Also keep the 3D render target
	# matched to the window so text/geometry stay crisp (no unchecked upscale).
	if _viewport_3d and size.x > 0 and size.y > 0:
		if not _draw_zones_init:
			_draw_zones_init = true
			_viewport_3d.size = Vector2i(int(size.x), int(size.y))
			_last_zone_size = size
			_reposition_draw_zones()
		elif size != Vector2(_last_zone_size):
			_last_zone_size = size
			_viewport_3d.size = Vector2i(int(size.x), int(size.y))
			_reposition_draw_zones()

# ── UI Construction ──────────────────────────────────────────────────

func _build_ui() -> void:
	# ── Background ──
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ── 3D table world (game_3d.tscn) ──
	_setup_3d_viewport()

	# ── Local player UI (player_ui.tscn: hand summoned at CenterCards) ──
	_setup_player_ui()

	# ── Top bar (Kenney-styled) ──
	var top_bar := PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 44)
	top_bar.offset_bottom = 44
	top_bar.add_theme_stylebox_override("panel", _make_kenney_style(_UI_TEX["button"]))
	add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 24)
	top_bar.add_child(top_hbox)

	turn_label = Label.new()
	turn_label.text = "Your Turn"
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	top_hbox.add_child(turn_label)

	active_display = Label.new()
	active_display.text = "Color: RED | Number: -"
	active_display.add_theme_font_size_override("font_size", 16)
	active_display.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	top_hbox.add_child(active_display)

	# Pause button (pushes to the right edge of the top bar).
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(top_spacer)

	var pause_btn := _make_kenney_button("❚❚", Vector2(46, 30), 14)
	pause_btn.tooltip_text = "Pause (Esc)"
	pause_btn.pressed.connect(_toggle_pause)
	top_hbox.add_child(pause_btn)

	# ── Invisible deck click zones (projected onto the 3D piles) ──
	_draw_btn_a = _make_draw_button("A")
	_draw_btn_b = _make_draw_button("B")

	# ── End Turn button (shown after drawing; lets the player skip playing) ──
	_end_turn_btn = _make_kenney_button("End Turn", Vector2(120, 36), 16, Color(0.9, 0.35, 0.25))
	_end_turn_btn.visible = false
	_end_turn_btn.pressed.connect(_end_turn)
	add_child(_end_turn_btn)

	# ── Turn timer ring (visual countdown, left side of screen) ──
	var ring_script := preload("res://scripts/turn_timer_ring.gd")
	_turn_timer_ring = ring_script.new()
	_turn_timer_ring.size = Vector2(64, 64)
	_turn_timer_ring.position = Vector2(24, get_viewport_rect().size.y - HANDCARD_H - 96)
	_turn_timer_ring.visible = false
	add_child(_turn_timer_ring)

	_turn_timer_label = Label.new()
	_turn_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_timer_label.size = Vector2(64, 64)
	_turn_timer_label.add_theme_font_size_override("font_size", 18)
	_turn_timer_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_turn_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_timer_ring.add_child(_turn_timer_label)

	# ── Overlay (for popups) ──
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	overlay_vbox = VBoxContainer.new()
	overlay_vbox.set_anchors_preset(Control.PRESET_CENTER)
	overlay_vbox.offset_left = -200
	overlay_vbox.offset_right = 200
	overlay_vbox.offset_top = -150
	overlay_vbox.offset_bottom = 150
	overlay_vbox.add_theme_constant_override("separation", 12)
	overlay.add_child(overlay_vbox)

	# ── Chamber draw text ──
	chamber_text = Label.new()
	chamber_text.visible = false
	chamber_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chamber_text.add_theme_font_size_override("font_size", 28)
	chamber_text.add_theme_color_override("font_color", Color(0.95, 0.3, 0.15))
	chamber_text.set_anchors_preset(Control.PRESET_CENTER)
	chamber_text.offset_left = -250
	chamber_text.offset_right = 250
	chamber_text.offset_top = -80
	chamber_text.offset_bottom = 80
	add_child(chamber_text)

	chamber_count = Label.new()
	chamber_count.visible = false
	chamber_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chamber_count.add_theme_font_size_override("font_size", 64)
	chamber_count.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	chamber_count.set_anchors_preset(Control.PRESET_CENTER)
	chamber_count.offset_left = -100
	chamber_count.offset_right = 100
	chamber_count.offset_top = 50
	chamber_count.offset_bottom = 150
	add_child(chamber_count)

	# ── Notification ──
	notification_label = Label.new()
	notification_label.visible = false
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.add_theme_font_size_override("font_size", 22)
	notification_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	notification_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notification_label.offset_left = -400
	notification_label.offset_right = 400
	notification_label.offset_top = 54
	notification_label.offset_bottom = 94
	add_child(notification_label)

	# ── Sound effects (Kenney UI pack) ──
	_sfx_card_play = AudioStreamPlayer.new()
	_sfx_card_play.stream = preload("res://assets/imported_assets/kenney_ui-pack/Sounds/click-a.ogg")
	_sfx_card_play.volume_db = -6.0
	add_child(_sfx_card_play)

	_sfx_card_draw = AudioStreamPlayer.new()
	_sfx_card_draw.stream = preload("res://assets/imported_assets/kenney_ui-pack/Sounds/tap-a.ogg")
	_sfx_card_draw.volume_db = -6.0
	add_child(_sfx_card_draw)

	_sfx_button = AudioStreamPlayer.new()
	_sfx_button.stream = preload("res://assets/imported_assets/kenney_ui-pack/Sounds/switch-a.ogg")
	_sfx_button.volume_db = -8.0
	add_child(_sfx_button)

	_sfx_click_b = AudioStreamPlayer.new()
	_sfx_click_b.stream = preload("res://assets/imported_assets/kenney_ui-pack/Sounds/click-b.ogg")
	_sfx_click_b.volume_db = -8.0
	add_child(_sfx_click_b)

	_sfx_switch_a = AudioStreamPlayer.new()
	_sfx_switch_a.stream = preload("res://assets/imported_assets/kenney_ui-pack/Sounds/switch-a.ogg")
	_sfx_switch_a.volume_db = -8.0
	add_child(_sfx_switch_a)

	_sfx_switch_b = AudioStreamPlayer.new()
	_sfx_switch_b.stream = preload("res://assets/imported_assets/kenney_ui-pack/Sounds/switch-b.ogg")
	_sfx_switch_b.volume_db = -8.0
	add_child(_sfx_switch_b)

	_sfx_tap_b = AudioStreamPlayer.new()
	_sfx_tap_b.stream = preload("res://assets/imported_assets/kenney_ui-pack/Sounds/tap-b.ogg")
	_sfx_tap_b.volume_db = -8.0
	add_child(_sfx_tap_b)

	# ── Turn border (screen-edge glow in the local player's color while acting) ──
	_turn_border = Panel.new()
	_turn_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_border.visible = false
	_turn_border_style = StyleBoxFlat.new()
	_turn_border_style.draw_center = false
	_turn_border_style.set_border_width_all(8)
	_turn_border_style.border_color = Color(0.95, 0.85, 0.3, 0.0)
	_turn_border.add_theme_stylebox_override("panel", _turn_border_style)
	add_child(_turn_border)

## Distinct click for special card effects (Extra Life / swap / rotate / peek).
func _play_action_sound(action_id: String) -> void:
	match action_id:
		"extra_life":
			_play_sfx(_sfx_click_b)
		"swap_hands", "rotate_decks", "peek":
			_play_sfx(_sfx_tap_b)
		"draw_two", "draw_four", "draw_ten":
			_play_sfx(_sfx_switch_b)

## Shows a prominent notification for action cards with color coding.
func _show_action_notification(card: Card, actor_name: String, target_name: String = "") -> void:
	var color: Color = Color.WHITE
	var icon := ""
	var msg := ""
	match card.action_id:
		"skip":
			color = Color(1.0, 0.4, 0.3)
			icon = "⊘"
			msg = "%s SKIP %s's turn!" % [actor_name, target_name] if target_name else "%s plays SKIP!" % actor_name
		"reverse":
			color = Color(0.3, 0.8, 1.0)
			icon = "↻"
			msg = "%s REVERSE!" % actor_name
		"draw_two":
			color = Color(1.0, 0.6, 0.1)
			icon = "+2"
			msg = "%s plays DRAW TWO on %s!" % [actor_name, target_name] if target_name else "%s plays DRAW TWO!" % actor_name
		"draw_four":
			color = Color(0.6, 0.2, 1.0)
			icon = "+4"
			msg = "%s plays DRAW FOUR on %s!" % [actor_name, target_name] if target_name else "%s plays DRAW FOUR!" % actor_name
		"draw_ten":
			color = Color(1.0, 0.2, 0.8)
			icon = "+10"
			msg = "%s plays DRAW TEN on %s!" % [actor_name, target_name] if target_name else "%s plays DRAW TEN!" % actor_name
		"swap_hands":
			color = Color(0.9, 0.7, 0.2)
			icon = "⇄"
			msg = "%s SWAP HANDS with %s!" % [actor_name, target_name] if target_name else "%s plays SWAP HANDS!" % actor_name
		"extra_life":
			color = Color(0.2, 1.0, 0.5)
			icon = "♥"
			msg = "%s banks an EXTRA LIFE!" % actor_name
		"peek":
			color = Color(0.8, 0.8, 0.8)
			icon = "👁"
			msg = "%s PEEKS at a deck!" % actor_name
		"choose_deck":
			color = Color(0.7, 0.5, 0.9)
			icon = " Deck"
			msg = "%s forces %s to draw from a deck!" % [actor_name, target_name] if target_name else "%s plays CHOOSE DECK!" % actor_name
		"rotate_decks":
			color = Color(0.4, 0.9, 0.7)
			icon = " ⟳"
			msg = "%s ROTATES the decks!" % actor_name
		"wild_sabotage":
			color = Color(1.0, 0.3, 0.3)
			icon = "✕"
			msg = "%s SABOTAGES %s!" % [actor_name, target_name] if target_name else "%s plays WILD SABOTAGE!" % actor_name
		_:
			return

	# Show with icon and color
	if notification_label:
		notification_label.add_theme_color_override("font_color", color)
	_show_notification(icon + " " + msg, 2.0)

## Shows a notification when a player's turn is skipped.
func _show_skip_notification(skipped_name: String, skipper_name: String = "") -> void:
	if notification_label:
		notification_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	var msg := "⊘ %s's turn is SKIPPED!" % skipped_name
	if skipper_name:
		msg = "⊘ %s skips %s's turn!" % [skipper_name, skipped_name]
	_show_notification(msg, 2.0)


## Instances scenes/game_3d.tscn (the editor-built poker table + markers) into a
## full-screen SubViewport, then frames a camera and builds the 3D piles.
func _setup_3d_viewport() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	_viewport_3d = SubViewport.new()
	_viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_3d.transparent_bg = false
	_viewport_3d.gui_disable_input = true
	_viewport_container.add_child(_viewport_3d)

	# World environment: procedural night sky + sky-lit ambient + light fog
	var world := World3D.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.028, 0.06)
	sky_mat.sky_horizon_color = Color(0.17, 0.19, 0.27)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.ground_horizon_color = Color(0.13, 0.14, 0.19)
	sky_mat.sun_angle_max = 26.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.1, 0.14)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.6
	world.environment = env
	_viewport_3d.world_3d = world

	# The editor-built scene: poker table + Deck A / Deck B / Table top / PlayerN markers
	var game3d_scene := load("res://scenes/game_3d.tscn")
	if game3d_scene:
		_world_root_3d = game3d_scene.instantiate()
		_viewport_3d.add_child(_world_root_3d)

		_marker_deck_a = _world_root_3d.get_node_or_null("Deck A") as Marker3D
		_marker_deck_b = _world_root_3d.get_node_or_null("Deck B") as Marker3D
		_marker_discard = _world_root_3d.get_node_or_null("Table top") as Marker3D
		_marker_players.clear()
		for i in range(1, 7):
			var m := _world_root_3d.get_node_or_null("Player%d" % i) as Marker3D
			if m:
				_marker_players.append(m)

	# Use the camera placed in game_3d.tscn if there is one; otherwise frame one
	# from the marker bounds so any table scale works.
	var bounds := _compute_table_bounds()
	_table_center = bounds.get_center()
	var tsize := maxf(bounds.size.x, bounds.size.z)
	_char_scale = tsize * 0.2

	# Find all cameras in the scene (one per player seat).
	_player_cameras.clear()
	_find_all_cameras(_world_root_3d)

	# Use the camera for the local player's seat if available.
	_camera_3d = _get_camera_for_seat(own_index)
	if _camera_3d == null:
		# Fallback: use the first camera found, or create an auto-framed one.
		_camera_3d = _get_camera_for_seat(0) if _player_cameras.size() > 0 else null
		if _camera_3d == null:
			_camera_3d = Camera3D.new()
			_camera_3d.fov = 55.0
			_camera_3d.position = _table_center + Vector3(0.0, tsize * 1.55, tsize * 0.58)
			_viewport_3d.add_child(_camera_3d)
			_camera_3d.look_at(_table_center + Vector3(0.0, 0.2, 0.0), Vector3.UP)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.3
	_viewport_3d.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.35
	_viewport_3d.add_child(fill)

	_build_3d_piles(tsize)

## AABB spanning every marker in the scene.
func _compute_table_bounds() -> AABB:
	var bmin := Vector3(INF, INF, INF)
	var bmax := Vector3(-INF, -INF, -INF)
	var seen := false
	for m in _marker_players:
		var p: Vector3 = m.global_position
		bmin = bmin.min(p)
		bmax = bmax.max(p)
		seen = true
	for m in [_marker_deck_a, _marker_deck_b, _marker_discard]:
		if m:
			var p2: Vector3 = m.global_position
			bmin = bmin.min(p2)
			bmax = bmax.max(p2)
			seen = true
	if not seen:
		return AABB(Vector3.ZERO, Vector3(2.0, 1.0, 2.0))
	return AABB(bmin, bmax - bmin)

## Card-back piles at the Deck A / Deck B markers + colored discard at Table top.
func _build_3d_piles(tsize: float) -> void:
	var card_w := tsize * 0.16
	var card_h := tsize * 0.23

	var pile_mat_a := StandardMaterial3D.new()
	pile_mat_a.roughness = 0.5
	pile_mat_a.albedo_color = Color(0.16, 0.16, 0.18)

	var pile_mat_b := pile_mat_a.duplicate()
	_pile_a_mat = pile_mat_a
	_pile_b_mat = pile_mat_b

	if _marker_deck_a:
		_pile_a_mesh = _create_pile_mesh(_marker_deck_a.global_position, _pile_a_mat, card_w, card_h)
	if _marker_deck_b:
		_pile_b_mesh = _create_pile_mesh(_marker_deck_b.global_position, _pile_b_mat, card_w, card_h)

	# Discard pile: render the ACTUAL top card the same way hand UI cards do
	# (a CardNode in a tiny SubViewport projected onto a Sprite3D), instead of a
	# flat colored box with a text label hovering above it.
	if _marker_discard:
		var discard_pos: Vector3 = _marker_discard.global_position
		_discard_vp = SubViewport.new()
		_discard_vp.size = Vector2i(128, 192)
		_discard_vp.transparent_bg = true
		_discard_vp.gui_disable_input = true
		_discard_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport_3d.add_child(_discard_vp)

		_discard_card_node = CardNode.new()
		_discard_card_node.setup(CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 0, "", ""), true, 128.0, 192.0)
		_discard_vp.add_child(_discard_card_node)

		var discard_mat := StandardMaterial3D.new()
		discard_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		discard_mat.albedo_texture = _discard_vp.get_texture()
		discard_mat.roughness = 1.0
		discard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		_discard_sprite = Sprite3D.new()
		_discard_sprite.texture = _discard_vp.get_texture()
		_discard_sprite.material_override = discard_mat
		_discard_sprite.centered = true
		_discard_sprite.pixel_size = card_w / 128.0
		_discard_sprite.position = discard_pos + Vector3(0, 0.06, 0)
		_discard_sprite.rotation_degrees.x = -90.0
		_discard_sprite.visible = false
		_viewport_3d.add_child(_discard_sprite)

	# Deck labels + counts
	if _marker_deck_a:
		_add_table_label("DECK A", _marker_deck_a.global_position + Vector3(0, 0.14, 0), 9, Color(0.9, 0.85, 0.6))
		_pile_a_count_label = _add_table_label("", _marker_deck_a.global_position + Vector3(0, 0.06, 0), 7, Color(0.8, 0.75, 0.6))
	if _marker_deck_b:
		_add_table_label("DECK B", _marker_deck_b.global_position + Vector3(0, 0.14, 0), 9, Color(0.9, 0.85, 0.6))
		_pile_b_count_label = _add_table_label("", _marker_deck_b.global_position + Vector3(0, 0.06, 0), 7, Color(0.8, 0.75, 0.6))

func _create_pile_mesh(pos: Vector3, mat: StandardMaterial3D, w: float, h: float) -> MeshInstance3D:
	var stack := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, 0.05, h)
	stack.mesh = box
	stack.material_override = mat
	stack.position = pos + Vector3(0, 0.03, 0)
	_viewport_3d.add_child(stack)
	return stack

func _add_table_label(text: String, pos: Vector3, font_size: int, color: Color) -> Label3D:
	var label3d := Label3D.new()
	# Rasterize at higher resolution for crisp text: Label3D renders the string
	# into a texture at font_size pixels, then billboards it at pixel_size 3D
	# units per pixel. Keep the WORLD-SPACE size constant (font_size * pixel_size
	# unchanged) but bump the texture density, which removes the upscale blur.
	var raster_scale := 4
	label3d.text = text
	label3d.font_size = font_size * raster_scale
	label3d.pixel_size = 0.005 / raster_scale
	label3d.modulate = color
	label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label3d.no_depth_test = true
	label3d.position = pos
	_viewport_3d.add_child(label3d)
	return label3d

## Depth-first search for ALL Camera3D nodes in the scene and store them by player.
## Cameras are expected as children of PlayerN markers (Player1 = index 0, etc.).
func _find_all_cameras(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Camera3D:
			# Determine which player this camera belongs to.
			var player_idx := -1
			var parent := child.get_parent()
			if parent and parent.name.begins_with("Player"):
				var suffix := parent.name.substr(6)  # "Player" = 6 chars
				if suffix.is_valid_int():
					player_idx = suffix.to_int() - 1  # 1-indexed to 0-indexed
			if player_idx >= 0 and player_idx < 7:  # Support up to 7 players
				# Ensure array is large enough
				while _player_cameras.size() <= player_idx:
					_player_cameras.append(null)
				_player_cameras[player_idx] = child
			# Keep searching for more cameras in other branches
		_find_all_cameras(child)

## Get the camera for a specific player seat, or null if none exists.
func _get_camera_for_seat(seat_index: int) -> Camera3D:
	if seat_index < 0 or seat_index >= _player_cameras.size():
		return null
	return _player_cameras[seat_index]

## Switch the active camera to the given player seat.
func _switch_camera_to_seat(seat_index: int) -> void:
	var cam := _get_camera_for_seat(seat_index)
	if cam == null or cam == _camera_3d:
		return
	_camera_3d = cam
	# Reposition draw zones to match the new camera.
	if _draw_zones_init:
		_reposition_draw_zones()

## Subtle neutral glow on the draw piles while it's the local player's turn
## (was green emissive; decks should stay neutral so they don't read as "green").
func _set_piles_glow(on: bool) -> void:
	var mats: Array[StandardMaterial3D] = []
	if _pile_a_mat:
		mats.append(_pile_a_mat)
	if _pile_b_mat:
		mats.append(_pile_b_mat)
	for mat in mats:
		mat.emission_enabled = on
		mat.emission = Color(0.7, 0.7, 0.75) if on else Color.BLACK
		mat.emission_energy_multiplier = 0.35 if on else 0.0

## Places a Kenney character at each opponent's marker. Only the local player's
## hand is ever rendered (their seat shows nothing in 3D — cards are 2D below).
func _place_opponents_3d() -> void:
	for child in _opponent_nodes_3d:
		if is_instance_valid(child):
			child.queue_free()
	_opponent_nodes_3d.clear()
	_char_node_by_index.clear()

	if game.players.is_empty() or _marker_players.is_empty():
		return

	var n := game.players.size()
	for i in range(1, n):
		if i == own_index:
			continue
		var p: PlayerData = game.players[i]
		# Skip eliminated players — their character disappears.
		if p.eliminated:
			continue
		# Seat i sits at the "Player{i+1}" marker; wraps for 7-player games.
		var marker: Marker3D = _marker_players[i % _marker_players.size()]
		var base_pos: Vector3 = marker.global_position
		# The Kenney GLBs are authored with the origin above the feet — lower them
		# so they actually stand on the felt (tune CHAR_SEAT_OFFSET if needed).
		base_pos.y -= _char_scale * CHAR_SEAT_OFFSET
		if i % _marker_players.size() == 0:
			# 7th player reuses the bottom marker — nudge aside so it clears the local hand.
			base_pos += Vector3(0.45 * _char_scale, 0, -0.2 * _char_scale)

		var char_path := "res://assets/imported_assets/kenney_blocky-characters_20/Models/GLB format/character-%s.glb" % char(97 + (i - 1) % 18)
		var char_res = load(char_path)
		if char_res:
			var char_node: Node3D = char_res.instantiate()
			char_node.position = base_pos
			char_node.scale = Vector3(_char_scale, _char_scale, _char_scale)
			var to_center: Vector3 = _table_center - base_pos
			char_node.rotation.y = atan2(to_center.x, to_center.z)
			_viewport_3d.add_child(char_node)
			_opponent_nodes_3d.append(char_node)
			_char_node_by_index[i] = char_node
			_animate_character(char_node, base_pos, i == game.current_index)

		var is_current: bool = i == game.current_index
		var name_text := (">> " if is_current else "") + p.display_name
		var lift := _char_scale * 2.1
		var name_col: Color = Color(0.95, 0.85, 0.3) if is_current else p.color.lightened(0.28)

		var name_label := _add_table_label(name_text, base_pos + Vector3(0, lift + 0.03, 0), 9,
			name_col)
		_opponent_nodes_3d.append(name_label)

		var count_text := "%d cards" % p.hand_size()
		if p.banked_lives > 0:
			count_text += " • %d %s" % [p.banked_lives, "life" if p.banked_lives == 1 else "lives"]
		var count_label := _add_table_label(count_text, base_pos + Vector3(0, lift - 0.06, 0), 7,
			Color(0.7, 0.67, 0.6))
		_opponent_nodes_3d.append(count_label)

## Procedural character animation: a gentle idle bob for everyone, plus a "turn
## pop" pulse for the acting player. If you add AnimationPlayer clips to the
## character nodes in game_3d.tscn (named e.g. idle/play/draw/celebrate/wave),
## call them here instead of the tweens.
func _animate_character(char_node: Node3D, base_pos: Vector3, is_turn: bool) -> void:
	var bob := create_tween().bind_node(char_node).set_loops()
	var bob_h := 0.03 * _char_scale
	bob.tween_property(char_node, "position:y", base_pos.y + bob_h, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(char_node, "position:y", base_pos.y - bob_h * 0.4, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if is_turn:
		var s := _char_scale
		var pop := create_tween().bind_node(char_node)
		pop.tween_property(char_node, "scale", Vector3(s * 1.12, s * 1.12, s * 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(char_node, "scale", Vector3(s, s, s), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

## Instances scenes/player_ui.tscn; the local hand is summoned around CenterCards.
func _setup_player_ui() -> void:
	var ui_scene := load("res://scenes/player_ui.tscn")
	if ui_scene:
		_player_ui = ui_scene.instantiate()
		_player_ui.name = "PlayerUI"
		_player_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_player_ui)
		_hand_marker = _player_ui.get_node_or_null("CenterCards") as Marker2D

		if _hand_marker:
			_own_label = Label.new()
			_own_label.name = "OwnLabel"
			_own_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_own_label.custom_minimum_size = Vector2(220, 0)
			_own_label.position = Vector2(_hand_marker.position.x - 110, _hand_marker.position.y - HANDCARD_H - 36 - PLAYABLE_LIFT)
			_own_label.add_theme_font_size_override("font_size", 17)
			_own_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
			_player_ui.add_child(_own_label)

## Invisible click target projected over a 3D draw pile (used when no valid plays).
func _make_draw_button(pile_id: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.85, 0.35, 0.14)
	style.border_color = Color(0.45, 0.95, 0.5, 0.6)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style)

	var style_hover := style.duplicate()
	style_hover.bg_color = Color(0.35, 0.95, 0.4, 0.22)
	style_hover.border_color = Color(0.6, 1.0, 0.65, 0.9)
	btn.add_theme_stylebox_override("hover", style_hover)

	btn.pressed.connect(_on_deck_clicked.bind(pile_id))
	add_child(btn)
	return btn

## Flies a ghost copy of the played card from the hand area to the discard pile.
func _fly_card_to_discard(card: Card) -> void:
	if card == null or _hand_marker == null:
		return
	var target := _hand_marker.position
	if _marker_discard and _camera_3d:
		target = _camera_3d.unproject_position(_marker_discard.global_position)
	_spawn_ghost(card, _hand_marker.position + Vector2(0, -HANDCARD_H * 0.8), target)

## Flies a ghost of the drawn card from the deck pile to the hand area.
func _fly_draw_to_hand(pile_id: String, card: Card) -> void:
	if card == null or _hand_marker == null:
		return
	var src := Vector2(960, 400)
	var marker: Marker3D = _marker_deck_a if pile_id == "A" else _marker_deck_b
	if marker and _camera_3d:
		src = _camera_3d.unproject_position(marker.global_position)
	_spawn_ghost(card, src, _hand_marker.position + Vector2(0, -HANDCARD_H * 0.8))

## Spawns a fading CardNode that flies between two screen points (pure feedback,
## never interactive).
func _spawn_ghost(card: Card, from: Vector2, to: Vector2) -> void:
	var ghost := CardNode.new()
	ghost.setup(card, true, HANDCARD_W * 0.85, HANDCARD_H * 0.85)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = from
	ghost.z_index = 60
	ghost.modulate.a = 0.95
	add_child(ghost)
	var tw := create_tween().bind_node(ghost)
	tw.tween_property(ghost, "position", to, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ghost, "modulate:a", 0.0, 0.3)
	tw.tween_callback(ghost.queue_free)

## Flies `count` card-back ghosts from a deck to a seat, staggered, so forced
## draws (Draw Two/Four/Ten) read as visible processing time.
func _animate_forced_draw(pile_id: String, target_index: int, count: int) -> void:
	if count <= 0:
		return
	var src := Vector2(960, 400)
	var marker: Marker3D = _marker_deck_a if pile_id == "A" else _marker_deck_b
	if marker and _camera_3d:
		src = _camera_3d.unproject_position(marker.global_position)
	var dst := _target_screen_pos(target_index)
	for i in range(count):
		var ghost := CardNode.new()
		ghost.setup(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""), false, HANDCARD_W * 0.85, HANDCARD_H * 0.85)
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.position = src
		ghost.z_index = 60
		ghost.modulate.a = 0.0
		add_child(ghost)
		var tw := create_tween().bind_node(ghost)
		tw.tween_interval(i * 0.32)
		tw.tween_callback(func() -> void:
			_play_sfx(_sfx_tap_b))
		tw.tween_property(ghost, "modulate:a", 0.95, 0.08)
		tw.tween_property(ghost, "position", dst, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(ghost, "modulate:a", 0.0, 0.18)
		tw.tween_callback(ghost.queue_free)

## Reveals the last `hide_count` hand cards one-by-one (pop-in) in sync with the
## staggered card ghosts, so each drawn card *appears* in the fan as its ghost
## lands instead of the whole hand flickering to its final state at once. Cards
## start hidden + non-interactive until their slot is revealed. `first_delay` is
## the seconds before the first card shows (≈ ghost flight), `step` the stagger
## between cards.
func _reveal_hand_tail(hide_count: int, first_delay: float = 0.0, step: float = 0.32) -> void:
	if hide_count <= 0 or card_nodes.is_empty():
		return
	var n: int = card_nodes.size()
	var start := maxi(n - hide_count, 0)
	if start >= n:
		return
	for i in range(start, n):
		var cn: CardNode = card_nodes[i]
		cn.modulate.a = 0.0
		cn.scale = Vector2(0.6, 0.6)
		cn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := create_tween().bind_node(cn)
		tw.tween_interval(first_delay + float(i - start) * step)
		tw.tween_property(cn, "scale", Vector2.ONE, 0.22)
		tw.parallel().tween_property(cn, "modulate:a", 1.0, 0.18)
		tw.tween_callback(func() -> void:
			cn.mouse_filter = Control.MOUSE_FILTER_STOP
		)

## Screen position for a seat's hand area (2D hand for self, character marker
## for opponents).
func _target_screen_pos(seat: int) -> Vector2:
	if _hand_marker == null:
		return Vector2(960, 700)
	if seat == own_index:
		return _hand_marker.position + Vector2(0, -HANDCARD_H * 0.8)
	if _camera_3d and not _marker_players.is_empty():
		var marker: Marker3D = _marker_players[seat % _marker_players.size()]
		return _camera_3d.unproject_position(marker.global_position + Vector3(0, _char_scale * 1.8, 0))
	return Vector2(960, 300)

## Projects the deck markers onto screen space and moves the click zones there.
func _reposition_draw_zones() -> void:
	if not _camera_3d or not _viewport_3d or _viewport_3d.size.x <= 0:
		return
	if _draw_btn_a == null or _draw_btn_b == null:
		return
	if _marker_deck_a:
		var pa: Vector2 = _camera_3d.unproject_position(_marker_deck_a.global_position)
		_draw_btn_a.position = pa - Vector2(45, 70)
		_draw_btn_a.size = Vector2(90, 140)
	if _marker_deck_b:
		var pb: Vector2 = _camera_3d.unproject_position(_marker_deck_b.global_position)
		_draw_btn_b.position = pb - Vector2(45, 70)
		_draw_btn_b.size = Vector2(90, 140)

# ── Kenney UI styling helpers ────────────────────────────────────────

func _make_kenney_style(tex: Texture2D, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = 22
	s.texture_margin_right = 22
	s.texture_margin_top = 16
	s.texture_margin_bottom = 16
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.modulate_color = tint
	return s

## Every UI button is built through here so all chrome uses the Kenney UI pack.
func _make_kenney_button(text: String, min_size: Vector2, font_size: int = 18, tint: Color = Color.WHITE) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.75))
	btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
	btn.add_theme_stylebox_override("normal", _make_kenney_style(_UI_TEX["button"], tint))
	btn.add_theme_stylebox_override("hover", _make_kenney_style(_UI_TEX["button_hover"], tint.lightened(0.18)))
	btn.add_theme_stylebox_override("pressed", _make_kenney_style(_UI_TEX["button_pressed"], tint.darkened(0.15)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn

## Solid-color button for the color-choice dialog: modulating the Kenney button
## texture with modulate_color leaves all four swatches muddy and hard to tell
## apart, so color picks use flat, unmistakably-red/blue/green/yellow buttons.
func _make_color_button(text: String, color: Color, min_size: Vector2, font_size: int = 18) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", font_size)

	var font_col := Color.WHITE if color.get_luminance() < 0.5 else Color(0.15, 0.12, 0.08)
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", font_col)
	btn.add_theme_color_override("font_pressed_color", font_col)

	var norm := StyleBoxFlat.new()
	norm.bg_color = color
	norm.border_color = color.lightened(0.4)
	norm.set_border_width_all(3)
	norm.set_corner_radius_all(10)
	norm.content_margin_left = 10
	norm.content_margin_right = 10
	norm.content_margin_top = 6
	norm.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", norm)

	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.12)
	hover.border_color = color.lightened(0.55)
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(10)
	hover.content_margin_left = 10
	hover.content_margin_right = 10
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.18)
	pressed.border_color = color.darkened(0.05)
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(10)
	pressed.content_margin_left = 10
	pressed.content_margin_right = 10
	pressed.content_margin_top = 6
	pressed.content_margin_bottom = 6
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn

# ── Game Setup ────────────────────────────────────────────────────────

func _start_game() -> void:
	var globals := get_node_or_null("/root/GameGlobals")
	if globals:
		is_online = globals.is_online
		own_index = globals.own_seat
		is_tutorial = globals.is_tutorial

	game = GameState.new()
	game.log_event.connect(_on_log)
	game.jump_in_available.connect(_on_jump_in_available)
	game.player_respawned.connect(_on_player_respawned)
	game.bomb_vote_started.connect(_on_bomb_vote_started)
	game.bomb_vote_finished.connect(_on_bomb_vote_finished)

	if is_online:
		if _eos and _eos.is_host:
			var mode: int = GameGlobals.game_mode
			var gm: int = GameState.Mode.SHEDDING_RACE if mode == 0 else GameState.Mode.LAST_ONE_STANDING
			game.setup(GameGlobals.num_players, gm)
			_apply_roster_identity()
			# Deal animation for the host; clients see snapshots.
			_start_dealing_animation(GameGlobals.num_players)
		else:
			# Client: no local authority. Deck must exist for UI reads, but its
			# contents don't matter - the first snapshot sets pile sizes.
			game.deck = DeckManager.new()
			state = State.WAITING
			_refresh_all()
	else:
		var num_p := 4
		var mode := 0
		if globals:
			num_p = globals.num_players
			mode = globals.game_mode
		var gm: int = GameState.Mode.SHEDDING_RACE if mode == 0 else GameState.Mode.LAST_ONE_STANDING
		if is_tutorial:
			_build_tutorial_state()
			_start_tutorial()
			return
		game.setup(num_p, gm)
		_assign_offline_colors()
		# Start the dealing animation (deals cards to players with visual feedback).
		_start_dealing_animation(num_p)

# ── Guided Tutorial ───────────────────────────────────────────────────

## Builds a fully scripted 4-player GameState with fixed hands/piles (no RNG),
## reconnects the state signals, and lays out the table. The tutorial director
## (`tutorial_director.gd`) then replays every mechanic in order.
func _build_tutorial_state() -> void:
	game = GameState.new()
	game.players = [
		PlayerData.new(0, "You"),
		PlayerData.new(1, "Rex"),
		PlayerData.new(2, "Nia"),
		PlayerData.new(3, "Zed"),
	]
	game.mode = GameState.Mode.SHEDDING_RACE
	game.current_index = 0
	game.direction = 1
	game.pending_last_shot = false
	game.active_color = Card.CardColor.RED
	game.active_number = 5
	game.active_action_id = ""
	game.deck = DeckManager.new()
	game.deck.pile_a = []
	game.deck.pile_b = []
	game.deck.discard = []
	game.log_event.connect(_on_log)
	game.jump_in_available.connect(_on_jump_in_available)
	game.player_respawned.connect(_on_player_respawned)
	game.bomb_vote_started.connect(_on_bomb_vote_started)
	game.bomb_vote_finished.connect(_on_bomb_vote_finished)
	_assign_offline_colors()
	_place_opponents_3d()
	_switch_camera_to_seat(own_index)
	_refresh_all()

## Spawns the tutorial director and hands it the reins. The director fully
## scripts AI behavior and gates human input, so no dealing animation plays.
func _start_tutorial() -> void:
	var script := load("res://scripts/tutorial_director.gd")
	if script == null:
		push_error("Tutorial director script not found")
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	var director: Node = script.new()
	director.set("g", self)
	add_child(director)
	director.call_deferred("_run_tutorial")

# Offline: the local player keeps their menu-picked color; each AI seat gets a
# random remaining palette color so no two seats match.
func _assign_offline_colors() -> void:
	var indices: Array[int] = []
	var used := {GameGlobals.my_color_idx: true}
	for i in range(game.players.size()):
		var idx: int = GameGlobals.my_color_idx if i == 0 else _random_free_color(used)
		used[idx] = true
		indices.push_back(idx)
	game.apply_seat_colors(indices)

func _random_free_color(used: Dictionary) -> int:
	var pool: Array[int] = []
	for i in range(GameGlobals.PALETTE.size()):
		if not used.has(i):
			pool.push_back(i)
	if pool.is_empty():
		return randi() % GameGlobals.PALETTE.size()
	pool.shuffle()
	return pool[0]

# Online host: seat i takes the lobby-chosen display name + color from the
# roster. Collisions (two players picked the same color) get a free color,
# resolved in seat order so seat 0 always keeps its pick.
func _apply_roster_identity() -> void:
	if _eos == null or _eos.roster.is_empty():
		return
	var seen := {}
	for i in range(game.players.size()):
		var entry: Dictionary = {}
		for r in _eos.roster:
			if r.get("seat") == i:
				entry = r
				break
		var p: PlayerData = game.players[i]
		var name: String = entry.get("display_name", p.display_name)
		var idx: int = int(entry.get("color_idx", 0)) % GameGlobals.PALETTE.size()
		if seen.has(idx):
			idx = _random_free_color(seen)
		seen[idx] = true
		p.display_name = name
		p.color_idx = idx
		p.color = GameGlobals.PALETTE[idx]

## Helper to emit a game log line from the UI layer.
func _game_log(text: String) -> void:
	if game:
		game.log_event.emit(text)

func _on_log(text: String) -> void:
	# Host forwards authoritative game log lines to clients (peek lines filtered).
	if is_online and is_host_here() and not _is_peek_log(text):
		rpc("_rpc_log", text)

	# Show action card notifications from log messages.
	_show_notification_for_log(text)

func is_host_here() -> bool:
	return _eos != null and _eos.is_host

## Called when a player respawns from a Respawn card.
func _on_player_respawned(player_index: int) -> void:
	var p: PlayerData = game.players[player_index]
	if player_index == own_index:
		# Local player respawned — leave spectator mode!
		state = State.WAITING
		_show_notification("🎉 You RESPAWNED! Back in the game!", 3.0)
	else:
		_show_notification("🎉 %s RESPAWNED!" % p.display_name, 3.0)
	_play_sfx(_sfx_switch_b)
	_refresh_all()
	if player_index == own_index:
		_check_turn()  # Resume normal turn flow for the respawned player
	_play_respawn_animation(player_index)

## Called when all bombs are diffused and voting begins.
func _on_bomb_vote_started() -> void:
	if is_tutorial:
		return  # Tutorial scripts the bomb/chamber directly; never open the vote UI
	if game.players[own_index].eliminated:
		return  # Spectators don't vote
	state = State.BOMB_VOTE
	_hide_timer_ui()
	_show_bomb_vote_ui()

## Called when the bomb vote concludes.
func _on_bomb_vote_finished(continued: bool) -> void:
	state = State.WAITING
	_dismiss_all_overlays()
	if continued:
		_show_notification("🗳️ Vote passed! Bombs redistributed. Game continues!", 3.0)
	else:
		_show_notification("🗳️ Vote ended! All remaining players win!", 3.0)
	_play_sfx(_sfx_switch_b)
	_refresh_all()
	_check_turn()

## Shows the bomb vote UI with Continue/End buttons.
func _show_bomb_vote_ui() -> void:
	if get_node_or_null("BombVotePanel"):
		return
	_dismiss_all_overlays()
	_show_notification("💣 All bombs diffused! Vote to continue or end.", 5.0)
	# Create vote buttons
	var vote_panel := PanelContainer.new()
	vote_panel.name = "BombVotePanel"
	vote_panel.set_anchors_preset(Control.PRESET_CENTER)
	vote_panel.offset_left = -200
	vote_panel.offset_right = 200
	vote_panel.offset_top = -100
	vote_panel.offset_bottom = 100
	vote_panel.add_theme_stylebox_override("panel", _make_kenney_style(_UI_TEX["button"]))
	add_child(vote_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vote_panel.add_child(vbox)

	var title := Label.new()
	title.text = "💣 All bombs diffused!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Vote to continue or end the game:"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	vbox.add_child(subtitle)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)

	var continue_btn := _make_kenney_button("Continue Game", Vector2(150, 50), 18, Color(0.2, 0.8, 0.3))
	continue_btn.pressed.connect(func() -> void:
		vote_panel.queue_free()
		if is_online and not is_host_here():
			send_intent({"kind": "bomb_vote", "continue_game": true})
		else:
			game.cast_vote(own_index, true)
		_show_notification("You voted to CONTINUE!", 2.0)
	)
	row.add_child(continue_btn)

	var end_btn := _make_kenney_button("End Game", Vector2(150, 50), 18, Color(0.9, 0.3, 0.2))
	end_btn.pressed.connect(func() -> void:
		vote_panel.queue_free()
		if is_online and not is_host_here():
			send_intent({"kind": "bomb_vote", "continue_game": false})
		else:
			game.cast_vote(own_index, false)
		_show_notification("You voted to END!", 2.0)
	)
	row.add_child(end_btn)

## Parses log messages and shows action card notifications.
func _show_notification_for_log(text: String) -> void:
	var lower := text.to_lower()
	# Skip notifications
	if " is skipped" in text or "skip" in lower and "turn" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		var msg := text
		if "is skipped" in text:
			msg = "⊘ " + text
		_show_notification(msg, 2.0)
		return
	# Reverse
	if "reverse" in lower and "plays" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		_show_notification("↻ " + text, 2.0)
		return
	# Draw cards (two/four/ten)
	if "draw two" in lower or "draw four" in lower or "draw ten" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
		var icon := "+2"
		if "draw four" in lower: icon = "+4"
		elif "draw ten" in lower: icon = "+10"
		_show_notification(icon + " " + text, 2.0)
		return
	# Swap hands
	if "swap hands" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		_show_notification("⇄ " + text, 2.0)
		return
	# Extra life
	if "extra life" in lower or "banks an extra" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
		_show_notification("♥ " + text, 2.0)
		return
	# Peek
	if "peek" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		_show_notification("👁 " + text, 2.0)
		return
	# Choose deck / force draw
	if "forces" in lower and "draw to come from" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))
		_show_notification(" Deck " + text, 2.0)
		return
	# Rotate decks
	if "rotates the decks" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.7))
		_show_notification("⟳ " + text, 2.0)
		return
	# Overcharge
	if "overcharged" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
		_show_notification("⚡ " + text, 3.0)
		return
	# Last shot
	if "last shot" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		_show_notification("🎯 " + text, 3.0)
		return
	# Jump in
	if "jumps in" in lower:
		if notification_label:
			notification_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		_show_notification("⚡ " + text, 2.0)
		return

func _show_notification(text: String, duration: float = 2.5) -> void:
	if notification_label:
		notification_label.text = text
		notification_label.visible = true
		_notification_timer = duration

## Big center-screen banner that bounces in, holds, then fades out.
func _play_center_banner(text: String, color: Color, size_px: int, hold: float = 0.55) -> void:
	var old := get_node_or_null("CenterBanner")
	if old:
		old.queue_free()
	var banner := Label.new()
	banner.name = "CenterBanner"
	banner.text = text
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", size_px)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	banner.add_theme_constant_override("shadow_offset_x", 3)
	banner.add_theme_constant_override("shadow_offset_y", 3)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -400
	banner.offset_right = 400
	banner.offset_top = -160
	banner.offset_bottom = 160
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.pivot_offset = Vector2(400, 160)
	banner.scale = Vector2(1.5, 1.5)
	banner.modulate.a = 1.0
	add_child(banner)
	var tw := create_tween().bind_node(banner)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hold > 0.0:
		tw.tween_interval(hold)
	tw.tween_property(banner, "modulate:a", 0.0, 0.3)
	tw.tween_callback(banner.queue_free)

## Played the first time control passes to the local player each turn.
func _play_your_turn_animation() -> void:
	_play_center_banner("YOUR TURN!", Color(1.0, 0.9, 0.35), 72)
	_play_sfx(_sfx_switch_a)

## Respawn reveal: banner, then the fresh hand (local) or re-summoned character
## (opponent) pops in AFTER the animation.
func _play_respawn_animation(player_index: int) -> void:
	var p: PlayerData = game.players[player_index]
	_play_center_banner("✨ %s RESPAWNED!" % p.display_name, Color(0.3, 1.0, 0.5), 56)
	_play_sfx(_sfx_switch_b)
	if player_index == own_index:
		var delay := 0.0
		for cn in card_nodes:
			cn.pivot_offset = cn.size / 2.0
			cn.scale = Vector2(0.1, 0.1)
			var ct := create_tween().bind_node(cn)
			ct.tween_interval(delay)
			ct.tween_property(cn, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			delay += 0.05
	else:
		var char_node: Node3D = _char_node_by_index.get(player_index, null)
		if char_node:
			char_node.scale = Vector3.ZERO
			var ct := create_tween().bind_node(char_node)
			ct.tween_property(char_node, "scale", Vector3(_char_scale, _char_scale, _char_scale), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Dealing Animation ──────────────────────────────────────────────────

## Starts the dealing animation: cards fly from the deck to each player,
## then a random player is selected to go first.
func _start_dealing_animation(num_players: int) -> void:
	state = State.DEALING
	_deal_phase = 0
	_deal_player_idx = 0
	_deal_card_idx = 0
	_deal_total_cards = 7 * num_players  # STARTING_HAND_SIZE = 7
	_deal_cards_dealt = 0
	_deal_timer = 0.0
	_deal_card_delay = 0.08
	_show_notification("Dealing cards...", 3.0)
	_refresh_all()

## Called from _process while state == DEALING.
func _process_dealing(delta: float) -> void:
	_deal_timer -= delta
	if _deal_timer > 0:
		return

	var num_players := game.players.size()

	if _deal_phase == 0:
		# Phase 0: Deal cards to each player one by one.
		if _deal_cards_dealt < _deal_total_cards:
			# Animate a card flying from the deck to the current player.
			var src_pos: Vector2 = Vector2(960, 300)  # Center of screen (deck area)
			if _camera_3d and _marker_deck_a:
				src_pos = _camera_3d.unproject_position(_marker_deck_a.global_position)
			var dst_pos := _target_screen_pos(_deal_player_idx)

			# Spawn a card-back ghost flying to the player.
			var ghost := CardNode.new()
			ghost.setup(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""), false, HANDCARD_W * 0.7, HANDCARD_H * 0.7)
			ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ghost.position = src_pos
			ghost.z_index = 60
			ghost.modulate.a = 0.9
			add_child(ghost)
			var tw := create_tween().bind_node(ghost)
			tw.tween_property(ghost, "position", dst_pos, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(ghost, "modulate:a", 0.0, 0.08)
			tw.tween_callback(ghost.queue_free)

			_play_sfx(_sfx_card_draw)

			_deal_cards_dealt += 1
			_deal_card_idx += 1
			if _deal_card_idx >= 7:  # STARTING_HAND_SIZE
				_deal_card_idx = 0
				_deal_player_idx += 1
				if _deal_player_idx >= num_players:
					_deal_player_idx = 0

			_deal_timer = _deal_card_delay
			# Speed up slightly as we go.
			_deal_card_delay = maxf(0.04, _deal_card_delay * 0.98)
		else:
			# All cards dealt — move to phase 1 (flip starter).
			_deal_phase = 1
			_deal_timer = 0.4
			_refresh_all()  # Show all hands.

	elif _deal_phase == 1:
		# Phase 1: Flip the starter card onto the discard pile.
		var src_pos: Vector2 = Vector2(960, 300)
		if _camera_3d and _marker_deck_a:
			src_pos = _camera_3d.unproject_position(_marker_deck_a.global_position)
		var dst_pos: Vector2 = Vector2(960, 500)
		if _camera_3d and _marker_discard:
			dst_pos = _camera_3d.unproject_position(_marker_discard.global_position)

		var starter_card: Card = null
		if not game.deck.discard.is_empty():
			starter_card = game.deck.discard.back()

		if starter_card:
			var ghost := CardNode.new()
			ghost.setup(starter_card, true, HANDCARD_W * 0.9, HANDCARD_H * 0.9)
			ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ghost.position = src_pos
			ghost.z_index = 60
			add_child(ghost)
			var tw := create_tween().bind_node(ghost)
			tw.tween_property(ghost, "position", dst_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(ghost, "modulate:a", 0.0, 0.3)
			tw.tween_callback(ghost.queue_free)
			_play_sfx(_sfx_card_play)

			_refresh_all()

		# Phase 2: Pick first player.
		_deal_phase = 2
		_deal_timer = 0.6

	elif _deal_phase == 2:
		# Phase 2: Randomly select the starting player.
		var first := randi() % num_players
		game.current_index = first

		var who: String = game.players[first].display_name
		_show_notification("🎲 %s goes first!" % who, 3.0)
		_play_sfx(_sfx_switch_a)

		# Brief pause, then start the game.
		_deal_timer = 1.2
		_deal_phase = 3

	elif _deal_phase == 3:
		# Done — transition to the first turn.
		if is_online and is_host_here():
			_broadcast_snapshot()
		_check_turn()

# ── Refresh All ───────────────────────────────────────────────────────

func _refresh_all() -> void:
	_refresh_decks()
	_refresh_discard()
	_refresh_opponents()
	_refresh_hand()
	_refresh_top_bar()
	_update_turn_border()
	# Show overcharge banner when it activates.
	if game.overcharge_active and not _overcharge_notified:
		_overcharge_notified = true
		_play_center_banner("⚡ OVERCHARGED! Play 2 cards!", Color(1.0, 0.85, 0.0), 36, 0.8)
	elif not game.overcharge_active:
		_overcharge_notified = false

## Screen-edge glow tinted with the local player's color while it's their turn
## (or while choosing a forced-draw deck or taking the Last Shot). Pulses subtly.
func _update_turn_border() -> void:
	if _turn_border == null:
		return
	var show := state == State.HUMAN_TURN or state == State.FORCED_DRAW_DECK_CHOICE or state == State.LAST_SHOT
	_turn_border.visible = show
	if not show:
		return
	if game == null or own_index >= game.players.size():
		return
	var col := _own_color()
	var pulse := 0.65 + 0.3 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 240.0))
	_turn_border_style.border_color = Color(col.r, col.g, col.b, pulse)

func _own_color() -> Color:
	var idx: int = 0
	if game and own_index >= 0 and own_index < game.players.size():
		idx = game.players[own_index].color_idx
	idx %= GameGlobals.PALETTE.size()
	return GameGlobals.PALETTE[idx]

func _refresh_decks() -> void:
	if _pile_a_count_label:
		var sz_a := game.deck.pile_a.size()
		_pile_a_count_label.text = "%d cards • %d%% chamber" % [sz_a, _chamber_pct(_deck_bombs("A"), sz_a)]
	if _pile_b_count_label:
		var sz_b := game.deck.pile_b.size()
		_pile_b_count_label.text = "%d cards • %d%% chamber" % [sz_b, _chamber_pct(_deck_bombs("B"), sz_b)]

## Number of Bomb (chamber) cards in a draw pile. Online clients use the
## per-deck bomb counts from the snapshot; offline/host counts live.
func _deck_bombs(pile_id: String) -> int:
	if pile_id == "A" and _snapshot_bombs_a >= 0:
		return _snapshot_bombs_a
	if pile_id == "B" and _snapshot_bombs_b >= 0:
		return _snapshot_bombs_b
	var pile: Array[Card] = game.deck.pile_a if pile_id == "A" else game.deck.pile_b
	return _count_bombs(pile)

func _count_bombs(pile: Array[Card]) -> int:
	var n := 0
	for c in pile:
		if c.type == Card.CardType.BOMB:
			n += 1
	return n

func _chamber_pct(bombs: int, size: int) -> int:
	return (bombs * 100) / size if size > 0 else 0

func _refresh_discard() -> void:
	_update_discard_mesh_3d()

func _refresh_opponents() -> void:
	_place_opponents_3d()

func _refresh_hand() -> void:
	# Return used CardNodes to the pool for reuse (avoids allocation churn).
	for c in card_nodes:
		c.visible = false
		_player_ui.remove_child(c)
		_card_node_pool.append(c)
	card_nodes.clear()

	if game.players.is_empty() or own_index >= game.players.size():
		return
	var p: PlayerData = game.players[own_index]

	var valid_plays: Array[int] = []
	if state == State.HUMAN_TURN:
		valid_plays = game.get_valid_plays(own_index)

	# During a forced draw the target may STACK any Draw card (Uno rule);
	# highlight those cards so the option is discoverable alongside the decks.
	var stackable: Array[int] = []
	if state == State.FORCED_DRAW_DECK_CHOICE and game.pending_forced_draw_count > 0 and game.pending_forced_draw_player_index == own_index:
		for i in range(p.hand.size()):
			var sc: Card = p.hand[i]
			if game.is_draw_stack_candidate(own_index, sc):
				stackable.append(i)

	# Only the local player's cards are ever rendered — opponents show avatars.
	if _own_label:
		var is_current: bool = state == State.HUMAN_TURN or game.current_index == own_index
		var own_text := (">> " if is_current else "") + p.display_name + " • %d cards" % p.hand_size()
		if p.banked_lives > 0:
			own_text += " • %d %s" % [p.banked_lives, "life" if p.banked_lives == 1 else "lives"]
		_own_label.text = own_text
		_own_label.add_theme_color_override("font_color",
			Color(0.95, 0.85, 0.3) if is_current else p.color.lightened(0.25))
		_own_label.visible = true

	if _hand_marker == null:
		return
	var n := p.hand.size()
	if n == 0:
		return

	# Fan the hand around the player_ui CenterCards marker, pivoted at the
	# bottom-center of each card so hover lift + rotation look natural.
	var spacing := HANDCARD_W * 0.55
	var total_w := (n - 1) * spacing + HANDCARD_W
	var x0 := _hand_marker.position.x - total_w / 2.0
	var y0 := _hand_marker.position.y - HANDCARD_H

	for i in range(n):
		var is_playable := (state == State.HUMAN_TURN and i in valid_plays) or (state == State.FORCED_DRAW_DECK_CHOICE and i in stackable)
		var cn: CardNode
		if _card_node_pool.size() > 0:
			cn = _card_node_pool.pop_back()
		else:
			cn = CardNode.new()
		cn.setup(p.hand[i], true, HANDCARD_W, HANDCARD_H)
		cn.set_playable(is_playable)
		cn.card_clicked.connect(_on_card_clicked)
		cn.position = Vector2(x0 + i * spacing, y0 - (PLAYABLE_LIFT if is_playable else 0.0))
		cn.pivot_offset = Vector2(HANDCARD_W / 2.0, HANDCARD_H)
		cn.rotation_degrees = lerpf(-10.0, 10.0, float(i) / maxf(n - 1, 1))
		cn.visible = true
		_player_ui.add_child(cn)
		card_nodes.append(cn)

func _refresh_top_bar() -> void:
	if turn_label:
		if game.game_over:
			turn_label.text = "GAME OVER"
		elif state == State.JUMP_IN:
			turn_label.text = "JUMP IN! — play a matching card"
		elif state == State.HUMAN_TURN:
			turn_label.text = "YOUR TURN - Play a card or draw"
		elif game.players.is_empty() or own_index >= game.players.size():
			turn_label.text = "Waiting for players..."
		else:
			turn_label.text = "%s's turn" % game.current_player().display_name

	if active_display:
		var col_name: String = Card.CardColor.keys()[game.active_color]
		if game.active_number >= 0:
			active_display.text = "Color: %s | Number: %d" % [col_name, game.active_number]
		else:
			active_display.text = "Color: %s" % col_name

	_highlight_decks(state == State.HUMAN_TURN or state == State.FORCED_DRAW_DECK_CHOICE or state == State.LAST_SHOT)

func _highlight_decks(highlight: bool) -> void:
	if highlight:
		# Decks are ALWAYS drawable during your turn; the invisible click zones
		# stay live so drawing is never blocked (keyboard A/B works too). Also
		# shown while a forced-draw target, who must pick which deck to draw.
		if state == State.HUMAN_TURN and game.get_valid_plays(own_index).is_empty():
			_show_notification("No valid plays! Click Deck A or Deck B to draw.")
		if _draw_btn_a:
			_draw_btn_a.visible = true
			_draw_btn_a.disabled = false
		if _draw_btn_b:
			_draw_btn_b.visible = true
			_draw_btn_b.disabled = false
		_reposition_draw_zones()
		_set_piles_glow(true)
	else:
		if _draw_btn_a:
			_draw_btn_a.visible = false
		if _draw_btn_b:
			_draw_btn_b.visible = false
		_set_piles_glow(false)

# ── 3D discard update ────────────────────────────────────────────────

func _update_discard_mesh_3d() -> void:
	if _discard_sprite == null or _discard_card_node == null:
		return
	if game.deck.discard.is_empty():
		_discard_sprite.visible = false
	else:
		var top_card: Card = game.deck.discard.back()
		_discard_card_node.setup(top_card, true, 128.0, 192.0)
		_discard_card_node.queue_redraw()
		_discard_sprite.visible = true

# ── Turn Management ───────────────────────────────────────────────────

func _check_turn() -> void:
	# Never clobber an in-flight chamber reveal (e.g. the AI's last-shot bomb
	# path calls _check_turn() right after the un-awaited _start_chamber_draw(),
	# which would bounce CHAMBER_REVEAL back to AI_THINKING and re-trigger the
	# last shot mid-sequence). The chamber coroutine resumes via _check_turn()
	# itself after setting state = WAITING.
	if state == State.CHAMBER_REVEAL:
		return

	if game.jump_in_open:
		state = State.JUMP_IN
		_hide_timer_ui()
		_refresh_all()
		return

	if game.game_over:
		state = State.GAME_OVER
		_hide_timer_ui()
		_refresh_all()
		_show_game_over()
		return

	# Check if local player is eliminated — enter spectator mode.
	if own_index >= 0 and own_index < game.players.size():
		var me: PlayerData = game.players[own_index]
		if me.eliminated:
			state = State.SPECTATING
			_was_my_turn = false
			_hide_timer_ui()
			_hide_end_turn_btn()
			_show_notification("☠ You are eliminated — spectating...", 3.0)
			_refresh_all()
			return

	# Check if the current player has a pending forced draw (from Draw Two/Four/Ten).
	if game.pending_forced_draw_count > 0 and game.pending_forced_draw_player_index == game.current_index:
		if game.current_index == own_index:
			# Human target: show deck choice prompt.
			state = State.FORCED_DRAW_DECK_CHOICE
			var draw_count := game.pending_forced_draw_count
			_show_notification("⚡ You must draw %d cards! Stack the same +N card (any color), or pick Deck A/B." % draw_count, 5.0)
			_refresh_all()
		else:
			# AI target: auto-choose a random deck.
			if is_tutorial:
				# The director scripts the AI target's forced-draw resolution.
				state = State.WAITING
				_refresh_all()
				return
			var ai_pile := "A" if randi() % 2 == 0 else "B"
			state = State.AI_THINKING
			_ai_timer = randf_range(0.6, 1.0)  # Brief pause before resolving
			_refresh_all()
			# Store the choice for the AI to resolve.
			_pending_ai_forced_draw_pile = ai_pile
		return

	# Tutorial: AI seats are scripted by the director, never the game loop.
	if is_tutorial and game.current_index != own_index:
		_was_my_turn = false
		state = State.WAITING
		_hide_timer_ui()
		_refresh_all()
		return

	if game.current_index == own_index:
		if not _was_my_turn:
			_was_my_turn = true
			_play_your_turn_animation()
		# In SHEDDING_RACE, a player with 1 card must take the Last Shot.
		if game.mode == GameState.Mode.SHEDDING_RACE and game.players[own_index].hand_size() == 1 and game.pending_last_shot:
			state = State.LAST_SHOT
			_play_center_banner("🎯 LAST SHOT!", Color(1.0, 0.3, 0.3), 42, 1.2)
			_show_notification("Pull the trigger! Choose Deck A or Deck B to win.", 5.0)
			_refresh_all()
		else:
			var valid := game.get_valid_plays(own_index)
			if valid.size() > 0:
				state = State.HUMAN_TURN
				_show_notification("Your turn! Click a highlighted card to play it.")
			else:
				state = State.HUMAN_TURN
				_show_notification("No valid plays! Choose Deck A or Deck B to draw.")
			_refresh_all()
	else:
		_was_my_turn = false
		if is_online:
			state = State.WAITING
			_hide_timer_ui()
			_refresh_all()
		else:
			state = State.AI_THINKING
			_ai_timer = randf_range(1.2, 1.8)
			_refresh_all()

	# Reset the turn timer for the new turn.
	_reset_turn_timer()

# ── Human Input Handlers ──────────────────────────────────────────────

func _on_card_clicked(card_node: CardNode) -> void:
	var card: Card = card_node.card_data
	var hand_idx := -1
	for i in range(game.players[own_index].hand.size()):
		if game.players[own_index].hand[i] == card:
			hand_idx = i
			break
	if hand_idx == -1:
		return
	_play_by_hand_index(hand_idx)

## Core path for playing the card at hand_idx (mouse or keyboard).
func _play_by_hand_index(hand_idx: int) -> void:
	if _paused:
		return
	if game.current_index != own_index:
		return
	if hand_idx < 0 or hand_idx >= game.players[own_index].hand.size():
		return

	# Tutorial: restrict which hand cards the player may play this step.
	if is_tutorial:
		if not (_tut_input_hands.is_empty() or hand_idx in _tut_input_hands):
			_show_notification("Not that card -- follow the tutorial prompt!", 1.5)
			_play_sfx(_sfx_button)
			return

	var card: Card = game.players[own_index].hand[hand_idx]

	# Uno-style stacking: a forced-draw target may play ANY Draw card (any +N,
	# any color) to ADD to the punishment instead of choosing a deck.
	# NONE-color Draw cards go through the color popup first; colored ones
	# resolve immediately.
	if state == State.FORCED_DRAW_DECK_CHOICE:
		if game.is_draw_stack_candidate(own_index, card):
			_pending_card = card
			_pending_options = {"hand_idx": hand_idx}
			_pending_next_step = "stack"
			if card.color == Card.CardColor.NONE:
				state = State.HUMAN_COLOR_SELECT
				_show_color_selector()
			else:
				_dismiss_all_overlays()
				_play_sfx(_sfx_card_play)
				_finalize_or_send_play()
		else:
			_show_notification("Only the same +N value can be stacked here!", 1.5)
			_play_sfx(_sfx_button)
		return

	if state != State.HUMAN_TURN:
		return

	if not card.matches(game.active_color, game.active_number, game.active_action_id):
		_show_notification("Can't play that card!", 1.5)
		_play_sfx(_sfx_button)
		return

	match card.type:
		Card.CardType.WILD:
			_pending_card = card
			_pending_options = {"hand_idx": hand_idx}
			if card.action_id == "wild_sabotage":
				state = State.HUMAN_TARGET_SELECT
				_show_target_selector("Sabotage: redirect draw to...")
			else:
				state = State.HUMAN_COLOR_SELECT
				_show_color_selector()
			return
		Card.CardType.ACTION:
			match card.action_id:
				"swap_hands":
					_pending_card = card
					_pending_options = {"hand_idx": hand_idx}
					if card.color == Card.CardColor.NONE:
						_pending_next_step = "target"
						state = State.HUMAN_COLOR_SELECT
						_show_color_selector()
						return
					state = State.HUMAN_TARGET_SELECT
					_show_target_selector("Swap hands with...")
					return
				"wild_sabotage":
					pass
				"choose_deck":
					_pending_card = card
					_pending_options = {"hand_idx": hand_idx}
					if card.color == Card.CardColor.NONE:
						_pending_next_step = "target"
						state = State.HUMAN_COLOR_SELECT
						_show_color_selector()
						return
					state = State.HUMAN_TARGET_SELECT
					_show_target_selector("Force next draw for...")
					return
				"draw_two", "draw_four", "draw_ten":
					_pending_card = card
					_pending_options = {"hand_idx": hand_idx}
					# NONE-color draw cards: choose color for the next turn. Colored
					# draw cards play immediately — the TARGET picks the draw pile
					# when they resolve the forced draw (FORCED_DRAW_DECK_CHOICE).
					if card.color == Card.CardColor.NONE:
						state = State.HUMAN_COLOR_SELECT
						_show_color_selector()
					else:
						_finalize_or_send_play()
					return
				"peek":
					_pending_card = card
					_pending_options = {"hand_idx": hand_idx}
					if card.color == Card.CardColor.NONE:
						_pending_next_step = "peek"
						state = State.HUMAN_COLOR_SELECT
						_show_color_selector()
						return
					state = State.HUMAN_PEEK_SELECT
					_show_peek_selector()
					return
				"extra_life", "rotate_decks":
					# NONE-color action cards: choose color for the next turn.
					if card.color == Card.CardColor.NONE:
						_pending_card = card
						_pending_options = {"hand_idx": hand_idx}
						state = State.HUMAN_COLOR_SELECT
						_show_color_selector()
						return

	_pending_card = card
	_pending_options = {}

	# Play sound for valid card selection
	_play_sfx(_sfx_card_play)

	# Plain cards and non-special actions finish through the shared path
	# (offline executes locally, online host self-routes, online client sends intent).
	_finalize_or_send_play()

func _on_deck_clicked(pile_id: String) -> void:
	if _paused or state == State.SPECTATING:
		return

	# Tutorial: deck clicks only allowed when the current step calls for one
	# (forced-draw deck choice is always part of an on-going tutorial step).
	if is_tutorial and not _tut_allow_draw and state != State.FORCED_DRAW_DECK_CHOICE:
		_show_notification("Not now -- follow the tutorial prompt!", 1.5)
		_play_sfx(_sfx_button)
		return

	# Handle forced draw deck choice (Draw Two/Four/Ten target).
	if state == State.FORCED_DRAW_DECK_CHOICE and game.pending_forced_draw_player_index == own_index:
		_play_sfx(_sfx_card_draw)
		if is_online and not is_host_here():
			send_intent({"kind": "forced_draw", "pile": pile_id})
			state = State.WAITING
			_refresh_all()
			return
		var fd_count: int = game.pending_forced_draw_count
		_animate_forced_draw(pile_id, own_index, fd_count)
		game.resolve_forced_draw(pile_id)
		if is_online:
			_broadcast_snapshot()
		_refresh_all()
		_check_turn()
		if fd_count > 0:
			_reveal_hand_tail(fd_count, 0.43, 0.32)
		if is_tutorial:
			tutorial_action_done.emit("forced_draw_choice", {"pile": pile_id, "count": fd_count})
		return

	# Handle Last Shot deck choice (1 card remaining in SHEDDING_RACE).
	if state == State.LAST_SHOT and game.pending_last_shot and game.current_index == own_index:
		_play_sfx(_sfx_card_draw)
		if is_online and not is_host_here():
			send_intent({"kind": "last_shot", "pile": pile_id})
			state = State.WAITING
			_refresh_all()
			return
		game.trigger_last_shot(own_index, pile_id)
		# Fly a ghost of the drawn card from the pile to the hand.
		var ls_drawn: Card = null
		if game.pending_bomb != null:
			ls_drawn = game.pending_bomb
		elif not game.players[own_index].hand.is_empty():
			ls_drawn = game.players[own_index].hand.back()
		_fly_draw_to_hand(pile_id, ls_drawn)
		if game.pending_bomb != null:
			_refresh_all()
			var ls_p: PlayerData = game.players[own_index]
			var ls_has_diffuse := false
			for c in ls_p.hand:
				if c.type == Card.CardType.DIFFUSE:
					ls_has_diffuse = true
					break
			if ls_has_diffuse:
				state = State.DIFFUSE_DECISION
				_show_diffuse_decision()
			else:
				_start_chamber_draw()
			return
		if is_online:
			_broadcast_snapshot()
		_refresh_all()
		_check_turn()
		_reveal_hand_tail(1, 0.3)
		return

	if state != State.HUMAN_TURN:
		return
	if game.current_index != own_index:
		return

	# Remote client: send draw intent to host, wait for snapshot.
	if is_online and not is_host_here():
		send_intent({"kind": "draw", "pile": pile_id})
		state = State.WAITING
		_hide_timer_ui()  # Don't time out while waiting for snapshot
		_refresh_all()
		return

	# Play draw sound
	_play_sfx(_sfx_card_draw)

	# Acting player is here (host in online mode, or offline solo): run locally.
	# end_turn=false: the player may play the drawn card immediately.
	game.draw_card(own_index, pile_id, true, false)

	# Fly a ghost of the drawn card from the pile to the hand.
	var drawn: Card = null
	if game.pending_bomb != null:
		drawn = game.pending_bomb
	elif not game.players[own_index].hand.is_empty():
		drawn = game.players[own_index].hand.back()
	_fly_draw_to_hand(pile_id, drawn)

	if game.pending_bomb != null:
		_refresh_all()
		var p: PlayerData = game.players[own_index]
		var has_diffuse := false
		for c in p.hand:
			if c.type == Card.CardType.DIFFUSE:
				has_diffuse = true
				break
		if has_diffuse:
			state = State.DIFFUSE_DECISION
			_show_diffuse_decision()
		else:
			_start_chamber_draw()
		return

	# Stay on this player's turn — refresh hand so the drawn card is playable.
	# The turn only ends when they play a card or click End Turn.
	_state_after_draw()
	_refresh_all()
	_reveal_hand_tail(1, 0.3)
	if is_tutorial:
		tutorial_action_done.emit("draw", {"pile": pile_id, "count": 1})

## After a voluntary draw, position and show the "End Turn" button so the
## player can skip playing the drawn card.
func _state_after_draw() -> void:
	_drew_this_turn = true
	if _end_turn_btn:
		_end_turn_btn.visible = true
		_end_turn_btn.position = Vector2(get_viewport_rect().size.x * 0.5 - 60,
			get_viewport_rect().size.y - HANDCARD_H - 42)

## Clicked "End Turn" — end the current turn without playing a card.
func _end_turn() -> void:
	if is_tutorial and not _tut_allow_end_turn:
		return
	if _end_turn_btn:
		_end_turn_btn.visible = false
	_drew_this_turn = false
	game.advance_turn()
	_play_sfx(_sfx_switch_a)
	_check_turn()
	if is_tutorial:
		tutorial_action_done.emit("end_turn", {})

## Hide the End Turn button (called whenever a card is played or turn changes).
func _hide_end_turn_btn() -> void:
	if _end_turn_btn:
		_end_turn_btn.visible = false
	_drew_this_turn = false

# ── Turn Timer ────────────────────────────────────────────────────────

## Resets the turn timer to the full time limit and shows the timer UI.
func _reset_turn_timer() -> void:
	_turn_timer = TURN_TIME_LIMIT
	if _turn_timer_ring:
		_turn_timer_ring.visible = true
		_turn_timer_ring.call("set_color", _current_timer_color())
		_turn_timer_ring.call("set_pct", 1.0)
	if _turn_timer_label:
		_turn_timer_label.text = str(int(TURN_TIME_LIMIT))

## Updates the visual timer ring and label each frame.
func _update_timer_ui() -> void:
	var pct := clampf(_turn_timer / TURN_TIME_LIMIT, 0.0, 1.0)
	var timer_color := _current_timer_color()
	if _turn_timer_ring:
		_turn_timer_ring.call("set_color", timer_color)
		_turn_timer_ring.call("set_pct", pct)
	if _turn_timer_label:
		_turn_timer_label.text = str(int(maxf(0, _turn_timer)))
		_turn_timer_label.add_theme_color_override("font_color", timer_color.lightened(0.4))

## Color of the player whose turn is currently timed.
func _current_timer_color() -> Color:
	if game == null or game.players.is_empty():
		return Color(0.2, 0.8, 0.3)
	return game.players[game.current_index].color

## Hides the timer UI.
func _hide_timer_ui() -> void:
	if _turn_timer_ring:
		_turn_timer_ring.visible = false
	if _turn_timer_label:
		_turn_timer_label.visible = false

## Called when the turn timer expires — forces the current player to draw 4 cards
## (2 from each deck) and ends their turn.
func _on_turn_timer_expired() -> void:
	var idx := game.current_index
	var p: PlayerData = game.players[idx]
	var is_human := idx == own_index

	# If the timed-out player is the forced-draw target, they forfeit the
	# deck/stack decision: resolve the pending forced draw (cards drawn +
	# turn consumed) instead of stacking an extra generic 4-card penalty on
	# top, and clear the pending state so it can't linger stale.
	if game.pending_forced_draw_count > 0 and game.pending_forced_draw_player_index == idx:
		if is_human:
			_show_notification("⏰ Time's up! Drawing the forced %d cards..." % game.pending_forced_draw_count, 2.5)
		else:
			_show_notification("⏰ %s ran out of time! Drawing forced cards..." % p.display_name, 2.5)
		_play_sfx(_sfx_switch_b)
		var ff_pile: String = "A" if randi() % 2 == 0 else "B"
		var ff_count: int = game.pending_forced_draw_count
		_animate_forced_draw(ff_pile, idx, ff_count)
		game.resolve_forced_draw(ff_pile)
		_refresh_all()
		_check_turn()
		if is_human and ff_count > 0:
			_reveal_hand_tail(ff_count, 0.43, 0.32)
		return

	_hide_timer_ui()
	_hide_end_turn_btn()

	if is_human:
		_show_notification("⏰ Time's up! Drawing 4 cards...", 2.5)
	else:
		_show_notification("⏰ %s ran out of time! Drawing 4 cards..." % p.display_name, 2.5)

	_play_sfx(_sfx_switch_b)

	# Draw 2 from each deck.
	var penalty_drawn := 0
	for pile_id in ["A", "B"]:
		for _i in range(2):
			var card := game.deck.draw_from(pile_id)
			if card:
				if card.type == Card.CardType.BOMB:
					# Don't trigger chamber on timer draw — return bomb and draw safe.
					game.deck.return_bomb_randomly(card)
					card = game.deck.draw_from(pile_id)
				if card and card.type != Card.CardType.BOMB:
					p.hand.append(card)
					penalty_drawn += 1

		# Animate the forced draw ghosts.
		_animate_forced_draw(pile_id, idx, 2)

	_game_log("⏰ %s's turn expired — drew 4 cards (2 from each deck)." % p.display_name)
	_refresh_all()

	# End the turn.
	game.advance_turn()
	_check_turn()
	if is_human and penalty_drawn > 0:
		_reveal_hand_tail(penalty_drawn, 0.43, 0.32)

## Keyboard shortcuts: 1-9 play the matching hand card, A/B draw from a deck.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if key_event.keycode == KEY_ESCAPE:
		_toggle_pause()
		return
	if _paused or state == State.SPECTATING:
		return

	# Forced draw deck choice: A/B keys choose the deck, number keys stack a
	# matching Draw card (if the card at that index is stackable).
	if state == State.FORCED_DRAW_DECK_CHOICE and game.pending_forced_draw_player_index == own_index:
		var key := key_event.keycode
		if key == KEY_A or key == KEY_LEFT:
			_on_deck_clicked("A")
		elif key == KEY_B or key == KEY_RIGHT:
			_on_deck_clicked("B")
		elif key >= KEY_1 and key <= KEY_9:
			_play_by_hand_index(key - KEY_1)
		elif key == KEY_0:
			_play_by_hand_index(9)
		return

	# Last Shot: A/B keys choose which deck to pull the chamber card from.
	if state == State.LAST_SHOT and game.pending_last_shot and game.current_index == own_index:
		var ls_key := key_event.keycode
		if ls_key == KEY_A or ls_key == KEY_LEFT:
			_on_deck_clicked("A")
		elif ls_key == KEY_B or ls_key == KEY_RIGHT:
			_on_deck_clicked("B")
		return

	if state != State.HUMAN_TURN:
		return
	if game.current_index != own_index:
		return
	var key := key_event.keycode
	if key == KEY_A or key == KEY_LEFT:
		_on_deck_clicked("A")
	elif key == KEY_B or key == KEY_RIGHT:
		_on_deck_clicked("B")
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		# After drawing, Enter ends turn without playing.
		if _drew_this_turn:
			_end_turn()
	elif key >= KEY_1 and key <= KEY_9:
		_play_by_hand_index(key - KEY_1)
	elif key == KEY_0:
		_play_by_hand_index(9)

# ── Jump In (matching-card response) ─────────────────────────────────

## Called by GameState whenever the jump-in window opens or reopens (chains).
func _on_jump_in_available(candidates: Array) -> void:
	_jump_in_window = true
	_jump_in_timer = 0.0
	state = State.JUMP_IN

	if is_tutorial:
		# No AI auto-answer or timeout — the director drives the demo. The
		# JUMP IN prompt itself is also suppressed: the director shows it at
		# the exact beat it wants (right after its explanatory popup closes).
		_pending_ai_jump_index = -1
		_ai_jump_delay = 0.0
	elif not is_online:
		# Offline: the first AI copy answers automatically after a short delay.
		_pending_ai_jump_index = -1
		for idx in candidates:
			if int(idx) != own_index:
				_pending_ai_jump_index = int(idx)
				break
		_ai_jump_delay = randf_range(0.8, 1.4)
	else:
		_pending_ai_jump_index = -1

	_refresh_all()
	if own_index in candidates and not is_tutorial:
		_show_jump_in_prompt()

	if is_tutorial:
		tutorial_action_done.emit("jump_in_window", {"candidates": candidates})

## Offline AI answers the jump-in window.
func _ai_jump_in(who: int) -> void:
	if not game.jump_in_open:
		return
	if not game.jump_in(who):
		return
	_play_sfx(_sfx_switch_b)
	_hide_jump_prompt()
	_refresh_all()
	if not game.jump_in_open:
		_jump_in_window = false
		_check_turn()
		if is_tutorial:
			tutorial_action_done.emit("jump_done", {"who": "ai"})

## Local player clicks "Jump In!".
func _do_jump_in() -> void:
	if not game.jump_in_open:
		return
	if is_online and not is_host_here():
		_hide_jump_prompt()
		send_intent({"kind": "jump_in"})
		state = State.WAITING
		_refresh_all()
		return
	if not game.jump_in(own_index):
		return
	_play_sfx(_sfx_switch_b)
	_hide_jump_prompt()
	_refresh_all()
	if not game.jump_in_open:
		_jump_in_window = false
		_check_turn()
		if is_tutorial:
			tutorial_action_done.emit("jump_done", {"who": "me"})

## Local player passes — the window stays open for others / timeout.
func _pass_jump_in() -> void:
	_hide_jump_prompt()
	if not game.jump_in_open:
		return
	if is_online and not is_host_here():
		state = State.WAITING
		_refresh_all()
		return
	_show_notification("Jump-in window open...", JUMP_WINDOW_TIME)
	if is_tutorial:
		tutorial_action_done.emit("jump_pass", {})

## Closes the window (timeout) and continues the turn.
func _close_jump_window() -> void:
	if not _jump_in_window:
		return
	_jump_in_window = false
	_pending_ai_jump_index = -1
	_hide_jump_prompt()
	if not is_online or is_host_here():
		game.close_jump_in_window()
		if is_online:
			_broadcast_snapshot()
		_refresh_all()
		_check_turn()

func _show_jump_in_prompt() -> void:
	if _jump_prompt:
		return
	_dismiss_all_overlays()
	var vbox := VBoxContainer.new()
	vbox.name = "JumpPrompt"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -190
	vbox.offset_right = 190
	vbox.offset_top = -120
	vbox.offset_bottom = 120
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(vbox)
	_jump_prompt = vbox

	var title := Label.new()
	title.text = "JUMP IN!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "You have the same card!"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	vbox.add_child(sub)

	if game.last_played_card:
		var card_view := CardNode.new()
		card_view.setup(game.last_played_card, true, 66, 99)
		card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card_center := CenterContainer.new()
		card_center.add_child(card_view)
		vbox.add_child(card_center)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)

	var jump_btn := _make_kenney_button("Jump In!", Vector2(150, 50), 18, Color(0.85, 0.6, 0.1))
	jump_btn.pressed.connect(_do_jump_in)
	row.add_child(jump_btn)

	var pass_btn := _make_kenney_button("Pass", Vector2(110, 50), 16, Color(0.35, 0.35, 0.42))
	pass_btn.pressed.connect(_pass_jump_in)
	row.add_child(pass_btn)

	_play_sfx(_sfx_button)

func _hide_jump_prompt() -> void:
	if _jump_prompt:
		_jump_prompt.queue_free()
		_jump_prompt = null

# ── Pause (offline vs AI only) ───────────────────────────────────────

func _toggle_pause() -> void:
	if is_tutorial:
		return
	if is_online:
		_show_notification("Pause is only available in offline games.", 1.5)
		return
	if state == State.CHAMBER_REVEAL or state == State.GAME_OVER:
		_show_notification("Can't pause right now.", 1.5)
		return
	_paused = not _paused
	if _paused:
		_show_pause_overlay()
	else:
		_hide_pause_overlay()
		_play_sfx(_sfx_click_b)
		_show_notification("Game resumed.", 1.0)

func _show_pause_overlay() -> void:
	if _pause_overlay:
		return
	var dim := ColorRect.new()
	dim.name = "PauseOverlay"
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_pause_overlay = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	vbox.add_child(title)

	var resume_btn := _make_kenney_button("Resume", Vector2(200, 54), 20, Color(0.2, 0.6, 0.3))
	resume_btn.pressed.connect(_toggle_pause)
	vbox.add_child(resume_btn)

	var menu_btn := _make_kenney_button("Main Menu", Vector2(200, 54), 20, Color(0.4, 0.35, 0.45))
	menu_btn.pressed.connect(_on_play_again)
	vbox.add_child(menu_btn)

	_play_sfx(_sfx_button)

func _hide_pause_overlay() -> void:
	if _pause_overlay:
		_pause_overlay.queue_free()
		_pause_overlay = null

# ── Color Selector ────────────────────────────────────────────────────

func _show_color_selector() -> void:
	_dismiss_all_overlays()
	_prepare_overlay_popup()
	overlay.visible = true

	var title := Label.new()
	title.text = "Choose a color:"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(title)

	# Windows-XP-logo layout: a 2x2 grid of four color panes (top row
	# green→blue, bottom row yellow→red, exactly like the old XP flag).
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	overlay_vbox.add_child(grid)

	var colors := [
		["Green", Color(0.15, 0.65, 0.28)],
		["Red", Color(0.85, 0.18, 0.18)],
		["Orange", Color(0.95, 0.5, 0.12)],
		["Purple", Color(0.55, 0.2, 0.78)],
	]
	var indices := [Card.CardColor.GREEN, Card.CardColor.RED, Card.CardColor.ORANGE, Card.CardColor.PURPLE]

	for i in range(4):
		var btn := _make_color_button(colors[i][0], colors[i][1], Vector2(150, 150), 18)
		var idx: int = indices[i]
		btn.pressed.connect(_on_color_chosen.bind(idx))
		grid.add_child(btn)

	_center_overlay_vbox()

## Switches overlay_vbox to a content-hugging, fully-centered popup so selectors
## render dead-center and sized to their content instead of pinned top-left inside
## a fixed oversized box. Call before adding children, then _center_overlay_vbox().
func _prepare_overlay_popup() -> void:
	overlay_vbox.set_anchors_preset(Control.PRESET_CENTER)
	overlay_vbox.offset_left = 0
	overlay_vbox.offset_right = 0
	overlay_vbox.offset_top = 0
	overlay_vbox.offset_bottom = 0
	overlay_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay_vbox.add_theme_constant_override("separation", 12)

## Sizes the popup to its content and pins it to the dead center of the overlay.
## Call after all children are added — guarantees centering regardless of anchor
## /grow quirks instead of drifting to a corner.
func _center_overlay_vbox() -> void:
	overlay_vbox.size = overlay_vbox.get_combined_minimum_size()
	overlay_vbox.position = Vector2(
		(overlay.size.x - overlay_vbox.size.x) * 0.5,
		(overlay.size.y - overlay_vbox.size.y) * 0.5
	)

func _on_color_chosen(color: int) -> void:
	overlay.visible = false
	_clear_overlay()
	_play_sfx(_sfx_button)

	_pending_options["chosen_color"] = color

	if _pending_card and _pending_card.type == Card.CardType.WILD and _pending_card.action_id == "wild_sabotage" and not _pending_options.has("target_player_index"):
		state = State.HUMAN_TARGET_SELECT
		_show_target_selector("Sabotage: redirect draw to...")
		return

	# Consume any chained step so a canceled flow cannot replay it later.
	var next := _pending_next_step
	_pending_next_step = ""
	match next:
		"stack":
			# Color picked for a NONE-color Draw card being stacked onto a forced draw.
			state = State.FORCED_DRAW_DECK_CHOICE
			_play_sfx(_sfx_card_play)
			_finalize_or_send_play()
			return
		"target":
			state = State.HUMAN_TARGET_SELECT
			_show_target_selector("Swap hands with..." if _pending_card and _pending_card.action_id == "swap_hands" else "Force next draw for...")
			return
		"peek":
			state = State.HUMAN_PEEK_SELECT
			_show_peek_selector()
			return

	_finalize_or_send_play()

func _finalize_or_send_play() -> void:
	# Tutorial routing info is captured BEFORE the pending step is consumed.
	var tut_was_stack := _pending_next_step == "stack"
	var tut_card_action: String = _pending_card.action_id if _pending_card else ""
	_pending_next_step = ""  # any chained step (stack/target/peek) is being consumed
	_hide_end_turn_btn()  # Turn is being played, hide the button
	_hide_timer_ui()  # Turn is being played, stop the timer
	var hand_idx: int = _pending_options.get("hand_idx", -1)
	if hand_idx == -1:
		for i in range(game.players[own_index].hand.size()):
			if game.players[own_index].hand[i] == _pending_card:
				hand_idx = i
				break

	if hand_idx == -1:
		_pending_card = null
		_pending_options = {}
		state = State.WAITING
		return

	_pending_options["hand_idx"] = hand_idx

	# Ghost of the played card flies to the discard pile.
	if _pending_card:
		_fly_card_to_discard(_pending_card)

	if is_online:
		send_intent({"kind": "play", "hand_index": hand_idx, "options": _pending_options})
		_show_notification("Played %s" % _pending_card.display_name, 1.5)
	else:
		# Capture the draw-card target size so the forced draw can be animated.
		var draw_target := -1
		var draw_pile := "A"
		var draw_before := 0
		if _pending_card and _pending_card.action_id in ["draw_two", "draw_four", "draw_ten"]:
			draw_target = game._next_alive_index(own_index, game.direction)
			draw_pile = _pending_options.get("chosen_pile", "A")
			draw_before = game.players[draw_target].hand.size()
		game.play_card(own_index, hand_idx, _pending_options)
		_show_notification("Played %s" % _pending_card.display_name, 1.5)
		if _pending_card:
			_play_action_sound(_pending_card.action_id)
		if draw_target >= 0:
			var added := game.players[draw_target].hand.size() - draw_before
			if added > 0:
				_animate_forced_draw(draw_pile, draw_target, added)

	_pending_card = null
	_pending_options = {}
	state = State.WAITING
	_refresh_all()
	_check_turn()
	if is_tutorial:
		tutorial_action_done.emit("card", {"action_id": tut_card_action, "hand_idx": hand_idx, "stack": tut_was_stack})

# ── Target Selector ───────────────────────────────────────────────────

func _show_target_selector(prompt: String) -> void:
	_dismiss_all_overlays()
	_prepare_overlay_popup()
	overlay.visible = true

	var title := Label.new()
	title.text = prompt
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	overlay_vbox.add_child(row)

	for i in range(game.players.size()):
		if i == own_index:
			continue
		var p: PlayerData = game.players[i]
		if p.eliminated:
			continue
		var btn := _make_kenney_button(p.display_name, Vector2(130, 50), 16)
		btn.pressed.connect(_on_target_chosen.bind(i))
		row.add_child(btn)

	_center_overlay_vbox()

func _on_target_chosen(target_idx: int) -> void:
	overlay.visible = false
	_clear_overlay()
	_play_sfx(_sfx_button)

	_pending_options["target_player_index"] = target_idx

	if _pending_card and _pending_card.type == Card.CardType.WILD and _pending_card.action_id == "wild_sabotage" and not _pending_options.has("chosen_color"):
		state = State.HUMAN_COLOR_SELECT
		_show_color_selector()
		return

	if _pending_card.action_id == "choose_deck":
		state = State.HUMAN_DECK_CHOICE
		_show_deck_choice_selector()
		return

	_finalize_or_send_play()

# ── Deck Choice (for Choose a Deck card) ──────────────────────────────

func _show_deck_choice_selector(prompt: String = "Force next draw from which deck?") -> void:
	_dismiss_all_overlays()
	_prepare_overlay_popup()
	overlay.visible = true

	var title := Label.new()
	title.text = prompt
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	overlay_vbox.add_child(row)

	for pile_id in ["A", "B"]:
		var btn := _make_kenney_button("Deck %s (%d cards)" % [pile_id, game.deck.pile_a.size() if pile_id == "A" else game.deck.pile_b.size()], Vector2(200, 52), 16)
		btn.pressed.connect(_on_deck_choice_chosen.bind(pile_id))
		row.add_child(btn)

	_center_overlay_vbox()

func _on_deck_choice_chosen(pile_id: String) -> void:
	overlay.visible = false
	_clear_overlay()
	_play_sfx(_sfx_button)

	_pending_options["chosen_pile"] = pile_id
	_finalize_or_send_play()

# ── Peek Selector ─────────────────────────────────────────────────────

func _show_peek_selector() -> void:
	_dismiss_all_overlays()
	_prepare_overlay_popup()
	overlay.visible = true

	var title := Label.new()
	title.text = "Peek at which deck?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	overlay_vbox.add_child(row)

	for pile_id in ["A", "B"]:
		var btn := _make_kenney_button("Deck %s" % pile_id, Vector2(150, 50), 16)
		btn.pressed.connect(_on_peek_chosen.bind(pile_id))
		row.add_child(btn)

	_center_overlay_vbox()

func _on_peek_chosen(pile_id: String) -> void:
	overlay.visible = false
	_clear_overlay()

	if overlay_vbox and overlay_vbox.get_parent():
		overlay_vbox.get_parent().remove_child(overlay_vbox)
		overlay_vbox.queue_free()

	overlay_vbox = VBoxContainer.new()
	overlay_vbox.set_anchors_preset(Control.PRESET_CENTER)
	overlay_vbox.offset_left = -250
	overlay_vbox.offset_right = 250
	overlay_vbox.offset_top = -130
	overlay_vbox.offset_bottom = 130
	overlay_vbox.add_theme_constant_override("separation", 12)
	overlay.add_child(overlay_vbox)

	_pending_options["chosen_pile"] = pile_id

	var top_cards: Array[Card] = []
	if is_online:
		# In online mode, host sends peek data privately.
		# Show placeholder until _rpc_private(peek_result) arrives.
		var wait_lbl := Label.new()
		wait_lbl.text = "Waiting for peek data..."
		wait_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wait_lbl.add_theme_font_size_override("font_size", 16)
		wait_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
		overlay_vbox.add_child(wait_lbl)
		# Send the peek play intent; host replies with peek data privately.
		send_intent({"kind": "play", "hand_index": _pending_options.get("hand_idx", -1), "options": _pending_options.duplicate(true)})
		overlay.visible = true
		return

	top_cards = game.deck.peek(pile_id, 3)

	var title2 := Label.new()
	title2.text = "Top 3 of Deck %s:" % pile_id
	title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title2.add_theme_font_size_override("font_size", 20)
	title2.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(title2)

	for c in top_cards:
		var card_lbl := Label.new()
		card_lbl.text = c.display_name
		card_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_lbl.add_theme_font_size_override("font_size", 16)
		card_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		overlay_vbox.add_child(card_lbl)

	var close_btn := _make_kenney_button("Close", Vector2(130, 44), 16)
	close_btn.pressed.connect(_on_peek_close)
	overlay_vbox.add_child(close_btn)

	overlay.visible = true

func _on_peek_close() -> void:
	overlay.visible = false
	_clear_overlay()

	if is_online:
		# In online mode, the play intent was already sent when peek was chosen.
		_pending_card = null
		_pending_options = {}
		state = State.WAITING
		_refresh_all()
		_check_turn()
		return

	var hand_idx: int = _pending_options.get("hand_idx", -1)
	var tut_pile: String = _pending_options.get("chosen_pile", "")
	if hand_idx >= 0:
		game.play_card(own_index, hand_idx, _pending_options)
		_show_notification("Peeked at the deck!", 1.5)

	_pending_card = null
	_pending_options = {}
	state = State.WAITING
	_refresh_all()
	_check_turn()
	if is_tutorial:
		tutorial_action_done.emit("peek", {"hand_idx": hand_idx, "chosen_pile": tut_pile})

## Builds the options dictionary for an AI card play based on the card's type/ID.
## Returns the options dict (may be empty).
func _make_ai_options(card: Card, player_idx: int) -> Dictionary:
	var opts: Dictionary = {}
	if card.type == Card.CardType.WILD:
		opts["chosen_color"] = randi() % 4
	if card.action_id == "wild_sabotage":
		opts["chosen_color"] = randi() % 4
		opts["target_player_index"] = game._next_alive_index(player_idx, game.direction)
	if card.action_id in ["swap_hands", "choose_deck"]:
		opts["target_player_index"] = game._next_alive_index(player_idx, game.direction)
	if card.action_id in ["choose_deck", "peek"]:
		opts["chosen_pile"] = "A" if randi() % 2 == 0 else "B"
	if card.color == Card.CardColor.NONE and card.type == Card.CardType.ACTION:
		opts["chosen_color"] = randi() % 4
	return opts

# ── AI Turn ───────────────────────────────────────────────────────────

func _process_ai_turn() -> void:
	if game.game_over:
		return

	var idx := game.current_index
	if idx == own_index:
		_check_turn()
		return

	var p: PlayerData = game.players[idx]

# Handle AI forced draw (Draw Two/Four/Ten target chooses deck). The AI
	# stacks a matching Draw card ~60% of the time (Uno rule) to push a larger
	# punishment to the next player before resorting to drawing.
	if game.pending_forced_draw_count > 0 and game.pending_forced_draw_player_index == idx:
		var stack_idx := -1
		for hi in range(p.hand.size()):
			var hc: Card = p.hand[hi]
			if game.is_draw_stack_candidate(idx, hc):
				stack_idx = hi
				break
		if stack_idx >= 0 and randf() < 0.6:
			var scard: Card = p.hand[stack_idx]
			var sopts := _make_ai_options(scard, idx)
			game.play_card(idx, stack_idx, sopts)
			_play_action_sound(scard.action_id)
			_refresh_all()
			_check_turn()
			return
		var ai_pile: String = _pending_ai_forced_draw_pile if _pending_ai_forced_draw_pile != "" else "A"
		_pending_ai_forced_draw_pile = ""
		# Animate the forced draw.
		_animate_forced_draw(ai_pile, idx, game.pending_forced_draw_count)
		game.resolve_forced_draw(ai_pile)
		_refresh_all()
		_check_turn()
		return

		if p.skip_next_turn:
			p.skip_next_turn = false
			game.log_event.emit("%s is skipped." % p.display_name)
			game.advance_turn()
			_refresh_all()
			_check_turn()
			return

		# AI Last Shot: 1 card in SHEDDING_RACE — must pull trigger before winning.
		if game.mode == GameState.Mode.SHEDDING_RACE and p.hand_size() == 1 and game.pending_last_shot:
			var ls_pile := "A" if randi() % 2 == 0 else "B"
			game.trigger_last_shot(idx, ls_pile)
			_refresh_all()
			if game.pending_bomb != null:
				var ls_has_diffuse := false
				for c in p.hand:
					if c.type == Card.CardType.DIFFUSE:
						ls_has_diffuse = true
						break
				if ls_has_diffuse:
					# AI auto-diffuses if possible.
					game.resolve_bomb(true)
				else:
					_start_chamber_draw()
				_refresh_all()
				_check_turn()
				return
			# Survived — overcharge is now active. AI plays its cards.
			if not game.overcharge_active:
				game.advance_turn()
				_refresh_all()
				_check_turn()
				return
			# Overcharge gives 2 plays. Play up to 2 cards.
			var oc_plays_left := game.overcharge_plays_remaining
			while oc_plays_left > 0 and game.overcharge_active:
				var oc_valid := game.get_valid_plays(idx)
				if oc_valid.is_empty():
					break
				var oc_idx: int = oc_valid[0]
				var oc_card: Card = p.hand[oc_idx]
				var oc_opts := _make_ai_options(oc_card, idx)
				game.play_card(idx, oc_idx, oc_opts)
				_play_action_sound(oc_card.action_id)
				_refresh_all()
				if game.game_over:
					_check_turn()
					return
				oc_plays_left -= 1
				if game.jump_in_open:
					return
			_check_turn()
			return

		# AI Overcharge gamble: with 2+ cards, optionally draw to get 2 plays.
		# Draw if no valid plays or if hand is large (≥4) and bomb risk is acceptable.
		var valid := game.get_valid_plays(idx)
		if valid.size() > 0:
			var hand_idx: int = valid[0]
			var card: Card = p.hand[hand_idx]
			var options := _make_ai_options(card, idx)
			# Capture the draw-card target size so the forced draw can be animated.
			var draw_target := -1
			var draw_pile := "A"
			var draw_before := 0
			if card.action_id in ["draw_two", "draw_four", "draw_ten"]:
				draw_target = game._next_alive_index(idx, game.direction)
				draw_pile = "A" if randi() % 2 == 0 else "B"
				draw_before = game.players[draw_target].hand.size()
			game.play_card(idx, hand_idx, options)
			_play_action_sound(card.action_id)
			_refresh_all()
			if game.jump_in_open:
				return  # jump-in window pauses the AI mid-turn
			if draw_target >= 0:
				var added := game.players[draw_target].hand.size() - draw_before
				if added > 0:
					_animate_forced_draw(draw_pile, draw_target, added)
					if draw_target == own_index:
						_reveal_hand_tail(added, 0.43, 0.32)
		else:
			# AI draws, then checks if the drawn card is playable.
			# Overcharge gamble: draw even with valid plays if hand is large (≥4 cards)
			# and the risk is acceptable (chamber < 30%).
			var pile := "A" if game.deck.pile_a.size() >= game.deck.pile_b.size() else "B"
			var gamble := false
			if game.mode == GameState.Mode.SHEDDING_RACE and p.hand_size() >= 4 and valid.size() > 0:
				var bomb_total: int = int(game.deck.bomb_count_a) + int(game.deck.bomb_count_b)
				var pile_size: int = game.deck.pile_a.size() + game.deck.pile_b.size()
				var odds: float = 0.0 if pile_size == 0 else float(bomb_total) / float(pile_size)
				if odds < 0.30:
					gamble = true
			if gamble:
				game.draw_card(idx, pile, false, false)  # end_turn=false: overcharge activates
				_refresh_all()
				# Overcharge is now active. Play up to 2 cards.
				var oc_plays_left := game.overcharge_plays_remaining
				while oc_plays_left > 0 and game.overcharge_active:
					var oc_valid := game.get_valid_plays(idx)
					if oc_valid.is_empty():
						break
					var oc_idx: int = oc_valid[0]
					var oc_card: Card = p.hand[oc_idx]
					var oc_opts := _make_ai_options(oc_card, idx)
					game.play_card(idx, oc_idx, oc_opts)
					_play_action_sound(oc_card.action_id)
					_refresh_all()
					if game.game_over:
						_check_turn()
						return
					oc_plays_left -= 1
					if game.jump_in_open:
						return
				if not game.game_over:
					_check_turn()
				return
			else:
				game.draw_card(idx, pile, false, false)  # end_turn=false: check drawn card
				_refresh_all()
# After drawing, check if the AI can now play.
			var new_valid := game.get_valid_plays(idx)
			if new_valid.size() > 0:
				# Play the first valid card (including the just-drawn one if playable).
				var draw_idx: int = new_valid[0]
				var draw_card: Card = p.hand[draw_idx]
				var draw_opts := _make_ai_options(draw_card, idx)
				game.play_card(idx, draw_idx, draw_opts)
				_play_action_sound(draw_card.action_id)
				_refresh_all()
			else:
				# No playable cards even after drawing — end turn.
				game.advance_turn()
				_refresh_all()

	if not game.game_over:
		state = State.AI_THINKING
		_ai_timer = randf_range(0.9, 1.5)
	else:
		_check_turn()

# ── Diffuse Decision (when bomb is drawn by human) ────────────────────

func _show_diffuse_decision() -> void:
	_play_sfx(_sfx_switch_b)
	_dismiss_all_overlays()
	if overlay_vbox and overlay_vbox.get_parent():
		overlay_vbox.get_parent().remove_child(overlay_vbox)
		overlay_vbox.queue_free()
	overlay_vbox = VBoxContainer.new()
	overlay.visible = true
	overlay_vbox.set_anchors_preset(Control.PRESET_CENTER)
	overlay_vbox.offset_left = -200
	overlay_vbox.offset_right = 200
	overlay_vbox.offset_top = -120
	overlay_vbox.offset_bottom = 120
	overlay_vbox.add_theme_constant_override("separation", 15)
	overlay.add_child(overlay_vbox)

	var warning := Label.new()
	warning.text = "YOU DREW THE BOMB!"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_font_size_override("font_size", 28)
	warning.add_theme_color_override("font_color", Color(0.95, 0.2, 0.1))
	overlay_vbox.add_child(warning)

	var sub := Label.new()
	sub.text = "You have a Diffuse card. Use it?"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	overlay_vbox.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	overlay_vbox.add_child(row)

	var use_btn := _make_kenney_button("Use Diffuse", Vector2(170, 52), 18, Color(0.2, 0.65, 0.35))
	use_btn.pressed.connect(_on_diffuse_use)
	row.add_child(use_btn)

	var risk_btn := _make_kenney_button("Take the risk!", Vector2(170, 52), 18, Color(0.75, 0.2, 0.12))
	risk_btn.pressed.connect(_on_diffuse_risk)
	row.add_child(risk_btn)

func _on_diffuse_use() -> void:
	overlay.visible = false
	_clear_overlay()
	_play_sfx(_sfx_button)

	# Remote client: send intent, wait for snapshot.
	if is_online and not is_host_here():
		send_intent({"kind": "diffuse", "use": true})
		state = State.WAITING
		_refresh_all()
		return

	game.resolve_bomb(true)
	_play_sfx(_sfx_click_b)

	if is_online and is_host_here():
		_broadcast_snapshot()

	state = State.WAITING
	_refresh_all()
	_check_turn()
	if is_tutorial:
		tutorial_action_done.emit("diffuse_use", {"pile": "", "count": 0})

func _on_diffuse_risk() -> void:
	overlay.visible = false
	_clear_overlay()
	_play_sfx(_sfx_button)

	# Remote client: send intent, wait for snapshot.
	if is_online and not is_host_here():
		send_intent({"kind": "diffuse", "use": false})
		state = State.WAITING
		_refresh_all()
		return

	_start_chamber_draw()

# ── Chamber Draw Sequence ─────────────────────────────────────────────

func _start_chamber_draw() -> void:
	if get_node_or_null("ChamberBG"):
		return
	state = State.CHAMBER_REVEAL
	_hide_timer_ui()

	# Dramatic background with vignette effect
	var chamber_bg := ColorRect.new()
	chamber_bg.name = "ChamberBG"
	chamber_bg.color = Color(0, 0, 0, 0.92)
	chamber_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	chamber_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(chamber_bg)

	var chamber_center := CenterContainer.new()
	chamber_center.name = "ChamberCenter"
	chamber_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(chamber_center)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 30)
	chamber_center.add_child(vbox)

	# Title with dramatic glow
	var title := Label.new()
	title.name = "ChamberTitle"
	title.text = "💀 THE CHAMBER 💀"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.95, 0.15, 0.1))
	vbox.add_child(title)

	# Rotating cylinder display with 6 chambers
	var cylinder := Label.new()
	cylinder.name = "ChamberCylinder"
	cylinder.text = "● ● ● ● ● ●"
	cylinder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cylinder.add_theme_font_size_override("font_size", 64)
	cylinder.add_theme_color_override("font_color", Color(0.8, 0.2, 0.15))
	vbox.add_child(cylinder)

	# Tension text
	var tension := Label.new()
	tension.name = "ChamberTension"
	tension.text = "Pulling the trigger..."
	tension.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tension.add_theme_font_size_override("font_size", 24)
	tension.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	vbox.add_child(tension)

	# Sound: dramatic bass rumble
	_play_sfx(_sfx_switch_a)

	await get_tree().create_timer(0.8).timeout

	# Dramatic spin: highlight chambers one by one with screen pulse
	var cylinder_node := get_node_or_null("ChamberCenter/VBoxContainer/ChamberCylinder")
	var tension_node := get_node_or_null("ChamberCenter/VBoxContainer/ChamberTension")
	if cylinder_node:
		# First pass: slow spin
		for i in range(6):
			var slots := ["●", "●", "●", "●", "●", "●"]
			slots[i] = "◉"
			cylinder_node.text = " ".join(slots)
			cylinder_node.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
			_play_sfx(_sfx_tap_b)
			await get_tree().create_timer(0.2).timeout
			cylinder_node.add_theme_color_override("font_color", Color(0.8, 0.2, 0.15))

		# Second pass: faster spin
		if tension_node:
			tension_node.text = "Spinning faster..."
		await get_tree().create_timer(0.3).timeout
		for i in range(12):
			var slots := ["●", "●", "●", "●", "●", "●"]
			slots[i % 6] = "◉"
			cylinder_node.text = " ".join(slots)
			cylinder_node.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
			_play_sfx(_sfx_tap_b)
			await get_tree().create_timer(0.08).timeout
			cylinder_node.add_theme_color_override("font_color", Color(0.8, 0.2, 0.15))

	# Final suspense pause
	if tension_node:
		tension_node.text = "..and.."
	if cylinder_node:
		cylinder_node.text = "? ? ? ? ? ?"
		cylinder_node.add_theme_color_override("font_color", Color(0.5, 0.1, 0.1))
	await get_tree().create_timer(0.8).timeout

	# Resolve the draw. Offline and online-host run the authority; online
	# clients never reach here (they get chamber_reveal packed in snapshots).
	var result: int
	if is_host_here():
		result = game.chamber.draw()
		_pending_chamber_reveal = {"seat": game.pending_diffuse_player_index, "result": int(result)}
		game.resolve_bomb_with_result(result)
		game.sync_respawn_cards()
		if is_online:
			_broadcast_snapshot()
	else:
		# Offline solo acting locally.
		result = game.chamber.draw()

	_play_chamber_reveal(result)

func _play_chamber_reveal(result: int) -> void:
	# Dramatic reveal with big text and effects
	var result_label := Label.new()
	result_label.name = "ChamberResult"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 84)

	# Result-specific styling with icons
	match result:
		ChamberDeck.Result.LIVE:
			result_label.text = "💥 LIVE!"
			result_label.add_theme_color_override("font_color", Color(1.0, 0.05, 0.02))
			_play_sfx(_sfx_switch_b)
		ChamberDeck.Result.BLANK:
			result_label.text = "💨 BLANK"
			result_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			_play_sfx(_sfx_tap_b)
		ChamberDeck.Result.BACKFIRE:
			result_label.text = "🔥 BACKFIRE!"
			result_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
			_play_sfx(_sfx_switch_b)
		ChamberDeck.Result.LUCKY_DRAW:
			result_label.text = "🌟 LUCKY DRAW!"
			result_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
			_play_sfx(_sfx_click_b)

	var chamber_center := get_node_or_null("ChamberCenter")
	if chamber_center:
		var vbox := chamber_center.get_child(0) if chamber_center.get_child_count() > 0 else null
		if vbox:
			vbox.add_child(result_label)

	# Screen effects based on result
	match result:
		ChamberDeck.Result.LIVE:
			_do_screen_shake(0.6, 12.0)
			# Flash red background
			var bg := get_node_or_null("ChamberBG")
			if bg:
				bg.color = Color(0.4, 0, 0, 0.95)
			await get_tree().create_timer(0.1).timeout
			if bg:
				bg.color = Color(0, 0, 0, 0.92)
		ChamberDeck.Result.BACKFIRE:
			_do_screen_shake(0.4, 8.0)
		ChamberDeck.Result.LUCKY_DRAW:
			# Flash green background
			var bg := get_node_or_null("ChamberBG")
			if bg:
				bg.color = Color(0, 0.3, 0, 0.95)
			await get_tree().create_timer(0.1).timeout
			if bg:
				bg.color = Color(0, 0, 0, 0.92)

	if is_online and not is_host_here():
		pass  # client: host already broadcast this log line via _rpc_log
	else:
		game.log_event.emit("Chamber Draw result: %s" % ChamberDeck.result_name(result))

	await get_tree().create_timer(2.5).timeout

	var chamber_bg_node := get_node_or_null("ChamberBG")
	if chamber_bg_node:
		chamber_bg_node.queue_free()
	var chamber_center_node := get_node_or_null("ChamberCenter")
	if chamber_center_node:
		chamber_center_node.queue_free()

	_resolve_chamber_result(result)

func _resolve_chamber_result(result: int) -> void:
	if is_online:
		# Host has already resolved. Client just updates its local state from snapshot.
		state = State.WAITING
		_refresh_all()
		_check_turn()
		return

	game.resolve_bomb_with_result(result)
	# The death sequence has played; now align respawn cards to any eliminated
	# players (there are none in the deck while nobody is dead).
	game.sync_respawn_cards()
	state = State.WAITING
	_refresh_all()
	_check_turn()
	if is_tutorial:
		tutorial_action_done.emit("chamber_done", {"result": result})

# ── Screen Shake ──────────────────────────────────────────────────────

func _do_screen_shake(duration: float, _intensity: float) -> void:
	var flash := ColorRect.new()
	flash.color = Color(0.9, 0.1, 0.05, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	var tw := create_tween()
	tw.tween_property(flash, "color", Color(1.0, 0.8, 0.2, 0.25), 0.08)
	tw.tween_property(flash, "color", Color(0.9, 0.1, 0.05, 0.0), duration)

	await get_tree().create_timer(duration).timeout
	flash.queue_free()

# ── Game Over ─────────────────────────────────────────────────────────

func _show_game_over() -> void:
	_clear_overlay()
	if overlay_vbox and overlay_vbox.get_parent():
		overlay_vbox.get_parent().remove_child(overlay_vbox)
		overlay_vbox.queue_free()
	overlay_vbox = VBoxContainer.new()
	overlay.visible = true
	overlay_vbox.set_anchors_preset(Control.PRESET_CENTER)
	overlay_vbox.offset_left = -250
	overlay_vbox.offset_right = 250
	overlay_vbox.offset_top = -120
	overlay_vbox.offset_bottom = 120
	overlay_vbox.add_theme_constant_override("separation", 15)
	overlay.add_child(overlay_vbox)

	_play_sfx(_sfx_switch_b)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	overlay_vbox.add_child(title)

	var winner := Label.new()
	winner.text = "%s wins!" % game.winner_name
	winner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner.add_theme_font_size_override("font_size", 24)
	winner.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(winner)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	overlay_vbox.add_child(row)

	var replay_btn := _make_kenney_button("Play Again", Vector2(160, 52), 18, Color(0.2, 0.6, 0.3))
	replay_btn.pressed.connect(_on_play_again)
	row.add_child(replay_btn)

	var menu_btn := _make_kenney_button("Main Menu", Vector2(160, 52), 18, Color(0.4, 0.35, 0.45))
	menu_btn.pressed.connect(_on_play_again)
	row.add_child(menu_btn)

func _on_play_again() -> void:
	if is_online:
		if _eos:
			_eos.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

# ── Helpers ───────────────────────────────────────────────────────────

## Plays a sound if the player node is currently set (safe no-op otherwise).
func _play_sfx(audio: AudioStreamPlayer) -> void:
	if audio:
		audio.play()

func _clear_overlay() -> void:
	for c in overlay_vbox.get_children():
		overlay_vbox.remove_child(c)
		c.queue_free()

## Closes every transient overlay system so they can never stack:
## the color/target/deck-choice popup, the jump-in prompt, and the bomb
## vote panel. Called before any new popup is shown.
func _dismiss_all_overlays() -> void:
	_clear_overlay()
	overlay.visible = false
	_hide_jump_prompt()
	var bvp := get_node_or_null("BombVotePanel")
	if bvp:
		bvp.queue_free()

# ──────────────────────────────────────────────────────────────────────
# ── ONLINE NETWORK LAYER ─────────────────────────────────────────────
# ──────────────────────────────────────────────────────────────────────

## Send an intent to the host. Host self-actions execute in place (local).
func send_intent(intent: Dictionary) -> void:
	if not is_online:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_intent_time < INTENT_COOLDOWN:
		return  # throttled
	_last_intent_time = now
	if is_host_here():
		_rpc_intent(intent)
		return
	rpc_id(1, "_rpc_intent", intent)

# ── RPC: Client → Host (intent) ──────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(intent: Dictionary) -> void:
	if not is_online:
		return
	if not _eos or not _eos.is_host:
		return
	if game == null:
		return  # Host still initializing; client will retry hello.

	var sender_peer_id := multiplayer.get_remote_sender_id()
	var seat: int = _eos.get_seat_for_peer(sender_peer_id)
	if seat == -1:
		return

	if intent.kind == "hello":
		# Client wants a fresh board; push current state once we have it.
		if game.players.size() > 0:
			_broadcast_snapshot()
		return

	if game.players.is_empty() or seat >= game.players.size():
		return

	# Turn/order guard: play/draw only on the acting player's turn; diffuse only
	# while that seat is mid-bomb; last_shot only on the acting player's turn.
	var is_acting: bool = seat == game.current_index
	if not is_acting and not ((intent.kind == "diffuse" and game.pending_bomb != null and game.pending_diffuse_player_index == seat) or (intent.kind == "jump_in" and game.jump_in_open) or (intent.kind == "last_shot" and game.pending_last_shot)):
		return

	var p: PlayerData = game.players[seat]

	match intent.kind:
		"play":
			var hand_idx: int = int(intent.hand_index)
			var options: Dictionary = intent.options if intent.has("options") else {}

			# Capture peek cards privately before play executes (if peek card).
			var peek_cards: Array[Card] = []
			if hand_idx >= 0 and hand_idx < p.hand.size():
				var card: Card = p.hand[hand_idx]
				if card.action_id == "peek":
					var peek_pile: String = options.get("chosen_pile", "A")
					peek_cards = game.deck.peek(peek_pile, 3)

			# Execute on host authoritative GameState.
			game.play_card(seat, hand_idx, options)

			# If peek was played, send peek data privately to acting player.
			if peek_cards.size() > 0:
				var peek_data: Array[Dictionary] = []
				for c in peek_cards:
					peek_data.append(c.to_dict())
				if sender_peer_id == EOSManager.HOST_PEER_ID:
					_show_peek_result_ui(peek_data)
				else:
					rpc_id(sender_peer_id, "_rpc_private", "peek_result", peek_data)

			_broadcast_snapshot()

		"draw":
			var pile_id: String = intent.pile if intent.has("pile") else "A"
			game.draw_card(seat, pile_id, true)

			if game.pending_bomb != null:
				# Bomb drawn; check if player has a diffuse in hand.
				var has_diffuse := false
				for c in p.hand:
					if c.type == Card.CardType.DIFFUSE:
						has_diffuse = true
						break
				_broadcast_snapshot()
				if has_diffuse:
					# Client will show diffuse UI and reply with diffuse intent.
					pass
				else:
					# No diffuse; resolve immediately on host.
					_host_resolve_chamber_draw()
			else:
				_broadcast_snapshot()

		"diffuse":
			var use_diffuse: bool = intent.use if intent.has("use") else false
			if use_diffuse:
				game.resolve_bomb(true)
				_broadcast_snapshot()
			else:
				# Declining: run chamber resolution (draw + resolve + reveal).
				_host_resolve_chamber_draw()

		"forced_draw":
			# Client chose a deck for the forced draw (Draw Two/Four/Ten).
			var pile_id: String = intent.pile if intent.has("pile") else "A"
			if game.pending_forced_draw_count > 0 and game.pending_forced_draw_player_index == seat:
				game.resolve_forced_draw(pile_id)
				_broadcast_snapshot()

		"last_shot":
			# Client chose a deck for the last shot (1 card remaining).
			var ls_pile: String = intent.pile if intent.has("pile") else "A"
			if game.pending_last_shot and game.current_index == seat:
				game.trigger_last_shot(seat, ls_pile)
				if game.pending_bomb != null:
					var ls_has_diffuse := false
					for c in p.hand:
						if c.type == Card.CardType.DIFFUSE:
							ls_has_diffuse = true
							break
					_broadcast_snapshot()
					if not ls_has_diffuse:
						_host_resolve_chamber_draw()
				else:
					_broadcast_snapshot()

		"bomb_vote":
			# Client voted on bomb continue/end.
			var continue_vote: bool = intent.continue_game if intent.has("continue_game") else true
			game.cast_vote(seat, continue_vote)
			_broadcast_snapshot()

		"jump_in":
			if game.jump_in(seat):
				_broadcast_snapshot()

		_:
			pass

# ── Host: resolve chamber draw immediately ────────────────────────────

## Host: resolve the chamber draw immediately (no diffuse available).
func _host_resolve_chamber_draw() -> void:
	if game.pending_bomb == null:
		return

	var result := game.chamber.draw()
	_pending_chamber_reveal = {"seat": game.pending_diffuse_player_index, "result": int(result)}
	game.resolve_bomb_with_result(result)
	game.sync_respawn_cards()
	_broadcast_snapshot()

# ── Snapshot: host → clients (per-seat, hand data private) ────────────

## Builds a snapshot dict. seat>=0 gives that seat's real hand and hides every
## other seat's cards behind same-sized placeholders. seat=-1 exposes every
## hand (host-internal only - never broadcast).
func _make_snapshot(seat: int = -1) -> Dictionary:
	var players_data: Array = []
	for i in range(game.players.size()):
		var p: PlayerData = game.players[i]
		var hand_data: Array[Dictionary] = []
		if seat == -1 or i == seat:
			for c in p.hand:
				hand_data.append(c.to_dict())
		else:
			for _h in range(p.hand.size()):
				hand_data.append({
					"type": Card.CardType.NUMBER,
					"color": Card.CardColor.NONE,
					"number": -1,
					"action_id": "",
					"display_name": "",
				})
		players_data.append({
			"id": p.id,
			"display_name": p.display_name,
			"color_idx": p.color_idx,
			"hand": hand_data,
			"banked_lives": p.banked_lives,
			"eliminated": p.eliminated,
			"skip_next_turn": p.skip_next_turn,
		})

	var discard_data: Array = []
	for c in game.deck.discard:
		discard_data.append(c.to_dict())

	# Send only pile sizes (not the card order) - deck contents are secret until
	# drawn host-side. Clients render placeholder backs sized by these counts.
	var deck_a_count: int = game.deck.pile_a.size()
	var deck_b_count: int = game.deck.pile_b.size()

	var bomb_snap = null
	if game.pending_bomb != null:
		bomb_snap = game.pending_bomb.to_dict()

	return {
		"mode": int(game.mode),
		"current_index": game.current_index,
		"direction": game.direction,
		"active_color": game.active_color,
		"active_number": game.active_number,
		"active_action_id": game.active_action_id,
		"players": players_data,
		"deck_a_count": deck_a_count,
		"deck_b_count": deck_b_count,
		"deck_a_bombs": _count_bombs(game.deck.pile_a),
		"deck_b_bombs": _count_bombs(game.deck.pile_b),
		"jump_in_open": game.jump_in_open,
		"last_played_card": game.last_played_card.to_dict() if game.last_played_card != null else null,
		"jump_in_candidates": game.jump_in_candidate_list.duplicate(),
		"discard": discard_data,
		"pending_bomb": bomb_snap,
		"pending_diffuse_player_index": game.pending_diffuse_player_index,
		"pending_forced_draw_count": game.pending_forced_draw_count,
		"pending_forced_draw_player_index": game.pending_forced_draw_player_index,
		"pending_forced_draw_amount": game.pending_forced_draw_amount,
		"winner_name": game.winner_name,
		"game_over": game.game_over,
		"forced_pile_for_player": game.forced_pile_for_player.duplicate(),
		"override_next_player_index": game.override_next_player_index,
		"overcharge_active": game.overcharge_active,
		"overcharge_plays_remaining": game.overcharge_plays_remaining,
		"pending_last_shot": game.pending_last_shot,
		"last_shot_passed": game.last_shot_passed,
	}

## Host sends each client a private snapshot (its own hand visible, others hidden).
func _broadcast_snapshot() -> void:
	if not _eos:
		return
	for entry in _eos.roster:
		if entry.peer_id == EOSManager.HOST_PEER_ID:
			continue
		var snap := _make_snapshot(entry.seat)
		if not _pending_chamber_reveal.is_empty():
			snap["chamber_reveal"] = _pending_chamber_reveal
		rpc_id(entry.peer_id, "_rpc_snapshot", snap)
	_pending_chamber_reveal = {}

func _is_peek_log(line: String) -> bool:
	var lower_line: String = line.to_lower()
	return "peeks at" in lower_line or "peek at" in lower_line

# ── RPC: Host → Client (snapshot) ────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snapshot: Dictionary) -> void:
	if not is_online:
		return
	_apply_snapshot(snapshot)

func _apply_snapshot(snapshot: Dictionary) -> void:
	_got_first_snapshot = true

	if not _eos:
		return

	var local_seat: int = _eos.get_own_seat()

	# Rebuild game.players from snapshot data.
	game.players.clear()
	var idx := 0
	for pdata in snapshot.players:
		var p := PlayerData.new(pdata.id, pdata.display_name)
		p.banked_lives = pdata.banked_lives
		p.eliminated = pdata.eliminated
		p.skip_next_turn = pdata.skip_next_turn
		p.color_idx = int(pdata.get("color_idx", 0)) % GameGlobals.PALETTE.size()
		p.color = GameGlobals.PALETTE[p.color_idx]

		if idx == local_seat:
			# This is our own seat: rebuild hand from snapshot cards.
			p.hand.clear()
			for card_dict in pdata.hand:
				p.hand.append(Card.from_dict(card_dict))
		else:
			# Other seat: placeholder cards sized to their real hand length.
			p.hand.clear()
			for _i in range(pdata.hand.size()):
				p.hand.append(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""))

		game.players.append(p)
		idx += 1

	own_index = local_seat

	# Switch to this player's camera if available.
	_switch_camera_to_seat(own_index)

	# Rebuild deck state from snapshot (counts only - contents are secret).
	game.deck.pile_a.clear()
	for _i in range(snapshot.deck_a_count):
		game.deck.pile_a.append(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""))

	game.deck.pile_b.clear()
	for _i in range(snapshot.deck_b_count):
		game.deck.pile_b.append(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""))

	# Per-deck bomb counts ride along in the snapshot (deck contents stay secret).
	_snapshot_bombs_a = snapshot.get("deck_a_bombs", -1)
	_snapshot_bombs_b = snapshot.get("deck_b_bombs", -1)

	game.deck.discard.clear()
	for c in snapshot.discard:
		game.deck.discard.append(Card.from_dict(c))

	# Core state.
	game.mode = snapshot.mode
	game.current_index = snapshot.current_index
	game.direction = snapshot.direction
	game.active_color = snapshot.active_color
	game.active_number = snapshot.active_number
	game.active_action_id = snapshot.get("active_action_id", "")
	game.game_over = snapshot.game_over
	game.winner_name = snapshot.get("winner_name", "")
	game.override_next_player_index = snapshot.get("override_next_player_index", null)

	# Pending bomb.
	if snapshot.pending_bomb != null:
		game.pending_bomb = Card.from_dict(snapshot.pending_bomb)
	else:
		game.pending_bomb = null
	game.pending_diffuse_player_index = snapshot.get("pending_diffuse_player_index", -1)

	# Forced piles.
	game.forced_pile_for_player = snapshot.get("forced_pile_for_player", {})

	# Pending forced draw (Draw Two/Four/Ten target chooses deck).
	game.pending_forced_draw_count = snapshot.get("pending_forced_draw_count", 0)
	game.pending_forced_draw_player_index = snapshot.get("pending_forced_draw_player_index", -1)
	game.pending_forced_draw_amount = snapshot.get("pending_forced_draw_amount", 0)

	# Overcharge and Last Shot state from host.
	game.overcharge_active = snapshot.get("overcharge_active", false)
	game.overcharge_plays_remaining = snapshot.get("overcharge_plays_remaining", 0)
	game.pending_last_shot = snapshot.get("pending_last_shot", false)
	game.last_shot_passed = snapshot.get("last_shot_passed", false)

	# Jump-in window state from the host.
	game.jump_in_open = snapshot.get("jump_in_open", false)
	var lpc = snapshot.get("last_played_card", null)
	if lpc != null:
		game.last_played_card = Card.from_dict(lpc)
	else:
		game.last_played_card = null
	game.jump_in_candidate_list = []
	for ci in snapshot.get("jump_in_candidates", []):
		game.jump_in_candidate_list.append(int(ci))

	# Chamber reveal: show the chamber draw animation with preset result.
	if snapshot.has("chamber_reveal"):
		var reveal: Dictionary = snapshot.chamber_reveal
		var reveal_seat: int = reveal.seat
		var reveal_result: int = reveal.result
		if reveal_seat == local_seat:
			_play_chamber_reveal(reveal_result)
		else:
			# Show brief notification for other players' chamber draws.
			var result_name: String = ChamberDeck.result_name(reveal_result)
			_show_notification("%s's chamber draw: %s" % [game.players[reveal_seat].display_name, result_name], 3.0)

	# Handle pending bomb diffuse UI for our own seat.
	if game.pending_bomb != null and game.pending_diffuse_player_index == local_seat:
		var has_diffuse := false
		for c in game.players[local_seat].hand:
			if c.type == Card.CardType.DIFFUSE:
				has_diffuse = true
				break
		if has_diffuse:
			state = State.DIFFUSE_DECISION
			_show_diffuse_decision()
		# If no diffuse, host will have already resolved and sent updated snapshot.
		return

	# If game is over, show game over screen.
	if game.game_over:
		state = State.GAME_OVER
		_refresh_all()
		_show_game_over()
		return

	# Jump-in window: mirror the host's window state.
	if game.jump_in_open:
		_jump_in_window = true
		_jump_in_timer = 0.0
		state = State.JUMP_IN
		_refresh_all()
		if own_index in game.jump_in_candidate_list:
			_show_jump_in_prompt()
		else:
			_hide_jump_prompt()
		return
	_jump_in_window = false
	_pending_ai_jump_index = -1
	_hide_jump_prompt()

	_refresh_all()
	_check_turn()

# ── RPC: Host → Client (log, filtered to hide peek info) ─────────────

@rpc("authority", "call_remote", "reliable")
func _rpc_log(line: String) -> void:
	if _is_peek_log(line):
		return
	_on_log(line)

# ── RPC: Host → Client (private data, e.g. peek result) ─────────────

@rpc("authority", "call_remote", "reliable")
func _rpc_private(kind: String, payload: Array) -> void:
	match kind:
		"peek_result":
			_show_peek_result_ui(payload)
		_:
			pass

func _show_peek_result_ui(card_dicts: Array) -> void:
	# Rebuild overlay with peek result.
	if overlay_vbox and overlay_vbox.get_parent():
		overlay_vbox.get_parent().remove_child(overlay_vbox)
		overlay_vbox.queue_free()

	overlay_vbox = VBoxContainer.new()
	overlay_vbox.set_anchors_preset(Control.PRESET_CENTER)
	overlay_vbox.offset_left = -250
	overlay_vbox.offset_right = 250
	overlay_vbox.offset_top = -130
	overlay_vbox.offset_bottom = 130
	overlay_vbox.add_theme_constant_override("separation", 12)
	overlay.add_child(overlay_vbox)

	var title := Label.new()
	title.text = "Peek result:"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(title)

	for cdict in card_dicts:
		var card_lbl := Label.new()
		var c: Card = Card.from_dict(cdict)
		card_lbl.text = c.display_name
		card_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_lbl.add_theme_font_size_override("font_size", 16)
		card_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		overlay_vbox.add_child(card_lbl)

	var close_btn := _make_kenney_button("Close", Vector2(130, 44), 16)
	close_btn.pressed.connect(_on_peek_close)
	overlay_vbox.add_child(close_btn)

	overlay.visible = true
