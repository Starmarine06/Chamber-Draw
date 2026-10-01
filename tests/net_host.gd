extends SceneTree
const Bot := preload("res://tests/net_bot.gd")
func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	seed(7)
	var e = root.get_node("EOSManager")
	print("HOST start ", e.debug_enet_host(29555))
	while e.roster.size() < 2:
		await create_timer(0.2).timeout
	await create_timer(1.0).timeout
	e.debug_start(0)
	await create_timer(9.0).timeout
	var g = current_scene
	for i in 70:
		await create_timer(1.2).timeout
		var act: String = Bot.step(g)
		print("HOST t=%d st=%d cur=%d hands=%s pend=%d act=%s" % [i, g.state, g.game.current_index, str(g.game.players.map(func(p): return p.hand.size())), g.game.pending_forced_draw_player_index, act])
	print("HOST leaving via main menu")
	g._on_main_menu()
	await create_timer(2.5).timeout
	print("HOST after menu, scene=", current_scene.name if current_scene else "none")
	quit()
