extends Node

## Draws the first-person "vice" props (hand, glass, cigarette, bottle...) in a
## second 3D pass ON TOP of the world, so they can never be sliced open by the
## table rim or any other geometry between the lens and the hand.
##
## How: rig meshes live on render layer 2. The main cameras do not render layer 2;
## a second SubViewport (same World3D) with its own camera copies the seat
## camera every frame and renders ONLY layer 2 onto a transparent texture that
## sits just above the 3D view.

const LAYER := 2
const RIG_NAMES := ["FirstPersonSmoke", "FirstPersonDrink", "FirstPersonDrinkWorld"]

var main_vp: SubViewport
var vp: SubViewport
var cam: Camera3D
var rect: TextureRect
var main_cam: Camera3D = null


static func create(host: Control, p_main_vp: SubViewport, above: Control) -> Node:
	var o: Node = (load("res://scripts/fx/prop_overlay.gd") as Script).new()
	o.name = "PropOverlay"
	o.process_priority = 200   # after every script that moves the seat camera
	o.main_vp = p_main_vp
	host.add_child(o)
	o._build(host, above)
	return o


func _build(host: Control, above: Control) -> void:
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_3d = main_vp.world_3d
	vp.size = main_vp.size
	add_child(vp)

	cam = Camera3D.new()
	cam.cull_mask = LAYER_MASK()
	cam.near = 0.003
	cam.far = 50.0
	# Match the main view's look without painting an opaque background.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.36, 0.4)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	cam.environment = env
	vp.add_child(cam)
	cam.current = true

	rect = TextureRect.new()
	rect.name = "PropOverlayRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = vp.get_texture()
	host.add_child(rect)
	host.move_child(rect, above.get_index() + 1)

	get_tree().node_added.connect(_on_node_added)
	set_active(false)


static func LAYER_MASK() -> int:
	return 1 << (LAYER - 1)


## Call once (and whenever a new seat camera appears): hide layer 2 from it.
func exclude_from(cameras: Array) -> void:
	for c in cameras:
		var camera := c as Camera3D
		if camera != null and camera != cam:
			camera.cull_mask = camera.cull_mask & ~LAYER_MASK()


## The second pass only renders while a vice rig is on screen.
func set_active(on: bool) -> void:
	if rect:
		rect.visible = on
	if vp:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)


func _process(_delta: float) -> void:
	if main_vp == null or cam == null:
		return
	if vp.size != main_vp.size:
		vp.size = main_vp.size
	if main_cam != null and is_instance_valid(main_cam):
		cam.global_transform = main_cam.global_transform
		cam.fov = main_cam.fov
		cam.h_offset = main_cam.h_offset
		cam.v_offset = main_cam.v_offset
		# Cameras added later (seat switches) must not draw layer 2 either.
		if main_cam.cull_mask & LAYER_MASK() != 0:
			main_cam.cull_mask = main_cam.cull_mask & ~LAYER_MASK()


func _in_rig(n: Node) -> bool:
	var p: Node = n
	for _i in 24:
		if p == null:
			return false
		if RIG_NAMES.has(String(p.name)):
			return true
		p = p.get_parent()
	return false


## Every mesh added under a vice rig moves to layer 2; when it is re-parented out
## of the rig (glass set on the table, cigarette laid in the ashtray) it goes back.
func _on_node_added(n: Node) -> void:
	var g := n as GeometryInstance3D
	if g == null:
		return
	if _in_rig(n):
		g.layers = LAYER_MASK()
	elif g.layers == LAYER_MASK():
		g.layers = 1
