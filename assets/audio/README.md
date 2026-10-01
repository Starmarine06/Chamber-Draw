# Chamber Draw — Audio drop-in manifest

The game already plays sound for every event. Until you add files here, each
event falls back to one of the 6 Kenney UI blips (or stays silent). **Drop a
file with the right name into the right folder and it is picked up on the
next launch — no code changes.**

- SFX: `assets/audio/sfx/<event>.ogg` (also `.wav` / `.mp3`)
- Variants: `<event>_1.ogg`, `<event>_2.ogg`, … — one is chosen at random per
  play (great for card sounds).
- Music: `assets/audio/music/<track>.ogg` (loops automatically).

All mixing (volume, pitch jitter, bus) lives in `scripts/audio_manager.gd`
(`EVENTS` table). Players control levels in **Settings** (Master / Music /
Effects / Interface).

## Suggested CC0 sources

| Pack | Where | Use for |
|---|---|---|
| Kenney **Casino Audio** | kenney.nl/assets/casino-audio | card slide/place/shuffle, chips |
| Kenney **Impact Sounds** | kenney.nl/assets/impact-sounds | slaps, hits, thuds |
| Kenney **Interface Sounds** | kenney.nl/assets/interface-sounds | hover, confirm, error, ticks |
| Freesound (filter: CC0) | freesound.org | revolver spin / cock / dry fire / gunshot, heartbeat |
| OpenGameArt (CC0) | opengameart.org | noir / lounge jazz loops, tension drone |

## SFX events (`assets/audio/sfx/`)

| File name | When it plays | Suggested sound |
|---|---|---|
| `card_play` | you play a card | Casino `cardPlace1-4` (as `card_play_1..4`) |
| `card_draw` | you draw a card | Casino `cardSlide1-8` |
| `card_slide` | any card lands on the discard pile | Casino `cardPlace` / `cardShove` |
| `card_flip` | starter card flips | Casino `cardTakeOutPackage` / flip |
| `deal` | each card during the opening deal | Casino `cardSlide` (quiet) |
| `shuffle` | start of the deal | Casino `cardShuffle` / `cardFan` |
| `forced_draw` | each card of a +2/+4/+10 | Casino `cardSlide` |
| `chip` | (spare) chips clack | Casino `chipsStack` / `chipsHandle` |
| `draw_attack` | a +2/+4/+10 is played | Impact `impactPunch_heavy` |
| `stack` | a draw card is stacked | Impact `impactPlate_heavy` |
| `skip` / `reverse` / `swap` / `peek` / `rotate` / `wild` | those action cards | Interface `switch`/`toggle` variants |
| `extra_life` | Extra Life banked | Interface `confirmation` / chime |
| `jump_in` | someone jumps in | Impact `impactPunch_medium` |
| `your_turn` | your turn starts | soft bell / Interface `confirmation_002` |
| `banner` | big banners ("goes first" etc.) | Interface `maximize` |
| `timer_tick` | each of your last 10 seconds | Interface `tick_001` |
| `timer_urgent` | each of your last 5 seconds | Interface `tick_002` (sharper) |
| `timer_expired` | turn timed out | Interface `error_004` |
| `end_turn` | End Turn pressed | Interface `switch` |
| `bomb_drawn` | you draw a Bomb (diffuse prompt) | low stinger / Impact `impactMetal_heavy` |
| `diffuse` | Diffuse used | metal click + hiss |
| `chamber_start` | the Chamber opens | low boom / drone hit |
| `cylinder_spin` | cylinder starts spinning | Freesound revolver cylinder spin |
| `cylinder_click` | each chamber passing the hammer | Freesound revolver ratchet click |
| `hammer_cock` | hammer pulled back | Freesound revolver cock |
| `heartbeat` | loops while the cylinder spins | Freesound heartbeat (seamless loop) |
| `gunshot` | LIVE | Freesound revolver gunshot |
| `blank` | BLANK | Freesound dry fire click |
| `backfire` | BACKFIRE | muffled shot / Impact heavy |
| `lucky` | LUCKY DRAW | coin / chime |
| `eliminate` | (spare) elimination sting | low brass stab |
| `respawn` | a player respawns | rising chime |
| `vote` | bomb vote result | Interface `confirmation` |
| `win` / `lose` | game over (you won / lost) | short jazz sting / sad trombone |
| `lighter` | lighter lid flicked open | Freesound zippo open + strike |
| `lighter_close` | lighter lid snapped shut | Freesound zippo close |
| `pack` | a fresh cigarette pulled from the pack | cardboard/foil rustle |
| `inhale` | start of a drag (scroll) | Freesound cigarette inhale (short) |
| `exhale` | smoke exhale | Freesound exhale / breath out |
| `gulp` | whiskey sip | Freesound gulp / swallow |
| `glass_clink` | tumbler lifted / set down | Casino-ish glass clink, ice rattle |
| `button` | any UI button | Interface `click_002` |
| `hover` | hovering buttons / playable cards | Interface `tick` (very quiet) |
| `toggle` | settings checkboxes | Interface `switch` |
| `invalid` | illegal play / not now | Interface `error_006` |
| `pause` | pause toggle | Interface `minimize` |

## Music (`assets/audio/music/`)

| File name | Where |
|---|---|
| `menu` | main menu + lobby — slow noir jazz / lounge loop |
| `table` | in-game — subdued, low-energy loop (it ducks under the Chamber) |

(A missing music file just means silence; nothing breaks.)
