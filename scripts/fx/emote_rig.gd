extends RefCounted

## Builds the "vice" emotes for a Kenney blocky character: procedural props
## (a cigarette that hangs from the lips, a whiskey tumbler in the right hand)
## and hand-authored AnimationPlayer clips ("emotes/smoke", "emotes/drink")
## that raise the right arm to the mouth, tilt the head, and tip the glass.
##
## The rig is rigid-part: torso / arm-* / head are separate meshes rotated by
## quaternion tracks (identity rest pose). In torso space the right shoulder
## pivot is (-0.4, 1.1, -0.1), the head origin (0, 1.2, 0) at scale 0.1 and
## the mouth ≈ (-0.1, 1.45, 0.42). The model faces +Z.

const LIB := "emotes"
const SHOULDER := Vector3(-0.4, 1.1, -0.1)
const HAND_SMOKE := Vector3(-0.15, 1.45, 0.62)
const HAND_DRINK := Vector3(-0.08, 1.38, 0.66)
const HAND_AIM := Vector3(-0.4, 1.1, 0.9)   # fist with the arm straight out (revolver duel)
const AIM_HOLD := 30.0
const SMOKE_LEN := 3.4
const DRINK_LEN := 2.9
## Props are oversized vs. the blocky proportions so they read at table distance.
const CIG_SCALE := 1.8
const GLASS_SCALE := 1.6

## Arm rotation that swings the hanging arm (-Y) to point at `hand_target`.
static func arm_to(hand_target: Vector3) -> Quaternion:
	return Quaternion(Vector3.DOWN, (hand_target - SHOULDER).normalized())

static func head_tilt(deg: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, deg_to_rad(deg))

## Finds "<prefix>/root/torso/<part>" from the idle clip's track paths.
static func part_path(anim: AnimationPlayer, part: String) -> String:
	var idle: Animation = anim.get_animation("idle") if anim.has_animation("idle") else null
	if idle:
		for t in idle.get_track_count():
			var p := String(idle.track_get_path(t))
			if p.ends_with("/" + part):
				return p
	return ""

# ── Props ─────────────────────────────────────────────────────────────

static func _mat(col: Color, emissive: float = 0.0, rough: float = 0.6, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.roughness = rough
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive
	return m

static func _cyl(radius: float, height: float, mat: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = 12
	c.rings = 1
	c.material = mat
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Cigarette on the lips: a PropRoot under the head (scale 10 cancels the
## head's 0.1 so the geometry is in model units).
static func make_cigarette(head: Node3D, soft_tex: Texture2D, cigar: bool = false) -> Node3D:
	var root := build_cigarette(soft_tex)
	root.name = "Cigar" if cigar else "Cigarette"
	root.position = Vector3(-1.0, 1.9, 4.0)  # head-local: right side of the mouth (a tad lower)
	if cigar:
		# Fatter, brown, with a band: same rig, restyled.
		var stick0 := root.get_child(0) as Node3D
		stick0.scale = Vector3(1.55, 1.15, 1.55)
		for ch in stick0.get_children():
			var mi0 := ch as MeshInstance3D
			if mi0 and mi0.mesh is CylinderMesh:
				var cm0 := mi0.mesh as CylinderMesh
				if cm0.height > 0.15:
					cm0.material = _mat(Color(0.4, 0.24, 0.1), 0.0, 0.8)
				elif cm0.height > 0.05 and cm0.height < 0.1:
					cm0.material = _mat(Color(0.32, 0.2, 0.09))
		var ring := _cyl(0.028, 0.03, _mat(Color(0.85, 0.7, 0.25), 0.0, 0.3))
		ring.position = Vector3(0, 0.13, 0)
		stick0.add_child(ring)
	root.scale = Vector3.ONE * 10.0 * CIG_SCALE
	head.add_child(root)
	var stick := root.get_child(0) as Node3D
	stick.rotation_degrees = Vector3(100.0, -12.0, 0.0)  # forward, drooping, angled out
	return root

## Recolors a cigarette built by build_cigarette(): body paper + filter by their sizes.
static func style_cigarette(root: Node3D, paper: Color, filt: Color) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or not (mi.mesh is CylinderMesh):
			continue
		var cm := mi.mesh as CylinderMesh
		if cm.height > 0.15 and cm.height < 0.25:
			cm.material = _mat(paper, 0.0, 0.8)
		elif cm.height > 0.05 and cm.height < 0.1:
			cm.material = _mat(filt)

## Bare cigarette in model units: a "Stick" child running along +Y from the
## filter (origin) to the ember (~0.3). Meta "ember_mat" is the glowing tip's
## material; "TipLight" (OmniLight3D) and "Wisps" (particles) sit at the tip.
static func build_cigarette(soft_tex: Texture2D) -> Node3D:
	var root := Node3D.new()
	var stick := Node3D.new()
	stick.name = "Stick"
	root.add_child(stick)
	var filt := _cyl(0.024, 0.07, _mat(Color(0.78, 0.55, 0.3)))
	filt.position = Vector3(0, 0.035, 0)
	stick.add_child(filt)
	var body := _cyl(0.023, 0.2, _mat(Color(0.95, 0.94, 0.9), 0.0, 0.8))
	body.position = Vector3(0, 0.17, 0)
	stick.add_child(body)
	var ember_mat := _mat(Color(1.0, 0.4, 0.1), 3.0)
	var ember := _cyl(0.024, 0.03, ember_mat)
	ember.position = Vector3(0, 0.285, 0)
	stick.add_child(ember)
	root.set_meta(&"ember_mat", ember_mat)
	var tip := OmniLight3D.new()
	tip.name = "TipLight"
	tip.light_color = Color(1.0, 0.45, 0.15)
	tip.light_energy = 0.4
	tip.omni_range = 0.6
	tip.position = Vector3(0, 0.3, 0)
	stick.add_child(tip)
	var wisps := smoke_particles(soft_tex, 14, 2.4, 0.11, false)
	wisps.name = "Wisps"
	wisps.position = Vector3(0, 0.3, 0)
	stick.add_child(wisps)
	return root

## Whiskey tumbler held in the right hand (child of arm-right, model units).
static func make_glass(arm: Node3D) -> Node3D:
	var glass := build_glass()
	glass.name = "Glass"
	glass.position = Vector3(-0.2, -1.0, 0.24)  # just in front of the fist
	glass.set_meta(&"full_scale", GLASS_SCALE)
	arm.add_child(glass)
	return glass

## Bare tumbler in model units, origin at the base, ~0.24 tall. Meta "liquid"
## is the liquid pivot (animate scale.y for the level).
static func build_glass() -> Node3D:
	var glass := Node3D.new()
	var shell := _cyl(0.13, 0.24, _mat(Color(0.85, 0.93, 0.97), 0.0, 0.05, 0.42), 0.14)
	shell.position = Vector3(0, 0.12, 0)
	glass.add_child(shell)
	var base := _cyl(0.125, 0.04, _mat(Color(0.8, 0.9, 0.95), 0.0, 0.05, 0.3))
	base.position = Vector3(0, 0.02, 0)
	glass.add_child(base)
	var liquid_pivot := Node3D.new()
	liquid_pivot.position = Vector3(0, 0.04, 0)
	glass.add_child(liquid_pivot)
	var liquid := _cyl(0.118, 0.12, _mat(Color(0.85, 0.45, 0.08), 0.6, 0.2, 0.95), 0.122)
	liquid.position = Vector3(0, 0.06, 0)
	liquid_pivot.add_child(liquid)
	for k in range(2):
		var ice := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 0.07, 0.07)
		box.material = _mat(Color(0.9, 0.97, 1.0), 0.0, 0.05, 0.6)
		ice.mesh = box
		ice.position = Vector3(0.03 - k * 0.06, 0.1 + k * 0.01, -0.02 + k * 0.04)
		ice.rotation_degrees = Vector3(20 + k * 15, 35 - k * 50, 10)
		liquid_pivot.add_child(ice)
	glass.set_meta(&"liquid", liquid_pivot)
	return glass

## Kenney-style blocky fist (skin-tone box) used for the first-person hand.
static func build_fist(skin: Color, sleeve_col: Color = Color(0.14, 0.12, 0.16)) -> Node3D:
	var root := Node3D.new()
	var skin_mat := _mat(skin, 0.0, 0.85)
	# Fist (origin = the fist end; the arm hangs down along -Y).
	var fist := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.36, 0.34, 0.36)
	fb.material = skin_mat
	fist.mesh = fb
	fist.position = Vector3(0, -0.17, 0)
	fist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fist)
	# Thumb tucked against the side.
	var thumb := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.12, 0.22, 0.14)
	tb.material = skin_mat
	thumb.mesh = tb
	thumb.position = Vector3(0.2, -0.1, -0.05)
	thumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(thumb)
	# Finger creases on the front of the fist.
	var crease_mat := _mat(skin.darkened(0.35), 0.0, 0.9)
	for k in range(3):
		var crease := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(0.012, 0.3, 0.012)
		cbm.material = crease_mat
		crease.mesh = cbm
		crease.position = Vector3(-0.09 + k * 0.09, -0.17, -0.183)
		root.add_child(crease)
	# Wrist, shirt cuff, then the sleeve running off toward the camera.
	var wrist := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(0.27, 0.18, 0.27)
	wb.material = skin_mat
	wrist.mesh = wb
	wrist.position = Vector3(0, -0.43, 0)
	wrist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wrist)
	var cuff := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.36, 0.09, 0.36)
	cb.material = _mat(Color(0.93, 0.9, 0.84), 0.0, 0.8)
	cuff.mesh = cb
	cuff.position = Vector3(0, -0.56, 0)
	root.add_child(cuff)
	var sleeve := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.44, 1.2, 0.44)
	sb.material = _mat(sleeve_col, 0.0, 0.9)
	sleeve.mesh = sb
	sleeve.position = Vector3(0, -1.19, 0)
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sleeve)
	return root

## Soft grey smoke. `burst` = one-shot exhale cloud, else continuous wisps.
static func smoke_particles(soft_tex: Texture2D, amount: int, life: float, size: float, burst: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = burst
	p.explosiveness = 0.85 if burst else 0.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0.4) if burst else Vector3(0, 1, 0)
	pm.spread = 35.0 if burst else 12.0
	pm.initial_velocity_min = 0.25 if burst else 0.08
	pm.initial_velocity_max = 0.55 if burst else 0.16
	pm.gravity = Vector3(0, 0.12, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.83, 0.8, 0.0))
	g.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	g.add_point(0.15, Color(0.85, 0.83, 0.8, 0.5 if burst else 0.32))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex
	q.material = m
	p.draw_pass_1 = q
	return p

## One-shot exhale cloud in front of the mouth (parented to `head`).
static func exhale(head: Node3D, soft_tex: Texture2D) -> void:
	var p := smoke_particles(soft_tex, 18, 2.4, 0.22, true)
	var holder := Node3D.new()
	holder.position = Vector3(-0.6, 2.3, 4.6)
	holder.scale = Vector3.ONE * 10.0
	head.add_child(holder)
	holder.add_child(p)
	p.emitting = true
	p.finished.connect(holder.queue_free)

# ── Clips ─────────────────────────────────────────────────────────────

## Adds "emotes/smoke" and "emotes/drink" to the player (idempotent).
static func install_clips(anim: AnimationPlayer) -> void:
	if anim.has_animation_library(LIB):
		return
	var arm := part_path(anim, "arm-right")
	var head := part_path(anim, "head")
	if arm == "" or head == "":
		return
	var lib := AnimationLibrary.new()
	lib.add_animation("smoke", _smoke_clip(arm, head))
	lib.add_animation("drink", _drink_clip(arm, head))
	lib.add_animation("aim", _aim_clip(arm, head, false))
	lib.add_animation("recoil", _aim_clip(arm, head, true))
	anim.add_animation_library(LIB, lib)

static func _rot_track(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath(path))
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	for k: Array in keys:
		a.rotation_track_insert_key(t, float(k[0]), k[1])

static func _smoke_clip(arm: String, head: String) -> Animation:
	var a := Animation.new()
	a.length = SMOKE_LEN
	var up := arm_to(HAND_SMOKE)
	var I := Quaternion.IDENTITY
	# Hand to the lips, a long drag, back down; head lifts a touch on the drag.
	_rot_track(a, arm, [[0.0, I], [0.5, up], [1.55, up], [2.0, I], [SMOKE_LEN, I]])
	_rot_track(a, head, [[0.0, I], [0.6, head_tilt(-4.0)], [1.4, head_tilt(-9.0)], [2.1, head_tilt(-14.0)], [2.9, I], [SMOKE_LEN, I]])
	return a

## Right arm thrust straight out holding a revolver (held ~30 s, the duel ends it).
## With `recoil` the arm kicks up on the shot and settles back onto the target.
static func _aim_clip(arm: String, head: String, recoil: bool) -> Animation:
	var a := Animation.new()
	a.length = AIM_HOLD
	var aim := arm_to(HAND_AIM)
	var I := Quaternion.IDENTITY
	var lean := head_tilt(-3.0)
	if recoil:
		var kick := arm_to(HAND_AIM + Vector3(0.0, 0.55, -0.25))
		_rot_track(a, arm, [[0.0, aim], [0.06, kick], [0.55, aim], [AIM_HOLD, aim]])
		_rot_track(a, head, [[0.0, lean], [0.06, head_tilt(8.0)], [0.6, lean], [AIM_HOLD, lean]])
	else:
		_rot_track(a, arm, [[0.0, I], [0.3, aim], [AIM_HOLD, aim]])
		_rot_track(a, head, [[0.0, I], [0.3, lean], [AIM_HOLD, lean]])
	return a

static func _drink_clip(arm: String, head: String) -> Animation:
	var a := Animation.new()
	a.length = DRINK_LEN
	var up := arm_to(HAND_DRINK)
	var I := Quaternion.IDENTITY
	_rot_track(a, arm, [[0.0, I], [0.55, up], [1.5, up], [2.05, I], [DRINK_LEN, I]])
	_rot_track(a, head, [[0.0, I], [0.6, head_tilt(-14.0)], [1.4, head_tilt(-24.0)], [2.0, I], [DRINK_LEN, I]])
	# Glass: upright → tipped toward the mouth (rim back/up) → upright.
	var glass_peak := up.inverse() * Quaternion(Vector3.UP, Vector3(0.0, 0.15, -1.0).normalized())
	var glass_mid := Quaternion.IDENTITY.slerp(glass_peak, 0.55)
	_rot_track(a, arm + "/Glass", [[0.0, I], [0.55, glass_mid], [1.35, glass_peak], [2.05, I], [DRINK_LEN, I]])
	return a
