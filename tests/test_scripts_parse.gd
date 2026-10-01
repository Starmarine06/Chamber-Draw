@tool
extends McpTestSuite

## Gatekeeping: the project's two scene entry points and every gameplay script
## must LOAD without a parse error. A parse error in a shipped script is
## invisible to the headless menu boot (menu.tscn does not preload game.gd),
## so this suite is the regression net that catches it.

func suite_name() -> String:
	return "scripts_parse"


func test_entry_scenes_load_without_errors() -> void:
	assert_true(load("res://scenes/menu.tscn") != null, "menu.tscn loads")
	assert_true(load("res://scenes/game.tscn") != null, "game.tscn loads")
	assert_true(load("res://scenes/game_3d.tscn") != null, "game_3d.tscn loads")
	assert_true(load("res://scenes/player_ui.tscn") != null, "player_ui.tscn loads")


func test_core_gameplay_scripts_load() -> void:
	assert_true(load("res://scripts/game.gd") != null, "game.gd parses")
	assert_true(load("res://scripts/game_state.gd") != null, "game_state.gd parses")
	assert_true(load("res://scripts/deck_manager.gd") != null, "deck_manager.gd parses")
	assert_true(load("res://scripts/card_node.gd") != null, "card_node.gd parses")
	assert_true(load("res://scripts/card_database.gd") != null, "card_database.gd parses")


func test_system_scripts_load() -> void:
	assert_true(load("res://scripts/game_globals.gd") != null, "game_globals.gd parses")
	assert_true(load("res://scripts/player_data.gd") != null, "player_data.gd parses")
	assert_true(load("res://scripts/chamber_deck.gd") != null, "chamber_deck.gd parses")
	assert_true(load("res://scripts/turn_timer_ring.gd") != null, "turn_timer_ring.gd parses")
	assert_true(load("res://scripts/eos_config.gd") != null, "eos_config.gd parses")
	assert_true(load("res://scripts/eos_manager.gd") != null, "eos_manager.gd parses")
	assert_true(load("res://scripts/menu.gd") != null, "menu.gd parses")
	assert_true(load("res://scripts/lobby.gd") != null, "lobby.gd parses")
	assert_true(load("res://scripts/settings.gd") != null, "settings.gd parses")
	assert_true(load("res://scripts/audio_manager.gd") != null, "audio_manager.gd parses")
	assert_true(load("res://scripts/ui_style.gd") != null, "ui_style.gd parses")
	assert_true(load("res://scripts/settings_panel.gd") != null, "settings_panel.gd parses")
	assert_true(load("res://scripts/noir_background.gd") != null, "noir_background.gd parses")
	assert_true(load("res://scripts/character_actor.gd") != null, "character_actor.gd parses")
	assert_true(load("res://scripts/voice_chat.gd") != null, "voice_chat.gd parses")
	assert_true(load("res://scripts/ui/voice_bar.gd") != null, "ui/voice_bar.gd parses")
	assert_true(load("res://scripts/fx/juice.gd") != null, "fx/juice.gd parses")
	assert_true(load("res://scripts/fx/screen_shake.gd") != null, "fx/screen_shake.gd parses")
	assert_true(load("res://scripts/fx/chamber_cylinder.gd") != null, "fx/chamber_cylinder.gd parses")
	assert_true(load("res://scripts/sound.gd") != null, "sound.gd parses")
	assert_true(load("res://scripts/fx/emote_rig.gd") != null, "fx/emote_rig.gd parses")
	assert_true(load("res://scripts/fx/vice_first_person.gd") != null, "fx/vice_first_person.gd parses")
	assert_true(load("res://scripts/ui/deck_gauge.gd") != null, "ui/deck_gauge.gd parses")
	assert_true(load("res://scripts/fx/first_person_smoke.gd") != null, "fx/first_person_smoke.gd parses")
	assert_true(load("res://scripts/fx/first_person_drink.gd") != null, "fx/first_person_drink.gd parses")
	assert_true(load("res://scripts/fx/sfx_synth.gd") != null, "fx/sfx_synth.gd parses")
	assert_true(load("res://scripts/fx/revolver_duel.gd") != null, "fx/revolver_duel.gd parses")
	assert_true(load("res://scripts/fx/music_synth.gd") != null, "fx/music_synth.gd parses")
	assert_true(load("res://scripts/ui/tutorial_coach.gd") != null, "ui/tutorial_coach.gd parses")
	assert_true(load("res://scripts/tutorial_director.gd") != null, "tutorial_director.gd parses")