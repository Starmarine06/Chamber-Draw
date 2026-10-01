extends RefCounted

## Procedural glassware for the drinks: tumbler, shot, martini, mug, wine,
## flute, snifter. Every glass is built in "model units" with its origin at the
## base and is ~0.24-0.32 tall, like EmoteRig.build_glass(). Meta "liquid" is a
## pivot at the liquid's base: animate its scale.y for the fill level.

const EmoteRig := preload("res://scripts/fx/emote_rig.gd")


static func _glass_mat() -> StandardMaterial3D:
	return EmoteRig._mat(Color(0.85, 0.93, 0.97), 0.0, 0.05, 0.42)


static func _liquid_mat(col: Color) -> StandardMaterial3D:
	return EmoteRig._mat(col, 0.5, 0.2, 0.93)


## kind: tumbler | shot | martini | mug | wine | flute | snifter
static func build(kind: String, liquid_col: Color) -> Node3D:
	match kind:
		"shot": return _tapered(0.085, 0.11, 0.17, 0.11, liquid_col, false)
		"mug": return _mug(liquid_col)
		"martini": return _stemmed(0.16, 0.0, 0.14, 0.18, liquid_col, true)
		"wine": return _stemmed(0.115, 0.1, 0.12, 0.17, liquid_col, false)
		"flute": return _stemmed(0.06, 0.06, 0.12, 0.22, liquid_col, false)
		"snifter": return _stemmed(0.13, 0.05, 0.05, 0.12, liquid_col, false, 0.6)
		_: return _tumbler(liquid_col)


static func _finish(glass: Node3D, pivot: Node3D) -> Node3D:
	glass.set_meta(&"liquid", pivot)
	return glass


static func _tumbler(col: Color) -> Node3D:
	var glass := EmoteRig.build_glass()
	var pivot: Node3D = glass.get_meta(&"liquid")
	for c in pivot.get_children():
		var mi := c as MeshInstance3D
		if mi and mi.mesh is CylinderMesh:
			(mi.mesh as CylinderMesh).material = _liquid_mat(col)
	return glass


## Simple tapered vessel (shot glass): base radius, top radius, height, liquid height.
static func _tapered(r_bottom: float, r_top: float, height: float, liquid_h: float, col: Color, _ice: bool) -> Node3D:
	var glass := Node3D.new()
	var shell := EmoteRig._cyl(r_bottom, height, _glass_mat(), r_top)
	shell.position = Vector3(0, height * 0.5, 0)
	glass.add_child(shell)
	var base := EmoteRig._cyl(r_bottom * 1.02, 0.035, EmoteRig._mat(Color(0.8, 0.9, 0.95), 0.0, 0.05, 0.6))
	base.position = Vector3(0, 0.0175, 0)
	glass.add_child(base)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.035, 0)
	glass.add_child(pivot)
	var liquid := EmoteRig._cyl(r_bottom * 0.93, liquid_h, _liquid_mat(col), r_top * 0.94)
	liquid.position = Vector3(0, liquid_h * 0.5, 0)
	pivot.add_child(liquid)
	return _finish(glass, pivot)


## Foot + stem + bowl (martini cone, wine, flute, snifter).
static func _stemmed(bowl_r: float, bowl_bottom_r: float, stem_h: float, bowl_h: float, col: Color, cone: bool, round_factor: float = 0.0) -> Node3D:
	var glass := Node3D.new()
	var foot := EmoteRig._cyl(0.08, 0.02, _glass_mat())
	foot.position = Vector3(0, 0.01, 0)
	glass.add_child(foot)
	var stem := EmoteRig._cyl(0.012, stem_h, _glass_mat())
	stem.position = Vector3(0, 0.02 + stem_h * 0.5, 0)
	glass.add_child(stem)
	var y0 := 0.02 + stem_h
	var bowl_r0 := maxf(bowl_bottom_r, 0.012)
	var bowl_top_r := bowl_r
	if round_factor > 0.0:
		bowl_top_r = bowl_r * (1.0 - round_factor * 0.55)  # snifter narrows at the rim
		bowl_r0 = bowl_r * 0.55
	var bowl := EmoteRig._cyl(bowl_r0, bowl_h, _glass_mat(), bowl_top_r if not cone else bowl_r)
	bowl.position = Vector3(0, y0 + bowl_h * 0.5, 0)
	glass.add_child(bowl)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, y0, 0)
	glass.add_child(pivot)
	var lh := bowl_h * (0.55 if round_factor > 0.0 else 0.85)
	var liq := EmoteRig._cyl(maxf(bowl_r0 * 0.92, 0.01), lh, _liquid_mat(col), bowl_top_r * 0.92 if not cone else bowl_r * 0.9)
	liq.position = Vector3(0, lh * 0.5, 0)
	pivot.add_child(liq)
	if cone:
		# Olive on a pick.
		var pick := EmoteRig._cyl(0.004, bowl_h * 1.1, EmoteRig._mat(Color(0.7, 0.6, 0.35), 0.0, 0.4))
		pick.position = Vector3(0.03, y0 + bowl_h * 0.62, 0)
		pick.rotation_degrees = Vector3(0, 0, -22)
		glass.add_child(pick)
		var olive := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.02
		sm.height = 0.04
		sm.material = EmoteRig._mat(Color(0.3, 0.42, 0.12), 0.0, 0.5)
		olive.mesh = sm
		olive.position = Vector3(-0.005, y0 + bowl_h * 0.35, 0)
		glass.add_child(olive)
	return _finish(glass, pivot)


static func _mug(col: Color) -> Node3D:
	var glass := Node3D.new()
	var shell := EmoteRig._cyl(0.115, 0.27, _glass_mat(), 0.125)
	shell.position = Vector3(0, 0.135, 0)
	glass.add_child(shell)
	var base := EmoteRig._cyl(0.118, 0.04, EmoteRig._mat(Color(0.8, 0.9, 0.95), 0.0, 0.05, 0.6))
	base.position = Vector3(0, 0.02, 0)
	glass.add_child(base)
	# Handle.
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.045
	tm.outer_radius = 0.07
	tm.material = _glass_mat()
	handle.mesh = tm
	handle.rotation_degrees = Vector3(90, 0, 0)
	handle.position = Vector3(0.14, 0.14, 0)
	glass.add_child(handle)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.04, 0)
	glass.add_child(pivot)
	var liquid := EmoteRig._cyl(0.108, 0.2, _liquid_mat(col), 0.116)
	liquid.position = Vector3(0, 0.1, 0)
	pivot.add_child(liquid)
	# Foam head that rides on the liquid surface.
	var foam := EmoteRig._cyl(0.117, 0.035, EmoteRig._mat(Color(0.98, 0.96, 0.88), 0.0, 0.9))
	foam.position = Vector3(0, 0.2, 0)
	pivot.add_child(foam)
	return _finish(glass, pivot)
