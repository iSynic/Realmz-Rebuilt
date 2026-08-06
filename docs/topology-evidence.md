# Authoritative topology evidence

This document records the evidence boundary for the Phase 2 world model. Providence compiles legacy/native representation details into explicit runtime topology. `MapTopology` plus session-owned `WorldState` overlays then answers every gameplay query; `GameView` is the presentation-safe projection of those answers.

## Castle source/control-flow evidence

Evidence label: `source-control-flow` at Castle commit `491816ad60037394f92c428e99c004494d3c28b3`.

- `src/realmz_orig/threed.c:515-550` reads the destination dungeon field before committing movement. A directional bit matching `8 - head` permits forward entry and records discovery; another directional-secret mask blocks entry; note/encounter markers and a non-wall field permit entry; door bits are observed after the move. This proves that wall, door, directional-secret, and encounter facts belong to the destination-cell movement decision.
- `src/realmz_orig/checkforsecret.c:38-72` searches the surrounding 3×3 area. Land secrets use the encoded terrain band, while dungeon secrets use mask `3840`, skip already revealed bit 9, roll `Rand(100)`, and set reveal/arch bits on success. This proves that search mutates playthrough state over otherwise immutable map facts.

- `src/realmz_orig/textbox-time.c:376-426` visits matching random rectangles from slot 19 down to 0, rolls `Rand(10000)`, consumes three ordered random-door rolls, clears a positive door percentage after success, optionally asks the player whether to take a favorable surprise, rolls a separate 10-percent unfavorable surprise, and then selects the battle. The 2.0 session preserves that order and serializes both one-shot door state and the surprise interaction.
- `src/realmz_orig/structs.h:49-56` stores `landid`, `landx`, and `landy` in each `door`/AP record. `newland.c:3742-3772` applies those fields after the action sequence as a level and position destination, then allows one `seconddoor` recheck. `flashrange-loaddoor.c:43-59` preserves the current AP's destination fields while loading XAP code. This proves the AP header is post-action location data, not terrain replacement data, and that macro transfer must retain AP origin context.

These observations do not prove final 2.0 search chances, LOS rules, elapsed-time costs, or presentation timing. Those exact formulas require Castle runtime fixtures where source control flow alone is insufficient.

## Providence compiler normalization

Providence commit `a525e9df0d0619847a5928463eed881ace79152a` is the current authoritative compiler checkpoint. Its `src-tauri/src/dungeon.rs` decoder names packed dungeon bits, and the `.realmz2` exporter converts those bits into stable cells, directional edges, and explicit features. Providence Layout adjacency becomes explicit bidirectional map transitions, and placed AP headers become validated post-action destinations. Referenced land atlases and the normalized PICT 302 dungeon-composition atlas become immutable package media, while packed native values do not enter the runtime package as an alternate topology.

The runtime mirror is schema v1 SHA-256 `4ecdc3866ada29a0d311e87700870d2e63732d97bf04d4898a3bc68331d073fd`.

## Realmz 2.0 behavior and proof

Target behavior:

- `MapTopology.probe_entry` owns passability, wall, door, and secret entry decisions.
- `MapTopology.find_path`, LOS, visibility, movement, search, trigger discovery, random-region membership, and presentation views consume the same cells, edges, features, and overlays.
- `WorldState` owns terrain replacements, opened doors, discovered secrets, disabled triggers, and visited/minimap cells in the save aggregate.
- `ClassicMapPresenter` consumes only `GameView`; its clipped, party-centered atlas view, minimap, and debug facts cannot become simulation authority.

Evidence labels:

- `runtime-unit`: the synthetic package verifies normalized land/dungeon cells, directional secret entry, door identity, wall rejection, deterministic pathfinding, visibility, and typed overlay serialization.
- `runtime-integration`: typed intents execute message APs, explicit opcode-12 terrain replacement, one post-action AP relocation and destination recheck, reverse-order random rectangles, one-shot random-door XAPs, serializable surprise choices, battle start, search/discovery, map transition, dungeon door opening, and transactional save/restore through `GameSession`.
- `live-route`: MCP Pro keyboard/mouse input exercised movement, a message AP, search roll 52, secret discovery, a Layout transition, save, restart, and restore. A fresh editor inspection reported zero errors and the captured 960×600 exploration view showed the topology-derived map and minimap.

The fixture is synthetic and Providence-authored. Its exact package and compiler hashes are recorded in `tests/fixtures/packages/fixture-provenance.json`; it contains no commercial campaign data.
