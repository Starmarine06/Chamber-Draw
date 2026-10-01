extends RefCounted

## A heavy glass ashtray that lives on the felt. `f` is the world-size of the
## first-person fist (VFP._fist_scale) so it matches the glass and cigarettes.
## Cigarettes/cigars rest across the rim; butts pile up inside.

const EmoteRig := preload("res://scripts/fx/emote_rig.gd")


static func build(f: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Ashtray"
	var r := 0.4 * f
	var glass := EmoteRig._mat(Color(0.1, 0.16, 0.14), 0.0, 0.08, 0.92)
	var outer := EmoteRig._cyl(r, 0.09 * f, glass)
	outer.position = Vector3(0, 0.045 * f, 0)
	root.add_child(outer)
	var well := EmoteRig._cyl(r * 0.78, 0.02 * f, EmoteRig._mat(Color(0.03, 0.03, 0.035), 0.0, 0.9))
	well.position = Vector3(0, 0.092 * f, 0)
	root.add_child(well)
	# Ash bed.
	var ash := EmoteRig._cyl(r * 0.74, 0.012 * f, EmoteRig._mat(Color(0.45, 0.44, 0.42), 0.0, 1.0))
	ash.position = Vector3(0, 0.102 * f, 0)
	root.add_child(ash)
	# Three rest notches cut into the rim (dark slots).
	for k in 3:
		var notch := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09 * f, 0.03 * f, 0.07 * f)
		bm.material = EmoteRig._mat(Color(0.02, 0.02, 0.025), 0.0, 1.0)
		notch.mesh = bm
		var a := TAU * float(k) / 3.0 + 0.5
		notch.position = Vector3(cos(a) * r * 0.95, 0.09 * f, sin(a) * r * 0.95)
		notch.rotation.y = -a
		root.add_child(notch)
	root.set_meta(&"radius", r)
	root.set_meta(&"f", f)
	root.set_meta(&"butts", [])
	return root


## World point where a lit cigarette/cigar rests (front notch, slightly raised).
static func rest_spot(tray: Node3D) -> Vector3:
	var f: float = tray.get_meta(&"f")
	return tray.global_position + Vector3(0, 0.13 * f, 0)
