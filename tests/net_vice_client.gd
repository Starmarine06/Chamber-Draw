extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var e = root.get_node("EOSManager")
	e.debug_enet_client(29556)
	await create_timer(15.0).timeout
	var g = current_scene
	for i in 14:
		await create_timer(1.0).timeout
		var bt = g._crowd.bartender if g._crowd != null else {}
		print("CLIENT t=%d glass=%s prod=%s busy=%s" % [i, str(g._seat_glass.keys()), str(g._seat_drink_prod.get(0, {}).get("id", "-")), str(bt.get("busy", "?"))])
	quit()
