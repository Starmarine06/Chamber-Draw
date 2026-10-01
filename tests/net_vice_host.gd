extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var e = root.get_node("EOSManager")
	e.debug_enet_host(29556)
	while e.roster.size() < 2:
		await create_timer(0.2).timeout
	await create_timer(1.0).timeout
	e.debug_start(0)
	await create_timer(14.0).timeout
	var g = current_scene
	g._vice_pick["drink"] = {"cat": "wine", "brand": 1}
	g._start_vice_after_pick(&"drink")
	await create_timer(14.0).timeout
	print("HOST seat_glass=", g._seat_glass.keys(), " crowd=", g._crowd != null)
	quit()
