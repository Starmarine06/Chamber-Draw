extends RefCounted

## Procedural poker table: a round woven-felt top with brass betting rings and revolver-chamber
## studs, a padded leather rail, brass trim, a lacquered apron and a turned pedestal.
##
## Everything is lathed from 2D profiles (radius, height) and sized from the table radius, so
## the seats, decks and cameras (which hang off markers) are untouched: the game just hides the
## old model and calls build() with the same radius, felt height and floor.

const FELT_SHADER := preload("res://shaders/table_felt.gdshader")
const SEGMENTS := 96

const LEATHER := Color(0.09, 0.035, 0.03)
const BRASS := Color(0.79, 0.64, 0.36)
const WOOD := Color(0.075, 0.04, 0.03)


# Drink coaster + ashtray shelves that stick out past the rail beside every seat, so a glass or
# an ashtray never has to stand on the felt. Seats use spot_pos() to find them, so the table
# and the game always agree on where they are.
const TAB_ANGLE := 0.42        # widest offset along the rim from the seat (+ = the seat's right)
const TAB_CLEAR := 0.30        # radians that must stay free between two neighbouring shelves
const TAB_MIN := 0.14          # a seat's own glass + ashtray shelves are never closer than 2x this
const TAB_AT := 1.085          # shelf centre, as a multiple of the table radius
const TAB_SIZE := 0.105        # shelf radius, in table radii
const TAB_DROP := 0.03         # shelf top sits this far (x radius) below the felt


## World position of a seat's "glass" (right, on the coaster) or "ashtray" (left) shelf top.
static func spot_pos(centre: Vector3, radius: float, surface_y: float, seat_pos: Vector3, kind: String, off: float = 0.24) -> Vector3:
	var seat_ang := atan2(seat_pos.x - centre.x, seat_pos.z - centre.z)
	var ang := seat_ang + (off if kind == "glass" else -off)
	var r := radius * TAB_AT
	return Vector3(centre.x + sin(ang) * r, surface_y - radius * TAB_DROP + 0.004, centre.z + cos(ang) * r)


## How far each shelf sits from its seat along the rim (radians). Sized from the CLOSEST pair of
## seats so no two shelves ever touch, whatever the player count or seating.
static func tab_offset(centre: Vector3, seat_positions: Array) -> float:
	var angs: Array[float] = []
	for sp: Vector3 in seat_positions:
		angs.append(atan2(sp.x - centre.x, sp.z - centre.z))
	angs.sort()
	var min_gap := TAU
	for i in range(angs.size()):
		var nxt: float = angs[(i + 1) % angs.size()] + (TAU if i == angs.size() - 1 else 0.0)
		min_gap = minf(min_gap, nxt - angs[i])
	if angs.size() < 2:
		min_gap = TAU
	return clampf((min_gap - TAB_CLEAR) * 0.5, TAB_MIN, TAB_ANGLE)


## centre: table centre (x/z used), radius: outer radius of the rail, surface_y: felt height,
## floor_y: the floor the pedestal stands on, seat_positions: one shelf pair per seat.
static func build(parent: Node, centre: Vector3, radius: float, surface_y: float, floor_y: float, seat_positions: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralTable"
	parent.add_child(root)
	root.global_position = Vector3(centre.x, surface_y, centre.z)

	var R := radius
	var rf := R * 0.865                      # where the felt ends and the trim begins
	var drop := maxf(surface_y - floor_y, R * 0.6)

	# ── Felt ─────────────────────────────────────────────────────────────
	var felt_mat := ShaderMaterial.new()
	felt_mat.shader = FELT_SHADER
	felt_mat.set_shader_parameter("felt_radius", rf)
	var felt: Array[Vector2] = []
	for i in range(0, 9):
		felt.append(Vector2(rf * float(i) / 8.0, 0.0))
	root.add_child(_lathe("Felt", felt, felt_mat))

	# ── Brass inner trim (a small raised bead where felt meets rail) ─────
	var trim_pts := _arc(rf - 0.002 * R, rf + 0.014 * R, 0.0, 0.010 * R, 7)
	root.add_child(_lathe("InnerTrim", trim_pts, _metal(BRASS, 0.28)))

	# ── Padded leather rail ──────────────────────────────────────────────
	var rail_in := rf + 0.014 * R
	var rail: Array[Vector2] = _arc(rail_in, R, 0.0, 0.040 * R, 18)
	rail.append(Vector2(R, -0.020 * R))
	rail.append(Vector2(R, -0.048 * R))
	var leather := StandardMaterial3D.new()
	leather.albedo_color = LEATHER
	leather.roughness = 0.68
	leather.metallic_specular = 0.3
	root.add_child(_lathe("Rail", rail, leather))

	# ── Brass band around the rail's lower edge ──────────────────────────
	var band: Array[Vector2] = [Vector2(R * 1.0035, -0.022 * R), Vector2(R * 1.0035, -0.036 * R)]
	root.add_child(_lathe("RailBand", band, _metal(BRASS, 0.3)))

	# ── Lacquered wood apron and underside ───────────────────────────────
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD
	wood.roughness = 0.3
	wood.metallic_specular = 0.6
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.6
	wood.clearcoat_roughness = 0.2
	var apron: Array[Vector2] = [
		Vector2(R * 0.995, -0.048 * R), Vector2(R * 0.985, -0.080 * R), Vector2(R * 0.945, -0.108 * R),
		Vector2(R * 0.60, -0.125 * R), Vector2(R * 0.26, -0.140 * R),
	]
	root.add_child(_lathe("Apron", _smooth(apron, 2), wood))

	# ── Turned pedestal and foot ─────────────────────────────────────────
	var foot_h := minf(0.12 * R, drop * 0.16)
	var base_y := -drop
	var ped: Array[Vector2] = [
		Vector2(0.26 * R, -0.140 * R), Vector2(0.17 * R, -0.185 * R), Vector2(0.115 * R, -0.25 * R),
		Vector2(0.105 * R, -0.33 * R), Vector2(0.15 * R, -0.40 * R), Vector2(0.115 * R, -0.47 * R),
		Vector2(0.095 * R, -drop * 0.55),
		Vector2(0.10 * R, base_y + foot_h * 2.2), Vector2(0.20 * R, base_y + foot_h * 1.2),
		Vector2(0.40 * R, base_y + foot_h * 0.55), Vector2(0.46 * R, base_y + foot_h * 0.2),
		Vector2(0.46 * R, base_y), Vector2(0.0, base_y),
	]
	root.add_child(_lathe("Pedestal", _smooth(ped, 3), wood))

	# ── Brass collar where the column meets the foot ─────────────────────
	var collar: Array[Vector2] = _arc(0.10 * R, 0.13 * R, base_y + foot_h * 2.2, base_y + foot_h * 2.2 + 0.03 * R, 6)
	root.add_child(_lathe("Collar", collar, _metal(BRASS, 0.32)))

	# ── Coaster + ashtray shelves, one pair per seat ─────────────────────
	var inlay := StandardMaterial3D.new()
	inlay.albedo_color = Color(0.02, 0.07, 0.05)
	inlay.roughness = 0.95
	var off := tab_offset(centre, seat_positions)
	for sp: Vector3 in seat_positions:
		for kind: String in ["glass", "ashtray"]:
			var spot := spot_pos(centre, radius, surface_y, sp, kind, off)
			root.add_child(_shelf(radius, spot - root.global_position, kind == "glass", wood, inlay))
	return root


## One round shelf: lacquered wood disc, brass rim, a bracket back to the apron, and (for the
## drink) a felt-lined coaster with its own brass ring.
static func _shelf(R: float, local_top: Vector3, with_coaster: bool, wood: Material, inlay: Material) -> Node3D:
	var s := Node3D.new()
	s.name = "Coaster" if with_coaster else "AshShelf"
	s.position = Vector3(local_top.x, local_top.y - 0.004, local_top.z)
	var rr := R * TAB_SIZE
	var thick := R * 0.026
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rr
	cm.bottom_radius = rr
	cm.height = thick
	cm.radial_segments = 40
	cm.rings = 1
	disc.mesh = cm
	disc.material_override = wood
	disc.position.y = -thick * 0.5
	s.add_child(disc)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = rr * 0.93
	tm.outer_radius = rr * 1.06
	tm.rings = 32
	tm.ring_segments = 8
	rim.mesh = tm
	rim.material_override = _metal(BRASS, 0.3)
	rim.scale = Vector3(1.0, 0.45, 1.0)
	rim.position.y = -thick * 0.1
	s.add_child(rim)
	var bracket := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = rr * 0.7
	bm.bottom_radius = rr * 0.25
	bm.height = R * 0.07
	bm.radial_segments = 24
	bracket.mesh = bm
	bracket.material_override = wood
	bracket.position = Vector3(0.0, -thick - bm.height * 0.5 + 0.002, 0.0)
	s.add_child(bracket)
	if with_coaster:
		var pad := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = rr * 0.62
		pm.bottom_radius = rr * 0.62
		pm.height = R * 0.006
		pm.radial_segments = 36
		pad.mesh = pm
		pad.material_override = inlay
		pad.position.y = R * 0.003
		s.add_child(pad)
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = rr * 0.6
		rm.outer_radius = rr * 0.67
		rm.rings = 32
		rm.ring_segments = 6
		ring.mesh = rm
		ring.material_override = _metal(BRASS, 0.3)
		ring.scale = Vector3(1.0, 0.35, 1.0)
		ring.position.y = R * 0.005
		s.add_child(ring)
	return s


## Chaikin corner-cutting: rounds a coarse profile into a smooth curve (end points stay put).
static func _smooth(pts: Array[Vector2], rounds: int) -> Array[Vector2]:
	var cur: Array[Vector2] = pts.duplicate()
	for _r in range(rounds):
		var nxt: Array[Vector2] = [cur[0]]
		for i in range(cur.size() - 1):
			nxt.append(cur[i].lerp(cur[i + 1], 0.25))
			nxt.append(cur[i].lerp(cur[i + 1], 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


static func _metal(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.92
	m.roughness = rough
	return m


## Half-ellipse bump from (r0, y0) to (r1, y0), peaking `h` above y0.
static func _arc(r0: float, r1: float, y0: float, y_top: float, steps: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rc := (r0 + r1) * 0.5
	var a := (r1 - r0) * 0.5
	var h := y_top - y0
	for i in range(steps + 1):
		var t := PI * float(i) / float(steps)
		out.append(Vector2(rc - a * cos(t), y0 + h * sin(t)))
	return out


## Spins a (radius, height) profile around the Y axis. Normals come straight from the profile
## tangent (smooth around the ring, smooth along it), so rails and columns shade as one piece.
## Travel the profile so that the visible side is on the LEFT of the direction of travel
## (inner -> outer for upward faces, top -> bottom for outward faces).
static func _lathe(node_name: String, profile: Array[Vector2], mat: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := profile.size()
	var ring_norm: Array[Vector2] = []
	for i in range(n):
		var prev := profile[maxi(i - 1, 0)]
		var next := profile[mini(i + 1, n - 1)]
		var t := next - prev
		ring_norm.append(Vector2(-t.y, t.x).normalized() if t.length() > 0.00001 else Vector2(0.0, 1.0))
	for i in range(n):
		for j in range(SEGMENTS + 1):
			var a := TAU * float(j) / float(SEGMENTS)
			var s := sin(a)
			var c := cos(a)
			verts.append(Vector3(profile[i].x * s, profile[i].y, profile[i].x * c))
			norms.append(Vector3(ring_norm[i].x * s, ring_norm[i].y, ring_norm[i].x * c).normalized())
			uvs.append(Vector2(float(j) / float(SEGMENTS), float(i) / float(maxi(n - 1, 1))))
	var stride := SEGMENTS + 1
	for i in range(n - 1):
		for j in range(SEGMENTS):
			var a0 := i * stride + j
			var b0 := a0 + 1
			var c0 := a0 + stride
			var d0 := c0 + 1
			idx.append_array([a0, b0, c0, b0, d0, c0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	return mi
