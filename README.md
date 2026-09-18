# Chamber Draw — Godot Prototype (Core Logic)

This is a **local, no-art, no-networking** prototype of the core card game
loop described in `Chamber_Draw_Game_Design_Doc.md`. Its only purpose is to
prove out the rules engine — Multi-Deck System, Chamber Draw resolution, all
action/wild cards, and both win-condition modes — before any UI, art, or
Epic Online Services networking is layered on top.

**Built for Godot 4.2+.** It has not been run inside the Godot editor itself
(no engine binary was available in the environment this was written in) — it
has only been carefully reviewed line-by-line for correct GDScript 4.x syntax
and logic. Please open it in Godot and run it as your first step; see
"If something doesn't run" below for what to check.

## How to run

1. Open Godot 4.2 or later.
2. "Import" this folder as a project (select the `project.godot` file).
3. Open `scenes/Main.tscn` and press **F6** (Run Current Scene).
4. Watch the on-screen log (and the Godot output console) — it simulates a
   full game between 4 simple AI players and should always terminate with
   a printed winner, e.g.:
   ```
   === GAME OVER — Winner: Player 3 (after 187 turns) ===
   ```

You can tweak `num_players` (2–7) and `mode` (Shedding Race / Last One
Standing) on the `Main` node in the Inspector, or directly in `main.gd`.

## File structure

```
chamber_draw_godot/
├── project.godot
├── icon.svg
├── scenes/
│   └── Main.tscn          # test harness scene (Control + log label)
└── scripts/
    ├── card.gd            # Card resource: type/color/number/action_id
    ├── card_database.gd   # builds the full tunable card pool
    ├── chamber_deck.gd    # the 6-card Chamber mini-deck (Live/Blank/etc.)
    ├── deck_manager.gd    # the two-pile Multi-Deck System + rotation
    ├── player_data.gd     # hand, banked Extra Lives, eliminated flag
    ├── game_state.gd      # the core rules engine — turns, play, draw, win
    └── main.gd            # AI-driven simulation harness (no UI/art yet)
```

## What's implemented

- Full card pool: numbers, Skip/Reverse/Draw Two/Draw Four/Draw Ten,
  Swap Hands, Peek, Extra Life, Choose a Deck, Rotate Decks, Wild Color,
  Wild Sabotage, Bombs, and Diffuses — all counts are named constants at the
  top of `card_database.gd` so balance tuning never requires touching logic.
- The Multi-Deck System: two draw piles, player choice of which to draw
  from, Choose a Deck forcing an opponent's next pull, Rotate Decks
  reshuffling/redealing both piles.
- The Chamber Draw: reshuffles after every use, auto-Diffuse cancellation
  when a player is holding one, and all four possible outcomes (Live,
  Blank, Backfire, Lucky Draw).
- Both win modes: Shedding Race (Live = penalty + skipped turn, race to
  empty hand) and Last One Standing (Live = elimination unless a banked
  Extra Life absorbs it).
- Forced draws (Draw Two/Four/Ten) are immune to triggering the Bomb, per
  the design note in the GDD — a Bomb pulled during a forced draw is
  reshuffled back in and redrawn instead.

## What's intentionally NOT implemented yet (next steps)

- **Any real UI or art.** This is pure logic + a debug text log.
- **Human input.** The harness only drives dumb AI (first valid card, else
  draw from the fuller pile) so the rules engine can be validated in
  isolation. A real player-facing scene will need to call the same
  `GameState` methods (`play_card`, `draw_card`, `get_valid_plays`) in
  response to UI clicks instead of the AI's automatic choices in `main.gd`.
- **Peek's reorder step.** `deck_manager.gd` has `reorder_top()` ready to
  wire up, but the AI harness doesn't use it (it just peeks and moves on).
- **Off-turn Extra Life play.** The GDD allows playing Extra Life "at any
  time, even off-turn"; this prototype simplifies it to a normal on-turn
  action for now. Supporting true off-turn interrupts needs a small event/
  reaction window added to the turn structure — worth doing once real
  networking is in place, since interrupts are also a networking sync
  concern.
- **Epic Online Services networking.** This prototype is entirely local/
  synchronous. The plan is to keep `GameState` as the single source of
  truth run by the host, and have clients send intents (`play_card`,
  `draw_card` calls) via RPC for the host to validate and apply — this
  file structure was written with that host-authoritative split in mind.

## If something doesn't run

Since this hasn't been test-run in the actual editor yet, if you hit an
error on first run, the most likely spots (in rough order of likelihood) are:
- A typo in a `match` case string (e.g. `"draw_two"` vs `"draw_two "`) —
  these are matched against `action_id` strings set in `card_database.gd`.
- Godot version mismatch — this targets 4.2+ syntax (`@export`, `@onready`,
  typed arrays like `Array[Card]`). Godot 3.x will not run this as-is.
- `scenes/Main.tscn`'s `ext_resource` path — should be fine as long as the
  folder structure above is preserved.

Feel free to paste back any error message from the Godot console and I'll
fix it directly.
