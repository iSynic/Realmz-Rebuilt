# Authoritative topology evidence

This document records the evidence boundary for the Phase 2 world model. Providence compiles legacy/native representation details into explicit runtime topology. `MapTopology` plus session-owned `WorldState` overlays then answers every gameplay query; `GameView` is the presentation-safe projection of those answers.

## Castle source/control-flow evidence

Evidence label: `source-control-flow` at Castle commit `491816ad60037394f92c428e99c004494d3c28b3`.

- `src/realmz_orig/threed.c:515-550` reads the destination dungeon field before committing movement. A directional bit matching `8 - head` permits forward entry and records discovery; another directional-secret mask blocks entry; note/encounter markers and a non-wall field permit entry; door bits are observed after the move. This proves that wall, door, directional-secret, and encounter facts belong to the destination-cell movement decision.
- `src/realmz_orig/checkforsecret.c:38-72` searches the surrounding 3×3 area. Land secrets use the encoded terrain band, while dungeon secrets use mask `3840`, skip already revealed bit 9, roll `Rand(100)`, and set reveal/arch bits on success. This proves that search mutates playthrough state over otherwise immutable map facts.
- `src/realmz_orig/centerpict.c:74-186` renders a 15×13 land window in 32-pixel cells. It selects a one-based tile from a 20-column atlas with `top = (tile - 1) / 20 * 32` and `left = (tile - 1) % 20 * 32`; `fastplot.c:14-35` uses the same addressing. This proves the normal land presenter should use the decoded atlas at native 32×32 size rather than scale each cell to 48 pixels.

- `src/realmz_orig/textbox-time.c:376-426` visits matching random rectangles from slot 19 down to 0, rolls `Rand(10000)`, consumes three ordered random-door rolls, clears a positive door percentage after success, optionally asks the player whether to take a favorable surprise, rolls a separate 10-percent unfavorable surprise, and then selects the battle. The 2.0 session preserves that order and serializes both one-shot door state and the surprise interaction.
- `src/realmz_orig/structs.h:49-56` stores `landid`, `landx`, and `landy` in each `door`/AP record. `newland.c:3742-3772` applies those fields after the action sequence as a level and position destination, then allows one `seconddoor` recheck. `flashrange-loaddoor.c:43-59` preserves the current AP's destination fields while loading XAP code. This proves the AP header is post-action location data, not terrain replacement data, and that macro transfer must retain AP origin context.
- `src/realmz_orig/newland.c:2336-2339` identifies opcode 24 as Keep Codes and jumps past ordinary cleanup. At `newland.c:3729-3730`, a completed placed AP otherwise sets its saved percent to `-1`. Realmz 2 therefore disables an ordinary AP only after its full direct or resumed timeline succeeds, preserves it when opcode 24 is reached, and serializes that state. This corrects replaying story APs such as Assault's starting AP without inventing coordinate- or campaign-specific exceptions.

These observations do not prove final 2.0 search chances, LOS rules, elapsed-time costs, or presentation timing. Those exact formulas require Castle runtime fixtures where source control flow alone is insufficient.

## Providence compiler normalization

Providence commit `84a5afde2ec13b218289fcb02ace20adfc71b6f2` is the current authoritative compiler checkpoint. Its `src-tauri/src/dungeon.rs` decoder names packed dungeon bits, and the `.realmz2` exporter converts those bits into stable cells, directional edges, and explicit features. Providence Layout adjacency becomes explicit bidirectional map transitions, and placed AP headers become validated post-action destinations. Classic land matrices use their native `x * height + y` storage while dungeon matrices remain `y * width + x`; both compile to explicit `(x,y)` cells. Referenced land atlases, negative-land `cicn` overlays, and the normalized PICT 302 dungeon-composition atlas become immutable package media, while packed native values do not enter the runtime package as an alternate topology. The later option-label and sound-packaging work at this checkpoint does not alter that topology document.

The runtime mirror is schema v2 SHA-256 `c9c713b99ec58c366f6eeaf96ed371c94e491e8ab8351ba791a848d5f2f878ac`, mirrored from Providence commit `2b5eadff`. The topology contract is unchanged by the display-metadata addition.

## Realmz 2.0 behavior and proof

Target behavior:

- `MapTopology.probe_entry` owns passability, wall, door, and secret entry decisions.
- `MapTopology.find_path`, LOS, visibility, movement, search, trigger discovery, random-region membership, and presentation views consume the same cells, edges, features, and overlays.
- `WorldState` owns terrain replacements, opened doors, discovered secrets, disabled triggers, and visited/minimap cells in the save aggregate.
- Placed APs are one-shot by default after successful completion. Opcode 24 Keep Codes is the source-backed repeatable exception, while opcode 25 explicitly removes the issuing AP.
- `ClassicMapPresenter` consumes only `GameView`; its clipped, party-centered native 32-pixel atlas view, minimap, cardinal cues, and opt-in debug facts cannot become simulation authority. Normal play does not draw fabricated land-edge walls, AP diamonds, random-region boxes, or cell grids over Classic art.
- `GameView` projects at most a 25×25 party-local cell window while carrying the complete visited-coordinate set and four topology-probed movement answers. This reduces presentation work without creating an alternate map or passability model.

Evidence labels:

- `runtime-unit`: the synthetic package verifies normalized land/dungeon cells, directional secret entry, door identity, wall rejection, deterministic pathfinding, visibility, native atlas sizing, click-direction translation, and typed overlay serialization.
- `runtime-integration`: typed intents execute message APs, default one-shot AP cleanup after a resumed textbox timeline, opcode-24 Keep Codes preservation, explicit opcode-12 terrain replacement, one post-action AP relocation and destination recheck, reverse-order random rectangles, one-shot random-door XAPs, serializable surprise choices, battle start, search/discovery, map transition, dungeon door opening, movement-cue changes, visited minimap facts, and transactional save/restore through `GameSession`.
- `live-route`: MCP Pro keyboard/mouse input exercised movement, a message AP, search roll 52, secret discovery, a Layout transition, save, restart, and restore. A fresh editor inspection reported zero errors and the captured 960×600 exploration view showed the topology-derived map and minimap.

The fixture is synthetic and Providence-authored. Its exact package and compiler hashes are recorded in `tests/fixtures/packages/fixture-provenance.json`; it contains no commercial campaign data.
