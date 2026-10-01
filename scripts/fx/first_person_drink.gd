extends Node3D

## Interactive first-person whiskey for the LOCAL player (camera = eyes).
##
##   start()  → if the glass already sits on the table in front of you, your
##              hand reaches down and lifts it (ice clinks); otherwise a glass
##              comes in from the side. Empty? A bottle comes in and pours.
##   sip()    → one scroll tick = one sip: glass to the lips, head tips back,
##              the level drops (gulps, ice rattles). Stop scrolling and it
##              lowers again. Run it dry and it's refilled from the bottle.
##   finish() → set the glass back down on the felt (it STAYS on the table);
##              also after IDLE_END seconds without a sip. abort() does the same
##              instantly (Chamber / game over). `done(glass)` hands the table
##              glass back to the game.
##   The level persists between drinks (static `level`).

const VFP := preload("res://scripts/fx/vice_first_person.gd")
const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const Juice := preload("res://scripts/fx/juice.gd")
const Sound := preload("res://scripts/sound.gd")
const Glassware := preload("res://scripts/fx/glassware.gd")
const BartenderPour := preload("res://scripts/fx/bartender_pour.gd")

const BASE_SIP_PER_TICK := 0.05   # ~20 sips per glass
const LOWER_AFTER := 0.6        # seconds without a sip → glass comes down
const IDLE_END := 5.0
const HELD_POS := Vector3(-0.06, -0.3, -0.26)   # glass in the fist (hand-local)
const GLASS_SCALE := 1.5

## 1 = full, 0 = empty. Persists between drinks.
static var level: float = 1.0
## Which drink the glass on the table holds (a different one gets a fresh glass).
static var drink_id: String = ""

enum Phase { INTRO, READY, SIPPING, BUSY, OUTRO, DONE }

var phase: Phase = Phase.INTRO
## W while the bartender is pouring: you let go and get your cards back; the pour finishes on its own.
var on_walk_away: Callable
## Called (awaited) when the pour ends after a walk-away: the game puts the cards back down.
var on_resume: Callable
var _refilling := false      # a refill (bartender pour) is under way
var _pouring := false        # the glass is on the table and the bartender is pouring
var _walked_away := false
var _walk_pending := false   # asked to walk away before the glass reached the table
var drink: Dictionary = {}
var sip_per_tick := BASE_SIP_PER_TICK
var abv := 1.0
var on_sip: Callable
var glass_scale := GLASS_SCALE
var _sleeve := Color(0.14, 0.12, 0.16)
var _pour_bottle: Node3D = null     # the bottle being poured
var _waiter: Node3D = null          # the person pouring it: a world-fixed Kenney character
var _world_holder: Node3D = null    # world-space parent of the player's hand during the pour
var waiter_scale := 0.3             # set by the game
var seat_fwd := Vector3.ZERO          # seat -> table-centre direction (look-independent)
var net_cb: Callable = Callable()   # (event: String, data: Dictionary) -> void, mirrored to other players
var table_center := Vector3.ZERO
var table_radius := 1.0
var seat_pos := Vector3.ZERO
var crowd: Node = null
var floor_y := 0.0                  # the room floor the waiter stands on (set by the game)
# Pour choreography (all world space, so turning the head never moves any of it).
var _sh_local := Vector3.ZERO       # waiter's shoulder, actor-local
var _arm: Node3D = null
var _arm_len := 0.5
var _shoulder_w := Vector3.ZERO
var _dir_rest := Vector3.DOWN
var _dir_pour := Vector3.DOWN
var _frame := Basis.IDENTITY        # x = right (horizontal), y = up
var _pour_t := 0.0                  # 0 = bottle held low, 1 = tipped over the glass
var _bottle_s := 1.0
var _driving := false
var _grip_pour := Vector3.ZERO
var _arm_sleeve: MeshInstance3D = null   # stretched sleeve joining the pinned hand to your body
var _hidden_sleeve: MeshInstance3D = null
const RoomCrowd := preload("res://scripts/fx/room_crowd.gd")
const WAITER_GLB := "res://assets/imported_assets/kenney_blocky-characters_20/Models/GLB format/character-g.glb"
var cam: Camera3D
var on_done: Callable
var table_spot: Vector3
var _hand: Node3D
var _glass: Node3D
var _liquid: Node3D
var _last_sip := 0.0
var _now := 0.0
var _idle := 0.0
var _sips := 0
var _finish_requested := false
var _tilt := 0.0
var _tilt_tw: Tween
var _off: Vector3
var _rest: Vector3
var _lips: Vector3
const REST_ROT := Vector3(10.0, -18.0, 18.0)
const LIPS_ROT := Vector3(62.0, -6.0, 6.0)

static func start(camera: Camera3D, sleeve: Color, table_glass: Node3D, spot: Vector3, done: Callable, drink_def: Dictionary = {}, sip_cb: Callable = Callable(), p_waiter_scale: float = 0.3, p_floor_y: float = 0.0, p_seat_fwd: Vector3 = Vector3.ZERO, p_extra: Dictionary = {}) -> Node3D:
	var rig: Node3D = (load("res://scripts/fx/first_person_drink.gd") as Script).new()
	rig.name = "FirstPersonDrink"
	rig.cam = camera
	rig.on_done = done
	rig.table_spot = spot
	rig.on_sip = sip_cb
	rig.waiter_scale = p_waiter_scale
	rig.floor_y = p_floor_y
	rig.seat_fwd = p_seat_fwd
	rig.net_cb = p_extra.get("net_cb", Callable())
	rig.crowd = p_extra.get("crowd", null)
	rig.table_center = p_extra.get("center", Vector3.ZERO)
	rig.table_radius = float(p_extra.get("table_r", 1.0))
	rig.seat_pos = p_extra.get("seat_pos", Vector3.ZERO)
	rig.drink = drink_def
	if not drink_def.is_empty():
		rig.sip_per_tick = float(drink_def.get("sip", BASE_SIP_PER_TICK))
		rig.abv = float(drink_def.get("abv", 1.0))
		if str(drink_def.get("glass", "tumbler")) == "mug":
			rig.glass_scale = GLASS_SCALE * 0.85
		var id: String = str(drink_def.id)
		if id != drink_id:
			# Different drink: the old glass leaves and a fresh, full one comes in.
			if table_glass != null and is_instance_valid(table_glass):
				table_glass.queue_free()
			table_glass = null
			level = 1.0
			drink_id = id
	camera.add_child(rig)
	rig._build(sleeve, table_glass)
	return rig

func _build(sleeve: Color, table_glass: Node3D) -> void:
	_sleeve = sleeve
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.85, 0.65)
	fill.light_energy = 0.35
	fill.omni_range = VFP.DEPTH * 1.6
	fill.position = Vector3(0, VFP.DEPTH * 0.3, -VFP.DEPTH * 0.4)
	add_child(fill)
	_off = VFP._at(cam, 0.82, -1.9, VFP.DEPTH)
	_rest = VFP._at(cam, 0.62, -0.7, VFP.DEPTH)
	_lips = VFP._at(cam, 0.08, -0.95, VFP.DEPTH * 0.66)
	_hand = EmoteRig.build_fist(VFP.SKIN, sleeve)
	_hand.scale = Vector3.ONE * VFP._fist_scale(cam)
	_hand.position = _off
	_hand.rotation_degrees = REST_ROT
	add_child(_hand)
	VFP._capture_head(cam)

	var tw := create_tween()
	if table_glass != null and is_instance_valid(table_glass):
		# Reach down to the glass on the felt and lift it.
		_glass = table_glass
		_liquid = _glass.get_meta(&"liquid")
		var reach_rot := Vector3(-10.0, -18.0, 10.0)
		var hb := Basis.from_euler(reach_rot * (PI / 180.0)).scaled(_hand.scale)
		var reach := to_local(_glass.global_position) - hb * HELD_POS
		tw.tween_property(_hand, "position", reach, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_hand, "rotation_degrees", reach_rot, Juice.d(0.45))
		tw.tween_callback(func() -> void:
			_attach_glass()
			Sound.play(&"ice"))
	else:
		if drink.is_empty():
			_glass = EmoteRig.build_glass()
		else:
			_glass = Glassware.build(str(drink.get("glass", "tumbler")), drink.get("color", Color(0.85, 0.45, 0.08)))
		_liquid = _glass.get_meta(&"liquid")
		_hand.add_child(_glass)
		_glass.position = HELD_POS
		_glass.scale = Vector3.ONE * glass_scale
		level = 0.0   # a fresh glass arrives EMPTY and gets poured
		tw.tween_callback(func() -> void: Sound.play(&"glass_clink"))
	_apply_level()
	tw.tween_property(_hand, "position", _rest, Juice.d(0.4)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", REST_ROT, Juice.d(0.4))
	tw.tween_callback(func() -> void:
		Sound.play(&"ice", -4.0)
		_enter_ready())

## Moves the table glass into the fist, keeping its world pose, then settles
## it into the grip.
func _attach_glass() -> void:
	var xf := _glass.global_transform
	_glass.get_parent().remove_child(_glass)
	_hand.add_child(_glass)
	_glass.global_transform = xf
	var tw := create_tween().set_parallel()
	tw.tween_property(_glass, "position", HELD_POS, Juice.d(0.12))
	tw.tween_property(_glass, "rotation", Vector3.ZERO, Juice.d(0.12))
	tw.tween_property(_glass, "scale", Vector3.ONE * glass_scale, Juice.d(0.12))

func _apply_level() -> void:
	if _liquid:
		_liquid.scale = Vector3(1.0, maxf(level, 0.02), 1.0)
		_liquid.visible = level > 0.01

# ── Interaction ───────────────────────────────────────────────────────

## One scroll tick = one sip.
func sip() -> void:
	if phase == Phase.READY:
		if level <= 0.02:
			_refill()
			return
		phase = Phase.SIPPING
		_sips = 0
		if net_cb.is_valid():
			net_cb.call("sip", {"level": level})
		var tw := create_tween()
		tw.tween_property(_hand, "position", _lips, Juice.d(0.3)).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(_hand, "rotation_degrees", LIPS_ROT, Juice.d(0.3)).set_trans(Tween.TRANS_SINE)
		_tilt_to(VFP.HEAD_BACK_DRINK, 0.4)
		Sound.play(&"ice", -6.0)
	elif phase != Phase.SIPPING:
		return
	_idle = 0.0
	_last_sip = _now
	var before := level
	level = maxf(level - sip_per_tick, 0.0)
	if on_sip.is_valid():
		on_sip.call((before - level) * abv)
	_apply_level()
	_sips += 1
	if _sips % 2 == 0:
		Sound.play(&"gulp")
	if randf() < 0.3:
		Sound.play(&"ice", -8.0)
	if level <= 0.0:
		_lower()  # dry — lower, then it gets refilled

func finish() -> void:
	_finish_requested = true

## The drink key: while a refill is running, let the player play cards instead of waiting for
## the pour; otherwise it just asks for the glass to be set down.
func request_walk_away() -> void:
	if _refilling and not _walked_away:
		if _pouring:
			_walk_away()
		else:
			_walk_pending = true
	else:
		finish()

func _walk_away() -> void:
	_walked_away = true
	_walk_pending = false
	if _hand != null:
		_hand.visible = false
	if on_walk_away.is_valid():
		on_walk_away.call()

func abort() -> void:
	_set_down(true)

func _process(delta: float) -> void:
	_now += delta
	_drive_pour()
	match phase:
		Phase.SIPPING:
			if _now - _last_sip > LOWER_AFTER:
				_lower()
		Phase.READY:
			_idle += delta
			if _finish_requested or _idle > IDLE_END:
				_set_down(false)

func _enter_ready() -> void:
	phase = Phase.READY
	_idle = 0.0
	if level <= 0.02 and not _finish_requested:
		_refill()

func _lower() -> void:
	phase = Phase.BUSY
	var tw := create_tween()
	tw.tween_property(_hand, "position", _rest, Juice.d(0.35)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_hand, "rotation_degrees", REST_ROT, Juice.d(0.35))
	_tilt_to(0.0, 0.45)
	tw.tween_callback(func() -> void: Sound.play(&"ice", -5.0))
	tw.tween_interval(Juice.d(0.1))
	tw.tween_callback(func() -> void: _enter_ready())

# ── Refill from the bottle ────────────────────────────────────────────

## Every frame during a pour: the bottle rides the waiter's hand, tipping toward the
## glass on the table as `_pour_t` goes 0 -> 1. Everything is world space, so the head
## can turn freely without moving any of it.
func _drive_pour() -> void:
	if not _driving or _waiter == null or not is_instance_valid(_waiter) or _arm == null:
		return
	if _pour_bottle == null or not is_instance_valid(_pour_bottle):
		return
	var hand_pt := _arm.to_global(Vector3(0.0, -0.85, 0.0))
	var grip := hand_pt.lerp(_grip_pour, _pour_t)
	var ang := lerpf(20.0, 118.0, _pour_t)
	var bb := (_frame * Basis(Vector3(0, 0, 1), deg_to_rad(ang))).scaled(Vector3.ONE * _bottle_s)
	_pour_bottle.global_transform = Transform3D(bb, grip - bb * Vector3(0.0, 0.2, 0.0))


func _drop_waiter() -> void:
	_driving = false
	if _waiter != null and is_instance_valid(_waiter):
		_waiter.queue_free()
	_waiter = null
	_arm = null


func _reclaim_hand() -> void:
	pass   # (the hand is never pinned any more; kept so _set_down / _exit_tree stay simple)


func _exit_tree() -> void:
	_drop_waiter()


## You set the glass down on the table spot, the bartender comes from the bar and pours
## (the same scene everyone else sees, see bartender_pour.gd), then you pick it up again.
## Nothing is attached to the camera, so the head turns freely.
func _refill() -> void:
	phase = Phase.BUSY
	_refilling = true
	if net_cb.is_valid():
		net_cb.call("pour", {"level": level})

	# 1) The bartender comes from the bar; work out where the glass must stand (near the
	#    rim, within his arm's reach), then set it down THERE.
	var done := [false]
	var ctx := {
		"host": self, "world": cam.get_parent(), "glass": _glass, "center": table_center,
		"seat_pos": seat_pos, "floor_y": floor_y, "crowd": crowd, "drink": drink,
		"table_y": table_spot.y, "table_r": table_radius,
		"level_from": level,
		"level_cb": func(v: float) -> void:
			level = v
			_apply_level(),
		"poured": func() -> void: done[0] = true,
	}
	var plan: Dictionary = await BartenderPour.prepare(ctx)
	if plan.is_empty() or not is_instance_valid(_glass):
		_refilling = false
		_pick_glass_back_up()
		return
	var spot: Vector3 = plan.pour_spot
	var reach_rot := Vector3(-10.0, -18.0, 10.0)
	var hb := Basis.from_euler(reach_rot * (PI / 180.0)).scaled(_hand.scale)
	var reach := to_local(spot) - hb * HELD_POS
	var down := create_tween()
	down.tween_property(_hand, "position", reach, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	down.parallel().tween_property(_hand, "rotation_degrees", reach_rot, Juice.d(0.45))
	down.tween_callback(func() -> void:
		_place_glass_on_table(spot)
		Sound.play(&"glass_clink"))
	down.tween_property(_hand, "position", _off, Juice.d(0.4)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await down.finished
	if not is_instance_valid(_glass):
		return

	# 2) The bartender pours it.
	ctx["glass"] = _glass
	BartenderPour.perform(ctx, plan)   # (coroutine: keeps running after we move on)
	_pouring = true
	if _walk_pending:
		_walk_away()
	while not done[0] and is_inside_tree():
		await get_tree().process_frame
	_pouring = false
	_refilling = false
	if _walked_away:
		_walked_away = false
		if _finish_requested:
			_set_down(true)   # they asked to put it away meanwhile: the full glass stays on the table
			return
		# Pour over: cards go back down and the glass is in your hand again.
		if on_resume.is_valid():
			await on_resume.call()
		if _hand != null:
			_hand.visible = true
	_pick_glass_back_up()


## Your hand reaches down to the (now full) glass on the table and lifts it.
func _pick_glass_back_up() -> void:
	if _glass == null or not is_instance_valid(_glass):
		_enter_ready()
		return
	var reach_rot := Vector3(-10.0, -18.0, 10.0)
	var hb := Basis.from_euler(reach_rot * (PI / 180.0)).scaled(_hand.scale)
	var reach := to_local(_glass.global_position) - hb * HELD_POS
	var tw := create_tween()
	tw.tween_interval(Juice.d(0.5))
	tw.tween_property(_hand, "position", reach, Juice.d(0.5)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", reach_rot, Juice.d(0.5))
	tw.tween_callback(func() -> void:
		_attach_glass()
		Sound.play(&"ice"))
	tw.tween_property(_hand, "position", _rest, Juice.d(0.4)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", REST_ROT, Juice.d(0.4))
	tw.tween_callback(func() -> void: _enter_ready())


# ── Put it back on the table ──────────────────────────────────────────

func _set_down(instant: bool) -> void:
	if net_cb.is_valid():
		net_cb.call("set_down", {"level": level})
	_reclaim_hand()
	_drop_waiter()
	if _pour_bottle != null and is_instance_valid(_pour_bottle):
		_pour_bottle.queue_free()
	_pour_bottle = null
	if phase == Phase.DONE or phase == Phase.OUTRO:
		return
	phase = Phase.OUTRO
	_tilt_to(0.0, 0.3)
	if instant:
		_place_glass_on_table()
		_finish()
		return
	# Hand carries the glass down to its spot on the felt, lets go, withdraws.
	var reach_rot := Vector3(-10.0, -18.0, 10.0)
	var hb := Basis.from_euler(reach_rot * (PI / 180.0)).scaled(_hand.scale)
	var reach := to_local(table_spot) - hb * HELD_POS
	var tw := create_tween()
	tw.tween_property(_hand, "position", reach, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", reach_rot, Juice.d(0.45))
	tw.tween_callback(func() -> void:
		_place_glass_on_table()
		Sound.play(&"glass_clink")
		Sound.play(&"ice", -4.0))
	tw.tween_property(_hand, "position", _off, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _finish())

## Re-parents the glass to the world, standing upright on its table spot.
func _place_glass_on_table(at: Variant = null) -> void:
	if _glass == null or not is_instance_valid(_glass):
		return
	var world := cam.get_parent()
	var s := _glass.global_transform.basis.get_scale().x
	if _glass.get_parent():
		_glass.get_parent().remove_child(_glass)
	world.add_child(_glass)
	var where: Vector3 = at if at is Vector3 else table_spot
	_glass.global_transform = Transform3D(Basis().scaled(Vector3.ONE * s), where)

func _finish() -> void:
	VFP._release_head(cam)
	phase = Phase.DONE
	var cb := on_done
	on_done = Callable()
	var g := _glass
	queue_free()
	if cb.is_valid():
		cb.call(g)

func _tilt_to(deg: float, dur: float) -> void:
	if _tilt_tw and _tilt_tw.is_valid():
		_tilt_tw.kill()
	_tilt_tw = create_tween()
	VFP._head_to(_tilt_tw, cam, _tilt, deg, Juice.d(dur))
	_tilt_tw.parallel().tween_property(self, "_tilt", deg, Juice.d(dur))
