extends Node3D

## One opponent avatar at the table: wraps a Kenney blocky-character GLB and
## drives its built-in AnimationPlayer clips (idle / interact / emote-yes /
## emote-no / die) with crossfades, adds a soft seat-colored rim light, and
## floats Kenney emote bubbles above the head.

const EMOTE_DIR := "res://assets/imported_assets/kenney_emotes-pack/PNG/Vector/Style 1/"
const EmoteRig := preload("res://scripts/fx/emote_rig.gd")
const Juice := preload("res://scripts/fx/juice.gd")
const BLEND := 0.2

var seat: int = -1
var model: Node3D
var anim: AnimationPlayer
var dead := false
var removing := false   ## die_and_remove() is running (fade-out under way)
var _is_turn := false
var _bubble: Sprite3D
var _bubble_tw: Tween
var _rim: OmniLight3D
var _base_scale: float = 1.0
# Vice emotes (smoke / drink): props live on the rig, hidden until used.
var _head: Node3D
var _cig: Node3D
var _glass: Node3D
var _emote_busy := false
var _cig_tw: Tween
# Head look: the player's mouse-look direction (yaw/pitch relative to the seat's
# facing) is applied on top of whatever the animation does to the head.
var glance := false                 ## offline AI: idle random glances when nobody drives the head
var _look_target := Vector2.ZERO    ## (yaw, pitch) degrees
var _look_cur := Vector2.ZERO
var _last_look_ms := 0
var _next_glance := 0.0
var _head_rest := Basis.IDENTITY
var _head_applied := Basis.IDENTITY

func setup(glb_path: String, char_scale: float, seat_color: Color, seat_index: int) -> void:
	seat = seat_index
	_base_scale = char_scale
	scale = Vector3.ONE * char_scale
	var res := load(glb_path) as PackedScene
	if res == null:
		return
	model = res.instantiate() as Node3D
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for loop_name in ["idle", "sit", "static"]:
			if anim.has_animation(loop_name):
				anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
		anim.animation_finished.connect(_on_anim_finished)
		anim.mixer_updated.connect(_apply_head_look)
		_play("idle", 0.0)
		# De-sync idles so the table doesn't breathe in unison.
		if anim.has_animation("idle"):
			anim.seek(randf() * anim.get_animation("idle").length, true)
		anim.speed_scale = randf_range(0.85, 1.1)
		EmoteRig.install_clips(anim)
	_head = model.find_child("head", true, false) as Node3D
	var arm := model.find_child("arm-right", true, false) as Node3D
	if _head:
		_head_rest = _head.basis
		_head_applied = _head.basis
		_cig = EmoteRig.make_cigarette(_head, Juice.soft_texture(), randf() < 0.35)  # some bots smoke cigars
		_cig.visible = false
	if arm:
		_glass = EmoteRig.make_glass(arm)
		_glass.visible = false

	_rim = OmniLight3D.new()
	_rim.light_color = seat_color.lightened(0.2)
	_rim.light_energy = 0.45
	_rim.omni_range = 1.5
	_rim.omni_attenuation = 1.6
	_rim.position = Vector3(0, 1.2, -0.9)  # behind + above: back-light rim
	_rim.shadow_enabled = false
	add_child(_rim)

## Sets where the head looks: yaw (+ = turn left, like the camera) and pitch
## (+ = look up), in degrees relative to the seat's facing direction.
func set_look(yaw_deg: float, pitch_deg: float) -> void:
	_look_target = Vector2(clampf(yaw_deg, -75.0, 75.0), clampf(pitch_deg, -35.0, 40.0))
	_last_look_ms = Time.get_ticks_msec()

func _process(delta: float) -> void:
	if glance and Time.get_ticks_msec() - _last_look_ms > 2500:
		_next_glance -= delta
		if _next_glance <= 0.0:
			_next_glance = randf_range(1.8, 5.0)
			_look_target = Vector2(randf_range(-35.0, 35.0), randf_range(-8.0, 10.0))
	_look_cur = _look_cur.lerp(_look_target, 1.0 - exp(-delta * 9.0))

## Runs right after the AnimationPlayer has written the pose for this frame.
func _apply_head_look() -> void:
	if _head == null or dead:
		return
	var base: Basis = _head.basis
	if base.is_equal_approx(_head_applied):
		base = _head_rest  # the clip did not key the head this frame
	# Head yaw follows the camera's world yaw; head pitch is inverted (the model
	# faces +Z, the camera looks down -Z).
	var rot := Basis.from_euler(Vector3(deg_to_rad(-_look_cur.y * 0.9), deg_to_rad(_look_cur.x * 0.9), 0.0))
	_head_applied = base * rot
	_head.basis = _head_applied

func _play(clip: String, blend: float = BLEND) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	anim.play(clip, blend)

func _on_anim_finished(clip: StringName) -> void:
	if dead or _aiming:
		return
	if clip != &"idle":
		_play("idle")

## Turn indicator: a quick hop + brighter rim when this seat becomes active.
func set_turn(on: bool) -> void:
	if on == _is_turn:
		return
	_is_turn = on
	if _rim:
		var tw := create_tween()
		tw.tween_property(_rim, "light_energy", 1.2 if on else 0.45, 0.3)
	if on and not dead:
		var s := _base_scale
		var pop := create_tween()
		pop.tween_property(self, "scale", Vector3(s * 1.1, s * 1.1, s * 1.1), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(self, "scale", Vector3.ONE * s, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_play("interact-right")

## kind: &"play", &"hit", &"nervous", &"relief", &"win", &"die", &"respawn"
func react(kind: StringName) -> void:
	if dead and kind != &"respawn":
		return
	match kind:
		&"play":
			_play("interact-right" if randf() < 0.5 else "interact-left", 0.1)
			_squash()
		&"hit":
			_play("emote-no")
			emote("emote_anger")
			_squash()
		&"nervous":
			emote("emote_drops", 3.0)
			do_emote(&"smoke")
		&"relief":
			_play("emote-yes")
			emote("emote_faceHappy")
			get_tree().create_timer(1.2).timeout.connect(func() -> void:
				if is_instance_valid(self):
					do_emote(&"drink"))
		&"fear":
			# Gun pointed at us: wide-eyed sweat + a nervous tremble.
			_play("emote-no", 0.15)
			emote("emote_drops", 4.0)
			_tremble(2.2)
		&"win":
			_play("emote-yes")
			emote("emote_stars")
		&"die":
			dead = true
			if anim:
				anim.speed_scale = 1.0
			_play("die", 0.1)
			emote("emote_cross", 2.4)
		&"respawn":
			dead = false
			_play("idle", 0.0)
			scale = Vector3.ZERO
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector3.ONE * _base_scale, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			emote("emote_heart")

func _squash() -> void:
	var s := _base_scale
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(s * 1.08, s * 0.93, s * 1.08), 0.08)
	tw.tween_property(self, "scale", Vector3.ONE * s, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Pops a Kenney emote bubble above the head for `hold` seconds.
func emote(icon: String, hold: float = 1.6) -> void:
	var path := EMOTE_DIR + icon + ".png"
	if not ResourceLoader.exists(path):
		return
	if _bubble == null:
		_bubble = Sprite3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.no_depth_test = true
		_bubble.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		_bubble.pixel_size = 0.028
		_bubble.position = Vector3(-0.85, 2.25, 0.3)  # beside the head (stays in frame up close)
		_bubble.render_priority = 5
		add_child(_bubble)
	_bubble.texture = load(path)
	if _bubble_tw and _bubble_tw.is_valid():
		_bubble_tw.kill()
	_bubble.visible = true
	_bubble.scale = Vector3.ZERO
	_bubble.modulate.a = 1.0
	_bubble_tw = create_tween()
	_bubble_tw.tween_property(_bubble, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tw.tween_interval(hold)
	_bubble_tw.tween_property(_bubble, "modulate:a", 0.0, 0.3)
	_bubble_tw.tween_callback(func() -> void: _bubble.visible = false)

## Shaky little side-to-side jitter (fear). Restores the resting position.
func _tremble(seconds: float) -> void:
	var home := position
	var amp := _base_scale * 0.025
	var side := global_transform.basis.x.normalized()
	var step := func(t: float) -> void:
		if not is_instance_valid(self) or dead:
			return
		position = home + side * sin(t * seconds * 55.0) * amp * (1.0 - t)
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, seconds)
	tw.tween_callback(func() -> void:
		if is_instance_valid(self) and not dead:
			position = home)

# ── Revolver duel ─────────────────────────────────────────────────────

var _aiming := false
var _yaw_home := 0.0

## Turns to face `world_target` and thrusts the right arm straight out using the
## model's own "holding-right" pose (the arm holds its last frame while aiming).
func aim_at(world_target: Vector3, turn_time: float = 0.35) -> void:
	if dead or anim == null:
		return
	_aiming = true
	_emote_busy = true
	_yaw_home = rotation.y
	var d := world_target - global_position
	var yaw := atan2(d.x, d.z)
	var goal := rotation.y + wrapf(yaw - rotation.y, -PI, PI)
	create_tween().tween_property(self, "rotation:y", goal, turn_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	anim.speed_scale = 1.0
	_play("holding-right", 0.2)

## World position of the right fist (follows the animated arm, recoil included).
func aim_hand_pos() -> Vector3:
	var arm := _aim_arm()
	if arm == null:
		return global_position + global_transform.basis * Vector3(-0.6, 1.8, 0.8) * _base_scale
	return arm.to_global(Vector3(-0.2, -0.9, 0.0))

func _aim_arm() -> Node3D:
	if model == null:
		return null
	return model.find_child("arm-right", true, false) as Node3D

## The gun goes off: the model's own shoot clip kicks the arm up, body squashes.
func aim_recoil() -> void:
	if dead:
		return
	_play("holding-right-shoot", 0.0)
	_squash()

## Lowers the arm, turns back to the seat's original facing, resumes idle.
func aim_release(turn_time: float = 0.4) -> void:
	if not _aiming:
		return
	_aiming = false
	if not dead:
		var back := rotation.y + wrapf(_yaw_home - rotation.y, -PI, PI)
		create_tween().tween_property(self, "rotation:y", back, turn_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_play("idle", 0.3)
	_emote_busy = false

## Shoved along `dir_world` by `dist` (world units) — the bullet's punch.
func knockback(dir_world: Vector3, dist: float, dur: float = 0.18) -> void:
	var d := dir_world
	d.y = 0.0
	if d.length() < 0.001:
		return
	create_tween().tween_property(self, "position", position + d.normalized() * dist, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

var _slumped := false

## Passed out drunk: the avatar folds forward over the table until they wake.
func set_passed_out(on: bool) -> void:
	if on == _slumped or model == null or dead:
		return
	_slumped = on
	var tw := create_tween().set_parallel()
	tw.tween_property(model, "rotation_degrees:x", 62.0 if on else 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN_OUT)
	tw.tween_property(model, "position:y", -0.25 if on else 0.0, 0.9).set_trans(Tween.TRANS_SINE)

## Plays the fall and fades the avatar out; `on_done` fires when it's gone.
func die_and_remove(on_done: Callable = Callable()) -> void:
	if removing:
		return
	removing = true
	react(&"die")
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(self, "scale", Vector3(_base_scale, 0.0, _base_scale), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if on_done.is_valid():
			on_done.call()
		queue_free())

# ── Vice emotes ───────────────────────────────────────────────────────

func is_emote_busy() -> bool:
	return _emote_busy

## kind: &"smoke" (cigarette drag + exhale) or &"drink" (whiskey sip).
## Returns false if the character can't emote right now.
func do_emote(kind: StringName) -> bool:
	if dead or _emote_busy or anim == null:
		return false
	var clip := "%s/%s" % [EmoteRig.LIB, kind]
	if not anim.has_animation(clip):
		return false
	_emote_busy = true
	anim.speed_scale = 1.0
	anim.play(clip, 0.25)
	match kind:
		&"smoke": _run_smoke()
		&"drink": _run_drink()
	return true

## Re-dress the mouth cigarette for a catalogue product (cigarette brand / cigar).
func set_smoke_style(prod: Dictionary) -> void:
	if _head == null or _emote_busy:
		return
	if _cig != null and is_instance_valid(_cig):
		_cig.queue_free()
	var is_cigar := str(prod.get("kind", "cigarette")) == "cigar"
	_cig = EmoteRig.make_cigarette(_head, Juice.soft_texture(), is_cigar)
	_cig.visible = false
	var paper: Color = prod.get("wrapper", prod.get("paper", Color(0.95, 0.94, 0.9)))
	var filt: Color = prod.get("filter", paper.darkened(0.15))
	EmoteRig.style_cigarette(_cig, paper, filt)

## Re-dress the glass for a catalogue drink (tumbler / shot / martini / mug / wine ...).
func set_drink_style(prod: Dictionary) -> void:
	if _emote_busy:
		return
	var arm := model.find_child("arm-right", true, false) as Node3D if model else null
	if arm == null:
		return
	if _glass != null and is_instance_valid(_glass):
		_glass.queue_free()
	var g: Node3D = preload("res://scripts/fx/glassware.gd").build(str(prod.get("glass", "tumbler")), prod.get("color", Color(0.85, 0.45, 0.08)))
	g.name = "Glass"
	g.position = Vector3(-0.2, -1.0, 0.24)
	g.set_meta(&"full_scale", EmoteRig.GLASS_SCALE)
	arm.add_child(g)
	g.visible = false
	_glass = g

func _run_smoke() -> void:
	if _cig == null:
		_emote_busy = false
		return
	var ember: StandardMaterial3D = _cig.get_meta(&"ember_mat")
	var tip := _cig.find_child("TipLight", true, false) as OmniLight3D
	var wisps := _cig.find_child("Wisps", true, false) as GPUParticles3D
	if _cig_tw and _cig_tw.is_valid():
		_cig_tw.kill()
	_cig.visible = true
	_cig.scale = Vector3.ONE * 10.0 * EmoteRig.CIG_SCALE
	if wisps:
		wisps.emitting = true
	var tw := create_tween()
	_cig_tw = tw
	# Drag: ember flares while the hand is at the lips.
	tw.tween_interval(0.5)
	var glow := func(e: float) -> void:
		ember.emission_energy_multiplier = e
		if tip:
			tip.light_energy = e * 0.35
	tw.tween_method(glow, 2.0, 7.0, 0.9)
	tw.tween_method(glow, 7.0, 2.0, 0.5)
	# Exhale as the hand comes down.
	tw.tween_callback(func() -> void:
		if _head:
			EmoteRig.exhale(_head, Juice.soft_texture()))
	tw.tween_interval(EmoteRig.SMOKE_LEN - 1.9)
	tw.tween_callback(func() -> void: _emote_busy = false)
	# Keep it smouldering on the lips a while, then flick it away.
	tw.tween_interval(3.5)
	tw.tween_callback(func() -> void:
		if wisps:
			wisps.emitting = false)
	tw.tween_property(_cig, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _cig.visible = false)

func _run_drink() -> void:
	if _glass == null:
		_emote_busy = false
		return
	var liquid: Node3D = _glass.get_meta(&"liquid")
	_glass.visible = true
	_glass.scale = Vector3.ZERO
	liquid.scale = Vector3.ONE
	var tw := create_tween()
	tw.tween_property(_glass, "scale", Vector3.ONE * EmoteRig.GLASS_SCALE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.45)
	# Sip: the level drops while the glass is tipped.
	tw.tween_property(liquid, "scale:y", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(EmoteRig.DRINK_LEN - 1.5 - 0.3)
	tw.tween_property(_glass, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_glass.visible = false
		_emote_busy = false)
