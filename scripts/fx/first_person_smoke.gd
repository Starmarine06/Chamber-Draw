extends Node3D

## Interactive first-person smoking for the LOCAL player (the camera is the eyes).
##
##   start()  → if there's no lit cigarette (none yet, or the last one reached the
##              filter): a pack comes up, a fresh cigarette is pulled out, raised
##              to the lips and LIT with a brass lighter (lid flip, flame, ember
##              catches). Otherwise the current cigarette is simply raised.
##   inhale() → one scroll tick = one pull: the hand holds it at the lips, the
##              ember flares, the camera dips, and TOBACCO BURNS (the stick
##              visibly shortens). Stop scrolling and you exhale — the plume
##              grows with how long you dragged.
##   The SAME cigarette persists between smokes (static `burn`) until it's
##   smoked down to the filter: then the ember dies and the butt is flicked away,
##   so the next smoke starts with a new one from the pack.
##   finish() puts it away (also after IDLE_END seconds without a pull);
##   abort() removes everything instantly (Chamber / game over).

const VFP := preload("res://scripts/fx/vice_first_person.gd")
const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const Juice := preload("res://scripts/fx/juice.gd")
const Sound := preload("res://scripts/sound.gd")

const BASE_TOBACCO_LEN := 0.2   # model units of smokable paper
const BASE_FILTER_LEN := 0.07
const BASE_BURN_PER_PULL := 0.028   # ~36 pulls per cigarette
const BASE_DRAG_PER_PULL := 0.14
const Ashtray := preload("res://scripts/fx/ashtray.gd")
const EXHALE_AFTER := 0.5       # seconds without a pull → exhale
const IDLE_END := 5.0           # seconds idle (after exhale) → put it away

## 0 = fresh cigarette, 1 = smoked to the filter (or none). Persists between smokes.
static var burn: float = 1.0
## Which product `burn` belongs to (a new brand/kind starts a fresh one).
static var product_id: String = ""
## The ashtray on the felt (set by the game) and the lit smoke resting in it.
static var ashtray: Node3D = null
static var resting: Node3D = null

enum Phase { INTRO, READY, DRAGGING, EXHALING, OUTRO, DONE }

var phase: Phase = Phase.INTRO
var net_cb: Callable = Callable()   # (event: String, data: Dictionary) -> mirrored to other players
var product: Dictionary = {}
var is_cigar := false
var tobacco_len := BASE_TOBACCO_LEN
var filter_len := BASE_FILTER_LEN
var burn_per_pull := BASE_BURN_PER_PULL
var drag_per_pull := BASE_DRAG_PER_PULL
var stick_r := 0.023
var cig_scale := 1.6
var paper_col := Color(0.95, 0.94, 0.9)
var filter_col := Color(0.78, 0.55, 0.3)
var pack_col := Color(0.55, 0.08, 0.12)
var band_col := Color(0.79, 0.64, 0.36)
var cam: Camera3D
var on_done: Callable
var _hand: Node3D
var _cig: Node3D
var _body: Node3D
var _ember: MeshInstance3D
var _ash: Node3D
var _ember_mat: StandardMaterial3D
var _tip_light: OmniLight3D
var _wisps: GPUParticles3D
var _drag := 0.0
var _glow := 0.0
var _last_pull := 0.0
var _idle := 0.0
var _finish_requested := false
var _now := 0.0
var _tilt := 0.0            # current head pitch offset (deg)
var _tilt_tw: Tween
var _exhale_tw: Tween

var _off: Vector3
var _rest: Vector3
var _lips: Vector3
const REST_ROT := Vector3(18.0, 20.0, -22.0)
const LIPS_ROT := Vector3(58.0, 12.0, -6.0)

## Creates the rig under the camera and begins the intro. `done` fires once the
## hand has left the view (the caller picks the cards back up then).
static func start(camera: Camera3D, sleeve: Color, done: Callable, prod: Dictionary = {}, p_net_cb: Callable = Callable()) -> Node3D:
	var rig: Node3D = (load("res://scripts/fx/first_person_smoke.gd") as Script).new()
	rig.name = "FirstPersonSmoke"
	rig.cam = camera
	rig.on_done = done
	rig.net_cb = p_net_cb
	rig._apply_product(prod)
	camera.add_child(rig)
	rig._build(sleeve)
	return rig

## Reads the chosen brand (see vice_catalog.gd) into this session's parameters.
func _apply_product(prod: Dictionary) -> void:
	product = prod
	var id: String = str(prod.get("id", "cigarette:default"))
	if id != product_id:
		# A different brand/kind: the old one is thrown away and a fresh one starts.
		if resting != null and is_instance_valid(resting):
			resting.queue_free()
		resting = null
		burn = 1.0
		product_id = id
	if prod.is_empty():
		return
	is_cigar = str(prod.get("kind", "cigarette")) == "cigar"
	var len_mul: float = float(prod.get("len", 1.0))
	if is_cigar:
		tobacco_len = BASE_TOBACCO_LEN * 1.7 * len_mul
		filter_len = 0.05
		stick_r = 0.023 * 1.5 * float(prod.get("girth", 1.0))
		cig_scale = 1.3
		drag_per_pull = 0.2
		paper_col = prod.get("wrapper", Color(0.42, 0.26, 0.12))
		filter_col = paper_col.darkened(0.15)
		pack_col = prod.get("box", Color(0.35, 0.2, 0.1))
	else:
		tobacco_len = BASE_TOBACCO_LEN * len_mul
		paper_col = prod.get("paper", paper_col)
		filter_col = prod.get("filter", filter_col)
		pack_col = prod.get("pack", pack_col)
	band_col = prod.get("band", band_col)
	burn_per_pull = float(prod.get("burn", BASE_BURN_PER_PULL))


func _build(sleeve: Color) -> void:
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.85, 0.65)
	fill.light_energy = 0.35
	fill.omni_range = VFP.DEPTH * 1.6
	fill.position = Vector3(0, VFP.DEPTH * 0.3, -VFP.DEPTH * 0.4)
	add_child(fill)
	_off = VFP._at(cam, -0.8, -1.9, VFP.DEPTH)
	_rest = VFP._at(cam, -0.62, -0.72, VFP.DEPTH)
	_lips = VFP._at(cam, -0.1, -1.0, VFP.DEPTH * 0.62)
	_hand = EmoteRig.build_fist(VFP.SKIN, sleeve)
	_hand.scale = Vector3.ONE * VFP._fist_scale(cam)
	_hand.position = _off
	_hand.rotation_degrees = REST_ROT
	add_child(_hand)
	VFP._capture_head(cam)
	if burn >= 1.0:
		_intro_new_cigarette(sleeve)
	elif resting != null and is_instance_valid(resting) and ashtray != null and is_instance_valid(ashtray):
		_pick_up_from_ashtray()
	else:
		_make_cigarette()
		_set_lit(true)
		_apply_burn()
		var tw := create_tween()
		tw.tween_property(_hand, "position", _rest, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: _enter_ready())

# ── Cigarette ─────────────────────────────────────────────────────────

## A cigarette whose tobacco length follows `burn`: fixed filter, a scalable
## paper body, a grey ash cap and a glowing ember at the tip.
func _make_cigarette(parent: Node3D = null) -> void:
	_cig = Node3D.new()
	_cig.scale = Vector3.ONE * cig_scale
	_cig.position = Vector3(0.12, 0.02, -0.06)
	(parent if parent != null else _hand).add_child(_cig)
	var stick := Node3D.new()
	stick.rotation_degrees = Vector3(-50.0, -30.0, 0.0)  # lit end up-and-out
	_cig.add_child(stick)
	var filt := EmoteRig._cyl(stick_r * 1.04, filter_len, EmoteRig._mat(filter_col))
	filt.position = Vector3(0, filter_len * 0.5, 0)
	stick.add_child(filt)
	if is_cigar:
		# Paper band around the cigar near the mouth end.
		var ring := EmoteRig._cyl(stick_r * 1.12, 0.05, EmoteRig._mat(band_col, 0.0, 0.3))
		ring.position = Vector3(0, filter_len + 0.06, 0)
		stick.add_child(ring)
	elif str(product.get("name", "")) != "":
		# Thin brand ring on the filter.
		var ring2 := EmoteRig._cyl(stick_r * 1.06, 0.008, EmoteRig._mat(band_col, 0.0, 0.3))
		ring2.position = Vector3(0, filter_len - 0.006, 0)
		stick.add_child(ring2)
	_body = Node3D.new()
	_body.position = Vector3(0, filter_len, 0)
	stick.add_child(_body)
	var paper := EmoteRig._cyl(stick_r, tobacco_len, EmoteRig._mat(paper_col, 0.0, 0.8))
	paper.position = Vector3(0, tobacco_len * 0.5, 0)
	_body.add_child(paper)
	_ash = EmoteRig._cyl(stick_r * 1.02, 0.018, EmoteRig._mat(Color(0.5, 0.48, 0.46), 0.0, 1.0))
	stick.add_child(_ash)
	_ember_mat = EmoteRig._mat(Color(1.0, 0.4, 0.1), 0.0)
	_ember = EmoteRig._cyl(stick_r * 1.04, 0.012, _ember_mat)
	stick.add_child(_ember)
	_tip_light = OmniLight3D.new()
	_tip_light.light_color = Color(1.0, 0.45, 0.15)
	_tip_light.light_energy = 0.0
	_tip_light.omni_range = VFP.DEPTH * 0.5
	stick.add_child(_tip_light)
	_wisps = EmoteRig.smoke_particles(Juice.soft_texture(), 14, 2.4, VFP.DEPTH * 0.08, false)
	var wpm := _wisps.process_material as ParticleProcessMaterial
	wpm.initial_velocity_min = VFP.DEPTH * 0.08
	wpm.initial_velocity_max = VFP.DEPTH * 0.16
	wpm.gravity = Vector3(0, VFP.DEPTH * 0.12, 0)
	_wisps.emitting = false
	stick.add_child(_wisps)
	_apply_burn()

## Shortens the paper to the remaining tobacco and moves ash/ember/light/smoke
## to the new tip.
func _apply_burn() -> void:
	if _body == null:
		return
	var left := clampf(1.0 - burn, 0.0, 1.0)
	_body.scale = Vector3(1.0, maxf(left, 0.001), 1.0)
	var tip_y := filter_len + tobacco_len * left
	_ash.position = Vector3(0, tip_y + 0.004, 0)
	_ember.position = Vector3(0, tip_y + 0.012, 0)
	_tip_light.position = Vector3(0, tip_y + 0.02, 0)
	_wisps.position = Vector3(0, tip_y + 0.02, 0)
	_ash.visible = left > 0.02
	_ember.visible = left > 0.0

func _set_lit(on: bool) -> void:
	_glow = 2.2 if on else 0.0
	_ember_mat.emission_enabled = true
	_ember_mat.emission_energy_multiplier = _glow
	_ember_mat.albedo_color = Color(1.0, 0.4, 0.1) if on else Color(0.3, 0.28, 0.27)
	_wisps.emitting = on

# ── New cigarette: pack + lighter ─────────────────────────────────────

func _intro_new_cigarette(sleeve: Color) -> void:
	burn = 0.0
	# Pack held in the fist (cigarettes poking out of the open top).
	var pack := _make_pack()
	pack.position = Vector3(0.0, 0.12, -0.02)
	_hand.add_child(pack)
	_make_cigarette()
	_set_lit(false)
	_cig.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_callback(func() -> void: Sound.play(&"pack"))
	tw.tween_property(_hand, "position", VFP._at(cam, -0.34, -0.62, VFP.DEPTH), Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", Vector3(8.0, 10.0, -10.0), Juice.d(0.45))
	tw.tween_interval(Juice.d(0.2))
	# Pull one out: the pack drops away, the cigarette appears between the fingers.
	tw.tween_property(pack, "position", pack.position + Vector3(0, -0.9, 0.2), Juice.d(0.35)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_cig, "scale", Vector3.ONE * cig_scale, Juice.d(0.25)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(pack.queue_free)
	# To the lips.
	tw.tween_property(_hand, "position", _lips, Juice.d(0.4)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_hand, "rotation_degrees", LIPS_ROT, Juice.d(0.4))
	tw.tween_callback(func() -> void: _light_it(sleeve))

## Pack of noir-brand cigarettes (model units, held upright in the fist).
func _make_pack() -> Node3D:
	var pack := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.32, 0.1)
	bm.material = EmoteRig._mat(pack_col, 0.0, 0.6)
	box.mesh = bm
	box.position = Vector3(0, 0.16, 0)
	pack.add_child(box)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.245, 0.06, 0.105)
	bb.material = EmoteRig._mat(band_col, 0.2, 0.3)
	band.mesh = bb
	band.position = Vector3(0, 0.2, 0)
	pack.add_child(band)
	for k in range(3):
		var tipc := EmoteRig._cyl(0.022, 0.06, EmoteRig._mat(filter_col))
		tipc.position = Vector3(-0.06 + k * 0.06, 0.34 + (0.02 if k == 1 else 0.0), 0)
		pack.add_child(tipc)
	return pack

## A second fist brings a brass lighter to the tip: lid flips, flame, the
## ember catches, lid snaps shut, lighter leaves; then the hand settles.
func _light_it(sleeve: Color) -> void:
	if net_cb.is_valid():
		net_cb.call("light", {})
	var lighter_hand := EmoteRig.build_fist(VFP.SKIN, sleeve)
	lighter_hand.scale = _hand.scale
	lighter_hand.rotation_degrees = Vector3(10.0, -15.0, 20.0)
	add_child(lighter_hand)
	var zippo := Node3D.new()
	zippo.position = Vector3(0.0, 0.1, -0.05)
	lighter_hand.add_child(zippo)
	var brass := EmoteRig._mat(Color(0.79, 0.64, 0.36), 0.15, 0.25)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.2, 0.07)
	bm.material = brass
	body.mesh = bm
	body.position = Vector3(0, 0.1, 0)
	zippo.add_child(body)
	var lid_hinge := Node3D.new()
	lid_hinge.position = Vector3(0.07, 0.2, 0)  # hinge on the right edge
	zippo.add_child(lid_hinge)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.14, 0.08, 0.07)
	lm.material = brass
	lid.mesh = lm
	lid.position = Vector3(-0.07, 0.04, 0)
	lid_hinge.add_child(lid)
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.05
	fm.height = 0.17
	var fmat := EmoteRig._mat(Color(1.0, 0.7, 0.2), 8.0, 1.0, 0.95)
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.material = fmat
	flame.mesh = fm
	flame.position = Vector3(-0.02, 0.29, 0)
	flame.scale = Vector3.ZERO
	zippo.add_child(flame)
	# Soft halo so the flame reads at a glance.
	var halo := Sprite3D.new()
	halo.texture = Juice.soft_texture()
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.shaded = false
	halo.modulate = Color(1.0, 0.6, 0.2, 0.75)
	halo.pixel_size = 0.3 / 64.0
	flame.add_child(halo)
	var flame_light := OmniLight3D.new()
	flame_light.light_color = Color(1.0, 0.6, 0.25)
	flame_light.light_energy = 0.0
	flame_light.omni_range = VFP.DEPTH * 0.9
	flame_light.position = flame.position
	zippo.add_child(flame_light)

	# Where the flame must meet the cigarette tip (in rig space).
	var tip_rig := to_local(_ember.global_position)
	var flame_offset := lighter_hand.basis * (zippo.position + flame.position) * 1.0
	var target := tip_rig - flame_offset + Vector3(0, -VFP.DEPTH * 0.012, 0)
	lighter_hand.position = VFP._at(cam, 0.85, -1.9, VFP.DEPTH)

	var tw := create_tween()
	tw.tween_property(lighter_hand, "position", target, Juice.d(0.5)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: Sound.play(&"lighter"))
	tw.tween_property(lid_hinge, "rotation_degrees:z", -115.0, Juice.d(0.12))
	tw.tween_property(flame, "scale", Vector3.ONE, Juice.d(0.1)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flame_light, "light_energy", 1.4, Juice.d(0.1))
	# Draw the flame in: the tip catches (the first pull lights it).
	tw.tween_callback(func() -> void: Sound.play(&"inhale"))
	tw.tween_method(func(v: float) -> void:
		flame.scale = Vector3(1.0 + 0.15 * sin(v * 40.0), 1.0 + 0.25 * sin(v * 31.0), 1.0)
		flame_light.light_energy = 1.2 + 0.4 * sin(v * 23.0)
	, 0.0, 1.0, Juice.d(0.7))
	tw.tween_callback(func() -> void:
		_set_lit(true)
		_glow = 6.0)
	tw.tween_property(flame, "scale", Vector3.ZERO, Juice.d(0.08))
	tw.parallel().tween_property(flame_light, "light_energy", 0.0, Juice.d(0.08))
	tw.tween_property(lid_hinge, "rotation_degrees:z", 0.0, Juice.d(0.1))
	tw.tween_callback(func() -> void: Sound.play(&"lighter_close"))
	tw.tween_property(lighter_hand, "position", VFP._at(cam, 0.85, -1.9, VFP.DEPTH), Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(lighter_hand.queue_free)
	# First exhale after lighting up, then ready for pulls.
	tw.tween_callback(func() -> void:
		_drag = 0.6
		_begin_exhale())

# ── Interaction ───────────────────────────────────────────────────────

## One scroll tick: pull on the cigarette.
func inhale() -> void:
	# A pull during an exhale starts the next drag right away (responsive scroll).
	if phase == Phase.EXHALING:
		if _exhale_tw and _exhale_tw.is_valid():
			_exhale_tw.kill()
		phase = Phase.READY
	if phase != Phase.READY and phase != Phase.DRAGGING:
		return
	if burn >= 1.0:
		return
	_idle = 0.0
	_last_pull = _now
	_drag = minf(_drag + drag_per_pull, 1.6)
	burn = minf(burn + burn_per_pull, 1.0)
	_apply_burn()
	if phase == Phase.READY:
		phase = Phase.DRAGGING
		if net_cb.is_valid():
			net_cb.call("drag", {"burn": burn})
		Sound.play(&"inhale")
		var tw := create_tween()
		tw.tween_property(_hand, "position", _lips, Juice.d(0.22)).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(_hand, "rotation_degrees", LIPS_ROT, Juice.d(0.22))
		_tilt_to(VFP.LOOK_DOWN, 0.3)

## Put it away (S again). Takes effect once the current motion settles.
func finish() -> void:
	_finish_requested = true

## Remove instantly (Chamber / game over).
func abort() -> void:
	if net_cb.is_valid():
		net_cb.call("end", {"burn": burn})
	if _cig != null and is_instance_valid(_cig) and ashtray != null and is_instance_valid(ashtray):
		var smoke := _cig
		_cig = null
		smoke.reparent(ashtray, true)
		smoke.position = _tray_spot(burn >= 1.0)
		smoke.rotation = Vector3.ZERO
		var stick := smoke.get_child(0) as Node3D
		if stick:
			stick.rotation_degrees = Vector3(0, 0, -86.0)
		if burn >= 1.0:
			smoke.queue_free()
		else:
			resting = smoke
	VFP._release_head(cam)
	phase = Phase.DONE
	var cb := on_done
	on_done = Callable()
	queue_free()
	if cb.is_valid():
		cb.call()

func _process(delta: float) -> void:
	_now += delta
	# Ember eases toward its target: smoulder at rest, flare while pulling.
	if _cig != null and is_instance_valid(_tip_light) and _ember_mat.albedo_color.r > 0.9:
		var target := 2.2 if phase != Phase.DRAGGING else 3.5 + _drag * 3.5
		_glow = lerpf(_glow, target, clampf(delta * 6.0, 0.0, 1.0))
		_ember_mat.emission_energy_multiplier = _glow
		_tip_light.light_energy = _glow * 0.12
	match phase:
		Phase.DRAGGING:
			if _now - _last_pull > EXHALE_AFTER:
				_begin_exhale()
		Phase.READY:
			_idle += delta
			if _finish_requested or _idle > IDLE_END:
				_put_away()

func _enter_ready() -> void:
	phase = Phase.READY
	_idle = 0.0
	if burn >= 1.0:
		_burnt_out()

func _begin_exhale() -> void:
	phase = Phase.EXHALING
	var strength := clampf(_drag, 0.2, 1.6)
	_drag = 0.0
	var tw := create_tween()
	_exhale_tw = tw
	tw.tween_property(_hand, "position", _rest, Juice.d(0.35)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_hand, "rotation_degrees", REST_ROT, Juice.d(0.35))
	_tilt_to(VFP.HEAD_BACK * clampf(strength, 0.5, 1.3), 0.4)
	tw.tween_callback(func() -> void:
		Sound.play(&"exhale", -6.0 + strength * 4.0)
		_exhale(strength))
	tw.tween_interval(Juice.d(0.5 + strength * 0.5))
	tw.tween_callback(func() -> void: _tilt_to(0.0, 0.7))
	tw.tween_interval(Juice.d(0.35))
	tw.tween_callback(func() -> void: _enter_ready())

## Plume scaled by how long the drag was.
func _exhale(strength: float) -> void:
	var p := EmoteRig.smoke_particles(Juice.soft_texture(), int(10 + strength * 16.0), 2.2 + strength, VFP.DEPTH * (0.1 + 0.06 * strength), true)
	var pm := p.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = VFP.DEPTH * (0.5 + 0.4 * strength)
	pm.initial_velocity_max = VFP.DEPTH * (1.0 + 0.8 * strength)
	pm.damping_min = VFP.DEPTH * 0.5
	pm.damping_max = VFP.DEPTH * 0.9
	pm.gravity = Vector3(0, VFP.DEPTH * 0.08, 0)
	pm.spread = 14.0 + 10.0 * strength
	pm.turbulence_noise_strength = 0.15
	var xf := global_transform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-70.0), 0, 0)), VFP._at(cam, 0.0, -0.8, VFP.DEPTH * 0.6))
	cam.get_parent().add_child(p)
	p.global_transform = xf
	p.emitting = true
	p.finished.connect(p.queue_free)

## Smoked down to the filter: the ember dies and the butt is stubbed out in the ashtray.
func _burnt_out() -> void:
	phase = Phase.OUTRO
	_set_lit(false)
	if _wisps and is_instance_valid(_wisps):
		_wisps.emitting = false
	if ashtray != null and is_instance_valid(ashtray) and _cig != null:
		_stow(true)
		return
	# No ashtray around: flick it away like before.
	var butt := _cig
	var at := butt.global_transform
	_hand.remove_child(butt)
	add_child(butt)
	butt.global_transform = at
	_cig = null
	var tw := create_tween()
	tw.tween_property(_hand, "rotation_degrees", REST_ROT + Vector3(-25, 0, 35), Juice.d(0.12))
	tw.parallel().tween_property(butt, "position", butt.position + Vector3(VFP.DEPTH * 0.9, -VFP.DEPTH * 0.6, -VFP.DEPTH * 0.3), Juice.d(0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(butt, "rotation_degrees", butt.rotation_degrees + Vector3(0, 0, -540), Juice.d(0.5))
	tw.tween_callback(butt.queue_free)
	tw.tween_callback(func() -> void: _leave())

func _put_away() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.OUTRO
	_tilt_to(0.0, 0.3)
	if ashtray != null and is_instance_valid(ashtray) and _cig != null:
		_stow(false)
		return
	if _wisps and is_instance_valid(_wisps):
		_wisps.emitting = false
	_leave()

## The hand withdraws off-screen and the session ends.
func _leave() -> void:
	if net_cb.is_valid():
		net_cb.call("end", {"burn": burn})
	var tw := create_tween()
	tw.tween_property(_hand, "position", _off, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		VFP._release_head(cam)
		phase = Phase.DONE
		var cb := on_done
		on_done = Callable()
		if cb.is_valid():
			cb.call()
		queue_free())

## Where (ashtray-local) a resting smoke lies, or a butt is dropped.
func _tray_spot(butt: bool) -> Vector3:
	var f: float = ashtray.get_meta(&"f")
	if butt:
		return Vector3(randf_range(-0.2, 0.1) * f, 0.115 * f, randf_range(-0.2, 0.2) * f)
	var left := clampf(1.0 - burn, 0.0, 1.0)
	var len_w := (filter_len + tobacco_len * left) * cig_scale * f
	return Vector3(-len_w * 0.5, 0.135 * f, 0.05 * f)

## The hand carries the cigarette/cigar to the ashtray and lays it down (lit and
## smouldering), or drops the butt into it, then withdraws.
func _stow(butt: bool) -> void:
	var spot_local := _tray_spot(butt)
	var spot_world := ashtray.to_global(spot_local)
	var reach := to_local(spot_world) - _hand.basis * _cig.position
	var tw := create_tween()
	tw.tween_property(_hand, "position", reach, Juice.d(0.5)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", Vector3(30.0, 0.0, -10.0), Juice.d(0.5))
	tw.tween_callback(func() -> void:
		if _cig == null or not is_instance_valid(_cig) or ashtray == null or not is_instance_valid(ashtray):
			return
		var smoke := _cig
		_cig = null
		smoke.reparent(ashtray, true)
		var stick := smoke.get_child(0) as Node3D
		var t2 := smoke.create_tween()
		t2.tween_property(smoke, "position", spot_local, Juice.d(0.15))
		t2.parallel().tween_property(smoke, "rotation_degrees", Vector3(0, randf_range(-25.0, 25.0), 0), Juice.d(0.15))
		if stick:
			t2.parallel().tween_property(stick, "rotation_degrees", Vector3(0, 0, -86.0 if not butt else -80.0), Juice.d(0.15))
		Sound.play(&"glass_clink", -10.0, 1.4)
		if butt:
			var butts: Array = ashtray.get_meta(&"butts")
			butts.append(smoke)
			while butts.size() > 5:
				var old = butts.pop_front()
				if is_instance_valid(old):
					old.queue_free()
			resting = null
			burn = 1.0
		else:
			resting = smoke)
	tw.tween_interval(Juice.d(0.18))
	tw.tween_callback(func() -> void: _leave())

## A lit smoke lies in the ashtray: reach down, pick it up, bring it to the lips.
func _pick_up_from_ashtray() -> void:
	var lying := resting
	resting = null
	var xf := lying.global_transform
	_make_cigarette(lying.get_parent())   # temporary parent so the model exists
	_cig.reparent(cam.get_parent(), true)
	_cig.global_transform = xf
	var lying_stick := lying.get_child(0) as Node3D
	var st := _cig.get_child(0) as Node3D
	if lying_stick and st:
		st.rotation_degrees = lying_stick.rotation_degrees
	lying.queue_free()
	_set_lit(true)
	_apply_burn()
	var reach := to_local(_cig.global_position) - _hand.basis * Vector3(0.12, 0.02, -0.06)
	var tw := create_tween()
	tw.tween_property(_hand, "position", reach, Juice.d(0.5)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", Vector3(30.0, 0.0, -10.0), Juice.d(0.5))
	tw.tween_callback(func() -> void:
		var at := _cig.global_transform
		_cig.reparent(_hand, true)
		_cig.global_transform = at
		var t2 := _cig.create_tween().set_parallel()
		t2.tween_property(_cig, "position", Vector3(0.12, 0.02, -0.06), Juice.d(0.2))
		t2.tween_property(_cig, "rotation", Vector3.ZERO, Juice.d(0.2))
		t2.tween_property(_cig, "scale", Vector3.ONE * cig_scale, Juice.d(0.2))
		if st:
			t2.tween_property(st, "rotation_degrees", Vector3(-50.0, -30.0, 0.0), Juice.d(0.2)))
	tw.tween_interval(Juice.d(0.22))
	tw.tween_property(_hand, "position", _rest, Juice.d(0.4)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hand, "rotation_degrees", REST_ROT, Juice.d(0.4))
	tw.tween_callback(func() -> void: _enter_ready())

func _tilt_to(deg: float, dur: float) -> void:
	if _tilt_tw and _tilt_tw.is_valid():
		_tilt_tw.kill()
	_tilt_tw = create_tween()
	VFP._head_to(_tilt_tw, cam, _tilt, deg, Juice.d(dur))
	_tilt_tw.parallel().tween_property(self, "_tilt", deg, Juice.d(dur))
