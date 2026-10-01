extends Node3D

## The bartender ghost: a smooth, semi-transparent sheet ghost with a scalloped hem, hollow glowing
## eyes, a bow tie and a little top hat, white-gloved sleeves, a towel over one arm and a few
## drifting wisps. Procedural (no model assets).
##
## Local units: ~2.8 tall, hem at y=0, faces +Z (same yaw maths as the Kenney characters).
## `arm` is a pivot at the right shoulder; its sleeve and glove hang along -Y and ARM_LEN is the
## distance from the pivot to the middle of the glove, so the pour code can aim it with a quaternion.

const SHOULDER := Vector3(0.72, 1.7, 0.0)
const ARM_LEN := 0.85
const SHEET_ALPHA := 0.42
const DARK_ALPHA := 0.9

const SEGMENTS := 40
const RINGS := 34
## (height, radius) control points of the sheet, bottom to top; the dome closes it off.
const PROFILE := [[0.0, 0.9], [0.22, 0.84], [0.75, 0.72], [1.3, 0.66], [1.7, 0.64], [1.95, 0.6]]
const DOME_Y := 1.95
const DOME_R := 0.6
const DOME_H := 0.7

var anim = null        # (CharacterActor API compatibility: nothing to animate)
var model = null
var arm: Node3D
var _sheet: Array[StandardMaterial3D] = []
var _dark: Array[StandardMaterial3D] = []
var _glow: Array[StandardMaterial3D] = []
var _body: Node3D
var _light: OmniLight3D
var _eyes: Array[Node3D] = []
var _wisps: Array[Node3D] = []
var _alpha := 0.0
var _t := 0.0
var _blink_in := 2.5


func _init() -> void:
	_body = Node3D.new()
	add_child(_body)
	var sheet := _mat(Color(0.84, 0.92, 1.0), 0.5, SHEET_ALPHA, _sheet)
	sheet.rim_enabled = true
	sheet.rim = 0.8
	sheet.rim_tint = 0.5
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED   # see the inside of the sheet through the thin parts
	var shade := _mat(Color(0.7, 0.8, 0.97), 0.35, SHEET_ALPHA, _sheet)
	var dark := _mat(Color(0.02, 0.03, 0.07), 0.0, DARK_ALPHA, _dark)
	var cloth := _mat(Color(0.97, 0.97, 1.0), 0.25, DARK_ALPHA, _dark)       # gloves, towel
	var tie := _mat(Color(0.62, 0.06, 0.1), 0.35, DARK_ALPHA, _dark)          # bow tie, hat band

	# ── The sheet ────────────────────────────────────────────────────────
	var body := MeshInstance3D.new()
	body.mesh = _sheet_mesh()
	body.material_override = sheet
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(body)

	# ── Face: hollow eyes with a faint glow, and a small round mouth ─────
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.55, 0.9, 1.0, 0.0)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.append(glow)
	for k in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(0.22 * k, 2.1, 0.55)
		_body.add_child(eye)
		var socket := _sphere(0.115, Vector3(1.0, 1.45, 0.45), dark)
		eye.add_child(socket)
		var spark := _sphere(0.04, Vector3(1.0, 1.0, 0.6), glow)
		spark.position = Vector3(0.025 * k, 0.045, 0.045)
		eye.add_child(spark)
		_eyes.append(eye)
	var mouth := _sphere(0.085, Vector3(1.25, 1.0, 0.5), dark)
	mouth.position = Vector3(0, 1.93, 0.58)
	_body.add_child(mouth)

	# ── Waiter's kit: bow tie, top hat, towel ────────────────────────────
	for k in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.13
		cm.height = 0.2
		cm.radial_segments = 4
		wing.mesh = cm
		wing.material_override = tie
		wing.rotation_degrees = Vector3(0, 0, -90.0 * k)
		wing.position = Vector3(0.11 * k, 1.5, 0.645)
		wing.scale = Vector3(1.0, 1.0, 0.45)
		_body.add_child(wing)
	var knot := _sphere(0.055, Vector3(1.0, 1.0, 0.8), tie)
	knot.position = Vector3(0, 1.5, 0.665)
	_body.add_child(knot)
	var hat := Node3D.new()
	hat.position = Vector3(0.02, DOME_Y + DOME_H * 0.93, -0.02)
	hat.rotation_degrees = Vector3(-6.0, 0.0, 7.0)
	_body.add_child(hat)
	hat.add_child(_cyl(0.43, 0.43, 0.045, dark, 0.0))
	hat.add_child(_cyl(0.27, 0.29, 0.42, dark, 0.23))
	hat.add_child(_cyl(0.292, 0.292, 0.08, tie, 0.07))

	# ── Arms ─────────────────────────────────────────────────────────────
	arm = Node3D.new()
	arm.position = SHOULDER
	_body.add_child(arm)
	arm.add_child(_cyl(0.12, 0.16, 0.7, shade, -0.36))                 # sleeve (wider at the shoulder)
	var cuff := _cyl(0.145, 0.145, 0.06, cloth, -0.7)
	arm.add_child(cuff)
	var glove := _sphere(0.15, Vector3(1.0, 1.15, 1.0), cloth)
	glove.position = Vector3(0, -ARM_LEN, 0)
	arm.add_child(glove)
	# Left arm: hangs at his side with the towel folded over the forearm.
	var left := Node3D.new()
	left.position = Vector3(-SHOULDER.x, SHOULDER.y, 0.0)
	left.rotation_degrees = Vector3(-24.0, 0.0, -4.0)
	_body.add_child(left)
	left.add_child(_cyl(0.12, 0.16, 0.7, shade, -0.36))
	left.add_child(_cyl(0.145, 0.145, 0.06, cloth, -0.7))
	var lglove := _sphere(0.15, Vector3(1.0, 1.15, 1.0), cloth)
	lglove.position = Vector3(0, -ARM_LEN, 0)
	left.add_child(lglove)
	var towel := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.34, 0.12, 0.46)
	towel.mesh = tb
	towel.material_override = cloth
	towel.position = Vector3(0.0, -0.5, 0.03)
	left.add_child(towel)

	# ── Wisps drifting around the hem, and a soft cold glow ──────────────
	for i in 5:
		var w := _sphere(0.07 + 0.02 * float(i % 3), Vector3.ONE, shade)
		w.set_meta(&"phase", TAU * float(i) / 5.0)
		w.set_meta(&"rad", 0.95 + 0.12 * float(i % 2))
		_body.add_child(w)
		_wisps.append(w)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.85, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 4.0
	_light.position = Vector3(0, 1.4, 0.4)
	_light.shadow_enabled = false
	_body.add_child(_light)
	set_alpha(0.0)


## The sheet: a smooth bell with a rounded head dome and a scalloped, uneven hem.
func _sheet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[Vector2] = []     # (height, radius)
	for i in range(RINGS + 1):
		var t := float(i) / float(RINGS)
		rows.append(_profile_at(t))
	for i in range(RINGS + 1):
		for j in range(SEGMENTS):
			var a := TAU * float(j) / float(SEGMENTS)
			var y := rows[i].x
			# Scalloped hem: the bottom rows rise and fall around the ring, fading out upward.
			var fade := clampf(1.0 - y / 0.6, 0.0, 1.0)
			y += fade * (0.12 + 0.12 * sin(a * 6.0) + 0.05 * sin(a * 11.0 + 1.3))
			st.set_uv(Vector2(float(j) / float(SEGMENTS), float(i) / float(RINGS)))
			st.add_vertex(Vector3(sin(a) * rows[i].y, y, cos(a) * rows[i].y))
	for i in range(RINGS):
		for j in range(SEGMENTS):
			var j2 := (j + 1) % SEGMENTS
			var a0 := i * SEGMENTS + j
			var b0 := i * SEGMENTS + j2
			var c0 := (i + 1) * SEGMENTS + j
			var d0 := (i + 1) * SEGMENTS + j2
			st.add_index(a0)
			st.add_index(c0)
			st.add_index(b0)
			st.add_index(b0)
			st.add_index(c0)
			st.add_index(d0)
	st.generate_normals()
	return st.commit()


## Height / radius at t = 0..1 up the sheet (control points, then the head dome).
func _profile_at(t: float) -> Vector2:
	var top_y := DOME_Y + DOME_H
	var y := lerpf(0.0, top_y, t)
	if y <= DOME_Y:
		for k in range(PROFILE.size() - 1):
			var p0: Array = PROFILE[k]
			var p1: Array = PROFILE[k + 1]
			if y <= float(p1[0]):
				var f := inverse_lerp(float(p0[0]), float(p1[0]), y)
				return Vector2(y, lerpf(float(p0[1]), float(p1[1]), smoothstep(0.0, 1.0, f)))
		return Vector2(y, DOME_R)
	var u := clampf((y - DOME_Y) / DOME_H, 0.0, 1.0)
	return Vector2(y, DOME_R * sqrt(maxf(1.0 - u * u, 0.0)))


func _sphere(r: float, squash: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.scale = squash
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A cylinder / frustum centred at local y = `y`.
func _cyl(top_r: float, bottom_r: float, h: float, mat: Material, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = h
	cm.radial_segments = 20
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _mat(col: Color, glow: float, alpha: float, bucket: Array[StandardMaterial3D]) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.emission_enabled = glow > 0.0
	m.emission = col
	m.emission_energy_multiplier = glow
	m.roughness = 0.9
	bucket.append(m)
	return m


## 0..1 visibility (1 = the ghost's normal, near-transparent look).
func set_alpha(a: float) -> void:
	_alpha = a
	for m in _sheet:
		m.albedo_color.a = SHEET_ALPHA * a
	for m in _dark:
		m.albedo_color.a = DARK_ALPHA * a
	for m in _glow:
		m.albedo_color.a = 0.9 * a
	if _light != null:
		_light.light_energy = 0.55 * a
	visible = a > 0.01


func fade_to(target: float, dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_method(set_alpha, _alpha, target, dur)
	return tw


func _play(_clip: String = "", _blend: float = 0.0) -> void:
	pass


func _process(delta: float) -> void:
	_t += delta
	if _body:
		# Float and sway like something with no legs to stand on.
		_body.position.y = sin(_t * 2.2) * 0.06
		_body.rotation.y = sin(_t * 1.1) * 0.05
		_body.rotation.z = sin(_t * 1.6) * 0.025
	for w in _wisps:
		var ph: float = float(w.get_meta(&"phase")) + _t * 0.9
		var r: float = float(w.get_meta(&"rad"))
		w.position = Vector3(sin(ph) * r, 0.25 + 0.2 * sin(_t * 1.7 + ph * 2.0), cos(ph) * r)
	# Slow blink.
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = randf_range(2.2, 5.0)
		for e in _eyes:
			var tw := create_tween()
			tw.tween_property(e, "scale:y", 0.1, 0.07)
			tw.tween_property(e, "scale:y", 1.0, 0.1)
