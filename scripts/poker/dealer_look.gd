extends RefCounted

## The house dealer's costume: crisp white shirt, black waistcoat with brass buttons, red bow tie,
## gold sleeve garters, a green eyeshade and a waxed moustache. Parts hang off the torso, arms and
## head so they move with the animation.

static func _mat(col: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

static func dress(actor: Node3D) -> void:
	var model: Node3D = actor.get("model")
	if model == null:
		return
	var shirt := _mat(Color("f2ede2"), 0.7)
	var vest := _mat(Color("15121a"), 0.55)
	var brass := _mat(Color("d1a64b"), 0.3, 0.85)
	var red := _mat(Color("9e1b2a"), 0.5)
	var green := _mat(Color("1f7a4a"), 0.45)
	var hair := _mat(Color("0d0b0b"), 0.8)
	var torso := model.find_child("torso", true, false) as Node3D
	if torso != null:
		# Torso mesh spans x -0.4..0.4, y 0.3..1.2, z -0.3..0.3 (front is +Z).
		_box(torso, Vector3(0.82, 0.92, 0.62), Vector3(0.0, 0.75, 0.0), shirt)
		_box(torso, Vector3(0.84, 0.64, 0.05), Vector3(0.0, 0.62, -0.31), vest)
		for sx in [-1.0, 1.0]:
			_box(torso, Vector3(0.28, 0.66, 0.05), Vector3(0.27 * sx, 0.61, 0.31), vest)
			# straps over the shoulders
			_box(torso, Vector3(0.12, 0.05, 0.64), Vector3(0.27 * sx, 0.95, 0.0), vest)
		for k in range(3):
			_box(torso, Vector3(0.05, 0.05, 0.03), Vector3(-0.1, 0.42 + 0.14 * float(k), 0.345), brass)
		# watch chain
		_box(torso, Vector3(0.24, 0.018, 0.02), Vector3(0.2, 0.6, 0.345), brass, Vector3(0, 0, -12))
		# bow tie
		var tie := Node3D.new()
		tie.position = Vector3(0.0, 1.1, 0.33)
		torso.add_child(tie)
		for sx in [-1.0, 1.0]:
			_box(tie, Vector3(0.13, 0.09, 0.04), Vector3(0.08 * sx, 0.0, 0.0), red, Vector3(0, 0, 16 * sx))
		_box(tie, Vector3(0.05, 0.06, 0.05), Vector3.ZERO, red)
		for armn in ["arm-left", "arm-right"]:
			var arm := torso.find_child(armn, false, false) as Node3D
			if arm == null:
				continue
			var sgn: float = 1.0 if armn == "arm-left" else -1.0
			_box(arm, Vector3(0.42, 0.7, 0.42), Vector3(0.2 * sgn, -0.3, 0.0), shirt)
			_box(arm, Vector3(0.45, 0.06, 0.45), Vector3(0.2 * sgn, -0.18, 0.0), brass)
	# black trousers with a brass belt buckle
	for legn in ["leg-left", "leg-right"]:
		var leg := model.find_child(legn, true, false) as Node3D
		if leg != null:
			_box(leg, Vector3(0.42, 0.88, 0.42), Vector3(0.0, -0.5, 0.0), vest)
	if torso != null:
		_box(torso, Vector3(0.84, 0.07, 0.64), Vector3(0.0, 0.32, 0.0), vest)
		_box(torso, Vector3(0.1, 0.08, 0.03), Vector3(0.0, 0.32, 0.335), brass)
	var head := model.find_child("head", true, false) as Node3D
	if head != null:
		# Head-local units are x10 (the head node is scaled 0.1); face looks down +Z, y runs 0..8.
		_box(head, Vector3(8.4, 1.1, 8.4), Vector3(0.0, 6.9, 0.0), green)
		_box(head, Vector3(7.0, 0.35, 2.6), Vector3(0.0, 6.6, 5.2), green, Vector3(10, 0, 0))
		_box(head, Vector3(4.4, 0.7, 0.5), Vector3(0.0, 2.9, 4.05), hair)
		for sx in [-1.0, 1.0]:
			_box(head, Vector3(1.0, 0.6, 0.5), Vector3(2.5 * sx, 2.75, 4.05), hair, Vector3(0, 0, -25 * sx))
