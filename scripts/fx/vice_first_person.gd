extends RefCounted

## First-person 3D "vice" emotes for the LOCAL player. The seat camera IS the
## player's eyes, so everything is staged relative to it:
##  - the mouth sits just below the bottom-center of the view;
##  - smoking: a blocky fist brings the cigarette up from the lower-left to the
##    lips (camera dips to look at it), the ember flares on the drag, then the
##    head tips back (camera tilts up) and a 3D plume is exhaled over the felt;
##  - whiskey: the tumbler rises from the lower-right, meets the lips at the
##    bottom-center, the head tips back as the level drains, then it's set down.
## Props are parented to the Camera3D (lit by the table lamp, part of the 3D
## scene) and never block input.

const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const Juice := preload("res://scripts/fx/juice.gd")
const Sound := preload("res://scripts/sound.gd")

const SKIN := Color(0.93, 0.74, 0.58)
const DEPTH := 0.36           # world units in front of the lens (rest pose)
const FIST_SCREEN_H := 0.55   # fist+forearm height as a fraction of screen height
const LOOK_DOWN := -5.0       # head dips to look at the cigarette on the drag
const HEAD_BACK := 7.0        # head tips back on the exhale
const NEAR_DURING_VICE := 0.004
const HEAD_BACK_DRINK := 10.0 # head tips back while drinking

## `on_done` fires when the hand has left the view (the emote is over).
static func play(kind: StringName, camera: Camera3D, sleeve: Color, on_done: Callable = Callable()) -> void:
	if camera == null or not is_instance_valid(camera) or camera.has_node("FirstPersonVice"):
		if on_done.is_valid():
			on_done.call()
		return
	var rig := Node3D.new()
	rig.name = "FirstPersonVice"
	camera.add_child(rig)
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.85, 0.65)
	fill.light_energy = 0.35
	fill.omni_range = DEPTH * 1.6
	fill.position = Vector3(0, DEPTH * 0.3, -DEPTH * 0.4)
	rig.add_child(fill)
	rig.tree_exited.connect(func() -> void:
		if on_done.is_valid():
			on_done.call())
	match kind:
		&"smoke": _smoke(camera, rig, sleeve)
		&"drink": _drink(camera, rig, sleeve)
		_: rig.queue_free()

# ── Camera ("head") helpers ───────────────────────────────────────────

## Tilts the camera from `from_deg` to `to_deg` (pitch, + = look up) relative
## to its rest pose (captured once per emote so tweens can't drift).
static func _head_to(tw: Tween, cam: Camera3D, from_deg: float, to_deg: float, dur: float) -> void:
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(cam) and cam.has_meta(&"vice_rest_pitch"):
			cam.rotation.x = float(cam.get_meta(&"vice_rest_pitch")) + deg_to_rad(v)
	, from_deg, to_deg, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

static func _capture_head(cam: Camera3D) -> void:
	if not cam.has_meta(&"vice_rest_pitch"):
		cam.set_meta(&"vice_rest_pitch", cam.rotation.x)
		# The fist/arm live a few hundredths of a unit from the lens: pull the near
		# plane in so the hand is never sliced open by the camera's near clip.
		cam.set_meta(&"vice_rest_near", cam.near)
		cam.near = minf(cam.near, NEAR_DURING_VICE)

static func _release_head(cam: Camera3D) -> void:
	if is_instance_valid(cam) and cam.has_meta(&"vice_rest_pitch"):
		cam.rotation.x = float(cam.get_meta(&"vice_rest_pitch"))
		cam.remove_meta(&"vice_rest_pitch")
		if cam.has_meta(&"vice_rest_near"):
			cam.near = float(cam.get_meta(&"vice_rest_near"))
			cam.remove_meta(&"vice_rest_near")

# ── Screen-relative placement ─────────────────────────────────────────

static func _half_h(cam: Camera3D, d: float) -> float:
	return d * tan(deg_to_rad(cam.fov) * 0.5)

static func _aspect(cam: Camera3D) -> float:
	var vs := cam.get_viewport().get_visible_rect().size
	return vs.x / maxf(vs.y, 1.0)

## Camera-space point at normalized screen (fx, fy) ∈ [-1, 1] (y up), depth d.
static func _at(cam: Camera3D, fx: float, fy: float, d: float) -> Vector3:
	var hh := _half_h(cam, d)
	return Vector3(fx * hh * _aspect(cam), fy * hh, -d)

static func _fist_scale(cam: Camera3D) -> float:
	return _half_h(cam, DEPTH) * 2.0 * FIST_SCREEN_H

# ── Smoke ─────────────────────────────────────────────────────────────

static func _smoke(cam: Camera3D, rig: Node3D, sleeve: Color) -> void:
	var hand := EmoteRig.build_fist(SKIN, sleeve)
	hand.scale = Vector3.ONE * _fist_scale(cam)
	rig.add_child(hand)
	var cig := EmoteRig.build_cigarette(Juice.soft_texture())
	cig.scale = Vector3.ONE * 1.6
	cig.position = Vector3(0.12, 0.02, -0.06)
	(cig.get_child(0) as Node3D).rotation_degrees = Vector3(-50.0, -30.0, 0.0)  # lit end up-and-out
	hand.add_child(cig)
	var ember: StandardMaterial3D = cig.get_meta(&"ember_mat")
	var tip := cig.find_child("TipLight", true, false) as OmniLight3D
	if tip:
		tip.omni_range = DEPTH * 0.5
	var wisps := cig.find_child("Wisps", true, false) as GPUParticles3D
	if wisps:
		if wisps.draw_pass_1 is QuadMesh:
			(wisps.draw_pass_1 as QuadMesh).size = Vector2.ONE * DEPTH * 0.08
		var wpm := wisps.process_material as ParticleProcessMaterial
		wpm.initial_velocity_min = DEPTH * 0.08
		wpm.initial_velocity_max = DEPTH * 0.16
		wpm.gravity = Vector3(0, DEPTH * 0.12, 0)
		wisps.emitting = true

	# Poses: off-screen → resting low-left → at the lips (bottom-center, close).
	var off := _at(cam, -0.8, -1.9, DEPTH)
	var rest := _at(cam, -0.62, -0.72, DEPTH)
	var lips := _at(cam, -0.1, -1.0, DEPTH * 0.62)
	var rest_rot := Vector3(18.0, 20.0, -22.0)
	var lips_rot := Vector3(58.0, 12.0, -6.0)   # fist tipped so the cig points up/out of the mouth
	hand.position = off
	hand.rotation_degrees = rest_rot
	_capture_head(cam)
	Sound.play(&"lighter")
	var glow := func(e: float) -> void:
		ember.emission_energy_multiplier = e
		if tip:
			tip.light_energy = e * 0.15

	var tw := rig.create_tween()
	tw.tween_property(hand, "position", rest, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# To the lips — the head dips a touch to meet it.
	tw.tween_property(hand, "position", lips, Juice.d(0.45)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(hand, "rotation_degrees", lips_rot, Juice.d(0.45))
	_head_to(tw.parallel(), cam, 0.0, LOOK_DOWN, Juice.d(0.45))
	tw.tween_callback(func() -> void: Sound.play(&"inhale"))
	tw.tween_method(glow, 3.0, 8.0, Juice.d(0.85))
	# Away from the mouth; the head tips back and the smoke rolls out.
	tw.tween_method(glow, 8.0, 3.0, Juice.d(0.35))
	tw.parallel().tween_property(hand, "position", rest, Juice.d(0.4)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(hand, "rotation_degrees", rest_rot, Juice.d(0.4))
	_head_to(tw.parallel(), cam, LOOK_DOWN, HEAD_BACK, Juice.d(0.45))
	tw.tween_callback(func() -> void:
		Sound.play(&"exhale")
		_exhale(cam, rig))
	tw.tween_interval(Juice.d(0.7))
	_head_to(tw, cam, HEAD_BACK, 0.0, Juice.d(0.9))
	tw.tween_callback(func() -> void:
		if wisps:
			wisps.emitting = false)
	tw.tween_property(hand, "position", off, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _release_head(cam))
	tw.tween_callback(rig.queue_free)

## A plume of 3D smoke blown from the mouth (just below the view) out and up
## over the felt.
static func _exhale(cam: Camera3D, rig: Node3D) -> void:
	var p := EmoteRig.smoke_particles(Juice.soft_texture(), 22, 2.6, DEPTH * 0.16, true)
	p.position = _at(cam, 0.0, -0.8, DEPTH * 0.6)
	p.rotation_degrees = Vector3(-70.0, 0.0, 0.0)  # emitter +Y ≈ camera forward, tipped up
	var pm := p.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = DEPTH * 0.7
	pm.initial_velocity_max = DEPTH * 1.5
	pm.damping_min = DEPTH * 0.5
	pm.damping_max = DEPTH * 0.9
	pm.gravity = Vector3(0, DEPTH * 0.08, 0)
	pm.spread = 18.0
	pm.turbulence_noise_strength = 0.15
	# Lives in the world (not on the hand rig) so the plume keeps drifting after
	# the hand is gone, and frees itself when done.
	var world_parent := cam.get_parent()
	var xf := rig.global_transform * Transform3D(Basis.from_euler(p.rotation), p.position)
	p.position = Vector3.ZERO
	p.rotation = Vector3.ZERO
	world_parent.add_child(p)
	p.global_transform = xf
	p.emitting = true
	p.finished.connect(p.queue_free)

# ── Drink ─────────────────────────────────────────────────────────────

static func _drink(cam: Camera3D, rig: Node3D, sleeve: Color) -> void:
	var hand := EmoteRig.build_fist(SKIN, sleeve)
	hand.scale = Vector3.ONE * _fist_scale(cam)
	rig.add_child(hand)
	var glass := EmoteRig.build_glass()
	glass.scale = Vector3.ONE * 1.5
	glass.position = Vector3(-0.06, -0.3, -0.26)  # gripped in front of the fist
	hand.add_child(glass)
	var liquid: Node3D = glass.get_meta(&"liquid")

	var off := _at(cam, 0.82, -1.9, DEPTH)
	var rest := _at(cam, 0.62, -0.7, DEPTH)
	var lips := _at(cam, 0.08, -0.95, DEPTH * 0.66)
	var rest_rot := Vector3(10.0, -18.0, 18.0)
	var lips_rot := Vector3(62.0, -6.0, 6.0)    # rim tipped toward the mouth
	hand.position = off
	hand.rotation_degrees = rest_rot
	_capture_head(cam)
	Sound.play(&"glass_clink")
	var tw := rig.create_tween()
	tw.tween_property(hand, "position", rest, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Glass to the lips; the head tips back as you drink.
	tw.tween_property(hand, "position", lips, Juice.d(0.45)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(hand, "rotation_degrees", lips_rot, Juice.d(0.45)).set_trans(Tween.TRANS_SINE)
	_head_to(tw.parallel(), cam, 0.0, HEAD_BACK_DRINK, Juice.d(0.55))
	tw.tween_callback(func() -> void: Sound.play(&"gulp"))
	tw.tween_property(liquid, "scale:y", 0.3, Juice.d(0.75)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(hand, "position", rest, Juice.d(0.4)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(hand, "rotation_degrees", rest_rot, Juice.d(0.4))
	_head_to(tw.parallel(), cam, HEAD_BACK_DRINK, 0.0, Juice.d(0.5))
	tw.tween_callback(func() -> void: Sound.play(&"glass_clink"))
	tw.tween_property(hand, "position", off, Juice.d(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _release_head(cam))
	tw.tween_callback(rig.queue_free)
