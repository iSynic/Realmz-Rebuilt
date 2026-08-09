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

## FD-COMBAT-004 — Negative monster physical damage

- Affected rule: ordinary physical damage from an unarmed or weapon-carrying monster after its signed `damageBonus` is combined with the attack or weapon roll.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/attack.c`, `attack2`, lines 689–697 and 1201–1219, plus `src/realmz_orig/share-movecost-dialog.c`, `Rand`, lines 44–51. Providence's `src-tauri/src/realmz/combat.rs`, `parse_monsters_from_source`, preserves Data MD byte 40 as a signed value and its semantic round-trip test includes `-5`.
- Observable oracle behavior, determined from the complete source flow: damage plus `-5` and an attack range of `1…1` produce physical damage `-4`; Castle then subtracts `-4` from stamina, healing a target from 10 to 14. The synthetic source-observation fixture is `tests/fixtures/oracle/monster-negative-damage-correction.json`, SHA-256 `7ddee339de7b80453ed49b41b65c04abcac2c3cee7329fd24ddd4ef48983982f`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: a successful hostile physical attack can heal its target solely because an authored penalty exceeds its die result. Nothing in the attack presentation identifies that result as healing, and neighboring damage paths treat the value as harm.
- Chosen 2.0 behavior: preserve the signed bonus in accuracy and damage arithmetic, then floor the final physical component at zero before Dragon Hide and health mutation. Elemental and special damage remain independent and retain their source order.
- Tests: `_test_monster_ordinary_attacks` proves both the signed accuracy contribution and the nonhealing chosen result. The differential case is `combat.monster-ordinary-melee`.
- Legacy quirk: none. No authored scenario dependency on attack-driven healing is known; concrete route evidence would be required before considering a narrowly named exception.

## FD-COMBAT-005 — Preserve a fumbled item's runtime charges

- Affected rule: the item instance queued by a character weapon fumble and later assigned through post-battle recovery.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/attack.c`, `attack`, lines 199–238, and `src/realmz_orig/booty.c`, `booty`, lines 320–340 and 1559–1582. Castle queues only the item ID in `fumque`; booty later calls `loaditem` and writes the definition's initial `item.charge` into the recipient's new inventory slot. Its eligibility check tests only base weight with strict less-than, then adds base plus all reconstructed charge weight.
- Observable oracle behavior, determined from the complete source flow: an item definition with 30 initial charges fumbled after seven charges remain is recovered with 30. Given base weight 2, per-charge weight 1, current load 92, and maximum 100, Castle accepts the item because 94 is below 100 and then raises load to 124. The synthetic source-observation fixture is `tests/fixtures/oracle/fumbled-item-charge-correction.json`, SHA-256 `c2505fd002bfdf590b3db1df4d1e3da346654bacf1da445e4d2bd2f70eb83710`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: dropping and recovering a charged weapon silently replenishes spent charges and may push its recipient beyond maximum load because the eligibility check ignores charge weight. It also loses any future mutable per-instance fields represented outside the definition.
- Chosen 2.0 behavior: queue and save the exact `ItemInstance`, force it unequipped, mark it identified for the source-backed loot workflow, and transfer that same instance only when its complete current weight fits at or below the recipient's maximum load.
- Tests: `_test_battle_owned_fumble_and_exact_recovery` records the Castle reconstruction and proves exact remaining-charge preservation across battle state, save/restore, and recipient assignment. The scenario and session-persistence tests cover opcode 122 and the post-battle interaction. The differential case is `combat.fumble-and-battle-recovery`.
- Legacy quirk: none. No authored scenario dependency on charge replenishment is known; concrete route evidence would be required before considering a narrowly named exception.

## FD-COMBAT-006 — Terminating battlefield placement

- Affected rule: initial character, held-over ally, and authored-monster placement when no legal battlefield cell or complete footprint exists.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/combatsetup.c`, `combatsetup`, lines 133–189, 201–270, and 290–375. Each failed search decrements `start`, increments `stop`, and unconditionally jumps back to the same search. Once the complete 90×90 valid rectangle has been exhausted, a battlefield with no legal cell has no terminating failure branch.
- Observable oracle behavior, determined from the complete source flow: an all-solid 90×90 field cannot place the first ordinary party member and cannot reach battle initialization or a recoverable state/RNG boundary. The synthetic source-observation fixture is `tests/fixtures/oracle/battlefield-placement-termination-correction.json`, SHA-256 `8b27b211ba21fda7f899d090dd9692390d72c04570264b606a2abcbbead97b0a`. This is `source-control-flow` evidence, not a Castle-runtime claim; deliberately running the native non-terminating case would add no useful observation.
- Player-facing problem: malformed or adversarial terrain can hang the application during battle startup after gameplay RNG has already advanced.
- Chosen 2.0 behavior: search the complete finite battlefield in Castle order, then fail with a stable placement error. Battle setup is transactional: no combat state is committed, and RNG generator state, draw count, scripted cursor, and preexisting trace are restored exactly.
- Tests: `test_battlefield_builder.gd` proves impossible footprint search terminates explicitly. `test_combat_flow.gd` proves the stable error plus complete game-state and RNG rollback. The differential case is `combat.battlefield-generation-and-placement`.
- Legacy quirk: none. A non-terminating application state is not scenario behavior that can be supported as an authored dependency.

## FD-COMBAT-007 — Preserve battlefield occupancy through monster revival

- Affected rule: battlefield occupancy while a defeated monster's death macro is pending and after CODE 119 revives that monster.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/killbody.c`, `killbody`, lines 87–154, and `src/realmz_orig/newland.c`, CODE 119, lines 292–307. `killbody` calls `bodyground` and `bodyfield` before the macro; CODE 119 changes the death-macro monster to one stamina and friendly allegiance; the return path skips later body replacement and never puts the revived monster back into field occupancy.
- Observable oracle behavior, determined from the complete source flow: the revived monster record remains alive and retains its old `monpos`, but its battlefield cells were already restored to ground. The synthetic source-observation fixture is `tests/fixtures/oracle/death-macro-battlefield-occupancy-correction.json`, SHA-256 `b68292e8d05f5dea38af06cac226715db86c4d0c98a90fd35d59dad850b2e325`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: a living revived combatant becomes absent from adjacency and occupancy checks. In 2.0 it would also violate the central save invariant that every living battle participant has one position.
- Chosen 2.0 behavior: retain the defeated monster's footprint while its nested death macro is pending. Remove it after completion only if the monster remains dead; retain the original footprint if the macro revives it.
- Tests: `_test_automatic_monster_death_macro` covers direct and VM macro continuation, CODE 119 revival, battle completion, ally selection, and central save boundaries. The differential case is `combat.death-macro-battlefield-occupancy`.
- Legacy quirk: none. A live but nonoccupying combatant is an internally inconsistent state, not a useful authored dependency.

## FD-COMBAT-008 — Tactical LOS independent of presentation delay

- Affected rule: combat line of sight used by monster target selection and later projectile targeting.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/cansee.c`, `cansee`, lines 5–52, and `src/realmz_orig/combat.c`, `combat`, lines 388–480. `cansee` always performs 128 samples but divides the segment by `128 + delayspeed`.
- Observable oracle behavior, determined from the complete source flow: for a ten-cell horizontal segment with blocking terrain two cells before the target, delay zero reaches the blocker while delay 64 covers only two thirds of the segment and returns visible. The synthetic source-observation fixture is `tests/fixtures/oracle/tactical-los-delay-correction.json`, SHA-256 `529ff0b65cdda0b84e01c32c8a9ac78150af4d3c40fcb25ff3c860e3e429440c`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: changing animation speed can change which target a monster chooses, where it moves, and eventually whether a projectile is legal. It also violates the engine boundary that presentation settings cannot mutate simulation outcomes.
- Chosen 2.0 behavior: retain Castle's 128 center-offset samples and occupied-field-cell behavior, but use a fixed divisor of 128. The query reads only session-owned battlefield terrain and positions.
- Tests: `_test_monster_los_targeting_and_movement` covers open LOS, a blocker near the target, target fallback, and automatic movement. The differential case is `combat.monster-targeting-los-and-movement`.
- Legacy quirk: none. No authored campaign can observe or require the user's animation-delay preference as a rules input.

## FD-COMBAT-009 — Bounded monster target fallback

- Affected rule: the ascending combat-slot scan after a monster's first randomly selected target fails line of sight.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/combat.c`, `combat`, lines 388–480, and `src/realmz_orig/structs.h`, `struct monster`, lines 159–171. The scan uses 110 as a sentinel even after values exceed the populated `10 + nummon` slot range, then indexes `monster[temp - 10]` and may pass an invalid target to `movemonster`.
- Observable oracle behavior, determined from the complete source flow: an all-unseen opposed roster can read uninitialized or out-of-range monster state instead of reaching a valid no-target result. The synthetic source-observation fixture is `tests/fixtures/oracle/monster-target-scan-correction.json`, SHA-256 `541e244260bbbb70a0652af7a82cb89a90f024498c2e93760272ccdcf7b4edf8`. This is `source-control-flow` evidence, not a Castle-runtime claim; deliberately invoking invalid native memory adds no useful fidelity evidence.
- Player-facing problem: ordinary blocked LOS can produce undefined target identity, invalid movement, or a crash instead of a stable skipped activation.
- Chosen 2.0 behavior: preserve the random-to-ascending transition and Classic party/gap/monster slot ordering, but scan only validated live slots. Invalid random slots remain source-ordered retries under a deterministic execution bound; no visible target ends movement explicitly.
- Tests: `_test_monster_los_targeting_and_movement` covers the gap-nine reroll, unseen-random-target transition, draw count, and visible fallback target. The differential case is `combat.monster-target-scan-safety`.
- Legacy quirk: none. Out-of-range native memory is not an authored scenario behavior.

Source-conformant implementations and ownership changes are not deviations. Phase 4's packed spell identities, spell power-roll ordering, equipment escrow, program replacement, and fumble mutations preserve observed Castle behavior while moving ownership into typed session state.

Each entry must include:

- stable deviation ID and affected rule;
- Castle commit, source file/function/range, and control-flow observation;
- observable Castle oracle behavior and fixture hash;
- player-facing problem;
- chosen 2.0 behavior;
- source-observation and chosen-result tests;
- proof that a narrowly named legacy quirk is required, if one is introduced.
