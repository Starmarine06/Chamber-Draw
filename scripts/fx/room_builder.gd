extends RefCounted

## Procedural noir back room built around the poker table: carpeted floor, an
## octagon of paneled walls with framed pictures and warm sconces, a dark
## ceiling. Everything is sized relative to the table so any scale works.

const WALL_SHADER := preload("res://shaders/room_wall.gdshader")
const SIDES := 8

static func build(parent: Node, center: Vector3, tsize: float, floor_y: float, cam_dist: float, cam_top: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Room"
	parent.add_child(root)

	var radius := maxf(tsize * 2.7, cam_dist * 1.7 + tsize * 0.4)
	var top := maxf(cam_top + tsize * 1.2, floor_y + radius * 0.85)
	var height := top - floor_y

	_floor(root, center, radius, floor_y, tsize)
	_ceiling(root, center, radius, top)

	var chord := 2.0 * radius * sin(PI / SIDES) * 1.02
	for i in SIDES:
		var a := TAU * float(i) / SIDES
		var pos := center + Vector3(sin(a) * radius, floor_y + height * 0.5, cos(a) * radius)
		var wall := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(chord, height)
		var mat := ShaderMaterial.new()
		mat.shader = WALL_SHADER
		mat.set_shader_parameter("tiles", maxf(3.0, chord / maxf(height, 0.01) * 5.0))
		q.material = mat
		wall.mesh = q
		root.add_child(wall)
		wall.position = pos
		wall.rotation.y = a + PI
		_dress_wall(root, i, a, center, radius, floor_y, height, chord)
	root.set_meta("radius", radius)
	root.set_meta("height", height)
	return root


static func _floor(root: Node3D, center: Vector3, radius: float, floor_y: float, tsize: float) -> void:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.6, radius * 2.6)
	var mat := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 512
	tex.height = 512
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.32, 0.07, 0.09)
	mat.uv1_scale = Vector3(radius * 0.9, radius * 0.9, 1)
	mat.roughness = 0.95
	plane.material = mat
	m.mesh = plane
	root.add_child(m)
	m.position = Vector3(center.x, floor_y, center.z)

	# A slightly lighter round rug under the table.
	var rug := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = tsize * 1.55
	disc.bottom_radius = tsize * 1.55
	disc.height = 0.002
	disc.radial_segments = 64
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.05, 0.16, 0.11)
	rmat.roughness = 0.97
	disc.material = rmat
	rug.mesh = disc
	root.add_child(rug)
	rug.position = Vector3(center.x, floor_y + 0.002, center.z)


static func _ceiling(root: Node3D, center: Vector3, radius: float, top: float) -> void:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.6, radius * 2.6)
	plane.flip_faces = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.035, 0.035)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mat
	m.mesh = plane
	root.add_child(m)
	m.position = Vector3(center.x, top, center.z)


## Framed pictures on even walls, wall sconces (with a real warm light) on odd ones.
static func _dress_wall(root: Node3D, i: int, a: float, center: Vector3, radius: float, floor_y: float, height: float, chord: float) -> void:
	var inward := Vector3(-sin(a), 0, -cos(a))
	var base := center + Vector3(sin(a) * radius, 0, cos(a) * radius) + inward * 0.02
	if i % 2 == 0:
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(chord * 0.34, height * 0.26, 0.03)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.5, 0.36, 0.16)
		fm.metallic = 0.8
		fm.roughness = 0.35
		fb.material = fm
		frame.mesh = fb
		root.add_child(frame)
		frame.position = base + Vector3(0, floor_y + height * 0.62, 0) + inward * 0.02
		frame.rotation.y = a + PI

		var canvas := MeshInstance3D.new()
		var qb := QuadMesh.new()
		qb.size = Vector2(chord * 0.3, height * 0.22)
		var cm := StandardMaterial3D.new()
		var grad := GradientTexture2D.new()
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.02, 0.03, 0.05), Color(0.16, 0.1, 0.06)])
		grad.gradient = g
		grad.fill_from = Vector2(0.5, 0)
		grad.fill_to = Vector2(0.5, 1)
		cm.albedo_texture = grad
		cm.roughness = 0.8
		qb.material = cm
		canvas.mesh = qb
		root.add_child(canvas)
		canvas.position = frame.position + inward * 0.02
		canvas.rotation.y = a + PI
	else:
		var sconce := MeshInstance3D.new()
		var sb := SphereMesh.new()
		sb.radius = height * 0.028
		sb.height = height * 0.056
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(1.0, 0.8, 0.5)
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.72, 0.4)
		sm.emission_energy_multiplier = 4.0
		sb.material = sm
		sconce.mesh = sb
		root.add_child(sconce)
		var p := base + Vector3(0, floor_y + height * 0.55, 0) + inward * (height * 0.05)
		sconce.position = p

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.4)
		light.light_energy = 3.5
		light.omni_range = radius * 1.1
		light.omni_attenuation = 1.4
		root.add_child(light)
		light.position = p + inward * (height * 0.04)
