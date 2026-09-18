# Chamber Draw — Game Design Document

**Working Title:** Chamber Draw
**Genre:** Multiplayer party card game
**Engine:** Godot 4.x
**Players:** 2–7 (recommended sweet spot: 4–6)
**Platform:** PC / Mobile (cross-platform via Godot export)
**Networking:** Epic Online Services (EOS) for lobbies/matchmaking, ENet or WebRTC for gameplay sync
**Session Length:** 10–20 minutes per match

---

## 1. High Concept

Chamber Draw is a fast-paced, chaotic card game where players race to empty their hand while avoiding a hidden threat buried in the draw pile. It blends classic shedding-game mechanics (match colors/numbers, play action cards) with an escalating risk mechanic: every time someone draws from the pile, there's a chance they trigger the **Chamber** — a tense mini-draw that can cost them the game, cost them cards, or leave them completely unscathed. Alliances shift every round as players use Sabotage and Wild cards to redirect danger toward each other.

**Tagline:** *"Every draw could be your last."*

---

## 2. Player Fantasy

Players should feel:
- The satisfying flow of a shedding game (Uno-like) — matching, chaining, dumping action cards on opponents.
- The dread/thrill spike of a hidden-threat game (Exploding Kittens-like) — "is THIS the card?"
- The adrenaline of a push-your-luck gamble (Russian Roulette-like) — "do I draw again, or play it safe?"

---

## 3. Core Loop

1. Player takes their turn: play a matching card, or play an Action/Wild card.
2. If unable/unwilling to play, player must **Draw**.
3. Drawing has a chance of pulling the hidden **Bomb** card.
4. If Bomb is drawn → **Chamber Draw** sequence triggers (see Section 6).
5. Turn passes to the next player (unless modified by an Action card).
6. Game ends when one player empties their hand, or all but one player is eliminated (mode-dependent — see Section 9).

---

## 4. The Deck

Total deck size scales with player count: **Base deck = 80 cards + 1 Bomb per 4 players (min 1, max 3, for the 2–7 player range)**.

### 4.1 Number Cards (56 cards)
Four colors (Red, Blue, Green, Yellow), numbers 0–9. Two of each number/color except 0 (one of each).
Standard shedding rule: match by color or number.

### 4.2 Action Cards (32 cards, split evenly across colors)
| Card | Effect |
|---|---|
| **Skip** | Next player loses their turn. |
| **Reverse** | Turn order flips direction. |
| **Draw Two** | Next player draws 2 cards (no Chamber risk from forced draws — see 4.4 note). |
| **Draw Four** | Next player draws 4 cards (no Chamber risk). Rarer than Draw Two (2 copies total instead of 4). |
| **Draw Ten** | Next player draws 10 cards (no Chamber risk). A single, very rare "hand-flooding" card — only 1 copy in the deck regardless of player count. Intended as a rare comeback-denial/panic card, not a reliable strategy. |
| **Swap Hands** | Trade your entire hand with any opponent. |
| **Peek** | Secretly view the top 3 cards of the draw pile — you may reorder them. |
| **Extra Life** | Play this from your hand at any time (even off-turn) to bank one extra life. Banked lives are consumed automatically the next time you would be eliminated by a Live Chamber result, instead of eliminating you. Max 2 banked lives per player. |

> **Card count note:** with the new Draw Four, Draw Ten, and Extra Life cards added, total Action Cards rise from 18 to 32. To keep the deck's overall risk density from 4.4 consistent, the Number Card pool is trimmed slightly (see updated deck total in Section 12).

### 4.3 Wild Cards (6 cards)
| Card | Effect |
|---|---|
| **Wild Color** | Change the active color to any color. |
| **Wild Sabotage** | Change the active color AND force the next drawer to be a player of your choice (instead of the next-in-turn-order player). |

### 4.4 The Chamber Mechanic (special cards, kept in a separate mini-deck)
- **Bomb Card(s):** 1–3 in the main deck depending on player count. When drawn, immediately triggers a Chamber Draw.
- **Diffuse Card(s):** 2–3 in the main deck. Holding one lets you cancel a triggered Chamber Draw on yourself, OR force a re-shuffle of the Bomb back into the deck at a random position instead of resolving it.

> **Design note:** Forced draws from "Draw Two" pull only from the safe number-card pool by default (configurable house rule) — this keeps action-card chains from feeling like unfair ambushes, while voluntary draws (choosing to draw because you have no play) carry full Bomb risk. This is the key balancing lever; see Section 8.

### 4.5 Multi-Deck System (core mechanic)

Instead of a single draw pile, the table always has **two active draw piles** ("Deck A" and "Deck B"), each seeded with its own share of the Bombs and Diffuses from Section 4.4. Piles are visually identical from the back — players know bombs exist across both, but not the exact split.

On a normal draw, the current player **chooses which pile to draw from**. This adds a light bluffing/read-the-table layer: if a pile has been drawn from heavily without producing a Bomb, players may (correctly or not) assume it's "hot."

Two new cards manipulate this system:

| Card | Effect |
|---|---|
| **Choose a Deck** | Force a chosen opponent's *next* draw to come from a specific pile (A or B) instead of letting them pick. |
| **Rotate Decks** | Merge both piles together, reshuffle, and redeal them back into two new piles of equal size. This erases any "hot pile" reads players had built up and re-randomizes Bomb distribution. |

Both cards are part of the Action Card set (included in the 32-card count above).

> **Design intent:** the Multi-Deck System turns the "should I draw?" tension of Section 6 into "should I draw, and from where?" — giving skilled/observant players a slight edge while Rotate Decks keeps any one pile from becoming a guaranteed "safe" choice for too long.

---

## 5. Turn Structure

1. **Start of turn** — resolve any pending effects (e.g., must-draw-two).
2. **Main action** — play one card, or draw one card (choosing Deck A or Deck B, per Section 4.5) if no valid play/choose not to play.
3. **Chamber resolution** (if triggered).
4. **End of turn** — pass turn per current direction/skips.

---

## 6. The Chamber Draw (signature mechanic)

When a player draws the Bomb, they immediately draw from the **Chamber Deck**: a small 6-card deck refreshed each time it's used.

**Chamber Deck composition (default): 6 cards**
- 1 × **Live** — the drawing player is eliminated (or loses 2 lives, mode-dependent).
- 3 × **Blank** — nothing happens; play continues normally.
- 1 × **Backfire** — the *previous* player who could have drawn instead is penalized (loses a card).
- 1 × **Lucky Draw** — the drawing player gets to draw one bonus card from the main deck and continue their turn.

This 6-card structure keeps the "1-in-6" Russian Roulette flavor intentional and legible to players, while softening pure elimination odds with alternate outcomes so games don't end abruptly on bad luck alone.

After a Chamber Draw resolves, the Chamber Deck is reshuffled for next time, and the Bomb card is returned to the main deck at a random position (unless a Diffuse was used to remove it for the rest of the round).

---

## 7. Win / Lose Conditions

Two supported modes:

### Mode A — Shedding Race (default, faster, party-friendly)
- First player to empty their hand wins.
- Being hit by a **Live** Chamber result doesn't eliminate you — instead you draw 4 penalty cards and forfeit your next turn.
- Best for casual groups; nobody is knocked out early.

### Mode B — Last One Standing (classic elimination)
- Live Chamber result eliminates the player immediately.
- Game continues until 1 player remains.
- Higher tension, better for smaller groups (3–5 players) and short sessions.

Match settings screen lets the host pick the mode before starting.

---

## 8. Balance & Tuning Levers

| Lever | Effect |
|---|---|
| # of Bombs in deck | More bombs = more frequent tension, faster games |
| # of Diffuse cards | More diffuses = more player agency, less pure luck |
| Chamber Deck odds (Live/Blank/etc.) | Adjusts lethality curve |
| Forced-draw Bomb immunity | Determines whether action-card chains can "gift" danger to others |
| Player count scaling | Bomb count scales with lobby size (2–7) to keep odds consistent per player |
| Draw Four / Draw Ten copy count | Controls how often hands get flooded; Draw Ten intentionally kept to 1 copy to stay a rare swing card |
| Extra Life max banked count | Caps how "safe" a player can make themselves; 2 is the recommended ceiling |
| Bomb/Diffuse split between Deck A & B | Can be even (neutral) or skewed each match for variety; Rotate Decks resets any skew |

Recommended default odds keep the *effective* chance of a Live result on any given voluntary draw around **4–7%**, rising as the deck thins later in the round — mirroring the escalating tension curve of Exploding Kittens.

---

## 9. Multiplayer Structure

- **Lobby creation/matchmaking:** Epic Online Services (EOS) Lobby + Sessions interface (free tier, cross-platform, P2P NAT punchthrough).
- **Gameplay sync:** Godot's high-level multiplayer (ENetMultiplayerPeer for LAN/direct, or WebRTC for P2P over EOS relay) with **host-authoritative** logic — the host resolves all draws/shuffles/Chamber outcomes to prevent cheating via manipulated client state.
- **Reconnect handling:** Player state (hand count, lives, turn position) is snapshotted so a dropped player can rejoin an in-progress match within a grace window.
- **Spectator mode:** Eliminated players (Mode B) can spectate remaining players' public state (hand counts, played cards) but not opponents' hidden hands.

---

## 10. Art & Tone Direction (kept original to avoid IP overlap)

- Avoid any direct visual/thematic reuse of Exploding Kittens' cat illustrations or Uno's exact card back/logo styling.
- Suggested direction: a stylized "old west poker saloon meets fireworks factory" aesthetic — playing into the "Chamber"/gamble theme without literal gun imagery on cards (use a stylized revolving cylinder icon, fuse-and-spark bomb icon, etc.).
- Card back design: a simple geometric "loaded chamber" motif (six-segment circle) ties into the Chamber Deck theme.
- Sound design: a distinct "click" tension sound on every Chamber Draw regardless of outcome, to build suspense before reveal.

---

## 11. Accessibility & Content Considerations

- All "roulette" framing is abstracted into card draws — no realistic firearm imagery or sound effects, keeping the game platform-friendly (mobile app stores, younger audiences) and less likely to raise content-rating issues.
- Colorblind-friendly card design: pair each color with a distinct icon/shape, not just color, for number cards.
- Option to disable elimination entirely (Mode A) for players sensitive to "you're out" party-game dynamics.

---

## 12. Suggested Next Steps

1. Lock in final card counts per player-count tier (2p, 3–4p, 5–6p, 7p).
2. Prototype the core loop in Godot as local-only (hot-seat) to validate pacing before adding networking.
3. Build the Chamber Draw as an isolated, testable subsystem (pure function: deck state in → outcome out) so it's easy to unit test odds.
4. Layer in EOS lobby/matchmaking once core loop is fun locally.
5. Playtest Mode A vs Mode B with real groups to see which resonates more before committing to a default.

---

*Document version 1.0 — ready for iteration as design decisions are finalized.*
