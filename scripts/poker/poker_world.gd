extends Node

## The 3D side of Texas Hold'em: the same noir room, procedural table, Kenney giants and seat cameras the
## shedding game uses, plus real 3D playing cards (the Noir Deck, rendered once per card into a texture)
## and chip stacks on the felt. poker_game.gd owns the rules and 2D overlays; this owns everything in the world.

const UIStyle := preload("res://scripts/ui_style.gd")
const RoomBuilder := preload("res://scripts/fx/room_builder.gd")
const TableBuilder := preload("res://scripts/fx/table_builder.gd")
const RoomCrowd := preload("res://scripts/fx/room_crowd.gd")
const CharacterActor := preload("res://scripts/character_actor.gd")
const CardView := preload("res://scripts/poker/poker_card_view.gd")
const Juice := preload("res://scripts/fx/juice.gd")
const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const Bank := preload("res://scripts/poker/poker_chipbank.gd")

const TABLE_GROW := 1.45
const SEAT_PUSH := 1.62
const CHAR_SEAT_OFFSET := 1.15
const SEAT_RING_8: Array[int] = [0, 7, 3, 4, 1, 6, 2, 5]
const SEAT_SLOTS_8 := {
	2: [0, 4], 3: [0, 3, 5], 4: [0, 2, 4, 6], 5: [0, 2, 3, 5, 6], 6: [0, 1, 3, 4, 5, 7],
	7: [0, 1, 2, 3, 5, 6, 7], 8: [0, 1, 2, 3, 4, 5, 6, 7],
}
## Every chip has a value and its own colour: white 1, red 5, green 25, black 100, purple 500.
const CHIP_DENOMS: Array = [[500, Color("6b3fa0")], [100, Color("1b1b22")], [25, Color("2a8a52")], [5, Color("c0392b")], [1, Color("ece6d6")]]
const CHIP_ACCENT := {1: Color("2a2a30"), 5: Color("f5efe0"), 25: Color("f5efe0"), 100: Color("e0b84f"), 500: Color("f5efe0")}

var host: Control
var viewport: SubViewport
var tex_rect: TextureRect
var world_root: Node3D
var camera: Camera3D
var n_seats: int = 2
var markers: Array[Marker3D] = []
var cameras: Array = []
var center: Vector3 = Vector3.ZERO
var tsize: float = 1.0
var char_scale: float = 1.0
var table_radius: float = 1.0
var surface_y: float = 0.0
var card_w: float = 0.2
var card_h: float = 0.29
var deck_pos: Vector3 = Vector3.ZERO
var actors: Dictionary = {}
var _tex_cache: Dictionary = {}
var _bet_nodes: Dictionary = {}
var _pot_node: Node3D
var _cards: Array = []
var _seat_names: Array = []
var _base_rot: Vector3 = Vector3.ZERO
var _base_fov: float = 70.0
var _stacks: Dictionary = {}
var _banks: Dictionary = {}
var _bet_comp: Dictionary = {}
var _stack_labels: Dictionary = {}
var _colors: Array = []
var _chip_mesh_cache: Dictionary = {}
var _chip_face_vp: Dictionary = {}
var _seat_rings: Dictionary = {}
var _pending_nodes: Array = []
var _pending_sig: String = ""
var ring_node: MeshInstance3D
var _hover_d: int = 0
const DENOMS: Array = [1, 5, 25, 100, 500]
const MAX_TOWER := 10
const MAX_TOWERS_PER_DENOM := 2

func setup(p_host: Control, n: int, colors: Array, names: Array) -> void:
	host = p_host
	n_seats = n
	_seat_names = names
	_colors = colors
	_build_viewport()
	_build_world()
	_spawn_actors(colors)

func _render_size() -> Vector2i:
	var win := host.get_window()
	var px := Vector2i(win.size) if win else Vector2i(host.size)
	if px.x <= 0 or px.y <= 0:
		px = Vector2i(maxi(int(host.size.x), 64), maxi(int(host.size.y), 64))
	return px

func sync_size() -> void:
	var want := _render_size()
	if want != viewport.size:
		viewport.size = want

func view_scale() -> Vector2:
	if viewport == null or viewport.size.x <= 0 or host.size.x <= 0:
		return Vector2.ONE
	return host.size / Vector2(viewport.size)

func project(world_pt: Vector3) -> Vector2:
	if camera == null:
		return host.size * 0.5
	return camera.unproject_position(world_pt) * view_scale()

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
	viewport.size = _render_size()
	add_child(viewport)
	tex_rect = TextureRect.new()
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.texture = viewport.get_texture()
	host.add_child(tex_rect)
	host.move_child(tex_rect, 1)   # right above the background

const DEALER_GAP := 1.15
const FELT_A := 1.32         # felt half-length (x)
const FELT_B := 0.84         # felt half-width (z)
const RAIL_W := 0.17
const SE_P := 2.7            # superellipse power: 2 = ellipse, higher = squarer racetrack
const SEAT_MARGIN := 0.34    # seats sit this far beyond the rail
const STAND_DIST := 1.85     # where the other players stand
const TABLE_H := 0.75
var _seat_pts: Array[Vector3] = []
var dealer_pt: Vector3 = Vector3.ZERO
var dealer_dir: Vector3 = Vector3(0, 0, -1)
var dealer_actor: Node3D
var muck_pos: Vector3 = Vector3.ZERO
var burn_pos: Vector3 = Vector3.ZERO
var tray_pos: Vector3 = Vector3.ZERO
var _button: Node3D
var _muck_count: int = 0

## A clean casino room: one round table under a single lamp, a dark floor, players standing behind
## the rail. No crowd, no shelves, no props on the felt.
func _build_world() -> void:
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.016, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.36, 0.4)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.05, 0.05)
	env.fog_density = 0.02
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.92
	world.environment = env
	viewport.world_3d = world

	world_root = Node3D.new()
	viewport.add_child(world_root)
	tsize = 1.33
	table_radius = FELT_B + RAIL_W
	surface_y = TABLE_H
	center = Vector3(0.0, TABLE_H, 0.0)
	# Seat 0 (you) sits on the +Z side; the others follow clockwise (seen from above).
	_layout_seats()

	_build_racetrack_table()
	_build_hangers()
	_build_hang_tray()
	_build_clean_floor()

	camera = Camera3D.new()
	camera.fov = 58.0
	world_root.add_child(camera)
	camera.global_position = Vector3(0.0, TABLE_H + 0.86, FELT_B + RAIL_W + SEAT_MARGIN + 0.5)
	camera.look_at(Vector3(center.x, surface_y - 0.02, center.z + 0.05), Vector3.UP)
	camera.make_current()
	_base_rot = camera.global_rotation
	_base_fov = camera.fov

	_build_lighting()
	char_scale = 0.9
	card_w = tsize * 0.12
	card_h = card_w * 1.45
	var f0 := Vector3(center.x, surface_y, center.z)
	var d_right := dealer_dir.cross(Vector3.UP).normalized()
	var R_d := felt_extent(dealer_dir)
	deck_pos = f0 + dealer_dir * R_d * 0.66 + d_right * 0.09
	burn_pos = f0 + dealer_dir * R_d * 0.55 - d_right * 0.22
	muck_pos = f0 + dealer_dir * R_d * 0.50 + d_right * 0.24
	tray_pos = f0 + dealer_dir * R_d * 0.88
	_build_deck()
	_build_dealer_tray(d_right)

## Superellipse point (a racetrack-ish oval): power SE_P between an ellipse and a rounded rectangle.
func _se(a: float, b: float, t: float) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	var e := 2.0 / SE_P
	return Vector2(a * signf(c) * pow(absf(c), e), b * signf(s) * pow(absf(s), e))

## Distance from the table centre to the felt edge along a flat direction.
func felt_extent(dir: Vector3) -> float:
	var dx := absf(dir.x) / FELT_A
	var dz := absf(dir.z) / FELT_B
	return 1.0 / pow(pow(dx, SE_P) + pow(dz, SE_P), 1.0 / SE_P)

## Seats are spread by arc length around an oval just outside the rail, leaving a gap for the dealer.
func _layout_seats() -> void:
	_seat_pts.clear()
	var a := FELT_A + RAIL_W + SEAT_MARGIN
	var b := FELT_B + RAIL_W + SEAT_MARGIN
	var samples := 720
	var pts: Array[Vector2] = []
	var cum: Array[float] = [0.0]
	for i in range(samples + 1):
		pts.append(_se(a, b, PI * 0.5 + TAU * float(i) / float(samples)))
		if i > 0:
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total: float = cum[samples]
	var gap_len := 1.5
	var delta: float = (total - gap_len) / float(n_seats)
	var gap_after: int = int(ceil(float(n_seats) / 2.0)) - 1
	for i in range(n_seats):
		var s: float = float(i) * delta + (gap_len if i > gap_after else 0.0)
		var q := _at_len(pts, cum, s)
		_seat_pts.append(Vector3(q.x, surface_y, q.y))
	var sa := float(gap_after) * delta
	var sb := float(gap_after + 1) * delta + gap_len
	var d := _at_len(pts, cum, (sa + sb) * 0.5)
	dealer_pt = Vector3(d.x, surface_y, d.y)
	var to_d := Vector3(dealer_pt.x - center.x, 0.0, dealer_pt.z - center.z)
	dealer_dir = to_d.normalized() if to_d.length() > 0.001 else Vector3(0, 0, -1)

func _at_len(pts: Array[Vector2], cum: Array[float], s: float) -> Vector2:
	var total: float = cum[cum.size() - 1]
	var t := fposmod(s, total)
	var i := 1
	while i < cum.size() - 1 and cum[i] < t:
		i += 1
	var seg: float = maxf(cum[i] - cum[i - 1], 0.0001)
	return pts[i - 1].lerp(pts[i], (t - cum[i - 1]) / seg)

## A proper poker table: racetrack-shaped felt carrying the revolver-drum emblem and a ring of
## "CHAMBER DRAW" lettering, a padded leather rail with a brass bead, a lacquered apron and a plinth.
func _build_racetrack_table() -> void:
	var root := Node3D.new()
	root.name = "RacetrackTable"
	viewport.add_child(root)
	root.position = Vector3(center.x, surface_y, center.z)
	var n := 200
	var ring: Array[Vector2] = []
	var nrm: Array[Vector2] = []
	for i in range(n):
		ring.append(_se(FELT_A, FELT_B, TAU * float(i) / float(n)))
	for i in range(n):
		var tt := ring[(i + 1) % n] - ring[(i - 1 + n) % n]
		nrm.append(Vector2(tt.y, -tt.x).normalized())
	# Felt with the logo
	var felt_mat := ShaderMaterial.new()
	felt_mat.shader = load("res://shaders/poker_felt.gdshader")
	felt_mat.set_shader_parameter("felt_half", Vector2(FELT_A, FELT_B))
	felt_mat.set_shader_parameter("logo_tex", _make_felt_logo())
	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	var fi := PackedInt32Array()
	fv.append(Vector3.ZERO)
	fn.append(Vector3.UP)
	for p2 in ring:
		fv.append(Vector3(p2.x, 0.0, p2.y))
		fn.append(Vector3.UP)
	for i in range(n):
		fi.append_array(PackedInt32Array([0, 1 + i, 1 + (i + 1) % n]))
	var fa: Array = []
	fa.resize(Mesh.ARRAY_MAX)
	fa[Mesh.ARRAY_VERTEX] = fv
	fa[Mesh.ARRAY_NORMAL] = fn
	fa[Mesh.ARRAY_INDEX] = fi
	var fmesh := ArrayMesh.new()
	fmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fa)
	var felt_mi := MeshInstance3D.new()
	felt_mi.name = "Felt"
	felt_mi.mesh = fmesh
	felt_mi.material_override = felt_mat
	root.add_child(felt_mi)
	# Brass bead where the felt meets the rail
	var bead: Array[Vector2] = TableBuilder._arc(-0.004, 0.014, 0.0, 0.011, 6)
	root.add_child(_sweep(ring, nrm, bead, TableBuilder._metal(TableBuilder.BRASS, 0.28)))
	# Padded leather cushion, a brass joint, and a lacquered wooden rim
	var cushion: Array[Vector2] = TableBuilder._arc(0.012, RAIL_W - 0.06, 0.0, 0.075, 18)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.16, 0.035, 0.05)
	leather.roughness = 0.5
	leather.metallic_specular = 0.45
	leather.clearcoat_enabled = true
	leather.clearcoat = 0.25
	root.add_child(_sweep(ring, nrm, cushion, leather))
	var joint: Array[Vector2] = TableBuilder._arc(RAIL_W - 0.066, RAIL_W - 0.05, 0.0, 0.022, 6)
	root.add_child(_sweep(ring, nrm, joint, TableBuilder._metal(TableBuilder.BRASS, 0.28)))
	var rim_wood := StandardMaterial3D.new()
	rim_wood.albedo_color = Color(0.17, 0.075, 0.04)
	rim_wood.roughness = 0.28
	rim_wood.clearcoat_enabled = true
	rim_wood.clearcoat = 0.8
	rim_wood.clearcoat_roughness = 0.12
	var rim: Array[Vector2] = TableBuilder._arc(RAIL_W - 0.052, RAIL_W, 0.0, 0.062, 14)
	rim.append(Vector2(RAIL_W, -0.03))
	rim.append(Vector2(RAIL_W, -0.06))
	root.add_child(_sweep(ring, nrm, rim, rim_wood))
	# Brass band around the rim's lower edge
	var band: Array[Vector2] = [Vector2(RAIL_W + 0.003, -0.034), Vector2(RAIL_W + 0.003, -0.052)]
	root.add_child(_sweep(ring, nrm, band, TableBuilder._metal(TableBuilder.BRASS, 0.3)))
	# Lacquered apron, underside and plinth
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.09, 0.045, 0.03)
	wood.roughness = 0.3
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.7
	wood.clearcoat_roughness = 0.18
	var drop := surface_y
	var apron: Array[Vector2] = [
		Vector2(RAIL_W, -0.06), Vector2(RAIL_W - 0.012, -0.11), Vector2(RAIL_W - 0.07, -0.14),
		Vector2(-0.34, -0.15), Vector2(-0.38, -0.20), Vector2(-0.38, -drop + 0.05), Vector2(-0.44, -drop + 0.02), Vector2(-0.44, -drop),
	]
	root.add_child(_sweep(ring, nrm, TableBuilder._smooth(apron, 1), wood))

## Sweeps a (offset-from-edge, height) profile around a closed outline.
func _sweep(ring: Array[Vector2], nrm: Array[Vector2], prof: Array[Vector2], mat: Material) -> MeshInstance3D:
	var n := ring.size()
	var m := prof.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var pn: Array[Vector2] = []
	for j in range(m):
		var tg := prof[mini(j + 1, m - 1)] - prof[maxi(j - 1, 0)]
		pn.append(Vector2(-tg.y, tg.x).normalized() if tg.length() > 0.00001 else Vector2(0, 1))
	for i in range(n + 1):
		var k := i % n
		var o := nrm[k]
		for j in range(m):
			var d := prof[j].x
			verts.append(Vector3(ring[k].x + o.x * d, prof[j].y, ring[k].y + o.y * d))
			norms.append(Vector3(o.x * pn[j].x, pn[j].y, o.y * pn[j].x).normalized())
	var stride := m
	for i in range(n):
		for j in range(m - 1):
			var a := i * stride + j
			var b := (i + 1) * stride + j
			idx.append_array(PackedInt32Array([a, a + 1, b, b, a + 1, b + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sm: Material = mat.duplicate()
	if sm is StandardMaterial3D:
		(sm as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = sm
	return mi

## The foil emblem: a revolver drum in the middle and "CHAMBER DRAW" running round it in a circle.
class FeltLogo extends Control:
	var brass := Color(0.84, 0.69, 0.4, 0.95)
	func _draw() -> void:
		var c := size * 0.5
		var H := size.y
		draw_arc(c, H * 0.468, 0, TAU, 160, brass, 8.0)
		draw_arc(c, H * 0.445, 0, TAU, 160, Color(brass, 0.55), 3.0)
		draw_arc(c, H * 0.285, 0, TAU, 160, brass, 6.0)
		draw_arc(c, H * 0.262, 0, TAU, 160, Color(brass, 0.5), 2.5)
		# Lettering on the circle (twice, with a diamond between the two)
		var font: Font = load("res://assets/imported_assets/kenney_ui-pack/Font/Kenney Future.ttf")
		var phrase := "CHAMBER DRAW"
		var rt := H * 0.357
		var fs := int(H * 0.058)
		var step := deg_to_rad(15.0)
		for rep in range(2):
			var centre_ang := -PI * 0.5 + float(rep) * PI
			var start := centre_ang - step * float(phrase.length()) * 0.5
			for k in range(phrase.length()):
				var ch := phrase.substr(k, 1)
				if ch == " ":
					continue
				var ang := start + step * (float(k) + 0.5)
				var pos := c + Vector2(cos(ang), sin(ang)) * rt
				var wdt := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_set_transform(pos, ang + PI * 0.5, Vector2.ONE)
				draw_string(font, Vector2(-wdt * 0.5, fs * 0.36), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, brass)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var dang := centre_ang + PI * 0.5
			var dpos := c + Vector2(cos(dang), sin(dang)) * rt
			var dd := H * 0.02
			draw_colored_polygon(PackedVector2Array([dpos + Vector2(0, -dd), dpos + Vector2(dd, 0), dpos + Vector2(0, dd), dpos + Vector2(-dd, 0)]), brass)
		# Revolver drum
		var rd := H * 0.225
		draw_circle(c, rd, Color(0.0, 0.03, 0.02, 0.55))
		draw_arc(c, rd, 0, TAU, 96, brass, 7.0)
		draw_arc(c, rd * 0.86, 0, TAU, 96, Color(brass, 0.55), 2.5)
		for i in range(6):
			var a2 := TAU * float(i) / 6.0 - PI * 0.5
			var p := c + Vector2(cos(a2), sin(a2)) * rd * 0.56
			draw_circle(p, rd * 0.19, Color(0.0, 0.02, 0.015, 0.92))
			draw_arc(p, rd * 0.19, 0, TAU, 32, brass, 4.0)
			var a3 := a2 + PI / 6.0
			draw_line(c + Vector2(cos(a3), sin(a3)) * rd * 0.2, c + Vector2(cos(a3), sin(a3)) * rd * 0.82, Color(brass, 0.45), 2.0)
		draw_circle(c, rd * 0.16, brass)
		draw_circle(c, rd * 0.07, Color(0.0, 0.03, 0.02, 0.9))
		# Fine rays around the lettering ring
		for i in range(48):
			var a4 := TAU * float(i) / 48.0
			draw_line(c + Vector2(cos(a4), sin(a4)) * H * 0.452, c + Vector2(cos(a4), sin(a4)) * H * (0.462 if i % 2 == 0 else 0.458), Color(brass, 0.7), 2.0)

func _make_felt_logo() -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, int(round(2048.0 * FELT_B / FELT_A)))
	vp.transparent_bg = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var logo := FeltLogo.new()
	logo.size = Vector2(vp.size)
	vp.add_child(logo)
	viewport.add_child(vp)
	return vp.get_texture()

func _build_clean_floor() -> void:
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.03, 0.025, 0.03)
	fm.roughness = 0.4
	fm.metallic = 0.1
	floor_mi.material_override = fm
	viewport.add_child(floor_mi)
	var rug := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.4
	cyl.height = 0.006
	cyl.radial_segments = 64
	rug.mesh = cyl
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.1, 0.022, 0.03)
	rm.roughness = 0.95
	rug.material_override = rm
	rug.position = Vector3(0.0, 0.004, 0.0)
	viewport.add_child(rug)

func _build_lighting() -> void:
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.58)
	lamp.light_energy = 9.0
	lamp.spot_range = tsize * 4.0
	lamp.spot_angle = 42.0
	lamp.spot_angle_attenuation = 1.6
	lamp.spot_attenuation = 0.6
	lamp.shadow_enabled = true
	lamp.shadow_blur = 1.5
	viewport.add_child(lamp)
	lamp.position = center + Vector3(0, tsize * 1.6, 0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.62, 0.85)
	fill.rotation_degrees = Vector3(-35, -140, 0)
	fill.light_energy = 0.22
	viewport.add_child(fill)

func seat_marker_pos(seat: int) -> Vector3:
	if _seat_pts.is_empty():
		return center
	return _seat_pts[seat % _seat_pts.size()]

## Distance from a seat to the table centre (varies around the oval).
func reach(seat: int) -> float:
	var p := seat_marker_pos(seat)
	return Vector2(p.x - center.x, p.z - center.z).length()

func _stand_pos(seat: int) -> Vector3:
	var p := seat_marker_pos(seat)
	var out := Vector3(p.x - center.x, 0.0, p.z - center.z).normalized()
	return Vector3(p.x, 0.0, p.z) + out * 0.55

# ── Seats / characters ────────────────────────────────────────────────

func _spawn_actors(colors: Array) -> void:
	_spawn_dealer()
	var scale_done := false
	for i in range(1, n_seats):
		var base := _stand_pos(i)
		var actor: Node3D = CharacterActor.new()
		var path := "res://assets/imported_assets/kenney_blocky-characters_20/Models/GLB format/character-%s.glb" % char(97 + posmod(i - 1, 15))
		viewport.add_child(actor)
		actor.setup(path, 1.0, colors[i], i)
		# Normal human size, feet on the floor.
		var m: Dictionary = RoomCrowd.measure(actor)
		var h: float = maxf(float(m.hi) - float(m.lo), 0.1)
		var sc: float = 1.35 / h
		actor.scale = Vector3.ONE * sc
		actor.set("_base_scale", sc)
		actor.position = Vector3(base.x, -float(m.lo) * sc, base.z)
		var to_c := Vector3(center.x, 0.0, center.z) - base
		actor.rotation.y = atan2(to_c.x, to_c.z)
		actor.glance = true
		actors[i] = actor
		if not scale_done:
			char_scale = sc * 0.55
			scale_done = true

func head_anchor_of(actor: Node3D) -> Vector3:
	var m: Dictionary = RoomCrowd.measure(actor)
	return Vector3(actor.global_position.x, actor.global_position.y + float(m.hi) * actor.scale.y + 0.08, actor.global_position.z)

func head_anchor(i: int) -> Vector3:
	var actor: Node3D = actors.get(i, null)
	if actor != null and is_instance_valid(actor):
		var m: Dictionary = RoomCrowd.measure(actor)
		return Vector3(actor.global_position.x, actor.global_position.y + float(m.hi) * actor.scale.y + 0.08, actor.global_position.z)
	var base := seat_marker_pos(i)
	return Vector3(base.x, base.y + 0.8, base.z)

func react(i: int, kind: StringName) -> void:
	var a: Node3D = actors.get(i, null)
	if a != null and is_instance_valid(a):
		a.react(kind)

func set_turn(i: int, on: bool) -> void:
	var a: Node3D = actors.get(i, null)
	if a != null and is_instance_valid(a):
		a.set_turn(on)

func think(i: int) -> void:
	var a: Node3D = actors.get(i, null)
	if a != null and is_instance_valid(a):
		a.emote("emote_dots3", 1.0)

func remove_actor(i: int) -> void:
	var a: Node3D = actors.get(i, null)
	if a != null and is_instance_valid(a) and not a.removing:
		a.die_and_remove()

# ── Geometry on the felt ──────────────────────────────────────────────

func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length() > 0.001 else Vector3(0, 0, -1)

func forward_of(seat: int) -> Vector3:
	return _flat_dir(seat_marker_pos(seat), center)

func right_of(seat: int) -> Vector3:
	return forward_of(seat).cross(Vector3.UP).normalized()

## Basis that lays a card flat on the felt, face up, its top edge pointing at the table centre.
func _flat_basis(fwd: Vector3) -> Basis:
	var yaw := atan2(-fwd.x, -fwd.z)
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2.0)

func hole_transform(seat: int, k: int) -> Transform3D:
	var fwd := forward_of(seat)
	var right := right_of(seat)
	var side: float = (-0.56 if k == 0 else 0.56) * card_w
	var yaw := atan2(-fwd.x, -fwd.z)
	var depth := 0.30 if seat == 0 else 0.27
	var pos := felt_pt(seat, depth, side * (1.1 if seat == 0 else 1.0))
	pos.y += 0.006
	return Transform3D(Basis(Vector3.UP, yaw + (0.07 if k == 0 else -0.07)) * Basis(Vector3.RIGHT, -PI / 2.0), pos)

## Where a contender's hole cards go at showdown: slid forward onto the felt in front of them, face up.
func show_transform(seat: int, k: int) -> Transform3D:
	var fwd := forward_of(seat)
	var yaw := atan2(-fwd.x, -fwd.z)
	var side: float = (-0.56 if k == 0 else 0.56) * card_w
	var pos := felt_pt(seat, 0.50, side * 1.05)
	pos.y += 0.008
	return Transform3D(Basis(Vector3.UP, yaw + (0.05 if k == 0 else -0.05)) * Basis(Vector3.RIGHT, -PI / 2.0), pos)

func peek_transform(k: int) -> Transform3D:
	var rest := hole_transform(0, k)
	var fwd := forward_of(0)
	var yaw := atan2(-fwd.x, -fwd.z)
	var b := Basis(Vector3.UP, yaw + (0.09 if k == 0 else -0.09)) * Basis(Vector3.RIGHT, -PI / 2.0 + 1.0)
	return Transform3D(b, rest.origin - fwd * card_h * 0.18 + Vector3(0, card_h * 0.42, 0))

## Look at your cards: they turn face up in place (a little lift mid-turn) and turn back when you let go.
## t = 0 face down, 1 face up.
func set_peek(node: Node3D, k: int, t: float) -> void:
	if not is_instance_valid(node):
		return
	var a := hole_transform(0, k)
	var e := t * t * (3.0 - 2.0 * t)
	var flip := 1.0 - e
	node.set_meta(&"base", a.basis)
	node.set_meta(&"flip", flip)
	node.basis = a.basis * Basis(Vector3.UP, PI * flip)
	node.position = a.origin + Vector3(0, sin(e * PI) * card_h * 0.22, 0)
	set_card_bend(node, 0.0)

func set_card_bend(node: Node3D, amount: float) -> void:
	if not is_instance_valid(node):
		return
	var flip: float = node.get_meta(&"flip", 1.0)
	var signed: float = amount * (1.0 - 2.0 * clampf(flip, 0.0, 1.0))
	for key in [&"front_mat", &"back_mat"]:
		(node.get_meta(key) as ShaderMaterial).set_shader_parameter("bend", signed)

## Deal flick: the card skims in over the felt with a spin that settles, then a tiny bounce.
func deal_card(node: Node3D, target: Transform3D, dur: float = 0.34, delay: float = 0.0, spin: float = 1.1) -> void:
	if not is_instance_valid(node):
		return
	var start := node.position
	var base: Basis = target.basis
	node.set_meta(&"base", base)
	var step := func(t: float) -> void:
		if not is_instance_valid(node):
			return
		var flip: float = node.get_meta(&"flip", 1.0)
		node.position = start.lerp(target.origin, t) + Vector3(0, sin(t * PI) * card_h * 0.4, 0)
		node.basis = Basis(Vector3.UP, spin * pow(1.0 - t, 2.0)) * base * Basis(Vector3.UP, PI * flip)
	var tw := node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(step, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position:y", target.origin.y + card_h * 0.05, 0.05)
	tw.tween_property(node, "position:y", target.origin.y, 0.07)

## Winning cards rise off the felt a little (and settle back with the next hand).
func lift_card(node: Node3D, up: bool) -> void:
	if not is_instance_valid(node):
		return
	var tw := node.create_tween()
	tw.tween_property(node, "position:y", node.position.y + (card_h * 0.22 if up else 0.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Brief gold flash (a reveal).
func flash_card(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var m: ShaderMaterial = node.get_meta(&"front_mat")
	var tw := node.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("glow", v), 1.0, 0.0, 0.45)

func board_transform(k: int) -> Transform3D:
	var fwd := forward_of(0)
	var right := right_of(0)
	var grow := 1.25   # community cards are drawn larger so they read from across the table
	var gap := card_w * 0.16 * grow
	var pos := Vector3(center.x, surface_y + 0.006, center.z) + fwd * 0.10 + right * (float(k) - 2.0) * (card_w * grow + gap)
	return Transform3D(_flat_basis(fwd).scaled(Vector3.ONE * grow), pos)

func bet_pos(seat: int) -> Vector3:
	if seat == 0:
		return inside_felt(ring_point() - right_of(0) * 0.23, 0.05)
	var p := felt_pt(seat, 0.36, 0.26)
	return Vector3(p.x, surface_y, p.z)

func pot_pos() -> Vector3:
	return Vector3(center.x, surface_y, center.z) + forward_of(0) * 0.40

# ── Cards ─────────────────────────────────────────────────────────────

func card_texture(c: int) -> Texture2D:
	if _tex_cache.has(c):
		return (_tex_cache[c] as SubViewport).get_texture()
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 768)
	vp.transparent_bg = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cv := CardView.new()
	cv.flat3d = true
	cv.size = Vector2(512, 768)
	cv.show_card(c, c >= 0)
	vp.add_child(cv)
	viewport.add_child(vp)
	_tex_cache[c] = vp
	return vp.get_texture()

func refresh_textures() -> void:
	for c in _tex_cache:
		var vp: SubViewport = _tex_cache[c]
		for ch in vp.get_children():
			ch.queue_redraw()
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE

var _card_shader: Shader
var _card_edge_mat: StandardMaterial3D
var _card_mesh_cache: ArrayMesh

func _card_material(tex: Texture2D) -> ShaderMaterial:
	if _card_shader == null:
		_card_shader = load("res://shaders/poker_card.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _card_shader
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("half_h", card_h * 0.5)
	return m

## A thin rounded-rectangle solid: front face (surface 0), back face (1) and a cream paper edge (2).
func _card_mesh() -> ArrayMesh:
	if _card_mesh_cache != null:
		return _card_mesh_cache
	var w := card_w
	var h := card_h
	var t := card_w * 0.022
	var cr := card_w * 0.075
	var pts: Array[Vector2] = []
	var corners: Array = [[Vector2(w * 0.5 - cr, h * 0.5 - cr), 0.0], [Vector2(-w * 0.5 + cr, h * 0.5 - cr), 90.0], [Vector2(-w * 0.5 + cr, -h * 0.5 + cr), 180.0], [Vector2(w * 0.5 - cr, -h * 0.5 + cr), 270.0]]
	for cn in corners:
		for i in range(6):
			var a := deg_to_rad(float(cn[1]) + 90.0 * float(i) / 5.0)
			pts.append((cn[0] as Vector2) + Vector2(cos(a), sin(a)) * cr)
	var n := pts.size()
	var mesh := ArrayMesh.new()
	for face in range(2):
		var z: float = t * 0.5 if face == 0 else -t * 0.5
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		verts.append(Vector3(0, 0, z))
		uvs.append(Vector2(0.5, 0.5))
		norms.append(Vector3(0, 0, 1.0 if face == 0 else -1.0))
		for p in pts:
			verts.append(Vector3(p.x, p.y, z))
			var u: float = p.x / w + 0.5 if face == 0 else 0.5 - p.x / w
			uvs.append(Vector2(u, 0.5 - p.y / h))
			norms.append(Vector3(0, 0, 1.0 if face == 0 else -1.0))
		for i in range(n):
			var a1 := 1 + i
			var a2 := 1 + (i + 1) % n
			if face == 0:
				idx.append_array(PackedInt32Array([0, a2, a1]))
			else:
				idx.append_array(PackedInt32Array([0, a1, a2]))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Edge ring
	var ev := PackedVector3Array()
	var en := PackedVector3Array()
	var eu := PackedVector2Array()
	var ei := PackedInt32Array()
	for i in range(n):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var d := (p1 - p0)
		var nrm := Vector3(d.y, -d.x, 0.0).normalized()
		var base := ev.size()
		ev.append(Vector3(p0.x, p0.y, t * 0.5))
		ev.append(Vector3(p1.x, p1.y, t * 0.5))
		ev.append(Vector3(p1.x, p1.y, -t * 0.5))
		ev.append(Vector3(p0.x, p0.y, -t * 0.5))
		for _k in range(4):
			en.append(nrm)
			eu.append(Vector2(0.5, 0.5))
		ei.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var ea: Array = []
	ea.resize(Mesh.ARRAY_MAX)
	ea[Mesh.ARRAY_VERTEX] = ev
	ea[Mesh.ARRAY_NORMAL] = en
	ea[Mesh.ARRAY_TEX_UV] = eu
	ea[Mesh.ARRAY_INDEX] = ei
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ea)
	_card_mesh_cache = mesh
	_card_edge_mat = StandardMaterial3D.new()
	_card_edge_mat.albedo_color = Color("e7dcc3")
	_card_edge_mat.roughness = 0.7
	_card_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mesh

func make_card(c: int) -> Node3D:
	var root := Node3D.new()
	root.set_meta(&"card", c)
	root.set_meta(&"flip", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _card_mesh()
	var fm := _card_material(card_texture(c))
	var bm := _card_material(card_texture(-1))
	mi.set_surface_override_material(0, fm)
	mi.set_surface_override_material(1, bm)
	mi.set_surface_override_material(2, _card_edge_mat)
	root.add_child(mi)
	root.set_meta(&"front_mat", fm)
	root.set_meta(&"back_mat", bm)
	viewport.add_child(root)
	_cards.append(root)
	return root

## Swap which card a node shows (used when an opponent's hole cards are revealed).
func set_card_face(node: Node3D, c: int) -> void:
	if not is_instance_valid(node):
		return
	var m: ShaderMaterial = node.get_meta(&"front_mat")
	m.set_shader_parameter("albedo_tex", card_texture(c))
	node.set_meta(&"card", c)

func set_card_pose(node: Node3D, t: Transform3D, flip: float) -> void:
	node.set_meta(&"base", t.basis)
	node.set_meta(&"flip", flip)
	node.basis = t.basis * Basis(Vector3.UP, PI * flip)
	node.position = t.origin

func _apply_flip(node: Node3D, f: float) -> void:
	if not is_instance_valid(node):
		return
	var base: Basis = node.get_meta(&"base")
	node.set_meta(&"flip", f)
	node.basis = base * Basis(Vector3.UP, PI * f)

func flip_card(node: Node3D, face_up: bool, dur: float = 0.25) -> void:
	if not is_instance_valid(node):
		return
	var from: float = node.get_meta(&"flip", 1.0)
	var to: float = 0.0 if face_up else 1.0
	if absf(from - to) < 0.01:
		return
	var tw := node.create_tween()
	tw.tween_method(func(f: float) -> void: _apply_flip(node, f), from, to, dur)
	var lift := node.create_tween()
	lift.tween_property(node, "position:y", node.position.y + card_h * 0.18, dur * 0.5).set_ease(Tween.EASE_OUT)
	lift.tween_property(node, "position:y", node.position.y, dur * 0.5).set_ease(Tween.EASE_IN)

func move_card(node: Node3D, to: Vector3, dur: float = 0.3) -> void:
	if not is_instance_valid(node):
		return
	var tw := node.create_tween()
	tw.tween_property(node, "position", to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_card_state(node: Node3D, lit: bool, dim: bool) -> void:
	if not is_instance_valid(node):
		return
	for key in [&"front_mat", &"back_mat"]:
		var m: ShaderMaterial = node.get_meta(key)
		m.set_shader_parameter("glow", 1.0 if lit else 0.0)
		m.set_shader_parameter("dim", 1.0 if dim else 0.0)

func clear_cards() -> void:
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()

## Screen-space rectangle (UI canvas units) around a set of world points.
func screen_rect(points: Array) -> Rect2:
	var r := Rect2(project(points[0]), Vector2.ZERO)
	for p in points:
		r = r.expand(project(p))
	return r

func card_corners(t: Transform3D) -> Array:
	var out: Array = []
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			out.append(t * Vector3(sx * card_w, sy * card_h, 0.0))
	return out

# ── Your chip rack, the betting ring, camera look ───────────────────

## The betting circle: right under your cards, a little nearer you. Aim at it to push chips or check.
func ring_point() -> Vector3:
	var p := felt_pt(0, 0.115, 0.0)
	return Vector3(p.x, surface_y, p.z)

func pending_point() -> Vector3:
	return inside_felt(ring_point() + right_of(0) * 0.23, 0.05)

func set_pending(comp: Dictionary) -> void:
	var sig := str(comp)
	if sig == _pending_sig:
		return
	_pending_sig = sig
	for n in _pending_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_pending_nodes.clear()
	var r := _chip_dims().x
	var col_i := 0
	for d in DENOMS:
		var c: int = int(comp.get(d, 0))
		if c <= 0:
			continue
		var col := _column(d, c)
		viewport.add_child(col)
		col.position = pending_point() + right_of(0) * float(col_i) * _pitch()
		_pending_nodes.append(col)
		col_i += 1

func pulse_ring(on: bool) -> void:
	if ring_node == null:
		var m := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = card_w * 0.50
		tm.outer_radius = card_w * 0.56
		tm.rings = 40
		tm.ring_segments = 6
		m.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.79, 0.64, 0.36, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.79, 0.64, 0.36)
		mat.emission_energy_multiplier = 0.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.scale = Vector3(1.0, 0.05, 1.0)
		viewport.add_child(m)
		m.position = ring_point() + Vector3(0, 0.004, 0)
		ring_node = m
	var mat2: StandardMaterial3D = ring_node.material_override
	mat2.albedo_color.a = 0.9 if on else 0.18
	mat2.emission_energy_multiplier = 1.0 if on else 0.0

## Fold: the cards flick across the felt (spinning) and land face down in the muck by the deck.
func toss(node: Node3D, delay: float = 0.0) -> void:
	if not is_instance_valid(node):
		return
	var start := node.position
	var base: Basis = node.get_meta(&"base", node.basis)
	var f0: float = node.get_meta(&"flip", 1.0)
	var spin := randf_range(1.2, 2.6) * TAU * (1.0 if randf() < 0.5 else -1.0)
	var target := muck_target()
	set_card_bend(node, 0.0)
	var step := func(t: float) -> void:
		if is_instance_valid(node):
			node.position = start.lerp(target, t) + Vector3(0, sin(t * PI) * card_h * 0.7, 0)
			# Turn face down on the way (a peeked card starts face up).
			node.basis = Basis(Vector3.UP, spin * t) * base * Basis(Vector3.UP, PI * lerpf(f0, 1.0, minf(t * 2.0, 1.0)))
	var tw := node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(step, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.set_meta(&"flip", 1.0)
			node.set_meta(&"base", node.basis * Basis(Vector3.UP, -PI)))

func emote(i: int, icon: String) -> void:
	var a: Node3D = actors.get(i, null)
	if a != null and is_instance_valid(a):
		a.emote(icon, 1.5)

func confetti(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = tsize * 0.04
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = tsize * 0.8
	pm.initial_velocity_max = tsize * 1.6
	pm.gravity = Vector3(0, -tsize * 1.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color("ffd877"), Color("ff6b5a"), Color("7fe0a1"), Color("8fb8ff")])
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(tsize * 0.018, tsize * 0.026)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	p.draw_pass_1 = q
	viewport.add_child(p)
	p.position = at
	p.emitting = true
	get_tree().create_timer(3.2).timeout.connect(p.queue_free)

## Mouse look: yaw/pitch in degrees on top of the seat camera's authored direction.
func set_look(yaw_deg: float, pitch_deg: float, tilt_deg: float = 0.0, roll_deg: float = 0.0) -> void:
	if camera == null:
		return
	var rest := _base_rot.x + deg_to_rad(pitch_deg)
	# A vice (cigarette / glass) nods the head on top of where you are looking.
	if camera.has_meta(&"vice_rest_pitch"):
		camera.set_meta(&"vice_rest_pitch", rest)
	camera.global_rotation = Vector3(rest + deg_to_rad(tilt_deg), _base_rot.y + deg_to_rad(yaw_deg), _base_rot.z + deg_to_rad(roll_deg))

## Hanging coasters: a small shelf bolted to the outside of the rail on each side of every seat, one for the
## glass (to the seat's right) and one for the ashtray (to its left). Nothing stands on the felt.
func vice_spot(seat: int, kind: String) -> Vector3:
	var base := seat_marker_pos(seat)
	var dc := Vector3(base.x - center.x, 0.0, base.z - center.z).normalized()
	var e := felt_extent(dc) + RAIL_W + 0.10
	var lat := 0.56 if kind == "glass" else -0.56
	var p := Vector3(center.x, surface_y, center.z) + dc * e + right_of(seat) * lat
	return Vector3(p.x, surface_y - 0.045, p.z)

func _build_hangers() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.09, 0.045, 0.03)
	wood.roughness = 0.35
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.5
	var brass := TableBuilder._metal(TableBuilder.BRASS, 0.3)
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.02, 0.09, 0.06)
	felt.roughness = 0.95
	for s in range(n_seats):
		for kind in ["glass", "ashtray"]:
			var spot := vice_spot(s, kind)
			var root := Node3D.new()
			viewport.add_child(root)
			root.position = Vector3(spot.x, spot.y - 0.006, spot.z)
			var base := seat_marker_pos(s)
			var dc := Vector3(base.x - center.x, 0.0, base.z - center.z).normalized()
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.105
			cm.bottom_radius = 0.105
			cm.height = 0.014
			cm.radial_segments = 36
			disc.mesh = cm
			disc.material_override = wood
			root.add_child(disc)
			var rim := MeshInstance3D.new()
			var rc := CylinderMesh.new()
			rc.top_radius = 0.114
			rc.bottom_radius = 0.114
			rc.height = 0.008
			rc.radial_segments = 36
			rim.mesh = rc
			rim.material_override = brass
			rim.position.y = -0.004
			root.add_child(rim)
			var inlay := MeshInstance3D.new()
			var ic := CylinderMesh.new()
			ic.top_radius = 0.088
			ic.bottom_radius = 0.088
			ic.height = 0.004
			ic.radial_segments = 36
			inlay.mesh = ic
			inlay.material_override = felt if kind == "glass" else wood
			inlay.position.y = 0.008
			root.add_child(inlay)
			# Bracket back to the apron
			var arm := MeshInstance3D.new()
			var ab := BoxMesh.new()
			ab.size = Vector3(0.05, 0.012, 0.14)
			arm.mesh = ab
			arm.material_override = brass
			root.add_child(arm)
			arm.look_at_from_position(root.global_position - dc * 0.09 + Vector3(0, -0.005, 0), root.global_position + Vector3(0, -0.005, 0) + dc * 0.09, Vector3.UP)

func look_angles_to(point: Vector3) -> Vector2:
	var d := point - camera.global_position
	var yaw_t := atan2(-d.x, -d.z)
	var flat := Vector2(d.x, d.z).length()
	var pitch_t := atan2(d.y, flat)
	return Vector2(rad_to_deg(wrapf(yaw_t - _base_rot.y, -PI, PI)), rad_to_deg(pitch_t - _base_rot.x))

func punch_fov(amount: float = 7.0) -> void:
	if camera == null:
		return
	var tw := camera.create_tween()
	tw.tween_property(camera, "fov", _base_fov - amount, 0.18)
	tw.tween_property(camera, "fov", _base_fov, 0.5).set_trans(Tween.TRANS_CUBIC)

func has_hole_cards(nodes: Array) -> bool:
	for n in nodes:
		if n == null or not is_instance_valid(n):
			return false
	return true

## Debug / spectating: put the camera where a seat's player would sit.
func debug_view(seat: int) -> void:
	var p := seat_marker_pos(seat)
	var out := Vector3(p.x - center.x, 0.0, p.z - center.z).normalized()
	camera.global_position = Vector3(p.x, 0.0, p.z) + out * 0.5 + Vector3(0.0, TABLE_H + 0.86, 0.0)
	camera.look_at(Vector3(center.x, surface_y - 0.02, center.z) + out * 0.05, Vector3.UP)
	_base_rot = camera.global_rotation

## Showdown: a contender's two cards slide forward onto the felt in front of them and turn face up.
func show_hole(nodes: Array, seat: int) -> void:
	for k in range(2):
		var n: Variant = nodes[k]
		if n == null or not is_instance_valid(n):
			continue
		var node: Node3D = n
		var t := show_transform(seat, k)
		var start := node.position
		var q0 := Quaternion(node.basis.orthonormalized())
		var q1 := Quaternion(t.basis)
		node.set_meta(&"base", t.basis)
		set_card_bend(node, 0.0)
		var step := func(f: float) -> void:
			if is_instance_valid(node):
				node.position = start.lerp(t.origin, f) + Vector3(0, sin(f * PI) * card_h * 0.5, 0)
				node.basis = Basis(q0.slerp(q1, f))
		var tw := node.create_tween()
		tw.tween_interval(0.1 * k)
		tw.tween_method(step, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void:
			if is_instance_valid(node):
				node.set_meta(&"flip", 0.0)
				node.basis = t.basis
				node.position = t.origin)

func is_behind(point: Vector3) -> bool:
	return camera != null and camera.is_position_behind(point)

## ── Chips ────────────────────────────────────────────────────────────

class ChipFace extends Control:
	var value: int = 1
	var base: Color = Color.WHITE
	var accent: Color = Color.BLACK
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_circle(c, r, base)
		# Edge spots
		for i in range(8):
			var a := TAU * float(i) / 8.0
			var p0 := c + Vector2(cos(a - 0.17), sin(a - 0.17)) * r * 0.97
			var p1 := c + Vector2(cos(a + 0.17), sin(a + 0.17)) * r * 0.97
			var p2 := c + Vector2(cos(a + 0.17), sin(a + 0.17)) * r * 0.78
			var p3 := c + Vector2(cos(a - 0.17), sin(a - 0.17)) * r * 0.78
			draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), accent)
		draw_arc(c, r * 0.72, 0, TAU, 48, accent, r * 0.035)
		draw_circle(c, r * 0.66, base.darkened(0.12))
		draw_circle(c, r * 0.6, base)
		draw_arc(c, r * 0.6, 0, TAU, 48, Color(accent, 0.7), r * 0.02)
		var font := ThemeDB.fallback_font
		var txt := str(value)
		var fs := int(r * (0.78 if txt.length() < 3 else 0.6))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var txt_col := accent if base.get_luminance() < 0.5 else Color("1a1a1f")
		if value == 1:
			txt_col = Color("1a1a1f")
		draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.33), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)

func chip_color(d: int) -> Color:
	for x in CHIP_DENOMS:
		if int(x[0]) == d:
			return x[1]
	return Color.WHITE

func greedy(v: int) -> Dictionary:
	var out: Dictionary = {}
	var left := v
	for d in [500, 100, 25, 5, 1]:
		out[d] = int(left / d)
		left -= int(left / d) * d
	return out

func _chip_dims() -> Vector2:
	return Vector2(tsize * 0.034, tsize * 0.0125)

func _chip_mesh(d: int) -> ArrayMesh:
	if _chip_mesh_cache.has(d):
		return _chip_mesh_cache[d]
	var dims := _chip_dims()
	var base := chip_color(d)
	var accent: Color = CHIP_ACCENT[d]
	# Edge: a capless cylinder, base colour with 8 accent blocks around the rim.
	var cyl := CylinderMesh.new()
	cyl.top_radius = dims.x
	cyl.bottom_radius = dims.x
	cyl.height = dims.y
	cyl.radial_segments = 32
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var img := Image.create(128, 8, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for k in range(8):
		for x in range(k * 16 + 3, k * 16 + 13):
			for y in range(0, 8):
				img.set_pixel(x, y, accent)
	var side := StandardMaterial3D.new()
	side.albedo_texture = ImageTexture.create_from_image(img)
	side.roughness = 0.4
	side.metallic = 0.1
	side.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cyl.get_mesh_arrays())
	mesh.surface_set_material(0, side)
	# Top face: a triangle fan whose texture shows the value.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var y := dims.y * 0.5
	verts.append(Vector3(0, y, 0))
	uvs.append(Vector2(0.5, 0.5))
	norms.append(Vector3.UP)
	var seg := 32
	for i in range(seg):
		var a := TAU * float(i) / float(seg)
		verts.append(Vector3(cos(a) * dims.x, y, sin(a) * dims.x))
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
		norms.append(Vector3.UP)
	for i in range(seg):
		idx.append(0)
		idx.append(1 + (i + 1) % seg)
		idx.append(1 + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var vp := SubViewport.new()
	vp.size = Vector2i(192, 192)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var face := ChipFace.new()
	face.size = Vector2(192, 192)
	face.value = d
	face.base = base
	face.accent = accent
	vp.add_child(face)
	viewport.add_child(vp)
	_chip_face_vp[d] = vp
	var top := StandardMaterial3D.new()
	top.albedo_texture = vp.get_texture()
	top.roughness = 0.35
	top.metallic = 0.1
	top.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, top)
	_chip_mesh_cache[d] = mesh
	return mesh

func _chip_node(d: int) -> MeshInstance3D:
	var chip := MeshInstance3D.new()
	chip.mesh = _chip_mesh(d)
	return chip

func _column(d: int, count: int) -> Node3D:
	var root := Node3D.new()
	var h := _chip_dims().y
	for k in range(mini(count, MAX_TOWER)):
		var chip := _chip_node(d)
		chip.position.y = h * 0.5 + k * h * 1.04
		chip.rotation.y = randf() * TAU
		root.add_child(chip)
	return root

func _felt_clamp(p: Vector3, max_r: float) -> Vector3:
	var v := Vector3(p.x - center.x, 0.0, p.z - center.z)
	if v.length() > max_r:
		v = v.normalized() * max_r
	return Vector3(center.x + v.x, p.y, center.z + v.z)

## The dealer: a character in the gap of the seating ring who runs the deck.
func _spawn_dealer() -> void:
	var base := Vector3(dealer_pt.x, 0.0, dealer_pt.z) + dealer_dir * 0.55
	var actor: Node3D = CharacterActor.new()
	viewport.add_child(actor)
	actor.setup("res://assets/imported_assets/kenney_blocky-characters_20/Models/GLB format/character-g.glb", 1.0, Color("c9a45c"), 20)
	var m: Dictionary = RoomCrowd.measure(actor)
	var h: float = maxf(float(m.hi) - float(m.lo), 0.1)
	var sc: float = 1.35 / h
	actor.scale = Vector3.ONE * sc
	actor.set("_base_scale", sc)
	actor.position = Vector3(base.x, -float(m.lo) * sc, base.z)
	var to_c := Vector3(center.x, 0.0, center.z) - base
	actor.rotation.y = atan2(to_c.x, to_c.z)
	actor.glance = false
	dealer_actor = actor
	_dress_dealer(actor)

## A bow tie and a green visor so the dealer reads as the house at a glance.
func _dress_dealer(actor: Node3D) -> void:
	var model: Node3D = actor.get("model")
	if model == null:
		return
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("9e1b2a")
	red.roughness = 0.6
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("2a8a52")
	green.roughness = 0.5
	var tie := Node3D.new()
	tie.position = Vector3(0.0, 1.03, 0.13)
	for sgn in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.11, 0.07, 0.035)
		wing.mesh = bm
		wing.material_override = red
		wing.position = Vector3(0.07 * sgn, 0.0, 0.0)
		wing.rotation_degrees.z = 18.0 * sgn
		tie.add_child(wing)
	var knot := MeshInstance3D.new()
	var kb := BoxMesh.new()
	kb.size = Vector3(0.05, 0.05, 0.04)
	knot.mesh = kb
	knot.material_override = red
	tie.add_child(knot)
	model.add_child(tie)
	var head := model.find_child("head", true, false) as Node3D
	if head != null:
		var visor := MeshInstance3D.new()
		var vb := BoxMesh.new()
		vb.size = Vector3(3.6, 0.35, 2.6)
		visor.mesh = vb
		visor.material_override = green
		visor.position = Vector3(0.0, 2.7, -0.6)
		head.add_child(visor)

func dealer_gesture() -> void:
	if dealer_actor != null and is_instance_valid(dealer_actor):
		dealer_actor.react(&"play")

## The flat dealer button (a white puck) sits in front of the dealer-button player's cards.
func set_dealer_button(seat: int) -> void:
	if _button == null:
		_button = Node3D.new()
		var puck := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = card_w * 0.34
		cyl.bottom_radius = card_w * 0.34
		cyl.height = 0.012
		cyl.radial_segments = 32
		puck.mesh = cyl
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color("f1e8d4")
		pm.roughness = 0.35
		puck.material_override = pm
		_button.add_child(puck)
		var rim := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = card_w * 0.36
		rc.bottom_radius = card_w * 0.36
		rc.height = 0.006
		rim.mesh = rc
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color("c9a45c")
		rm.metallic = 0.8
		rm.roughness = 0.3
		rim.material_override = rm
		rim.position.y = -0.002
		_button.add_child(rim)
		var lbl := Label3D.new()
		lbl.text = "D"
		lbl.font = UIStyle.title_font()
		lbl.font_size = 48
		lbl.pixel_size = 0.0007 * tsize
		lbl.modulate = Color("1a1a1f")
		lbl.rotation_degrees.x = -90.0
		lbl.position.y = 0.008
		lbl.no_depth_test = false
		_button.add_child(lbl)
		viewport.add_child(_button)
		_button.position = _button_spot(seat)
	var target := _button_spot(seat)
	var tw := _button.create_tween()
	tw.tween_property(_button, "position:y", target.y + card_h * 0.3, 0.12)
	tw.tween_property(_button, "position", target + Vector3(0, card_h * 0.3, 0), 0.35).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_button, "position:y", target.y, 0.1)

func button_point() -> Vector3:
	return _button.position if _button != null else center

func _button_spot(seat: int) -> Vector3:
	var p := felt_pt(seat, 0.44, -0.34)
	return Vector3(p.x, surface_y + 0.012, p.z)

func burn_card() -> void:
	var node := make_card(-1)
	var fwd := dealer_dir * -1.0
	var yaw := atan2(-fwd.x, -fwd.z)
	var basis := Basis(Vector3.UP, yaw + randf_range(-0.2, 0.2)) * Basis(Vector3.RIGHT, -PI / 2.0)
	var jitter := Vector3(randf_range(-0.01, 0.01), 0.0, randf_range(-0.01, 0.01))
	set_card_pose(node, Transform3D(basis, deck_pos + Vector3(0, 0.05, 0)), 1.0)
	deal_card(node, Transform3D(basis, burn_pos + jitter + Vector3(0, 0.006 + 0.003 * float(_burn_n), 0)), 0.3, 0.0, 0.6)
	_burn_n += 1

var _burn_n: int = 0

func reset_table_piles() -> void:
	_burn_n = 0
	_muck_count = 0

## A folded hand is mucked: face down into the dealer's pile.
## (toss() is used for the throw; the pile just stacks slightly higher each time.)
func muck_target() -> Vector3:
	_muck_count += 1
	return muck_pos + Vector3(randf_range(-0.03, 0.03), 0.004 * float(_muck_count), randf_range(-0.03, 0.03))

## The dealer's house chip tray: a dark tray in front of the dealer with neat chip rows.
func _build_dealer_tray(d_right: Vector3) -> void:
	var root := Node3D.new()
	viewport.add_child(root)
	root.position = Vector3(tray_pos.x, surface_y + 0.006, tray_pos.z)
	root.rotation.y = atan2(-(-dealer_dir.x), -(-dealer_dir.z))
	var tray := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.62, 0.014, 0.11)
	tray.mesh = tb
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.05, 0.04, 0.045)
	tm.roughness = 0.4
	tray.material_override = tm
	root.add_child(tray)
	var rimm := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.64, 0.008, 0.125)
	rimm.mesh = rb
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("c9a45c")
	bm.metallic = 0.8
	bm.roughness = 0.3
	rimm.material_override = bm
	rimm.position.y = -0.004
	root.add_child(rimm)
	var i := 0
	for d in DENOMS:
		var col := _column(d, 6 + (4 - i) * 2)
		col.position = Vector3((float(i) - 2.0) * _pitch() * 0.9, 0.007, 0.0)
		root.add_child(col)
		i += 1


## A point on the felt for a seat: `depth` metres in from the felt edge (along the line from the centre to the
## seat) and `lateral` metres to the seat's right (negative = left). Measuring from the edge keeps everything
## on the cloth for every seat of an oval table, whether it sits on the long side, an end or a corner.
func felt_pt(seat: int, depth: float, lateral: float) -> Vector3:
	var base := seat_marker_pos(seat)
	var dc := Vector3(base.x - center.x, 0.0, base.z - center.z).normalized()
	var e := felt_extent(dc)
	var p := Vector3(center.x, surface_y, center.z) + dc * (e - depth)
	return inside_felt(p + right_of(seat) * lateral, 0.10)

## Pulls a point back onto the cloth (margin metres in from the edge) so nothing hovers over the rail or beyond it.
func inside_felt(p: Vector3, margin: float) -> Vector3:
	var v := Vector3(p.x - center.x, 0.0, p.z - center.z)
	var l := v.length()
	if l < 0.001:
		return p
	var dir := v / l
	var e := felt_extent(dir) - margin
	if l > e:
		return Vector3(center.x + dir.x * e, p.y, center.z + dir.z * e)
	return p

func _pitch() -> float:
	return _chip_dims().x * 2.35

## Rotation that lines a chip layout up with a seat (columns run along the seat's right).
func _seat_yaw(seat: int) -> float:
	var f := forward_of(seat)
	return atan2(-f.x, -f.z)

## Your selectable chips stand on a tray that hangs off the rail dead centre in front of you.
func hang_tray_center() -> Vector3:
	var base := seat_marker_pos(0)
	var dc := Vector3(base.x - center.x, 0.0, base.z - center.z).normalized()
	var e := felt_extent(dc) + RAIL_W + 0.17
	return Vector3(center.x + dc.x * e, surface_y - 0.035, center.z + dc.z * e)

func tray_center(seat: int) -> Vector3:
	if seat == 0:
		return hang_tray_center()
	return felt_pt(seat, 0.26, 0.62)

func stack_point(seat: int, d: int) -> Vector3:
	var i: int = DENOMS.find(d)
	if seat == 0:
		var q := tray_center(0) + right_of(0) * (float(i) - 2.0) * _pitch() * 1.18
		return q + Vector3(0, card_w * 0.1, 0)
	var p := inside_felt(tray_center(seat) + right_of(seat) * (float(i) - 2.0) * _pitch(), 0.07)
	return p + Vector3(0, card_w * 0.1, 0)

func _build_hang_tray() -> void:
	var root := Node3D.new()
	viewport.add_child(root)
	var c := hang_tray_center()
	root.position = c
	root.rotation.y = _seat_yaw(0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.1, 0.05, 0.035)
	wood.roughness = 0.3
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.6
	var brass := TableBuilder._metal(TableBuilder.BRASS, 0.3)
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.02, 0.1, 0.07)
	felt.roughness = 0.95
	var width := _pitch() * 1.18 * 5.0 + 0.1
	var tray := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(width, 0.018, 0.24)
	tray.mesh = tb
	tray.material_override = wood
	tray.position.y = -0.009
	root.add_child(tray)
	var rim := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(width + 0.03, 0.01, 0.27)
	rim.mesh = rb
	rim.material_override = brass
	rim.position.y = -0.021
	root.add_child(rim)
	var lining := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(width - 0.04, 0.004, 0.2)
	lining.mesh = lb
	lining.material_override = felt
	lining.position.y = 0.0
	root.add_child(lining)
	var i := 0
	for d in DENOMS:
		var slot := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = _chip_dims().x * 1.12
		cm.bottom_radius = cm.top_radius
		cm.height = 0.004
		cm.radial_segments = 28
		slot.mesh = cm
		var sm := StandardMaterial3D.new()
		sm.albedo_color = chip_color(d).darkened(0.35)
		sm.roughness = 0.8
		slot.material_override = sm
		slot.position = Vector3((float(i) - 2.0) * _pitch() * 1.18, 0.003, 0.0)
		root.add_child(slot)
		i += 1
	# Two brackets back to the apron
	for sx in [-0.5, 0.5]:
		var arm := MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(0.035, 0.014, 0.17)
		arm.mesh = ab
		arm.material_override = brass
		arm.position = Vector3(width * sx * 0.78, -0.026, -0.2)
		root.add_child(arm)

func rack_point(d: int) -> Vector3:
	return stack_point(0, d)

func fly_chip(from: Vector3, to: Vector3, d: int, dur: float = 0.28, done: Callable = Callable(), delay: float = 0.0) -> void:
	var chip := _chip_node(d)
	viewport.add_child(chip)
	chip.position = from
	chip.visible = delay <= 0.0
	var lift := tsize * 0.12
	var step := func(t: float) -> void:
		if is_instance_valid(chip):
			chip.visible = true
			chip.position = from.lerp(to, t) + Vector3(0, sin(t * PI) * lift, 0)
			chip.rotation.x = t * TAU * 1.5
	var tw := chip.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(step, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(chip):
			chip.queue_free()
		if done.is_valid():
			done.call())

func sweep(to: Vector3) -> void:
	var nodes: Array = []
	for k in _bet_nodes:
		var e: Dictionary = _bet_nodes[k]
		nodes.append(e["node"])
	if _pot_node != null and is_instance_valid(_pot_node):
		nodes.append(_pot_node)
	var i := 0
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var tw := (n as Node3D).create_tween()
		tw.tween_interval(0.08 * i)
		tw.tween_property(n, "position", to + Vector3(0, 0.05, 0), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.35, 0.7)
		tw.tween_callback(n.queue_free)
		i += 1
	_bet_nodes.clear()
	_pot_node = null
	_pot_amount = -1

## ── Real chip banks ─────────────────────────────────────────────────

func bank_of(seat: int) -> Bank:
	if not _banks.has(seat):
		_banks[seat] = Bank.new()
	return _banks[seat]

## Reconciles a seat's chips to `value` and redraws its towers. Returns {removed, added}.
func sync_bank(seat: int, value: int) -> Dictionary:
	var bank := bank_of(seat)
	var first: bool = not _stacks.has(seat)
	var d: Dictionary = bank.sync(value)
	if first or not (d.removed as Dictionary).is_empty() and Bank.value_of(d.removed) > 0 or Bank.value_of(d.added) > 0:
		render_bank(seat, Bank.value_of(d.added) > 0 and not first)
	elif not _stack_labels.has(seat):
		render_bank(seat, false)
	return d

## One tower per denomination (extra towers behind it when a count tops MAX_TOWER).
## Heights are the player's real chips, so the stack visibly shrinks and grows.
func render_bank(seat: int, pop: bool = false) -> void:
	var bank := bank_of(seat)
	var sig := str(bank.counts)
	var cur: Dictionary = _stacks.get(seat, {})
	if cur.get("sig", "") == sig:
		_update_stack_label(seat, bank.value())
		return
	if cur.has("nodes"):
		for d in cur["nodes"]:
			for n in cur["nodes"][d]:
				if is_instance_valid(n):
					n.queue_free()
	var nodes: Dictionary = {}
	var r := _chip_dims().x
	var fwd := forward_of(seat)
	var tallest := 0
	for d in DENOMS:
		var count: int = int(bank.counts[d])
		var towers: Array = []
		var left: int = count
		var t := 0
		while left > 0 and t < MAX_TOWERS_PER_DENOM:
			var n_here: int = mini(left, MAX_TOWER) if t < MAX_TOWERS_PER_DENOM - 1 else left
			var col := _column(d, n_here)
			viewport.add_child(col)
			col.position = stack_point(seat, d) - Vector3(0, card_w * 0.1, 0) + fwd * float(t) * _pitch()
			if pop:
				col.scale = Vector3.ONE * 0.8
				col.create_tween().tween_property(col, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			towers.append(col)
			tallest = maxi(tallest, mini(n_here, MAX_TOWER))
			left -= n_here
			t += 1
		nodes[d] = towers
	_stacks[seat] = {"sig": sig, "nodes": nodes, "tallest": tallest}
	_update_stack_label(seat, bank.value())

func _update_stack_label(_seat: int, _value: int) -> void:
	pass

func highlight_rack(d: int) -> void:
	if d == _hover_d:
		return
	_hover_d = d
	var nodes: Dictionary = _stacks.get(0, {}).get("nodes", {})
	for k in nodes:
		for n in nodes[k]:
			if is_instance_valid(n):
				var tw := (n as Node3D).create_tween()
				tw.tween_property(n, "scale", Vector3.ONE * (1.25 if int(k) == d else 1.0), 0.1)

## Chips built from exact counts (a bet or the pot) as one cluster of towers.
func _chip_stack_comp(comp: Dictionary) -> Node3D:
	var root := Node3D.new()
	var r := _chip_dims().x
	var col_i := 0
	for d in [500, 100, 25, 5, 1]:
		var c: int = int(comp.get(d, 0))
		if c <= 0:
			continue
		var col := _column(d, c)
		col.position.x = col_i * _pitch()
		root.add_child(col)
		col_i += 1
	for ch in root.get_children():
		(ch as Node3D).position.x -= float(maxi(col_i - 1, 0)) * _pitch() * 0.5
	return root

## Records chips you pushed in with the pile so the bet stack shows those exact chips.
func note_bet_chips(seat: int, comp: Dictionary) -> void:
	var cur: Dictionary = _bet_comp.get(seat, {500: 0, 100: 0, 25: 0, 5: 0, 1: 0})
	for d in comp:
		cur[d] = int(cur.get(d, 0)) + int(comp[d])
	_bet_comp[seat] = cur

## The bet stack in front of a seat. `removed` = chips that just left their stack (they fly in).
func set_bet(seat: int, amount: int, removed: Dictionary = {}) -> void:
	var cur: Variant = _bet_nodes.get(seat, null)
	var has_node: bool = cur != null and is_instance_valid(cur["node"])
	if amount <= 0:
		if has_node:
			(cur["node"] as Node3D).queue_free()
		_bet_nodes.erase(seat)
		_bet_comp.erase(seat)
		return
	var comp: Dictionary = _bet_comp.get(seat, {500: 0, 100: 0, 25: 0, 5: 0, 1: 0})
	if seat != 0:
		for d in removed:
			comp[d] = int(comp.get(d, 0)) + int(removed[d])
	if Bank.value_of(comp) != amount:
		comp = Bank.mixed(amount)
	_bet_comp[seat] = comp
	if has_node and int(cur["amount"]) == amount:
		return
	if has_node:
		(cur["node"] as Node3D).queue_free()
	var node := _chip_stack_comp(comp)
	viewport.add_child(node)
	node.rotation.y = _seat_yaw(seat)
	node.position = bet_pos(seat)
	_bet_nodes[seat] = {"node": node, "amount": amount}
	if seat != 0 and Bank.value_of(removed) > 0:
		var n := 0
		for d in [500, 100, 25, 5, 1]:
			for _k in range(mini(int(removed.get(d, 0)), 3)):
				fly_chip(stack_point(seat, d), bet_pos(seat), d, 0.3, Callable(), 0.06 * n)
				n += 1
		node.scale = Vector3.ONE * 0.01
		var tw2 := node.create_tween()
		tw2.tween_interval(0.12 * mini(n, 4))
		tw2.tween_property(node, "scale", Vector3.ONE, 0.12)
	else:
		node.scale = Vector3.ONE * 0.6
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_pot(amount: int) -> void:
	if amount == _pot_amount:
		return
	_pot_amount = amount
	if _pot_node != null and is_instance_valid(_pot_node):
		_pot_node.queue_free()
		_pot_node = null
	if amount <= 0:
		return
	_pot_node = _chip_stack_comp(Bank.mixed(amount))
	viewport.add_child(_pot_node)
	_pot_node.rotation.y = _seat_yaw(0)
	_pot_node.position = pot_pos()

## A small walnut tray with a brass rim under each seat's chips keeps them in an orderly row.
func _build_trays() -> void:
	var width := _pitch() * 5.0 + 0.03
	var depth := _pitch() * 1.25 + 0.03
	for i in range(n_seats):
		var root := Node3D.new()
		var brass := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(width + 0.02, 0.006, depth + 0.02)
		brass.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("c9a45c")
		bm.metallic = 0.5
		bm.roughness = 0.35
		brass.material_override = bm
		root.add_child(brass)
		var wood := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(width, 0.01, depth)
		wood.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color("2a1710")
		wm.roughness = 0.55
		wood.material_override = wm
		wood.position.y = 0.004
		root.add_child(wood)
		viewport.add_child(root)
		root.rotation.y = _seat_yaw(i)
		# The tray sits just behind the front row of towers (towers spill toward the table centre).
		root.position = tray_center(i) + Vector3(0, 0.014, 0)

## A faint ring on the felt marks each player's betting spot, tinted in their colour.
func _build_seat_rings() -> void:
	for i in range(1, n_seats):
		var m := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = card_w * 0.95
		cyl.bottom_radius = card_w * 0.95
		cyl.height = 0.002
		cyl.radial_segments = 36
		m.mesh = cyl
		var mat := StandardMaterial3D.new()
		var col: Color = _colors[i] if i < _colors.size() else Color.WHITE
		mat.albedo_color = Color(col, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		viewport.add_child(m)
		m.position = bet_pos(i) + Vector3(0, 0.003, 0)
		_seat_rings[i] = m

## An expanding ring on the felt (a knock, a chip landing).
func ripple(at: Vector3, col: Color = Color(1, 1, 1)) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = card_w * 0.5
	cyl.bottom_radius = card_w * 0.5
	cyl.height = 0.001
	cyl.radial_segments = 32
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	viewport.add_child(m)
	m.position = Vector3(at.x, surface_y + 0.006, at.z)
	var tw := m.create_tween().set_parallel()
	tw.tween_property(m, "scale", Vector3(3.2, 1, 3.2), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(m.queue_free)

## Your fist comes down on the felt twice. Returns when it is gone.
func knock_fist(sleeve: Color, on_tap: Callable = Callable()) -> void:
	var fist := EmoteRig.build_fist(Color("c98f68"), sleeve)
	viewport.add_child(fist)
	var s := card_w * 0.26 / 0.36
	fist.scale = Vector3.ONE * s
	var fwd := forward_of(0)
	var yaw := atan2(-fwd.x, -fwd.z)
	fist.basis = (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -2.214)).scaled(Vector3.ONE * s)
	var tip := ring_point() + Vector3(0, card_w * 0.34, 0)
	var high := tip + Vector3(0, card_w * 0.9, 0) - fwd * card_w * 0.5
	fist.position = high - fwd * card_w * 1.2
	var tw := fist.create_tween()
	tw.tween_property(fist, "position", high, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for k in range(2):
		tw.tween_property(fist, "position", tip, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			ripple(ring_point(), Color(1, 0.95, 0.8))
			if on_tap.is_valid():
				on_tap.call())
		tw.tween_property(fist, "position", high, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fist, "position", high - fwd * card_w * 1.4 + Vector3(0, -card_w * 0.3, 0), 0.2)
	tw.tween_callback(fist.queue_free)

## Your pile slides into the bet spot. kind: "call" (a gentle slide) or "raise" (a toss).
func commit_anim(kind: String, comp: Dictionary) -> void:
	var n := 0
	var raise := kind == "raise"
	for d in [500, 100, 25, 5, 1]:
		for _k in range(mini(int(comp.get(d, 0)), 6)):
			var scatter := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) * card_w * (0.55 if raise else 0.12)
			fly_chip(pending_point() + Vector3(0, 0.03, 0), bet_pos(0) + scatter, d, 0.38 if raise else 0.26, Callable(), 0.06 * n)
			n += 1
	if n > 0:
		get_tree().create_timer(0.3 + 0.06 * n).timeout.connect(func() -> void:
			ripple(bet_pos(0), chip_color(100) if raise else Color(1, 1, 1)))

# ── Deck + chips ──────────────────────────────────────────────────────

func _build_deck() -> void:
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(card_w * 0.98, card_w * 0.22, card_h * 0.98)
	slab.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.82, 0.72)
	mat.roughness = 0.7
	slab.material_override = mat
	viewport.add_child(slab)
	slab.position = deck_pos + Vector3(0, box.size.y * 0.5, 0)
	slab.rotation.y = atan2(-forward_of(0).x, -forward_of(0).z)
	var top := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(card_w, card_h)
	top.mesh = q
	top.material_override = _card_material(card_texture(-1))
	top.rotation_degrees.x = -90.0
	top.position.y = box.size.y * 0.5 + 0.002
	slab.add_child(top)

var _pot_amount: int = -1

