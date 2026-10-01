extends Node3D

## The Chamber, fully in 3D. When a bomb is drawn, a random OTHER player picks up
## a revolver and points it at the player who drew it. The gun (procedural mesh:
## steel frame, brass trim, walnut grip, spinning six-shot drum, cocking hammer)
## is held in the shooter's outstretched fist — a Kenney avatar's real arm, or a
## first-person fist when the local player is the shooter. When the local player
## is the target, the barrel points straight down the camera.
##
## Sequence (awaited by game.gd):  intro() → spin() → cock() → fire(kind) → finish()
## kind: &"live" (lethal shot), &"blank" (dry click), &"backfire" (the gun blows
## in the shooter's hand), &"lucky" (gold "LUCKY!" bang).
##
## Every effect is a real 3D object — muzzle flash + light + shock ring, tracer
## bullet in bullet-time, particle sparks / smoke / blood mist, recoil, a spotlight
## on the target, a camera that swings to frame the duel and a gun that twirls in
## and (on backfire) flies out of the shooter's hand.

signal chamber_click                  ## the drum passed a chamber while spinning
signal sfx(event: StringName)         ## physical sounds (game.gd routes to AudioManager)
signal shake(amount: float)           ## screen-shake request (0..1)
signal screen_flash(color: Color, duration: float)
signal victim_hit                     ## the bullet landed (game.gd plays the death)

const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const Juice := preload("res://scripts/fx/juice.gd")
const VFP := preload("res://scripts/fx/vice_first_person.gd")

const GUN_REACH := 0.72        ## grip → muzzle, in gun model units
const AI_GUN_MULT := 1.5       ## gun size relative to an avatar's model units
const FP_GUN_SCREEN := 0.5     ## first-person gun length as a fraction of screen height
const FP_DEPTH := 0.5          ## world units in front of the lens for the first-person gun
const SKIN := Color(0.93, 0.76, 0.6)

var camera: Camera3D
var shooter_actor: Node3D      ## null → the local player holds the gun (first person)
var victim_actor: Node3D       ## null → the local player is the target
var unit: float = 0.3          ## world size of one avatar model unit
var seat_color: Color = Color(0.85, 0.65, 0.25)
var font: Font                 ## for the "LUCKY!" label (optional)
var gun_scale: float = 0.3

var _gun: Node3D
var _model: Node3D
var _drum: Node3D
var _hammer: Node3D
var _muzzle: Node3D
var _fist: Node3D
var _spot: SpotLight3D
var _flying := false
var _kick := Vector3.ZERO      ## recoil offset (world units)
var _kick_rot := 0.0           ## recoil / twirl pitch (radians, + = muzzle up)
var _shake_amp := 0.0
var _last_step := 0
var _fp_local := Vector3.ZERO
var _cam_home: Transform3D
var _cam_framed := false
var _slowmo_on := false

static var _tex_cache: Dictionary = {}

# ── Setup ─────────────────────────────────────────────────────────────

## Call after adding to the 3D world. `shooter`/`victim` are CharacterActor
## nodes, or null for the local player's own seat.
func setup(cam: Camera3D, shooter: Node3D, victim: Node3D, world_unit: float, color: Color) -> void:
	camera = cam
	shooter_actor = shooter
	victim_actor = victim
	unit = maxf(world_unit, 0.01)
	seat_color = color

func _exit_tree() -> void:
	if _slowmo_on:
		Engine.time_scale = 1.0

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

# ── Positions ─────────────────────────────────────────────────────────

func _victim_target() -> Vector3:
	if victim_actor != null and is_instance_valid(victim_actor):
		return victim_actor.to_global(Vector3(0.0, 1.2, 0.05))
	return camera.global_position + camera.global_basis.y * -0.01

func _shooter_head() -> Vector3:
	if shooter_actor != null and is_instance_valid(shooter_actor):
		return shooter_actor.to_global(Vector3(0.0, 1.25, 0.0))
	return camera.global_position

func _hand_pos() -> Vector3:
	if shooter_actor != null:
		if is_instance_valid(shooter_actor):
			return shooter_actor.aim_hand_pos()
		return _gun.global_position
	return camera.to_global(_fp_local)

# ── Frame update: keep the gun in the hand and aimed ──────────────────

func _process(_delta: float) -> void:
	if _gun == null or _flying or camera == null:
		return
	var hand := _hand_pos()
	var jitter := Vector3.ZERO
	if _shake_amp > 0.0:
		jitter = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amp
	_gun.global_position = hand + _kick + jitter
	var target := _victim_target()
	if hand.distance_to(target) > 0.01:
		_gun.look_at(target, Vector3.UP)
		if _kick_rot != 0.0:
			_gun.rotate_object_local(Vector3.RIGHT, _kick_rot)

# ── Gun model ─────────────────────────────────────────────────────────

func _box(size: Vector3, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Cylinder whose axis runs along Z (the barrel direction).
func _cyl_z(radius: float, length: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := EmoteRig._cyl(radius, length, mat)
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mi.position = pos
	return mi

func _build_revolver_parts() -> void:
	var steel := EmoteRig._mat(Color(0.14, 0.15, 0.18), 0.0, 0.26)
	steel.metallic = 0.92
	var brass := EmoteRig._mat(Color(0.86, 0.62, 0.22), 0.0, 0.28)
	brass.metallic = 0.95
	var wood := EmoteRig._mat(Color(0.34, 0.17, 0.08), 0.0, 0.5)
	var black := EmoteRig._mat(Color(0.02, 0.02, 0.03), 0.0, 0.9)
	var inlay := EmoteRig._mat(seat_color, 1.4, 0.4)

	_model.add_child(_box(Vector3(0.07, 0.11, 0.16), steel, Vector3(0.0, 0.05, 0.08)))          # rear frame
	_model.add_child(_box(Vector3(0.05, 0.022, 0.26), steel, Vector3(0.0, 0.108, -0.06)))       # top strap
	_model.add_child(_box(Vector3(0.05, 0.03, 0.18), steel, Vector3(0.0, 0.0, -0.07)))          # lower frame
	_model.add_child(_cyl_z(0.022, 0.42, steel, Vector3(0.0, 0.085, -0.36)))                    # barrel
	_model.add_child(_box(Vector3(0.018, 0.014, 0.4), steel, Vector3(0.0, 0.118, -0.37)))       # rib
	_model.add_child(_box(Vector3(0.012, 0.024, 0.014), steel, Vector3(0.0, 0.13, -0.55)))      # front sight
	_model.add_child(_cyl_z(0.026, 0.014, brass, Vector3(0.0, 0.085, -0.575)))                  # muzzle crown
	_model.add_child(_cyl_z(0.03, 0.018, brass, Vector3(0.0, 0.085, -0.16)))                    # barrel collar
	_model.add_child(_box(Vector3(0.052, 0.15, 0.075), wood, Vector3(0.0, -0.06, 0.14), Vector3(-20.0, 0.0, 0.0)))  # grip
	_model.add_child(_box(Vector3(0.056, 0.012, 0.06), brass, Vector3(0.0, -0.132, 0.165), Vector3(-20.0, 0.0, 0.0)))  # butt cap
	_model.add_child(_box(Vector3(0.056, 0.03, 0.03), inlay, Vector3(0.0, -0.05, 0.125), Vector3(-20.0, 0.0, 0.0)))     # seat-colour inlay
	_model.add_child(_box(Vector3(0.01, 0.012, 0.11), steel, Vector3(0.0, -0.045, 0.02)))       # trigger guard (bottom)
	_model.add_child(_box(Vector3(0.01, 0.05, 0.012), steel, Vector3(0.0, -0.022, -0.033)))     # trigger guard (front)
	_model.add_child(_box(Vector3(0.008, 0.036, 0.01), brass, Vector3(0.0, -0.012, 0.03), Vector3(15.0, 0.0, 0.0)))  # trigger

	# Six-shot drum: pivot spins about Z. Dark bores + brass round noses on both faces.
	_drum = Node3D.new()
	_drum.name = "Drum"
	_drum.position = Vector3(0.0, 0.06, -0.09)
	_model.add_child(_drum)
	_drum.add_child(_cyl_z(0.056, 0.12, steel, Vector3.ZERO))
	_drum.add_child(_cyl_z(0.058, 0.014, brass, Vector3(0.0, 0.0, 0.058)))
	for k in range(6):
		var a: float = TAU * float(k) / 6.0
		var off := Vector3(cos(a) * 0.034, sin(a) * 0.034, 0.0)
		_drum.add_child(_cyl_z(0.0125, 0.123, black, off))
		_drum.add_child(_cyl_z(0.0105, 0.012, brass, off + Vector3(0.0, 0.0, 0.062)))

	# Hammer pivots at the rear of the top strap.
	_hammer = Node3D.new()
	_hammer.name = "Hammer"
	_hammer.position = Vector3(0.0, 0.118, 0.15)
	_model.add_child(_hammer)
	_hammer.add_child(_box(Vector3(0.02, 0.05, 0.026), steel, Vector3(0.0, 0.02, 0.008), Vector3(-10.0, 0.0, 0.0)))
	_hammer.add_child(_box(Vector3(0.022, 0.012, 0.03), brass, Vector3(0.0, 0.046, 0.018)))

	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, 0.085, -0.6)
	_model.add_child(_muzzle)


func _build_gun() -> void:
	_gun = Node3D.new()
	_gun.name = "Revolver"
	add_child(_gun)
	_model = Node3D.new()
	_model.position = Vector3(0.0, 0.06, -0.14)   # grip centre → gun origin
	_gun.add_child(_model)

	_build_revolver_parts()

	# A little key light so the steel isn't black in the dark scene.
	var glint := OmniLight3D.new()
	glint.light_color = Color(1.0, 0.9, 0.75)
	glint.light_energy = 0.9
	glint.omni_range = 4.0
	glint.position = Vector3(0.0, 0.35, 0.3)
	_gun.add_child(glint)

	# Gun scale: avatar-relative, or sized to the screen for the first-person hand.
	if shooter_actor != null:
		gun_scale = maxf(shooter_actor.scale.x, 0.01) * AI_GUN_MULT
	else:
		var half_h: float = VFP._half_h(camera, FP_DEPTH)
		gun_scale = (half_h * 2.0 * FP_GUN_SCREEN) / GUN_REACH
		_fp_local = VFP._at(camera, 0.5, -0.6, FP_DEPTH)
		_fist = EmoteRig.build_fist(SKIN, seat_color.darkened(0.55))
		_fist.position = Vector3(0.0, -0.01, 0.03)
		_fist.scale = Vector3.ONE * 0.32
		_fist.quaternion = Quaternion(Vector3.DOWN, Vector3(0.0, -0.55, 0.85).normalized())
		_gun.add_child(_fist)
	_gun.scale = Vector3.ONE * gun_scale * 0.001
	_glint_light_scale(glint)

func _glint_light_scale(l: OmniLight3D) -> void:
	l.omni_range = 6.0 * gun_scale

# ── Camera + spotlight ────────────────────────────────────────────────

func _focus_point() -> Vector3:
	if victim_actor == null:
		return _shooter_head()          # the gun is pointed at you
	if shooter_actor == null:
		return _victim_target()         # you are the gunman
	return (_shooter_head() + _victim_target()) * 0.5

## Swings the seat camera round to frame the duel and pushes in on the action
## (much closer when you are the target, so you can see the gunman). Restored
## in finish().
func _frame_camera(dur: float) -> void:
	if camera == null or Juice.reduced_motion():
		return
	_cam_home = camera.global_transform
	var focus := _focus_point()
	if focus.distance_to(_cam_home.origin) < 0.05:
		return
	var push: float = 0.4 if victim_actor == null else 0.2
	var p0: Vector3 = _cam_home.origin
	var p1: Vector3 = p0.lerp(focus, push)
	var q0 := _cam_home.basis.get_rotation_quaternion()
	var q1 := Transform3D(Basis(), p0).looking_at(focus, Vector3.UP).basis.get_rotation_quaternion()
	_cam_framed = true
	var cam := camera
	var swing := func(t: float) -> void:
		if is_instance_valid(cam):
			cam.global_basis = Basis(q0.slerp(q1, t))
			cam.global_position = p0.lerp(p1, t)
	create_tween().tween_method(swing, 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _restore_camera(dur: float) -> Tween:
	if not _cam_framed or camera == null or not is_instance_valid(camera):
		return null
	_cam_framed = false
	var q0 := camera.global_basis.get_rotation_quaternion()
	var q1 := _cam_home.basis.get_rotation_quaternion()
	var p0: Vector3 = camera.global_position
	var p1: Vector3 = _cam_home.origin
	var cam := camera
	var swing := func(t: float) -> void:
		if is_instance_valid(cam):
			cam.global_basis = Basis(q0.slerp(q1, t))
			cam.global_position = p0.lerp(p1, t)
	var tw := create_tween()
	tw.tween_method(swing, 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return tw

## A hard cone of light dropped on the target — the room goes quiet around them.
func _spotlight() -> void:
	if victim_actor == null:
		return
	var pos := _victim_target()
	_spot = SpotLight3D.new()
	add_child(_spot)
	_spot.global_position = pos + Vector3(0.25, 5.0, 0.25) * unit
	_spot.look_at(pos, Vector3.RIGHT)
	_spot.spot_range = 10.0 * unit
	_spot.spot_angle = 16.0
	_spot.spot_attenuation = 0.6
	_spot.light_color = Color(1.0, 0.86, 0.68)
	_spot.light_energy = 0.0
	create_tween().tween_property(_spot, "light_energy", 12.0, 0.8).set_trans(Tween.TRANS_SINE)

# ── Sequence ──────────────────────────────────────────────────────────

## The shooter squares up, the revolver twirls into the hand.
func intro() -> void:
	_frame_camera(1.0)
	_spotlight()
	if shooter_actor != null and is_instance_valid(shooter_actor):
		shooter_actor.aim_at(_victim_target(), 0.4)
		await _wait(0.42)
	_build_gun()
	_kick_rot = -TAU
	sfx.emit(&"hammer_cock")
	var tw := create_tween().set_parallel()
	tw.tween_property(_gun, "scale", Vector3.ONE * gun_scale, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_kick_rot", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# A little glint as the steel catches the light.
	_glow(_muzzle.global_position, Color(1.0, 0.95, 0.8), 0.5 * gun_scale, 0.35, _tex_star())
	await tw.finished
	await _wait(0.15)

## Spins the drum with ratcheting clicks; lands on a random chamber.
func spin(revs: int, dur: float) -> void:
	var total: float = TAU * float(revs) + TAU / 6.0 * float(randi() % 6)
	var step_angle := TAU / 6.0
	_last_step = 0
	var spin_fn := func(a: float) -> void:
		if _drum == null:
			return
		_drum.rotation.z = a
		var s: int = int(a / step_angle)
		if s != _last_step:
			_last_step = s
			chamber_click.emit()
	var tw := create_tween()
	tw.tween_method(spin_fn, 0.0, total, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await tw.finished

## Thumb draws the hammer back; the whole gun starts to tremble.
func cock() -> void:
	sfx.emit(&"hammer_cock")
	if _hammer:
		create_tween().tween_property(_hammer, "rotation:x", 0.75, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shake_amp = 0.012 * gun_scale
	await _wait(0.3)

func fire(kind: StringName) -> void:
	_shake_amp = 0.0
	match kind:
		&"live": await _fire_live()
		&"blank": await _fire_blank()
		&"backfire": await _fire_backfire()
		&"lucky": await _fire_lucky()
		_: await _wait(0.5)

## Lowers the gun, drops the spotlight, swings the camera back, frees itself.
func finish() -> void:
	_shake_amp = 0.0
	if shooter_actor != null and is_instance_valid(shooter_actor):
		shooter_actor.aim_release()
	if _spot and is_instance_valid(_spot):
		create_tween().tween_property(_spot, "light_energy", 0.0, 0.4)
	var cam_tw := _restore_camera(0.7)
	if _gun and is_instance_valid(_gun) and not _flying:
		var tw := create_tween()
		tw.tween_property(_gun, "scale", Vector3.ONE * gun_scale * 0.001, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await tw.finished
	if cam_tw and cam_tw.is_valid():
		await cam_tw.finished
	else:
		await _wait(0.2)
	if _slowmo_on:
		Engine.time_scale = 1.0
		_slowmo_on = false
	queue_free()

# ── Shots ─────────────────────────────────────────────────────────────

func _hammer_fall() -> void:
	if _hammer:
		create_tween().tween_property(_hammer, "rotation:x", 0.0, 0.05)

func _recoil(strength: float) -> void:
	if _gun == null:
		return
	var back: Vector3 = _gun.global_basis.z.normalized() * 0.3 * gun_scale * strength
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "_kick", back, 0.05).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_kick_rot", 0.6 * strength, 0.05).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(self, "_kick", Vector3.ZERO, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "_kick_rot", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _fire_live() -> void:
	var muzzle: Vector3 = _muzzle.global_position
	var target := _victim_target()
	var fwd: Vector3 = (-_gun.global_basis.z).normalized()
	_hammer_fall()
	sfx.emit(&"gunshot")
	shake.emit(1.0)
	screen_flash.emit(Color(1.0, 0.95, 0.8, 0.85), 0.16)
	_muzzle_flash(muzzle, fwd, 1.0)
	_recoil(1.0)
	if shooter_actor != null and is_instance_valid(shooter_actor):
		shooter_actor.aim_recoil()
	_slowmo(0.2, 0.7)
	await _tracer(muzzle, target)
	if victim_actor != null and is_instance_valid(victim_actor):
		_impact(target, fwd)
		victim_actor.knockback(fwd, 0.4 * unit, 0.2)
	victim_hit.emit()
	await _wait(0.9)

## Effects anchored to the drum / hammer fall back to the gun itself, so every outcome keeps
## working (on every client) even after the gun was tossed or a part is missing.
func _breech_pos() -> Vector3:
	if _drum != null:
		return _drum.global_position
	return _gun.global_position if _gun != null else global_position

func _hammer_pos() -> Vector3:
	return _hammer.global_position if _hammer != null else _breech_pos()

func _fire_blank() -> void:
	var muzzle: Vector3 = _muzzle.global_position
	var fwd: Vector3 = (-_gun.global_basis.z).normalized()
	_hammer_fall()
	sfx.emit(&"blank")
	shake.emit(0.15)
	_recoil(0.2)
	# Nothing but a puff of stale powder and a few embers from the striker.
	var strike := _hammer_pos()
	_glow(strike, Color(1.0, 0.6, 0.25), 0.28 * gun_scale, 0.12)
	_burst(strike, Vector3.UP, Color(1.0, 0.85, 0.5), Color(1.0, 0.35, 0.1), 6, 1.2 * gun_scale, 0.35, 0.03 * gun_scale, 2.5 * gun_scale, 40, true)
	_smoke(muzzle, fwd, 0.22 * gun_scale, 8, Color(0.75, 0.75, 0.75))
	if shooter_actor != null and is_instance_valid(shooter_actor):
		shooter_actor.emote("emote_anger", 1.4)
	await _wait(1.1)

func _fire_backfire() -> void:
	var drum_pos: Vector3 = _breech_pos()
	var side: Vector3 = _gun.global_basis.x.normalized()
	_hammer_fall()
	sfx.emit(&"backfire")
	shake.emit(0.85)
	screen_flash.emit(Color(1.0, 0.5, 0.1, 0.55), 0.35)
	_glow(drum_pos, Color(1.0, 0.55, 0.15), 1.5 * gun_scale, 0.3)
	_glow(drum_pos, Color(1.0, 0.92, 0.65), 1.0 * gun_scale, 0.14, _tex_star())
	_ring(drum_pos, Color(1.0, 0.6, 0.2), 2.6 * gun_scale, 0.4)
	_light_flash(drum_pos, Color(1.0, 0.55, 0.2), 8.0, 8.0 * gun_scale, 0.3)
	_burst(drum_pos, side, Color(1.0, 0.9, 0.5), Color(1.0, 0.3, 0.05), 46, 5.5 * gun_scale, 0.9, 0.05 * gun_scale, 5.0 * gun_scale, 70, true)
	_burst(drum_pos, -side, Color(1.0, 0.9, 0.5), Color(1.0, 0.3, 0.05), 30, 4.5 * gun_scale, 0.8, 0.045 * gun_scale, 5.0 * gun_scale, 70, true)
	_smoke(drum_pos, Vector3.UP, 0.5 * gun_scale, 22, Color(0.25, 0.24, 0.24))
	# The drum rattles apart in the shooter's hand.
	if _drum:
		var rattle := create_tween()
		for i in range(6):
			rattle.tween_property(_drum, "rotation:z", _drum.rotation.z + randf_range(-0.5, 0.5), 0.04)
	_recoil(1.5)
	if shooter_actor != null and is_instance_valid(shooter_actor):
		shooter_actor.aim_recoil()
		shooter_actor.emote("emote_cross", 1.8)
		shooter_actor.knockback(_shooter_head() - _victim_target(), 0.3 * unit, 0.25)
	await _wait(0.3)
	_toss_gun()
	await _wait(1.0)

func _fire_lucky() -> void:
	var muzzle: Vector3 = _muzzle.global_position
	var fwd: Vector3 = (-_gun.global_basis.z).normalized()
	_hammer_fall()
	sfx.emit(&"blank")
	_recoil(0.5)
	await _wait(0.12)
	sfx.emit(&"lucky")
	shake.emit(0.25)
	screen_flash.emit(Color(1.0, 0.85, 0.4, 0.4), 0.5)
	var gold := Color(1.0, 0.82, 0.3)
	_glow(muzzle, gold, 1.3 * gun_scale, 0.4, _tex_star())
	_glow(muzzle, Color(1.0, 0.95, 0.75), 0.8 * gun_scale, 0.2)
	_ring(muzzle, gold, 2.4 * gun_scale, 0.5)
	_light_flash(muzzle, gold, 7.0, 8.0 * gun_scale, 0.5)
	_burst(muzzle, fwd + Vector3.UP * 0.7, Color(1.0, 0.95, 0.7), gold, 60, 5.0 * gun_scale, 1.4, 0.06 * gun_scale, 4.0 * gun_scale, 55, true)
	_burst(muzzle, Vector3.UP, Color(1.0, 1.0, 0.85), Color(1.0, 0.7, 0.2), 30, 3.0 * gun_scale, 1.6, 0.05 * gun_scale, 2.0 * gun_scale, 30, true)
	_pop_label("LUCKY!", muzzle + Vector3.UP * 0.3 * gun_scale, gold)
	if victim_actor != null and is_instance_valid(victim_actor):
		var head := _victim_target()
		_glow(head, gold, 1.1 * unit, 0.6)
		_burst(head + Vector3.UP * 0.3 * unit, Vector3.UP, Color(1.0, 0.95, 0.7), gold, 34, 2.4 * unit, 1.5, 0.05 * unit, 1.5 * unit, 90, true)
	if shooter_actor != null and is_instance_valid(shooter_actor):
		shooter_actor.emote("emote_stars", 1.8)
	await _wait(1.3)

# ── Effects ───────────────────────────────────────────────────────────

func _muzzle_flash(pos: Vector3, fwd: Vector3, s: float) -> void:
	var g := gun_scale * s
	_glow(pos + fwd * 0.1 * g, Color(1.0, 0.95, 0.75), 1.6 * g, 0.1, _tex_star())
	_glow(pos + fwd * 0.2 * g, Color(1.0, 0.6, 0.2), 1.0 * g, 0.18)
	_ring(pos + fwd * 0.15 * g, Color(1.0, 0.75, 0.4), 2.2 * g, 0.28)
	_light_flash(pos, Color(1.0, 0.72, 0.38), 9.0, 10.0 * g, 0.16)
	_burst(pos, fwd, Color(1.0, 0.97, 0.75), Color(1.0, 0.5, 0.1), 34, 6.0 * g, 0.5, 0.05 * g, 4.0 * g, 22, true)
	_burst(pos, fwd, Color(1.0, 0.8, 0.4), Color(0.9, 0.25, 0.05), 16, 3.0 * g, 0.9, 0.035 * g, 7.0 * g, 60, true)
	_smoke(pos, fwd, 0.4 * g, 26, Color(0.8, 0.8, 0.8))

## A brass bullet + hot streak crossing the table (runs in bullet-time).
func _tracer(from: Vector3, to: Vector3) -> void:
	var bullet := Node3D.new()
	add_child(bullet)
	bullet.global_position = from
	if from.distance_to(to) > 0.01:
		bullet.look_at(to, Vector3.UP)
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.9, 0.55)
	var core := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.03, 0.03, 0.16) * unit
	cb.material = core_mat
	core.mesh = cb
	bullet.add_child(core)
	var streak_mat := StandardMaterial3D.new()
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	streak_mat.albedo_color = Color(1.0, 0.7, 0.3, 0.7)
	var streak := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.012, 0.012, 1.6) * unit
	sb.material = streak_mat
	streak.mesh = sb
	streak.position = Vector3(0.0, 0.0, 0.85 * unit)
	bullet.add_child(streak)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.light_energy = 2.5
	light.omni_range = 2.0 * unit
	bullet.add_child(light)
	var dur: float = 0.09
	var tw := create_tween()
	tw.tween_property(bullet, "global_position", to, dur)
	await tw.finished
	bullet.queue_free()

## Blood mist, sparks, smoke and a red flash where the bullet lands.
func _impact(pos: Vector3, fwd: Vector3) -> void:
	_glow(pos, Color(1.0, 0.35, 0.2), 0.7 * unit, 0.22)
	_ring(pos, Color(1.0, 0.4, 0.3), 1.6 * unit, 0.3)
	_light_flash(pos, Color(1.0, 0.2, 0.12), 7.0, 5.0 * unit, 0.3)
	_burst(pos, fwd, Color(0.85, 0.04, 0.05), Color(0.35, 0.0, 0.02), 40, 3.4 * unit, 0.9, 0.09 * unit, 6.0 * unit, 50, false)
	_burst(pos, fwd, Color(1.0, 0.85, 0.45), Color(1.0, 0.3, 0.1), 18, 4.2 * unit, 0.45, 0.035 * unit, 8.0 * unit, 55, true)
	_smoke(pos, Vector3.UP, 0.55 * unit, 14, Color(0.5, 0.45, 0.45))

## The revolver leaves the shooter's hand, tumbling end over end.
func _toss_gun() -> void:
	if _gun == null:
		return
	_flying = true
	var gun := _gun
	var p0: Vector3 = gun.global_position
	var back: Vector3 = (_shooter_head() - _victim_target())
	back.y = 0.0
	back = back.normalized() if back.length() > 0.001 else Vector3.BACK
	var vel: Vector3 = (Vector3.UP * 2.4 + back * 1.3 + gun.global_basis.x.normalized() * 0.9) * unit
	var grav: float = 5.5 * unit
	var rot0: Vector3 = gun.rotation
	var fly := func(t: float) -> void:
		if not is_instance_valid(gun):
			return
		gun.global_position = p0 + vel * t + Vector3(0.0, -0.5 * grav * t * t, 0.0)
		gun.rotation = rot0 + Vector3(11.0, 4.0, 2.0) * t
	var tw := create_tween()
	tw.tween_method(fly, 0.0, 0.85, 0.85)
	tw.tween_property(gun, "scale", Vector3.ONE * 0.001, 0.15)
	tw.tween_callback(func() -> void:
		if is_instance_valid(gun):
			gun.queue_free())
	_gun = null

## Floating gold text that rises out of the barrel and fades.
func _pop_label(text: String, pos: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.0055 * maxf(gun_scale, unit * 0.5)
	l.modulate = col
	l.outline_size = 14
	l.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 8
	if font:
		l.font = font
	add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.1
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", pos + Vector3.UP * 1.2 * unit, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)

## Brief global slow-motion (real-time timer so it always ends).
func _slowmo(scale_to: float, real_seconds: float) -> void:
	if Juice.reduced_motion():
		return
	_slowmo_on = true
	Engine.time_scale = scale_to
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_slowmo_on = false

# ── Effect primitives ─────────────────────────────────────────────────

func _tex_soft() -> Texture2D:
	return Juice.soft_texture()

static func _tex_star() -> Texture2D:
	if _tex_cache.has(&"star"):
		return _tex_cache[&"star"]
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var fx: float = (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var fy: float = (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var ax: float = absf(fx)
			var ay: float = absf(fy)
			var r: float = sqrt(fx * fx + fy * fy)
			var spike: float = maxf(exp(-ay * 26.0) * (1.0 - ax), exp(-ax * 26.0) * (1.0 - ay))
			var v: float = clampf(spike + exp(-r * 4.5) * 0.9, 0.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, r))
			img.set_pixel(x, y, Color(1, 1, 1, v))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[&"star"] = tex
	return tex

static func _tex_ring() -> Texture2D:
	if _tex_cache.has(&"ring"):
		return _tex_cache[&"ring"]
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var fx: float = (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var fy: float = (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r: float = sqrt(fx * fx + fy * fy)
			var d: float = (r - 0.74) / 0.1
			var v: float = exp(-d * d) * (1.0 - smoothstep(0.86, 1.0, r))
			img.set_pixel(x, y, Color(1, 1, 1, v))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[&"ring"] = tex
	return tex

func _glow_material(tex: Texture2D, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = true
	m.render_priority = 6
	m.albedo_texture = tex
	m.albedo_color = col
	return m

## Expanding, fading additive sprite (flash / halo). Star texture by default soft.
func _glow(pos: Vector3, col: Color, size: float, dur: float, tex: Texture2D = null) -> void:
	var m := _glow_material(tex if tex != null else _tex_soft(), col)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.4
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.3, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

## Shock ring that blooms outward.
func _ring(pos: Vector3, col: Color, size: float, dur: float) -> void:
	var m := _glow_material(_tex_ring(), col)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.15
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)

func _light_flash(pos: Vector3, col: Color, energy: float, light_range: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = maxf(light_range, 0.5)
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)

## One-shot spark / mist burst. `glow` = additive (sparks); false = normal alpha (blood).
func _burst(pos: Vector3, dir: Vector3, col_a: Color, col_b: Color, amount: int, speed: float,
		life: float, size: float, gravity: float, spread: float, glow: bool) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3.ONE * -6.0 * unit, Vector3.ONE * 12.0 * unit)
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.0, -gravity, 0.0)
	pm.damping_min = 0.5
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.15))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, col_a)
	grad.set_color(1, Color(col_b, 0.0))
	grad.add_point(0.35, col_b)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _tex_soft()
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## Drifting smoke cloud (reuses the exhale particle look).
func _smoke(pos: Vector3, dir: Vector3, size: float, amount: int, tint: Color) -> void:
	var p := EmoteRig.smoke_particles(_tex_soft(), amount, 2.0, maxf(size, 0.01), true)
	p.visibility_aabb = AABB(Vector3.ONE * -6.0 * unit, Vector3.ONE * 12.0 * unit)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	pm.spread = 28.0
	pm.initial_velocity_min = 0.3 * unit
	pm.initial_velocity_max = 1.1 * unit
	pm.gravity = Vector3(0.0, 0.25 * unit, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(tint, 0.0))
	grad.set_color(1, Color(tint.darkened(0.2), 0.0))
	grad.add_point(0.15, Color(tint, 0.55))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
