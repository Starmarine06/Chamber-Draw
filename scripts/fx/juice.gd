extends RefCounted

## Stateless "game feel" helpers: arc flights, squash, particle bursts and
## flashes. All durations respect Settings.anim_speed and every flash /
## shake respects Settings.reduced_motion.

# ── Settings access ───────────────────────────────────────────────────

static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Settings")

## Scales a base duration by the player's animation-speed preference.
static func d(seconds: float) -> float:
	var s := _settings()
	if s == null:
		return seconds
	return seconds / maxf(float(s.anim_speed), 0.1)

static func reduced_motion() -> bool:
	var s := _settings()
	return s != null and bool(s.reduced_motion)

# ── Math ──────────────────────────────────────────────────────────────

## Quadratic Bézier point.
static func bezier(a: Vector2, ctrl: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + ctrl * (2.0 * u * t) + b * (t * t)

## Control point that bows the path upward by `height` × distance.
static func arc_control(from: Vector2, to: Vector2, height: float = 0.25) -> Vector2:
	var mid := (from + to) * 0.5
	return mid + Vector2(0, -from.distance_to(to) * height)

# ── Flights ───────────────────────────────────────────────────────────

## Flies a Control along an upward arc from `from` to `to` (its position is
## the top-left corner; the pivot is centered). Options:
##   height (0.25), dur (0.42), delay (0), spin (deg added, 0),
##   rot_to (final deg, 0), peak_scale (1.15), end_scale (1.0),
##   trans (Tween.TRANS_SINE), land_squash (true)
## Returns the tween so callers can chain callbacks (e.g. queue_free).
static func fly_arc(node: Control, from: Vector2, to: Vector2, opts: Dictionary = {}) -> Tween:
	var height: float = opts.get("height", 0.25)
	var dur: float = d(opts.get("dur", 0.42))
	var delay: float = opts.get("delay", 0.0)
	var spin: float = opts.get("spin", 0.0)
	var rot_to: float = opts.get("rot_to", 0.0)
	var peak: float = opts.get("peak_scale", 1.15)
	var end_s: float = opts.get("end_scale", 1.0)
	var trans: int = opts.get("trans", Tween.TRANS_SINE)
	var squash_on: bool = opts.get("land_squash", true)
	node.pivot_offset = node.size * 0.5
	node.position = from
	var rot_from := rot_to - spin
	node.rotation_degrees = rot_from
	var ctrl := arc_control(from, to, height)
	var tw := node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(t: float) -> void:
		node.position = bezier(from, ctrl, to, t)
		node.rotation_degrees = lerpf(rot_from, rot_to, t)
		var sc := lerpf(1.0, peak, sin(t * PI)) * lerpf(1.0, end_s, t)
		node.scale = Vector2(sc, sc)
	, 0.0, 1.0, dur).set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	if squash_on:
		tw.tween_property(node, "scale", Vector2(end_s * 1.14, end_s * 0.86), d(0.06))
		tw.tween_property(node, "scale", Vector2(end_s, end_s), d(0.12)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw

## Flip a CardNode over (scale-x squeeze) and swap its face at the midpoint.
static func flip_card(card: CardNode, to_face: bool, dur: float = 0.24) -> Tween:
	card.pivot_offset = card.size * 0.5
	var sy := card.scale.y
	var tw := card.create_tween()
	tw.tween_property(card, "scale:x", 0.0, d(dur * 0.5)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: card.update_face(to_face))
	tw.tween_property(card, "scale:x", sy, d(dur * 0.5)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tw

## Scale punch (pop) on any CanvasItem with a `scale` (Control / Node2D).
static func punch(node: Control, amount: float = 0.2, dur: float = 0.3) -> Tween:
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * (1.0 + amount), d(dur * 0.3)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, d(dur * 0.7)).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw

# ── Flash ─────────────────────────────────────────────────────────────

## Full-screen color flash (dimmed heavily under reduced motion).
static func flash(parent: Control, col: Color, dur: float = 0.35) -> void:
	var a := col.a * (0.25 if reduced_motion() else 1.0)
	var r := ColorRect.new()
	r.color = Color(col, a)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 150
	parent.add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(r.queue_free)

# ── Particles ─────────────────────────────────────────────────────────

static var _soft_tex: Texture2D

## Soft round sprite for smoke / glow particles (generated, no asset needed).
static func soft_texture() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex

static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / float(cols.size() - 1), cols[i])
	return g

## One-shot particle burst at a screen position. Presets:
## &"sparks" (card slap), &"confetti" (win), &"smoke" (blank / backfire),
## &"muzzle" (LIVE), &"gold" (respawn / extra life / lucky), &"ember".
static func burst(parent: Node, pos: Vector2, preset: StringName, scale_mul: float = 1.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.position = pos
	p.z_index = 120
	p.local_coords = false
	match preset:
		&"sparks":
			p.amount = 18
			p.lifetime = 0.45
			p.spread = 180.0
			p.initial_velocity_min = 120.0 * scale_mul
			p.initial_velocity_max = 260.0 * scale_mul
			p.gravity = Vector2(0, 420)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 3.5
			p.color_ramp = _ramp([Color(1, 0.95, 0.7), Color(0.95, 0.7, 0.3), Color(0.8, 0.4, 0.1, 0)])
		&"confetti":
			p.amount = 90
			p.lifetime = 2.6
			p.explosiveness = 0.85
			p.direction = Vector2(0, -1)
			p.spread = 70.0
			p.initial_velocity_min = 380.0 * scale_mul
			p.initial_velocity_max = 720.0 * scale_mul
			p.gravity = Vector2(0, 520)
			p.damping_min = 40.0
			p.damping_max = 90.0
			p.angular_velocity_min = -360.0
			p.angular_velocity_max = 360.0
			p.scale_amount_min = 4.0
			p.scale_amount_max = 8.0
			var cg := Gradient.new()
			cg.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
			cg.colors = PackedColorArray([Color("c9a45c"), Color("b3262f"), Color("2e7d4f"), Color("d0741f"), Color("6b3a93")])
			p.color_initial_ramp = cg
			p.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		&"smoke":
			p.amount = 22
			p.lifetime = 1.4
			p.explosiveness = 0.7
			p.texture = soft_texture()
			p.direction = Vector2(0, -1)
			p.spread = 50.0
			p.initial_velocity_min = 30.0 * scale_mul
			p.initial_velocity_max = 90.0 * scale_mul
			p.gravity = Vector2(0, -30)
			p.damping_min = 10.0
			p.damping_max = 30.0
			p.scale_amount_min = 0.8 * scale_mul
			p.scale_amount_max = 2.2 * scale_mul
			var curve := Curve.new()
			curve.add_point(Vector2(0, 0.4))
			curve.add_point(Vector2(1, 1.0))
			p.scale_amount_curve = curve
			p.color_ramp = _ramp([Color(0.75, 0.72, 0.7, 0.0), Color(0.7, 0.68, 0.66, 0.45), Color(0.5, 0.5, 0.5, 0.0)])
		&"muzzle":
			p.amount = 34
			p.lifetime = 0.5
			p.texture = soft_texture()
			p.spread = 180.0
			p.initial_velocity_min = 240.0 * scale_mul
			p.initial_velocity_max = 620.0 * scale_mul
			p.damping_min = 300.0
			p.damping_max = 600.0
			p.scale_amount_min = 0.3 * scale_mul
			p.scale_amount_max = 1.1 * scale_mul
			p.color_ramp = _ramp([Color(1, 1, 0.9, 1), Color(1, 0.75, 0.3, 0.9), Color(0.9, 0.2, 0.05, 0.5), Color(0.2, 0.05, 0.05, 0)])
		&"gold":
			p.amount = 40
			p.lifetime = 1.2
			p.explosiveness = 0.6
			p.texture = soft_texture()
			p.spread = 180.0
			p.initial_velocity_min = 60.0 * scale_mul
			p.initial_velocity_max = 200.0 * scale_mul
			p.gravity = Vector2(0, -60)
			p.damping_min = 30.0
			p.damping_max = 60.0
			p.scale_amount_min = 0.08 * scale_mul
			p.scale_amount_max = 0.22 * scale_mul
			p.color_ramp = _ramp([Color(1, 0.95, 0.7, 0), Color(1, 0.85, 0.45, 1), Color(0.95, 0.7, 0.3, 0)])
		_:
			p.amount = 16
			p.lifetime = 0.8
			p.spread = 180.0
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 140.0
			p.color_ramp = _ramp([Color(1, 0.6, 0.2, 1), Color(0.6, 0.1, 0.05, 0)])
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p
