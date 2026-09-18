# Chamber Draw — Project Memory

Godot 4.7.2 (engine: `X:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`).
Epic Online Services multiplayer (EOS P2P) via `addons/epic-online-services-godot`.
Hybrid UI: editor-built 3D table scene + programmatic 2D overlays. 2–7 players;
`SHEDDING_RACE` mode vs AI or online.

## Current status
- **3D table edition (current):** game.gd instances `scenes/game_3d.tscn` (poker table +
  Marker3D nodes) full-screen in a SubViewport; local hand is summoned around the
  `CenterCards` marker of `scenes/player_ui.tscn`; opponent seats get a Kenney character
  GLB at their  `PlayerN` marker (lowered onto the felt via `CHAR_SEAT_OFFSET` — the GLB origin is above
  the feet; only the LOCAL hand ever renders — Uno-style privacy).
  All buttons/panels use the Kenney UI pack textures; sounds from `kenney_ui-pack/Sounds`;
  **Dealing animation:** at game start, card-back ghosts fly from the deck to each player
  (7 cards per player, staggered 0.08s, accelerating), then the starter card flips onto
  the discard, a random player is selected with a "Player X goes first!" notification,
  and the game begins. Online: host runs the animation, then broadcasts the snapshot.
  (click-a card play, tap-a deck draw, switch-a buttons, click-b extra life/resume/lucky,
  switch-b draw cards/jump-in/bomb/chamber-LIVE/game-over, tap-b forced-draw deal-out/
  swap/rotate/peek/chamber ticks); keyboard shortcuts (1–9 play hand card, A/B draw). Decks are clickable ANY time it's
  the local player's turn (invisible zones projected from the Deck A/B markers; subtle
  emissive glow on the piles). Deck labels show "N cards • M% chamber" (per-deck bomb
  odds; bomb counts ride in snapshots for online). Opponent labels show lives:
  "N cards • M lives". Procedural animations: character idle bob + turn pop,
  a bouncing "YOUR TURN!" banner when control passes to the local player,
  **Spectator mode:** eliminated players enter SPECTATING state — input disabled,
  character removed from table, viewing only. **Respawn cards:** NOT seeded at
  setup — they exist in the deck ONLY while a player is eliminated (2 per dead
  player, injected by `game_state.sync_respawn_cards()` right after the death/
  chamber sequence) and are removed when nobody's dead. Eliminated seats skip
  turns, so an ALIVE player drawing a Respawn card revives the MOST RECENTLY
  eliminated player (`last_eliminated_index`) with 4 fresh cards. Respawn plays a
  banner + hand/character pop-in animation. **Discard pile** renders the actual
  top card face (CardNode in a 128x192 SubViewport projected onto a Sprite3D),
  not a flat color box + text label.
  ghost card flights hand→discard, deck→hand, and staggered card-back flights
  for forced draws (Draw Two/Four/Ten choose a deck first via the same deck-choice
  prompt; game_state `_forced_draw` honors `options.chosen_pile`, AI picks random).
  **Player colors:** every seat gets a color from the 8-color palette in
  `game_globals.gd` (`PALETTE`/`PALETTE_NAMES`). Offline: local player picks in the
  main menu (`GameGlobals.my_color_idx`), AI get random remaining colors
  (`game._assign_offline_colors`). Online: each member publishes their pick as the
  public lobby member attribute `ATTR_COLOR` (`EOSManager.set_my_color`); the host
  resolves collisions in seat order (`game._apply_roster_identity` also applies
  roster display names). `PlayerData.color`/`color_idx`; color_idx rides every
  snapshot. Colors show on: opponent name labels (Label3D), the local hand label,
  the lobby roster (● swatch), and the **turn border** — a full-screen Panel glow
  (`game._update_turn_border`) in the local player's color that pulses during
  `HUMAN_TURN` and `FORCED_DRAW_DECK_CHOICE`. Menu + lobby both use a toggle-swatch
  button row (`_make_swatch_button`, ButtonGroup-exclusive).
  **Target chooses deck:** when a Draw Two/Four/Ten is played, the TARGET player
  (not the attacker) chooses which deck to draw from. `advance_turn` does NOT
  auto-skip a pending forced-draw target (see `resolve_forced_draw`), so the
  target lands ON their turn with an immediate "you must draw N" prompt; the
  deck zones stay highlighted/clickable during `FORCED_DRAW_DECK_CHOICE`. The
target may instead play any Draw Two/Four/Ten to STACK: `game_state`
  `_start_or_stack_forced_draw()` adds the card's amount to
  `pending_forced_draw_count` (memory from last session's log does not cover
  this — see the session log entry at the bottom) and re-targets the next
  player. Any +N stacks on any other +N (color and value are both irrelevant).
  NONE-color Draw Ten stacks go through the color popup first.
  Choosing a deck draws the cards and CONSUMES the target's turn
  (`resolve_forced_draw` clears skip + advances). Human target gets a clickable
  prompt; AI auto-picks random, OR stacks a Draw card ~60% of the time
  (`_process_ai_turn`). Keyboard A/B picks a deck, number keys 1-9/0 stack a
  Draw card; stackable Draw cards are highlighted during
  `FORCED_DRAW_DECK_CHOICE`. Target timeout forfeits the choice — the pending
  forced draw resolves instead of stacking the generic 4-card penalty
  (`_on_turn_timer_expired`).
  AI pauses: 1.2–1.8s before its first move, 0.9–1.5s between moves.
  **Turn timer:** 30 seconds per turn; if a player doesn't act in time, they draw 4 cards
  (2 from each deck) and their turn ends. Visual timer bar (green→yellow→red) shown
  above the hand; hides during popups (color/target/deck choice) but doesn't reset.
  Timer RING is tinted to the current player's color (`turn_timer_ring.set_color`,
  driven by `game._current_timer_color`), blending to red only under 25% left.
  Offline pause: Esc or the ❚❚ button in the top bar freezes all timers/input
  (`_paused` guard in `_process` + play/draw/key handlers) with a Kenney-styled
  Pause overlay (Resume / Main Menu); disabled online and during chamber/game-over. Skybox is a procedural night sky (ProceduralSkyMaterial,
  BG_SKY + sky ambient + light fog).  A Camera3D/XRCamera3D placed inside game_3d.tscn is used if present (cameras under
  PlayerN markers, picked up by recursive `_find_all_cameras` — each player seat gets
  its own camera, switched via `_switch_camera_to_seat`). Otherwise the script frames
  one from the marker bounds. AI "thinking"
  pauses: 1.2–1.8s before its first move, 0.9–1.5s between moves.
- **Offline vs-AI: stable & verified** (logic unchanged; headless boot of game.tscn clean).
- **Online (EOS P2P): code complete, NOT yet E2E-tested.** Host-authoritative turn relay +
  per-client private snapshots implemented; blocked on a credential setting (below).
- Editor Errors tab is clean — all warnings resolved.

## Run commands
- Headless parse check: `Godot_v4.7.2-stable_win64_console.exe --headless --path "X:\Godot Games\chamber-draw" --quit-after 3` — expect zero SCRIPT ERROR / Parse Error lines.
- Main scene: `scenes\menu.tscn`. Editor is Godot 4.7.2, connected via godot-ai MCP (uvx, godot-ai==3.2.5).

## Scripts
- `scripts/game.gd` — game screen, HUD, all input, host/relay logic. `enum State` at line 8.
  Reads markers by name from game_3d.tscn: `Deck A`, `Deck B`, `Table top` (discard),
  `Player1`..`Player6`. Seat i (1-indexed) → `Player{i}` marker; 7th player wraps to
  `Player1` (bottom) with a nudge. Camera is framed programmatically from marker bounds
  or uses per-seat cameras from PlayerN markers.
- `scenes/game_3d.tscn` — editor-built 3D world (poker table FBX + markers, NO camera).
- `scenes/player_ui.tscn` — 2D layer; `CenterCards` Marker2D anchors the local hand fan.
- `scenes/game.tscn` — entry scene (Control root + game.gd); menu/lobby/eos load this.
- `scripts/game_state.gd` — authoritative game rules, `get_valid_plays` (line 86). `Card`, `PlayerData`.
- `scripts/deck_manager.gd`, `card_database.gd`, `chamber_deck.gd` (in deck_manager) — deck/chamber logic.
  When a draw pile runs out, `_split_discard_into_piles()` shuffles the discard and splits
  it 50/50 between BOTH piles (not dumped into the exhausted deck).
- **Chamber distribution:** 2 bombs per player total (N per deck, placed exactly by
  `DeckManager.setup`; diffuses scattered randomly). `bomb_count_for(n)` = n*2.
  **Bombs are one-time use:** once diffused, they are discarded permanently (not returned
  to the deck). When all bombs are diffused, remaining players vote to continue (bombs
  redistributed) or end (all remaining players win).
- **Extra Life:** 2 per player (`extra_life_count_for(n)` = n*2); a consumable that stacks
  up to TWO lives (`PlayerData.MAX_BANKED_LIVES = 2`), consumed one-per-elimination on chamber LIVE.
- **Deck shuffling:** `DeckManager.setup` shuffles the safe pool, DEALS it alternating
  between decks (even mix, no contiguous half-pile clumps), then shuffles each pile
  independently; `_split_discard_into_piles()` and `rotate_decks()` deal alternately too.
- `scripts/card_node.gd` — playable card control (class_name `CardNode`).
- `scripts/eos_manager.gd` (autoload) — EOS login, lobby, P2P relay, roster/seat mapping.
- `scripts/eos_config.gd` (autoload) — EOS config loader (reads `eos_config.local.json`).
- `scripts/lobby.gd`, `scripts/menu.gd` — lobby UI (`lobby.tscn`) and main menu
  (has an EXIT GAME button → `get_tree().quit()`).
- `scripts/game_globals.gd` (autoload) — is_online / own_seat / num_players / game_mode,
  plus the shared seat-color palette `PALETTE` (8 Colors) `/PALETTE_NAMES` and
  the local player's pick `my_color_idx` (menu offline + lobby online both set it).
- `scripts/turn_timer_ring.gd` — custom-drawn circular turn timer. `set_pct()` for
  remaining fraction, `set_color()` tints the ring to the current player's seat color
  (blends to red below 25% left); the number label is tinted too.

## Fixed bugs (this session — do not reintroduce)
1. **Click handler signature (Godot 3→4 rename):** `card_node.gd` — `input_event.connect(_on_input)` is
   gone in Godot 4. Use `gui_input.connect(_on_input)` AND the handler must be
   `func _on_input(event: InputEvent)` (1 arg). A 3-arg method cannot connect to `gui_input`
   (1-arg signal) — the connect silently fails and cards never receive clicks.
2. **`else []` ternary typed-array trap:** `game.gd` `_refresh_hand` crashed with
   `Trying to assign an array of type "Array" to "Array[int]"` because the `else []` branch is an
   UNTYPED array literal. Never write `var arr: Array[int] = X if cond else []` — split into if/else
   with a typed `= []` default.
3. **Variant-inference parse errors (project has strict typing):** `var x := f.get_attribute(...)`,
   `:= min()/max()/lerp()`, `:= int`. all infer Variant and fail to parse here. Use explicit
   `: float`/`: Variant`/`: int` types. Fixed in card_node.gd, eos_manager.gd (7 sites),
   game.gd, lobby.gd, eos_config.gd.
4. **`class_name EOSConfig` collision:** autoload `EOSConfig` + `class_name EOSConfig` collided
   ("hides an autoload singleton") — removed the class_name.
5. **`OS.get_user_name()` doesn't exist** in 4.7 — use `OS.get_environment("USERNAME")`.
6. **`Node3D.look_at()` needs the node IN the tree** — call `add_child(camera)` before
   `look_at()` (or use `look_at_from_position`), else "Node not inside tree".
7. **Lone `\r` at EOF breaks parsing** — a file ending `...true\r` with no `\n` fails with
   "Stray carriage return character in source code". Always end .gd files with a newline.
   (Project source uses CRLF line endings.)
8. **Colored Buttons need real StyleBoxFlat objects, not `duplicate()` chains:** `game.gd`
   `_make_color_button` builds a fresh StyleBoxFlat per state (normal/hover/pressed) with
   the player-selected color (auto dark/white font via `Color.get_luminance()`); the `focus`
   stylebox is `StyleBoxEmpty`. Reuse of a single shared stylebox across states makes the
   pressed/hover feedback silently identical — build new ones.
9. **EOS member-attribute values arrive as Strings:** `HLobbyMember.get_attribute(name)`
   returns a Dictionary with `value` (usually a String). Coerce with
   `raw.to_int() if raw is String else int(raw)`, never compare a raw Variant `<` an int
   (e.g. `_member_color_idx` in eos_manager.gd / lobby.gd roster swatches).
10. **`CardNode.setup` omitted `card_height = h`:** caused any resized card instance (e.g. the 128x192
    discard pile top card in `_discard_vp`) to render only the top 120 pixels of the card face, leaving
    the bottom 72 pixels empty and pitch black.
11. **`LineEdit` alignment property in Godot 4:** `LineEdit` uses `.alignment = HORIZONTAL_ALIGNMENT_CENTER`,
    not `.horizontal_alignment`.

## Online architecture (P2P, host-authoritative)
- Host peer id = 1. Seats = index into `game.players`. Host runs `game.setup()` on its local
  GameState; clients build a render-only GameState (`game.deck = DeckManager.new()`) and receive
  **snapshots**. Deck contents are never sent.
- **Intents:** clients `rpc_id(1, "_rpc_intent", intent)`; host also self-calls it directly.
  `"draw" {pile}`, `"play" {hand_index, options}`, `"diffuse" {use}`, `"hello"` (broadcast once
  players exist). Guards: game must exist; play/draw must be that seat's turn; diffuse only when
  `pending_diffuse_player_index == seat`.
- **Snapshots:** `_make_snapshot(seat)` exposes only that seat's real hand; all other seats get
  same-sized placeholder dicts (`CardDatabase._make(NUMBER, 0, -1, "", "")`). `_broadcast_snapshot()`
  fans out per roster entry, skipping host. Fields: mode, current_index, direction, active_color,
  active_number, players[], deck_a/b_count, discard, pending_bomb, pending_diffuse_player_index,
  winner_name, game_over, forced_pile_for_player, override_next_player_index,
  chamber_reveal {seat, result}.
- **Bomb/chamber:** pending bomb + diffuse in hand → pending snapshot + wait for diffuse intent;
  `use` → `resolve_bomb(true)`; `use=false`/no diffuse → single `game.chamber.draw()` +
  `resolve_bomb_with_result` (NO double draw). `_pending_chamber_reveal` merges into + clears on
  next snapshot. Own-seat reveal plays preset result (no local draw).
- **Peek:** client plays peek with `{hand_idx, chosen_pile}` → host `deck.peek(pile, 3)` →
  host self = `_show_peek_result_ui`, remote = `_rpc_private` "peek_result".
- **Jump-in (matching-card response):** after ANY playable card is played, every hand
  holding an exact copy (incl. the actor) may play it out of turn. `game_state.gd`:
  `_finish_play()` opens the window + emits `jump_in_available(candidates)` instead of
  advancing when copies exist; `jump_in(i)` consumes the copy (chains keep the window
  open), `close_jump_in_window()` advances. Only NUMBER + choice-free ACTION cards
  (skip/reverse/draw_two/draw_four/draw_ten/extra_life/rotate_decks) can be answered.
  game.gd: `JUMP_IN` state, `_on_jump_in_available`, prompt UI (Kenney buttons),
  4s window (`JUMP_WINDOW_TIME`), offline AI answers after 0.8–1.4s. Snapshot fields:
  `jump_in_open`, `last_played_card`, `jump_in_candidates`; intent `"jump_in"`.
- **Known caveats (accepted):** `pending_bomb`/`pending_diffuse_player_index` visible to all seats;
  disconnected client on its turn stalls the game; client placeholder hands render as backs.

## Testing checklist (driven by user — do NOT auto-run the game/min it)
- **Test 1 (offline):** Play vs AI, 4 players → plays/draws/actions/diffuse/chamber to game over.
- **Test 2 (online):** two editor instances → lobby → Start. BOTH instances must be logged in.

## Blocked / pending
- **EOS credential:** `devtool_credential_name` in `eos_config.local.json` is EMPTY — required for login
  (`eos_config.local.json`, product f8659ed259c243488e03fae58de5606e;
  sandbox 8a491764274f490a9ac5ad0de386d6d2; deployment ff5c577ddc854b43a05612fe33b56118;
  client_id xyza7891goqUDqhcj1mbkpPBTbG06yVj). eos_config.gd generates the template on first run.
- **Account-portal login broken for other players:** fresh machines have no persistent token, so
  `persistent_auth` falls back to `account_portal` (eos_manager `_do_login`) and Epic's portal
  returns "Invalid Client - Client has no application associated". Dev Portal Client Settings →
  **Epic Account Services** section needs an Application created/assigned to this client_id.
  Until then, workaround = set `login.method` to `"anonymous"` in eos_config.local.json for tests.
- Dev Portal client policies / Epic Account Services permissions unconfirmed.
- Art/audio assets pending user delivery (non-blocking).

## EOS secrets environment (unchanged, from eos_config.local.json)
See the local file — production values live there, never commit unrelated values here.

## Session log
### Same-action cross-color matching (rule change)
- **Rule:** ACTION cards skip & reverse are playable on ANY card with the same
  `action_id`, regardless of color — a Red Reverse plays on a Green.
  Reverse. Number cards already matched by value across colors; skip/reverse now do
  too. The +N Draw cards (Draw Two/Four) stay COLOR-locked in normal play —
  cross-color +N plays exist ONLY through the forced-draw stacking bypass
  (`is_draw_stack_candidate`, which ignores color/type for the +N amount).
  Draw Ten is NONE-color in the real deck, so it remains an "anytime" card.
- **Implementation:** `card.gd` `matches(active_color, active_number, active_action_id)` —
  third param defaults to `""` (backwards compatible; empty = color-only, as before).
  `GameState.active_action_id` tracks the top-of-discard action, set in `setup()`
  (starter), `play_card` NUMBER/WILD (cleared `""`), `_apply_action` (set to
  `card.action_id`), and `jump_in`. `get_valid_plays`/`play_card` validation pass it.
- **Threaded through:** game.gd client-side pre-check (`:1914`), tutorial `_seed`
  (clears to `""` — all tutorial seeds use number tops), online snapshots
  (`active_action_id` field sent + applied).
- **Tests:** `test_card.gd` new `test_action_card_matches_same_action_across_colors`,
  `test_action_card_no_cross_action_match`, `test_action_card_matches_own_action_with_empty_active`;
  `test_game_state.gd` new `test_get_valid_plays_same_action_across_colors` and
  `test_play_same_action_across_colors`. All 12 parse files clean (`PARSE_CHECK_RESULT failed=0`).
- Not affected: `is_draw_stack_candidate` (forced-draw stacking) is a separate,
  pre-existing bypass that intentionally ignores color AND value for Draw cards.
### Ship/polish round (colors + timer + forced draw + EOS prod config)
- **Player colors shipped end-to-end:** `game_globals.gd` gained `PALETTE`/`PALETTE_NAMES`
  (8 Colors) + `my_color_idx`; `PlayerData` gained `color_idx`/`color`. Offline: menu swatch
  row (toggle Buttons + exclusive `ButtonGroup`) sets `my_color_idx`; `game._assign_offline_colors`
  gives seat 0 the pick and AI random distinct remaining colors via `_random_free_color`.
  Online: lobby has its own "YOUR COLOR" swatch row; each member publishes `ATTR_COLOR`
  (`EOSManager.set_my_color`), `_rebuild_roster` reads it into `color_idx` per entry,
  and on start `game._apply_roster_identity` maps seat→name+color (collisions resolved in
  seat order — seat 0 keeps its pick). `color_idx` rides every snapshot player dict and is
  applied in `_apply_snapshot`. `game_state.apply_seat_colors(indices)` is the offline-side
  loader.
- **Turn border:** full-rect `Panel` behind everything but above the 3D viewport
  (`MOUSE_FILTER_IGNORE`), border-only `StyleBoxFlat` (draw_center=false, width 8), visible +
  pulsing during `HUMAN_TURN` and `FORCED_DRAW_DECK_CHOICE` (`_update_turn_border`,
  color = `_own_color()`). Colors also on opponent Label3D names (`p.color.lightened(0.28)`)
  and the local hand label (gold while it's your turn).
- **Timer = current player's color:** `turn_timer_ring.gd` new `set_color()`; ring + numeric
  label tinted via `game._current_timer_color()` (players[current_index].color), blending to
  red only below 25% remaining. Set every frame in `_update_timer_ui` + in `_reset_turn_timer`.
- **Forced-draw target-fix:** `advance_turn` no longer auto-skips a pending forced-draw
  target; the target lands ON their turn, picks a deck (`FORCED_DRAW_DECK_CHOICE`, zones
  highlighted/clickable), and `resolve_forced_draw` draws + consumes the turn. (Was broken:
  skip consumed a rotation early AND hidden deck zones made the prompt unclickable → stall.)
- **Menu EXIT GAME** button added (`_on_quit` → `get_tree().quit()`).
- **EOS config for a distributable exe:** `_write_template` placeholders are NEVER used in
  practice — it only fires when no config exists and writes to `user://`. The real
  `res://eos_config.local.json` (production ids/secrets, `login.method=persistent_auth`,
  `devtool_*` empty, `fallback_to_account_portal=true`) is packaged into the exe. Keep
  `client_secret` + `encryption_key` embedded for EOS persistent auth.
- **EOS login fails for friends ("Invalid Client — Client has no application associated"):**
  friends have no persistent token → `persistent_auth` → `account_portal` fallback → portal
  rejects client_id because Dev Portal's client has no **Application** assigned under Client
  Settings → Epic Account Services. Fix on dev.epicgames.com, not in code. Workaround for
  tests: `login.method:"anonymous"`.
- All changes headless-parse clean (`game.tscn` + `menu.tscn`, see Run commands). Not yet
  visually verified — user runs the game/Tests 1 & 2.

### Uno-style forced-draw stacking (Draw Two/Four/Ten)
- **Stacking is now a real rule.** A forced-draw target may play any Draw
  card instead of picking a deck: `game_state._start_or_stack_forced_draw()` adds
  the card's amount to `pending_forced_draw_count`, clears the stacker's own
  `skip_next_turn`, and re-targets the next alive player (skip set). 2-player
  games bounce the stack between the two. `draw_two`/`draw_four`/`draw_ten`
  branches in `play_card` all route through it.
- **Cross-color +N stacking is restricted:** a stack only lands when the
  stacker's +N value matches the pile's +N (cross-color, same value) OR the
  stacker's card shares the active color (same color, any value). A red +4 does
  **NOT** stack on a green +2; a red +2 or a green +4 **does**.
- **Human UX:** during `FORCED_DRAW_DECK_CHOICE` hands highlight stackable Draw
  cards and clicking one plays it (NONE-color Draw Ten goes through the color
  popup first); A/B pick a deck, 1-9/0 stack. Non-stackable clicks notify.
  Colored Draw cards now play IMMEDIATELY on your own turn — the dead attacker
  "Target draws from which deck?" deck-choice prompt was removed (the TARGET
  always picks the pile at `resolve_forced_draw`).
- **AI:** `_process_ai_turn` stacks a Draw card ~60% of the time
  (random color for NONE Draw Ten), else calls `resolve_forced_draw` as before.
- **Color-first routing:** NONE-color swap_hands/choose_deck/peek now show the
  color popup first (new `_pending_next_step` = `"stack"/"target"/"peek"`,
  consumed in `_on_color_chosen`, cleared defensively in `_finalize_or_send_play`).
- **Color picker is now a centered 2x2 XP-logo-order grid** (Green/Blue/Yellow/Red)
  via new `_prepare_overlay_popup()` helper (`overlay_vbox.reset_size()` at the end of
  each selector; `_clear_overlay` now `remove_child` + `queue_free` so stale children
  can't skew `reset_size`).
- **Timer forfeit:** if a forced-draw target times out (deck or stack popup open),
  `_on_turn_timer_expired` resolves the pending forced draw instead of stacking a
  second generic 4-card penalty, so `pending_forced_draw` can't linger stale.
- Stacking plays go through the SAME `send_intent`/`_rpc_intent` play path online
  (host-authoritative, `is_acting` true for the target), so no new net code.
- Headless parse clean. Test 1 covers offline; add a manual forced-draw stack
  check (attack with Draw Two, target it at a human, stack with a Draw
  card of any value, confirm the count grows and bounces).

### Polishing regressions fixed
- **Bomb-dealt-at-deal fixed:** `game_state.setup()` deal loop now uses the same
  `while card and card.type == BOMB and attempts < 10` re-draw pattern as
  `_forced_draw`/`_handle_respawn` — a dealt bomb is returned and re-drawn until
  a safe card comes up (was: returned + a SINGLE replacement appended with no
  bomb re-check, so a bomb could silently land in an opening hand and "do nothing").
- **Blue card after red skip fixed:** `_apply_action` (skip/reverse/draw_two/
  draw_four) set `active_color = card.color` but never cleared `active_number`,
  so `matches()` (`color == active_color or number == active_number`) let a
  matching-number card of any color play after an action. Every action-color
  write now also sets `active_number = -1` (incl. the NONE-color `chosen_color`
  path).
- **Blurry 3D text fixed:** two causes addressed in game.gd: (1) the SubViewport
  render target was never sized (defaults 512x512 then `stretch` upscales it) —
  now driven from window size each frame alongside the existing draw-zone
  reposition; (2) `_add_table_label` rasterizes at 4x and scales `pixel_size`
  down 4x, so Label3D text keeps its world-space size but renders crisply.
- **Draw Two:** user confirmed no real issue (the only visible gap is the
  attacker-side ghost animation, which by design waits for the target's resolve
  at deck choice) — no code change.

### Polishing round: one-by-one hand reveal + overlay centering
- **Goal:** when cards are drawn, each card now *appears* in the local hand one by one, timed to the ghost-flight animation, instead of the whole hand flickering to its final state at once.
- **New helper:** _reveal_hand_tail(hide_count, first_delay = 0.0, step = 0.32) in game.gd (after _animate_forced_draw). Hides the tail hide_count CardNodes (alpha 0, scale 0.6, MOUSE_FILTER_IGNORE), then staggered pop-in tweens (scale?ONE 0.22s, alpha?1 0.18s, restore MOUSE_FILTER_STOP). Uses create_tween().bind_node(cn) -> if a later _refresh_hand frees the nodes, the tweens die safely and new hand nodes render normally.
- **Sync:** ghosts land at ~0.43 + i*0.32 (forced draw) / ~0.3 (single voluntary draw), so call sites use _reveal_hand_tail(count, 0.43, 0.32) or _reveal_hand_tail(1, 0.3).
- **Wiring (all staged AFTER the final _check_turn()/_refresh_all(), because _check_turn rebuilds hand nodes in most branches and would free the staged tweens):
  - _on_deck_clicked FORCED_DRAW_DECK_CHOICE branch -> capture d_count := game.pending_forced_draw_count BEFORE esolve_forced_draw (it zeroes the count), then reveal after _check_turn().
  - _on_turn_timer_expired forced-draw forfeit -> same capture-first pattern; reveal after _check_turn() when is_human.
  - _on_turn_timer_expired generic 4-card penalty -> humans previously got NO ghost (_fly_draw_to_hand(pile_id, null) no-ops on null card); now _animate_forced_draw(pile_id, idx, 2) for everyone, count penalty_drawn, reveal after _check_turn() when human.
  - _process_ai_turn draw-attack -> when draw_target == own_index (AI stacks a Draw card onto the human), reveal after _animate_forced_draw.
  - Voluntary single draw (_on_deck_clicked non-bomb) -> _reveal_hand_tail(1, 0.3) after _refresh_all() (no turn advance; End Turn button path).
  - LAST_SHOT drawn card -> _reveal_hand_tail(1, 0.3) after _check_turn() (non-bomb path).
- **NOT staged:** AI-resolving forced draws (target = AI, local hand unchanged), _finalize_or_send_play offline human?AI draw attacks (target = AI), online snapshot clients (hand rebuilt from snapshot).
- **Overlay centering finished:** the four selectors (_show_color_selector, _show_target_selector, _show_deck_choice_selector, _show_peek_selector) now end with _center_overlay_vbox() instead of the stale overlay_vbox.reset_size() (which pinned the popup top-left). _prepare_overlay_popup() + _center_overlay_vbox() are the paired helpers for content-hugging, dead-centered popups.
- All changes headless parse-clean. Test 1 (offline, 4 players) now shows the win; watch a forced draw / stack / timer penalty and a voluntary draw to confirm cards pop in one-by-one.

### Test infrastructure round (green baseline + coverage)
- **Full baseline green & deterministic:** `godot-ai_test_run` runs 137 tests across 10 suites (`/tests/test_*.gd`), 0 failures, 0 skipped, verified twice consecutively. Run recipe: edit -> `filesystem_manage(op="scan")` -> `godot-ai_test_run({})` (scan force-reloads disk edits the editor otherwise keeps stale). Keep `res://scenes/menu.tscn` open -> wrong scene causes phantom failures. Do NOT auto-run the game.
- **Flake-family root causes fixed in tests (pin the randomness):** (1) a random Bomb on the pile top diverts `draw_card(defer=true)` into `pending_bomb` -> pin pile tops to a safe card; (2) a random Diffuse in a drawer's hand is auto-consumed by `game_state._handle_bomb_drawn` -> pin drawer hands; (3) playing a RED 5 with copies in other hands opens the jump-in window and freezes the turn -> pin hands to non-jump-in cards; (4) `advance_turn` inspects the player it moves TO -> a 1-card hand triggers `pending_last_shot` and blocks the win -> pin opponents to TWO non-matching cards.
- **Gotchas:** `McpTestSuite.assert_eq` uses exact `!=` -> float-computed Colors need `is_equal_approx`. GDScript `%` strings escape a literal percent as `%%`. `CardDatabase._make(type, color, number, name, key)` is the 5-arg test factory. Deck top = end of array.
- **Coverage status:** utilities (deck/chamber/player_data/card_database/card/eos_config/timer) ~100%; core rules (`game_state.gd`, 35 funcs) ~94% (only `current_player`/`_emit_log` lack dedicated asserts); auth = eos_config 100% + `eos_manager.gd` 0/31 (14 pure helpers testable via `load(...).new()` WITHOUT `add_child`, which skips the EOS SDK `_ready`); UI layer ~2% (card_node/menu/lobby/game.gd untested -> `test_card.gd` covers the Card *data class*, NOT the CardNode control). `game.gd` (119 funcs) is the ceiling for headless coverage: ~15 pure helpers, the rest scene/input/anim/RPC.
- The per-run "1 new error/warning" hint is expected noise: eos_config `_read_json` invalid-JSON negative tests print to stderr, and `scripts_parse` scene loads fire the pre-existing SubViewport/shadowing warnings. Never blamestorm a green run over those.

### Freeze fix round (LAST SHOT soft-lock) + stacking + menu fit
- **LAST SHOT unclickable (root cause of "I'm at last shot, can't click anything"):**
  `_refresh_top_bar()` gated `_highlight_decks(state == HUMAN_TURN or FORCED_DRAW_DECK_CHOICE)`,
  so in `LAST_SHOT` the invisible deck click zones stayed `visible=false` (mouse dead) AND
  `_unhandled_key_input` gated A/B to `HUMAN_TURN` (keyboard dead) -> zero input paths, log
  tail showed `Player 2 plays Wild Color` (down to 1 card) then silence. Fixed: the
  `_highlight_decks` call now includes `state == State.LAST_SHOT`, and the key handler has
  a LAST_SHOT branch (A/B pick the chamber pile).
- **Any-+N stacking (user rule):** a forced-draw target may stack a Draw card of ANY
  +N value in ANY color (red +4 on green +2; +2 on +10). game_state: new
  `pending_forced_draw_amount` (records the starter +N; cleared in `resolve_forced_draw`),
  public helper `is_draw_stack_candidate(player_index, card)`
  (`is_draw_stack_candidate` ignores color AND value — any Draw Two/Four/Ten held by the
  current target stacks); `play_card`'s `matches()` check is bypassed ONLY for such stack
  plays. All three UI/AI filters (game.gd `_refresh_hand` stackable list,
  `_play_by_hand_index` FORCED_DRAW gate, AI ~60% stack picker) now use
  `is_draw_stack_candidate` instead of `matches()`. The amount rides online snapshots
  (`pending_forced_draw_amount`). Tests added: `test_stack_cross_color_same_value_allowed`,
  `test_stack_different_value_allowed` (+4 on +2 -> 6), `test_stack_draw_ten_on_draw_ten`.
- **Menu overflow fixed (EXIT GAME below the fold at every window size):** project.godot
  sets no window size -> 1152x648 design height, and the menu VBox measured ~730px, so
  `CenterContainer` clipped the bottom (stretch mode canvas_items only scales, never reflows).
  Compacted menu.gd: separation 12->8, spacers 40->12 / 30->8, title 56->44, subtitle 18->16,
  play buttons 56->50, tutorial/quit 50->46 -> ~585px total.
- Headless parse check clean. Editor session closed mid-session, so the full 140-test sweep
  still needs one run on next editor open.
- Still open: deck click-zone slight mesh-vs-marker offset (cosmetic; zones are now visible
  during LAST_SHOT so users can see exactly where to click).

### Physical turn-order ring + direction randomization + tutorial bomb/jump-in fixes
- **Turn order is now a physical ring**: `game_state.gd` gains `turn_order: Array[int]`
  (empty = fallback linear), `_RING_6 = [0,3,4,1,2,5]`, and `_build_turn_order(n)` (called
  from `setup()` :127) that derives `[0,1]` (2p), `[0,1,2]` (3p/linear), `[0,3,1,2]` (4p),
  `[0,3,4,1,2,5]` (6p), `[0,6,3,4,1,2,5]` (7p) by filtering the canonical string of seat AABB
  positions. `_next_alive_index(from, dir)` (:174) walks the ring via `posmod(find+step, size)`
  skipping eliminated seats, falling back to linear only when `turn_order` is empty (hand-built
  test states). `advance_turn`/`_start_or_stack_forced_draw`/`resolve_forced_draw` all land on
  ring neighbors. **Direction is randomized each game** (`+1` clockwise / `-1` counter-clockwise)
  — tests MUST pin `gs.direction = 1` or they go flaky (3p from 0: +1 → 1 but -1 → 2).
- **Tutorial armed-bomb fix:** steps 12/13 now arm whichever pile is drawn via
  `_bomb_on_both_piles` (the loops left in are dead safety only). No stale `_bomb_on_pile_a`
  references remain.
- **Tutorial guards:** `_on_bomb_vote_started` no-ops in tutorial (`game.gd` :1235) so the
  vote overlay can't appear, and the Jump-In prompt in step 14 fires only after the Continue
  popup closes (`_show_jump_in_prompt` at :2394, suppressed in `_on_jump_in_available`).
- **Tests rewritten for the ring:** `test_play_skip_sets_next_player_skip`,
  `test_advance_turn_{wraps_around,respects_direction,skips_eliminated,consumes_skip_next_turn,
  forced_draw_target_keeps_turn}`, `test_start_forced_draw_targets_next_player`,
  `test_stack_forced_draw_accumulates`, `test_stack_cross_color_same_value_allowed`,
  `test_stack_draw_ten_on_draw_ten`, `test_resolve_forced_draw_gives_cards_and_advances`,
  `test_forced_draw_honors_chosen_pile` — all pin `direction = 1` (4p ring target seat 3,
  not the old linear seat 1). `test_close_jump_in_window_advances` (3p) also needed the pin.
  2p bomb/resolve/overcharge tests are direction-independent (ring2 is invariant).
- **Editor staleness gotcha:** after disk-only edits, `godot-ai_test_run` logged
  `cache_warning` and 9 ring failures (target 1 vs 3 = linear fallback) even though
  game_state.gd on disk was correct. `filesystem_manage(op="scan")` force-reloads the disk
  edits — after scan + the direction pins the suite went **140 passed / 0 failed** (10 suites),
  headless parse clean. Treat a failing run after disk edits as stale preloads until a scan
  has run.

### Custom card art round (assets/imported_assets/cards) — REVERTED (art pending rework)
- **Status:** user reverted the art integration to make better textures and re-add later.
  card_node.gd is back to **pure procedural** drawing (no `card_art_texture` /
  `_draw_art_face` / matte trim). The deck-color work STAYED: `Card.CardColor` still has
  `ORANGE=5, PURPLE=6` (appended after `NONE=4`), `card_database.gd` `COLORS` is
  `[RED, GREEN, ORANGE, PURPLE]`, color popup is Green/Red/Orange/Purple, tutorial
  BLUE→ORANGE / YELLOW→PURPLE remap, `test_game_state.gd` bound `<= PURPLE`.
- **Deck piles are neutral, not green:** `_build_3d_piles` uses a flat
  `Color(0.16,0.16,0.18)` albedo (no Emerald texture); `_set_piles_glow` turn-highlight
  is faint neutral emission `Color(0.7,0.7,0.75)` @0.35 (was green `(0.25,0.95,0.4)`).
- **How the art worked (for when the new textures land; keep this pipeline or reuse):**
  `CardNode.card_art_texture(key, skip_matting)` static, cached by path: `exists()`+`load()`
  guard → `get_image()` (fallback `Image.load_from_file` dev-only) → trim uniform matte per side
  (tol 0.09, cap 20% of dim, corner-color ref/side) → center-crop to 2:3 → RGBA8 → `ImageTexture`.
  `_draw_art_face()` (falls through to procedural when no art) + `card_back` skipped matting.
  **Known bug to avoid:** the left/right scans must call `_line_is_matte(img, ref, tol, h, x, true)`
  — the original `(x, h, true)` read `get_pixel(h, i)` out of bounds, trimming side matte to ≈0
  (that's the white border the user saw). Maps `{color}_n`, `*_plus_2/4` (purple_plus_2/4 files
  absent → procedural fallback), draw_10, swap_hands, peek_deck, choose_deck, rotate_deck,
  extra_life, wild, sabotage, card_back.
- **Art mapping:** numbers `{color}_n` (red/green/orange/purple 0–9) — purple_drawn_2/4 missing →
  procedural fallback for purple `+2`/`+4` (no `purple_plus_2/4.png`); actions `*_plus_2/4`,
  `draw_10`, `swap_hands`, `peek_deck`, `choose_deck`, `rotate_deck`, `extra_life`; wild → `wild`,
  sabotage → `sabotage`; back → `card_back` (drawn with `skip_matting=true` — its dark side bands
  are a designed 3D-edge, raw ratio already ~0.700). `card_back.png` is 896x1280.
- **Gameboard (current):** 3D deck-pile boxes (`_build_3d_piles`) use a flat neutral
  `Color(0.16,0.16,0.18)` albedo — **no Emerald green** — so piles never read as green; the
  `_set_piles_glow` turn-highlight is a faint NEUTRAL emission (`Color(0.7,0.7,0.75)`, energy 0.35)
  instead of the old green `(0.25,0.95,0.4)`. Color popup (`_show_color_selector`) is
  Green/Red/Orange/Purple in a 2x2 grid.
- **Tutorial:** all BLUE→ORANGE / YELLOW→PURPLE mapping in tutorial_director.gd (replaceAll over
  the whole file: `CardColor` refs, `_filler_colors`, "BLUE SKIP/DRAW 2/DRAW 4" labels, prose).
- **Tests:** only bound change needed was `test_game_state.gd` active-color range
  `<= YELLOW` → `<= PURPLE`; BLUE/YELLOW used as arbitrary colors elsewhere still works (values
  unchanged). `test_card_database.gd` counts are color-generic → unaffected.
- **Verified:** `get_image()` decodes all imported card PNGs headless (tex_probe); art_verify
  confirmed 13/13 present art keys normalize to exactly 2:3 and `purple_plus_2` reports MISS
  (correct fallback). All edited scripts + `game.tscn`/`player_ui.tscn`/`menu.tscn` parse clean
  (`PARSE_CHECK_RESULT failed=0`). Full 140-test suite still needs a run in the editor
  (scan first — disk edits versus stale editor cache).