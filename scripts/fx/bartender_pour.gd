extends RefCounted

## The bartender pours a drink into a glass that stands on the table at someone's seat.
## Used by the local player's drink session AND by everyone else's screen when a remote
## player orders a drink, so the scene is identical for all players.
##
## The bartender is the REAL bartender from the room (RoomCrowd): he leaves his post
## behind the bar, walks across the floor (around the table, never through it) to a spot
## beside the seat, OUTSIDE the table rim, pours, and walks back to the bar.
##
## ctx: {
##   host: Node              (for tweens / timers)
##   world: Node3D           (where the bottle + stream are added)
##   glass: Node3D           (upright on the table; "liquid" meta = fill pivot)
##   center: Vector3         (table centre)
##   seat_pos: Vector3       (the seat's marker position)
##   floor_y: float
##   crowd: Node             (RoomCrowd, may be null)
##   drink: Dictionary       (ViceCatalog drink product)
##   level_cb: Callable      (float) -> void, fill level 0..1
##   level_from: float
##   poured: Callable        (optional) called the moment the pour ends (before he walks off)
## }

const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const Juice := preload("res://scripts/fx/juice.gd")
const Sound := preload("res://scripts/sound.gd")
const RoomCrowd := preload("res://scripts/fx/room_crowd.gd")
const GhostWaiter := preload("res://scripts/fx/ghost_waiter.gd")
const GHOST_SCALE := 0.4
const GHOST_SPEED := 1.1       # world units per second
const HOVER := 0.12            # how far off the floor he floats


static func make_bottle(drink: Dictionary) -> Node3D:
	var bottle := Node3D.new()
	var bcol: Color = drink.get("bottle", Color(0.12, 0.22, 0.14))
	var glass_mat := EmoteRig._mat(bcol, 0.0, 0.1, 0.85)
	var body := EmoteRig._cyl(0.1, 0.36, glass_mat)
	body.position = Vector3(0, 0.18, 0)
	bottle.add_child(body)
	var shoulder := EmoteRig._cyl(0.04, 0.08, glass_mat, 0.1)
	shoulder.rotation_degrees = Vector3(180, 0, 0)
	shoulder.position = Vector3(0, 0.4, 0)
	bottle.add_child(shoulder)
	var neck := EmoteRig._cyl(0.035, 0.14, glass_mat)
	neck.position = Vector3(0, 0.51, 0)
	bottle.add_child(neck)
	var label := EmoteRig._cyl(0.102, 0.12, EmoteRig._mat(Color(0.93, 0.88, 0.74), 0.0, 0.7))
	label.position = Vector3(0, 0.17, 0)
	bottle.add_child(label)
	var band := EmoteRig._cyl(0.103, 0.025, EmoteRig._mat(Color(0.79, 0.64, 0.36), 0.2, 0.3))
	band.position = Vector3(0, 0.24, 0)
	bottle.add_child(band)
	return bottle


## Walks `actor` along world-space points (y is left untouched). Awaitable.
static func _walk(host: Node, actor: Node3D, points: Array, speed: float) -> void:
	for p: Vector3 in points:
		if not is_instance_valid(actor):
			return
		var from := actor.global_position
		var to := Vector3(p.x, from.y, p.z)
		var dist := from.distance_to(to)
		if dist < 0.01:
			continue
		actor.rotation.y = atan2(to.x - from.x, to.z - from.z)
		var tw := host.create_tween()
		tw.tween_property(actor, "global_position", to, dist / speed)
		await tw.finished


## Remote players' pours: slide their glass to the pour spot, pour, slide it back.
static func run(ctx: Dictionary) -> void:
	var glass: Node3D = ctx.glass
	if not is_instance_valid(glass):
		return
	var home_pos := glass.global_position
	var plan: Dictionary = await prepare(ctx)
	if plan.is_empty() or not is_instance_valid(glass):
		return
	var slide := (ctx.host as Node).create_tween()
	slide.tween_property(glass, "global_position", plan.pour_spot, 0.4).set_trans(Tween.TRANS_SINE)
	await slide.finished
	await perform(ctx, plan)
	if is_instance_valid(glass):
		var back := (ctx.host as Node).create_tween()
		back.tween_property(glass, "global_position", home_pos, 0.4).set_trans(Tween.TRANS_SINE)


## Step 1: get the bartender (from his post at the bar) and work out WHERE everything
## goes so that his real arm reaches the bottle over the glass while he stands OUTSIDE the
## table rim. Returns the plan (pour_spot = where the glass must stand).
static func prepare(ctx: Dictionary) -> Dictionary:
	var host: Node = ctx.host
	var world: Node3D = ctx.world
	var glass: Node3D = ctx.glass
	var center: Vector3 = ctx.center
	var seat_pos: Vector3 = ctx.seat_pos
	var floor_y: float = ctx.floor_y
	var crowd: Node = ctx.get("crowd", null)
	var table_y: float = float(ctx.get("table_y", glass.global_position.y))
	var table_r: float = float(ctx.get("table_r", Vector2(seat_pos.x - center.x, seat_pos.z - center.z).length() * 1.0))

	# A procedural ghost serves the drinks. He appears at the bar and floats over.
	var bar_pos := Vector3(seat_pos.x - center.x, 0.0, seat_pos.z - center.z).normalized() * table_r * 2.6 + Vector3(center.x, 0.0, center.z)
	var home_yaw := 0.0
	if crowd != null and "bartender" in crowd and not (crowd.bartender as Dictionary).is_empty():
		bar_pos = (crowd.bartender as Dictionary).home
	var borrowed := false
	var home := Vector3(bar_pos.x, floor_y + HOVER, bar_pos.z)
	var actor: Node3D = GhostWaiter.new()
	world.add_child(actor)
	actor.scale = Vector3.ONE * GHOST_SCALE
	actor.global_position = home
	var feet_y := actor.global_position.y

	# His arm (see ghost_waiter.gd): pivot at the shoulder, 0.85 local units long.
	var arm: Node3D = (actor as Object).get("arm")
	var sh_local: Vector3 = GhostWaiter.SHOULDER
	var arm_len: float = GhostWaiter.ARM_LEN * GHOST_SCALE
	var sc := GHOST_SCALE

	# Glass / bottle geometry.
	var gs: float = glass.global_basis.get_scale().x
	var bottle_s: float = gs * 0.83
	var glass_top_y := table_y + 0.27 * gs
	var grip_y := glass_top_y + 0.1 * bottle_s + 0.38 * 0.47 * bottle_s   # see pour_basis below
	var sh_y := feet_y + sh_local.y * sc
	var dy := sh_y - grip_y
	var h := sqrt(maxf(arm_len * arm_len - dy * dy, 0.0025))
	# Along the rim, to the right of the seat (from the seated player's view).
	var seat_ang := atan2(seat_pos.x - center.x, seat_pos.z - center.z)
	var ang := seat_ang + 0.5
	var rad := Vector3(sin(ang), 0.0, cos(ang))           # centre -> outside
	var r_sh := table_r + 0.2
	var shoulder := Vector3(center.x, sh_y, center.z) + rad * r_sh
	var glass_xz := Vector3(center.x, 0.0, center.z) + rad * (r_sh - h - 0.335 * bottle_s)
	var pour_spot := Vector3(glass_xz.x, table_y, glass_xz.z)
	var yaw := atan2(-rad.x, -rad.z)                        # facing the glass
	var stand := shoulder - Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc) * sh_local
	stand.y = feet_y

	# Path: bar -> in to a ring around the table -> along the ring -> the stand point.
	var ring_r := table_r * 1.6
	var a0 := atan2(home.x - center.x, home.z - center.z)
	var a1 := atan2(stand.x - center.x, stand.z - center.z)
	var da := wrapf(a1 - a0, -PI, PI)
	var steps := maxi(int(absf(da) / deg_to_rad(22.0)), 1)
	var path: Array = []
	for i in range(steps + 1):
		var aa := a0 + da * float(i) / float(steps)
		path.append(Vector3(center.x + sin(aa) * ring_r, feet_y, center.z + cos(aa) * ring_r))
	path.append(stand)

	return {
		"actor": actor, "borrowed": borrowed, "home": home, "home_yaw": home_yaw, "arm": arm,
		"arm_len": arm_len, "shoulder": shoulder, "pour_spot": pour_spot, "yaw": yaw, "stand": stand,
		"path": path, "feet_y": feet_y, "speed": GHOST_SPEED, "rad": rad,
		"bottle_s": bottle_s, "glass_top_y": glass_top_y,
	}


## Step 2: walk to the stand point, hold the bottle in his (IK-driven) hand, pour, walk back.
static func perform(ctx: Dictionary, plan: Dictionary) -> void:
	var host: Node = ctx.host
	var world: Node3D = ctx.world
	var glass: Node3D = ctx.glass
	var crowd: Node = ctx.get("crowd", null)
	var drink: Dictionary = ctx.get("drink", {})
	var level_cb: Callable = ctx.get("level_cb", Callable())
	var level_from: float = float(ctx.get("level_from", 0.0))
	var actor: Node3D = plan.actor
	var arm: Node3D = plan.arm
	var path: Array = plan.path
	var feet_y: float = plan.feet_y
	var home: Vector3 = plan.home
	var bottle_s: float = plan.bottle_s
	var arm_len: float = plan.arm_len
	var shoulder: Vector3 = plan.shoulder
	var rad: Vector3 = plan.rad

	actor.call("fade_to", 1.0, 0.8)
	await _walk(host, actor, path, plan.speed)
	if not is_instance_valid(actor) or not is_instance_valid(glass):
		_finish(crowd, actor, plan.borrowed, home, plan.home_yaw)
		return
	var turn := host.create_tween()
	turn.tween_property(actor, "rotation:y", plan.yaw, 0.3)
	await turn.finished
	await host.get_tree().create_timer(0.2).timeout
	var ap: AnimationPlayer = null

	# Bottle in his hand.
	var frame := Basis(rad, Vector3.UP, rad.cross(Vector3.UP).normalized())
	var glass_top := Vector3(glass.global_position.x, plan.glass_top_y, glass.global_position.z)
	var pour_basis := (frame * Basis(Vector3(0, 0, 1), deg_to_rad(118.0))).scaled(Vector3.ONE * bottle_s)
	var grip_pour := glass_top + Vector3.UP * 0.1 * bottle_s - pour_basis * Vector3(0.0, 0.58 - 0.2, 0.0)
	var dir_pour := (grip_pour - shoulder).normalized()
	var dir_rest := (Vector3.DOWN * 0.8 - rad * 0.6).normalized()
	var bottle := make_bottle(drink)
	bottle.scale = Vector3.ONE * bottle_s
	world.add_child(bottle)
	var apply := func(t: float) -> void:
		if not is_instance_valid(bottle) or not is_instance_valid(actor):
			return
		var dir := dir_rest.slerp(dir_pour, t).normalized()
		if arm != null:
			var pb := (arm.get_parent() as Node3D).global_basis.orthonormalized()
			arm.quaternion = Quaternion(Vector3.DOWN, pb.inverse() * dir)
		var grip := shoulder + dir * arm_len
		var bb := (frame * Basis(Vector3(0, 0, 1), deg_to_rad(lerpf(20.0, 118.0, t)))).scaled(Vector3.ONE * bottle_s)
		bottle.global_transform = Transform3D(bb, grip - bb * Vector3(0.0, 0.2, 0.0))
	apply.call(0.0)

	var stream_col: Color = drink.get("color", Color(0.85, 0.45, 0.08))
	var stream := EmoteRig._cyl(0.012 * bottle_s, 1.0, EmoteRig._mat(stream_col, 0.6, 0.2, 0.9))
	stream.visible = false
	world.add_child(stream)
	var neck_tip := grip_pour + pour_basis * Vector3(0.0, 0.38, 0.0)
	stream.global_position = (neck_tip + glass_top) * 0.5
	stream.scale = Vector3(1.0, maxf(neck_tip.distance_to(glass_top), 0.001), 1.0)

	var tw := host.create_tween()
	tw.tween_method(apply, 0.0, 1.0, Juice.d(0.9)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		stream.visible = true
		Sound.play(&"pour")
		Sound.play(&"ice", -6.0))
	tw.tween_method(func(v: float) -> void:
		if level_cb.is_valid():
			level_cb.call(v)
	, level_from, 0.9, Juice.d(1.5)).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: stream.visible = false)
	tw.tween_method(apply, 1.0, 0.0, Juice.d(0.6)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(bottle):
		bottle.queue_free()
	if is_instance_valid(stream):
		stream.queue_free()
	if ctx.has("poured") and (ctx.poured as Callable).is_valid():
		(ctx.poured as Callable).call()

	# Back to the bar the way he came.
	if is_instance_valid(actor):
		var back: Array = path.duplicate()
		back.reverse()
		back.append(Vector3(home.x, feet_y, home.z))
		await _walk(host, actor, back, plan.speed)
	_finish(crowd, actor, plan.borrowed, home, plan.home_yaw)


static func _finish(_crowd: Node, actor: Node3D, _borrowed: bool, _home: Vector3, _home_yaw: float) -> void:
	if actor != null and is_instance_valid(actor):
		var tw := actor.create_tween()
		tw.tween_method(func(a: float) -> void: actor.call("set_alpha", a), 1.0, 0.0, 0.6)
		tw.tween_callback(actor.queue_free)
