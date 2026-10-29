extends Control

## Texas Hold'em screen (offline vs computer players). Beginner-first: a live hand-ranking
## sidebar on the right, a coach strip that explains what you hold and what to do, plain-English
## buttons, and a guided tutorial hand. Rules live in poker_table.gd; this file is presentation.

const UIStyle := preload("res://scripts/ui_style.gd")
const Sound := preload("res://scripts/sound.gd")
const Eval := preload("res://scripts/poker/poker_eval.gd")
const Table := preload("res://scripts/poker/poker_table.gd")
const CardView := preload("res://scripts/poker/poker_card_view.gd")
const Tutorial := preload("res://scripts/poker/poker_tutorial.gd")
const World := preload("res://scripts/poker/poker_world.gd")
const Keybinds := preload("res://scripts/keybinds.gd")
const Vices := preload("res://scripts/poker/poker_vices.gd")

const START_CHIPS := 1000
const HUMAN := 0
const RANK_W := 228.0
const TOP_H := 52.0
const ACTION_H := 74.0
const BLIND_LEVEL_HANDS := 6
const AI_NAMES := ["Vinnie", "Mabel", "Doc", "Lucky", "Rosa", "Ghost", "Sly", "Duchess"]
const SNAP_CHUNK := 800
const REMOTE_TURN_SECONDS := 45.0
const LOCAL_TURN_SECONDS := 60.0
const LOOK_YAW := 75.0
const LOOK_PITCH_UP := 30.0
const LOOK_PITCH_DOWN := 42.0
const BARKS := {
	"raise": ["Raise it up!", "Let's make it interesting.", "Pay to play, friend.", "Chips talk."],
	"call": ["I'll see that.", "Call.", "Fine. I'm in.", "Keep your chips warm."],
	"check": ["Check.", "Knock knock.", "Check it."],
	"fold": ["Too rich for me.", "Not today.", "I'm out.", "Nope."],
	"allin": ["ALL IN!", "Everything. Right now.", "Pray for me."],
	"win": ["Thank you kindly!", "Read 'em and weep.", "Come to papa.", "Easy money."],
	"lose": ["Unreal...", "Beginner's luck.", "Bah!", "Next hand."],
}
const AI_STYLES := ["balanced", "tight", "loose", "wild", "balanced", "tight", "loose", "balanced"]

signal human_acted(kind: String, amount: int)
signal next_pressed
signal coach_continued

var engine: Table
var tutorial: RefCounted = null
var is_tutorial: bool = false
var colors: Array = []

var _shown_board: int = 0
var _awaiting: bool = false
var _allowed: Array = []
var _fold_armed: bool = false
var _coach_on: bool = true
var key_strip: RichTextLabel
var right_w: float = 205.0
var _turn_border: Panel
var _turn_style: StyleBoxFlat
var _coach_wait: bool = false
var coach_hint: Label
var _paused: bool = false
var _thinking: int = -1
var _revealed: Dictionary = {}
var _winners: Dictionary = {}
var _status_text: Dictionary = {}
var _tier_cat: int = -1
var _hand_summary: String = ""
var _waiting_next: bool = false
var _anim_busy: bool = false
var _dealing: bool = false
var is_online: bool = false
var is_host: bool = true
var own_seat: int = 0
var _eos: Node = null
var _snap_seq: int = 0
var _snap_applied: int = -1
var _snap_rx: Dictionary = {}
var _snap_queue: Array = []
var _hello: Dictionary = {}
var _dropped: Dictionary = {}
var _remote_intents: Dictionary = {}
var _turn_id: int = 0
var _hand_presented: bool = false
var _busted_told: bool = false
var _roster_names: Array = []
var _cursor_free: bool = false
var _look_yaw: float = 0.0
var _look_pitch: float = -15.0
var _cinematic: bool = false
var _pending: Dictionary = {}
var _pending_order: Array = []
var _hover: Dictionary = {}
var _peek_t: float = 0.0
var _peek_until: int = 0
var _force_up: bool = false
var _acting: bool = false
var _pot_hidden: bool = false
var _chip_hold: Dictionary = {}
var crosshair: Panel
var prompt_label: Label
var legend_label: RichTextLabel
var winner_banner: PanelContainer
var vices: Node
var _sleep_hands: int = 0
var _sleep_cover: ColorRect
var dealer_tag: Label
var pile_label: Label
var me_hud: PanelContainer
var me_name: Label
var me_chips: Label
var me_role: Label
var _button_seat: int = -1
var help_panel: PanelContainer
var _help_seen: bool = false
var winner_title: Label
var winner_sub: Label

# Scene pieces
var world: Node
var stage: Control
var top_title: Label
var pot_label: Label
var stage_label: Label
var hint_label: RichTextLabel
var action_bar: PanelContainer
var right_panel: PanelContainer
var coach_panel: PanelContainer
var coach_title: Label
var coach_body: RichTextLabel
var spot_ring: Panel
var _spot_target: Variant = null
var _menu_popup: Control = null

var seat_views: Array = []        # per seat: {panel,name,chips,role,bet,dealer,cards:[v,v]}
var board_nodes: Array = [null, null, null, null, null]
var tier_rows: Array = []

func _ready() -> void:
	UIStyle.install()
	is_tutorial = GameGlobals.is_tutorial
	var st: Node = UIStyle.settings()
	if st != null:
		_coach_on = bool(st.get("poker_hints"))
		if st.has_signal("changed") and not st.is_connected("changed", Callable(self, "_on_settings_changed")):
			st.connect("changed", Callable(self, "_on_settings_changed"))
	_setup_match()
	_build_ui()
	resized.connect(_layout)
	_layout()
	_refresh_all()
	Sound.play_music(&"table")
	if is_online and not is_host:
		_client_start()
	else:
		_game_loop()

# ── Match setup ───────────────────────────────────────────────────────

func _setup_match() -> void:
	is_online = GameGlobals.is_online and not is_tutorial
	if is_online:
		_setup_online_match()
		return
	var n: int = clampi(GameGlobals.num_players, 2, 8)
	if is_tutorial:
		n = 2
	var pool: Array = AI_NAMES.duplicate()
	pool.shuffle()
	var names: Array = ["You"]
	var styles: Array = ["balanced"]
	for k in range(n - 1):
		names.append(pool[k])
		styles.append(AI_STYLES[k])
	if is_tutorial:
		names[1] = "Coach Bot"
	engine = Table.new()
	engine.setup(names, START_CHIPS, HUMAN, styles)
	var free: Array = range(GameGlobals.PALETTE.size())
	var mine: int = clampi(GameGlobals.my_color_idx, 0, GameGlobals.PALETTE.size() - 1)
	free.erase(mine)
	free.shuffle()
	colors = [GameGlobals.PALETTE[mine]]
	for k in range(n - 1):
		colors.append(GameGlobals.PALETTE[free[k]])
	if is_tutorial:
		tutorial = Tutorial.new(self)

## Online: everyone is a real player from the lobby roster. Seats are re-numbered so YOU are always
## index 0 on your own screen (the host's numbering is the real one; clients get rotated snapshots).
func _setup_online_match() -> void:
	_eos = get_node_or_null("/root/EOSManager")
	is_host = _eos.is_host
	own_seat = _eos.get_own_seat()
	var roster: Array = _eos.roster
	var n: int = roster.size()
	var names: Array = []
	colors = []
	for k in range(n):
		var entry: Dictionary = roster[(own_seat + k) % n]
		names.append("You" if k == 0 else String(entry.display_name))
		colors.append(_eos.color_for_entry(entry))
		_roster_names.append(String(entry.display_name))
	engine = Table.new()
	engine.setup(names, START_CHIPS, HUMAN, [])
	if is_host:
		for k in range(1, n):
			engine.players[k]["remote"] = true
	if _eos.has_signal("player_left_game") and not _eos.player_left_game.is_connected(_on_player_left):
		_eos.player_left_game.connect(_on_player_left)
	if _eos.has_signal("host_lost_in_game") and not _eos.host_lost_in_game.is_connected(_on_host_lost):
		_eos.host_lost_in_game.connect(_on_host_lost)

# ── UI construction ───────────────────────────────────────────────────

func _build_ui() -> void:
	var bg := preload("res://scripts/noir_background.gd").new()
	add_child(bg)

	var names: Array = []
	for p in engine.players:
		names.append(p.name)
	world = World.new()
	add_child(world)
	world.setup(self, engine.players.size(), colors, names)

	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)

	# Seats
	for i in range(engine.players.size()):
		seat_views.append(_make_seat(i))

	pot_label = UIStyle.make_label("", 12, UIStyle.CREAM)
	pot_label.visible = false
	stage.add_child(pot_label)
	stage_label = UIStyle.make_label("", 15, UIStyle.BRASS_LIGHT, true)
	stage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_label.add_theme_stylebox_override("normal", UIStyle.panel_style(Color(UIStyle.INK, 0.78), UIStyle.BRASS_DIM, 12, 1))
	stage_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	stage_label.add_theme_constant_override("outline_size", 4)
	stage_label.custom_minimum_size = Vector2(0, 26)
	stage.add_child(stage_label)

	_build_top_bar()
	_build_action_bar()
	_build_right_panel()
	var st0: Node = UIStyle.settings()
	right_panel.visible = bool(st0.get("poker_rankings")) if st0 != null else true
	_build_coach_panel()

	spot_ring = Panel.new()
	spot_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(0, 0, 0, 0)
	ring.border_color = UIStyle.BRASS_LIGHT
	ring.set_border_width_all(3)
	ring.set_corner_radius_all(10)
	ring.shadow_color = Color(UIStyle.BRASS, 0.6)
	ring.shadow_size = 10
	spot_ring.add_theme_stylebox_override("panel", ring)
	spot_ring.visible = false
	add_child(spot_ring)
	_build_hud_extras()
	_apply_right_w()

func _build_hud_extras() -> void:
	_turn_border = Panel.new()
	_turn_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_turn_border.offset_right = -right_w
	_turn_style = StyleBoxFlat.new()
	_turn_style.draw_center = false
	_turn_style.set_border_width_all(7)
	_turn_style.border_color = Color(1, 0.85, 0.3, 0.9)
	_turn_style.shadow_color = Color(1, 0.85, 0.3, 0.35)
	_turn_style.shadow_size = 18
	_turn_border.add_theme_stylebox_override("panel", _turn_style)
	_turn_border.visible = false
	add_child(_turn_border)
	vices = Vices.new()
	add_child(vices)
	vices.setup(self, world)
	me_hud = UIStyle.make_panel(Color(UIStyle.INK, 0.88))
	me_hud.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(UIStyle.INK, 0.88), UIStyle.BRASS_DIM, 12, 2))
	me_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 0)
	me_hud.add_child(mv)
	me_name = UIStyle.make_label("YOU", 12, UIStyle.CREAM, true)
	mv.add_child(me_name)
	me_chips = UIStyle.make_label("1,000", 24, UIStyle.BRASS_LIGHT, true)
	mv.add_child(me_chips)
	me_role = UIStyle.make_label("chips", 10, UIStyle.MUTED)
	mv.add_child(me_role)
	add_child(me_hud)
	pile_label = UIStyle.make_label("", 14, UIStyle.BRASS_LIGHT, true)
	pile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile_label.add_theme_stylebox_override("normal", UIStyle.panel_style(Color(UIStyle.INK, 0.9), UIStyle.BRASS, 10, 1))
	pile_label.visible = false
	add_child(pile_label)
	dealer_tag = UIStyle.make_label("DEALER", 12, UIStyle.BRASS_LIGHT, true)
	dealer_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dealer_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	dealer_tag.add_theme_constant_override("outline_size", 4)
	dealer_tag.size = Vector2(80, 18)
	add_child(dealer_tag)
	help_panel = UIStyle.make_panel(Color(UIStyle.INK, 0.94))
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.visible = false
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	help_panel.add_child(hv)
	hv.add_child(UIStyle.make_label("CONTROLS", 16, UIStyle.BRASS, true))
	var rows := [["MOUSE", "look around"], ["CLICK a chip stack", "add that chip to your pile"], ["CLICK the pile / SPACE", "bet (empty pile = check)"], ["RIGHT-CLICK", "take a chip back"], ["CLICK your cards / F", "fold"], ["C", "call or check"], ["R", "minimum raise"], ["A", "all-in"], ["1-5", "add chip 1 / 5 / 25 / 100 / 500"], ["Q or hover", "peek at your cards"], ["TAB", "free the cursor"], ["H", "this help"]]
	for r in rows:
		var rl := UIStyle.make_label("%s   %s" % [r[0], r[1]], 11, UIStyle.CREAM)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hv.add_child(rl)
	add_child(help_panel)
	help_panel.position = Vector2(14, TOP_H + 40.0)

	crosshair = Panel.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -4
	crosshair.offset_right = 4
	crosshair.offset_top = -4
	crosshair.offset_bottom = 4
	crosshair.pivot_offset = Vector2(4, 4)
	add_child(crosshair)
	prompt_label = UIStyle.make_label("", 13, UIStyle.BRASS_LIGHT, true)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt_label.add_theme_constant_override("outline_size", 6)
	prompt_label.size = Vector2(360, 24)
	add_child(prompt_label)
	winner_banner = UIStyle.make_panel(Color(UIStyle.INK, 0.9))
	winner_banner.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(UIStyle.INK, 0.92), Color("ffd877"), 16, 3))
	winner_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	winner_banner.visible = false
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 2)
	winner_banner.add_child(wv)
	winner_title = UIStyle.make_label("", 34, Color("ffd877"), true)
	wv.add_child(winner_title)
	winner_sub = UIStyle.make_label("", 18, UIStyle.CREAM)
	wv.add_child(winner_sub)
	add_child(winner_banner)

func _make_seat(i: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(92, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	panel.add_child(vb)
	var nm := UIStyle.make_label(String(engine.players[i].name), 11, colors[i].lightened(0.25), true)
	vb.add_child(nm)
	var chips := UIStyle.make_label("", 10, UIStyle.CREAM)
	vb.add_child(chips)
	var role := UIStyle.make_label("", 9, UIStyle.MUTED)
	vb.add_child(role)
	stage.add_child(panel)
	var cards: Array = [null, null]
	var bet := Label.new()
	bet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bet.add_theme_font_size_override("font_size", 14)
	bet.add_theme_color_override("font_color", Color("1b1408"))
	var bsb := UIStyle.flat_box(UIStyle.BRASS_LIGHT, UIStyle.BRASS_DIM, 11, 1)
	bsb.content_margin_left = 9
	bsb.content_margin_right = 9
	bsb.content_margin_top = 2
	bsb.content_margin_bottom = 2
	bet.add_theme_stylebox_override("normal", bsb)
	bet.visible = false
	stage.add_child(bet)
	var dealer := Label.new()
	dealer.text = "D"
	dealer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dealer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dealer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dealer.custom_minimum_size = Vector2(26, 26)
	dealer.add_theme_font_size_override("font_size", 15)
	dealer.add_theme_color_override("font_color", UIStyle.INK)
	dealer.add_theme_stylebox_override("normal", UIStyle.flat_box(UIStyle.CREAM, UIStyle.BRASS, 13, 2))
	dealer.tooltip_text = "Dealer button. It moves one seat every hand."
	dealer.visible = false
	stage.add_child(dealer)
	return {"panel": panel, "name": nm, "chips": chips, "role": role, "bet": bet, "dealer": dealer, "cards": cards}

func _build_top_bar() -> void:
	top_title = UIStyle.make_label("", 12, UIStyle.CREAM)
	top_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_title.set_anchor(SIDE_LEFT, 0.0)
	top_title.set_anchor(SIDE_RIGHT, 1.0)
	top_title.offset_left = 10
	top_title.offset_right = -right_w - 10
	top_title.offset_top = 12
	top_title.offset_bottom = 36
	add_child(top_title)

func _build_action_bar() -> void:
	action_bar = UIStyle.make_panel(Color(UIStyle.INK, 0.88))
	action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_bar.set_anchor(SIDE_LEFT, 0.0)
	action_bar.set_anchor(SIDE_RIGHT, 1.0)
	action_bar.set_anchor(SIDE_TOP, 1.0)
	action_bar.set_anchor(SIDE_BOTTOM, 1.0)
	action_bar.offset_left = 10
	action_bar.offset_right = -right_w - 10
	action_bar.offset_top = -ACTION_H - 8
	action_bar.offset_bottom = -8
	add_child(action_bar)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	action_bar.add_child(vb)
	hint_label = RichTextLabel.new()
	hint_label.bbcode_enabled = true
	hint_label.fit_content = false
	hint_label.scroll_active = false
	hint_label.custom_minimum_size = Vector2(0, 22)
	hint_label.add_theme_font_override("normal_font", UIStyle.body_font())
	hint_label.add_theme_font_override("bold_font", UIStyle.body_font())
	hint_label.add_theme_font_size_override("normal_font_size", 13)
	hint_label.add_theme_font_size_override("bold_font_size", 13)
	hint_label.add_theme_color_override("default_color", UIStyle.CREAM)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint_label)
	key_strip = RichTextLabel.new()
	key_strip.bbcode_enabled = true
	key_strip.fit_content = false
	key_strip.scroll_active = false
	key_strip.custom_minimum_size = Vector2(0, 24)
	key_strip.add_theme_font_override("normal_font", UIStyle.title_font())
	key_strip.add_theme_font_override("bold_font", UIStyle.title_font())
	key_strip.add_theme_font_size_override("normal_font_size", 12)
	key_strip.add_theme_font_size_override("bold_font_size", 12)
	key_strip.add_theme_color_override("default_color", UIStyle.CREAM)
	key_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(key_strip)

func _build_right_panel() -> void:
	right_panel = UIStyle.make_panel(Color(UIStyle.SMOKE, 0.94))
	right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_panel.set_anchor(SIDE_LEFT, 1.0)
	right_panel.set_anchor(SIDE_RIGHT, 1.0)
	right_panel.set_anchor(SIDE_TOP, 0.0)
	right_panel.set_anchor(SIDE_BOTTOM, 0.0)
	right_panel.offset_left = -RANK_W
	right_panel.offset_right = -6
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_panel.custom_minimum_size = Vector2(RANK_W - 6.0, 0)
	right_panel.offset_top = 6
	add_child(right_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	right_panel.add_child(vb)
	vb.add_child(UIStyle.make_label("HAND RANKINGS", 13, UIStyle.BRASS, true))
	var n := Eval.TIERS.size()
	for k in range(n):
		var tier: Dictionary = Eval.TIERS[k]
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", _tier_style(false))
		vb.add_child(row)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 2)
		row.add_child(head)
		var you := UIStyle.make_label("", 10, UIStyle.BRASS_LIGHT, true)
		you.custom_minimum_size = Vector2(10, 0)
		head.add_child(you)
		var nm := UIStyle.make_label(String(tier.name), 10, UIStyle.CREAM)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.custom_minimum_size = Vector2(106, 0)
		nm.clip_text = true
		nm.tooltip_text = String(tier.desc)
		head.add_child(nm)
		for c in tier.example:
			var mv := CardView.new()
			mv.mini = true
			mv.custom_minimum_size = Vector2(12, 18)
			mv.size = Vector2(12, 18)
			mv.show_card(int(c), true)
			head.add_child(mv)
		tier_rows.append({"cat": int(tier.cat), "row": row, "you": you, "name": nm})
	var tip := UIStyle.make_label("best 5 of 7 cards  ·  [%s] hide" % Keybinds.label(&"rankings"), 9, UIStyle.BRASS_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(RANK_W - 30, 0)
	vb.add_child(tip)

func _tier_style(on: bool) -> StyleBoxFlat:
	var sb := UIStyle.flat_box(Color(UIStyle.BRASS, 0.18) if on else Color(0, 0, 0, 0.22), UIStyle.BRASS_LIGHT if on else Color(UIStyle.BRASS_DIM, 0.35), 6, 2 if on else 1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb

func _build_coach_panel() -> void:
	coach_panel = UIStyle.make_panel(Color(UIStyle.INK, 0.96))
	coach_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(UIStyle.INK, 0.96), UIStyle.BRASS, 12, 2))
	coach_panel.custom_minimum_size = Vector2(250, 0)
	coach_panel.visible = false
	add_child(coach_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	coach_panel.add_child(vb)
	coach_title = UIStyle.make_label("", 15, UIStyle.BRASS_LIGHT, true)
	coach_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(coach_title)
	coach_body = RichTextLabel.new()
	coach_body.bbcode_enabled = true
	coach_body.fit_content = true
	coach_body.scroll_active = false
	coach_body.custom_minimum_size = Vector2(230, 0)
	coach_body.add_theme_font_override("normal_font", UIStyle.body_font())
	coach_body.add_theme_font_override("bold_font", UIStyle.body_font())
	coach_body.add_theme_font_size_override("normal_font_size", 12)
	coach_body.add_theme_font_size_override("bold_font_size", 12)
	coach_body.add_theme_color_override("default_color", UIStyle.CREAM)
	vb.add_child(coach_body)
	coach_hint = UIStyle.make_label("[SPACE] continue   ·   [ESC] menu", 11, UIStyle.BRASS)
	coach_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(coach_hint)

# ── Layout ────────────────────────────────────────────────────────────

## Shows or hides the rankings list; the table area and bars follow.
func _apply_right_w() -> void:
	var show_rank: bool = right_panel != null and right_panel.visible
	right_w = (RANK_W + 6.0) if show_rank else 0.0
	if _turn_border != null:
		_turn_border.offset_right = -right_w
	if top_title != null:
		top_title.offset_right = -right_w - 10
	if action_bar != null:
		action_bar.offset_right = -right_w - 10
	_layout()

func _toggle_rankings() -> void:
	var on: bool = not right_panel.visible
	right_panel.visible = on
	var st: Node = UIStyle.settings()
	if st != null:
		st.set("poker_rankings", on)
		st.call("commit")
	_apply_right_w()
	_toast("Hand rankings %s  ·  [%s] toggles" % ["shown" if on else "hidden", Keybinds.label(&"rankings")])

func _table_rect() -> Rect2:
	return Rect2(0, TOP_H, size.x - right_w, size.y - TOP_H - ACTION_H - 8)





## Screen position of a seat's name panel (above the giant's head; bottom of the table for you).
func _seat_pos(i: int) -> Vector2:
	if i == HUMAN:
		var tr := _table_rect()
		return Vector2(human_card_rect().get_center().x - 215.0, tr.end.y - 38.0)
	var actor: Node3D = world.actors.get(i, null)
	var at: Vector3 = world.seat_marker_pos(i) + Vector3(0, 0.55, 0)
	if actor != null and is_instance_valid(actor):
		at = Vector3(actor.global_position.x, 1.0, actor.global_position.z)
	return world.project(at)

func _layout() -> void:
	if seat_views.is_empty():
		return
	stage_label.reset_size()
	stage_label.size.x = maxf(stage_label.size.x, 190.0)
	stage_label.position = Vector2(_table_rect().get_center().x - stage_label.size.x / 2.0, TOP_H - 6.0)
	_layout_panels_only()
	_place_coach()

func _place_coach() -> void:
	coach_panel.reset_size()
	var tr := _table_rect()
	coach_panel.position = Vector2(14, size.y - ACTION_H - 16 - coach_panel.size.y)
	coach_panel.size.x = 250.0







# ── Main loop ─────────────────────────────────────────────────────────

func _wait(t: float) -> void:
	var tw := create_tween()
	tw.tween_interval(t)
	await tw.finished
	while _paused:
		await get_tree().process_frame

func _game_loop() -> void:
	if tutorial:
		await tutorial.on_event("intro")
	if is_online:
		await _wait_for_clients()
	while true:
		if is_online:
			if engine.alive_count() < 2:
				break
		elif engine.alive_count() < 2 or int(engine.players[HUMAN].chips) <= 0:
			break
		await _play_hand()
		if tutorial:
			await tutorial.on_event("hand_end")
			return
		await _wait_next_hand()
	_broadcast({"type": "match_over"})
	await _show_match_end()

func _reset_hand_visuals() -> void:
	_tick_sleep_at_hand_start()
	_shown_board = 0
	_revealed.clear()
	_winners.clear()
	_status_text.clear()
	_hand_summary = ""
	_tier_cat = -1
	_hand_presented = false
	world.clear_cards()
	world.reset_table_piles()
	board_nodes = [null, null, null, null, null]
	for sv in seat_views:
		sv.cards = [null, null]
	_dealing = true
	_pot_hidden = false
	_chip_hold.clear()
	_force_up = false
	_peek_t = 0.0
	winner_banner.visible = false
	_clear_pending()

func _play_hand() -> void:
	if not is_tutorial:
		var level: int = int(float(engine.hand_number) / float(BLIND_LEVEL_HANDS))
		var bb: int = 20 * int(pow(2, mini(level, 4)))
		if bb != engine.big_blind:
			engine.big_blind = bb
			engine.small_blind = int(bb * 0.5)
			_toast("Blinds go up to %d / %d" % [engine.small_blind, engine.big_blind])
	var rig: Dictionary = tutorial.rig() if tutorial else {}
	engine.start_hand(rig)
	_reset_hand_visuals()
	_broadcast({"type": "new_hand"})
	_refresh_all()
	await _deal_animation()
	_dealing = false
	_refresh_all()
	if tutorial:
		await tutorial.on_event("dealt")
	while not engine.hand_over:
		if engine.board.size() > _shown_board:
			await _reveal_board()
			if tutorial:
				await tutorial.on_event("street")
			continue
		var i: int = engine.current
		_refresh_all()
		if bool(engine.players[i].human):
			await _human_turn(i)
		elif bool(engine.players[i].get("remote", false)):
			await _remote_turn(i)
		else:
			await _ai_turn(i)
	if engine.board.size() > _shown_board:
		await _reveal_board()
	_hand_presented = true
	await _showdown_sequence()

func _deal_animation() -> void:
	_anim_busy = true
	Sound.play(&"shuffle")
	var order: Array = []
	for off in range(engine.players.size()):
		var s: int = (engine.dealer + 1 + off) % engine.players.size()
		if bool(engine.players[s].in_hand):
			order.append(s)
	for rnd in range(2):
		for s in order:
			var node: Node3D = world.make_card(int(engine.players[s].hole[rnd]))
			var t: Transform3D = world.hole_transform(s, rnd)
			world.set_card_pose(node, Transform3D(t.basis, world.deck_pos + Vector3(0, 0.05, 0)), 1.0)
			world.deal_card(node, t, 0.34, 0.0, randf_range(-1.3, 1.3))
			seat_views[s].cards[rnd] = node
			world.dealer_gesture()
			Sound.play(&"deal", 0.0, randf_range(0.95, 1.1))
			await _wait(0.09)
	await _wait(0.3)
	_anim_busy = false
	_peek_until = Time.get_ticks_msec() + 2800
	_refresh_all()
	await _wait(0.3)



func _reveal_board() -> void:
	_anim_busy = true
	var fast: bool = not engine.hand_over
	while _shown_board < engine.board.size():
		var batch: int = 3 if _shown_board == 0 else 1
		world.burn_card()
		world.dealer_gesture()
		Sound.play(&"card_slide", -4.0)
		await _wait(0.35)
		for _b in range(batch):
			var k := _shown_board
			var t: Transform3D = world.board_transform(k)
			var node: Node3D = world.make_card(int(engine.board[k]))
			world.set_card_pose(node, Transform3D(t.basis, world.deck_pos + Vector3(0, 0.05, 0)), 1.0)
			world.deal_card(node, t, 0.36, 0.0, randf_range(-0.5, 0.5))
			board_nodes[k] = node
			Sound.play(&"deal")
			await _wait(0.2)
			world.flip_card(node, true, 0.28)
			world.flash_card(node)
			Sound.play(&"card_flip", 0.0, randf_range(0.95, 1.08))
			_shown_board += 1
			_refresh_tier()
			await _wait(0.12)
		if _shown_board < engine.board.size():
			await _wait(0.5 if fast else 1.0)
	_anim_busy = false
	await _wait(0.25)

func _human_turn(i: int) -> void:
	_awaiting = true
	_allowed = []
	_fold_armed = false
	_thinking = -1
	_clear_pending()
	_peek_until = Time.get_ticks_msec() + 2200
	_first_turn_help()
	if tutorial:
		await tutorial.on_event("human_turn")
	Sound.play(&"your_turn")
	_refresh_all()
	_arm_turn_timer()
	if _sleep_hands > 0:
		_sleep_autofold()
	var res: Array = await human_acted
	_awaiting = false
	_allowed = []
	var kind: String = res[0]
	var amount: int = res[1]
	coach_hide()
	spot(null)
	var comp: Dictionary = _pending.duplicate()
	_clear_pending(kind == "fold")
	_do_action(i, kind, amount)
	_human_action_fx(kind, comp)
	if tutorial:
		await tutorial.on_event("acted", kind)
	_refresh_all()
	await _wait(0.4)

func _first_turn_help() -> void:
	if not _help_seen and not is_tutorial:
		_help_seen = true
		_toast("Press H any time for the controls")

## Online: a turn that runs out of time checks (or folds) so nobody can stall the table.
func _arm_turn_timer() -> void:
	if not is_online:
		return
	_turn_id += 1
	var id := _turn_id
	get_tree().create_timer(LOCAL_TURN_SECONDS).timeout.connect(func() -> void:
		if id == _turn_id and _awaiting:
			human_acted.emit("check" if engine.can_check(HUMAN) else "fold", 0))

## Hand/chip animation for the local player's own move (check = knock, call/raise = chips).
func _human_action_fx(kind: String, comp: Dictionary) -> void:
	if kind == "check":
		world.knock_fist(colors[HUMAN], func() -> void: Sound.play(&"card_play", -2.0, randf_range(0.8, 0.95)))
	elif kind == "call" or kind == "raise":
		world.note_bet_chips(0, comp)
		world.commit_anim(kind, comp)
	if kind == "raise":
		world.punch_fov(3.5)

## Host only: waits for a remote player's intent (with a timeout; a dropped player auto-acts).
func _remote_turn(i: int) -> void:
	_thinking = i
	_refresh_all()
	var elapsed := 0.0
	var limit := 1.0 if _dropped.has(_true_seat(i)) else REMOTE_TURN_SECONDS
	while not _remote_intents.has(i) and elapsed < limit:
		await get_tree().process_frame
		elapsed += get_process_delta_time() / maxf(Engine.time_scale, 0.001)
	_thinking = -1
	var kind := "check" if engine.can_check(i) else "fold"
	var amount := 0
	if _remote_intents.has(i):
		var intent: Dictionary = _remote_intents[i]
		_remote_intents.erase(i)
		var k: String = String(intent.kind)
		if ["fold", "check", "call", "raise"].has(k):
			kind = k
			amount = int(intent.amount)
	_do_action(i, kind, amount)
	_refresh_all()
	await _wait(0.55)

func _ai_turn(i: int) -> void:
	_thinking = i
	_refresh_all()
	world.think(i)
	await _wait(randf_range(0.8, 1.5))
	_thinking = -1
	var d: Dictionary
	if tutorial:
		d = tutorial.bot_decision(engine, i)
	else:
		d = engine.ai_decide(i)
	_do_action(i, String(d.kind), int(d.raise_to))
	_refresh_all()
	await _wait(0.55)

func _do_action(i: int, kind: String, amount: int) -> void:
	var opening: bool = engine.current_bet == 0
	var msg: String = engine.act(kind, amount)
	var short := ""
	var key := kind
	match kind:
		"fold":
			short = "FOLD"
		"check", "call":
			short = "CHECK" if msg.ends_with("checks") else "CALL"
			key = "check" if short == "CHECK" else "call"
		"raise":
			short = "BET" if opening else "RAISE"
	var allin: bool = bool(engine.players[i].all_in) and kind != "fold"
	if allin:
		short = "ALL-IN"
		key = "allin"
	_action_visuals(i, kind, short, key, allin)
	_broadcast({"type": "action", "seat": i, "kind": kind, "short": short, "key": key, "allin": allin})
	_log(msg)

## Pop text, sounds, reactions and fold/check/call animations for one player's move.
func _action_visuals(i: int, kind: String, short: String, key: String, allin: bool) -> void:
	match kind:
		"fold":
			Sound.play(&"skip")
		"check", "call":
			Sound.play(&"chip" if key == "call" else &"card_flip")
		"raise":
			Sound.play(&"chip", 2.0, 0.9)
	if allin:
		world.punch_fov(6.0)
		Sound.play(&"heartbeat", -4.0)
	_pop_text(_seat_pos(i), short, colors[i].lightened(0.3))
	if kind == "fold":
		Sound.play(&"card_slide", 0.0, randf_range(0.9, 1.1))
		for k in range(2):
			world.toss(seat_views[i].cards[k], 0.08 * k)
		if i != HUMAN:
			world.emote(i, "emote_cross")
		else:
			world.punch_fov(-4.0)
	if i != HUMAN:
		if not is_online:
			_bubble(i, _pick_bark(key))
		match key:
			"check":
				world.ripple(world.bet_pos(i), Color(1, 1, 1))
				Sound.play(&"card_play", -2.0, randf_range(0.8, 0.95))
				world.react(i, &"play")
			"call":
				world.ripple(world.bet_pos(i), Color(0.8, 1, 0.85))
			"raise", "allin":
				world.react(i, &"play")

func _pick_bark(key: String) -> String:
	var lines: Array = BARKS.get(key, ["..."])
	return String(lines[randi() % lines.size()])

## Speech bubble over an opponent's seat.
func _bubble(i: int, text: String) -> void:
	var l := UIStyle.make_label(text, 15, UIStyle.CREAM)
	l.add_theme_stylebox_override("normal", UIStyle.panel_style(Color(0.96, 0.93, 0.86, 0.95), UIStyle.BRASS_DIM, 12, 1))
	l.add_theme_color_override("font_color", UIStyle.INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	l.reset_size()
	l.position = _seat_pos(i) + Vector2(-l.size.x / 2.0, -74.0)
	l.scale = Vector2.ZERO
	l.pivot_offset = l.size / 2.0
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)

# ── Showdown ──────────────────────────────────────────────────────────

func _show_order() -> Array:
	var out: Array = []
	var n: int = engine.players.size()
	for off in range(1, n + 1):
		var i: int = (engine.dealer + off) % n
		var p: Dictionary = engine.players[i]
		if bool(p.in_hand) and not bool(p.folded):
			out.append(i)
	return out

func _showdown_sequence() -> void:
	_thinking = -1
	_awaiting = false
	_force_up = true
	if engine.showdown_reached:
		# Everyone still in throws their cards forward, one after another, so all can see them.
		await _wait(0.5)
		for i in _show_order():
			var p: Dictionary = engine.players[i]
			_revealed[i] = true
			for k in range(2):
				var nd: Variant = seat_views[i].cards[k]
				if nd != null and i != HUMAN:
					world.set_card_face(nd, int(p.hole[k]))
			world.show_hole(seat_views[i].cards, i)
			Sound.play(&"card_flip", 0.0, randf_range(0.92, 1.05))
			Sound.play(&"card_slide", -2.0)
			if i != HUMAN:
				world.react(i, &"play")
			var ev: Dictionary = Eval.evaluate(p.hole + engine.board)
			_status_text[i] = String(ev.name)
			_refresh_all()
			await _wait(1.0)
		await _wait(1.0)
	var lines: Array = []
	var first := true
	for r in engine.results:
		var winners: Array = r.winners
		for w in winners:
			_winners[int(w)] = true
		var names: Array = []
		for w in winners:
			names.append("You" if int(w) == HUMAN else String(engine.players[int(w)].name))
		var who: String = " and ".join(names)
		var verb: String = "win" if names.size() == 1 and names[0] == "You" else "wins"
		if names.size() > 1:
			verb = "split"
		var line := "[b]%s %s %d[/b]" % [who, verb, int(r.amount)]
		if String(r.hand) != "":
			line += " with [color=#ecd394]%s[/color]" % String(r.hand)
		else:
			line += " (everyone else folded)"
		lines.append(line)
		if first:
			first = false
			if String(r.hand) != "":
				_tier_cat = int(Eval.evaluate(r.best).cat)
			_highlight_winning_cards(r)
	_hand_summary = "\n".join(lines)
	for w in _winners:
		_pop_text(_seat_pos(int(w)) + Vector2(0, -40), "WINNER", Color("ffd877"))
	# Winners' stacks keep their pre-award size until the pot slides over to them.
	var gains: Dictionary = {}
	for r2 in engine.results:
		var ws: Array = r2.winners
		for w2 in ws:
			gains[int(w2)] = int(gains.get(int(w2), 0)) + int(int(r2.amount) / ws.size())
	_chip_hold.clear()
	for k in gains:
		_chip_hold[int(k)] = int(engine.players[int(k)].chips) - int(gains[k])
	_refresh_all()
	_refresh_tier()
	await _winner_cinematic()
	if tutorial:
		await tutorial.on_event("showdown")

## The round's winner gets the spotlight: the camera swings to them, they celebrate, the pot slides over.
func _winner_cinematic() -> void:
	if engine.results.is_empty():
		return
	var r0: Dictionary = engine.results[0]
	var w: int = int((r0.winners as Array)[0])
	var human_won: bool = _winners.has(HUMAN)
	_cinematic = true
	var from := Vector2(_look_yaw, _look_pitch)
	var target_pt: Vector3 = world.head_anchor(w) - Vector3(0, world.char_scale * 0.75, 0) if w != HUMAN else Vector3(world.center.x, world.surface_y, world.center.z)
	var ang: Vector2 = world.look_angles_to(target_pt)
	ang.x = clampf(ang.x, -130.0, 130.0)
	ang.y = clampf(ang.y, -40.0, 8.0)
	_show_winner_banner(r0, w)
	var tw := create_tween()
	tw.tween_method(func(v: Vector2) -> void: world.set_look(v.x, v.y), from, ang, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	world.punch_fov(8.0)
	world.confetti(world.head_anchor(w) if w != HUMAN else world.ring_point() + Vector3(0, world.char_scale * 0.5, 0))
	Sound.play(&"win" if human_won else &"lose")
	world.react(w, &"win")
	if w != HUMAN and not is_online:
		_bubble(w, _pick_bark("win"))
	for k in range(engine.players.size()):
		if k != w and k != HUMAN and not bool(engine.players[k].folded) and bool(engine.players[k].in_hand) and engine.showdown_reached:
			world.react(k, &"hit")
	await _wait(2.0)
	world.sweep(world.rack_point(100) if w == HUMAN else world.stack_point(w, 100))
	Sound.play(&"chip", 0.0, 0.8)
	await _wait(1.0)
	_pot_hidden = true
	_chip_hold.clear()
	_refresh_all()
	var back := create_tween()
	back.tween_method(func(v: Vector2) -> void: world.set_look(v.x, v.y), ang, from, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await back.finished
	_cinematic = false

func _show_winner_banner(r: Dictionary, w: int) -> void:
	var who: String = "YOU" if w == HUMAN else String(engine.players[w].name).to_upper()
	if (r.winners as Array).size() > 1:
		winner_title.text = "SPLIT POT  %d" % int(r.amount)
	else:
		winner_title.text = "%s WIN%s  %d" % [who, "" if who == "YOU" else "S", int(r.amount)]
	winner_sub.text = String(r.hand) if String(r.hand) != "" else "everyone else folded"
	winner_title.add_theme_color_override("font_color", colors[w].lightened(0.35) if w != HUMAN else Color("ffd877"))
	winner_banner.visible = true
	winner_banner.reset_size()
	winner_banner.position = Vector2(_table_rect().get_center().x - winner_banner.size.x / 2.0, TOP_H + 34.0)
	winner_banner.pivot_offset = winner_banner.size / 2.0
	winner_banner.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(winner_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _highlight_winning_cards(r: Dictionary) -> void:
	var best: Array = r.best
	if best.is_empty():
		return
	var all_nodes: Array = []
	for k in range(_shown_board):
		all_nodes.append(board_nodes[k])
	for i in range(seat_views.size()):
		var p: Dictionary = engine.players[i]
		if bool(p.in_hand) and not bool(p.folded):
			for nd in seat_views[i].cards:
				all_nodes.append(nd)
	for nd in all_nodes:
		if nd == null or not is_instance_valid(nd):
			continue
		var hit: bool = best.has(int(nd.get_meta(&"card")))
		world.set_card_state(nd, hit, not hit)
		world.lift_card(nd, hit)

func _wait_next_hand() -> void:
	if is_online:
		await _wait(4.0)
		return
	_waiting_next = true
	_refresh_all()
	await next_pressed
	_waiting_next = false

func _show_match_end() -> void:
	if is_online:
		var champ := ""
		for p in engine.players:
			if int(p.chips) > 0:
				champ = String(p.name)
		var mine_alive: bool = int(engine.players[HUMAN].chips) > 0
		_popup("YOU TAKE THE TABLE" if mine_alive else "%s TAKES THE TABLE" % champ.to_upper(), "Everyone else is out of chips.", [
			["BACK TO LOBBY", &"primary", func() -> void: get_tree().change_scene_to_file("res://scenes/lobby.tscn")],
			["MAIN MENU", &"secondary", _to_main_menu],
		])
		return
	var human_alive: bool = int(engine.players[HUMAN].chips) > 0
	var title := "YOU CLEANED UP THE TABLE" if human_alive else "YOU'RE OUT OF CHIPS"
	var body := "Every opponent is broke. Nice work." if human_alive else "The table took your last chip. It happens to everyone, even the pros."
	_popup(title, body, [
		["PLAY AGAIN", &"primary", func() -> void: get_tree().reload_current_scene()],
		["MAIN MENU", &"secondary", _to_main_menu],
	])

# ── Human input ───────────────────────────────────────────────────────

func _permitted(kind: String) -> bool:
	if not _awaiting or _paused or _acting or _hands_busy_now():
		return false
	if _allowed.is_empty():
		return true
	if kind == "check":
		kind = "call"
	return _allowed.has(kind)

func _on_fold() -> void:
	if not _permitted("fold"):
		Sound.play(&"invalid")
		if _awaiting and not _allowed.is_empty():
			_toast("Not yet. Follow the coach box.")
		return
	if engine.can_check(HUMAN) and not _fold_armed:
		_fold_armed = true
		_toast("You can CHECK for free. Fold again if you really want to.")
		return
	human_acted.emit("fold", 0)

func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	if Keybinds.matches(ke, &"hints"):
		_toggle_hints()
		return
	if Keybinds.matches(ke, &"rankings"):
		_toggle_rankings()
		return
	if vices != null and not is_tutorial and ke.keycode in [KEY_S, KEY_W, KEY_B] and vices.handle_key(ke):
		return
	match ke.keycode:
		KEY_ESCAPE:
			if _menu_popup:
				_close_menu()
			else:
				_open_menu()
		KEY_H:
			help_panel.visible = not help_panel.visible
		KEY_TAB:
			_cursor_free = not _cursor_free
			_toast("Cursor free. Press TAB to look around again." if _cursor_free else "Mouse look on.")
			_sync_mouse()
			_refresh_actions()
		KEY_F:
			_on_fold()
		KEY_C:
			if engine.can_check(HUMAN):
				_auto_stack(0)
			else:
				_auto_stack(engine.to_call(HUMAN))
		KEY_R:
			if _awaiting and engine.can_raise(HUMAN):
				_auto_stack(engine.min_raise_to(HUMAN) - int(engine.players[HUMAN].bet))
		KEY_A:
			if _awaiting:
				_auto_stack(int(engine.players[HUMAN].chips))
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_add_chip(World.DENOMS[ke.keycode - KEY_1])
		KEY_BACKSPACE:
			_remove_chip()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if coach_panel.visible and _coach_wait:
				coach_continued.emit()
			elif _waiting_next:
				next_pressed.emit()
			else:
				_commit_pile()

# ── Online (host-authoritative; clients get per-seat snapshots) ─────

func _true_seat(rel: int) -> int:
	return (own_seat + rel) % engine.players.size()

func _rel_seat(true_seat: int, for_seat: int) -> int:
	if true_seat < 0:
		return -1
	return posmod(true_seat - for_seat, engine.players.size())

func _peers() -> Array:
	var out: Array = []
	if _eos == null:
		return out
	for entry in _eos.roster:
		if int(entry.peer_id) != 1 and bool(entry.connected):
			out.append(entry)
	return out

## Host: wait until every connected client has loaded the scene.
func _wait_for_clients() -> void:
	var waited := 0.0
	while waited < 25.0:
		var all_in := true
		for entry in _peers():
			if not _hello.has(int(entry.seat)):
				all_in = false
		if all_in:
			break
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(0.6).timeout

func _make_snapshot(for_seat: int, ev: Dictionary) -> Dictionary:
	var n: int = engine.players.size()
	var plist: Array = []
	for k in range(n):
		var seat: int = (for_seat + k) % n
		var p: Dictionary = engine.players[seat]
		var show_hole: bool = seat == for_seat or (engine.hand_over and engine.showdown_reached and bool(p.in_hand) and not bool(p.folded))
		var hole: Array = []
		if bool(p.in_hand) and (p.hole as Array).size() == 2:
			hole = (p.hole as Array).duplicate() if show_hole else [-1, -1]
		plist.append({"name": p.name, "chips": p.chips, "bet": p.bet, "total": p.total, "folded": p.folded, "all_in": p.all_in, "in_hand": p.in_hand, "hole": hole})
	var res: Array = []
	for r in engine.results:
		var ws: Array = []
		for w in r.winners:
			ws.append(_rel_seat(int(w), for_seat))
		res.append({"winners": ws, "amount": r.amount, "hand": r.hand, "best": r.best})
	var e2: Dictionary = ev.duplicate()
	if e2.has("seat"):
		e2["seat"] = _rel_seat(int(e2.seat), for_seat)
	return {
		"players": plist, "board": engine.board.duplicate(), "stage": engine.stage,
		"dealer": _rel_seat(engine.dealer, for_seat), "sb": _rel_seat(engine.sb_index, for_seat), "bb": _rel_seat(engine.bb_index, for_seat),
		"current": _rel_seat(engine.current, for_seat), "current_bet": engine.current_bet, "min_raise": engine.min_raise,
		"small_blind": engine.small_blind, "big_blind": engine.big_blind, "hand_number": engine.hand_number,
		"hand_over": engine.hand_over, "showdown": engine.showdown_reached, "results": res, "event": e2,
	}

func _broadcast(ev: Dictionary) -> void:
	if not (is_online and is_host):
		return
	for entry in _peers():
		_send_snapshot_to(int(entry.peer_id), _make_snapshot(int(entry.seat), ev))

func _send_snapshot_to(peer_id: int, snap: Dictionary) -> void:
	var raw := var_to_bytes(snap)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	_snap_seq += 1
	var total: int = ceili(packed.size() / float(SNAP_CHUNK))
	for i in range(total):
		var part := packed.slice(i * SNAP_CHUNK, mini((i + 1) * SNAP_CHUNK, packed.size()))
		rpc_id(peer_id, "_rpc_snapshot_chunk", _snap_seq, i, total, raw.size(), part)

@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot_chunk(seq: int, idx: int, total: int, raw_size: int, part: PackedByteArray) -> void:
	if not is_online or seq <= _snap_applied:
		return
	var entry: Dictionary = _snap_rx.get(seq, {})
	if entry.is_empty():
		entry = {"total": total, "parts": {}}
		_snap_rx[seq] = entry
	entry.parts[idx] = part
	if entry.parts.size() < total:
		return
	var packed := PackedByteArray()
	for k in range(total):
		packed.append_array(entry.parts[k])
	_snap_applied = seq
	for k in _snap_rx.keys():
		if int(k) <= seq:
			_snap_rx.erase(k)
	var snap: Variant = bytes_to_var(packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD))
	if snap is Dictionary:
		_got_first = true
		_snap_queue.append(snap)

var _got_first: bool = false

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello() -> void:
	if not is_online or not is_host or _eos == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var seat: int = _eos.get_seat_for_peer(sender)
	if seat >= 0:
		_hello[seat] = true
		_eos.mark_client_in_game(sender)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(kind: String, amount: int) -> void:
	if not is_online or not is_host or _eos == null:
		return
	var seat: int = _eos.get_seat_for_peer(multiplayer.get_remote_sender_id())
	# Accept it whenever it is that seat's turn (the host may still be animating the previous move).
	if seat < 0 or engine.hand_over or seat != engine.current:
		return
	_remote_intents[seat] = {"kind": kind, "amount": amount}

# Client side ----------------------------------------------------------

func _client_start() -> void:
	human_acted.connect(_client_on_acted)
	_client_worker()
	while not _got_first:
		rpc_id(1, "_rpc_hello")
		await get_tree().create_timer(1.5).timeout

func _client_on_acted(kind: String, amount: int) -> void:
	if not _awaiting:
		return
	_awaiting = false
	_allowed = []
	_turn_id += 1
	var comp: Dictionary = _pending.duplicate()
	_clear_pending(kind == "fold")
	_human_action_fx(kind, comp)
	_refresh_all()
	rpc_id(1, "_rpc_intent", kind, amount)

func _client_worker() -> void:
	while true:
		while _snap_queue.is_empty():
			await get_tree().process_frame
		var snap: Dictionary = _snap_queue.pop_front()
		await _client_present(snap)

func _apply_snapshot_state(s: Dictionary) -> void:
	var arr: Array[Dictionary] = []
	for pd in s.players:
		var d: Dictionary = (pd as Dictionary).duplicate()
		var hole: Array[int] = []
		for c in d.hole:
			hole.append(int(c))
		d["hole"] = hole
		d["human"] = arr.size() == 0
		arr.append(d)
	engine.players = arr
	var board: Array[int] = []
	for c in s.board:
		board.append(int(c))
	engine.board = board
	engine.stage = int(s.stage)
	engine.dealer = int(s.dealer)
	engine.sb_index = int(s.sb)
	engine.bb_index = int(s.bb)
	engine.current = int(s.current)
	engine.current_bet = int(s.current_bet)
	engine.min_raise = int(s.min_raise)
	engine.small_blind = int(s.small_blind)
	engine.big_blind = int(s.big_blind)
	engine.hand_number = int(s.hand_number)
	engine.hand_over = bool(s.hand_over)
	engine.showdown_reached = bool(s.showdown)
	var res: Array[Dictionary] = []
	for r in s.results:
		res.append({"winners": r.winners, "amount": int(r.amount), "hand": String(r.hand), "best": r.best})
	engine.results = res

var _phase: String = ""

func _client_present(s: Dictionary) -> void:
	var ev: Dictionary = s.event
	_phase = "start " + String(ev.type)
	var old_bb: int = engine.big_blind
	_apply_snapshot_state(s)
	match String(ev.type):
		"new_hand":
			if engine.big_blind != old_bb and engine.hand_number > 1:
				_toast("Blinds go up to %d / %d" % [engine.small_blind, engine.big_blind])
			_reset_hand_visuals()
			_refresh_all()
			await _deal_animation()
			_dealing = false
		"action":
			var seat: int = int(ev.seat)
			_action_visuals(seat, String(ev.kind), String(ev.short), String(ev.key), bool(ev.allin))
		"match_over":
			_refresh_all()
			await _show_match_end()
			return
	_phase = "reveal"
	_refresh_all()
	if engine.board.size() > _shown_board:
		await _reveal_board()
	_phase = "post"
	if engine.hand_over and not _hand_presented:
		_hand_presented = true
		await _showdown_sequence()
		return
	if engine.hand_over:
		return
	var mine: bool = engine.current == HUMAN
	_thinking = engine.current if not mine else -1
	if mine:
		_awaiting = true
		_allowed = []
		_fold_armed = false
		_clear_pending()
		_peek_until = Time.get_ticks_msec() + 2200
		_first_turn_help()
		Sound.play(&"your_turn")
		_arm_turn_timer_client()
		if _sleep_hands > 0:
			_sleep_autofold()
	_refresh_all()
	if int(engine.players[HUMAN].chips) <= 0 and not _busted_told:
		_busted_told = true
		_toast("You're out of chips. Stick around and watch the rest.")

func _arm_turn_timer_client() -> void:
	_turn_id += 1
	var id := _turn_id
	get_tree().create_timer(REMOTE_TURN_SECONDS - 3.0).timeout.connect(func() -> void:
		if id == _turn_id and _awaiting:
			human_acted.emit("check" if engine.can_check(HUMAN) else "fold", 0))

func _on_player_left(seat: int, display_name: String) -> void:
	if not is_host:
		return
	_dropped[seat] = true
	_toast("%s left. Their hands auto-fold." % display_name)
	var humans_left := 1
	for entry in _eos.roster:
		if int(entry.seat) != 0 and not _dropped.has(int(entry.seat)):
			humans_left += 1
	if humans_left < 2:
		_popup("EVERYONE LEFT", "Nobody else is at the table.", [
			["MAIN MENU", &"primary", _to_main_menu],
		])

func _on_host_lost() -> void:
	_popup("THE HOST LEFT", "The game ended.", [
		["MAIN MENU", &"primary", _to_main_menu],
	])

# ── Hints (saved in Settings) ───────────────────────────────────────

func _update_hints_button() -> void:
	pass

func _toggle_hints() -> void:
	_coach_on = not _coach_on
	var st: Node = UIStyle.settings()
	if st != null:
		st.set("poker_hints", _coach_on)
		st.call("commit")
	_toast("Hints %s  ·  [%s] toggles" % ["ON" if _coach_on else "OFF", Keybinds.label(&"hints")])
	_refresh_all()

## Settings changed elsewhere (the Settings panel): follow it.
func _on_settings_changed() -> void:
	var st: Node = UIStyle.settings()
	if st == null:
		return
	var on: bool = bool(st.get("poker_hints"))
	if on != _coach_on:
		_coach_on = on
		_refresh_all()

# ── Vices (smoking / drinking), drunk, passing out, sync ────────────

## A pulsing glow around the screen while the action is on you.
func _update_turn_indicator() -> void:
	if _turn_border == null or engine == null:
		return
	var mine: bool = _awaiting and engine.current == HUMAN and not engine.hand_over and not bool(engine.players[HUMAN].folded)
	_turn_border.visible = mine
	if mine:
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
		_turn_border.modulate.a = pulse
		_turn_style.border_color = Color(colors[HUMAN].lightened(0.2), 0.95)
		_turn_style.shadow_color = Color(colors[HUMAN], 0.45)

## The permanent pot capsule: the pot (0 once it has been paid out), the street, and the chips in your pile.
func _update_pot_hud() -> void:
	if stage_label == null or engine == null:
		return
	var pot_now: int = 0 if _pot_hidden else engine.pot()
	var txt := "POT  %d" % pot_now
	var mine: int = _pending_value()
	if mine > 0:
		txt += "  +%d" % mine
	var stg := _stage_text()
	if stg != "":
		txt += "     %s" % stg
	if stage_label.text != txt:
		stage_label.text = txt
		stage_label.reset_size()
		stage_label.size.x = maxf(stage_label.size.x, 190.0)
		stage_label.position = Vector2(_table_rect().get_center().x - stage_label.size.x / 2.0, TOP_H - 6.0)
	_update_pile_label()

## A running total over your pile so adding chips visibly adds up.
func _update_pile_label() -> void:
	if pile_label == null or engine == null:
		return
	var v: int = _pending_value()
	pile_label.visible = v > 0
	if v > 0:
		var owe: int = engine.to_call(HUMAN)
		var txt := "YOUR BET  %d" % v
		if owe > 0:
			txt += "   (call %d)" % owe
		pile_label.text = txt
		pile_label.reset_size()

func _fmt_chips(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## My name and chip count live in one spot (bottom left), nowhere else.
func _update_me_hud(p: Dictionary, role: String, active: bool) -> void:
	if me_hud == null:
		return
	me_name.text = String(p.name).to_upper() if String(p.name) != "You" else "YOU"
	me_name.add_theme_color_override("font_color", colors[HUMAN].lightened(0.3))
	me_chips.text = _fmt_chips(int(p.chips))
	me_role.text = role if role != "" else "chips"
	me_role.add_theme_color_override("font_color", UIStyle.BRASS_LIGHT if active else UIStyle.MUTED)
	var border: Color = colors[HUMAN] if active else UIStyle.BRASS_DIM
	me_hud.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(UIStyle.INK, 0.88), border, 12, 3 if active else 2))
	me_hud.reset_size()
	me_hud.position = Vector2(12.0, size.y - ACTION_H - 16.0 - me_hud.size.y)

func _hands_busy_now() -> bool:
	return vices != null and vices.hands_busy

func vice_blocked() -> bool:
	return _paused or is_tutorial or _sleep_hands > 0 or _dealing or _cinematic or has_node("PokerModal")

func is_sleeping() -> bool:
	return _sleep_hands > 0

func vice_toast(text: String) -> void:
	_toast(text)

func vice_pass_out() -> void:
	if _sleep_hands > 0:
		return
	vices.force_end()
	_sleep_hands = 2
	Sound.play(&"banner")
	_toast("You have had too much... everything goes dark.")
	if _sleep_cover == null:
		_sleep_cover = ColorRect.new()
		_sleep_cover.color = Color(0, 0, 0, 1)
		_sleep_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sleep_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UIStyle.make_label("PASSED OUT\nYou will sleep through this hand and the next", 24, UIStyle.CREAM, true)
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.grow_vertical = Control.GROW_DIRECTION_BOTH
		_sleep_cover.add_child(l)
		add_child(_sleep_cover)
	_sleep_cover.modulate.a = 0.0
	create_tween().tween_property(_sleep_cover, "modulate:a", 0.93, 1.2)
	if _awaiting:
		_sleep_autofold()

func _wake_up() -> void:
	_sleep_hands = 0
	vices.drunk = vices.WAKE_DRUNK
	_toast("You come to, head pounding. The room still spins.")
	if _sleep_cover != null:
		var cover := _sleep_cover
		_sleep_cover = null
		var tw := create_tween()
		tw.tween_property(cover, "modulate:a", 0.0, 1.6)
		tw.tween_callback(cover.queue_free)

## A sleeping player just checks (or folds) when the action reaches them.
func _sleep_autofold() -> void:
	await _wait(0.9)
	if _awaiting and _sleep_hands > 0:
		human_acted.emit("check" if engine.can_check(HUMAN) else "fold", 0)

func _tick_sleep_at_hand_start() -> void:
	if _sleep_hands > 0:
		_sleep_hands -= 1
		if _sleep_hands == 0:
			_wake_up()

## Local vice step -> everyone (through the host). Seats on the wire are the real (host) seat numbers.
func net_vice(event: String, data: Dictionary = {}) -> void:
	if not is_online or is_tutorial:
		return
	if is_host:
		rpc("_rpc_vice_play", own_seat, event, data)
	else:
		rpc_id(1, "_rpc_vice", event, data)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_vice(event: String, data: Dictionary) -> void:
	if not is_online or not is_host or _eos == null:
		return
	var seat: int = _eos.get_seat_for_peer(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	vices.play_remote(_rel_seat(seat, own_seat), event, data)
	rpc("_rpc_vice_play", seat, event, data)

@rpc("authority", "call_remote", "reliable")
func _rpc_vice_play(true_seat: int, event: String, data: Dictionary) -> void:
	if not is_online:
		return
	var rel := _rel_seat(true_seat, own_seat)
	if rel == HUMAN:
		return
	vices.play_remote(rel, event, data)

# ── First-person controls: mouse look, chips, cards ───────────────────

const PROMPT_NONE := ""

func _looking() -> bool:
	if _cursor_free or _paused or has_node("PokerModal") or (vices != null and vices.picker_open()):
		return false
	return DisplayServer.window_is_focused()

func _pending_value() -> int:
	var v := 0
	for d in _pending:
		v += int(d) * int(_pending[d])
	return v

## Empties the pile. refund = true gives the chips back to your stack (a cancelled bet); false = they were spent.
func _clear_pending(refund: bool = true) -> void:
	if refund and world != null:
		for d in _pending:
			world.bank_of(0).give(int(d), int(_pending[d]))
	_pending.clear()
	_pending_order.clear()
	if world != null:
		world.set_pending({})
		world.render_bank(0)
	_update_pot_hud()

func _sync_pile() -> void:
	world.set_pending(_pending)
	world.render_bank(0)
	_update_pot_hud()

func _add_chip(d: int) -> void:
	if _hands_busy_now():
		_toast("Your hands are full. Put it down first.")
		return
	if not _awaiting or _paused or _acting:
		Sound.play(&"invalid")
		_toast("Wait for your turn.")
		return
	var remaining: int = int(engine.players[HUMAN].chips) - _pending_value()
	if d > remaining or not world.bank_of(0).take_denom(d):
		Sound.play(&"invalid")
		_toast("You don't have a %d chip's worth left." % d)
		return
	_pending[d] = int(_pending.get(d, 0)) + 1
	_pending_order.append(d)
	world.fly_chip(world.rack_point(d), world.pending_point() + Vector3(0, 0.03, 0), d, 0.25)
	Sound.play(&"chip", -2.0, randf_range(0.9, 1.15))
	_sync_pile()

func _remove_chip() -> void:
	if _pending_order.is_empty():
		return
	var d: int = _pending_order.pop_back()
	_pending[d] = int(_pending[d]) - 1
	if int(_pending[d]) <= 0:
		_pending.erase(d)
	world.bank_of(0).give(d)
	world.fly_chip(world.pending_point(), world.rack_point(d), d, 0.22)
	Sound.play(&"chip", -6.0, 1.2)
	_sync_pile()

func _commit_pile() -> void:
	if not _awaiting or _paused or _acting:
		Sound.play(&"invalid")
		return
	var p: Dictionary = engine.players[HUMAN]
	var v: int = _pending_value()
	var owe: int = engine.to_call(HUMAN)
	var kind := ""
	var amt := 0
	if v == 0:
		if engine.can_check(HUMAN):
			kind = "check"
		else:
			Sound.play(&"invalid")
			_toast("Stack %d in the pile to CALL, or click your cards to fold." % owe)
			return
	elif v < owe:
		Sound.play(&"invalid")
		_toast("That's not enough. It costs %d to call." % owe)
		return
	elif v == owe:
		kind = "call"
	else:
		var raise_to: int = int(p.bet) + v
		if raise_to < engine.min_raise_to(HUMAN) and v < int(p.chips):
			Sound.play(&"invalid")
			_toast("Minimum raise is up to %d. Add more chips." % engine.min_raise_to(HUMAN))
			return
		kind = "raise"
		amt = raise_to
	if not _permitted(kind):
		Sound.play(&"invalid")
		_toast("Not that. Follow the coach box.")
		return
	Sound.play(&"chip", 2.0, 0.9)
	human_acted.emit(kind, amt)

func _auto_stack(value: int) -> void:
	if not _awaiting or _paused or _acting:
		return
	_clear_pending()
	if value <= 0:
		_commit_pile()
		return
	_acting = true
	# Real chips leave your stack (making change if needed) and land in the pile.
	var removed: Dictionary = world.bank_of(0).take(value)
	var n := 0
	for d in [500, 100, 25, 5, 1]:
		for _k in range(int(removed.get(d, 0))):
			_pending[d] = int(_pending.get(d, 0)) + 1
			_pending_order.append(d)
			world.fly_chip(world.rack_point(d), world.pending_point() + Vector3(0, 0.03, 0), d, 0.25, Callable(), 0.04 * mini(n, 8))
			n += 1
	Sound.play(&"chip", -2.0)
	_sync_pile()
	await _wait(0.35)
	_acting = false
	_commit_pile()

func _click_cards() -> void:
	_on_fold()

func _on_click() -> void:
	if _waiting_next:
		next_pressed.emit()
		return
	match String(_hover.get("kind", "")):
		"chip":
			_add_chip(int(_hover.d))
		"pile":
			_commit_pile()
		"cards":
			_click_cards()

func _input(event: InputEvent) -> void:
	if vices != null and vices.wheel(event):
		get_viewport().set_input_as_handled()
		return
	if not _looking():
		return
	if event is InputEventMouseMotion:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if not _cinematic:
			_look_yaw = clampf(_look_yaw - rel.x * Keybinds.sens(), -LOOK_YAW, LOOK_YAW)
			_look_pitch = clampf(_look_pitch - rel.y * Keybinds.sens(), -LOOK_PITCH_DOWN, LOOK_PITCH_UP)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_remove_chip()
		get_viewport().set_input_as_handled()

func _update_aim() -> void:
	_hover = {}
	var looking := _looking()
	crosshair.visible = looking and not _cinematic
	prompt_label.visible = crosshair.visible
	if not looking or _cinematic:
		world.highlight_rack(0)
		return
	var c := size * 0.5
	var best_d := 38.0
	for d in World.DENOMS:
		var pt: Vector3 = world.rack_point(d)
		if world.is_behind(pt):
			continue
		var dist: float = c.distance_to(world.project(pt))
		if dist < best_d:
			best_d = dist
			_hover = {"kind": "chip", "d": d}
	if _hover.is_empty():
		var rp: Vector3 = world.ring_point()
		if not world.is_behind(rp) and c.distance_to(world.project(rp)) < 44.0:
			_hover = {"kind": "pile"}
	if _hover.is_empty() and not _anim_busy and world.has_hole_cards(seat_views[HUMAN].cards):
		if human_card_rect().grow(18.0).has_point(c):
			_hover = {"kind": "cards"}
	world.highlight_rack(int(_hover.get("d", 0)) if String(_hover.get("kind", "")) == "chip" else 0)
	var txt := ""
	match String(_hover.get("kind", "")):
		"chip":
			txt = "CLICK: add a %d chip" % int(_hover.d)
		"pile":
			var v := _pending_value()
			if _waiting_next:
				txt = ""
			elif v > 0:
				txt = "CLICK: push %d into the pot" % v
			elif _awaiting and engine.can_check(HUMAN):
				txt = "CLICK: check"
			else:
				txt = "Add chips to call"
		"cards":
			txt = "CLICK: fold   ·   Q: look at your cards"
	prompt_label.text = txt
	prompt_label.position = c + Vector2(-180, 22)
	var over: bool = not _hover.is_empty()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(UIStyle.BRASS_LIGHT, 0.95) if over else Color(1, 1, 1, 0.6)
	cs.set_corner_radius_all(4)
	crosshair.add_theme_stylebox_override("panel", cs)
	crosshair.scale = Vector2.ONE * (1.9 if over else 1.0)

func _update_peek(delta: float) -> void:
	if _force_up:
		return
	var nodes: Array = seat_views[HUMAN].cards
	if _anim_busy or not world.has_hole_cards(nodes) or bool(engine.players[HUMAN].folded):
		return
	var up: bool = String(_hover.get("kind", "")) == "cards" or Input.is_key_pressed(KEY_Q)
	var want: float = 1.0 if up else 0.0
	var prev := _peek_t
	_peek_t = move_toward(_peek_t, want, delta * 5.0)
	if _peek_t != prev or (_peek_t == 0.0 and prev == 0.0 and false):
		for k in range(2):
			world.set_peek(nodes[k], k, _peek_t)

func _sync_mouse() -> void:
	var want := Input.MOUSE_MODE_CAPTURED if _looking() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want
		_refresh_actions()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ── Refresh ───────────────────────────────────────────────────────────

func _refresh_all() -> void:
	if engine == null or seat_views.is_empty():
		return
	var lvl := "Blinds %d/%d" % [engine.small_blind, engine.big_blind]
	top_title.text = "TEXAS HOLD'EM   ·   %s   ·   Hand %d" % [lvl, engine.hand_number]
	pot_label.text = "POT  %d" % engine.pot()
	_update_pot_hud()
	var names := ["PRE-FLOP", "FLOP", "TURN", "RIVER", "SHOWDOWN"]
	for i in range(engine.players.size()):
		var p: Dictionary = engine.players[i]
		var sv: Dictionary = seat_views[i]
		var out: bool = not bool(p.in_hand)
		var folded: bool = bool(p.folded)
		var panel: PanelContainer = sv.panel
		panel.visible = i != HUMAN
		var active: bool = i == engine.current and not engine.hand_over
		var border: Color = UIStyle.BRASS_LIGHT if active else (Color("ffd877") if _winners.has(i) else UIStyle.BRASS_DIM)
		panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(UIStyle.INK, 0.92), border, 10, 3 if (active or _winners.has(i)) else 1))
		panel.modulate = Color(1, 1, 1, 0.45) if (folded or out) else Color.WHITE
		(sv.chips as Label).text = "%d chips" % int(p.chips) if not out else "OUT"
		var role := ""
		if _status_text.has(i):
			role = String(_status_text[i])
		elif out:
			role = "eliminated"
		elif folded:
			role = "folded"
		elif bool(p.all_in):
			role = "ALL-IN"
		elif _thinking == i:
			role = "thinking..."
		elif i == engine.current and not engine.hand_over and i == HUMAN:
			role = "YOUR TURN"
		else:
			var tags: Array = []
			if i == engine.dealer:
				tags.append("Dealer")
			if i == engine.sb_index:
				tags.append("Small blind")
			elif i == engine.bb_index:
				tags.append("Big blind")
			role = " · ".join(tags)
		(sv.role as Label).text = role
		if i == HUMAN:
			_update_me_hud(p, role, active)
		(sv.role as Label).add_theme_color_override("font_color", UIStyle.BRASS_LIGHT if (active or role == "ALL-IN") else UIStyle.MUTED)
		var d: Label = sv.dealer
		d.visible = false
		var bet: Label = sv.bet
		bet.visible = int(p.bet) > 0
		bet.text = str(int(p.bet))
		for k in range(2):
			var nd: Variant = sv.cards[k]
			if nd != null and is_instance_valid(nd) and out:
				(nd as Node3D).visible = false
		if i != HUMAN:
			world.set_turn(i, active)
		var shown: int = int(_chip_hold.get(i, int(p.chips)))
		var delta: Dictionary = world.sync_bank(i, shown - (_pending_value() if i == HUMAN else 0))
		world.set_bet(i, 0 if _pot_hidden else int(p.bet), delta.removed if i != HUMAN else {})
	if engine.hand_number > 0 and _button_seat != engine.dealer:
		_button_seat = engine.dealer
		world.set_dealer_button(engine.dealer)
	var bets := 0
	for p2 in engine.players:
		bets += int(p2.bet)
	world.set_pot(0 if _pot_hidden else engine.pot() - bets)
	world.pulse_ring(_awaiting and engine.current == HUMAN and not engine.hand_over)
	for pnl in seat_views:
		(pnl.panel as Control).reset_size()
	_layout_panels_only()
	_refresh_tier()
	_refresh_actions()
	_refresh_hint()

func _layout_panels_only() -> void:
	if seat_views.is_empty() or world == null:
		return
	for i in range(seat_views.size()):
		var sv: Dictionary = seat_views[i]
		var panel: Control = sv.panel
		panel.position = _seat_pos(i) - panel.size / 2.0
		var bet: Label = sv.bet
		bet.position = world.project(world.bet_pos(i)) + Vector2(0, 10) - bet.size / 2.0
		var d: Control = sv.dealer
		d.position = panel.position + Vector2(-12, -12)
	if pile_label != null and pile_label.visible:
		pile_label.position = world.project(world.pending_point()) + Vector2(-pile_label.size.x / 2.0, 30.0)
	if dealer_tag != null and world.dealer_actor != null:
		var hd: Vector3 = world.head_anchor_of(world.dealer_actor)
		dealer_tag.position = Vector2(world.project(hd).x - 40.0, maxf(world.project(hd).y - 22.0, 72.0))

func _stage_text() -> String:
	if engine.hand_over:
		return ""
	match engine.stage:
		Table.Stage.PREFLOP: return "PRE-FLOP"
		Table.Stage.FLOP: return "FLOP"
		Table.Stage.TURN: return "TURN"
		Table.Stage.RIVER: return "RIVER"
	return ""

func _redraw_cards() -> void:
	world.refresh_textures()
	for r in tier_rows:
		for ch in (r.row as Control).find_children("*", "Control", true, false):
			ch.queue_redraw()

func _human_best() -> Dictionary:
	var p: Dictionary = engine.players[HUMAN]
	if (p.hole as Array).size() < 2:
		return {}
	var cards: Array = (p.hole as Array).duplicate()
	for k in range(_shown_board):
		cards.append(engine.board[k])
	return Eval.evaluate(cards)

func _refresh_tier() -> void:
	var cat: int = _tier_cat
	if cat < 0 and not engine.hand_over:
		var b := _human_best()
		cat = int(b.cat) if not b.is_empty() else -1
	elif cat < 0:
		var b2 := _human_best()
		cat = int(b2.cat) if not b2.is_empty() else -1
	for r in tier_rows:
		var on: bool = int(r.cat) == cat
		(r.row as PanelContainer).add_theme_stylebox_override("panel", _tier_style(on))
		var you: Label = r.you
		you.text = "▶" if on else ""
		(r.name as Label).add_theme_color_override("font_color", UIStyle.BRASS_LIGHT if on else UIStyle.CREAM)

func _refresh_actions() -> void:
	var my_turn: bool = _awaiting and not engine.hand_over and engine.current == HUMAN
	var parts: Array = []
	if _waiting_next:
		var broke: bool = int(engine.players[HUMAN].chips) <= 0
		parts.append(_key("SPACE", "CONTINUE" if broke else "NEXT HAND"))
	elif my_turn:
		var owe: int = engine.to_call(HUMAN)
		var free: bool = engine.can_check(HUMAN)
		var chips: int = int(engine.players[HUMAN].chips)
		parts.append("[color=#ffd877][b]YOUR TURN[/b][/color]")
		parts.append(_key("F", "FOLD"))
		if free:
			parts.append(_key("C", "CHECK"))
		else:
			parts.append(_key("C", ("CALL ALL-IN %d" % owe) if owe >= chips else ("CALL %d" % owe)))
		if engine.can_raise(HUMAN):
			var lo: int = engine.min_raise_to(HUMAN)
			parts.append(_key("R", ("BET %d" % lo) if engine.current_bet == 0 else ("RAISE TO %d" % lo)))
			parts.append(_key("A", "ALL-IN %d" % chips))
	elif not engine.hand_over:
		var who: String = String(engine.players[engine.current].name) if engine.current >= 0 and engine.current < engine.players.size() else ""
		if who != "":
			parts.append("[color=#8a7f6a]%s is thinking...[/color]" % who)
	key_strip.text = "   ".join(parts)

func _key(k: String, label: String) -> String:
	return "[color=#c9a45c][b][%s][/b][/color] %s" % [k, label]

func _refresh_hint() -> void:
	if _waiting_next:
		hint_label.text = ""
		return
	if is_tutorial:
		hint_label.text = ""
		return
	if not _coach_on:
		hint_label.text = "[color=#6d6556]Hints off  ·  [%s] to turn them on[/color]" % Keybinds.label(&"hints")
		return
	var p: Dictionary = engine.players[HUMAN]
	if bool(p.folded):
		hint_label.text = "[color=#9c917f]You folded. Watch it play out.[/color]"
		return
	if (p.hole as Array).size() < 2 or not bool(p.in_hand):
		return
	var txt := ""
	if _shown_board == 0:
		txt = "[b]%s[/b]  %s" % [_hole_name(p.hole), _preflop_blurb(Table.preflop_strength(p.hole))]
	else:
		var b := _human_best()
		txt = "[b][color=#ecd394]%s[/color][/b]" % String(b.name)
		var note := _draw_note(p.hole)
		if note != "":
			txt += "  " + note
	if _awaiting and engine.current == HUMAN and not engine.hand_over:
		var adv: Dictionary = engine.advise(HUMAN)
		var label: String = String(adv.kind).to_upper()
		if adv.kind == "raise":
			label = "BET" if engine.current_bet == 0 else "RAISE"
		elif adv.kind == "call":
			label = "CALL %d" % engine.to_call(HUMAN)
		txt += "   [color=#c9a45c][b]Suggest: %s[/b][/color]" % label
		if not _looking():
			txt += " [color=#9c917f]- %s[/color]" % String(adv.why)
	hint_label.text = txt

func _hole_name(hole: Array) -> String:
	var r1: int = Eval.rank_of(hole[0])
	var r2: int = Eval.rank_of(hole[1])
	var hi: int = maxi(r1, r2)
	var lo: int = mini(r1, r2)
	var suited: bool = Eval.suit_of(hole[0]) == Eval.suit_of(hole[1])
	if r1 == r2:
		return "a pair of %s" % Eval.RANK_PLURAL[r1 - 2]
	return "%s and %s%s" % [Eval.RANK_NAMES[hi - 2], Eval.RANK_NAMES[lo - 2], (" (same suit)" if suited else "")]

func _preflop_blurb(s: float) -> String:
	if s >= 0.65:
		return "Strong start."
	if s >= 0.45:
		return "Good start."
	if s >= 0.3:
		return "Playable."
	return "Weak start."

func _draw_note(hole: Array) -> String:
	if _shown_board >= 5:
		return ""
	var cards: Array = (hole as Array).duplicate()
	for k in range(_shown_board):
		cards.append(engine.board[k])
	var cur: Dictionary = Eval.evaluate(cards)
	if int(cur.cat) >= Eval.STRAIGHT:
		return ""
	var suits: Dictionary = {}
	for c in cards:
		suits[Eval.suit_of(c)] = int(suits.get(Eval.suit_of(c), 0)) + 1
	for s in suits:
		if int(suits[s]) == 4:
			return "[color=#9fd8b0]Flush draw[/color]"
	var outs := 0
	for rk in range(2, 15):
		if int(Eval.evaluate(cards + [Eval.make(rk, 0)]).cat) >= Eval.STRAIGHT:
			outs += 1
	if outs >= 2:
		return "[color=#9fd8b0]Straight draw[/color]"
	if outs == 1:
		return "[color=#9fd8b0]Gutshot draw[/color]"
	return ""

# ── Small helpers ─────────────────────────────────────────────────────

func _pop_text(at: Vector2, text: String, col: Color) -> void:
	var l := UIStyle.make_label(text, 18, col, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.size = Vector2(160, 28)
	l.position = at - Vector2(80, 70)
	stage.add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 34.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)

func _toast(text: String) -> void:
	var l := UIStyle.make_label(text, 15, UIStyle.CREAM)
	l.add_theme_stylebox_override("normal", UIStyle.panel_style(Color(UIStyle.INK, 0.95), UIStyle.BRASS_DIM, 10, 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.reset_size()
	var tr := _table_rect()
	l.position = Vector2(tr.get_center().x - l.size.x / 2.0, TOP_H + 44.0)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)

func _log(_msg: String) -> void:
	pass

func _popup(title: String, body: String, buttons: Array) -> Control:
	var overlay := ColorRect.new()
	overlay.name = "PokerModal"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := UIStyle.make_panel(Color(UIStyle.INK, 0.97))
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(UIStyle.INK, 0.97), UIStyle.BRASS, 14, 2))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(UIStyle.make_label(title, 24, UIStyle.BRASS, true))
	if body != "":
		var bl := UIStyle.make_label(body, 15, UIStyle.CREAM)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(380, 0)
		vb.add_child(bl)
	for b in buttons:
		var btn := UIStyle.make_button(String(b[0]), b[1], Vector2(260, 46), 17)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(b[2])
		vb.add_child(btn)
	return overlay

func _open_menu() -> void:
	if _menu_popup:
		return
	_paused = not is_online
	_menu_popup = _popup("MENU" if is_online else "PAUSED", "", [
		["RESUME", &"primary", _close_menu],
		["HINTS: %s" % ("ON" if _coach_on else "OFF"), &"secondary", func() -> void:
			_toggle_hints()
			_close_menu()
			_open_menu()],
		["SETTINGS", &"secondary", func() -> void:
			# Keep the game paused while Settings is open, and return to this menu when it closes.
			if _menu_popup:
				_menu_popup.queue_free()
				_menu_popup = null
			var sp := preload("res://scripts/settings_panel.gd").new()
			sp.name = "PokerModal"
			add_child(sp)
			sp.tree_exited.connect(func() -> void:
				if is_inside_tree():
					_open_menu())],
		["MAIN MENU", &"danger", _to_main_menu],
	])

func _close_menu() -> void:
	_paused = false
	if _menu_popup:
		_menu_popup.queue_free()
		_menu_popup = null

func _to_main_menu() -> void:
	if vices != null:
		vices.force_end()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_online and _eos != null:
		await _eos.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

# ── Tutorial API (used by poker_tutorial.gd) ──────────────────────────

func coach_show(title: String, body: String, with_continue: bool) -> void:
	coach_title.text = title
	coach_body.text = body
	_coach_wait = with_continue
	coach_hint.text = "[SPACE] continue   ·   [ESC] menu" if with_continue else "do the highlighted move   ·   [ESC] menu"
	coach_panel.visible = true
	coach_panel.reset_size()
	_place_coach()
	coach_panel.modulate.a = 0.0
	create_tween().tween_property(coach_panel, "modulate:a", 1.0, 0.2)

func coach_hide() -> void:
	coach_panel.visible = false

## Info step: shows the box and waits for CONTINUE.
func coach_say(title: String, body: String, target: Variant = null) -> void:
	spot(target)
	coach_show(title, body, true)
	await coach_continued
	coach_hide()
	spot(null)

## Task step: shows the box, restricts the buttons, returns right away (the hand loop waits for the move).
func coach_task(title: String, body: String, allowed: Array, target: Variant = null) -> void:
	_allowed = allowed
	spot(target)
	coach_show(title, body, false)
	_refresh_all()

## target: null (clear), a Control, or the strings "cards" / "board".
func spot(target: Variant) -> void:
	_spot_target = target
	spot_ring.visible = target != null
	if spot_ring.has_meta("tw"):
		var old: Variant = spot_ring.get_meta("tw")
		if old is Tween:
			(old as Tween).kill()
		spot_ring.modulate.a = 1.0
	if target != null:
		_follow_spot()
		var tw := create_tween().set_loops()
		tw.tween_property(spot_ring, "modulate:a", 0.35, 0.5)
		tw.tween_property(spot_ring, "modulate:a", 1.0, 0.5)
		spot_ring.set_meta("tw", tw)

func _follow_spot() -> void:
	var r := Rect2()
	if _spot_target is Control:
		if not is_instance_valid(_spot_target):
			spot_ring.visible = false
			return
		r = (_spot_target as Control).get_global_rect()
	elif _spot_target is String and _spot_target == "cards":
		r = human_card_rect()
	elif _spot_target is String and _spot_target == "board":
		r = board_rect()
	elif _spot_target is String and _spot_target == "button":
		var bp: Vector2 = world.project(world.button_point())
		r = Rect2(bp - Vector2(26, 18), Vector2(52, 36))
	elif _spot_target is String and _spot_target == "rack":
		r = Rect2(world.project(world.rack_point(1)), Vector2.ZERO)
		for d in World.DENOMS:
			r = r.expand(world.project(world.rack_point(d)))
			r = r.expand(world.project(world.rack_point(d) + Vector3(0, world.card_h * 0.4, 0)))
	elif _spot_target is String and _spot_target == "pile":
		var rp: Vector2 = world.project(world.ring_point())
		r = Rect2(rp - Vector2(60, 36), Vector2(120, 72))
	else:
		spot_ring.visible = false
		return
	r = r.grow(6.0)
	spot_ring.global_position = r.position
	spot_ring.size = r.size

func _process(_delta: float) -> void:
	_update_turn_indicator()
	if world != null:
		world.sync_size()
		_sync_mouse()
		if not _cinematic:
			world.set_look(_look_yaw, _look_pitch, vices.tilt_deg() if vices != null else 0.0, vices.roll_deg() if vices != null else 0.0)
		_layout_panels_only()
		_update_aim()
		_update_peek(_delta)
	if spot_ring and spot_ring.visible:
		_follow_spot()

func human_card_rect() -> Rect2:
	var pts: Array = world.card_corners(world.hole_transform(HUMAN, 0)) + world.card_corners(world.hole_transform(HUMAN, 1))
	return world.screen_rect(pts)

func board_rect() -> Rect2:
	var pts: Array = []
	for k in range(5):
		pts += world.card_corners(world.board_transform(k))
	return world.screen_rect(pts)

func tutorial_finish() -> void:
	_popup("TUTORIAL COMPLETE", "That is a full hand of Texas Hold'em. Ready to play against the table?", [
		["PLAY A REAL GAME", &"primary", func() -> void:
			GameGlobals.is_tutorial = false
			GameGlobals.num_players = 4
			GameGlobals.game_mode = 1
			get_tree().reload_current_scene()],
		["REPLAY TUTORIAL", &"secondary", func() -> void: get_tree().reload_current_scene()],
		["MAIN MENU", &"secondary", _to_main_menu],
	])
