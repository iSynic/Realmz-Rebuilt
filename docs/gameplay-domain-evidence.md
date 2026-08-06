# Gameplay domain evidence

This document records the Phase 4 evidence boundary. Castle source observations guide the fixed rules and Classic opcode adapters; runtime tests prove the new implementation. Content inventory does not by itself prove Castle executable parity or campaign reachability.

## Castle source/control-flow

Pinned oracle: Realmz Castle commit `491816ad60037394f92c428e99c004494d3c28b3`.

- `src/realmz_orig/newland.c:1966-2003` loads the packed spell ID and applies power, save adjustment, and force-affect fields for opcodes 17 and 18. `src/realmz_orig/resolvespell.c:13-61` rolls base duration, one duration contribution per power level, base damage, and one damage contribution per power level in that order. Lines 286-365 apply saves, elemental protection, condition additions, and condition clears. The 2.0 rule keeps that draw order and packed identity rather than treating scenario-spell slots as zero-based runtime IDs.
- `src/realmz_orig/newland.c:2597-2662` pools and removes party wealth/equipment for opcode 36, then restores the exact stored records and returns items acquired in the interim separately. The 2.0 equivalent stores detached item instances and wealth in `PartyState`, persists the escrow, restores equipment, recalculates load from immutable item definitions, and moves interim finds to party storage.
- `src/realmz_orig/newland.c:1736-1823` copies XAP programs over encounter/AP programs or redirects the active AP. The 2.0 runtime records equivalent program mappings and active-frame redirects without modifying immutable package definitions.
- `src/realmz_orig/newland.c:351-404` removes and queues a party weapon or clears a monster weapon during opcode 122 fumble. The 2.0 runtime removes equipped party weapons into session-owned storage and clears monster weapon identity so the mutation survives save/restore.
- `src/realmz_orig/spelllist.c:105-123`, `136-166`, and `412-475` provide the source branches used for the selected scenario-spell specials, including death/Flesh to Stone, resurrection, dispel, curse removal, movement, animation, poison, haste/age, and youth. Implemented specials fail or mutate explicitly; there is no script-name fallback.

These are source/control-flow observations. They do not claim that every formula branch has a Castle runtime fixture yet.

## Providence compiler evidence

Providence commit `a06f2ef152139dfd3fccfc5e563ba9ee58b62d3a` owns the current additive Realmz 2.0 exporter. The schema mirror hash is `16ec7efe0aa3ef335f0b2c37b32424b571c2f8035e65da7f0b0c45d37be21298`. The synthetic package contains the bundled Classic race/caste/item/spell libraries, scenario supply/custom overlays, explicit battle slots, random rectangles, a source-correct AP destination pair, and two managed media assets.

The bounded Assault on Giant Mountain audit is recorded in `tests/fixtures/oracle/aogm-active-opcode-inventory.json`. Its source hash is `23e5a33dcf06e020d9efdde12ff1b5a85a97d42d732b9bc1bfb464f4fa1f7ce0`; it records 717 triggers, 32 Complex, 18 Simple, 9 Thief, and 12 Timed Encounters and an exact set of 58 active normalized opcodes. The committed fixture contains counts, hash, and opcode identities only—no commercial records. It proves bounded inventory/readiness coverage and explicitly makes no reachability claim.

## 2.0 proof

- `runtime-unit`: fixed rules cover signed arithmetic, character construction/leveling, conditions and camping, inventory/economy/treasure, combat, scenario-spell draw ordering and selected specials, monsters, and combat flow. VM tests cover equipment escrow, program replacement/redirect, fumble state, packed opcode 17/18 spells, unknown-spell failure, and save/restore.
- `runtime-contract`: the loader independently constructs and cross-validates direct gameplay/encounter definitions, rejects unsupported active opcodes and malformed references, and verifies the mirrored schema and package hashes.
- `runtime-integration`: the Providence-authored fixture drives encounter and gameplay-domain operations through `GameSession`, the one public `RealmzRuntimeApi`, domain executors, and whole-session persistence. The current aggregate gate passes 531 assertions across eight suites, including source-ordered random-region draws, typed surprise interaction save/resume, one-shot random doors, AP destination recheck, combat movement lockout, and ordered save v1-to-v3 migration.
- `content-inventory`: all 58 active normalized opcodes in the bounded campaign inventory have one declared owner, pass package readiness, and dispatch without the top-level unsupported-opcode fallback. Submode/argument coverage and completion-critical reachability remain Phase 5 route work.

The fresh local Assault on Giant Mountain export from this compiler contains 9 maps, 72,900 cells, 623 runtime-reachable triggers, 1,956 Classic instructions, 983 messages, and 21 decoded media assets. Runtime package hash `7561aa2d2f1c2acf4dc57bc12cef1d79049473a2e9bd19fe8c6e377acf087e84` independently validates and starts at land 0 coordinate 48,15. A generic 2.0 route harness executed local route hash `b84ff7d68d2d203cb03aca65f94600d4f7c87e01054d8b9a97aba6d68ef19a95` through the normal session/VM boundary: opening, Battle 60, Baron macro, Battle 274, all four terrain-155 mutations, quest 17, rewards 68/467/625, and final land 0 coordinate 84,8 passed. This is `live-route` evidence for that deterministic completion spine, not a claim that every campaign branch matches Castle runtime. The package, route, and report remain local and uncommitted.
