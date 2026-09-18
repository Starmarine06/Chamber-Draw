# Chamber Draw

**Every draw could be your last.**

*A fast, chaotic party card game built in Godot — shed your hand, dodge the bombs, and pray the Chamber misses you.*

<p align="center">
  <video src="chamber-draw-promo-2026.mp4" controls playsinline style="max-width:100%; border-radius:12px;"></video>
</p>

---

## The pitch

Chamber Draw is a multiplayer shedding card game that mashes the flow of **Uno** with the dread of **Exploding Kittens** and the push-your-luck rush of **Russian Roulette** — then turns the heat up with a double draw pile, King-of-the-hill action cards, and a brand-new *Chamber Draw* nobody survives on luck alone.

2–7 players sit around a 3D poker table full-screen on the table. Match colors or numbers, play savage action cards, and decide — game after game — whether to play it safe... or pull from the pile and find out what the Chamber has in store. 10–20 minutes a match. Alliances shift every single turn.

## What makes it special

- **Two hidden draw piles.** Deck A and Deck B both hide bombs, but nobody knows the split. Read the table, dodge the hot pile, and *force your rivals into it*.
- **The Chamber Draw.** Pull a Bomb and you immediately spin the 6-card Chamber: **Live** (you're gone), **Backfire** (an opponent pays), **Lucky Draw** (bonus card, keep going), or **Blank** (this time, at least). The Chamber reshuffles after every pull — the odds never get comfortable.
- **A deck packed with malice.** Swap Hands, Peek (reorder the top 3 — secretly), Choose a Deck (steer an opponent into danger), Rotate Decks (burn the table's reads), the rare Draw Ten hand-flooder, Wild Color, and the villainous Wild Sabotage.
- **Props, not placeholder UI.** A real 3D poker table with per-seat characters, hand-some animated card flights (deal, draw, discard), a live discard pile that shows the actual top card, procedural night sky, Kenney UI art, and a 30-second turn timer ring tinted to the current player's color.
- **Full table manners.** Uno-style Jump-In responses, stackable +N draw cards (any value, any color — red +4 on green +2), cross-color Skip/Reverse matching, and a physical turn-order ring so nobody argues who's next.
- **Nobody gets left behind.** This is why games happen again. Stay in it: Extra Life cards bank up to 2 spare lives; respawn cards can drag the last eliminated player back into the fight; and eliminated players become **spectators** watching the table (Uno-privacy — hands stay hidden).

## How it works

The rules are simple enough for a party, deep enough for a grudge.

1. **Get dealt in.** Everyone gets 7 cards from the two decks (the deal is animated — card-backs fly from the deck to every seat).
2. **Play a card** that matches the pile's color *or* number, or sling an action/wild card and make the table groan.
3. **Can't — or shouldn't — play? Draw.** And *from which pile?* That's the whole game. This is your choice, and it's the only one with a bomb in it.
4. **Boom?** The Bomb hits the Chamber. Resolve it and keep playing — alive, stacked, or... not.
5. **Dump your hand.** First player to shed every card wins. In **Last One Standing**, be the last player at the table.

Forced draws (Draw Two/Four/Ten) are **Bomb-proof** — they only pull safe cards, so you can weaponize them without self-sabotaging. Voluntary draws carry the full risk. Balance lever, engineered in.

### The lineup

| Card | What it does |
|---|---|
| **Numbers 0–9** (Red, Green, Orange, Purple) | Match color or number. |
| **Skip / Reverse** | Steal a turn / flip the order (matches ANY color of the same action). |
| **Draw Two / Draw Four / Draw Ten** | The next player draws 2, 4, or a brutal 10 — and **stacks**: answer with any +N of your own. |
| **Swap Hands** | Trade your whole hand with an opponent. |
| **Peek** | Secretly view the top 3 of a pile — reorder them to your liking. |
| **Choose a Deck** | Force an opponent's next draw onto the pile *you* want them on. |
| **Rotate Decks** | Shuffle both piles back into two fresh ones — erases every hot-pile read. |
| **Extra Life** | Bank a spare life (up to 2). Consumed automatically when you'd die. |
| **Wild Color / Wild Sabotage** | Pick the color — Sabotage also names the *next player to draw*. |
| **Bomb / Diffuse** | Bomb triggers the Chamber. Diffuse cancels it — and has one use. |

## Modes

- **Shedding Race** *(default)* — first to empty their hand wins. A Live Chamber result hits you with 4 penalty cards and a skipped turn instead of knocking you out. Fast and party-friendly.
- **Last One Standing** — a Live Chamber result eliminates you. Keep playing until only one player remains. Higher tension, sharpened knives.

## Play it anywhere

- **Offline vs. AI** — brave the Chamber against a table of bots. A full **guided tutorial** walks you through every mechanic before you touch a real match.
- **Online (host-authoritative)** — lobby up with friends via **Epic Online Services P2P** and play over the internet. The host holds the truth and every client gets a private hand snapshot — hiding hands is built into the protocol. Snap, reconnect-safe, 2–7 players.

### Controls

| Input | Action |
|---|---|
| **Click a card** | Play it (stackable Draw cards highlight when you're on the hook). |
| **Click a deck** | Draw from that pile. |
| **1–9 / 0** | Play hand card by index · stack a Draw card when targeted. |
| **A / B** | Draw from Deck A / Deck B · pick a forced-draw pile. |
| **Esc / ❚❚** | Pause (offline). |

## Run it

Fully built out — you can even skip setup:

- **Prebuilt binaries:** `builds/` contains the Windows executable and a **Chamber Draw Installer.exe**.
- **From source** — requires **Godot 4.7+**:
  1. Open this folder in the Godot editor (import `project.godot`).
  2. Run `scenes/menu.tscn` (the main scene).
  3. Hit **Play vs AI**, run the **Tutorial**, or create an online lobby.

> **Online note:** EOS login needs a `devtool_credential_name` in `eos_config.local.json`, or set `login.method` to `"anonymous"` to hop right in.

## Quality under the hood

- **140 tests · 10 suites · deterministic.** The rule engine (`game_state.gd`) and deck/chamber systems are unit-tested and flake-proof (randomness is pinned in test fixtures), so the math you play is the math that shipped.
- **Host-authoritative by design.** The single source of truth on the host; clients send intents, receive snapshots.
- **Balance levers, not hacks.** Every card count, bomb count, chamber-odds knob, and pile split is a named constant at the top of `card_database.gd`. Tune the lethality without touching logic.
- Headless parse-clean, editor errors list zeroed.

## Project map

```
scenes/game_3d.tscn   The 3D poker table world (decks, discard, seats)
scenes/player_ui.tscn The 2D hand layer
scenes/game.tscn      Entry scene (menu/lobby/game)
scripts/game.gd       Game screen, HUD, input, host/relay logic
scripts/game_state.gd Authoritative rules engine (turn order, chamber, wins)
scripts/deck_manager.gd  Two-pile Multi-Deck System + chamber deck
scripts/card_database.gd The full tunable card pool
scripts/eos_manager.gd   EOS login, lobbies, P2P relay, roster mapping
tests/test_*.gd       140 deterministic tests across 10 suites
```

For the full design intent — balance levers, tuning curves, art direction, accessibility choices — see **[Chamber_Draw_Game_Design_Doc.md](Chamber_Draw_Game_Design_Doc.md)**.

---

*Playing card art pending an asset upgrade — the current cards are rendered procedurally, so every build looks clean and consistent.*