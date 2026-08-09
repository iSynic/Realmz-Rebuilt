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

## FD-COMBAT-002 — Character-weapon elemental save target

- Affected rule: heat, cold, and electrical damage from an equipped character melee weapon against a monster.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/attack.c`, `attack`, lines 301–373, and `src/realmz_orig/misc.c`, `savevs`, lines 1188–1229. The monster-target branches test immunity on the defending monster but pass `chare`, the attacker, to `savevs`; the neighboring character-target branches pass `mon`, the defender.
- Observable oracle behavior, determined from the complete source flow: with elemental damage 8, matching protection, a failed attacker save, and a successful defender save, a monster target loses 4 elemental health while an otherwise equivalent character target loses 2. The synthetic source-observation fixture is `tests/fixtures/oracle/character-weapon-elemental-save-correction.json`, SHA-256 `9e5f128e0959a4d7a0ba6b1c848505d8b972ae91aac4ae30f88188753d78053f`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: a character's own elemental defense would determine how much damage their weapon deals to a monster, while monster defense would be ignored after its immunity gate. This also disagrees with the neighboring character-target path.
- Chosen 2.0 behavior: weapon elemental damage always uses the defender's matching save and protection. Monster immunity still suppresses the corresponding damage branch and its draws. All other ordering and integer truncation remain source-conformant.
- Tests: `_test_combat_magic_and_monsters` verifies the corrected monster-target save and committed damage. The differential case is `combat.character-melee-resolution`.
- Legacy quirk: none. No authored scenario dependency is known, and no compatibility profile is introduced.

## FD-COMBAT-003 — Character required-weapon enforcement

- Affected rule: the monster's required blunt, sharp, or specific weapon gate on a successful character melee attempt. This does not affect the separate Data BD battle-distance field or the monster's separate magical-plus threshold.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/attack.c`, `attack`, lines 259–282; `src/realmz_orig/loaditem.c`, `loaditem`, lines 5–34; and the shipped `base/Realmz/Data Files/Data ID`, SHA-256 `a64ad1fb64933ecca45de2cbf84b9e0415337ae045c71f2c0c56770af84e80ad`. Castle compares a specific signed monster byte to `item.itemid - 1024`, but the shipped item records use ordinary IDs 1–999. Its blunt/sharp branches are also guarded by the equipped weapon slot, allowing unarmed attacks to bypass either family restriction.
- Observable source/manual conflict: Divinity documents the positive value as the weapon's ordinary Item Number, `-1` as blunt-only, and `-2` as bladed-only. The Castle expression cannot accept a matching shipped Item Number, and the equipped-slot guard contradicts the stated weapon-only restrictions. The synthetic source-observation fixture is `tests/fixtures/oracle/character-required-weapon-correction.json`, SHA-256 `9af69f4ce70579679db5d3e6d723913a8287b530c0f3c1c4b1c93e2affc2d004`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: an authored signature weapon would never satisfy its monster gate, while fighting unarmed would bypass monsters intended to require a blunt or bladed weapon.
- Chosen 2.0 behavior: preserve zero, `-1`, and `-2` as distinct sentinels. Normalize any other stored signed byte to its unsigned 1–253 Item Number and compare it directly with the equipped weapon's Classic ID. Blunt and sharp restrictions require an actual equipped weapon with the matching family marker. The independent `magicToHit` threshold retains Castle's armed magic-plus and unarmed level-divided-by-eight behavior.
- Tests: `_test_combat_magic_and_monsters` covers insufficient magical plus, both weapon families, unarmed rejection, matching and wrong specific IDs, and signed storage above 127. Package tests prove `requiredWeapon`, `magicToHit`, and battle `distance` remain distinct. The differential case is `combat.character-required-weapon-correction`.
- Legacy quirk: none. A scenario needing Castle's impossible specific-ID comparison or unarmed sharp bypass would need concrete authored evidence before any narrowly named quirk is considered.

Source-conformant implementations and ownership changes are not deviations. Phase 4's packed spell identities, spell power-roll ordering, equipment escrow, program replacement, and fumble mutations preserve observed Castle behavior while moving ownership into typed session state.

Each entry must include:

- stable deviation ID and affected rule;
- Castle commit, source file/function/range, and control-flow observation;
- observable Castle oracle behavior and fixture hash;
- player-facing problem;
- chosen 2.0 behavior;
- source-observation and chosen-result tests;
- proof that a narrowly named legacy quirk is required, if one is introduced.
