extends Control

## Modal "what'll it be?" picker for smoking (cigarettes / cigars) and drinking
## (12 spirit/beer/wine types). Pick a type, then a brand; on_pick(cat, brand_index).
## Esc or Cancel closes it.

const UIStyle := preload("res://scripts/ui_style.gd")
const Catalog := preload("res://scripts/vice_catalog.gd")

var kind := "drink"                 # "smoke" | "drink"
var cat := "whiskey"
var brand_idx := 0
var on_pick: Callable
var on_cancel: Callable
var _body: VBoxContainer


static func open(host: Node, p_kind: String, pick: Callable, cancel: Callable, z: int = 300) -> Control:
	var p: Control = (load("res://scripts/ui/vice_picker.gd") as Script).new()
	p.kind = p_kind
	p.on_pick = pick
	p.on_cancel = cancel
	var last: Dictionary = Catalog.last_smoke if p_kind == "smoke" else Catalog.last_drink
	p.cat = str(last.cat)
	p.brand_idx = int(last.brand)
	p.z_index = z
	host.add_child(p)
	return p


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UIStyle.INK, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIStyle.make_panel()
	center.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	panel.add_child(_body)
	_rebuild()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()


func _cancel() -> void:
	var cb := on_cancel
	queue_free()
	if cb.is_valid():
		cb.call()


func _rebuild() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var title := "LIGHT UP" if kind == "smoke" else "WHAT'LL IT BE?"
	_body.add_child(UIStyle.make_label(title, 34, UIStyle.BRASS, true))

	# Category row(s).
	var cats: Array = []
	if kind == "smoke":
		cats = [["cigarette", "Cigarettes"], ["cigar", "Cigars"]]
	else:
		for id in Catalog.DRINK_ORDER:
			cats.append([id, Catalog.DRINKS[id].label])
	var grid := GridContainer.new()
	grid.columns = 2 if kind == "smoke" else 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	for entry in cats:
		var b := UIStyle.make_button(entry[1], &"primary" if entry[0] == cat else &"secondary", Vector2(150, 42), 16)
		var id: String = entry[0]
		b.pressed.connect(func() -> void:
			cat = id
			brand_idx = 0
			_rebuild())
		grid.add_child(b)

	# Brand row.
	_body.add_child(UIStyle.make_label("BRAND", 18, UIStyle.CREAM, true))
	var brands: Array = _brand_names()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	var tag := UIStyle.make_label(_tag_for(brand_idx), 15, UIStyle.CREAM, true)
	for i in brands.size():
		var bb := UIStyle.make_button(brands[i], &"confirm" if i == brand_idx else &"secondary", Vector2(170, 52), 16)
		var idx := i
		bb.mouse_entered.connect(func() -> void: tag.text = _tag_for(idx))
		bb.pressed.connect(func() -> void: _choose(idx))
		row.add_child(bb)
	_body.add_child(tag)

	var cancel := UIStyle.make_button("Cancel", &"danger", Vector2(160, 40), 16)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_cancel)
	_body.add_child(cancel)


func _brand_names() -> Array:
	var out: Array = []
	if kind == "smoke":
		var list: Array = Catalog.CIGARS if cat == "cigar" else Catalog.CIGARETTES
		for d in list:
			out.append(d.name)
	else:
		var def: Dictionary = Catalog.DRINKS.get(cat, Catalog.DRINKS.whiskey)
		for b in def.brands:
			out.append(b.name)
	return out


func _tag_for(i: int) -> String:
	if kind == "smoke":
		var list: Array = Catalog.CIGARS if cat == "cigar" else Catalog.CIGARETTES
		if i >= 0 and i < list.size():
			return str(list[i].tag)
		return ""
	var def: Dictionary = Catalog.DRINKS.get(cat, Catalog.DRINKS.whiskey)
	return "%s  ·  %s" % [def.label, "strong" if float(def.abv) >= 1.0 else "light"]


func _choose(i: int) -> void:
	brand_idx = i
	var last: Dictionary = Catalog.last_smoke if kind == "smoke" else Catalog.last_drink
	last["cat"] = cat
	last["brand"] = i
	var cb := on_pick
	var c := cat
	queue_free()
	if cb.is_valid():
		cb.call(c, i)
