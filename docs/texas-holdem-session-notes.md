# Texas Hold'em build: what we did

## Mode swap
- Menu and lobby game mode is now Shedding Race or Texas Hold'em. Last One Standing is gone from the menu and lobby (engine enum and tests untouched).
- Hold'em works offline, in the tutorial and online (host-authoritative over the EOS peer, `EOSManager.VERSION` 8).

## Code layout (`scripts/poker/`)
- `poker_eval.gd`: 7-card evaluator and the hand ranking tiers.
- `poker_table.gd`: rules engine (blinds, betting rounds, side pots, AI).
- `poker_card_view.gd`: the Noir Deck, drawn in code (pips, court cards, ornate ace, revolver-drum back).
- `poker_chipbank.gd`: each seat's chips as real counts per denomination (1/5/25/100/500).
- `poker_world.gd`: the 3D world (racetrack table, room, seats, dealer, cards, chips, camera).
- `poker_game.gd`: screen flow, HUD, input, online sync.
- `poker_vices.gd`: smoking, drinking, drunk sway, passing out.
- `poker_tutorial.gd`: rigged one-hand tutorial.
- Shaders: `poker_card.gdshader`, `poker_felt.gdshader`. Scene: `scenes/poker.tscn`.

## Presentation
- First-person view: mouse steers the camera and the cursor is hidden. Esc opens the menu (resume, hints, settings, main menu). There are no clickable buttons.
- Keys: F fold, C call or check, R min-raise, A all-in, 1-5 add a chip, Backspace or right-click removes one, Space commits, Q peeks at your cards, T hints, G hand rankings, Tab frees the cursor, S/W/B vices.
- Chips are real: a bet takes actual chips out of your stack, and winners' stacks grow when the pot sweeps to them.
- Your selectable chips sit on a tray hanging off the rail in front of you.
- Table: racetrack shape with a felt logo (revolver drum and "CHAMBER DRAW" in a circle), padded rail, brass trim, hanging coaster and ashtray shelves.
- Up to 8 seats. A dealer stands in the seating gap, burns cards, mucks folds and moves a dealer button.
- Showdown: contenders slide their cards forward and flip one by one, then the winner is shown (cards glow and lift, camera swing, confetti, pot sweep).
- HUD: permanent pot capsule, bottom-left name and chip count, a "YOUR TURN" key strip with a pulsing screen-edge glow, and a toggleable hand rankings list.
- Hints and the rankings list are toggles that persist in `user://settings.cfg`.

## Bugs fixed along the way
- Chip bank `mixed()` reserve overwrote the 5s (value was off by 980). It now adds.
- Pot HUD did not zero after payout and had no live pile total.
- Host dropped client intents that arrived during animations. They are now buffered per seat.
- Rankings panel overflowed or vanished (width too large, saved setting off).
- Settings General tab was clipped at 648px height. It now sits in a scroll area.
- Pot stack sat beside your betting circle. It moved to the far side of the board.

## Tests
- `tests/test_poker.gd` plus the parse gate in `tests/test_scripts_parse.gd`.
- Online two-process test: `godot --headless -s tests/net_poker_host.gd`, then two shells running `tests/net_poker_client.gd`.
- The in-editor suite has not been run for these changes.

## Still open
- Chip tray for every seat (only your seat has one).
- Better pot area.
- Dealer at the center of the table.
- Better dealing and river reveal animations.
- Online Hold'em and the new pot position are not checked in a live game.
