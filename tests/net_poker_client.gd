extends SceneTree
func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	var e = root.get_node("EOSManager")
	print("CLIENT start ", e.debug_enet_client(29556))
	await create_timer(6.0).timeout
	var g = current_scene
	print("CLIENT scene=", g.name if g else "none")
	Engine.time_scale = 6.0
	for i in 400:
		await create_timer(0.5).timeout
		if g._awaiting and not g._acting:
			var eng = g.engine
			var kind: String = eng.advise(0).kind
			if kind == "raise":
				g._auto_stack(eng.min_raise_to(0) - int(eng.players[0].bet))
			elif kind == "fold":
				g._on_fold()
				g._on_fold()
			else:
				g._auto_stack(0 if eng.can_check(0) else eng.to_call(0))
		if i % 60 == 0:
			print("CLIENT%d ph=%s q=%d aw=%s acting=%s pend=%s hand=%d stage=%d cur=%d over=%s chips=%s" % [g.own_seat, g._phase, g._snap_queue.size(), str(g._awaiting), str(g._acting), str(g._pending), g.engine.hand_number, g.engine.stage, g.engine.current, str(g.engine.hand_over), str(g.engine.players.map(func(p): return p.chips))])
	print("CLIENT done")
	quit()
