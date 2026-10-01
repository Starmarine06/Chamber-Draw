extends Node3D

## Living background for the noir back room: a bartender behind a bar, patrons
## leaning on it, pairs chatting in the corners and a few people strolling the
## floor. Reuses the Kenney blocky characters (CharacterActor) and their built-in
## clips (idle / walk / interact / emote / drink / smoke), so no extra assets.

const CharacterActor := preload("res://scripts/character_actor.gd")
const GLB := "res://assets/imported_assets/kenney_blocky-characters_20/Models/GLB format/character-%s.glb"
const LETTERS := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o"]

var center := Vector3.ZERO
var floor_y := 0.0
var room_r := 5.0
var npc_scale := 0.3
var wall_h := 4.0

var _walkers: Array[Dictionary] = []
var _idlers: Array[Dictionary] = []
var _letters: Array = []
var bartender: Dictionary = {}   # the idler entry of the man behind the bar
const TARGET_HEIGHT_FRAC := 0.34


static func spawn(parent: Node, p_center: Vector3, p_floor_y: float, p_room_r: float, p_npc_scale: float, p_wall_h: float) -> Node3D:
	var crowd: Node3D = load("res://scripts/fx/room_crowd.gd").new()
	crowd.name = "RoomCrowd"
	crowd.center = p_center
	crowd.floor_y = p_floor_y
	crowd.room_r = p_room_r
	crowd.npc_scale = p_npc_scale
	crowd.wall_h = p_wall_h
	parent.add_child(crowd)
	crowd.populate()
	return crowd


## Model-space vertical extent of a CharacterActor's meshes → {lo, hi} (unscaled).
static func measure(actor: Node3D) -> Dictionary:
	var model: Node3D = actor.get("model")
	var lo := INF
	var hi := -INF
	if model == null:
		return {"lo": 0.0, "hi": 1.0}
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible:
			continue  # hidden emote props (zero-scale) would poison the bounds
		# Model-space transform via the parent chain (no global-transform inversion).
		var rel := mi.transform
		var up := mi.get_parent()
		var skip := false
		while up != null and up != model:
			var u3 := up as Node3D
			if u3 == null or not u3.visible:
				skip = true
				break
			rel = u3.transform * rel
			up = up.get_parent()
		if skip:
			continue
		var bb: AABB = rel * mi.get_aabb()
		lo = minf(lo, bb.position.y)
		hi = maxf(hi, bb.end.y)
	if lo == INF:
		return {"lo": 0.0, "hi": 1.0}
	return {"lo": lo, "hi": hi}


func populate() -> void:
	_letters = LETTERS.duplicate()
	_letters.shuffle()
	# Size everyone relative to the room (distant people must read clearly).
	var probe_h := npc_height()
	npc_scale *= (wall_h * TARGET_HEIGHT_FRAC) / probe_h
	var h := _build_bar()
	# Patrons leaning on the bar (backs to the table).
	var bar_a := TAU * 2.0 / 8.0
	var bar_dir := Vector3(sin(bar_a), 0, cos(bar_a))
	var bar_tan := Vector3(cos(bar_a), 0, -sin(bar_a))
	for k: float in [-1.0, 1.0]:
		var pos := center + bar_dir * room_r * 0.82 + bar_tan * room_r * 0.15 * k
		_add_idler(pos, bar_a, ["drink", "drink", "smoke", "emote-yes", "interact-right"], 5.0, 12.0)
	# Bartender behind the bar, facing the room.
	bartender = _add_idler(center + bar_dir * room_r * 0.965, bar_a + PI, ["interact-right", "interact-left", "emote-yes", "interact-right"], 3.0, 7.0)
	# Two conversational pairs near the far walls.
	for wall: int in [5, 7]:
		var a := TAU * float(wall) / 8.0
		var d := Vector3(sin(a), 0, cos(a))
		var t := Vector3(cos(a), 0, -sin(a))
		var mid := center + d * room_r * 0.78
		var half := h * 0.34
		var f1 := atan2(-t.x, -t.z)
		var f2 := atan2(t.x, t.z)
		_add_idler(mid + t * half, f1, ["emote-yes", "interact-right", "drink", "interact-left"], 3.0, 8.0)
		_add_idler(mid - t * half, f2, ["emote-yes", "interact-left", "smoke", "interact-right"], 3.0, 8.0)
	# Strollers circling the floor between the table and the walls.
	var radii := [0.68, 0.74, 0.71]
	for i in radii.size():
		_add_walker(room_r * radii[i], randf() * TAU, 1.0 if i % 2 == 0 else -1.0)


## Lend out the bartender (waits if he is already serving someone). Returns
## {actor, home, yaw} or {} if there is none.
func acquire_bartender() -> Dictionary:
	if bartender.is_empty() or not is_instance_valid(bartender.a):
		return {}
	while bool(bartender.busy):
		await get_tree().process_frame
		if bartender.is_empty() or not is_instance_valid(bartender.a):
			return {}
	bartender.busy = true
	return {"actor": bartender.a, "home": bartender.home, "yaw": bartender.yaw}


func release_bartender(actor: Node3D, home: Vector3, yaw: float) -> void:
	if actor != null and is_instance_valid(actor):
		actor.global_position = Vector3(home.x, actor.global_position.y, home.z)
		actor.rotation.y = yaw
		actor.call("_play", "idle", 0.2)
	if not bartender.is_empty():
		bartender.busy = false
		bartender.t = randf_range(2.0, 5.0)


func _new_actor() -> Node3D:
	var a: Node3D = CharacterActor.new()
	add_child(a)
	var letter: String = _letters.pop_back() if not _letters.is_empty() else LETTERS[randi() % LETTERS.size()]
	a.call("setup", GLB % letter, npc_scale, Color(0.8, 0.7, 0.55), -1)
	var rim: Node = a.get("_rim")
	if rim:
		rim.queue_free()
		a.set("_rim", null)
	var ap: AnimationPlayer = a.get("anim")
	if ap:
		for clip in ["walk", "holding-right"]:
			if ap.has_animation(clip):
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return a


## Height of a standing NPC in world units.
func npc_height() -> float:
	var probe := _new_actor()
	var m := measure(probe)
	var hgt: float = (float(m.hi) - float(m.lo)) * npc_scale
	probe.queue_free()
	return maxf(hgt, 0.1)


func _feet_y(actor: Node3D) -> float:
	var m := measure(actor)
	return floor_y - float(m.lo) * npc_scale


func _add_idler(pos: Vector3, yaw: float, kinds: Array, t_min: float, t_max: float) -> Dictionary:
	var a := _new_actor()
	a.position = Vector3(pos.x, _feet_y(a), pos.z)
	a.rotation.y = yaw
	var entry := {"a": a, "t": randf_range(1.0, t_max), "kinds": kinds, "tmin": t_min, "tmax": t_max, "busy": false, "home": a.global_position, "yaw": yaw}
	_idlers.append(entry)
	return entry


func _add_walker(r: float, ang: float, dir: float) -> void:
	var a := _new_actor()
	a.position.y = _feet_y(a)
	a.call("_play", "walk", 0.0)
	_walkers.append({"a": a, "r": r, "ang": ang, "dir": dir, "speed": npc_height() * 0.28,
			"walk_t": randf_range(6.0, 14.0), "wait": 0.0})


func _process(delta: float) -> void:
	for w in _walkers:
		var a: Node3D = w.a
		if not is_instance_valid(a):
			continue
		if float(w.wait) > 0.0:
			w.wait = float(w.wait) - delta
			if float(w.wait) <= 0.0:
				a.call("_play", "walk", 0.25)
			continue
		w.walk_t = float(w.walk_t) - delta
		w.ang = float(w.ang) + float(w.dir) * float(w.speed) * delta / float(w.r)
		var ang: float = w.ang
		a.position.x = center.x + sin(ang) * float(w.r)
		a.position.z = center.z + cos(ang) * float(w.r)
		var heading := Vector3(cos(ang), 0, -sin(ang)) * float(w.dir)
		a.rotation.y = lerp_angle(a.rotation.y, atan2(heading.x, heading.z), minf(delta * 6.0, 1.0))
		if float(w.walk_t) <= 0.0:
			# Stop for a moment, maybe grab a drink or a smoke.
			w.walk_t = randf_range(8.0, 16.0)
			w.wait = randf_range(3.0, 6.0)
			a.call("_play", "idle", 0.25)
			var roll := randf()
			if roll < 0.4:
				a.call("do_emote", &"drink")
			elif roll < 0.6:
				a.call("do_emote", &"smoke")
	for it in _idlers:
		var a: Node3D = it.a
		if not is_instance_valid(a) or bool(it.get("busy", false)):
			continue
		it.t = float(it.t) - delta
		if float(it.t) > 0.0:
			continue
		it.t = randf_range(float(it.tmin), float(it.tmax))
		var kind: String = it.kinds[randi() % it.kinds.size()]
		if kind == "drink":
			a.call("do_emote", &"drink")
		elif kind == "smoke":
			a.call("do_emote", &"smoke")
		else:
			a.call("_play", kind, 0.15)


## Bar counter + back shelf with bottles on wall #2. Returns the NPC height.
func _build_bar() -> float:
	var h := npc_height()
	var a := TAU * 2.0 / 8.0
	var d := Vector3(sin(a), 0, cos(a))
	var chord := 2.0 * room_r * sin(PI / 8.0)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.11, 0.06)
	wood.roughness = 0.5
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.62, 0.45, 0.2)
	brass.metallic = 0.85
	brass.roughness = 0.3

	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(chord * 0.6, h * 0.5, room_r * 0.06)
	bm.material = wood
	bar.mesh = bm
	add_child(bar)
	bar.position = center + d * room_r * 0.9 + Vector3(0, floor_y + h * 0.25, 0)
	bar.rotation.y = a

	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(chord * 0.62, h * 0.02, room_r * 0.075)
	tm.material = brass
	top.mesh = tm
	add_child(top)
	top.position = bar.position + Vector3(0, h * 0.26, 0)
	top.rotation.y = a

	# Back shelf with bottles.
	var shelf := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(chord * 0.6, h * 0.02, room_r * 0.03)
	sm.material = wood
	shelf.mesh = sm
	add_child(shelf)
	var shelf_pos := center + d * room_r * 0.985 + Vector3(0, floor_y + h * 0.78, 0)
	shelf.position = shelf_pos
	shelf.rotation.y = a
	var tang := Vector3(cos(a), 0, -sin(a))
	var cols := [Color(0.5, 0.25, 0.05), Color(0.1, 0.35, 0.15), Color(0.6, 0.55, 0.3), Color(0.35, 0.05, 0.08), Color(0.15, 0.25, 0.5)]
	for i in 9:
		var bottle := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = h * 0.035
		cm.height = h * (0.16 + 0.06 * float(i % 3))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cols[i % cols.size()]
		mat.roughness = 0.15
		mat.metallic = 0.2
		mat.emission_enabled = true
		mat.emission = cols[i % cols.size()]
		mat.emission_energy_multiplier = 0.35
		cm.material = mat
		bottle.mesh = cm
		add_child(bottle)
		bottle.position = shelf_pos + tang * (float(i) - 4.0) * chord * 0.06 + Vector3(0, cm.height * 0.5 + h * 0.01, 0)

	# A warm lamp over the bar so the corner reads as a place.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.68, 0.35)
	lamp.light_energy = 2.5
	lamp.omni_range = room_r * 0.6
	add_child(lamp)
	lamp.position = center + d * room_r * 0.85 + Vector3(0, floor_y + h * 1.15, 0)
	return h
