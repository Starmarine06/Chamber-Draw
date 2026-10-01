extends Node

## Trauma-based screen shake (Squirrel Eiserloh model): `add_trauma()` bumps a
## 0..1 value that decays over time; the offset scales with trauma². Moves a
## 2D Control (the whole game screen) and nudges the 3D camera's h/v offset.
## Scaled by Settings.shake_factor() — zero under Reduced motion.

var target_2d: Control
var camera: Camera3D
var max_offset_px: float = 14.0
var max_cam_offset: float = 0.035
var max_roll_deg: float = 0.5
var decay: float = 1.6

var _trauma: float = 0.0
var _t: float = 0.0
var _base_pos: Vector2 = Vector2.ZERO
var _active := false

func add_trauma(amount: float) -> void:
	var s := get_node_or_null("/root/Settings")
	var f: float = 1.0 if s == null else float(s.shake_factor())
	if f <= 0.0:
		return
	if not _active and target_2d:
		_base_pos = target_2d.position
		target_2d.pivot_offset = target_2d.size * 0.5
	_active = true
	_trauma = clampf(_trauma + amount * f, 0.0, 1.0)

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	_trauma = maxf(_trauma - decay * delta, 0.0)
	var shake := _trauma * _trauma
	var ox := _n(1.0) * max_offset_px * shake
	var oy := _n(2.3) * max_offset_px * shake
	if target_2d:
		target_2d.position = _base_pos + Vector2(ox, oy)
		target_2d.rotation_degrees = _n(4.1) * max_roll_deg * shake
	if camera and is_instance_valid(camera):
		camera.h_offset = _n(5.7) * max_cam_offset * shake
		camera.v_offset = _n(7.9) * max_cam_offset * shake
	if _trauma <= 0.0:
		_active = false
		if target_2d:
			target_2d.position = _base_pos
			target_2d.rotation_degrees = 0.0
		if camera and is_instance_valid(camera):
			camera.h_offset = 0.0
			camera.v_offset = 0.0

## Cheap smooth pseudo-noise in [-1, 1] from layered sines.
func _n(seed_f: float) -> float:
	var x := _t * 38.0 + seed_f * 13.7
	return (sin(x) * 0.6 + sin(x * 2.17 + seed_f) * 0.3 + sin(x * 4.31 + seed_f * 2.0) * 0.1)
