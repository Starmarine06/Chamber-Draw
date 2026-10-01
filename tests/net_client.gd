extends SceneTree
const Bot := preload("res://tests/net_bot.gd")
func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	var e = root.get_node("EOSManager")
	print("CLIENT start ", e.debug_enet_client(29555))
	await create_timer(10.0).timeout
	var g = current_scene
	for i in 70:
		await create_timer(1.2).timeout
		var act: String = Bot.step(g)
		print("CLIENT look=", g._look_active(), " modal=", g._modal_visible(), " paused=", g._paused, " cf=", g._cursor_free, " mm=", Input.mouse_mode, " focus=", g.get_window().has_focus(), " ended=", g._session_ended, " ui_cover=", g._ui_cover != null, " line=", g._line_scene != null, " logp=", g._log_panel != null)
		print("CLIENT t=%d st=%d cur=%d hands=%s pend=%d own=%d act=%s" % [i, g.state, g.game.current_index, str(g.game.players.map(func(p): return p.hand.size())), g.game.pending_forced_draw_player_index, g.own_index, act])
	print("CLIENT leaving via main menu")
	g._on_main_menu()
	await create_timer(2.5).timeout
	print("CLIENT after menu, scene=", current_scene.name if current_scene else "none")
	quit()
