extends Node

## Smoking and drinking at the Hold'em table: the same first-person cigarette (pack, lighter, scroll to
## drag, burn down, ashtray) and drink (scroll to sip, glass on the felt, ghost waiter refills) as the
## Chamber Draw game, plus AI players who light up and pour, drunk sway, and passing out.
## The heavy lifting lives in scripts/fx (first_person_smoke / first_person_drink); this controller is the glue.

const UIStyle := preload("res://scripts/ui_style.gd")
const Sound := preload("res://scripts/sound.gd")
const Keybinds := preload("res://scripts/keybinds.gd")
const VicePicker := preload("res://scripts/ui/vice_picker.gd")
const ViceCatalog := preload("res://scripts/vice_catalog.gd")
const Ashtray := preload("res://scripts/fx/ashtray.gd")
const PropOverlay := preload("res://scripts/fx/prop_overlay.gd")
const BartenderPour := preload("res://scripts/fx/bartender_pour.gd")
const FirstPersonSmoke := preload("res://scripts/fx/first_person_smoke.gd")
const FirstPersonDrink := preload("res://scripts/fx/first_person_drink.gd")
const ViceFirstPerson := preload("res://scripts/fx/vice_first_person.gd")
const Glassware := preload("res://scripts/fx/glassware.gd")

const EMOTE_KINDS: Array[StringName] = [&"smoke", &"drink"]
const EMOTE_COOLDOWN := 4.6
const DRUNK_PER_UNIT := 0.32
const DRUNK_DECAY := 0.0018
const WAKE_DRUNK := 0.3
const PASS_OUT_AT := 1.0
const DRUNK_STEPS := [
	{"at": 0.2, "msg": "You're feeling warm."},
	{"at": 0.45, "msg": "The room sways a little."},
	{"at": 0.7, "msg": "Everything is a bit... double."},
	{"at": 0.92, "msg": "You should probably stop."},
]

var game: Control
var world: Node
var hands_busy: bool = false
var drunk: float = 0.0
var smoke_session: Node3D = null
var drink_session: Node3D = null
var table_glass: Node3D = null
var table_ashtray: Node3D = null

var _picker: Control = null
var _vice_pick: Dictionary = {"smoke": {}, "drink": {}}
var _pending_vice: StringName = &""
var _cooldown: float = 0.0
var _overlay_pass: Node = null
var _fx_mat: ShaderMaterial = null
var _fx_overlay: ColorRect = null
var _seat_glass: Dictionary = {}
var _seat_ashtray: Dictionary = {}
var _seat_smoke_prod: Dictionary = {}
var _seat_drink_prod: Dictionary = {}
var _ai_timers: Dictionary = {}
var _t: float = 0.0
var _pan_accum: float = 0.0

func setup(g: Control, w: Node) -> void:
	game = g
	world = w

func picker_open() -> bool:
	return _picker != null and is_instance_valid(_picker)

func session_active() -> bool:
	return (smoke_session != null and is_instance_valid(smoke_session)) or (drink_session != null and is_instance_valid(drink_session))

func drinking_active() -> bool:
	return drink_session != null and is_instance_valid(drink_session) and not bool(drink_session.call("is_walked_away"))

## Head tilt (degrees) the active session wants on top of the mouse look.
func tilt_deg() -> float:
	var sess: Object = null
	if smoke_session != null and is_instance_valid(smoke_session):
		sess = smoke_session
	elif drink_session != null and is_instance_valid(drink_session):
		sess = drink_session
	return float(sess.get("_tilt")) if sess != null else 0.0

## Drunk sway: the view slowly rolls.
func roll_deg() -> float:
	return sin(_t * 0.55) * 3.2 * drunk + sin(_t * 1.3) * 0.8 * drunk

# ── Requests (keys S / W / B) ─────────────────────────────────────────

func handle_key(ke: InputEventKey) -> bool:
	if Keybinds.matches(ke, &"smoke"):
		request(&"smoke")
		return true
	if Keybinds.matches(ke, &"drink"):
		request(&"drink")
		return true
	if Keybinds.matches(ke, &"change_vice"):
		if smoke_session != null and is_instance_valid(smoke_session):
			_change_choice(&"smoke")
		elif drink_session != null and is_instance_valid(drink_session):
			_change_choice(&"drink")
		return true
	return false

func request(kind: StringName) -> void:
	if kind == &"smoke" and smoke_session != null and is_instance_valid(smoke_session):
		smoke_session.call("finish")
		return
	if kind == &"drink" and drink_session != null and is_instance_valid(drink_session):
		drink_session.call("request_walk_away")
		return
	if drink_session != null and is_instance_valid(drink_session):
		return
	if hands_busy or _cooldown > 0.0 or picker_open() or game.vice_blocked():
		return
	if (kind == &"smoke" or kind == &"drink") and _vice_pick[String(kind)].is_empty():
		var on_pick := func(cat: String, brand: int) -> void:
			_vice_pick[String(kind)] = {"cat": cat, "brand": brand}
			_picker = null
			_start_after_pick(kind)
		var on_cancel := func() -> void: _picker = null
		_picker = VicePicker.open(game, "smoke" if kind == &"smoke" else "drink", on_pick, on_cancel, 150)
		return
	_cooldown = EMOTE_COOLDOWN
	_play_own(kind)

func _change_choice(kind: StringName) -> void:
	if picker_open():
		return
	var on_pick := func(cat: String, brand: int) -> void:
		_vice_pick[String(kind)] = {"cat": cat, "brand": brand}
		_picker = null
		var sess: Object = smoke_session if kind == &"smoke" else drink_session
		if sess != null and is_instance_valid(sess):
			_pending_vice = kind
			sess.call("finish")
		elif not hands_busy:
			_start_after_pick(kind)
	var on_cancel := func() -> void: _picker = null
	_picker = VicePicker.open(game, "smoke" if kind == &"smoke" else "drink", on_pick, on_cancel, 150)

func _start_after_pick(kind: StringName) -> void:
	if hands_busy or game.vice_blocked():
		return
	_cooldown = EMOTE_COOLDOWN
	_play_own(kind)

## Mouse wheel / trackpad ticks belong to the cigarette or glass. Returns true when consumed.
func wheel(event: InputEvent) -> bool:
	var smoking := smoke_session != null and is_instance_valid(smoke_session)
	var drinking := drinking_active()
	if not smoking and not drinking:
		return false
	var ticks := 0
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var bi := (event as InputEventMouseButton).button_index
		if bi == MOUSE_BUTTON_WHEEL_UP or bi == MOUSE_BUTTON_WHEEL_DOWN:
			ticks = 1
	elif event is InputEventPanGesture:
		_pan_accum += absf((event as InputEventPanGesture).delta.y)
		while _pan_accum >= 1.0:
			_pan_accum -= 1.0
			ticks += 1
	if ticks == 0:
		return false
	for _i in ticks:
		if smoking:
			smoke_session.call("inhale")
		else:
			drink_session.call("sip")
	return true

# ── Your own vice ─────────────────────────────────────────────────────

func _ensure_overlay_pass() -> void:
	if _overlay_pass == null and world != null and world.tex_rect != null:
		_overlay_pass = PropOverlay.create(game, world.viewport, world.tex_rect)
		_overlay_pass.exclude_from(world.viewport.find_children("*", "Camera3D", true, false))
	if _overlay_pass != null:
		_overlay_pass.set("main_cam", world.camera)

func _play_own(kind: StringName) -> void:
	if hands_busy:
		return
	hands_busy = true
	_ensure_overlay_pass()
	if _overlay_pass != null:
		_overlay_pass.set_active(true)
	var sleeve: Color = (game.colors[0] as Color).darkened(0.45)
	var released := [false]
	var finished := func() -> void:
		smoke_session = null
		if _pending_vice != &"" and is_inside_tree():
			var next_kind := _pending_vice
			_pending_vice = &""
			hands_busy = false
			_play_own(next_kind)
			return
		if released[0]:
			return
		if _overlay_pass != null:
			_overlay_pass.set_active(false)
		hands_busy = false
	if kind == &"smoke":
		var prod: Dictionary = {}
		if not _vice_pick.smoke.is_empty():
			prod = ViceCatalog.smoke_product(str(_vice_pick.smoke.cat), int(_vice_pick.smoke.brand))
		_ensure_ashtray()
		FirstPersonSmoke.ashtray = table_ashtray
		game.net_vice("smoke_begin", {"cat": str(_vice_pick.smoke.get("cat", "cigarette")), "brand": int(_vice_pick.smoke.get("brand", 0))})
		smoke_session = FirstPersonSmoke.start(world.camera, sleeve, finished, prod, Callable(self, "_on_my_smoke_event"))
		game.vice_toast("SCROLL to take a drag  ·  [%s] put it out  ·  [%s] change" % [Keybinds.label(&"smoke"), Keybinds.label(&"change_vice")])
	else:
		var after_drink := func(glass: Node3D) -> void:
			table_glass = glass
			drink_session = null
			finished.call()
		var walk_away := func() -> void:
			if released[0] or not is_inside_tree():
				return
			released[0] = true
			if _overlay_pass != null:
				_overlay_pass.set_active(false)
			hands_busy = false
		var dprod: Dictionary = {}
		if not _vice_pick.drink.is_empty():
			dprod = ViceCatalog.drink_product(str(_vice_pick.drink.cat), int(_vice_pick.drink.brand))
		game.net_vice("drink_begin", {"cat": str(_vice_pick.drink.get("cat", "whiskey")), "brand": int(_vice_pick.drink.get("brand", 0))})
		drink_session = FirstPersonDrink.start(world.camera, sleeve, table_glass, world.vice_spot(0, "glass"), after_drink, dprod,
			Callable(self, "on_sip"), 0.4, 0.0, world.forward_of(0),
			{"net_cb": Callable(self, "_on_my_drink_event"), "crowd": null, "center": world.center,
			"seat_pos": world.seat_marker_pos(0), "table_r": world.table_radius, "rest_spot": world.vice_spot(0, "glass")})
		drink_session.set("on_walk_away", walk_away)
		game.vice_toast("SCROLL to sip  ·  [%s] set it down  ·  [%s] change" % [Keybinds.label(&"drink"), Keybinds.label(&"change_vice")])

func _ensure_ashtray() -> void:
	if table_ashtray != null and is_instance_valid(table_ashtray):
		return
	var f: float = ViceFirstPerson._fist_scale(world.camera)
	table_ashtray = Ashtray.build(f)
	world.viewport.add_child(table_ashtray)
	table_ashtray.global_position = world.vice_spot(0, "ashtray")

func _on_my_smoke_event(event: String, data: Dictionary) -> void:
	game.net_vice("smoke_" + event, data)

func _on_my_drink_event(event: String, data: Dictionary) -> void:
	game.net_vice("drink_" + event, data)

## Everything is aborted (passed out, leaving, match over).
func force_end() -> void:
	if smoke_session != null and is_instance_valid(smoke_session):
		smoke_session.call("abort")
	if drink_session != null and is_instance_valid(drink_session):
		drink_session.call("abort")
	smoke_session = null
	drink_session = null
	_pending_vice = &""
	hands_busy = false
	if _overlay_pass != null:
		_overlay_pass.set_active(false)

# ── Drinking builds up ────────────────────────────────────────────────

func on_sip(amount: float) -> void:
	var before := drunk
	drunk = minf(drunk + amount * DRUNK_PER_UNIT, 1.0)
	_ensure_fx_overlay()
	if _fx_overlay != null:
		_fx_overlay.visible = true
	for step in DRUNK_STEPS:
		if before < float(step.at) and drunk >= float(step.at):
			game.vice_toast(str(step.msg))

func _ensure_fx_overlay() -> void:
	if _fx_overlay != null:
		return
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = preload("res://shaders/wired.gdshader")
	_fx_overlay = ColorRect.new()
	_fx_overlay.name = "DrunkOverlay"
	_fx_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_overlay.material = _fx_mat
	_fx_overlay.visible = false
	game.add_child(_fx_overlay)
	var above: int = world.tex_rect.get_index()
	if _overlay_pass != null and _overlay_pass.get("rect") != null:
		above = maxi(above, (_overlay_pass.get("rect") as Control).get_index())
	game.move_child(_fx_overlay, above + 1)

func _process(delta: float) -> void:
	if game == null or world == null:
		return
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if drunk > 0.0:
		drunk = maxf(drunk - DRUNK_DECAY * delta, 0.0)
	if _fx_mat != null:
		_fx_mat.set_shader_parameter("intensity", 0.0)
		_fx_mat.set_shader_parameter("crash", 0.0)
		_fx_mat.set_shader_parameter("drunk", drunk)
		_fx_mat.set_shader_parameter("t", _t)
	if _fx_overlay != null:
		_fx_overlay.visible = drunk > 0.005
	if drunk >= PASS_OUT_AT and not game.is_sleeping() and not game.vice_blocked():
		game.vice_pass_out()
		drunk = PASS_OUT_AT
	_process_ai(delta)

## Offline AI players light up or pour a drink now and then.
func _process_ai(delta: float) -> void:
	if game.is_online or game.is_tutorial or game.engine == null:
		return
	for i in range(1, game.engine.players.size()):
		var p: Dictionary = game.engine.players[i]
		if not bool(p.in_hand):
			continue
		var t: float = float(_ai_timers.get(i, randf_range(6.0, 18.0)))
		t -= delta
		if t <= 0.0:
			t = randf_range(14.0, 34.0)
			if i != game.engine.current and not game.engine.hand_over:
				_play_for_ai(i, EMOTE_KINDS[randi() % EMOTE_KINDS.size()])
		_ai_timers[i] = t

func _play_for_ai(seat: int, kind: StringName) -> void:
	_ensure_seat_props(seat, kind)
	var actor: Node3D = world.actors.get(seat, null)
	if actor != null and is_instance_valid(actor):
		actor.call("do_emote", kind)

# ── Other players' vices (seat is the RELATIVE seat on this screen) ───

func play_remote(seat: int, event: String, data: Dictionary) -> void:
	if seat == 0 or world == null:
		return
	var actor: Node3D = world.actors.get(seat, null)
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
				actor.call("do_emote", &"smoke")
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
					"host": self, "world": world.world_root, "glass": g,
					"center": world.center, "seat_pos": world.seat_marker_pos(seat), "floor_y": 0.0,
					"crowd": null, "drink": dp, "level_from": float(data.get("level", 0.0)),
					"table_y": world.vice_spot(seat, "glass").y, "table_r": world.table_radius, "rest_spot": world.vice_spot(seat, "glass"),
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

func _set_seat_glass(seat: int, prod: Dictionary, level: float) -> void:
	var old: Node3D = _seat_glass.get(seat, null)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var f: float = ViceFirstPerson._fist_scale(world.camera)
	var g: Node3D = Glassware.build(str(prod.get("glass", "tumbler")), prod.get("color", Color(0.85, 0.45, 0.08)))
	g.scale = Vector3.ONE * 1.5 * f
	world.viewport.add_child(g)
	g.global_position = world.vice_spot(seat, "glass")
	_set_glass_level(g, level)
	_seat_glass[seat] = g

func _ensure_seat_props(seat: int, kind: StringName) -> void:
	if seat == 0 or world == null:
		return
	var f: float = ViceFirstPerson._fist_scale(world.camera)
	if kind == &"drink" and not _seat_glass.has(seat):
		var g: Node3D = Glassware.build("tumbler", Color(0.85, 0.45, 0.08))
		g.scale = Vector3.ONE * 1.5 * f
		world.viewport.add_child(g)
		g.global_position = world.vice_spot(seat, "glass")
		_seat_glass[seat] = g
	elif kind == &"smoke" and not _seat_ashtray.has(seat):
		var a: Node3D = Ashtray.build(f)
		world.viewport.add_child(a)
		a.global_position = world.vice_spot(seat, "ashtray")
		_seat_ashtray[seat] = a

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
	var body := _cyl(0.022 * f, length, paper)
	body.rotation_degrees = Vector3(0, 0, 90)
	stick.add_child(body)
	if lit:
		var ember := _cyl(0.024 * f, 0.025 * f, Color(1.0, 0.4, 0.1))
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

func _cyl(radius: float, height: float, col: Color) -> MeshInstance3D:
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
