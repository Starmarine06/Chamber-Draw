extends Node3D

## A procedural, semi-transparent BLOCKY ghost that serves the drinks (no model assets),
## built from boxes to match the game's Kenney-style characters.
## Local units: ~2.5 tall, hem at y=0, right shoulder at (0.85, 1.75, 0); `arm` is a pivot at
## the shoulder whose box hangs along -Y (0.85 long), so it can be aimed with a quaternion.
## Faces +Z like the Kenney characters (same yaw maths everywhere).

const SHOULDER := Vector3(0.85, 1.75, 0.0)
const ARM_LEN := 0.85
const SHEET_ALPHA := 0.4
const DARK_ALPHA := 0.85

var anim = null        # (CharacterActor API compatibility: nothing to animate)
var model = null
var arm: Node3D
var _sheet: Array[StandardMaterial3D] = []
var _dark: Array[StandardMaterial3D] = []
var _body: Node3D
var _alpha := 0.0
var _t := 0.0


func _init() -> void:
	_body = Node3D.new()
	add_child(_body)
	var sheet := _mat(Color(0.82, 0.9, 1.0), 0.55, SHEET_ALPHA, _sheet)
	var shade := _mat(Color(0.66, 0.76, 0.95), 0.4, SHEET_ALPHA, _sheet)
	var dark := _mat(Color(0.03, 0.04, 0.09), 0.0, DARK_ALPHA, _dark)

	# Torso + a jagged, stepped hem (alternating block heights, like a tattered sheet).
	_box(Vector3(1.4, 1.15, 0.85), Vector3(0, 1.0, 0), sheet)
	var hem_x := [-0.525, -0.175, 0.175, 0.525]
	for i in 4:
		var h := 0.5 if i % 2 == 0 else 0.3
		_box(Vector3(0.36, h, 0.85), Vector3(hem_x[i], h * 0.5, 0), shade)
	# Head: a big cube.
	_box(Vector3(1.1, 1.0, 1.0), Vector3(0, 2.05, 0), sheet)
	# Face (+Z): square eyes + a square mouth.
	for k in [-1.0, 1.0]:
		_box(Vector3(0.26, 0.34, 0.06), Vector3(0.27 * k, 2.12, 0.51), dark)
	_box(Vector3(0.34, 0.16, 0.06), Vector3(0, 1.82, 0.51), dark)
	# Left arm stub (the drink-less one), hanging.
	_box(Vector3(0.3, 0.8, 0.3), Vector3(-0.85, 1.35, 0), shade)

	# Right arm: pivot at the shoulder, box + fist hang down -Y.
	arm = Node3D.new()
	arm.position = SHOULDER
	_body.add_child(arm)
	var am := MeshInstance3D.new()
	var abm := BoxMesh.new()
	abm.size = Vector3(0.3, ARM_LEN, 0.3)
	abm.material = shade
	am.mesh = abm
	am.position = Vector3(0, -ARM_LEN * 0.5, 0)
	arm.add_child(am)
	var fist := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.38, 0.3, 0.38)
	fm.material = sheet
	fist.mesh = fm
	fist.position = Vector3(0, -ARM_LEN - 0.05, 0)
	arm.add_child(fist)
	set_alpha(0.0)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)


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
		_body.position.y = sin(_t * 2.2) * 0.05
		_body.rotation.y = sin(_t * 1.1) * 0.05
