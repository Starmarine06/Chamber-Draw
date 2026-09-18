extends Node

## Global settings passed between menu, lobby and game scene.

var num_players: int = 4
var game_mode: int = 0  # 0 = Shedding Race, 1 = Last One Standing

## Network mode. True when playing over EOS multiplayer.
var is_online: bool = false

## Guided tutorial mode. True only when launched from the menu's TUTORIAL
## button; routes AI/timer/input control to the tutorial director.
var is_tutorial: bool = false

## Local seat index into the game's player array. 0 = host, and 0 offline too.
var own_seat: int = 0

## Player seat colors (index = seat). Shared by menu, lobby, game UI and borders.
const PALETTE: Array[Color] = [
	Color(0.88, 0.16, 0.16),  # 0 red
	Color(0.18, 0.42, 0.88),  # 1 blue
	Color(0.15, 0.68, 0.30),  # 2 green
	Color(0.95, 0.78, 0.10),  # 3 yellow
	Color(0.72, 0.28, 0.90),  # 4 purple
	Color(0.98, 0.50, 0.12),  # 5 orange
	Color(0.10, 0.77, 0.90),  # 6 cyan
	Color(0.93, 0.42, 0.72),  # 7 pink
]
const PALETTE_NAMES: Array[String] = [
	"Red", "Blue", "Green", "Yellow", "Purple", "Orange", "Cyan", "Pink",
]

## Color index the local player has chosen in the menu / online lobby.
var my_color_idx: int = 0
