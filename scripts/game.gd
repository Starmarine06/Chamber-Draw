extends Control
const UIStyle := preload("res://scripts/ui_style.gd")
const Sound := preload("res://scripts/sound.gd")
const RoomBuilder := preload("res://scripts/fx/room_builder.gd")
const TableBuilder := preload("res://scripts/fx/table_builder.gd")
const RoomCrowd := preload("res://scripts/fx/room_crowd.gd")
const FirstPersonLine := preload("res://scripts/fx/first_person_line.gd")
const VicePicker := preload("res://scripts/ui/vice_picker.gd")
const ViceCatalog := preload("res://scripts/vice_catalog.gd")
const Ashtray := preload("res://scripts/fx/ashtray.gd")
const PropOverlay := preload("res://scripts/fx/prop_overlay.gd")
const BartenderPour := preload("res://scripts/fx/bartender_pour.gd")
const Keybinds := preload("res://scripts/keybinds.gd")

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

const Juice := preload("res://scripts/fx/juice.gd")
const CharacterActor := preload("res://scripts/character_actor.gd")
const ViceFirstPerson := preload("res://scripts/fx/vice_first_person.gd")
const FirstPersonSmoke := preload("res://scripts/fx/first_person_smoke.gd")
const FirstPersonDrink := preload("res://scripts/fx/first_person_drink.gd")
const EMOTE_COOLDOWN := 4.6

# ── UI director: fixed draw layers so overlays never fight ──
const LAYER_HUD := 0
const LAYER_TOAST := 30
const LAYER_MODAL := 50        # popups needing a decision
const LAYER_BANNER := 90       # cinematic announcements (non-interactive)
const LAYER_CHAMBER := 100
const LAYER_GAME_OVER := 120
const LAYER_PAUSE := 200
const BANNER_MAX_AGE_MS := 3000  # stale announcements are dropped, not replayed late
const EMOTE_KINDS: Array[StringName] = [&"smoke", &"drink"]
const GHOST_SCALE := 0.85

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
var _hello_count := 0
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
var _jump_stuck_t := 0.0
var _jump_in_timer := 0.0
var _pending_ai_jump_index := -1
var _ai_jump_delay := 0.0
var _jump_prompt: Control
const JUMP_WINDOW_TIME := 4.0

# ── Pause (offline only) ──
var _paused := false
var _room_floor_y := 0.0
# Secret [C] joke: the waiter's tray. Afterwards you are "wired" for a while.
const TABLE_GROW := 1.45
const SEAT_PUSH := 1.62
# ── Mouse look (cursor hidden; the camera is the player's head) ──
const LOOK_YAW_MAX := 70.0
const LOOK_PITCH_UP := 30.0
const LOOK_PITCH_DOWN := 22.0
const LOOK_SEND_INTERVAL := 0.1
const WIRED_PLAYS := 15          # the high lasts this many of YOUR card plays
const WIRED_COOLDOWN := 30.0
const DRUNK_PER_UNIT := 0.32     # a full glass of whiskey ~ +0.32
const DRUNK_DECAY := 0.0018      # per second: sobering up takes several minutes
const PASS_OUT_AT := 1.0         # fully drunk: you pass out
const WAKE_DRUNK := 0.3          # ...and wake up still a little drunk
const KILL_HIGH_FADE := 2.5      # seconds the comedown takes when you end the high yourself
const DRUNK_STEPS := [
	{"at": 0.2, "msg": "You're feeling warm."},
	{"at": 0.45, "msg": "The room sways a little."},
	{"at": 0.7, "msg": "Everything is a bit... double."},
	{"at": 0.92, "msg": "You should probably stop."},
]
var _line_scene: Node3D = null
var _look_yaw := 0.0
var _look_pitch := 0.0
var _look_base := Vector3.ZERO
var _look_base_cam: Camera3D = null
var _look_base_fov := 0.0
var _cursor_free := false           # TAB: give the cursor back for clicking UI
var _hand_sel := -1                 # scroll-wheel selected card (-1 = none)
var _look_sync_t := 0.0
var _look_sent := Vector2(9999.0, 9999.0)
var _crosshair: Panel = null
var _look_hint_shown := false
var _line_cooldown := 0.0
var _wired_active := false
var _wired_plays_left := 0
var _wired_ending := 0.0
var _wired_t := 0.0
var _state_t := 0.0
var _drunk := 0.0
var _ui_cover: TextureRect = null
var _cover_mat: ShaderMaterial = null
var _vice_picker: Control = null
var _vice_pick := {"smoke": {}, "drink": {}}
var _table_ashtray: Node3D = null
var _prop_overlay: Node = null
const SPOT_FWD := 0.36      # how far from the seat toward the table centre (fraction)
const SPOT_SIDE := 0.2      # sideways offset of glass / ashtray (fraction)
var _seat_glass: Dictionary = {}
var _seat_drink_prod: Dictionary = {}     # seat -> catalogue drink product (glass type / colour)
var _seat_smoke_prod: Dictionary = {}     # seat -> catalogue smoke product
var _table_radius := 1.0
var _tb_built := false         # the procedural table (with its coaster / ashtray shelves) exists
var _tb_centre := Vector3.ZERO
var _tb_radius := 1.0
var _tb_surface := 0.0
var _tb_off := 0.24            # radians each coaster / ashtray shelf sits from its seat
var _crowd: Node = null                   # RoomCrowd (the bartender lives here)
var _seat_ashtray: Dictionary = {}
var _smoke_btn: Button = null
var _drink_btn: Button = null
var _keys_version := -1
var _pending_vice: StringName = &""   # brand changed mid-vice: start this one next
var _wired_overlay: ColorRect = null
var _wired_mat: ShaderMaterial = null
var _wired_base_fov := 0.0
var _wired_shake_t := 0.0
var _leaving := false                 # this player is leaving on purpose (ignore disconnect popups)
var _session_ended := false           # opponent/host gone; only "leave" choices remain
var _pending_leavers: Array[Dictionary] = []   # host: players who dropped, awaiting a decision
var _leave_popup: ColorRect = null
var _log_history: Array[String] = []
var _log_panel: ColorRect = null
var _log_text: RichTextLabel = null
var _log_t0_ms := 0
const LOG_HISTORY_MAX := 600
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
var _tut_allow_vice := false  # tutorial: smoke / whiskey keys + buttons

# ── 3D table view (instanced game_3d.tscn inside a SubViewport) ──
var _viewport_container: TextureRect   # shows the 3D render, stretched to the screen
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
var _gauge_a: Control   # scripts/ui/deck_gauge.gd — chamber odds for Deck A
var _gauge_b: Control
var _opponent_nodes_3d: Array[Node3D] = []
var _char_node_by_index: Dictionary = {}  # seat -> Node3D (for respawn pop-in)
var _discard_sprite_base_scale: Vector3 = Vector3.ONE

# ── Juice / FX ──
var _shaker: Node = null                 # scripts/fx/screen_shake.gd
var _suppress_discard_fly := false       # local play already flew its own ghost
var _last_discard_top: Card = null
var _last_hand_sizes: Array[int] = []
var _last_timer_second := -1

# ── Vice emotes (smoke / whiskey) ──
var _emote_cooldown := 0.0
var _hands_busy := false                 # cards set down while you smoke / drink
var _smoke_session: Node3D = null        # interactive cigarette (scroll = drag)
var _drink_session: Node3D = null        # interactive whiskey (scroll = sip)
var _table_glass: Node3D = null          # your whiskey glass, left standing on the felt
var _pan_accum := 0.0                    # trackpad scroll → pulls
var _banner_queue: Array[Dictionary] = []
var _banner_active := false
var _card_w3d: float = 0.2               # world width of a card lying on the felt
var _set_down_pile: Node3D = null        # your face-down stack on the table
var _ai_emote_timers: Dictionary = {}    # seat -> seconds until that AI's next vice

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
var _drew_marker := -1   # host: seat that drew this turn and may still play / end its turn
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


func _ready() -> void:
	UIStyle.install()
	_eos = get_node_or_null("/root/EOSManager")
	_build_ui()
	_shaker = preload("res://scripts/fx/screen_shake.gd").new()
	_shaker.target_2d = self
	_shaker.camera = _camera_3d
	add_child(_shaker)
	Sound.play_music(&"table")
	_log_t0_ms = Time.get_ticks_msec()
	_start_game()
	_connect_session_signals()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	_sync_mouse_mode()
	if _keys_version != Keybinds.version:
		_keys_version = Keybinds.version
		if _smoke_btn:
			_smoke_btn.text = "SMOKE [%s]" % Keybinds.label(&"smoke")
		if _drink_btn:
			_drink_btn.text = "DRINK [%s]" % Keybinds.label(&"drink")
	if _paused:
		return  # all timers/animations frozen while paused
	_update_wired(delta)
	_update_pass_out(delta)
	_update_mouse_look(delta)

	if _turn_border and _turn_border.visible:
		_update_turn_border()

	if _emote_cooldown > 0.0:
		_emote_cooldown -= delta
	_pump_banners()
	_process_ai_vices(delta)

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
	# The forced-draw target is on the clock too: an idle target forfeits (the
	# pending draw resolves in _on_turn_timer_expired) instead of stalling the table.
	var timer_active := state == State.HUMAN_TURN or state == State.AI_THINKING 		or (state == State.FORCED_DRAW_DECK_CHOICE and game.pending_forced_draw_player_index == own_index)
	if is_tutorial:
		timer_active = false
	if timer_active and not game.game_over and not game.jump_in_open:
		_turn_timer -= delta * _wired_timer_mult()
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
			_hello_count += 1
			if _hello_count == 1 or _hello_count % 10 == 0:
				print("[Net] client: hello #%d sent, still waiting for first snapshot (peer status=%s)" % [_hello_count, str(_eos.peer.get_connection_status()) if _eos and _eos.peer else "no peer"])
			send_intent({"kind": "hello"})

	if _notification_timer > 0:
		_notification_timer -= delta
		if _notification_timer <= 0 and notification_label:
			notification_label.visible = false
			notification_label.add_theme_color_override("font_color", UIStyle.BRASS_LIGHT)  # Reset to brass

	# Failsafes so a jump-in window can never hang the table:
	#  - host/offline: if the game says the window is open but our timer isn't running
	#    (missed signal, re-entrancy), start it now so it still times out;
	#  - online client: stuck in JUMP_IN with no news from the host -> ask for a fresh snapshot.
	if game != null and not is_tutorial:
		if game.jump_in_open and not _jump_in_window and (not is_online or is_host_here()):
			_jump_in_window = true
			_jump_in_timer = 0.0
		if state == State.JUMP_IN and is_online and not is_host_here():
			_jump_stuck_t += delta
			if _jump_stuck_t > JUMP_WINDOW_TIME * 2.5:
				_jump_stuck_t = 0.0
				send_intent({"kind": "hello"})
		else:
			_jump_stuck_t = 0.0

	# Jump-in window: AI (offline) answers on a delay; the window times out.
	if _jump_in_window:
		_jump_in_timer += delta
		if _pending_ai_jump_index >= 0 and _jump_in_timer >= _ai_jump_delay:
			var ai_who := _pending_ai_jump_index
			_pending_ai_jump_index = -1
			_ai_jump_in(ai_who)
		elif (not is_online or is_host_here()) and not is_tutorial and _jump_in_timer >= JUMP_WINDOW_TIME:
			_close_jump_window()

	# Keep the 3D render target at the window's REAL pixel resolution (not the
	# 1152x648 UI design size) so the table is sharp on any monitor, and
	# re-project the deck click zones / gauges whenever it changes.
	if _viewport_3d and size.x > 0 and size.y > 0:
		var want := _render_size()
		if not _draw_zones_init or want != _viewport_3d.size or size != Vector2(_last_zone_size):
			_draw_zones_init = true
			_viewport_3d.size = want
			_last_zone_size = size
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
	top_bar.add_theme_stylebox_override("panel", _top_bar_style())
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

	# ── Voice chat strip (online only; hidden when there is no voice room) ──
	if GameGlobals.is_online:
		var voice_bar := preload("res://scripts/ui/voice_bar.gd").new()
		voice_bar.name = "VoiceBar"
		voice_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
		voice_bar.position = Vector2(12, 50)
		add_child(voice_bar)

	# ── Invisible deck click zones (projected onto the 3D piles) ──
	_draw_btn_a = _make_draw_button("A")
	_draw_btn_b = _make_draw_button("B")

	# ── Chamber-odds gauges pinned above each deck (always readable) ──
	# The badges live IN the 3D scene (billboards floating above each deck), so
	# they are perspective-scaled and tied to the piles instead of being screen UI.
	_gauge_a = _make_gauge_3d(_marker_deck_a)
	_gauge_b = _make_gauge_3d(_marker_deck_b)

	# ── End Turn button (shown after drawing; lets the player skip playing) ──
	_end_turn_btn = _make_kenney_button("End Turn", Vector2(120, 36), 16, Color(0.9, 0.35, 0.25))
	_end_turn_btn.visible = false
	_end_turn_btn.pressed.connect(_end_turn)
	add_child(_end_turn_btn)

	# ── Vice emotes: smoke a cigarette / sip whiskey (S / W) ──
	var vice_row := HBoxContainer.new()
	vice_row.name = "ViceRow"
	vice_row.add_theme_constant_override("separation", 8)
	vice_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vice_row.offset_left = -268
	vice_row.offset_top = -58
	vice_row.offset_right = -16
	vice_row.offset_bottom = -16
	vice_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vice_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vice_row.alignment = BoxContainer.ALIGNMENT_END
	add_child(vice_row)
	# Smoking / drinking are keyboard-driven now; the buttons only exist (hidden) so the
	# tutorial's spotlight has something to point at. They show during the tutorial.
	var gg := get_node_or_null("/root/GameGlobals")
	vice_row.visible = gg != null and bool(gg.get("is_tutorial"))
	var smoke_btn := UIStyle.make_button("SMOKE [%s]" % Keybinds.label(&"smoke"), &"secondary", Vector2(124, 40), 14)
	_smoke_btn = smoke_btn
	smoke_btn.tooltip_text = "Light a cigarette or cigar"
	smoke_btn.pressed.connect(_request_emote.bind(&"smoke"))
	vice_row.add_child(smoke_btn)
	var drink_btn := UIStyle.make_button("DRINK [%s]" % Keybinds.label(&"drink"), &"secondary", Vector2(124, 40), 14)
	_drink_btn = drink_btn
	drink_btn.tooltip_text = "Pour yourself a drink"
	drink_btn.pressed.connect(_request_emote.bind(&"drink"))
	vice_row.add_child(drink_btn)

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
	notification_label.z_index = LAYER_TOAST
	notification_label.visible = false
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.add_theme_font_size_override("font_size", 18)
	notification_label.add_theme_color_override("font_color", UIStyle.BRASS_LIGHT)
	var toast := UIStyle.panel_style(Color(UIStyle.INK, 0.86), Color(UIStyle.BRASS_DIM, 0.8), 18, 1)
	toast.content_margin_top = 8
	toast.content_margin_bottom = 8
	toast.shadow_size = 8
	notification_label.add_theme_stylebox_override("normal", toast)
	notification_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	notification_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notification_label.offset_left = -400
	notification_label.offset_right = 400
	notification_label.offset_top = 54
	notification_label.offset_bottom = 94
	add_child(notification_label)

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

## Distinct sound per card action (routed through AudioManager events).
func _play_action_sound(action_id: String) -> void:
	match action_id:
		"extra_life": _sfx(&"extra_life")
		"swap_hands": _sfx(&"swap")
		"rotate_decks": _sfx(&"rotate")
		"peek", "choose_deck": _sfx(&"peek")
		"draw_two", "draw_four", "draw_ten": _sfx(&"draw_attack")
		"skip": _sfx(&"skip")
		"reverse": _sfx(&"reverse")
		"wild_color", "wild_sabotage": _sfx(&"wild")

## Instances scenes/game_3d.tscn (the editor-built poker table + markers) into a
## full-screen SubViewport, then frames a camera and builds the 3D piles.
func _setup_3d_viewport() -> void:
	# The 3D world renders into a SubViewport at native window resolution with
	# MSAA; a full-rect TextureRect scales it onto the (smaller) UI canvas.
	_viewport_3d = SubViewport.new()
	_viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_3d.transparent_bg = false
	_viewport_3d.gui_disable_input = true
	_viewport_3d.msaa_3d = Viewport.MSAA_4X
	_viewport_3d.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_viewport_3d.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
	_viewport_3d.size = _render_size()
	add_child(_viewport_3d)

	_viewport_container = TextureRect.new()
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewport_container.stretch_mode = TextureRect.STRETCH_SCALE
	_viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.texture = _viewport_3d.get_texture()
	add_child(_viewport_container)

	# World environment: a dark, smoky back room — ink background, low warm
	# ambient, distance fog, bloom for brass/emissive highlights, AgX tonemap.
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.022, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.36, 0.4)
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.08, 0.06)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.92
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
		_ensure_corner_seats()
		for i in range(1, 9):
			var m := _world_root_3d.get_node_or_null("Player%d" % i) as Marker3D
			if m:
				_marker_players.append(m)

	# Use the camera placed in game_3d.tscn if there is one; otherwise frame one
	# from the marker bounds so any table scale works.
	var bounds := _compute_table_bounds()
	_table_center = bounds.get_center()
	var tsize := maxf(bounds.size.x, bounds.size.z)
	_char_scale = tsize * 0.2

	_grow_table()

	# Find all cameras in the scene (one per player seat).
	_player_cameras.clear()
	_find_all_cameras(_world_root_3d)

	# Use the camera for the local player's seat if available.
	_camera_3d = _get_camera_for_seat(own_index)
	if _camera_3d != null:
		_camera_3d.make_current()
	if _camera_3d == null:
		# Fallback: use the first camera found, or create an auto-framed one.
		_camera_3d = _get_camera_for_seat(0) if _player_cameras.size() > 0 else null
		if _camera_3d == null:
			_camera_3d = Camera3D.new()
			_camera_3d.fov = 55.0
			_camera_3d.position = _table_center + Vector3(0.0, tsize * 1.55, tsize * 0.58)
			_viewport_3d.add_child(_camera_3d)
			_camera_3d.look_at(_table_center + Vector3(0.0, 0.2, 0.0), Vector3.UP)

	_build_lighting(tsize)
	_dress_table()
	_build_room(tsize)
	_build_3d_piles(tsize)

## Noir lighting: one warm spotlight hanging over the felt (the only real
## key light), a faint cool moon-fill for silhouettes, and dust motes drifting
## through the cone.
func _build_lighting(tsize: float) -> void:
	var lamp := SpotLight3D.new()
	lamp.name = "TableLamp"
	lamp.light_color = Color(1.0, 0.82, 0.58)
	lamp.light_energy = 9.0
	lamp.spot_range = tsize * 4.0
	lamp.spot_angle = 42.0
	lamp.spot_angle_attenuation = 1.6
	lamp.spot_attenuation = 0.6
	lamp.shadow_enabled = true
	lamp.shadow_blur = 1.5
	_viewport_3d.add_child(lamp)
	lamp.position = _table_center + Vector3(0, tsize * 1.6, 0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)

	var fill := DirectionalLight3D.new()
	fill.name = "MoonFill"
	fill.light_color = Color(0.55, 0.62, 0.85)
	fill.rotation_degrees = Vector3(-35, -140, 0)
	fill.light_energy = 0.22
	_viewport_3d.add_child(fill)

	var motes := GPUParticles3D.new()
	motes.name = "DustMotes"
	motes.amount = 60
	motes.lifetime = 12.0
	motes.preprocess = 12.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(tsize * 0.55, tsize * 0.6, tsize * 0.55)
	pm.direction = Vector3(0.2, 1, 0.1)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.004
	pm.initial_velocity_max = 0.02
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.2
	pm.turbulence_noise_scale = 2.0
	motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(tsize * 0.006, tsize * 0.006)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(1.0, 0.9, 0.7, 0.35)
	mm.albedo_texture = Juice.soft_texture()
	quad.material = mm
	motes.draw_pass_1 = quad
	_viewport_3d.add_child(motes)
	motes.position = _table_center + Vector3(0, tsize * 0.7, 0)

## A bigger table: the model grows sideways around the table centre and the seats
## (with their cameras) slide out a little, so there is more felt and the giants
## no longer crowd the cards.
func _grow_table() -> void:
	if _world_root_3d == null:
		return
	var c := _table_center
	var mesh := _world_root_3d.find_child("PokerTable", true, false) as Node3D
	if mesh != null:
		var t := mesh.global_transform
		var rel := t.origin - c
		mesh.global_transform = Transform3D(Basis.from_scale(Vector3(TABLE_GROW, 1.0, TABLE_GROW)) * t.basis,
			Vector3(c.x + rel.x * TABLE_GROW, t.origin.y, c.z + rel.z * TABLE_GROW))
	if mesh != null:
		var bb: AABB = mesh.global_transform * mesh.get_aabb()
		_table_radius = maxf(bb.size.x, bb.size.z) * 0.5
	for m in _marker_players:
		var g := m.global_position
		m.global_position = Vector3(c.x + (g.x - c.x) * SEAT_PUSH, g.y, c.z + (g.z - c.z) * SEAT_PUSH)
	_space_piles()

## Keeps the discard pile and both draw piles clear of each other (their card-sized
## footprints must never touch, from any camera angle): markers that sit too close
## are slid apart along the line between them.
func _space_piles() -> void:
	var min_gap := _char_scale * 5.0 * 0.42   # tsize * 0.42 (a card diagonal is ~0.28 tsize)
	var markers: Array[Marker3D] = []
	for m in [_marker_discard, _marker_deck_a, _marker_deck_b]:
		if m != null:
			markers.append(m)
	for _pass in 4:
		for i in range(markers.size()):
			for j in range(i + 1, markers.size()):
				var a := markers[i].global_position
				var b := markers[j].global_position
				var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
				var d := flat.length()
				if d >= min_gap:
					continue
				var dir := flat / d if d > 0.001 else Vector3(1, 0, 0)
				var push := (min_gap - d) * 0.5
				# The discard stays put; draw piles move. Two draw piles share the push.
				if markers[i] == _marker_discard:
					markers[j].global_position = b + dir * (min_gap - d)
				elif markers[j] == _marker_discard:
					markers[i].global_position = a - dir * (min_gap - d)
				else:
					markers[i].global_position = a - dir * push
					markers[j].global_position = b + dir * push

## Wraps the table in a paneled back room (floor, walls, ceiling, sconces) so the
## background is a real place instead of black void.
func _build_room(tsize: float) -> void:
	var floor_y := _table_center.y - tsize * 0.55
	var table_mesh := _world_root_3d.find_child("PokerTable", true, false) as MeshInstance3D if _world_root_3d else null
	if table_mesh != null:
		floor_y = (table_mesh.global_transform * table_mesh.get_aabb()).position.y
	var cam_dist := 0.0
	var cam_top := _table_center.y
	for c in _viewport_3d.find_children("*", "Camera3D", true, false):
		var cp: Vector3 = (c as Camera3D).global_position
		cam_dist = maxf(cam_dist, Vector2(cp.x - _table_center.x, cp.z - _table_center.z).length())
		cam_top = maxf(cam_top, cp.y)
	_room_floor_y = floor_y
	var room := RoomBuilder.build(_viewport_3d, _table_center, tsize, floor_y, cam_dist, cam_top)
	_crowd = RoomCrowd.spawn(room, _table_center, floor_y, float(room.get_meta("radius")), _char_scale, float(room.get_meta("height")))

## Replaces the table model's flat white material with the felt/rail shader.
func _dress_table() -> void:
	if _world_root_3d == null:
		return
	var mesh := _world_root_3d.find_child("PokerTable", true, false) as MeshInstance3D
	if mesh == null:
		return
	# The imported model stays in the scene (hidden) so its bounds still size the room; what you
	# see is the procedural table, built on the same radius / felt height / floor.
	var world_bb: AABB = mesh.global_transform * mesh.get_aabb()
	var surface_y: float = _marker_discard.global_position.y if _marker_discard != null else world_bb.position.y + world_bb.size.y * 0.86
	mesh.visible = false
	_tb_centre = world_bb.get_center()
	_tb_radius = maxf(world_bb.size.x, world_bb.size.z) * 0.5
	_tb_surface = surface_y
	var seat_ps: Array = []
	for s in range(_seat_count()):          # shelves only for seats somebody actually sits in
		seat_ps.append(_seat_marker_pos(s))
	_tb_off = TableBuilder.tab_offset(_tb_centre, seat_ps)
	TableBuilder.build(_world_root_3d, _tb_centre, _tb_radius, surface_y, world_bb.position.y, seat_ps)
	_tb_built = true

## Native pixel size for the 3D render (the real window, not the UI design
## size). Falls back to the canvas size when there's no window (headless).
func _render_size() -> Vector2i:
	var win := get_window()
	var px := Vector2i(win.size) if win else Vector2i(size)
	if px.x <= 0 or px.y <= 0:
		px = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	return px

## UI-canvas units per 3D render pixel (render is at native res, UI is scaled).
func _view_scale() -> Vector2:
	if _viewport_3d == null or _viewport_3d.size.x <= 0 or size.x <= 0:
		return Vector2.ONE
	return size / Vector2(_viewport_3d.size)

## World point → UI canvas position (use instead of camera.unproject_position).
func _unproject(world: Vector3) -> Vector2:
	if _camera_3d == null:
		return size * 0.5
	return _camera_3d.unproject_position(world) * _view_scale()

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
	_card_w3d = card_w

	# Deck slabs: cream card-edge sides with a brass rim glow on your turn; the
	# top face is a Sprite3D showing the real card back (rendered once).
	var pile_mat_a := StandardMaterial3D.new()
	pile_mat_a.roughness = 0.7
	pile_mat_a.albedo_color = Color(0.86, 0.82, 0.72)
	_build_back_texture()

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
		_discard_vp.size = Vector2i(256, 384)
		_discard_vp.transparent_bg = true
		_discard_vp.gui_disable_input = true
		_discard_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport_3d.add_child(_discard_vp)

		_discard_card_node = CardNode.new()
		_discard_card_node.setup(CardDatabase._make(Card.CardType.NUMBER, Card.CardColor.RED, 0, "", ""), true, 256.0, 384.0)
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
		_discard_sprite.pixel_size = card_w / 256.0
		_discard_sprite.position = discard_pos + Vector3(0, 0.06, 0)
		_discard_sprite.rotation_degrees.x = -90.0
		_discard_sprite.visible = false
		_viewport_3d.add_child(_discard_sprite)

	# Deck names + chamber odds live in the 2D gauges (_gauge_a/_gauge_b),
	# pinned above each pile — a 3D label here got buried behind the slabs.

func _create_pile_mesh(pos: Vector3, mat: StandardMaterial3D, w: float, h: float) -> MeshInstance3D:
	var stack := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w * 0.98, 0.05, h * 0.98)
	stack.mesh = box
	stack.material_override = mat
	stack.position = pos + Vector3(0, 0.025, 0)
	stack.set_meta(&"base_pos", pos)
	_viewport_3d.add_child(stack)
	# Card-back face on top of the slab.
	if _back_vp:
		var top := Sprite3D.new()
		top.name = "BackFace"
		top.texture = _back_vp.get_texture()
		top.pixel_size = w / 256.0
		top.rotation_degrees = Vector3(-90, randf_range(-3.0, 3.0), 0)
		top.shaded = false
		top.modulate = Color(0.82, 0.8, 0.78)
		top.position = Vector3(0, 0.026, 0)
		stack.add_child(top)
	return stack

## Renders one card back into a SubViewport so 3D decks show the real design.
var _back_vp: SubViewport
func _build_back_texture() -> void:
	_back_vp = SubViewport.new()
	_back_vp.size = Vector2i(256, 384)
	_back_vp.transparent_bg = true
	_back_vp.gui_disable_input = true
	_back_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport_3d.add_child(_back_vp)
	var back := CardNode.new()
	back.setup(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""), false, 256.0, 384.0)
	_back_vp.add_child(back)

## Deck slab thickness tracks its card count (a thin sliver when nearly empty).
func _set_pile_thickness(mesh: MeshInstance3D, count: int) -> void:
	if mesh == null:
		return
	var box := mesh.mesh as BoxMesh
	var t := clampf(float(count) * 0.0009, 0.004, 0.07)
	box.size.y = t
	var base: Vector3 = mesh.get_meta(&"base_pos", mesh.position)
	mesh.position = base + Vector3(0, t * 0.5, 0)
	var top := mesh.get_node_or_null("BackFace") as Sprite3D
	if top:
		top.position = Vector3(0, t * 0.5 + 0.001, 0)
	mesh.visible = count > 0

## The authored table has six seats. Seats 7 and 8 (top-right, bottom-left) complete the
## octagon so up to eight players each get their own place and camera: built here from the
## existing ones (same radius as the other corner seats, same camera rig turned to face in).
func _ensure_corner_seats() -> void:
	if _world_root_3d == null or _world_root_3d.get_node_or_null("Player7") != null:
		return
	var seats: Array[Marker3D] = []
	for i in range(1, 7):
		var s := _world_root_3d.get_node_or_null("Player%d" % i) as Marker3D
		if s == null:
			return
		seats.append(s)
	var cx := 0.0
	var cz := 0.0
	for s in seats:
		cx += s.position.x / 6.0
		cz += s.position.z / 6.0
	# The two authored corner seats (Player5, Player6) set the corner radius.
	var r := (Vector2(seats[4].position.x - cx, seats[4].position.z - cz).length() + Vector2(seats[5].position.x - cx, seats[5].position.z - cz).length()) * 0.5
	var cam_src: Camera3D = null
	for c in seats[0].get_children():
		if c is Camera3D:
			cam_src = c as Camera3D
			break
	for spec in [[7, 135.0], [8, 315.0]]:   # degrees, same convention as the other seats (0 = Player1's side)
		var th := deg_to_rad(float(spec[1]))
		var m := Marker3D.new()
		m.name = "Player%d" % int(spec[0])
		_world_root_3d.add_child(m)
		m.position = Vector3(cx + sin(th) * r, seats[0].position.y, cz + cos(th) * r)
		if cam_src != null:
			var cam := cam_src.duplicate() as Camera3D
			m.add_child(cam)
			var yaw := Basis(Vector3.UP, th)
			cam.transform = Transform3D(yaw * cam_src.transform.basis, yaw * cam_src.transform.origin)

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
			if player_idx >= 0 and player_idx < 8:  # Support up to 8 players
				# Ensure array is large enough
				while _player_cameras.size() <= player_idx:
					_player_cameras.append(null)
				_player_cameras[player_idx] = child
			# Keep searching for more cameras in other branches
		_find_all_cameras(child)

## Get the camera for a specific player seat, or null if none exists.
func _get_camera_for_seat(seat_index: int) -> Camera3D:
	var mi := _seat_marker_idx(seat_index)
	if seat_index < 0 or mi < 0 or mi >= _player_cameras.size():
		return null
	return _player_cameras[mi]

## Which table marker a seat sits at (6 authored markers + 2 corner seats built at startup).
## With fewer than 6 players the seats are
## spread EVENLY around the table (2 = opposite, 3 = 120 degrees, ...), instead of
## bunching up on Player1..N. The walking order around the table is unchanged: seats
## follow GameState's ring (0,3,4,1,2,5), and that ring is laid onto evenly spaced slots.
const SEAT_RING: Array[int] = [0, 3, 4, 1, 2, 5]
const SEAT_SLOTS := {2: [0, 3], 3: [0, 2, 4], 4: [0, 2, 3, 5], 5: [0, 1, 3, 4, 5], 6: [0, 1, 2, 3, 4, 5]}
## 7 and 8 players use the full octagon: markers in walking order (seat 0, then round the
## table), and which of the eight positions each count occupies (7 skips the one opposite seat 0).
const SEAT_RING_8: Array[int] = [0, 7, 3, 4, 1, 6, 2, 5]
const SEAT_SLOTS_8 := {
	2: [0, 4], 3: [0, 3, 5], 4: [0, 2, 4, 6], 5: [0, 2, 3, 5, 6], 6: [0, 1, 3, 4, 5, 7],
	7: [0, 1, 2, 3, 5, 6, 7], 8: [0, 1, 2, 3, 4, 5, 6, 7],
}

func _seat_count() -> int:
	if game != null and game.players.size() > 0:
		return game.players.size()
	if is_tutorial:
		return 4
	var gg := get_node_or_null("/root/GameGlobals")
	return int(gg.num_players) if gg != null else 4

func _seat_marker_idx(seat: int) -> int:
	var n := _seat_count()
	if n >= 2 and n <= 8 and seat < n:
		var ring8: Array = []
		for r8 in SEAT_RING_8:
			if r8 < n:
				ring8.append(r8)
		var p8: int = ring8.find(seat)
		if p8 >= 0:
			return SEAT_RING_8[int(SEAT_SLOTS_8[n][p8])]
	if n >= 7 or n < 2 or not SEAT_SLOTS.has(n) or seat >= n:
		return seat % 6
	var ring: Array = []
	for r in SEAT_RING:
		if r < n:
			ring.append(r)
	var p: int = ring.find(seat)
	if p < 0:
		return seat % 6
	return SEAT_RING[int(SEAT_SLOTS[n][p])]

## Switch the active camera to the given player seat.
func _switch_camera_to_seat(seat_index: int) -> void:
	var cam := _get_camera_for_seat(seat_index)
	if cam == null or cam == _camera_3d:
		return
	_camera_3d = cam
	# THIS was the multiplayer bug: the variable changed but the viewport kept RENDERING
	# the first camera in the scene (seat 0 = the host's view), so the client sat in the
	# host's chair, mouse look turned an invisible camera and deck picking was misaligned.
	cam.make_current()
	if _prop_overlay != null:
		_prop_overlay.set("main_cam", cam)
		_prop_overlay.exclude_from([cam])
	if _shaker:
		_shaker.camera = cam
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
		mat.emission = UIStyle.BRASS if on else Color.BLACK
		mat.emission_energy_multiplier = 1.4 if on else 0.0

## Places a Kenney character at each opponent's marker. Only the local player's
## hand is ever rendered (their seat shows nothing in 3D — cards are 2D below).
func _place_opponents_3d() -> void:
	# Labels are cheap and change every refresh — rebuild them. Character
	# actors are CACHED per seat (character_actor.gd) so their animation state,
	# emotes and turn light survive refreshes.
	for child in _opponent_nodes_3d:
		if is_instance_valid(child):
			child.queue_free()
	_opponent_nodes_3d.clear()

	if game.players.is_empty() or _marker_players.is_empty():
		return

	var n := game.players.size()
	for i in range(n):
		if i == own_index:
			continue
		var p: PlayerData = game.players[i]
		var base_pos := _seat_base_pos(i)
		var actor: Node3D = _char_node_by_index.get(i, null)
		if actor != null and not is_instance_valid(actor):
			_char_node_by_index.erase(i)
			actor = null
		# Eliminated players: play the fall once, then the seat empties.
		if p.eliminated:
			if i == _duel_seat:
				# Mid-duel (online snapshots arrive first): the bullet hasn't landed yet.
				_update_seat_tag(i, p, base_pos, false)
				continue
			if actor != null and not actor.removing:
				actor.die_and_remove(func() -> void: _char_node_by_index.erase(i))
			_update_seat_tag(i, p, base_pos, false)
			continue
		if actor == null or actor.dead:
			if actor != null:
				actor.queue_free()
			actor = _spawn_actor(i, base_pos, p)
		actor.set_turn(i == game.current_index)
		actor.set_passed_out(p.passed_out)

		_update_seat_tag(i, p, base_pos, i == game.current_index)

## 2D name tag pinned to an opponent's chest (the seat cameras sit so close
## that a 3D label above the head is off-screen). Seat-colored name, cards,
## banked lives; brass border + ▶ on the active seat; "OUT" when eliminated.
var _seat_tags: Dictionary = {}   # seat -> Label

func _update_seat_tag(i: int, p: PlayerData, base_pos: Vector3, is_current: bool) -> void:
	var tag: Label = _seat_tags.get(i, null)
	if tag == null or not is_instance_valid(tag):
		tag = Label.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_override("font", UIStyle.body_font())
		tag.add_theme_font_size_override("font_size", 15)
		# The tag lives in the 3D scene: rendered in a SubViewport and shown on a
		# billboard Sprite3D floating above the character's head.
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.gui_disable_input = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.size_2d_override_stretch = true
		vp.add_child(tag)
		_viewport_3d.add_child(vp)
		var sp := Sprite3D.new()
		sp.name = "SeatTag%d" % i
		sp.texture = vp.get_texture()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false
		sp.transparent = true
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sp.fixed_size = true  # readable at any distance, but still anchored above the head
		_viewport_3d.add_child(sp)
		tag.set_meta(&"vp", vp)
		tag.set_meta(&"sprite", sp)
		_seat_tags[i] = tag
	var lives := ""
	if p.banked_lives > 0:
		lives = "  ♥%d" % p.banked_lives
	if p.eliminated:
		tag.text = "%s  ·  OUT" % p.display_name
	else:
		tag.text = "%s%s\n%d cards%s%s" % ["▶ " if is_current else "", p.display_name, p.hand_size(), lives, "  💤 ASLEEP" if p.passed_out else ""]
	var col: Color = UIStyle.BRASS_LIGHT if is_current else p.color.lightened(0.3)
	tag.add_theme_color_override("font_color", col if not p.eliminated else UIStyle.MUTED)
	var box := UIStyle.panel_style(Color(UIStyle.INK, 0.82), UIStyle.BRASS if is_current else Color(p.color, 0.55), 10, 2)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_size = 6
	if is_current:
		box.shadow_color = Color(UIStyle.BRASS, 0.45)
		box.shadow_size = 12
	tag.add_theme_stylebox_override("normal", box)
	tag.modulate.a = 0.6 if p.eliminated else 1.0
	tag.reset_size()
	# Head-top of the avatar (measured from its meshes), plus a small gap.
	var head_y := base_pos.y + _char_scale * 2.2
	var actor: Node3D = _char_node_by_index.get(i, null)
	if actor != null and is_instance_valid(actor) and actor.get("model") != null:
		var m: Dictionary = RoomCrowd.measure(actor)
		head_y = actor.global_position.y + float(m.hi) * actor.scale.y
	tag.set_meta(&"anchor", Vector3(base_pos.x, head_y + _char_scale * 0.35, base_pos.z))
	_layout_seat_tag(tag)

## Sizes the tag's render target and pins its billboard above the head.
func _layout_seat_tag(tag: Label) -> void:
	if not tag.has_meta(&"anchor") or not tag.has_meta(&"sprite"):
		return
	var vp: SubViewport = tag.get_meta(&"vp")
	var sp: Sprite3D = tag.get_meta(&"sprite")
	var sz := Vector2i(maxi(int(tag.size.x), 8), maxi(int(tag.size.y), 8))
	if vp.size_2d_override != sz:
		vp.size_2d_override = sz
		vp.size = sz * 2
	sp.pixel_size = 0.00115
	sp.global_position = tag.get_meta(&"anchor")
	sp.visible = tag.visible

## World position where seat `i`'s avatar stands.
func _seat_base_pos(i: int) -> Vector3:
	var marker: Marker3D = _marker_players[_seat_marker_idx(i) % _marker_players.size()]
	var base_pos: Vector3 = marker.global_position
	# The Kenney GLBs are authored with the origin above the feet — lower them
	# so they actually stand on the felt (tune CHAR_SEAT_OFFSET if needed).
	base_pos.y -= _char_scale * CHAR_SEAT_OFFSET
	if i >= _marker_players.size():
		# 7th player reuses the bottom marker — nudge aside so it clears the local hand.
		base_pos += Vector3(0.45 * _char_scale, 0, -0.2 * _char_scale)
	return base_pos

func _spawn_actor(i: int, base_pos: Vector3, p: PlayerData) -> Node3D:
	var actor: Node3D = CharacterActor.new()
	var char_path := "res://assets/imported_assets/kenney_blocky-characters_20/Models/GLB format/character-%s.glb" % char(97 + posmod(i - 1, 15))
	_viewport_3d.add_child(actor)
	actor.setup(char_path, _char_scale, p.color, i)
	actor.position = base_pos
	var to_center: Vector3 = _table_center - base_pos
	actor.rotation.y = atan2(to_center.x, to_center.z)
	_char_node_by_index[i] = actor
	actor.glance = not is_online   # offline AIs glance around; online heads follow the real player
	return actor

## Character reactions: routes to the seat's actor (real animation clips +
## emote bubbles). kind: &"play", &"hit", &"nervous", &"relief", &"win", &"die".
func _character_react(seat: int, kind: StringName) -> void:
	var actor: Node3D = _char_node_by_index.get(seat, null)
	if actor == null or not is_instance_valid(actor):
		return
	actor.react(kind)

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


## Screen-space center of the discard pile (falls back to mid-screen).
func _discard_screen_pos() -> Vector2:
	if _marker_discard and _camera_3d:
		return _unproject(_marker_discard.global_position)
	return size * 0.5

## Screen-space center of a draw pile.
func _deck_screen_pos(pile_id: String) -> Vector2:
	var marker: Marker3D = _marker_deck_a if pile_id == "A" else _marker_deck_b
	if marker and _camera_3d:
		return _unproject(marker.global_position)
	return size * 0.5

## Flies a ghost copy of the played card from its hand slot to the discard pile.
func _fly_card_to_discard(card: Card) -> void:
	if card == null or _hand_marker == null:
		return
	var from := _hand_marker.position + Vector2(0, -HANDCARD_H * 0.5)
	for cn in card_nodes:
		if cn.card_data == card:
			from = cn.global_position + cn.size * 0.5
			cn.modulate.a = 0.0  # the ghost takes over; the refresh re-lays the hand
			break
	_suppress_discard_fly = true
	_spawn_ghost(card, from, _discard_screen_pos(), true)

## Flies a drawn card from the deck to the hand: leaves face-down, flips
## face-up mid-flight so the player sees what they got.
func _fly_draw_to_hand(pile_id: String, card: Card) -> void:
	if card == null or _hand_marker == null:
		return
	var ghost := _make_ghost(card, false)
	var dst := _hand_marker.position + Vector2(0, -HANDCARD_H * 0.55)
	var half := ghost.size * 0.5
	Juice.fly_arc(ghost, _deck_screen_pos(pile_id) - half, dst - half,
		{"dur": 0.32, "height": 0.2, "spin": 25.0, "land_squash": false})
	var flip := create_tween().bind_node(ghost)
	flip.tween_interval(Juice.d(0.1))
	flip.tween_callback(func() -> void: Juice.flip_card(ghost, true, 0.16))
	var fade := create_tween().bind_node(ghost)
	fade.tween_interval(Juice.d(0.32))
	fade.tween_property(ghost, "modulate:a", 0.0, Juice.d(0.1))
	fade.tween_callback(ghost.queue_free)

func _make_ghost(card: Card, face: bool, scale_mul: float = GHOST_SCALE) -> CardNode:
	var ghost := CardNode.new()
	ghost.setup(card, face, HANDCARD_W * scale_mul, HANDCARD_H * scale_mul)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 60
	add_child(ghost)
	return ghost

## Arcs a face-up ghost card between two screen points (centers). When
## `to_discard`, it slaps down onto the pile: sparks + pile bump on landing.
func _spawn_ghost(card: Card, from: Vector2, to: Vector2, to_discard: bool = false) -> void:
	var ghost := _make_ghost(card, true)
	var half := ghost.size * 0.5
	var tw := Juice.fly_arc(ghost, from - half, to - half,
		{"dur": 0.38, "height": 0.28, "spin": randf_range(-40.0, 40.0), "rot_to": randf_range(-8.0, 8.0), "peak_scale": 1.2, "end_scale": 0.85})
	if to_discard:
		tw.tween_callback(func() -> void: _on_card_landed_discard(to))
	tw.tween_property(ghost, "modulate:a", 0.0, Juice.d(0.12))
	tw.tween_callback(ghost.queue_free)

## Landing beat on the discard pile: slap sound, spark burst, 3D card bump.
func _on_card_landed_discard(at: Vector2) -> void:
	_sfx(&"card_slide")
	Juice.burst(self, at, &"sparks", 0.8)
	if _shaker:
		_shaker.add_trauma(0.12)
	if _discard_sprite:
		var base := _discard_sprite_base_scale
		var tw := create_tween().bind_node(_discard_sprite)
		tw.tween_property(_discard_sprite, "scale", base * 1.18, Juice.d(0.06))
		tw.tween_property(_discard_sprite, "scale", base, Juice.d(0.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Flies `count` card-back ghosts from a deck to a seat, staggered, so forced
## draws (Draw Two/Four/Ten) read as visible processing time. Each lands at
## ~0.42 + i*0.32 s (the hand reveal in _reveal_hand_tail is synced to this).
func _animate_forced_draw(pile_id: String, target_index: int, count: int) -> void:
	if count <= 0:
		return
	if target_index == own_index:
		_play_center_banner("+%d" % count, Color(1.0, 0.55, 0.3), 96, 0.35)
	var src := _deck_screen_pos(pile_id)
	var dst := _target_screen_pos(target_index)
	for i in range(count):
		var ghost := _make_ghost(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""), false)
		ghost.modulate.a = 0.0
		var half := ghost.size * 0.5
		var jitter := Vector2(randf_range(-14.0, 14.0), randf_range(-8.0, 8.0))
		var delay := Juice.d(i * 0.32)
		var tw := Juice.fly_arc(ghost, src - half, dst - half + jitter,
			{"dur": 0.42, "delay": delay, "height": 0.22, "spin": randf_range(120.0, 220.0), "rot_to": randf_range(-12.0, 12.0), "land_squash": false, "end_scale": 0.8})
		tw.tween_property(ghost, "modulate:a", 0.0, Juice.d(0.14))
		tw.tween_callback(ghost.queue_free)
		var show := create_tween().bind_node(ghost)
		show.tween_interval(delay)
		show.tween_callback(func() -> void: _sfx(&"forced_draw"))
		show.tween_property(ghost, "modulate:a", 1.0, 0.06)
		var land := create_tween().bind_node(ghost)
		land.tween_interval(delay + Juice.d(0.42))
		land.tween_callback(func() -> void: _on_seat_hit(target_index))

## Small "ouch" reaction when a forced-draw card lands on a seat.
func _on_seat_hit(seat: int) -> void:
	if seat == own_index:
		if _shaker:
			_shaker.add_trauma(0.18)
		return
	_character_react(seat, &"hit")

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
		cn.scale = Vector2(0.55, 0.55)
		cn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := create_tween().bind_node(cn)
		tw.tween_interval(Juice.d(first_delay + float(i - start) * step))
		tw.tween_property(cn, "scale", Vector2.ONE, Juice.d(0.26)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(cn, "modulate:a", 1.0, Juice.d(0.14))
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
		var marker: Marker3D = _marker_players[_seat_marker_idx(seat) % _marker_players.size()]
		return _unproject(marker.global_position + Vector3(0, _char_scale * 1.8, 0))
	return Vector2(960, 300)

## Extra world-space margin around a pile's real footprint that still counts as "on the deck".
const PILE_HIT_PAD := 0.12
## Smallest comfortable click target, in UI pixels.
const PILE_HIT_MIN := Vector2(76, 100)

## World-space box around a draw pile: the REAL pile mesh (so it follows what you see, not
## the editor marker), padded sideways and tall enough to include the top card.
func _pile_hit_aabb(pile_id: String) -> AABB:
	var mesh: MeshInstance3D = _pile_a_mesh if pile_id == "A" else _pile_b_mesh
	var marker: Marker3D = _marker_deck_a if pile_id == "A" else _marker_deck_b
	var centre := Vector3.ZERO
	if mesh != null and is_instance_valid(mesh):
		centre = mesh.global_position
	elif marker != null:
		centre = marker.global_position
	else:
		return AABB()
	var w := _card_w3d if _card_w3d > 0.0 else 0.4
	var half := Vector3(w * 0.5 + PILE_HIT_PAD, 0.1, w * 1.4375 * 0.5 + PILE_HIT_PAD)
	return AABB(centre - half, half * 2.0)

## The pile's click zone on screen: the projected bounds of its world box, so it grows and
## shrinks with distance and camera angle. Empty Rect2 when the pile does not exist.
func _pile_screen_rect(pile_id: String) -> Rect2:
	var bb := _pile_hit_aabb(pile_id)
	if bb.size == Vector3.ZERO or _camera_3d == null:
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(8):
		var p := _unproject(bb.get_endpoint(i))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var r := Rect2(lo, hi - lo)
	if r.size.x < PILE_HIT_MIN.x:
		r = r.grow_individual((PILE_HIT_MIN.x - r.size.x) * 0.5, 0.0, (PILE_HIT_MIN.x - r.size.x) * 0.5, 0.0)
	if r.size.y < PILE_HIT_MIN.y:
		r = r.grow_individual(0.0, (PILE_HIT_MIN.y - r.size.y) * 0.5, 0.0, (PILE_HIT_MIN.y - r.size.y) * 0.5)
	return r.grow(6.0)

## Projects the deck piles onto screen space and moves the click zones there.
func _reposition_draw_zones() -> void:
	if not _camera_3d or not _viewport_3d or _viewport_3d.size.x <= 0:
		return
	if _draw_btn_a == null or _draw_btn_b == null:
		return
	var ra := _pile_screen_rect("A")
	if ra.size.x > 0.0:
		_draw_btn_a.position = ra.position
		_draw_btn_a.size = ra.size
	var rb := _pile_screen_rect("B")
	if rb.size.x > 0.0:
		_draw_btn_b.position = rb.position
		_draw_btn_b.size = rb.size
	for t: Variant in _seat_tags.values():
		if is_instance_valid(t):
			_layout_seat_tag(t as Label)

## A chamber-odds badge that floats IN the 3D scene above its deck: the 2D gauge
## Control renders into a SubViewport whose texture is shown on a billboard
## Sprite3D. Works the same for the host and for online clients (the data comes
## from the local GameState / the host's snapshot either way).
func _make_gauge_3d(marker: Marker3D) -> Control:
	var gauge: Control = preload("res://scripts/ui/deck_gauge.gd").new()
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.gui_disable_input = true
	vp.size = Vector2i(352, 128)
	vp.size_2d_override = Vector2i(176, 64)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(gauge)
	_viewport_3d.add_child(vp)
	var sp := Sprite3D.new()
	sp.name = "DeckTag"
	sp.texture = vp.get_texture()
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.pixel_size = (_card_w3d * 1.25) / 352.0
	_viewport_3d.add_child(sp)
	if marker:
		sp.global_position = marker.global_position + Vector3(0.0, _card_w3d * 0.95, 0.0)
	gauge.set_meta(&"sprite", sp)
	return gauge

# ── UI styling helpers (delegate to the UIStyle autoload) ─────────────

## Every in-game button is built through here so all chrome shares the noir
## casino look. `tint` (legacy per-button color) is pulled toward smoke so
## bright greens/reds read as muted casino tones.
func _make_kenney_button(text: String, min_size: Vector2, font_size: int = 18, tint: Color = Color.WHITE) -> Button:
	if tint == Color.WHITE:
		return UIStyle.make_button(text, &"secondary", min_size, font_size)
	return UIStyle.make_tinted_button(text, tint.lerp(UIStyle.SMOKE, 0.35).darkened(0.08), min_size, font_size)

## Big flat card-color button for the color-choice dialog.
func _make_color_button(text: String, color: Color, min_size: Vector2, font_size: int = 18) -> Button:
	return UIStyle.make_color_button(text, color, min_size, font_size)

## Slim smoked-glass strip with a brass hairline along the bottom edge.
func _top_bar_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UIStyle.INK, 0.82)
	s.border_color = Color(UIStyle.BRASS_DIM, 0.9)
	s.border_width_bottom = 2
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	s.content_margin_left = 18
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

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
	game.player_passed_out.connect(_on_player_passed_out)
	game.player_woke_up.connect(_on_player_woke_up)
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
	game.player_passed_out.connect(_on_player_passed_out)
	game.player_woke_up.connect(_on_player_woke_up)
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
	_record_log(text)
	# Host forwards authoritative game log lines to clients (peek lines filtered).
	if is_online and is_host_here() and not _is_peek_log(text):
		rpc("_rpc_log", text)

	# Show action card notifications from log messages.
	_show_notification_for_log(text)

func is_host_here() -> bool:
	return _eos != null and _eos.is_host

## Another player drank themselves under the table / came round again (host/offline only).
func _on_player_passed_out(player_index: int) -> void:
	if player_index != own_index:
		_show_notification("💤 %s passed out!" % game.players[player_index].display_name, 2.5)
	_refresh_all()

func _on_player_woke_up(player_index: int, penalty: int) -> void:
	if player_index != own_index:
		_show_notification("%s wakes up with %d extra cards." % [game.players[player_index].display_name, penalty], 2.5)
	_refresh_all()

## Called when a player respawns from a Respawn card.
func _on_player_respawned(player_index: int) -> void:
	var p: PlayerData = game.players[player_index]
	if player_index == own_index:
		# Local player respawned — leave spectator mode!
		state = State.WAITING
		_show_notification("🎉 You RESPAWNED! Back in the game!", 3.0)
	else:
		_show_notification("🎉 %s RESPAWNED!" % p.display_name, 3.0)
	_sfx(&"respawn")
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
	_sfx(&"vote")
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
	vote_panel.add_theme_stylebox_override("panel", UIStyle.panel_style())
	vote_panel.z_index = LAYER_MODAL
	_cut_banner()
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
		var was_visible := notification_label.visible
		notification_label.text = text
		notification_label.visible = true
		_notification_timer = duration
		# Hug the text and stay centered under the top bar.
		var w := notification_label.get_combined_minimum_size().x
		notification_label.offset_left = -w * 0.5
		notification_label.offset_right = w * 0.5
		if not was_visible:
			notification_label.modulate.a = 0.0
			var tw := create_tween().bind_node(notification_label).set_parallel()
			tw.tween_property(notification_label, "offset_top", 54.0, Juice.d(0.22)).from(30.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(notification_label, "modulate:a", 1.0, Juice.d(0.15))

## Big center-screen banner: a smoked band with brass rules sweeps in, the
## title punches in over it, holds, then everything slides/fades away.
func _play_center_banner(text: String, color: Color, size_px: int, hold: float = 0.55) -> void:
	# Queued: banners play one at a time, never over a decision popup, the
	# Chamber, the deal roulette or the pause screen (see _pump_banners).
	_banner_queue.append({"text": text, "color": color, "size": size_px, "hold": hold, "t": Time.get_ticks_msec()})
	_pump_banners()

## True while something more important than an announcement owns the screen.
func _banner_blocked() -> bool:
	return _paused or _modal_visible() or state == State.CHAMBER_REVEAL or state == State.GAME_OVER \
		or get_node_or_null("FirstRoulette") != null or get_node_or_null("ChamberBG") != null

## Any popup that is waiting on the player's decision.
func _modal_visible() -> bool:
	return (overlay != null and overlay.visible) or _jump_prompt != null or get_node_or_null("BombVotePanel") != null \
		or (_vice_picker != null and is_instance_valid(_vice_picker))

func _pump_banners() -> void:
	if _banner_active or _banner_queue.is_empty() or _banner_blocked():
		return
	var now := Time.get_ticks_msec()
	while not _banner_queue.is_empty() and now - int(_banner_queue[0].t) > BANNER_MAX_AGE_MS:
		_banner_queue.pop_front()
	if _banner_queue.is_empty():
		return
	var b: Dictionary = _banner_queue.pop_front()
	_banner_active = true
	_show_banner_now(b.text, b.color, b.size, b.hold)

## Ends the current banner quickly so a decision popup can take the stage
## (announcement first, then the choice — never both at once).
func _cut_banner() -> void:
	var cur := get_node_or_null("CenterBanner")
	if cur:
		cur.name = "CenterBannerCut"
		var tw := create_tween().bind_node(cur)
		tw.tween_property(cur, "modulate:a", 0.0, 0.12)
		tw.tween_callback(cur.queue_free)
	_banner_active = false

## Clears every transient layer (banners, roulette, popups) before a takeover
## moment such as the Chamber or game over.
func _clear_stage() -> void:
	_banner_queue.clear()
	_cut_banner()
	var roulette := get_node_or_null("FirstRoulette")
	if roulette:
		roulette.queue_free()
	_dismiss_all_overlays()

func _show_banner_now(text: String, color: Color, size_px: int, hold: float) -> void:
	var root := Control.new()
	root.name = "CenterBanner"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = LAYER_BANNER
	add_child(root)

	var band_h := float(size_px) * 1.9
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(size.x * 1.3, band_h)
	band.position = Vector2(-size.x * 0.15, size.y * 0.5 - band_h * 0.5)
	band.pivot_offset = band.size * 0.5
	band.rotation_degrees = -2.5
	root.add_child(band)
	var fill := ColorRect.new()
	fill.color = Color(UIStyle.INK, 0.82)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(fill)
	for edge in [0.0, 1.0]:
		var rule := ColorRect.new()
		rule.color = Color(color.lerp(UIStyle.BRASS, 0.5), 0.9)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rule.size = Vector2(band.size.x, 3)
		rule.position = Vector2(0, edge * (band_h - 3))
		band.add_child(rule)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UIStyle.title_font())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", maxi(4, size_px / 9))
	label.add_theme_color_override("font_shadow_color", Color(color, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", maxi(10, size_px / 3))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(label)
	label.pivot_offset = size * 0.5
	label.scale = Vector2(1.6, 1.6)
	label.modulate.a = 0.0

	var sweep := create_tween().bind_node(root)
	sweep.tween_property(band, "position:x", band.position.x, Juice.d(0.22)).from(-band.size.x).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var tw := create_tween().bind_node(root)
	tw.tween_interval(Juice.d(0.08))
	tw.tween_property(label, "scale", Vector2.ONE, Juice.d(0.24)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 1.0, Juice.d(0.1))
	if hold > 0.0:
		tw.tween_interval(Juice.d(hold))
	tw.tween_property(band, "position:x", size.x, Juice.d(0.25)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(label, "modulate:a", 0.0, Juice.d(0.2))
	tw.tween_callback(root.queue_free)
	tw.tween_callback(func() -> void:
		if root.name == "CenterBanner":
			_banner_active = false)

## Played the first time control passes to the local player each turn.
func _play_your_turn_animation() -> void:
	_play_center_banner("YOUR TURN", UIStyle.BRASS_LIGHT, 72)
	_sfx(&"your_turn")

## Respawn reveal: banner, then the fresh hand (local) or re-summoned character
## (opponent) pops in AFTER the animation.
func _play_respawn_animation(player_index: int) -> void:
	var p: PlayerData = game.players[player_index]
	_play_center_banner("%s RESPAWNED" % p.display_name, Color(0.55, 1.0, 0.7), 52)
	Juice.burst(self, _target_screen_pos(player_index), &"gold", 1.4)
	_sfx(&"respawn")
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
		_character_react(player_index, &"respawn")

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
		if _deal_cards_dealt == 0:
			_sfx(&"shuffle")
		if _deal_cards_dealt < _deal_total_cards:
			# A card-back arcs from the deck to the current player.
			var pile := "A" if _deal_cards_dealt % 2 == 0 else "B"
			var ghost := _make_ghost(CardDatabase._make(Card.CardType.NUMBER, 0, -1, "", ""), false, 0.7)
			ghost.modulate.a = 0.95
			var half := ghost.size * 0.5
			var jitter := Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0))
			var tw := Juice.fly_arc(ghost, _deck_screen_pos(pile) - half, _target_screen_pos(_deal_player_idx) - half + jitter,
				{"dur": 0.24, "height": 0.16, "spin": randf_range(150.0, 210.0), "rot_to": randf_range(-10.0, 10.0), "land_squash": false, "peak_scale": 1.1, "end_scale": 0.85})
			tw.tween_property(ghost, "modulate:a", 0.0, 0.08)
			tw.tween_callback(ghost.queue_free)

			_sfx(&"deal")

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
			_reveal_hand_tail(card_nodes.size(), 0.0, 0.04)

	elif _deal_phase == 1:
		# Phase 1: The starter arcs face-down from the deck and FLIPS onto the pile.
		var starter_card: Card = null
		if not game.deck.discard.is_empty():
			starter_card = game.deck.discard.back()

		if starter_card:
			if _discard_sprite:
				_discard_sprite.visible = false
			var ghost := _make_ghost(starter_card, false, 0.9)
			var half := ghost.size * 0.5
			var dst := _discard_screen_pos()
			var tw := Juice.fly_arc(ghost, _deck_screen_pos("A") - half, dst - half,
				{"dur": 0.32, "height": 0.3, "spin": 180.0, "land_squash": false})
			tw.tween_callback(func() -> void: _sfx(&"card_flip"))
			var flip := create_tween().bind_node(ghost)
			flip.tween_interval(Juice.d(0.32))
			flip.tween_callback(func() -> void: Juice.flip_card(ghost, true, 0.26))
			flip.tween_interval(Juice.d(0.3))
			flip.tween_callback(func() -> void:
				_on_card_landed_discard(dst)
				_refresh_discard())
			flip.tween_property(ghost, "modulate:a", 0.0, 0.12)
			flip.tween_callback(ghost.queue_free)

		# Phase 2: Pick first player.
		_deal_phase = 2
		_deal_timer = 0.9

	elif _deal_phase == 2:
		# Phase 2: A roulette sweeps the seats and lands on the first player.
		var first := randi() % num_players
		game.current_index = first
		_deal_phase = 99  # waiting on the roulette coroutine
		_deal_timer = 999.0
		_roulette_first_player(first)

	elif _deal_phase == 3:
		# Done — transition to the first turn (drop the "Dealing..." toast).
		_notification_timer = 0.0
		if notification_label:
			notification_label.visible = false
		if is_online and is_host_here():
			_broadcast_snapshot()
		_check_turn()

## Spotlight roulette: a name banner ticks through the seats, slowing down,
## and stops on `first`. Ends by resuming the deal state machine (phase 3).
func _roulette_first_player(first: int) -> void:
	var n := game.players.size()
	var steps := n * 2 + first + 1
	var delay := 0.05
	var label := UIStyle.make_label("", 44, UIStyle.CREAM, true)
	label.name = "FirstRoulette"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -400
	label.offset_right = 400
	label.offset_top = -40
	label.offset_bottom = 40
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	for k in range(steps):
		var seat := k % n
		var pl: PlayerData = game.players[seat]
		label.text = pl.display_name
		label.add_theme_color_override("font_color", pl.color.lightened(0.3))
		_sfx(&"cylinder_click", -2.0, 1.0 + float(k) / float(steps) * 0.3)
		_character_react(seat, &"play")
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(label):
			return
		delay = minf(delay * 1.16, 0.34)
	label.text = "%s GOES FIRST!" % game.players[first].display_name
	label.add_theme_color_override("font_color", UIStyle.BRASS_LIGHT)
	Juice.punch(label, 0.25, 0.45)
	_sfx(&"banner")
	await get_tree().create_timer(1.1).timeout
	if is_instance_valid(label):
		var tw := create_tween().bind_node(label)
		tw.tween_property(label, "modulate:a", 0.0, 0.25)
		tw.tween_callback(label.queue_free)
	_deal_phase = 3
	_deal_timer = 0.2

# ── Refresh All ───────────────────────────────────────────────────────

func _refresh_all() -> void:
	_detect_remote_plays()
	_refresh_decks()
	_refresh_discard()
	_refresh_opponents()
	_refresh_hand()
	_refresh_top_bar()
	_update_turn_border()
	# Show overcharge banner when it activates.
	if game.overcharge_active and not _overcharge_notified:
		_overcharge_notified = true
		_play_center_banner("OVERCHARGED - play 2 cards", Color(1.0, 0.85, 0.3), 36, 0.8)
	elif not game.overcharge_active:
		_overcharge_notified = false

## Opponent / AI / remote plays don't go through the local fly code — detect
## them here (discard top changed AND an opponent's hand shrank) and fly a
## ghost from that seat to the pile so every play reads on screen.
func _detect_remote_plays() -> void:
	if game == null or game.deck == null:
		return
	var top: Card = null if game.deck.discard.is_empty() else game.deck.discard.back()
	var sizes: Array[int] = []
	for pl in game.players:
		sizes.append(pl.hand_size())
	if state != State.DEALING and top != null and top != _last_discard_top and not _suppress_discard_fly 			and _last_hand_sizes.size() == sizes.size():
		for i in range(sizes.size()):
			if i != own_index and sizes[i] < _last_hand_sizes[i]:
				_spawn_ghost(top, _target_screen_pos(i), _discard_screen_pos(), true)
				_character_react(i, &"play")
				break
	_suppress_discard_fly = false
	_last_discard_top = top
	_last_hand_sizes = sizes


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
	_set_pile_thickness(_pile_a_mesh, game.deck.pile_a.size())
	_set_pile_thickness(_pile_b_mesh, game.deck.pile_b.size())
	var sz_a := game.deck.pile_a.size()
	var sz_b := game.deck.pile_b.size()
	if _gauge_a:
		_gauge_a.set_data("DECK A", sz_a, _chamber_pct(_deck_bombs("A"), sz_a))
	if _gauge_b:
		_gauge_b.set_data("DECK B", sz_b, _chamber_pct(_deck_bombs("B"), sz_b))

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
	call_deferred("_apply_hand_selection")
	# Keep existing CardNodes in slot order so a refresh GLIDES each card from
	# its old slot to its new one (played cards close the gap, draws extend the
	# fan). Nodes past the new hand size go back to the pool.
	var prev_nodes: Array[CardNode] = card_nodes.duplicate()
	card_nodes.clear()

	if game.players.is_empty() or own_index >= game.players.size():
		for stale in prev_nodes:
			stale.visible = false
			if stale.get_parent():
				stale.get_parent().remove_child(stale)
			_card_node_pool.append(stale)
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

	var n := p.hand.size() if _hand_marker != null else 0
	if state == State.DEALING and _deal_phase == 0:
		n = 0  # the hand pops in when the deal finishes
	for k in range(n, prev_nodes.size()):
		var extra: CardNode = prev_nodes[k]
		extra.visible = false
		if extra.get_parent():
			extra.get_parent().remove_child(extra)
		_card_node_pool.append(extra)
	if n == 0:
		return

	# Fan the hand around the player_ui CenterCards marker, pivoted at the
	# bottom-center of each card so hover lift + rotation look natural. The
	# fan tightens as the hand grows so it never runs off-screen.
	var spacing := HANDCARD_W * clampf(0.62 - 0.012 * float(n), 0.32, 0.62)
	var total_w := (n - 1) * spacing + HANDCARD_W
	var x0 := _hand_marker.position.x - total_w / 2.0
	var y0 := _hand_marker.position.y - HANDCARD_H
	var arc := clampf(4.0 + float(n) * 1.1, 4.0, 16.0)

	for i in range(n):
		var is_playable := (state == State.HUMAN_TURN and i in valid_plays) or (state == State.FORCED_DRAW_DECK_CHOICE and i in stackable)
		var cn: CardNode
		var reused := i < prev_nodes.size()
		if reused:
			cn = prev_nodes[i]
		elif _card_node_pool.size() > 0:
			cn = _card_node_pool.pop_back()
		else:
			cn = CardNode.new()
		cn.setup(p.hand[i], true, HANDCARD_W, HANDCARD_H)
		cn.set_playable(is_playable)
		cn.set_dimmed(state == State.HUMAN_TURN and not is_playable)
		if not cn.card_clicked.is_connected(_on_card_clicked):
			cn.card_clicked.connect(_on_card_clicked)
		cn.pivot_offset = Vector2(HANDCARD_W / 2.0, HANDCARD_H)
		cn.visible = true
		if cn.get_parent() == null:
			_player_ui.add_child(cn)
		# Slight arc: edge cards sit lower, like a hand held in a fan.
		var t: float = 0.0
		if n > 1:
			t = (float(i) / float(n - 1)) * 2.0 - 1.0
		var slot := Vector2(x0 + i * spacing, y0 + t * t * arc - (PLAYABLE_LIFT if is_playable else 0.0))
		cn.place(slot, t * 10.0, 0.2 if reused else 0.0)
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
		var dir_arrow := "↻" if game.direction >= 0 else "↺"
		if game.active_number >= 0:
			active_display.text = "●  %s  %d     %s" % [col_name, game.active_number, dir_arrow]
		else:
			active_display.text = "●  %s     %s" % [col_name, dir_arrow]
		var chip: Color = CardNode.SUIT_COLORS.get(game.active_color, UIStyle.CREAM)
		active_display.add_theme_color_override("font_color", chip.lightened(0.35))

	_highlight_decks(state == State.HUMAN_TURN or state == State.FORCED_DRAW_DECK_CHOICE or state == State.LAST_SHOT)

func _highlight_decks(highlight: bool) -> void:
	for g: Control in [_gauge_a, _gauge_b]:
		if g:
			g.set_active(highlight)
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
	if game.deck.discard.is_empty() or (state == State.DEALING and _deal_phase < 2):
		_discard_sprite.visible = false
	else:
		var top_card: Card = game.deck.discard.back()
		if top_card != _discard_card_node.card_data:
			# Each new top card lands at a slight random twist, like a real pile.
			_discard_sprite.rotation_degrees = Vector3(-90.0, randf_range(-14.0, 14.0), 0.0)
		_discard_card_node.setup(top_card, true, 256.0, 384.0)
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
			_show_notification("You must draw %d! Stack any Draw card, or pick Deck A/B." % draw_count, 5.0)
			_refresh_all()
			_reset_turn_timer()  # a fresh clock for the decision (forfeits on expiry)
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
			_play_center_banner("LAST SHOT", UIStyle.BLOOD_LIGHT, 56, 1.2)
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
			# "Thinking…" bubble over the acting AI so it's clear who's deciding.
			var thinker: Node3D = _char_node_by_index.get(game.current_index, null)
			if thinker != null and is_instance_valid(thinker):
				thinker.emote("emote_dots3", _ai_timer)

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

## Wiggles a hand card to signal a rejected play.
func _shake_hand_card(hand_idx: int) -> void:
	if hand_idx >= 0 and hand_idx < card_nodes.size():
		card_nodes[hand_idx].shake_invalid()

## Core path for playing the card at hand_idx (mouse or keyboard).
func _play_by_hand_index(hand_idx: int) -> void:
	if _paused or _hands_busy or _own_passed_out():
		return
	if game.current_index != own_index:
		return
	if hand_idx < 0 or hand_idx >= game.players[own_index].hand.size():
		return

	# Tutorial: restrict which hand cards the player may play this step.
	if is_tutorial:
		if not (_tut_input_hands.is_empty() or hand_idx in _tut_input_hands):
			_show_notification("Not that card -- follow the tutorial prompt!", 1.5)
			_sfx(&"invalid")
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
				_sfx(&"card_play")
				_finalize_or_send_play()
		else:
			_show_notification("Only the same +N value can be stacked here!", 1.5)
			_sfx(&"invalid")
			_shake_hand_card(hand_idx)
		return

	if state != State.HUMAN_TURN:
		return

	if not card.matches(game.active_color, game.active_number, game.active_action_id):
		_show_notification("Can't play that card!", 1.5)
		_sfx(&"invalid")
		_shake_hand_card(hand_idx)
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
					_show_target_selector("Who draws - and loses their turn?")
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
	_sfx(&"card_play")

	# Plain cards and non-special actions finish through the shared path
	# (offline executes locally, online host self-routes, online client sends intent).
	_finalize_or_send_play()

func _on_deck_clicked(pile_id: String) -> void:
	if _paused or _hands_busy or _own_passed_out() or state == State.SPECTATING:
		return

	# Tutorial: deck clicks only allowed when the current step calls for one
	# (forced-draw deck choice is always part of an on-going tutorial step).
	if is_tutorial and not _tut_allow_draw and state != State.FORCED_DRAW_DECK_CHOICE:
		_show_notification("Not now -- follow the tutorial prompt!", 1.5)
		_sfx(&"invalid")
		return

	# Handle forced draw deck choice (Draw Two/Four/Ten target).
	if state == State.FORCED_DRAW_DECK_CHOICE and game.pending_forced_draw_player_index == own_index:
		_sfx(&"card_draw")
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
		_sfx(&"card_draw")
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
	_sfx(&"card_draw")

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
	if is_online and is_host_here():
		_drew_marker = own_index
		_broadcast_snapshot()
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
	_sfx(&"end_turn")
	if is_online and not is_host_here():
		# The host owns the game: ask it to end this turn.
		state = State.WAITING
		send_intent({"kind": "end_turn"})
		_refresh_all()
		return
	game.advance_turn()
	if is_online:
		_drew_marker = -1
		_broadcast_snapshot()
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
		_turn_timer_label.visible = true
		_turn_timer_label.text = str(int(TURN_TIME_LIMIT))
	_last_timer_second = -1

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
	# Last-10-seconds ticks on the local player's turn; last 5 pulse the ring.
	var sec := ceili(_turn_timer)
	if sec != _last_timer_second:
		_last_timer_second = sec
		if game and game.current_index == own_index and sec > 0 and sec <= 10:
			_sfx(&"timer_urgent" if sec <= 5 else &"timer_tick")
			if sec <= 5 and _turn_timer_ring:
				Juice.punch(_turn_timer_ring, 0.14, 0.3)

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
	# Online client: the HOST owns the game state. Never mutate the local render-only
	# copy (its deck is placeholders: that is what made junk "-1" cards appear) - just
	# tell the host this player ran out of time.
	if is_online and not is_host_here():
		_hide_timer_ui()
		state = State.WAITING
		send_intent({"kind": "timeout"})
		_refresh_all()
		return
	_apply_turn_timeout()
	if is_online and is_host_here():
		_broadcast_snapshot()

func _apply_turn_timeout() -> void:
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
		_sfx(&"timer_expired")
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

	_sfx(&"timer_expired")

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
	if key_event.keycode == KEY_L:
		_toggle_log_panel()
		return
	if key_event.keycode == KEY_ESCAPE:
		if _log_panel != null:
			_toggle_log_panel()
			return
		if _vice_picker != null and is_instance_valid(_vice_picker):
			return  # the picker handles its own Esc
		_toggle_pause()
		return
	if _paused:
		return
	if Keybinds.matches(key_event, &"smoke"):
		_request_emote(&"smoke")
		return
	if Keybinds.matches(key_event, &"drink"):
		_request_emote(&"drink")
		return
	if Keybinds.matches(key_event, &"line"):
		_request_line()  # hidden: not listed anywhere in the UI
		return
	if Keybinds.matches(key_event, &"kill_high"):
		_kill_high()
		return
	if Keybinds.matches(key_event, &"end_turn"):
		if _end_turn_btn != null and _end_turn_btn.visible and not _paused and not _hands_busy:
			_end_turn()
		return
	if Keybinds.matches(key_event, &"change_vice") and not _paused:
		var smoking_now := _smoke_session != null and is_instance_valid(_smoke_session)
		var drinking_now := _drinking_active()
		if smoking_now or drinking_now:
			_change_vice_choice(&"smoke" if smoking_now else &"drink")
			return
	if Keybinds.matches(key_event, &"free_cursor"):
		_cursor_free = not _cursor_free
		_show_notification(("Cursor free  ·  %s to return to mouse look" % Keybinds.label(&"free_cursor")) if _cursor_free else "Mouse look on", 1.6)
		return
	if state == State.SPECTATING:
		return

	# Forced draw deck choice: A/B keys choose the deck, number keys stack a
	# matching Draw card (if the card at that index is stackable).
	if state == State.FORCED_DRAW_DECK_CHOICE and game.pending_forced_draw_player_index == own_index:
		var key := key_event.keycode
		if Keybinds.matches(key_event, &"draw_a") or key == KEY_LEFT:
			_on_deck_clicked("A")
		elif Keybinds.matches(key_event, &"draw_b") or key == KEY_RIGHT:
			_on_deck_clicked("B")
		elif key >= KEY_1 and key <= KEY_9:
			_play_by_hand_index(key - KEY_1)
		elif key == KEY_0:
			_play_by_hand_index(9)
		return

	# Last Shot: A/B keys choose which deck to pull the chamber card from.
	if state == State.LAST_SHOT and game.pending_last_shot and game.current_index == own_index:
		var ls_key := key_event.keycode
		if Keybinds.matches(key_event, &"draw_a") or ls_key == KEY_LEFT:
			_on_deck_clicked("A")
		elif Keybinds.matches(key_event, &"draw_b") or ls_key == KEY_RIGHT:
			_on_deck_clicked("B")
		return

	if state != State.HUMAN_TURN:
		return
	if game.current_index != own_index:
		return
	var key := key_event.keycode
	if Keybinds.matches(key_event, &"draw_a") or key == KEY_LEFT:
		_on_deck_clicked("A")
	elif Keybinds.matches(key_event, &"draw_b") or key == KEY_RIGHT:
		_on_deck_clicked("B")
	elif Keybinds.matches(key_event, &"end_turn"):
		# After drawing, the end-turn key ends the turn without playing.
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
	_sfx(&"jump_in")
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
	_sfx(&"jump_in")
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
	_cut_banner()
	# Framed modal panel (same look + layer as every other decision popup).
	var panel := UIStyle.make_panel()
	panel.name = "JumpPrompt"
	panel.z_index = LAYER_MODAL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	_jump_prompt = panel
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIStyle.make_label("JUMP IN!", 30, UIStyle.BRASS_LIGHT, true))
	vbox.add_child(UIStyle.make_label("You hold the same card - slap it down out of turn!", 15, UIStyle.CREAM))

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

	# Center on the play area (above the hand) and pop in.
	panel.reset_size()
	panel.position = Vector2((size.x - panel.size.x) * 0.5, size.y * 0.42 - panel.size.y * 0.5)
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.9, 0.9)
	create_tween().bind_node(panel).tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sfx(&"banner")

func _hide_jump_prompt() -> void:
	if _jump_prompt:
		_jump_prompt.queue_free()
		_jump_prompt = null

# ── Pause (offline vs AI only) ───────────────────────────────────────

## Offline: freezes the game. Online host: freezes it for EVERYONE. Online client:
## only opens a personal menu (resume / settings / main menu); the game keeps running.
func _toggle_pause() -> void:
	if is_tutorial:
		return
	if is_online and not is_host_here():
		if _paused:
			return  # the host's pause is in charge; only Settings / Main Menu are offered
		if _pause_overlay:
			_hide_pause_overlay()
		else:
			_show_pause_overlay("menu")
		return
	if state == State.CHAMBER_REVEAL or state == State.GAME_OVER:
		_show_notification("Can't pause right now.", 1.5)
		return
	_paused = not _paused
	if _paused:
		_show_pause_overlay("pause")
	else:
		_hide_pause_overlay()
		_sfx(&"pause")
		_show_notification("Game resumed.", 1.0)
	if is_online:
		var host_name: String = game.players[own_index].display_name if own_index < game.players.size() else "Host"
		rpc("_rpc_set_paused", _paused, host_name)

## Host → clients: the host paused / resumed the table.
@rpc("authority", "call_remote", "reliable")
func _rpc_set_paused(value: bool, by_name: String) -> void:
	if not is_online or is_host_here():
		return
	_paused = value
	_hide_pause_overlay()
	if value:
		_show_pause_overlay("host_paused", by_name)
	else:
		_sfx(&"pause")
		_show_notification("Host resumed the game.", 1.2)

## kind: "pause" (frozen, Resume), "menu" (client menu, game still running),
## "host_paused" (client while the host has the table frozen; no Resume).
func _show_pause_overlay(kind: String = "pause", by_name: String = "") -> void:
	if _pause_overlay:
		return
	var dim := ColorRect.new()
	dim.name = "PauseOverlay"
	dim.z_index = LAYER_PAUSE
	dim.color = Color(UIStyle.INK, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_pause_overlay = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := UIStyle.make_panel()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	var title_text := "MENU" if kind == "menu" else "PAUSED"
	var title := UIStyle.make_label(title_text, 44, UIStyle.BRASS, true)
	vbox.add_child(title)
	if kind == "host_paused":
		var who := by_name if not by_name.is_empty() else "The host"
		vbox.add_child(UIStyle.make_label("%s paused the game" % who, 18, UIStyle.CREAM, true))
	else:
		var resume_btn := UIStyle.make_button("Resume", &"primary", Vector2(220, 52), 20)
		resume_btn.pressed.connect(_toggle_pause)
		vbox.add_child(resume_btn)
	if _wired_active and _wired_ending <= 0.0:
		var sober_btn := UIStyle.make_button("End the high", &"secondary", Vector2(220, 52), 20)
		sober_btn.pressed.connect(func() -> void:
			_kill_high()
			sober_btn.disabled = true)
		vbox.add_child(sober_btn)
	var settings_btn := UIStyle.make_button("Settings", &"secondary", Vector2(220, 52), 20)
	settings_btn.pressed.connect(func() -> void:
		var sp := preload("res://scripts/settings_panel.gd").new()
		add_child(sp))
	vbox.add_child(settings_btn)
	var menu_btn := UIStyle.make_button("Main Menu", &"danger", Vector2(220, 52), 20)
	menu_btn.pressed.connect(_on_main_menu)
	vbox.add_child(menu_btn)
	panel.pivot_offset = Vector2(150, 140)
	panel.scale = Vector2(0.9, 0.9)
	create_tween().bind_node(panel).tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_sfx(&"button")

func _hide_pause_overlay() -> void:
	if _pause_overlay:
		_pause_overlay.queue_free()
		_pause_overlay = null

# ── Color Selector ────────────────────────────────────────────────────

func _show_color_selector() -> void:
	_dismiss_all_overlays()
	_prepare_overlay_popup()
	overlay.visible = true

	# (No text: just the four colour panes; the name is only a hover tooltip.)

	# Windows-XP-logo layout: a 2x2 grid of four color panes (top row
	# green→blue, bottom row yellow→red, exactly like the old XP flag).
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	overlay_vbox.add_child(grid)

	var colors := [
		["Green", CardNode.SUIT_COLORS[Card.CardColor.GREEN]],
		["Red", CardNode.SUIT_COLORS[Card.CardColor.RED]],
		["Orange", CardNode.SUIT_COLORS[Card.CardColor.ORANGE]],
		["Purple", CardNode.SUIT_COLORS[Card.CardColor.PURPLE]],
	]
	var indices := [Card.CardColor.GREEN, Card.CardColor.RED, Card.CardColor.ORANGE, Card.CardColor.PURPLE]

	for i in range(4):
		var btn := _make_color_button("", colors[i][1], Vector2(150, 150), 18)
		btn.tooltip_text = colors[i][0]
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
	_frame_overlay_popup()

## Smoked-glass frame behind the centered popup + a quick pop-in entrance.
func _frame_overlay_popup() -> void:
	_cut_banner()
	overlay.z_index = LAYER_MODAL
	var frame := overlay.get_node_or_null("PopupFrame") as Panel
	if frame == null:
		frame = Panel.new()
		frame.name = "PopupFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", UIStyle.panel_style())
		overlay.add_child(frame)
	# Always the bottom-most child of the overlay: moving it to overlay_vbox's
	# index put it IN FRONT of the popup on the 2nd popup in a row (e.g. color →
	# player picker), hiding the buttons behind the frame.
	overlay.move_child(frame, 0)
	var pad := Vector2(28, 22)
	frame.position = overlay_vbox.position - pad
	frame.size = overlay_vbox.size + pad * 2.0
	frame.visible = true
	overlay.color = Color(UIStyle.INK, 0.62)
	for c: Control in [frame, overlay_vbox]:
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2(0.92, 0.92)
		c.modulate.a = 0.0
		var tw := create_tween().bind_node(c).set_parallel()
		tw.tween_property(c, "scale", Vector2.ONE, Juice.d(0.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, Juice.d(0.12))

func _on_color_chosen(color: int) -> void:
	overlay.visible = false
	_clear_overlay()
	_sfx(&"button")

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
			_sfx(&"card_play")
			_finalize_or_send_play()
			return
		"target":
			state = State.HUMAN_TARGET_SELECT
			_show_target_selector("Swap hands with..." if _pending_card and _pending_card.action_id == "swap_hands" else "Who draws - and loses their turn?")
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
	_wired_note_play()

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
		elif _pending_card and _pending_card.action_id == "choose_deck":
			# Your victim draws from the deck you picked (and loses their turn).
			draw_target = int(_pending_options.get("target_player_index", game._next_alive_index(own_index, game.direction)))
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
	_sfx(&"button")

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

func _show_deck_choice_selector(prompt: String = "They draw from which deck?") -> void:
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
	_sfx(&"button")

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
		elif card.action_id == "choose_deck":
			draw_target = int(options.get("target_player_index", game._next_alive_index(idx, game.direction)))
			draw_pile = options.get("chosen_pile", "A")
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
	_sfx(&"bomb_drawn")
	_dismiss_all_overlays()
	_cut_banner()
	overlay.z_index = LAYER_MODAL
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
	_sfx(&"button")

	# Remote client: send intent, wait for snapshot.
	if is_online and not is_host_here():
		send_intent({"kind": "diffuse", "use": true})
		state = State.WAITING
		_refresh_all()
		return

	game.resolve_bomb(true)
	_sfx(&"diffuse")

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
	_sfx(&"button")

	# Remote client: send intent, wait for snapshot.
	if is_online and not is_host_here():
		send_intent({"kind": "diffuse", "use": false})
		state = State.WAITING
		_refresh_all()
		return

	_start_chamber_draw()

# ── Vice emotes (smoke / whiskey) ─────────────────────────────────────

## Local player asks to smoke or drink: plays first-person here and, online,
## is relayed so every other table sees this seat's avatar do it.
## A glass is in your hand and sipping (false once you ended drinking mode mid-refill).
func _drinking_active() -> bool:
	return _drink_session != null and is_instance_valid(_drink_session) and not bool(_drink_session.call("is_walked_away"))

func _request_emote(kind: StringName) -> void:
	# S while smoking = put the cigarette away.
	if kind == &"smoke" and _smoke_session != null and is_instance_valid(_smoke_session):
		_smoke_session.finish()
		return
	# W while drinking = set the glass back down on the table.
	if kind == &"drink" and _drink_session != null and is_instance_valid(_drink_session):
		_drink_session.request_walk_away()   # mid-pour: get your cards back right away
		return
	if _drink_session != null and is_instance_valid(_drink_session):
		return   # the bartender is still finishing a pour: no second vice yet
	if _paused or _hands_busy or _own_passed_out() or _emote_cooldown > 0.0 or not (kind in EMOTE_KINDS):
		return
	if is_tutorial and not _tut_allow_vice:
		return
	if state == State.CHAMBER_REVEAL or state == State.GAME_OVER or state == State.DEALING:
		return
	if game == null or own_index >= game.players.size():
		return
	if not is_tutorial and (kind == &"smoke" or kind == &"drink") and _vice_pick[String(kind)].is_empty():
		# First time only: choose the brand (type -> brand), then the session starts.
		# Afterwards W / S reuse it; press B during the vice to change it.
		if _vice_picker != null and is_instance_valid(_vice_picker):
			return
		var on_pick := func(cat: String, brand: int) -> void:
			_vice_pick[String(kind)] = {"cat": cat, "brand": brand}
			_vice_picker = null
			_start_vice_after_pick(kind)
		var on_cancel := func() -> void: _vice_picker = null
		_vice_picker = VicePicker.open(self, "smoke" if kind == &"smoke" else "drink", on_pick, on_cancel, LAYER_PAUSE - 10)
		return
	_emote_cooldown = EMOTE_COOLDOWN
	_play_emote(own_index, kind)
	_broadcast_emote(kind)

## B during a vice: pick a different brand / type. The current cigarette or glass is
## put away and the new one comes out straight away.
func _change_vice_choice(kind: StringName) -> void:
	if _vice_picker != null and is_instance_valid(_vice_picker):
		return
	var on_pick := func(cat: String, brand: int) -> void:
		_vice_pick[String(kind)] = {"cat": cat, "brand": brand}
		_vice_picker = null
		var sess: Object = _smoke_session if kind == &"smoke" else _drink_session
		if sess != null and is_instance_valid(sess):
			_pending_vice = kind
			sess.call("finish")   # put it away; the new one starts when the hand is clear
		elif not _hands_busy:
			_start_vice_after_pick(kind)
	var on_cancel := func() -> void: _vice_picker = null
	_vice_picker = VicePicker.open(self, "smoke" if kind == &"smoke" else "drink", on_pick, on_cancel, LAYER_PAUSE - 10)

func _start_vice_after_pick(kind: StringName) -> void:
	if _paused or _hands_busy or state == State.CHAMBER_REVEAL or state == State.GAME_OVER:
		return
	_emote_cooldown = EMOTE_COOLDOWN
	_play_emote(own_index, kind)
	_broadcast_emote(kind)

func _broadcast_emote(kind: StringName) -> void:
	return   # smoking / drinking are mirrored step by step through _net_vice now
	if is_online:
		if is_host_here():
			rpc("_rpc_emote", own_index, String(kind))
		else:
			rpc_id(1, "_rpc_emote_request", String(kind))

## Plays a vice emote for a seat: first-person overlay for the local seat,
## the 3D character's clip for everyone else.
func _play_emote(seat: int, kind: StringName) -> void:
	if seat == own_index:
		_play_own_vice(kind)
		return
	_ensure_seat_props(seat, kind)
	var actor: Node3D = _char_node_by_index.get(seat, null)
	if actor != null and is_instance_valid(actor):
		actor.do_emote(kind)

## Where a seat's table items live. Derived from the SEAT and the table centre only
## (never from a camera), so every player in a multiplayer game computes the same
## spot for the same seat and sees everyone's glass / ashtray in the right place.
## kind: "glass" (right of the seat's cards) | "ashtray" (left) | "pile" (face-down cards)
func _seat_spot(seat: int, kind: String) -> Vector3:
	if _tb_built and (kind == "glass" or kind == "ashtray") and not _marker_players.is_empty():
		return TableBuilder.spot_pos(_tb_centre, _tb_radius, _tb_surface, _seat_marker_pos(seat), kind, _tb_off)
	var table_y := (_marker_discard.global_position.y if _marker_discard else _table_center.y) + 0.004
	if _marker_players.is_empty():
		return Vector3(_table_center.x, table_y, _table_center.z)
	var m: Marker3D = _marker_players[_seat_marker_idx(seat) % _marker_players.size()]
	var p := m.global_position
	var to_c := Vector3(_table_center.x - p.x, 0.0, _table_center.z - p.z)
	var r := to_c.length()
	if r < 0.01:
		return Vector3(_table_center.x, table_y, _table_center.z)
	var d := to_c / r
	var right := d.cross(Vector3.UP)
	var out := Vector3(p.x, table_y, p.z)
	match kind:
		"glass": out += d * r * SPOT_FWD + right * r * SPOT_SIDE
		"ashtray": out += d * r * SPOT_FWD - right * r * SPOT_SIDE
		_: out += d * r * (SPOT_FWD - 0.02)
	return out

## Horizontal direction from a seat toward the table centre (the way that seat faces).
func _seat_forward(seat: int) -> Vector3:
	if _marker_players.is_empty():
		return Vector3.ZERO
	var m: Marker3D = _marker_players[_seat_marker_idx(seat) % _marker_players.size()]
	var d := Vector3(_table_center.x - m.global_position.x, 0.0, _table_center.z - m.global_position.z)
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO

## ── Vice sync: what I smoke / drink, and every step of it, mirrored to everyone ──────

func _seat_marker_pos(seat: int) -> Vector3:
	if _marker_players.is_empty():
		return _table_center
	return (_marker_players[_seat_marker_idx(seat) % _marker_players.size()] as Marker3D).global_position

func _on_my_smoke_event(event: String, data: Dictionary) -> void:
	_net_vice("smoke_" + event, data)

func _on_my_drink_event(event: String, data: Dictionary) -> void:
	_net_vice("drink_" + event, data)

## Local -> everyone (through the host).
func _net_vice(event: String, data: Dictionary = {}) -> void:
	if not is_online or is_tutorial:
		return
	if is_host_here():
		rpc("_rpc_vice_play", own_index, event, data)
	else:
		rpc_id(1, "_rpc_vice", event, data)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_vice(event: String, data: Dictionary) -> void:
	if not is_online or not is_host_here() or _eos == null:
		return
	var seat: int = _eos.get_seat_for_peer(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	_play_vice_remote(seat, event, data)
	rpc("_rpc_vice_play", seat, event, data)

@rpc("authority", "call_remote", "reliable")
func _rpc_vice_play(seat: int, event: String, data: Dictionary) -> void:
	if not is_online or seat == own_index:
		return
	_play_vice_remote(seat, event, data)

## Plays another player's vice step on their character + at their seat.
func _play_vice_remote(seat: int, event: String, data: Dictionary) -> void:
	if seat == own_index or game == null or seat >= game.players.size():
		return
	var actor: Node3D = _char_node_by_index.get(seat, null)
	match event:
		"smoke_begin":
			var prod := ViceCatalog.smoke_product(str(data.get("cat", "cigarette")), int(data.get("brand", 0)))
			_seat_smoke_prod[seat] = prod
			_ensure_seat_props(seat, &"smoke")
			_clear_seat_rest(seat)
			if actor != null and is_instance_valid(actor):
				actor.call("set_smoke_style", prod)
		"smoke_light":
			Sound.play(&"lighter")
			if actor != null and is_instance_valid(actor):
				actor.call("do_emote", &"smoke")   # raises it to the lips + first drag/exhale
		"smoke_drag":
			if actor != null and is_instance_valid(actor):
				actor.call("do_emote", &"smoke")
		"smoke_end":
			_show_seat_rest(seat, float(data.get("burn", 0.0)) < 1.0)
		"drink_begin":
			var dprod := ViceCatalog.drink_product(str(data.get("cat", "whiskey")), int(data.get("brand", 0)))
			_seat_drink_prod[seat] = dprod
			_set_seat_glass(seat, dprod, 0.0)
			if actor != null and is_instance_valid(actor):
				actor.call("set_drink_style", dprod)
		"drink_pour":
			var dp: Dictionary = _seat_drink_prod.get(seat, ViceCatalog.drink_product("whiskey", 0))
			_ensure_seat_props(seat, &"drink")
			var g: Node3D = _seat_glass.get(seat, null)
			if g != null and is_instance_valid(g):
				BartenderPour.run({
					"host": self, "world": _world_root_3d if _world_root_3d else _viewport_3d, "glass": g,
					"center": _table_center, "seat_pos": _seat_marker_pos(seat), "floor_y": _room_floor_y,
					"crowd": _crowd, "drink": dp, "level_from": float(data.get("level", 0.0)),
					"table_y": _seat_spot(seat, "glass").y, "table_r": _table_radius, "rest_spot": _seat_spot(seat, "glass"),
					"level_cb": func(v: float) -> void: _set_glass_level(g, v),
				})
		"drink_sip":
			if actor != null and is_instance_valid(actor):
				actor.call("do_emote", &"drink")
			var sg: Node3D = _seat_glass.get(seat, null)
			if sg != null and is_instance_valid(sg):
				_set_glass_level(sg, float(data.get("level", 0.5)) - 0.05)
		"drink_set_down":
			var sg2: Node3D = _seat_glass.get(seat, null)
			if sg2 != null and is_instance_valid(sg2):
				_set_glass_level(sg2, float(data.get("level", 0.5)))

func _set_glass_level(g: Node3D, v: float) -> void:
	if g == null or not is_instance_valid(g) or not g.has_meta(&"liquid"):
		return
	var liq: Node3D = g.get_meta(&"liquid")
	liq.scale = Vector3(1.0, maxf(v, 0.02), 1.0)
	liq.visible = v > 0.01

## A seat's glass stands at its spot; replaced when they order a different drink.
func _set_seat_glass(seat: int, prod: Dictionary, level: float) -> void:
	if _camera_3d == null:
		return
	var old: Node3D = _seat_glass.get(seat, null)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var f: float = ViceFirstPerson._fist_scale(_camera_3d)
	var g: Node3D = preload("res://scripts/fx/glassware.gd").build(str(prod.get("glass", "tumbler")), prod.get("color", Color(0.85, 0.45, 0.08)))
	g.scale = Vector3.ONE * 1.5 * f
	(_world_root_3d if _world_root_3d else _viewport_3d).add_child(g)
	g.global_position = _seat_spot(seat, "glass")
	_set_glass_level(g, level)
	_seat_glass[seat] = g

## A cigarette resting in a seat's ashtray (lit, or a butt).
func _show_seat_rest(seat: int, lit: bool) -> void:
	_clear_seat_rest(seat)
	var tray: Node3D = _seat_ashtray.get(seat, null)
	if tray == null or not is_instance_valid(tray):
		return
	var f: float = tray.get_meta(&"f")
	var stick := Node3D.new()
	stick.name = "RestCig"
	var prod: Dictionary = _seat_smoke_prod.get(seat, {})
	var paper: Color = prod.get("wrapper", prod.get("paper", Color(0.95, 0.94, 0.9)))
	var length := (0.3 if lit else 0.08) * f
	var body := EmoteRig_cyl(0.022 * f, length, paper)
	body.rotation_degrees = Vector3(0, 0, 90)
	stick.add_child(body)
	if lit:
		var ember := EmoteRig_cyl(0.024 * f, 0.025 * f, Color(1.0, 0.4, 0.1))
		ember.rotation_degrees = Vector3(0, 0, 90)
		ember.position = Vector3(length * 0.5, 0, 0)
		stick.add_child(ember)
	tray.add_child(stick)
	stick.position = Vector3(-0.1 * f, 0.135 * f, 0.05 * f)
	stick.rotation_degrees = Vector3(0, -20, 0)

func _clear_seat_rest(seat: int) -> void:
	var tray: Node3D = _seat_ashtray.get(seat, null)
	if tray != null and is_instance_valid(tray):
		var old := tray.get_node_or_null("RestCig")
		if old:
			old.queue_free()

func EmoteRig_cyl(radius: float, height: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	cm.material = m
	mi.mesh = cm
	return mi

## Other players' vices: their glass / ashtray appears (and stays) at their seat.
func _ensure_seat_props(seat: int, kind: StringName) -> void:
	if seat == own_index or _camera_3d == null:
		return
	var f: float = ViceFirstPerson._fist_scale(_camera_3d)
	var parent: Node = _world_root_3d if _world_root_3d else _viewport_3d
	if kind == &"drink" and not _seat_glass.has(seat):
		var g: Node3D = preload("res://scripts/fx/glassware.gd").build("tumbler", Color(0.85, 0.45, 0.08))
		g.scale = Vector3.ONE * 1.5 * f
		parent.add_child(g)
		g.global_position = _seat_spot(seat, "glass")
		_seat_glass[seat] = g
	elif kind == &"smoke" and not _seat_ashtray.has(seat):
		var a: Node3D = Ashtray.build(f)
		parent.add_child(a)
		a.global_position = _seat_spot(seat, "ashtray")
		_seat_ashtray[seat] = a

## Your own vice, in order: set the cards down (the fan slides down onto the
## felt), THEN the first-person 3D emote plays, THEN you pick the cards back
## up. Card plays and deck draws are locked while your hands are busy.
## Second render pass so the hand/glass/cigarette are never clipped by the table.
func _ensure_prop_overlay() -> void:
	if _prop_overlay == null and _viewport_3d != null and _viewport_container != null:
		_prop_overlay = PropOverlay.create(self, _viewport_3d, _viewport_container)
		_prop_overlay.exclude_from(_viewport_3d.find_children("*", "Camera3D", true, false))
		if _wired_overlay != null:
			move_child(_wired_overlay, (_prop_overlay.get("rect") as Control).get_index() + 1)
	if _prop_overlay != null:
		_prop_overlay.set("main_cam", _camera_3d)

func _play_own_vice(kind: StringName, cards_already_down: bool = false) -> void:
	if _hands_busy:
		return
	_hands_busy = true
	_ensure_prop_overlay()
	if _prop_overlay != null:
		_prop_overlay.set_active(true)
	var sleeve := _own_color().darkened(0.45)
	var released := [false]   # cards already given back (walked away mid-pour)
	var pick_up_cards := func() -> void:
		_smoke_session = null
		if _pending_vice != &"" and is_inside_tree():
			# Brand changed: skip picking the cards up and bring out the new one.
			var next_kind := _pending_vice
			_pending_vice = &""
			_hands_busy = false
			_play_own_vice(next_kind, true)
			return
		if released[0]:
			return
		if _prop_overlay != null:
			_prop_overlay.set_active(false)
		if is_inside_tree():
			var pick_up := _set_cards_down(false)
			pick_up.tween_callback(func() -> void:
				_hands_busy = false
				if is_tutorial:
					tutorial_action_done.emit("vice_end", {"kind": kind}))
	var set_down: Tween
	if cards_already_down:
		set_down = create_tween()
		set_down.tween_interval(0.05)
	else:
		set_down = _set_cards_down(true)
	set_down.tween_callback(func() -> void:
		if kind == &"smoke":
			# Interactive: scroll to drag, the cigarette burns down across smokes.
			var prod: Dictionary = {}
			if not is_tutorial and not _vice_pick.smoke.is_empty():
				prod = ViceCatalog.smoke_product(str(_vice_pick.smoke.cat), int(_vice_pick.smoke.brand))
			_ensure_ashtray()
			FirstPersonSmoke.ashtray = _table_ashtray
			_net_vice("smoke_begin", {"cat": str(_vice_pick.smoke.get("cat", "cigarette")), "brand": int(_vice_pick.smoke.get("brand", 0))})
			_smoke_session = FirstPersonSmoke.start(_camera_3d, sleeve, pick_up_cards, prod, Callable(self, "_on_my_smoke_event"))
			if is_tutorial:
				tutorial_action_done.emit("vice_start", {"kind": kind})
			_show_notification("SCROLL to take a drag  ·  [%s] put it out  ·  [%s] change" % [Keybinds.label(&"smoke"), Keybinds.label(&"change_vice")], 4.5)
		else:
			# Interactive: scroll to sip; the glass lives on the table between drinks.
			var after_drink := func(glass: Node3D) -> void:
				_table_glass = glass
				_drink_session = null
				pick_up_cards.call()
			var walk_away := func() -> void:
				if released[0] or not is_inside_tree():
					return
				released[0] = true
				if _prop_overlay != null:
					_prop_overlay.set_active(false)
				var back := _set_cards_down(false)
				back.tween_callback(func() -> void:
					_hands_busy = false
					if is_tutorial:
						tutorial_action_done.emit("vice_end", {"kind": kind}))
			var dprod: Dictionary = {}
			if not is_tutorial and not _vice_pick.drink.is_empty():
				dprod = ViceCatalog.drink_product(str(_vice_pick.drink.cat), int(_vice_pick.drink.brand))
			_net_vice("drink_begin", {"cat": str(_vice_pick.drink.get("cat", "whiskey")), "brand": int(_vice_pick.drink.get("brand", 0))})
			_drink_session = FirstPersonDrink.start(_camera_3d, sleeve, _table_glass,
				_seat_spot(own_index, "glass"), after_drink, dprod, Callable(self, "_on_sip"), _char_scale, _room_floor_y, _seat_forward(own_index),
				{"net_cb": Callable(self, "_on_my_drink_event"), "crowd": _crowd, "center": _table_center, "seat_pos": _seat_marker_pos(own_index), "table_r": _table_radius, "rest_spot": _seat_spot(own_index, "glass")})
			_drink_session.set("on_walk_away", walk_away)
			if is_tutorial:
				tutorial_action_done.emit("vice_start", {"kind": kind})
			_show_notification("SCROLL to sip  ·  [%s] set it down  ·  [%s] change" % [Keybinds.label(&"drink"), Keybinds.label(&"change_vice")], 4.5))

## Heavy glass ashtray on the felt (left of your cards). Created on first smoke.
func _ensure_ashtray() -> void:
	if _table_ashtray != null and is_instance_valid(_table_ashtray):
		return
	if _camera_3d == null:
		return
	var f: float = ViceFirstPerson._fist_scale(_camera_3d)
	_table_ashtray = Ashtray.build(f)
	(_world_root_3d if _world_root_3d else _viewport_3d).add_child(_table_ashtray)
	_table_ashtray.global_position = _seat_spot(own_index, "ashtray")

# ── Mouse look ───────────────────────────────────────────────────────

## Mouse look is on when nothing needs the cursor: no popup, pause, log, picker,
## game over or Chamber, and the player has not pressed TAB to free the cursor.
func _look_active() -> bool:
	if is_tutorial or game == null or _cursor_free or _paused or _session_ended:
		return false
	if state == State.GAME_OVER or state == State.CHAMBER_REVEAL:
		return false
	if _modal_visible() or _log_panel != null or _line_scene != null:
		return false
	if _ui_cover != null:
		return false
	return true

## True when the camera may be turned by the mouse right now (vice sessions and the
## tray scene steer the camera themselves).
func _look_free_to_turn() -> bool:
	return _line_scene == null   # smoking / drinking: the head still turns freely

## Returns true when the event was consumed by mouse-look / card selection.
func _handle_look_input(event: InputEvent) -> bool:
	if not _look_active():
		return false
	# Some platforms only grant mouse capture after a click: re-assert it on every click.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion:
		# The (hidden) cursor must not hover / highlight cards, decks or buttons: only the
		# crosshair aims. Swallow the motion so the GUI never sees it.
		get_viewport().set_input_as_handled()
		if _look_free_to_turn():
			var rel := (event as InputEventMouseMotion).relative
			_look_yaw = clampf(_look_yaw - rel.x * Keybinds.sens(), -LOOK_YAW_MAX, LOOK_YAW_MAX)
			_look_pitch = clampf(_look_pitch - rel.y * Keybinds.sens(), -LOOK_PITCH_DOWN, LOOK_PITCH_UP)
		return true
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		var smoking := _smoke_session != null and is_instance_valid(_smoke_session)
		var drinking := _drinking_active()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if smoking or drinking:
				return false  # scroll belongs to the cigarette / glass
			_scroll_hand(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if not smoking and not drinking:
				_look_click()
			get_viewport().set_input_as_handled()
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_hand_sel = -1
			_apply_hand_selection()
			get_viewport().set_input_as_handled()
			return true
	return false

func _scroll_hand(dir: int) -> void:
	if card_nodes.is_empty() or _hands_busy:
		return
	if _hand_sel < 0:
		_hand_sel = 0 if dir > 0 else card_nodes.size() - 1
	else:
		_hand_sel = posmod(_hand_sel + dir, card_nodes.size())  # keeps cycling, no end stops
	_apply_hand_selection()
	_sfx(&"hover")

func _apply_hand_selection() -> void:
	if _hand_sel >= card_nodes.size():
		_hand_sel = card_nodes.size() - 1
	for i in range(card_nodes.size()):
		var cn: CardNode = card_nodes[i]
		if is_instance_valid(cn):
			cn.set_selected(i == _hand_sel)

## Left click: play the scroll-selected card, otherwise draw from the deck under
## the crosshair.
func _look_click() -> void:
	if _hand_sel >= 0 and _hand_sel < card_nodes.size():
		var idx := _hand_sel
		_hand_sel = -1
		_play_by_hand_index(idx)
		return
	var pile := _look_deck_target()
	if pile != "":
		_on_deck_clicked(pile)

## Which deck (if any) sits under the centre crosshair.
func _look_deck_target() -> String:
	if _camera_3d == null:
		return ""
	var centre := size * 0.5
	var cam_pt := centre / _view_scale()
	var from := _camera_3d.project_ray_origin(cam_pt)
	var dir := _camera_3d.project_ray_normal(cam_pt)
	var best := ""
	var best_d := INF
	# 1) The crosshair ray actually passes through a pile's box: nearest one wins.
	for id in ["A", "B"]:
		var bb := _pile_hit_aabb(id)
		if bb.size == Vector3.ZERO:
			continue
		var hit: Variant = bb.intersects_ray(from, dir)
		if hit != null:
			var d := from.distance_to(hit as Vector3)
			if d < best_d:
				best_d = d
				best = id
	if best != "":
		return best
	# 2) Close enough: the crosshair is within a generous slack of a pile's click zone.
	best_d = INF
	for id in ["A", "B"]:
		var r := _pile_screen_rect(id)
		if r.size.x <= 0.0:
			continue
		var slacked := r.grow(28.0)
		if slacked.has_point(centre):
			var d := r.get_center().distance_to(centre)
			if d < best_d:
				best_d = d
				best = id
	return best

## Cursor hidden + captured while looking around, visible whenever UI needs it
## (also while paused, so it runs even when the rest of _process is frozen).
func _sync_mouse_mode() -> void:
	var want := Input.MOUSE_MODE_CAPTURED if _look_active() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want

func _update_mouse_look(delta: float) -> void:
	var active := _look_active()
	if active and not _look_hint_shown and state != State.DEALING:
		_look_hint_shown = true
		_show_notification("Mouse look  ·  SCROLL picks a card  ·  CLICK plays / draws  ·  %s frees the cursor" % Keybinds.label(&"free_cursor"), 6.0)
	# Crosshair.
	if _crosshair == null:
		_crosshair = Panel.new()
		_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.z_index = LAYER_HUD + 6
		_crosshair.set_anchors_preset(Control.PRESET_CENTER)
		_crosshair.offset_left = -4
		_crosshair.offset_right = 4
		_crosshair.offset_top = -4
		_crosshair.offset_bottom = 4
		add_child(_crosshair)
	var over := _look_deck_target() if active else ""
	_crosshair.visible = active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(UIStyle.BRASS_LIGHT, 0.9) if over != "" else Color(1, 1, 1, 0.55)
	cs.set_corner_radius_all(4)
	_crosshair.add_theme_stylebox_override("panel", cs)
	_crosshair.scale = Vector2.ONE * (1.8 if over != "" else 1.0)
	_crosshair.pivot_offset = Vector2(4, 4)

	# Apply the look to the camera (head).
	if _camera_3d != _look_base_cam:
		_look_base_cam = _camera_3d
		if _camera_3d:
			_look_base = _camera_3d.rotation
			_look_base_fov = _camera_3d.fov
		_look_yaw = 0.0
		_look_pitch = 0.0
	if _camera_3d and active and _look_free_to_turn():
		# The vice sessions add their own head tilt (drag / sip) on top of the look.
		var sess: Object = null
		if _smoke_session != null and is_instance_valid(_smoke_session):
			sess = _smoke_session
		elif _drink_session != null and is_instance_valid(_drink_session):
			sess = _drink_session
		var tilt := float(sess.get("_tilt")) if sess != null else 0.0
		var rest_x := _look_base.x + deg_to_rad(_look_pitch)
		_camera_3d.rotation.x = rest_x + deg_to_rad(tilt)
		_camera_3d.rotation.y = _look_base.y + deg_to_rad(_look_yaw)
		if _camera_3d.has_meta(&"vice_rest_pitch"):
			_camera_3d.set_meta(&"vice_rest_pitch", rest_x)
	# Selection follows hand changes.
	if _hand_sel >= card_nodes.size():
		_hand_sel = card_nodes.size() - 1
		_apply_hand_selection()

	# Share the head direction so everyone sees this player's character look.
	_look_sync_t += delta
	if is_online and _look_sync_t >= LOOK_SEND_INTERVAL:
		_look_sync_t = 0.0
		var cur := Vector2(_look_yaw, _look_pitch)
		# Other players see your character's head dip for the tray, drags and sips too.
		if _line_scene != null and is_instance_valid(_line_scene) and bool(_line_scene.get("_snorting")):
			cur.y = -32.0
		elif _smoke_session != null and is_instance_valid(_smoke_session):
			cur.y += float(_smoke_session.get("_tilt"))
		elif _drink_session != null and is_instance_valid(_drink_session):
			cur.y += float(_drink_session.get("_tilt"))
		if cur.distance_to(_look_sent) > 0.6:
			_look_sent = cur
			if is_host_here():
				rpc("_rpc_look_state", own_index, cur.x, cur.y)
			else:
				rpc_id(1, "_rpc_look", cur.x, cur.y)

## Client -> host: my head direction.
@rpc("any_peer", "call_remote", "unreliable")
func _rpc_look(yaw: float, pitch: float) -> void:
	if not is_online or not is_host_here() or _eos == null:
		return
	var seat: int = _eos.get_seat_for_peer(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	yaw = clampf(yaw, -90.0, 90.0)
	pitch = clampf(pitch, -60.0, 60.0)
	_apply_remote_look(seat, yaw, pitch)
	rpc("_rpc_look_state", seat, yaw, pitch)

## Host -> everyone: seat's head direction.
@rpc("authority", "call_remote", "unreliable")
func _rpc_look_state(seat: int, yaw: float, pitch: float) -> void:
	if not is_online or seat == own_index:
		return
	_apply_remote_look(seat, yaw, pitch)

func _apply_remote_look(seat: int, yaw: float, pitch: float) -> void:
	var actor: Node3D = _char_node_by_index.get(seat, null)
	if actor != null and is_instance_valid(actor):
		actor.call("set_look", yaw, pitch)

# ── Secret: the waiter's tray ([C]) ───────────────────────────────────

func _request_line() -> void:
	if _line_scene != null and is_instance_valid(_line_scene):
		_line_scene.cancel()  # C again = walk away
		return
	if is_tutorial or _paused or _hands_busy or _own_passed_out() or _session_ended:
		return
	if state == State.DEALING or state == State.CHAMBER_REVEAL or state == State.GAME_OVER or state == State.SPECTATING:
		return
	if _wired_active:
		_show_notification("You're already flying.", 1.5)
		return
	if _line_cooldown > 0.0:
		_show_notification("The waiter is on his break.", 1.5)
		return
	_hands_busy = true
	_show_ui_cover(true)
	var set_down := _set_cards_down(true)
	set_down.tween_callback(func() -> void:
		_line_scene = FirstPersonLine.start(_world_root_3d if _world_root_3d else _viewport_3d, _camera_3d,
			_room_floor_y, Callable(self, "_start_wired"), Callable(self, "_on_line_done"), _own_color().darkened(0.45), _seat_forward(own_index)))

func _on_line_done() -> void:
	_line_scene = null
	_show_ui_cover(false)
	if not is_inside_tree():
		return
	var pick_up := _set_cards_down(false)
	pick_up.tween_callback(func() -> void: _hands_busy = false)

## Shared full-screen overlay (below the UI) used by both the wired high and the
## drunk blur. Created on first use.
func _ensure_fx_overlay() -> void:
	if _wired_overlay != null:
		return
	_wired_mat = ShaderMaterial.new()
	_wired_mat.shader = preload("res://shaders/wired.gdshader")
	_wired_overlay = ColorRect.new()
	_wired_overlay.name = "WiredOverlay"
	_wired_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wired_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wired_overlay.material = _wired_mat
	_wired_overlay.visible = false
	add_child(_wired_overlay)
	if _viewport_container:
		var above := _viewport_container.get_index()
		if _prop_overlay != null and _prop_overlay.get("rect") != null:
			above = maxi(above, (_prop_overlay.get("rect") as Control).get_index())
		move_child(_wired_overlay, above + 1)

func _start_wired() -> void:
	_wired_active = true
	_wired_plays_left = WIRED_PLAYS
	_wired_ending = 0.0
	_wired_t = 0.0
	_line_cooldown = 0.0
	if _camera_3d:
		_wired_base_fov = _camera_3d.fov
	_ensure_fx_overlay()
	_wired_overlay.visible = true
	Sound.play_loop(&"heartbeat", 3.0)
	_show_notification("Everything is very, very clear.", 3.0)

## Every card the wired player plays wears the high down; it lasts WIRED_PLAYS plays.
func _wired_note_play() -> void:
	if not _wired_active or _wired_ending > 0.0:
		return
	_wired_plays_left -= 1
	if _wired_plays_left == 5:
		_show_notification("It's starting to wear off...", 2.5)
	elif _wired_plays_left == 2:
		_show_notification("You can feel the crash coming.", 2.5)
	if _wired_plays_left <= 0:
		_wired_ending = 6.0  # the comedown fades out over a few seconds

## Ends the line's high right now (key or pause menu): a short comedown instead of 15 plays.
func _kill_high() -> void:
	if _line_scene != null and is_instance_valid(_line_scene):
		_line_scene.cancel()
		return
	if not _wired_active or _wired_ending > 0.0:
		_show_notification("You're not high.", 1.5)
		return
	_wired_ending = KILL_HIGH_FADE
	Sound.stop_loop(&"heartbeat", 1.0)
	_show_notification("You shake it off. The room settles.", 2.5)

func _own_passed_out() -> bool:
	return game != null and own_index >= 0 and own_index < game.players.size() and game.players[own_index].passed_out

var _was_passed_out := false
var _pass_out_retry := 0.0
var _pass_out_cover: ColorRect = null

## Drinking too much knocks you out; the host rules (game_state.pass_out) decide when it sticks.
func _update_pass_out(delta: float) -> void:
	if game == null or is_tutorial or own_index < 0 or own_index >= game.players.size():
		return
	var out := _own_passed_out()
	if out and not _was_passed_out:
		_on_local_pass_out()
	elif not out and _was_passed_out:
		_on_local_wake()
	_was_passed_out = out
	if out:
		_resolve_sleeping_forced_draw()
		return
	if _drunk < PASS_OUT_AT or _paused or state == State.DEALING or state == State.CHAMBER_REVEAL \
			or state == State.GAME_OVER or state == State.SPECTATING:
		return
	_pass_out_retry -= delta
	if _pass_out_retry > 0.0:
		return
	_pass_out_retry = 1.0   # refused right now (bomb / forced draw / jump-in open)? try again soon
	if is_online and not is_host_here():
		send_intent({"kind": "pass_out"})
	elif game.pass_out(own_index):
		if is_online:
			_drew_marker = -1
			_broadcast_snapshot()
		_check_turn()

func _on_local_pass_out() -> void:
	_force_end_vice()
	_hide_end_turn_btn()
	_hide_jump_prompt()
	if _wired_active:
		_wired_ending = 0.1   # blacking out ends any high
	_sfx(&"banner")
	_show_notification("You've had too much... everything goes dark.", 3.0)
	if _pass_out_cover == null:
		_pass_out_cover = ColorRect.new()
		_pass_out_cover.color = Color(0, 0, 0, 1)
		_pass_out_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pass_out_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pass_out_cover.z_index = LAYER_MODAL
		var l := UIStyle.make_label("💤  PASSED OUT\nYou'll sleep through your next turn", 26, UIStyle.CREAM, true)
		l.set_anchors_preset(Control.PRESET_CENTER)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.grow_vertical = Control.GROW_DIRECTION_BOTH
		_pass_out_cover.add_child(l)
		add_child(_pass_out_cover)
	_pass_out_cover.modulate.a = 0.0
	create_tween().bind_node(_pass_out_cover).tween_property(_pass_out_cover, "modulate:a", 0.94, 1.2)

func _on_local_wake() -> void:
	_drunk = WAKE_DRUNK   # still slightly drunk
	_show_notification("You come to, head pounding... +%d cards, and the room still spins." % game.PASS_OUT_PENALTY, 4.0)
	_refresh_all()
	if _pass_out_cover != null:
		var cover := _pass_out_cover
		_pass_out_cover = null
		var tw := create_tween().bind_node(cover)
		tw.tween_property(cover, "modulate:a", 0.0, 1.6)
		tw.tween_callback(cover.queue_free)

## A sleeper who becomes the forced-draw target can't choose: a random deck is picked for them.
func _resolve_sleeping_forced_draw() -> void:
	if game.current_index != own_index or game.pending_forced_draw_count <= 0 or game.pending_forced_draw_player_index != own_index:
		return
	var pile := "A" if randi() % 2 == 0 else "B"
	if is_online and not is_host_here():
		send_intent({"kind": "forced_draw", "pile": pile})
	else:
		game.resolve_forced_draw(pile)
		if is_online:
			_broadcast_snapshot()
		_check_turn()

## 0..1 strength of the high: full until 5 plays are left, then it tapers.
func _wired_strength() -> float:
	if not _wired_active or _wired_ending > 0.0:
		return 0.0
	var ramp := clampf(_wired_t / 1.5, 0.0, 1.0)
	var by_plays := 1.0
	if _wired_plays_left <= 5:
		by_plays = clampf(0.4 + 0.6 * float(_wired_plays_left - 2) / 3.0, 0.4, 1.0)
	return ramp * by_plays

func _wired_crash_amount() -> float:
	if not _wired_active:
		return 0.0
	if _wired_ending > 0.0:
		return 0.85 * clampf(_wired_ending / 6.0, 0.0, 1.0)
	if _wired_plays_left <= 3:
		return lerpf(0.15, 0.6, float(3 - _wired_plays_left) / 3.0)
	return 0.0

## Wired players feel the clock: the turn timer runs faster while it lasts.
func _wired_timer_mult() -> float:
	return 1.0 + 0.4 * _wired_strength()

## Called for every sip of a drink: alcohol slowly builds up.
func _on_sip(amount: float) -> void:
	var before := _drunk
	_drunk = minf(_drunk + amount * DRUNK_PER_UNIT, 1.0)
	_ensure_fx_overlay()
	_wired_overlay.visible = true
	for step in DRUNK_STEPS:
		if before < float(step.at) and _drunk >= float(step.at):
			_show_notification(str(step.msg), 2.5)

func _update_wired(delta: float) -> void:
	if _line_cooldown > 0.0 and not _wired_active:
		_line_cooldown -= delta
	_state_t += delta
	if _drunk > 0.0:
		_drunk = maxf(_drunk - DRUNK_DECAY * delta, 0.0)
	if _wired_active:
		_wired_t += delta
		if _wired_ending > 0.0:
			_wired_ending -= delta
			if _wired_ending <= 0.0:
				_end_wired()
	var k := _wired_strength()
	var crash := _wired_crash_amount()
	var fx_on := _wired_active or _drunk > 0.005
	if _wired_mat:
		_wired_mat.set_shader_parameter("intensity", k)
		_wired_mat.set_shader_parameter("crash", crash)
		_wired_mat.set_shader_parameter("drunk", _drunk)
		_wired_mat.set_shader_parameter("t", _state_t)
	if _cover_mat:
		_cover_mat.set_shader_parameter("intensity", k)
		_cover_mat.set_shader_parameter("crash", crash)
		_cover_mat.set_shader_parameter("drunk", _drunk)
		_cover_mat.set_shader_parameter("t", _state_t)
	if _wired_overlay:
		_wired_overlay.visible = fx_on
	var scene_running := _line_scene != null and is_instance_valid(_line_scene)
	if _camera_3d and not scene_running and _vice_camera_free():
		var fov := _wired_base_fov if _wired_base_fov > 0.0 else _camera_3d.fov
		if _wired_active and _wired_base_fov > 0.0:
			_camera_3d.fov = fov + (sin(_state_t * 9.0) * 1.2 + sin(_state_t * 3.1)) * k
		# Drunk: the whole view slowly rolls.
		_camera_3d.rotation.z = sin(_state_t * 0.55) * deg_to_rad(3.2) * _drunk + sin(_state_t * 1.3) * deg_to_rad(0.8) * _drunk
	if _player_ui and not _hands_busy:
		_player_ui.position.x = sin(_state_t * 27.0) * 2.5 * k + sin(_state_t * 1.1) * 9.0 * _drunk
	_wired_shake_t -= delta
	if _wired_shake_t <= 0.0 and k > 0.2 and _shaker:
		_wired_shake_t = 0.35
		_shaker.add_trauma(0.05 * k)

## True when nothing else is steering the camera (first-person vices pitch it).
func _vice_camera_free() -> bool:
	return not (_smoke_session != null and is_instance_valid(_smoke_session)) and not (_drink_session != null and is_instance_valid(_drink_session))

func _end_wired() -> void:
	_wired_active = false
	_wired_plays_left = 0
	_wired_ending = 0.0
	_line_cooldown = WIRED_COOLDOWN
	if _camera_3d and _wired_base_fov > 0.0:
		_camera_3d.fov = _wired_base_fov
	if _player_ui and _drunk <= 0.005:
		_player_ui.position.x = 0.0
	Sound.stop_loop(&"heartbeat", 1.0)
	_show_notification("...and down we go.", 2.5)

## Full-screen cover that shows ONLY the 3D view (drawn above every UI element),
## used while the waiter's tray scene plays.
func _show_ui_cover(on: bool) -> void:
	if not on:
		if _ui_cover != null:
			_ui_cover.queue_free()
		_ui_cover = null
		_cover_mat = null
		return
	if _ui_cover != null or _viewport_3d == null:
		return
	_cover_mat = ShaderMaterial.new()
	_cover_mat.shader = preload("res://shaders/wired.gdshader")
	_cover_mat.set_shader_parameter("use_own_texture", true)
	var tr := TextureRect.new()
	tr.name = "UICover"
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = _viewport_3d.get_texture()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.material = _cover_mat
	tr.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	add_child(tr)
	_ui_cover = tr
	var hint := UIStyle.make_label("SCROLL to run the straw along the line  ·  [C] to walk away", 16, Color(1, 1, 1, 0.7), true)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -300
	hint.offset_right = 300
	hint.offset_top = -46
	hint.offset_bottom = -16
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(hint)
	var fade := create_tween().bind_node(hint)
	fade.tween_interval(6.0)
	fade.tween_property(hint, "modulate:a", 0.0, 1.0)

## Ends any first-person vice immediately (Chamber / game over take the stage).
func _force_end_vice() -> void:
	if _vice_picker != null and is_instance_valid(_vice_picker):
		_vice_picker.queue_free()
	_vice_picker = null
	if _line_scene != null and is_instance_valid(_line_scene):
		_line_scene.abort()
	_line_scene = null
	if _smoke_session != null and is_instance_valid(_smoke_session):
		_smoke_session.abort()
	_smoke_session = null
	if _drink_session != null and is_instance_valid(_drink_session):
		_drink_session.abort()
	_drink_session = null
	if _player_ui:
		_player_ui.position.y = 0.0
		_player_ui.modulate.a = 1.0
	for cn in card_nodes:
		cn.update_face(true)
		cn.scale = Vector2.ONE
	if _set_down_pile and is_instance_valid(_set_down_pile):
		_set_down_pile.queue_free()
	_set_down_pile = null
	_hands_busy = false

## Scroll wheel / trackpad scroll = pulls on the cigarette while smoking.
func _input(event: InputEvent) -> void:
	if _handle_look_input(event):
		return
	if _paused:
		return
	var smoking := _smoke_session != null and is_instance_valid(_smoke_session)
	var drinking := _drinking_active()
	var lining := _line_scene != null and is_instance_valid(_line_scene)
	if not smoking and not drinking and not lining:
		return
	var ticks := 0
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ticks = 1
	elif event is InputEventPanGesture:
		_pan_accum += absf((event as InputEventPanGesture).delta.y)
		while _pan_accum >= 1.0:
			_pan_accum -= 1.0
			ticks += 1
	if ticks == 0:
		return
	for _i in ticks:
		if lining:
			_line_scene.advance(1)
		elif smoking:
			_smoke_session.inhale()
		else:
			_drink_session.sip()
	get_viewport().set_input_as_handled()

## Sets the hand down FACE-DOWN on the felt (down=true) or picks it back up.
## Down: the fan flips to card backs, drops out of view, and a face-down stack
## lands on the 3D table in front of your seat. Up: the stack lifts away, the
## fan rises back and flips face-up. Returns a tween to sequence after.
func _set_cards_down(down: bool) -> Tween:
	var tw := create_tween()
	if _player_ui == null:
		tw.tween_interval(0.01)
		return tw
	var drop := HANDCARD_H * 1.35
	if down:
		for i in range(card_nodes.size()):
			var cn: CardNode = card_nodes[i]
			var ft := create_tween().bind_node(cn)
			ft.tween_interval(0.025 * i)
			ft.tween_callback(func() -> void: Juice.flip_card(cn, false, 0.16))
		tw.tween_interval(0.22 + 0.025 * card_nodes.size())
		tw.tween_callback(func() -> void: _sfx(&"card_slide"))
		tw.tween_property(_player_ui, "position:y", drop, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_player_ui, "modulate:a", 0.0, 0.26)
		tw.tween_callback(_spawn_set_down_pile)
		tw.tween_interval(0.22)
	else:
		_lift_set_down_pile()
		tw.tween_interval(0.12)
		tw.tween_callback(func() -> void: _sfx(&"card_slide"))
		tw.tween_property(_player_ui, "position:y", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_player_ui, "modulate:a", 1.0, 0.2)
		tw.tween_callback(func() -> void:
			for i in range(card_nodes.size()):
				var cn: CardNode = card_nodes[i]
				var ft := create_tween().bind_node(cn)
				ft.tween_interval(0.03 * i)
				ft.tween_callback(func() -> void: Juice.flip_card(cn, true, 0.18)))
		tw.tween_interval(0.25 + 0.03 * card_nodes.size())
	return tw

## World point on the felt just in front of the local seat (rest view, bottom-centre).
func _felt_point_in_front() -> Vector3:
	return _seat_spot(own_index, "pile")

## A small face-down stack (real card backs) drops onto the felt.
func _spawn_set_down_pile() -> void:
	if _set_down_pile and is_instance_valid(_set_down_pile):
		_set_down_pile.queue_free()
	if _viewport_3d == null or _back_vp == null:
		return
	var pile := Node3D.new()
	pile.name = "SetDownHand"
	_viewport_3d.add_child(pile)
	pile.global_position = _felt_point_in_front()
	# Face the stack toward the player (its long side along the view).
	if _camera_3d:
		var to_cam := _camera_3d.global_position - pile.global_position
		pile.rotation.y = atan2(to_cam.x, to_cam.z)
	var n := clampi(card_nodes.size(), 1, 6)
	for i in range(n):
		var s := Sprite3D.new()
		s.texture = _back_vp.get_texture()
		s.pixel_size = _card_w3d * 0.72 / 256.0
		s.shaded = false
		s.modulate = Color(0.82, 0.8, 0.78)
		s.rotation_degrees = Vector3(-90.0, randf_range(-9.0, 9.0), 0.0)
		s.position = Vector3(randf_range(-0.01, 0.01), 0.0015 * i, randf_range(-0.01, 0.01))
		pile.add_child(s)
	# Drop in from a little above with a settle.
	var base_y := pile.position.y
	pile.position.y = base_y + _card_w3d * 0.6
	var tw := create_tween().bind_node(pile)
	tw.tween_property(pile, "position:y", base_y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _sfx(&"card_play", -4.0))
	_set_down_pile = pile

func _lift_set_down_pile() -> void:
	var pile := _set_down_pile
	_set_down_pile = null
	if pile == null or not is_instance_valid(pile):
		return
	var tw := create_tween().bind_node(pile)
	tw.tween_property(pile, "position:y", pile.position.y + _card_w3d * 0.8, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pile, "scale", Vector3.ONE * 0.6, 0.18)
	tw.tween_callback(pile.queue_free)

## Offline AIs light up or pour a drink now and then while waiting.
func _process_ai_vices(delta: float) -> void:
	if is_online or is_tutorial or game == null or game.game_over:
		return
	if state == State.DEALING or state == State.CHAMBER_REVEAL:
		return
	for i in range(game.players.size()):
		if i == own_index or game.players[i].eliminated:
			continue
		var t: float = _ai_emote_timers.get(i, randf_range(6.0, 18.0))
		t -= delta
		if t <= 0.0:
			t = randf_range(14.0, 34.0)
			if i != game.current_index:
				_play_emote(i, EMOTE_KINDS[randi() % EMOTE_KINDS.size()])
		_ai_emote_timers[i] = t

## Client → host: "my seat wants to emote". Host plays it and fans it out.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_emote_request(kind: String) -> void:
	if not is_online or not is_host_here() or _eos == null:
		return
	var seat: int = _eos.get_seat_for_peer(multiplayer.get_remote_sender_id())
	if seat < 0 or not (StringName(kind) in EMOTE_KINDS):
		return
	_play_emote(seat, StringName(kind))
	rpc("_rpc_emote", seat, kind)

## Host → clients: seat `seat` is smoking / drinking.
@rpc("authority", "call_remote", "reliable")
func _rpc_emote(seat: int, kind: String) -> void:
	if seat == own_index or not (StringName(kind) in EMOTE_KINDS):
		return  # our own emote already played locally
	_play_emote(seat, StringName(kind))

# ── Chamber Draw Sequence ─────────────────────────────────────────────
# The chamber is a 3D revolver duel (scripts/fx/revolver_duel.gd): a random living
# player OTHER than the bomb drawer points a revolver at the drawer, spins the
# drum, cocks the hammer and pulls the trigger. The 2D layer only carries the
# title, one status line and the verdict.

const RevolverDuel := preload("res://scripts/fx/revolver_duel.gd")
var _chamber_cam_fov: float = -1.0
var _duel: Node3D = null
var _duel_seat: int = -1          ## victim seat while a duel runs (its avatar stays on the table)
var _duel_shooter: int = -1
var _last_chamber_click_ms: int = 0

## Seat facing the chamber right now (bomb holder), for camera / reactions.
func _chamber_victim() -> int:
	if game and game.pending_diffuse_player_index >= 0:
		return game.pending_diffuse_player_index
	return game.current_index if game else own_index

## A random living player other than the bomb drawer holds the revolver.
func _pick_shooter(victim: int) -> int:
	var pool: Array[int] = []
	for i in range(game.players.size()):
		if i != victim and not game.players[i].eliminated:
			pool.append(i)
	if pool.is_empty():
		return victim
	return pool[randi() % pool.size()]

## The seat's avatar if it is on the table (null for the local seat / empty seats).
func _live_actor(seat: int) -> Node3D:
	if seat == own_index:
		return null
	var actor: Node3D = _char_node_by_index.get(seat, null)
	if actor == null or not is_instance_valid(actor) or actor.dead:
		return null
	return actor

func _duel_line(victim: int, shooter: int) -> String:
	var v: String = "you" if victim == own_index else game.players[victim].display_name
	if shooter == victim:
		return "%s holds the revolver to their own head..." % ("You" if victim == own_index else v)
	if shooter == own_index:
		return "You point the revolver at %s..." % v
	var s: String = game.players[shooter].display_name
	return "%s points the revolver at %s..." % [s, v]

func _begin_duel(victim: int, shooter: int) -> void:
	_end_duel()
	_duel_seat = victim
	_duel_shooter = shooter
	if _camera_3d == null or _viewport_3d == null or shooter < 0 or shooter >= game.players.size():
		return
	_duel = RevolverDuel.new()
	_duel.name = "RevolverDuel"
	_viewport_3d.add_child(_duel)
	_duel.font = UIStyle.body_font()
	_duel.setup(_camera_3d, _live_actor(shooter), _live_actor(victim), _char_scale, game.players[shooter].color)
	_duel.chamber_click.connect(_on_chamber_passed)
	_duel.sfx.connect(_on_duel_sfx)
	_duel.shake.connect(_on_duel_shake)
	_duel.screen_flash.connect(_on_duel_flash)
	_duel.victim_hit.connect(_on_duel_victim_hit.bind(victim))

func _end_duel() -> void:
	if _duel and is_instance_valid(_duel):
		_duel.queue_free()
	_duel = null
	Engine.time_scale = 1.0

func _on_duel_sfx(event: StringName) -> void:
	_sfx(event)

func _on_duel_shake(amount: float) -> void:
	if _shaker:
		_shaker.add_trauma(amount)

func _on_duel_flash(col: Color, dur: float) -> void:
	Juice.flash(self, col, dur)

## The bullet landed: the victim drops (avatar) or the screen goes red (local).
func _on_duel_victim_hit(victim: int) -> void:
	_character_react(victim, &"die")
	if victim == own_index:
		Juice.flash(self, Color(0.55, 0.0, 0.02, 0.75), 1.1)
		Juice.flash(self, Color(0.0, 0.0, 0.0, 0.55), 1.6)
		if _shaker:
			_shaker.add_trauma(1.0)

## Builds the chamber overlay: a vignette that keeps the table visible, the
## title + status line up top, the verdict line at the bottom, and starts the
## 3D duel. Music ducks, a heartbeat starts, the camera slowly pushes in.
func _build_chamber_ui(victim: int, shooter: int) -> void:
	_force_end_vice()
	_clear_stage()
	if notification_label:
		notification_label.visible = false
	if _player_ui:
		create_tween().bind_node(_player_ui).tween_property(_player_ui, "modulate:a", 0.0, 0.3)
	var chamber_bg := ColorRect.new()
	chamber_bg.name = "ChamberBG"
	chamber_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	chamber_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/vignette.gdshader")
	chamber_bg.material = mat
	chamber_bg.modulate.a = 0.0
	add_child(chamber_bg)
	create_tween().bind_node(chamber_bg).tween_property(chamber_bg, "modulate:a", 1.0, 0.35)

	var chamber_center := MarginContainer.new()
	chamber_center.name = "ChamberCenter"
	chamber_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	chamber_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chamber_center.add_theme_constant_override("margin_top", 58)
	chamber_center.add_theme_constant_override("margin_bottom", 46)
	add_child(chamber_center)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	chamber_center.add_child(vbox)

	var title := UIStyle.make_label("THE CHAMBER", 46, UIStyle.BLOOD_LIGHT, true)
	title.name = "ChamberTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	vbox.add_child(title)

	var sub := UIStyle.make_label(_duel_line(victim, shooter), 20, UIStyle.CREAM)
	sub.name = "ChamberWho"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var tension := UIStyle.make_label("", 22, UIStyle.BRASS_LIGHT)
	tension.name = "ChamberTension"
	tension.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tension)

	vbox.modulate.a = 0.0
	var tw := create_tween().bind_node(vbox)
	tw.tween_property(vbox, "modulate:a", 1.0, 0.3)
	Juice.punch(title, 0.15, 0.5)

	Sound.duck(-16.0, 0.5)
	Sound.play_loop(&"heartbeat")
	_begin_duel(victim, shooter)
	if _camera_3d and is_instance_valid(_camera_3d):
		_chamber_cam_fov = _camera_3d.fov
		create_tween().bind_node(_camera_3d).tween_property(_camera_3d, "fov", _chamber_cam_fov * 0.84, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_chamber_heartbeat_pulse()

## Drum clicks are throttled — the ratchet SFX already carries the spin.
func _on_chamber_passed(_index: int = 0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_chamber_click_ms < 140:
		return
	_last_chamber_click_ms = now
	_sfx(&"cylinder_click", -10.0)

## Rim of the vignette throbs red in time with the heartbeat.
func _chamber_heartbeat_pulse() -> void:
	var bg := get_node_or_null("ChamberBG") as ColorRect
	if bg == null:
		return
	var mat := bg.material as ShaderMaterial
	var setter := func(v: float) -> void: mat.set_shader_parameter("pulse", v)
	var tw := create_tween().bind_node(bg).set_loops()
	tw.tween_method(setter, 0.0, 0.3, 0.12)
	tw.tween_method(setter, 0.3, 0.05, 0.18)
	tw.tween_method(setter, 0.05, 0.2, 0.1)
	tw.tween_method(setter, 0.2, 0.0, 0.45)

## Gun comes up → drum spins → hammer cocks (shared by the local draw and the
## short online replay). `spin_revs`/`spin_dur` scale the spin.
func _duel_build_up(victim: int, spin_revs: int, spin_dur: float) -> void:
	var tension := get_node_or_null("ChamberCenter/VBoxContainer/ChamberTension") as Label
	if _duel:
		await _duel.intro()
	else:
		await get_tree().create_timer(0.6).timeout
	_character_react(victim, &"fear")
	if tension:
		tension.text = "Spinning the cylinder..."
	_sfx(&"cylinder_spin")
	if _duel:
		await _duel.spin(spin_revs, spin_dur)
	else:
		await get_tree().create_timer(spin_dur).timeout
	# Hammer back, then a beat of silence.
	if tension:
		tension.text = "..."
	Sound.stop_loop(&"heartbeat", 0.15)
	if _duel:
		await _duel.cock()
	else:
		_sfx(&"hammer_cock")
	await get_tree().create_timer(0.7).timeout

func _start_chamber_draw() -> void:
	if get_node_or_null("ChamberBG"):
		return
	state = State.CHAMBER_REVEAL
	_hide_timer_ui()
	var victim := _chamber_victim()
	var shooter := _pick_shooter(victim)
	_build_chamber_ui(victim, shooter)
	_sfx(&"chamber_start")
	await _duel_build_up(victim, 4, 2.2)

	# Resolve the draw. Offline and online-host run the authority; online
	# clients never reach here (they get chamber_reveal packed in snapshots).
	var result: int
	if is_host_here():
		result = game.chamber.draw()
		_pending_chamber_reveal = {"seat": game.pending_diffuse_player_index, "result": int(result), "shooter": shooter}
		game.resolve_bomb_with_result(result)
		game.sync_respawn_cards()
		if is_online:
			_broadcast_snapshot()
	else:
		# Offline solo acting locally.
		result = game.chamber.draw()

	_play_chamber_reveal(result, victim, shooter)

## Plays the trigger pull + verdict for `result`. `victim`/`shooter` come from the
## caller (the host's snapshot on clients); a duel already built by
## _start_chamber_draw is reused.
func _play_chamber_reveal(result: int, victim: int = -1, shooter: int = -1) -> void:
	if victim < 0:
		victim = _chamber_victim()
	# Online clients (and a host watching a remote seat) jump straight here:
	# build the overlay + duel and give the drum a short spin so it still lands.
	if get_node_or_null("ChamberBG") == null:
		if shooter < 0 or shooter >= game.players.size():
			shooter = _pick_shooter(victim)
		state = State.CHAMBER_REVEAL
		_hide_timer_ui()
		_build_chamber_ui(victim, shooter)
		await _duel_build_up(victim, 2, 1.2)
	else:
		shooter = _duel_shooter

	var tension := get_node_or_null("ChamberCenter/VBoxContainer/ChamberTension") as Label
	var text := ""
	var col := UIStyle.CREAM
	var line := ""
	var kind: StringName = &"live"
	match result:
		ChamberDeck.Result.LIVE:
			text = "LIVE"
			col = UIStyle.BLOOD_LIGHT
			line = "The chamber was loaded."
			kind = &"live"
		ChamberDeck.Result.BLANK:
			text = "BLANK"
			col = Color(0.8, 0.78, 0.74)
			line = "Click. Empty chamber."
			kind = &"blank"
		ChamberDeck.Result.BACKFIRE:
			text = "BACKFIRE"
			col = Color(1.0, 0.62, 0.2)
			line = "The gun blew up in the shooter's hand!"
			kind = &"backfire"
		ChamberDeck.Result.LUCKY_DRAW:
			text = "LUCKY DRAW"
			col = UIStyle.BRASS_LIGHT
			line = "Fortune smiles on the brave."
			kind = &"lucky"

	# The shot itself (muzzle flash, bullet-time tracer, recoil, sparks...) is 3D.
	if _duel:
		await _duel.fire(kind)
	else:
		_sfx(&"gunshot" if kind == &"live" else &"blank")
		await get_tree().create_timer(0.6).timeout
		if kind == &"live":
			_on_duel_victim_hit(victim)
	match result:
		ChamberDeck.Result.BLANK:
			_character_react(victim, &"relief")
		ChamberDeck.Result.LUCKY_DRAW:
			_character_react(victim, &"win")

	var result_label := UIStyle.make_label(text, 64, col, true)
	result_label.name = "ChamberResult"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	result_label.add_theme_constant_override("outline_size", 10)
	var vbox := get_node_or_null("ChamberCenter/VBoxContainer")
	if vbox:
		vbox.add_child(result_label)
	if tension:
		tension.text = line
	result_label.pivot_offset = Vector2(size.x * 0.5, 40)
	result_label.scale = Vector2(1.8, 1.8)
	var pop := create_tween().bind_node(result_label)
	pop.tween_property(result_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if is_online and not is_host_here():
		pass  # client: host already broadcast this log line via _rpc_log
	else:
		game.log_event.emit("Chamber Draw result: %s" % ChamberDeck.result_name(result))

	# Lower the gun / swing the camera back while the verdict sits on screen.
	if _duel:
		_duel.finish()
		_duel = null
	await get_tree().create_timer(1.9).timeout
	_close_chamber_ui()
	_resolve_chamber_result(result)

## Fades the chamber overlay away and restores camera / music.
func _close_chamber_ui() -> void:
	_duel_seat = -1
	_duel_shooter = -1
	_end_duel()
	if _player_ui:
		create_tween().bind_node(_player_ui).tween_property(_player_ui, "modulate:a", 1.0, 0.35)
	Sound.stop_loop(&"heartbeat", 0.2)
	Sound.unduck(1.0)
	if _camera_3d and is_instance_valid(_camera_3d) and _chamber_cam_fov > 0.0:
		create_tween().bind_node(_camera_3d).tween_property(_camera_3d, "fov", _chamber_cam_fov, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_chamber_cam_fov = -1.0
	for node_name: String in ["ChamberBG", "ChamberCenter"]:
		var n := get_node_or_null(node_name)
		if n:
			n.name = node_name + "Closing"
			var tw := create_tween().bind_node(n)
			tw.tween_property(n, "modulate:a", 0.0, 0.3)
			tw.tween_callback(n.queue_free)

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

# ── Game Over ─────────────────────────────────────────────────────────

func _show_game_over() -> void:
	_force_end_vice()
	_clear_stage()
	for t: Variant in _seat_tags.values():
		if is_instance_valid(t):
			(t as Control).visible = false
			var tsp: Variant = (t as Control).get_meta(&"sprite", null)
			if tsp != null and is_instance_valid(tsp):
				(tsp as Sprite3D).visible = false
	for g: Control in [_gauge_a, _gauge_b]:
		if g:
			g.visible = false
			var gsp: Variant = g.get_meta(&"sprite", null)
			if gsp != null and is_instance_valid(gsp):
				(gsp as Sprite3D).visible = false
	_clear_overlay()
	overlay.z_index = LAYER_GAME_OVER
	if overlay_vbox and overlay_vbox.get_parent():
		overlay_vbox.get_parent().remove_child(overlay_vbox)
		overlay_vbox.queue_free()
	overlay.visible = true
	overlay.color = Color(0, 0, 0, 0.0)
	create_tween().tween_property(overlay, "color:a", 0.55, 0.6)

	var won := false
	if own_index >= 0 and own_index < game.players.size():
		won = game.players[own_index].display_name in game.winner_name.split(", ")

	var panel := UIStyle.make_panel(Color(UIStyle.SMOKE, 0.96))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(440, 0)
	overlay.add_child(panel)
	overlay_vbox = VBoxContainer.new()
	overlay_vbox.add_theme_constant_override("separation", 16)
	panel.add_child(overlay_vbox)

	var title := UIStyle.make_label("VICTORY" if won else "GAME OVER", 56,
		UIStyle.BRASS_LIGHT if won else UIStyle.BLOOD_LIGHT, true)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	overlay_vbox.add_child(title)

	var rule := ColorRect.new()
	rule.color = Color(UIStyle.BRASS_DIM, 0.8)
	rule.custom_minimum_size = Vector2(0, 1)
	overlay_vbox.add_child(rule)

	var winner := UIStyle.make_label("%s wins!" % game.winner_name, 26, UIStyle.CREAM, true)
	overlay_vbox.add_child(winner)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	overlay_vbox.add_child(row)

	var replay_btn := UIStyle.make_button("Play Again", &"primary", Vector2(170, 52), 18)
	replay_btn.pressed.connect(_on_play_again)
	row.add_child(replay_btn)

	var menu_btn := UIStyle.make_button("Main Menu", &"secondary", Vector2(170, 52), 18)
	menu_btn.pressed.connect(_on_main_menu)
	row.add_child(menu_btn)

	# Center the panel once it has measured itself, then drop it in.
	panel.reset_size()
	panel.position = (size - panel.size) * 0.5
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.6, 0.6)
	panel.modulate.a = 0.0
	var tw := create_tween().bind_node(panel)
	tw.tween_interval(0.25)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: Juice.punch(title, 0.18, 0.5))

	Sound.duck(-10.0, 0.6)
	_sfx(&"win" if won else &"lose")
	if won:
		Juice.burst(self, Vector2(size.x * 0.2, size.y + 10), &"confetti", 1.2)
		Juice.burst(self, Vector2(size.x * 0.8, size.y + 10), &"confetti", 1.2)
		var again := create_tween().bind_node(self)
		again.tween_interval(0.7)
		again.tween_callback(func() -> void: Juice.burst(self, Vector2(size.x * 0.5, size.y + 10), &"confetti", 1.4))
	else:
		Juice.burst(self, size * 0.5, &"smoke", 3.0)
	for i in range(game.players.size()):
		if i != own_index and game.players[i].display_name in game.winner_name.split(", "):
			_character_react(i, &"win")
	_orbit_camera()

## Slow cinematic orbit around the table while the game-over panel is up.
func _orbit_camera() -> void:
	if _camera_3d == null or not is_instance_valid(_camera_3d) or Juice.reduced_motion():
		return
	var cam := _camera_3d
	var center := _table_center
	var start := cam.global_position
	var offset := start - center
	var tw := create_tween().bind_node(cam)
	tw.tween_method(func(a: float) -> void:
		if not is_instance_valid(cam):
			return
		cam.global_position = center + offset.rotated(Vector3.UP, a)
		cam.look_at(center, Vector3.UP)
	, 0.0, TAU * 0.35, 18.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Play Again: a fresh game with the SAME settings. Offline (and the tutorial)
## reloads the table; online returns everyone to the lobby room (still joined)
## so the host can start the next game.
func _on_play_again() -> void:
	_force_end_vice()
	if is_online:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		return
	get_tree().reload_current_scene()

## Main Menu: leave any online lobby and go back to the title screen.
func _on_main_menu() -> void:
	_leaving = true
	_force_end_vice()
	if is_online and _eos:
		# Finish leaving (destroy the lobby, close the peer) BEFORE the scene goes away:
		# tearing the network down while the scene is being freed crashed the host.
		await _eos.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

# ── Game log viewer (key L) ──────────────────────────────────────────

## Keeps every game/network log line (host and clients) so [L] can show the whole match.
func _record_log(text: String) -> void:
	if _is_peek_log(text):
		return
	var secs := int((Time.get_ticks_msec() - _log_t0_ms) / 1000)
	var line := "[%02d:%02d] %s" % [secs / 60, secs % 60, text]
	_log_history.append(line)
	if _log_history.size() > LOG_HISTORY_MAX:
		_log_history.pop_front()
	if _log_text != null:
		_log_text.append_text(_escape_bb(line) + "\n")

func _escape_bb(t: String) -> String:
	return t.replace("[", "[lb]")

## The log reveals what other players did/drew, so it is a hidden debug tool: no
## button, offline only. Online it stays locked unless the game is launched with
## the `--chamber-log` argument (for diagnosing network problems).
func _log_allowed() -> bool:
	if not is_online:
		return true
	return OS.get_cmdline_user_args().has("--chamber-log") or OS.get_cmdline_args().has("--chamber-log")

func _toggle_log_panel() -> void:
	if _log_panel == null and not _log_allowed():
		return
	if _log_panel != null:
		_log_panel.queue_free()
		_log_panel = null
		_log_text = null
		return
	var dim := ColorRect.new()
	dim.name = "LogPanel"
	dim.z_index = LAYER_PAUSE + 10
	dim.color = Color(UIStyle.INK, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_log_panel = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := UIStyle.make_panel()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.add_child(UIStyle.make_label("GAME LOG", 30, UIStyle.BRASS, true))

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.custom_minimum_size = Vector2(620, 340)
	rt.add_theme_color_override("default_color", UIStyle.CREAM)
	rt.add_theme_font_size_override("normal_font_size", 15)
	for l in _log_history:
		rt.append_text(_escape_bb(l) + "\n")
	vbox.add_child(rt)
	_log_text = rt

	var close_btn := UIStyle.make_button("Close  [L]", &"secondary", Vector2(180, 44), 18)
	close_btn.pressed.connect(_toggle_log_panel)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(close_btn)

# ── Players leaving an online game ───────────────────────────────────

func _connect_session_signals() -> void:
	if not is_online or _eos == null:
		return
	if not _eos.player_left_game.is_connected(_on_player_left_game):
		_eos.player_left_game.connect(_on_player_left_game)
	if not _eos.host_lost_in_game.is_connected(_on_host_lost):
		_eos.host_lost_in_game.connect(_on_host_lost)

func _make_choice_popup(message: String, buttons: Array) -> ColorRect:
	var dim := ColorRect.new()
	dim.z_index = LAYER_PAUSE + 20
	dim.color = Color(UIStyle.INK, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := UIStyle.make_panel()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	var msg := UIStyle.make_label(message, 24, UIStyle.CREAM, true)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(msg)
	for b in buttons:
		var btn := UIStyle.make_button(b.text, b.variant, Vector2(320, 52), 19)
		btn.pressed.connect(b.callback)
		vbox.add_child(btn)
	_sfx(&"banner")
	return dim

## Host: a client dropped. 1v1 (or last opponent) ends the session; otherwise the
## host decides whether the rest keep playing or the game ends for everyone.
func _on_player_left_game(seat: int, display_name: String) -> void:
	if _leaving or _session_ended or game == null or game.game_over:
		return
	if not is_host_here() or seat < 0 or seat >= game.players.size():
		return
	if game.players[seat].left_game:
		return
	_game_log("%s disconnected." % display_name)
	var remaining := 0
	for i in range(game.players.size()):
		if i != seat and not game.players[i].left_game:
			remaining += 1
	if remaining <= 1:
		_show_session_over("%s left the game." % display_name)
		return
	_pending_leavers.append({"seat": seat, "name": display_name})
	_process_next_leaver()

func _process_next_leaver() -> void:
	if _leave_popup != null or _pending_leavers.is_empty() or _session_ended:
		return
	var who: Dictionary = _pending_leavers[0]
	_paused = true
	rpc("_rpc_set_paused", true, game.players[own_index].display_name)
	_leave_popup = _make_choice_popup("%s left the game.\nLet everyone else keep playing, or end the game for all?" % who.name, [
		{"text": "Continue Without Them", "variant": &"primary", "callback": _on_leaver_continue},
		{"text": "End Game For Everyone", "variant": &"danger", "callback": _on_leaver_end},
	])

func _close_leave_popup() -> void:
	if _leave_popup != null:
		_leave_popup.queue_free()
		_leave_popup = null

func _on_leaver_continue() -> void:
	_close_leave_popup()
	for w in _pending_leavers:
		game.drop_player(int(w.seat))
	_pending_leavers.clear()
	_paused = false
	rpc("_rpc_set_paused", false, "")
	_broadcast_snapshot()
	_refresh_all()
	if game.game_over:
		state = State.GAME_OVER
		_show_game_over()
	else:
		_check_turn()

func _on_leaver_end() -> void:
	_close_leave_popup()
	_pending_leavers.clear()
	rpc("_rpc_session_ended", "The host ended the game.")
	_leave_to_online_screen()

## Host → clients: the match is over (host ended it).
@rpc("authority", "call_remote", "reliable")
func _rpc_session_ended(message: String) -> void:
	if not is_online or is_host_here():
		return
	_show_session_over(message)

func _on_host_lost() -> void:
	if _leaving or _session_ended:
		return
	_show_session_over("The host left the game.")

## Nobody left to play with (or the host closed the room): pick where to go next.
func _show_session_over(message: String) -> void:
	if _session_ended:
		return
	_session_ended = true
	_paused = true
	_close_leave_popup()
	_hide_pause_overlay()
	_leave_popup = _make_choice_popup(message, [
		{"text": "Online Screen", "variant": &"primary", "callback": _leave_to_online_screen},
		{"text": "Main Menu", "variant": &"secondary", "callback": _on_main_menu},
	])

func _leave_to_online_screen() -> void:
	_leaving = true
	_force_end_vice()
	if _eos:
		await _eos.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

# ── Helpers ───────────────────────────────────────────────────────────

## Plays a semantic sound event through the AudioManager autoload.
func _sfx(event: StringName, vol_offset_db: float = 0.0, pitch: float = 1.0) -> void:
	Sound.play(event, vol_offset_db, pitch)

func _clear_overlay() -> void:
	var frame := overlay.get_node_or_null("PopupFrame") if overlay else null
	if frame:
		frame.visible = false
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
	var remote := multiplayer.get_remote_sender_id() != 0
	_process_intent(intent)
	# A REMOTE player's action changed the host's own GameState: bring the host's screen
	# (and turn logic: its own turn, AI, popups) up to date too.
	if remote and is_online and is_host_here() and game != null and intent.get("kind", "") != "hello":
		_refresh_all()
		_check_turn()

func _process_intent(intent: Dictionary) -> void:
	if not is_online:
		return
	if not _eos or not _eos.is_host:
		return
	if game == null:
		return  # Host still initializing; client will retry hello.

	var sender_peer_id := multiplayer.get_remote_sender_id()
	if sender_peer_id == 0:
		sender_peer_id = EOSManager.HOST_PEER_ID   # the host calling its own intent directly
	var seat: int = 0 if sender_peer_id == EOSManager.HOST_PEER_ID else _eos.get_seat_for_peer(sender_peer_id)
	if seat == -1:
		print("[Net] host: intent '%s' from unknown peer %d ignored" % [intent.get("kind", "?"), sender_peer_id])
		return

	if intent.kind == "hello":
		print("[Net] host: hello from peer %d (seat %d) - sending snapshot" % [sender_peer_id, seat])
		# Client's game scene is up - stop re-sending the start RPC to it.
		_eos.mark_client_in_game(sender_peer_id)
		if _paused and sender_peer_id != EOSManager.HOST_PEER_ID:
			var hn: String = game.players[own_index].display_name if own_index < game.players.size() else "Host"
			rpc_id(sender_peer_id, "_rpc_set_paused", true, hn)
		# Client wants a fresh board; send it ONLY to that client (not every seat).
		if game.players.size() > 0 and sender_peer_id != EOSManager.HOST_PEER_ID:
			_send_snapshot_to(sender_peer_id, _make_snapshot(seat))
		return

	if game.players.is_empty() or seat >= game.players.size():
		return

	# Turn/order guard: play/draw only on the acting player's turn; diffuse only
	# while that seat is mid-bomb; last_shot only on the acting player's turn.
	var is_acting: bool = seat == game.current_index
	if not is_acting and not ((intent.kind == "diffuse" and game.pending_bomb != null and game.pending_diffuse_player_index == seat) or (intent.kind == "jump_in" and game.jump_in_open) or (intent.kind == "last_shot" and game.pending_last_shot) or intent.kind == "pass_out"):
		return

	if _paused:
		return  # host froze the table; ignore gameplay intents until resume

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
			game.draw_card(seat, pile_id, true, false)   # like offline: the turn goes on until a play / End Turn
			if game.pending_bomb == null:
				_drew_marker = seat

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

		"end_turn":
			if game.current_index == seat and not game.game_over and _drew_marker == seat:
				_drew_marker = -1
				game.advance_turn()
				_broadcast_snapshot()

		"pass_out":
			if game.pass_out(seat):
				_drew_marker = -1
				_broadcast_snapshot()

		"timeout":
			# A client ran out of time: apply the same penalty the host would take itself.
			if not game.game_over and game.current_index == seat:
				_apply_turn_timeout()
				_broadcast_snapshot()

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
	var victim := game.pending_diffuse_player_index
	var shooter := _pick_shooter(victim)
	_pending_chamber_reveal = {"seat": victim, "result": int(result), "shooter": shooter}
	game.resolve_bomb_with_result(result)
	game.sync_respawn_cards()
	_broadcast_snapshot()
	# The host watches the duel too (the remote seat has no local overlay here).
	if get_node_or_null("ChamberBG") == null:
		_play_chamber_reveal(result, victim, shooter)

# ── Snapshot: host → clients (per-seat, hand data private) ────────────

## Builds a snapshot dict. seat>=0 gives that seat's real hand and hides every
## other seat's cards behind same-sized placeholders. seat=-1 exposes every
## hand (host-internal only - never broadcast).
func _make_snapshot(seat: int = -1) -> Dictionary:
	if game.current_index != _drew_marker:
		_drew_marker = -1
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
			"passed_out": p.passed_out,
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
		"you": seat,
		"drew": _drew_marker == seat and seat >= 0,
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
		_send_snapshot_to(entry.peer_id, snap)
	_pending_chamber_reveal = {}

## A full snapshot is far bigger than one EOS P2P packet (~1170 bytes), so it is
## compressed and sent as small ordered chunks that the client reassembles.
const SNAP_CHUNK_BYTES := 800
var _snap_seq := 0
var _snap_rx: Dictionary = {}       # seq -> {total, parts}
var _snap_applied_seq := 0

func _send_snapshot_to(peer_id: int, snap: Dictionary) -> void:
	if peer_id <= 0:
		return
	var raw := var_to_bytes(snap)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	_snap_seq += 1
	var total: int = ceili(packed.size() / float(SNAP_CHUNK_BYTES))
	for i in range(total):
		var part := packed.slice(i * SNAP_CHUNK_BYTES, mini((i + 1) * SNAP_CHUNK_BYTES, packed.size()))
		rpc_id(peer_id, "_rpc_snapshot_chunk", _snap_seq, i, total, raw.size(), part)

@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot_chunk(seq: int, idx: int, total: int, raw_size: int, part: PackedByteArray) -> void:
	if not is_online or seq <= _snap_applied_seq:
		return
	var entry: Dictionary = _snap_rx.get(seq, {})
	if entry.is_empty():
		entry = {"total": total, "parts": {}}
		_snap_rx[seq] = entry
	entry.parts[idx] = part
	if entry.parts.size() < total:
		return
	var packed := PackedByteArray()
	for i in range(total):
		packed.append_array(entry.parts[i])
	_snap_applied_seq = seq
	for k in _snap_rx.keys():
		if int(k) <= seq:
			_snap_rx.erase(k)
	var snap: Variant = bytes_to_var(packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD))
	if snap is Dictionary:
		_apply_snapshot(snap)
	else:
		push_warning("[Net] client: snapshot #%d failed to decode" % seq)

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
	if not _got_first_snapshot:
		print("[Net] client: first snapshot received")
	_got_first_snapshot = true

	if not _eos:
		return

	# The host stamps every snapshot with the receiver's seat: trust that over any local guess.
	var local_seat: int = int(snapshot.get("you", _eos.get_own_seat()))

	# Rebuild game.players from snapshot data.
	game.players.clear()
	var idx := 0
	for pdata in snapshot.players:
		var p := PlayerData.new(pdata.id, pdata.display_name)
		p.banked_lives = pdata.banked_lives
		p.eliminated = pdata.eliminated
		p.skip_next_turn = pdata.skip_next_turn
		p.passed_out = bool(pdata.get("passed_out", false))
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
		var reveal_seat: int = int(reveal.seat)
		var reveal_result: int = int(reveal.result)
		var reveal_shooter: int = int(reveal.get("shooter", -1))
		# Every client watches the same duel (shooter chosen by the host).
		_play_chamber_reveal(reveal_result, reveal_seat, reveal_shooter)

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
	# Drew this turn already (host says so): show the End Turn button again.
	if bool(snapshot.get("drew", false)) and game.current_index == own_index and state == State.HUMAN_TURN:
		_state_after_draw()
	else:
		_hide_end_turn_btn()

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
