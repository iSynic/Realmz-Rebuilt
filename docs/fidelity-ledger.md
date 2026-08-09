# Fidelity decision ledger

Classic-visible behavior is the default ruleset. This ledger records deliberate departures only; the absence of a decision does not authorize reinterpretation.

## FD-COMBAT-001 — Monster-target elemental protection

- Affected rule: monster attack specials 12 through 15 against another monster carrying the matching elemental-protection condition.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/attack.c`, `attack2`, lines 1111–1164. Party targets and monster-target fire halve before adding to `specialdam`; monster-target cold, electrical, chemical, and mental add after the save but before protection. The latter protection therefore changes only the value passed to `showresults`.
- Observable oracle behavior, determined from the complete source flow: with elemental damage 8, a failed save, and matching protection, those four monster-target branches commit 8 elemental damage while reporting 4. The synthetic source-observation fixture is `tests/fixtures/oracle/monster-elemental-protection-correction.json`, SHA-256 `a5f88d1f69981c81ff8e290f8ecb51b930c68ad0ac3643cd8e1138788fb09114`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: protection would visibly report reduced damage while the protected combatant loses the unprotected amount. The neighboring five party branches and fire branch establish the consistent intent.
- Chosen 2.0 behavior: every matching elemental protection halves committed and displayed damage after the save. Integer truncation and all RNG ordering remain source-conformant.
- Tests: `_test_monster_elemental_attacks` records the Castle source anomaly and verifies the corrected result for all party elements and protected monster-target cold. The differential case is `combat.monster-elemental-specials`.
- Legacy quirk: none. No authored scenario dependency is known, and no compatibility profile is introduced.

Source-conformant implementations and ownership changes are not deviations. Phase 4's packed spell identities, spell power-roll ordering, equipment escrow, program replacement, and fumble mutations preserve observed Castle behavior while moving ownership into typed session state.

Each entry must include:

- stable deviation ID and affected rule;
- Castle commit, source file/function/range, and control-flow observation;
- observable Castle oracle behavior and fixture hash;
- player-facing problem;
- chosen 2.0 behavior;
- source-observation and chosen-result tests;
- proof that a narrowly named legacy quirk is required, if one is introduced.
