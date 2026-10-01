extends ColorRect
const UIStyle := preload("res://scripts/ui_style.gd")
const Sound := preload("res://scripts/sound.gd")

## Full-screen animated noir backdrop (smoke + warm light + vignette) for the
## menu and lobby. Also floats a few slow brass dust motes.

const SHADER := preload("res://shaders/smoke_bg.gdshader")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	color = UIStyle.INK
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	material = mat
	_add_motes()

func _add_motes() -> void:
	var motes := CPUParticles2D.new()
	motes.amount = 28
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.direction = Vector2(0.3, -1.0)
	motes.spread = 35.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 16.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.6
	var grad := Gradient.new()
	grad.set_color(0, Color(UIStyle.BRASS_LIGHT, 0.0))
	grad.set_color(1, Color(UIStyle.BRASS_LIGHT, 0.0))
	grad.add_point(0.3, Color(UIStyle.BRASS_LIGHT, 0.45))
	grad.add_point(0.7, Color(UIStyle.BRASS_LIGHT, 0.3))
	motes.color_ramp = grad
	add_child(motes)
	var place := func() -> void:
		motes.position = size * 0.5
		motes.emission_rect_extents = size * 0.5
	resized.connect(place)
	place.call()
