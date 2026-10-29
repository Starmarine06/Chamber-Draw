extends SceneTree
## Two-process Hold'em test over local ENet. Run host first, then net_poker_client.gd in a second shell.
func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	seed(11)
	var e = root.get_node("EOSManager")
	print("HOST start ", e.debug_enet_host(29556))
	while e.roster.size() < 3:
		await create_timer(0.2).timeout
	await create_timer(1.0).timeout
	e.debug_start(1)
	await create_timer(4.0).timeout
	var g = current_scene
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
			print("HOST hand=%d stage=%d cur=%d over=%s chips=%s" % [g.engine.hand_number, g.engine.stage, g.engine.current, str(g.engine.hand_over), str(g.engine.players.map(func(p): return p.chips))])
	print("HOST done")
	quit()
