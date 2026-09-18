extends Control

## Test harness: runs Chamber Draw with simple AI players so the core loop
## (deck building, playing, drawing, Chamber resolution, win conditions) can
## be validated with no art or networking yet. Run this scene (F6 in Godot)
## and watch the log — it should always terminate with a winner.

@export var num_players: int = 4
@export var mode: GameState.Mode = GameState.Mode.SHEDDING_RACE
@export var max_turns: int = 500  # safety cap so a bugged loop can't hang forever

var game: GameState
var log_lines: PackedStringArray = []

@onready var log_label: RichTextLabel = $LogLabel

func _ready() -> void:
	game = GameState.new()
	game.log_event.connect(_on_log_event)
	game.setup(num_players, mode)
	_run_simulation()

func _on_log_event(text: String) -> void:
	log_lines.append(text)

func _run_simulation() -> void:
	var turns := 0
	while not game.game_over and turns < max_turns:
		if game.jump_in_open:
			# AI answers the jump-in window with the first matching copy.
			var candidates: Array = game.jump_in_candidate_list
			if candidates.size() > 0:
				game.jump_in(int(candidates[0]))
			else:
				game.close_jump_in_window()
		else:
			_take_ai_turn(game.current_index)
		turns += 1

	if game.game_over:
		log_lines.append("\n=== GAME OVER — Winner: %s (after %d turns) ===" % [game.winner_name, turns])
	else:
		log_lines.append("\n=== Hit max_turns safety cap (%d) without a winner — check for a logic loop ===" % max_turns)

	if log_label:
		log_label.text = "\n".join(log_lines)
	else:
		for line in log_lines:
			print(line)

## Deliberately simple/dumb AI: play the first valid card in hand; if no valid
## card, draw from whichever pile has more cards left (arbitrary tie-break).
## This is only meant to exercise the rules engine, not to be a good player.
func _take_ai_turn(player_index: int) -> void:
	var valid := game.get_valid_plays(player_index)
	if valid.size() > 0:
		var hand_index: int = valid[0]
		var card: Card = game.players[player_index].hand[hand_index]
		var options := {}
		if card.type == Card.CardType.WILD or card.action_id in ["choose_deck"]:
			options["chosen_color"] = randi() % 4
		if card.action_id in ["swap_hands", "choose_deck", "wild_sabotage"]:
			options["target_player_index"] = game._next_alive_index(player_index, game.direction)
		if card.action_id in ["choose_deck", "peek"]:
			options["chosen_pile"] = "A" if randi() % 2 == 0 else "B"
		game.play_card(player_index, hand_index, options)
	else:
		var pile_choice := "A" if game.deck.pile_a.size() >= game.deck.pile_b.size() else "B"
		game.draw_card(player_index, pile_choice)
