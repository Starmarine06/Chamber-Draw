extends Node3D

## Secret joke scene: a waiter walks up on your right with a silver tray, you
## turn your head, lean in, take the line, and snap back. The caller (game.gd)
## starts the "wired" screen effect when `on_taken` fires.

const CharacterActor := preload("res://scripts/character_actor.gd")
const RoomCrowd := preload("res://scripts/fx/room_crowd.gd")
const Sound := preload("res://scripts/sound.gd")
const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const TICKS_PER_LINE := 16
const HAND_SCALE := 0.06
const WAITER_GLB := "res://assets/imported_assets/kenney_blocky-characters_20/Models/GLB format/character-g.glb"

var cam: Camera3D
var floor_y := 0.0
var on_taken: Callable
var on_done: Callable
var _rest: Transform3D
var _fov0 := 75.0
var _near0 := 0.05
var _waiter: Node3D
var _tray: Node3D
var _line: MeshInstance3D
var _aborted := false
var _cancelled := false
var _snorting := false
var _progress := 0.0          # 0..1 along the line, driven by the scroll wheel
var _kick := 0.0              # tiny head dip per scroll tick
var _hcam := 1.0
var _line_holder: Node3D
var _line_len := 0.1
var _hand: Node3D
var _straw: MeshInstance3D
var _lean_pos := Vector3.ZERO
var _sleeve := Color(0.14, 0.12, 0.16)
var _seat_fwd := Vector3.ZERO   # seat -> table-centre direction (look-independent)
var _finished := false


static func start(parent: Node, camera: Camera3D, p_floor_y: float, taken: Callable, done: Callable, sleeve: Color = Color(0.14, 0.12, 0.16), seat_fwd: Vector3 = Vector3.ZERO) -> Node3D:
	var s: Node3D = load("res://scripts/fx/first_person_line.gd").new()
	s.name = "LineScene"
	s.cam = camera
	s.floor_y = p_floor_y
	s._seat_fwd = seat_fwd
	s.on_taken = taken
	s.on_done = done
	s._sleeve = sleeve
	parent.add_child(s)
	s._run()
	return s


func abort() -> void:
	_aborted = true
	_restore_camera()
	_finish()


## Scroll wheel tick: the straw travels along the line and the line disappears behind it.
func advance(ticks: int = 1) -> void:
	if not _snorting or _aborted:
		return
	_progress = minf(_progress + float(ticks) / float(TICKS_PER_LINE), 1.0)
	_kick = 1.0
	Sound.play(&"sniff", -9.0, randf_range(1.15, 1.45))
	_apply_progress()


## Walk away without taking it.
func cancel() -> void:
	if _snorting:
		_cancelled = true


func _apply_progress() -> void:
	if _line_holder == null:
		return
	_line_holder.position.x = -_line_len * 0.5 + _progress * _line_len
	_line_holder.scale.x = maxf(1.0 - _progress, 0.001)


func _straw_tip() -> Vector3:
	return _tray.to_global(Vector3(-_line_len * 0.5 + _progress * _line_len, _hcam * 0.02, 0.0))


func _process(delta: float) -> void:
	if not _snorting or _aborted or not is_instance_valid(cam) or _tray == null:
		return
	var tip := _straw_tip()
	# Hand comes in from the lower right of the view; the straw continues its arm.
	var b := cam.global_transform.basis
	var back := cam.global_position + b.x * _hcam * 0.28 - b.y * _hcam * 0.28
	var dir := (tip - back).normalized()
	if _hand != null:
		var hand_basis := Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3.ONE * _hcam * HAND_SCALE)
		var len_s := _hcam * HAND_SCALE * 0.7
		_hand.global_transform = Transform3D(hand_basis, tip - dir * len_s)
	# The head follows the straw along the line and dips a little on every pull.
	_kick = maxf(_kick - delta * 5.0, 0.0)
	var want := Transform3D(Basis.looking_at((tip - _lean_pos).normalized(), Vector3.UP), _lean_pos)
	want.basis = want.basis * Basis(Vector3.RIGHT, -_kick * 0.025)
	cam.global_transform = cam.global_transform.interpolate_with(want, minf(delta * 7.0, 1.0))


func _restore_camera() -> void:
	if is_instance_valid(cam):
		cam.global_transform = _rest
		cam.fov = _fov0
		cam.near = _near0


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(cam):
		cam.near = _near0
	if is_instance_valid(_waiter):
		_waiter.queue_free()
	if is_instance_valid(_tray):
		_tray.queue_free()
	if on_done.is_valid():
		on_done.call()
	queue_free()


func _set_cam(t: float, a: Transform3D, b: Transform3D, fa: float, fb: float) -> void:
	if is_instance_valid(cam):
		cam.global_transform = a.interpolate_with(b, t)
		cam.fov = lerpf(fa, fb, t)


func _tween_cam(a: Transform3D, b: Transform3D, fa: float, fb: float, dur: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> Tween:
	var tw := create_tween()
	tw.tween_method(_set_cam.bind(a, b, fa, fb), 0.0, 1.0, dur).set_trans(trans).set_ease(ease_type)
	return tw


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	if cam == null or not is_instance_valid(cam):
		_finish()
		return
	_rest = cam.global_transform
	_fov0 = cam.fov
	_near0 = cam.near
	cam.near = minf(cam.near, 0.004)   # the head ends up right above the tray
	var hcam := maxf(cam.global_position.y - floor_y, 0.5)
	var fwd := -_rest.basis.z
	if _seat_fwd != Vector3.ZERO:
		fwd = _seat_fwd   # anchored to the seat, not to where the head happens to point
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.rotated(Vector3.UP, -deg_to_rad(70.0))

	# Tray point: to the player's right, below eye level.
	var tray_p := cam.global_position + right * hcam * 0.55
	tray_p.y = floor_y + hcam * 0.58
	_build_tray(tray_p, hcam, right)

	# Waiter (giant-scale like the seat characters), standing behind the tray.
	_waiter = CharacterActor.new()
	add_child(_waiter)
	_waiter.call("setup", WAITER_GLB, 1.0, Color(0.9, 0.9, 0.9), -1)
	var rim: Node = _waiter.get("_rim")
	if rim:
		rim.queue_free()
		_waiter.set("_rim", null)
	var m := RoomCrowd.measure(_waiter)
	var k := (hcam * 1.02) / maxf(float(m.hi) - float(m.lo), 0.01)
	_waiter.scale = Vector3.ONE * k
	_waiter.set("_base_scale", k)
	var ap: AnimationPlayer = _waiter.get("anim")
	if ap:
		for clip in ["walk", "holding-right"]:
			if ap.has_animation(clip):
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var stand := tray_p + right * hcam * 0.3
	var feet := floor_y - float(m.lo) * k
	var face := atan2(-right.x, -right.z)
	var start_pos := stand + right * hcam * 1.6
	_waiter.position = Vector3(start_pos.x, feet, start_pos.z)
	_waiter.rotation.y = face
	_waiter.call("_play", "walk", 0.0)

	# 1) Waiter walks in.
	var walk_in := create_tween()
	walk_in.tween_property(_waiter, "position", Vector3(stand.x, feet, stand.z), 1.5).set_trans(Tween.TRANS_SINE)
	await walk_in.finished
	if _aborted:
		return
	_waiter.call("_play", "holding-right", 0.2)
	await _wait(0.25)
	if _aborted:
		return

	# 2) Turn your head to the right and down at the tray.
	var look := Transform3D(Basis.looking_at((tray_p - cam.global_position).normalized(), Vector3.UP), cam.global_position)
	var turn := _tween_cam(_rest, look, _fov0, _fov0, 0.95, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	await turn.finished
	if _aborted:
		return
	await _wait(0.5)
	if _aborted:
		return

	# 3) Lean in over the line.
	# Drop the head right over the tray: the view pitches steeply DOWN at the line.
	var lean_pos := cam.global_position.lerp(tray_p + Vector3(0, hcam * 0.15, 0), 0.8)
	var lean_xf := Transform3D(Basis.looking_at((tray_p - lean_pos).normalized(), Vector3.UP), lean_pos)
	var lean := _tween_cam(look, lean_xf, _fov0, _fov0, 0.55, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	await lean.finished
	if _aborted:
		return

	# 4) Hand + straw: scroll to run the straw along the line.
	_lean_pos = lean_pos
	_spawn_hand()
	_snorting = true
	while _progress < 1.0 and not _cancelled and not _aborted:
		await get_tree().process_frame
	_snorting = false
	if _aborted:
		return
	if _cancelled:
		# Changed your mind: straighten up, the waiter shrugs off.
		if is_instance_valid(_hand):
			_hand.queue_free()
		var back_off := _tween_cam(cam.global_transform, _rest, _fov0, _fov0, 0.9, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
		if is_instance_valid(_waiter):
			_waiter.call("_play", "walk", 0.2)
			_waiter.rotation.y = atan2(right.x, right.z)
			create_tween().tween_property(_waiter, "position", Vector3(start_pos.x, feet, start_pos.z), 1.5)
		await back_off.finished
		_restore_camera()
		_finish()
		return
	Sound.play(&"sniff")
	await _wait(0.25)
	if is_instance_valid(_hand):
		_hand.queue_free()
	if _aborted:
		return
	lean_xf = cam.global_transform

	# 5) Head snaps back, everything goes bright and fast.
	var snap_xf := Transform3D(Basis.looking_at(((tray_p - lean_pos).normalized() + Vector3(0, 0.75, 0)).normalized(), Vector3.UP), lean_pos + Vector3(0, hcam * 0.05, 0))
	var snap := _tween_cam(lean_xf, snap_xf, _fov0, _fov0 + 10.0, 0.16, Tween.TRANS_BACK, Tween.EASE_OUT)
	await snap.finished
	if on_taken.is_valid():
		on_taken.call()
	if is_instance_valid(_waiter):
		_waiter.call("_play", "emote-yes", 0.1)
	await _wait(0.6)
	if _aborted:
		return

	# 6) Settle back to the seat while the waiter strolls off.
	var back := _tween_cam(snap_xf, _rest, _fov0 + 10.0, _fov0, 1.1, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	if is_instance_valid(_waiter):
		_waiter.call("_play", "walk", 0.2)
		_waiter.rotation.y = atan2(right.x, right.z)
		var leave := create_tween()
		leave.tween_property(_waiter, "position", Vector3(start_pos.x, feet, start_pos.z), 1.6).set_trans(Tween.TRANS_SINE)
	await back.finished
	if _aborted:
		return
	_restore_camera()
	_finish()


func _spawn_hand() -> void:
	_hand = EmoteRig.build_fist(Color(0.93, 0.76, 0.62), _sleeve)
	_hand.scale = Vector3.ONE * _hcam * HAND_SCALE
	add_child(_hand)
	# Rolled note used as a straw, continuing the arm past the fist.
	_straw = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.62, 0.42)
	mat.roughness = 0.6
	cm.material = mat
	_straw.mesh = cm
	_straw.position = Vector3(0, 0.35, 0)
	_hand.add_child(_straw)
	_apply_progress()


## Silver tray with a mirror, one white line and a rolled note.
func _build_tray(pos: Vector3, hcam: float, right: Vector3) -> void:
	_tray = Node3D.new()
	add_child(_tray)
	_tray.position = pos
	_tray.rotation.y = atan2(right.x, right.z)

	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.75, 0.77, 0.8)
	silver.metallic = 0.9
	silver.roughness = 0.25
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(hcam * 0.34, hcam * 0.012, hcam * 0.24)
	bm.material = silver
	base.mesh = bm
	_tray.add_child(base)

	var mirror := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(hcam * 0.26, hcam * 0.004, hcam * 0.15)
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.05, 0.06, 0.08)
	mmat.metallic = 1.0
	mmat.roughness = 0.05
	mm.material = mmat
	mirror.mesh = mm
	mirror.position = Vector3(0, hcam * 0.008, 0)
	_tray.add_child(mirror)

	_hcam = hcam
	_line_len = hcam * 0.18
	_line_holder = Node3D.new()
	_line_holder.position = Vector3(-_line_len * 0.5, hcam * 0.012, 0)
	_tray.add_child(_line_holder)
	_line = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(_line_len, hcam * 0.003, hcam * 0.012)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.97, 0.97, 1.0)
	lmat.emission_enabled = true
	lmat.emission = Color(0.9, 0.92, 1.0)
	lmat.emission_energy_multiplier = 0.6
	lm.material = lmat
	_line.mesh = lm
	_line.position = Vector3(_line_len * 0.5, 0, 0)
	_line_holder.add_child(_line)

	var note := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = hcam * 0.006
	cm.bottom_radius = hcam * 0.006
	cm.height = hcam * 0.07
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.35, 0.55, 0.38)
	cm.material = nmat
	note.mesh = cm
	note.position = Vector3(hcam * 0.11, hcam * 0.014, hcam * 0.05)
	note.rotation = Vector3(0, 0, PI / 2.0)
	_tray.add_child(note)

	# A small spotlight so the tray reads clearly.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = 1.2
	light.omni_range = hcam * 0.8
	light.position = Vector3(0, hcam * 0.25, 0)
	_tray.add_child(light)
