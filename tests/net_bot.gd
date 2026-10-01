extends RefCounted
## Tiny autopilot for the two-process network tests: plays whatever the local seat is allowed to do.
static func step(g: Node) -> String:
	var me: int = g.own_index
	if g.game == null or me >= g.game.players.size():
		return "noplayers"
	var S = g.State
	match g.state:
		S.HUMAN_TURN:
			if g.game.current_index == me:
				var vp: Array = g.game.get_valid_plays(me)
				# Plain number cards only: no popups to drive.
				vp = vp.filter(func(i): return g.game.players[me].hand[i].type == Card.CardType.NUMBER)
				if not vp.is_empty():
					g._play_by_hand_index(vp[0])
					return "play"
				if g._drew_this_turn:
					g._end_turn()
					return "end"
				g._on_deck_clicked("A")
				return "draw"
		S.FORCED_DRAW_DECK_CHOICE:
			if g.game.pending_forced_draw_player_index == me:
				g._on_deck_clicked("B")
				return "forced"
		S.JUMP_IN:
			if g.own_index in g.game.jump_in_candidate_list:
				g._pass_jump_in()
				return "pass"
			return "jwait cand=" + str(g.game.jump_in_candidate_list) + " open=" + str(g.game.jump_in_open) + " win=" + str(g._jump_in_window)
		S.LAST_SHOT:
			if g.game.current_index == me:
				g._on_deck_clicked("A")
				return "lastshot"
		S.HUMAN_COLOR_SELECT:
			g._on_color_chosen(Card.CardColor.RED) if g.has_method("_on_color_chosen") else null
			return "color"
	return "-"
