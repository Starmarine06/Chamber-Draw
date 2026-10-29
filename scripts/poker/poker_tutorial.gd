extends RefCounted

## Guided first hand of Texas Hold'em. The deck is rigged so the lesson always plays out the same way:
## you hold Ace-King of spades, the bot holds Queen-Jack. The game loop calls `on_event` at key moments.

const Eval := preload("res://scripts/poker/poker_eval.gd")

var g: Control

func _init(game: Control) -> void:
	g = game

## Seat 0 (you) is dealer + small blind, seat 1 is Coach Bot.
func rig() -> Dictionary:
	return {
		"dealer": 0,
		"hole": {
			0: [Eval.make(14, 3), Eval.make(13, 3)],   # A♠ K♠
			1: [Eval.make(12, 1), Eval.make(11, 0)],   # Q♦ J♣
		},
		"board": [Eval.make(14, 2), Eval.make(7, 0), Eval.make(2, 1), Eval.make(9, 3), Eval.make(13, 1)],  # A♥ 7♣ 2♦ 9♠ K♦
	}

## The bot never folds, bets once on the flop, otherwise checks and calls.
func bot_decision(engine: RefCounted, i: int) -> Dictionary:
	if engine.stage == 1 and engine.current_bet == 0:
		return {"kind": "raise", "raise_to": 40}
	if engine.current_bet > int(engine.players[i].bet):
		return {"kind": "call", "raise_to": 0}
	return {"kind": "check", "raise_to": 0}

func on_event(name: String, arg: Variant = null) -> void:
	match name:
		"intro":
			await _intro()
		"dealt":
			await _dealt()
		"street":
			await _street()
		"human_turn":
			_human_turn()
		"acted":
			if String(arg) == "raise":
				g.Sound.play(&"win", -8.0)
		"showdown":
			await _showdown()
		"hand_end":
			await _end()

func _intro() -> void:
	await g.coach_say("WELCOME TO TEXAS HOLD'EM",
		"This is the most popular poker game on Earth, and you can learn it in about two minutes.\n\nYou are playing one practice hand against [b]Coach Bot[/b]. Nothing here costs real money. Press [b]SPACE[/b] when you have read a box. Move the [b]mouse[/b] to look around the table: you are sitting right there.")
	await g.coach_say("THE GOAL",
		"Win chips. Everybody gets [b]2 private cards[/b]. Five more cards go [b]face up in the middle[/b], shared by everyone, a few at a time.\n\nYour hand is the [b]best 5 cards[/b] you can make from your 2 plus the 5 in the middle. Best hand wins the pot, or everyone else gives up first.")
	await g.coach_say("THE CHEAT SHEET",
		"This list on the right ranks every hand, [b]strongest at the top[/b]. Keep it in view.\n\nDuring the game, the row for the best hand you currently hold lights up and says [b]YOU[/b]. You never have to memorise it.",
		g.right_panel)
	await g.coach_say("YOUR FOUR MOVES",
		"[b]FOLD[/b]  give up the hand. You lose what you already put in.\n[b]CHECK[/b]  pass for free when nobody has bet.\n[b]CALL[/b]  match the bet to stay in.\n[b]RAISE / BET[/b]  put in more chips and make others pay.\n\nThe suggestion line under the table tells you what a sensible player would do, with a reason.",
		g.action_bar)
	await g.coach_say("YOUR HANDS ARE ON THE TABLE",
		"Everything is physical. Your [b]chips[/b] are the stacks on the tray hanging in front of you (look down). [b]Click a stack[/b] to drop a chip in your pile by the betting ring, [b]click the pile[/b] to push it in (an empty pile means check), [b]right-click[/b] to take a chip back.

Shortcuts: [b]C[/b] call, [b]R[/b] raise, [b]A[/b] all-in, [b]F[/b] fold. [b]TAB[/b] frees the mouse cursor.",
		"rack")

func _dealt() -> void:
	await g.coach_say("YOUR CARDS",
		"Your two cards lie face down on the felt. [b]Hover your crosshair over them[/b] (or hold [b]Q[/b]) to flip them face up. You were dealt the [b]Ace[/b] and [b]King of spades[/b]. Nobody else can see them.\n\nAce-King is one of the best starting hands there is.",
		"cards")
	await g.coach_say("THE DEALER, THE BUTTON AND BLINDS",
		"The [b]D[/b] button marks the dealer and moves one seat every hand.\n\nTo make sure there is always something to win, two players post forced bets first: the [b]small blind (10)[/b] and the [b]big blind (20)[/b]. That is why chips are already in the pot.",
		"button")

func _human_turn() -> void:
	var e = g.engine
	match int(e.stage):
		0:
			g.coach_task("YOUR MOVE: PRE-FLOP",
				"Betting starts. The big blind is 20 and you have put in 10, so it costs [b]10 more[/b] to stay in.\n\nWith Ace-King you want to play. Press [b]C[/b] to CALL. Want the real feel? Look down at the chip stacks on your right, [b]click the 5 chip twice[/b], then [b]click the pile[/b] in the ring (or press SPACE).",
				["call"], "rack")
		1:
			g.coach_task("COACH BOT BET 40",
				"Coach Bot pushed 40 chips in. A bluff? Maybe. Players bet with nothing all the time.\n\nYou hold a pair of Aces and the price is 40 to win a pot of 80+. Good price. Press [b]C[/b] to call, or build 40 in the pile yourself and click it.",
				["call"], "pile")
		2:
			g.coach_task("YOUR TURN TO BET",
				"Coach Bot checked, so you can bet. Your pair of Aces is the best hand on the table right now, so make them pay.\n\n[b]Click chips[/b] to build a bet (about half the pot is classic, so try 25 + 25 + 5 + 5), then [b]click the pile[/b] or press [b]SPACE[/b]. Too many chips? [b]Right-click[/b] takes one back. Shortcut: [b]R[/b].",
				["raise"], "rack")
		_:
			g.coach_task("FINAL BETTING ROUND",
				"The river gave you a King: [b]Two Pair, Aces and Kings[/b]. You are almost certainly ahead.\n\nBet again: stack chips, then click the pile or press SPACE.",
				["raise"], "rack")

func _street() -> void:
	var n: int = g.engine.board.size()
	match n:
		3:
			await g.coach_say("THE FLOP",
				"The first 3 shared cards. An Ace landed, and you hold the other Ace.\n\nLook at the rankings list: [b]One Pair[/b] is now lit up for you. Everyone shares these cards, so the question is who uses them best.",
				"board")
		4:
			await g.coach_say("THE TURN",
				"A 4th shared card. It is a 9 and does not change your hand.\n\nAfter each new card there is another round of betting. Cards you do not need are just noise.",
				"board")
		5:
			await g.coach_say("THE RIVER",
				"The last shared card, a King. Together with the King in your hand you now have [b]Two Pair[/b]. See the list light up?",
				"board")

func _showdown() -> void:
	await g.coach_say("SHOWDOWN",
		"When betting ends, players still in turn their cards face up. Best 5-card hand wins.\n\nYou made [b]Two Pair, Aces and Kings[/b]. Coach Bot only has Ace high. The winning cards glow gold, the rest fade, and the winner rakes in the pot. Every round the camera swings to whoever won.")

func _end() -> void:
	g.tutorial_finish()
