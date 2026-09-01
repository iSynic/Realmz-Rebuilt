# Fidelity decision ledger

Classic-visible behavior is the default ruleset. This ledger records deliberate departures only; the absence of a decision does not authorize reinterpretation.

## FD-SCENARIO-001 — Per-character opcode 30 checks

- Affected rule: Classic opcode 30 filtering of tracked characters by an attribute or trained ability.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/newland.c`, `newland`, lines 2426–2500. The loop advances `loop` through tracked characters but reads `c[t]`, where `t` is the action-slot cursor. Negative attribute checks invert inside the attribute branch and then invert the complete party again, while negative ability checks invert only after the loop.
- Observable Castle behavior: a controlled synthetic fixture with three distinct characters showed that all three results changed with the instruction slot instead of the iterated character, while still consuming three draws. It also confirmed the inconsistent double inversion. The runtime fixture record is `tests/fixtures/oracle/scenario-character-check-indexing-correction.json`, SHA-256 `51c025afb0c18360d911fdffdccc1edcf459046a3f1899e0bf69eada94889340`. The same fixture established that opcode 31 attribute index 10 prompts, consumes one draw, and continues without either XAP; Realmz Rebuilt preserves that separate inert behavior.
- Player-facing problem: an authored “set picked on check” operation can select or reject everyone according to an unrelated party member, and its negative meaning changes depending on whether the author selected an attribute or ability.
- Chosen 2.0 behavior: test every candidate's own value in party order, preserve one RNG draw per candidate, and apply a negative check index once as select-on-failure. Opcode 31's observed undefined attribute index remains source-conformant and does not share this correction.
- Tests: `test_scenario_vm.gd::_test_public_character_checks` covers distinct per-character attribute and ability results, one inversion, opcode 31 index-10 picker/RNG/no-branch behavior, serialization, and forged-response rejection. The differential case is `scenario.character-check-indexing`.
- Legacy quirk: none. Action-slot aliasing and asymmetric double inversion are implementation defects, not meaningful authored behavior.

## FD-SCENARIO-002 — Mandatory opcode 31 character selection

- Affected rule: aborting the required character picker used by Classic opcode 31.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/getchoice.c`, `getchoice`, and `src/realmz_orig/newland.c`, `newland`, case 31. A-abort clears every tracked selection, but case 31 ignores that result, leaves `track[0]` equal to zero, and evaluates `c[0]` as though the first party member had been chosen.
- Observable Castle behavior: a controlled synthetic fixture exercised both attribute and trained-ability checks after A-abort. Both left `track=000`, consumed one ordinary check draw, evaluated party slot zero, and loaded the fixture's failure XAP 6. Two runs produced byte-identical output. The fixture record is `tests/fixtures/oracle/scenario-character-check-abort-correction.json`, SHA-256 `374a65b15c4417f8f510cc769fdd52f6ff92260a3acfbeb4bb90fd3f0519c491`.
- Player-facing problem: abort appears to cancel a required choice but silently branches on the first party member, so party order changes an invisible selection and its RNG-backed result.
- Chosen 2.0 behavior: opcode 31 selection is mandatory. The Party-list picker has no cancel response, Back or Escape cannot dismiss its blocking request, and the check consumes no RNG until the exact required stable character identity is submitted.
- Tests: `test_classic_ui_system.gd::_test_fixture_gallery_coverage` proves that the character picker exposes no cancel or premature-submit control and auto-submits only the exact count. `test_scenario_vm.gd::_test_public_character_checks` proves that an invalid or missing response cannot consume the check draw or resume the VM. The differential case is `scenario.character-check-abort`.
- Legacy quirk: none. Silent party-slot-zero selection is an implementation defect, not a useful authored capability.

## FD-SCENARIO-003 — Opcode 55 specific picked position

- Affected rule: Classic opcode 55 selectors 1 through 6, which branch on whether a specific party position is picked.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/newland.c`, `newland`, lines 3315–3365. The switch labels every selector as “Success if Specific Picked,” but cases 1 through 6 all read `track[0]`.
- Observable source inconsistency: selectors 2 through 6 cannot test their authored positions and instead duplicate selector 1. The source observation is `tests/fixtures/oracle/scenario-picked-position-correction.json`, SHA-256 `c9c41c270df73967ed42a7b205cc8492be13f09b5537f19062a121bd74c407f8`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: Tutorial's check for the second party member reports the first member as the second, and any scenario branch aimed at positions 2 through 6 resolves against the wrong character.
- Chosen 2.0 behavior: selectors 1 through 6 test the corresponding one-based party position. Selector 0 and the absolute picked-count modes remain unchanged and no branch consumes RNG.
- Tests: `test_scenario_vm.gd::_test_public_character_checks` proves selector 2 rejects a first-position-only pick and accepts a second-position pick while preserving the authored GOSUB branch.
- Legacy quirk: none. Six distinct authored switch cases collapsing onto `track[0]` is a source typo, not a meaningful scenario capability.

## FD-ECONOMY-001 — Zero-charge shop valuation

- Affected rule: shop sale value for an item definition whose authored charge count is zero.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/moveicon.c`, `moveicon`, lines 129–170, and `itemcost`, lines 5–24. Sale integer-halves absolute cost, divides current charges by authored charges as floating point, multiplies the halved cost by that ratio, applies sale inflation capped at 100 percent, and divides unidentified value by fifty.
- Observable source inconsistency: authored zero charges with current zero charges evaluates `0.0 / 0.0` and converts the resulting non-finite value through the signed item-cost field. That conversion is undefined or platform-dependent. The synthetic source-observation fixture is `tests/fixtures/oracle/shop-zero-charge-valuation-correction.json`, SHA-256 `a8d5977ba170e174a552666d1a6338a9d28e31dc37505541cd9ec5c7957db952`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: the same uncharged item can receive an unstable, nonsensical, or platform-dependent sale offer even though charge condition does not apply to it.
- Chosen 2.0 behavior: a definition with nonpositive authored charges retains a condition multiplier of one. Positive authored charges preserve Castle's current/authored ratio and truncation order; all later inflation and unidentified penalties remain unchanged.
- Tests: `test_realmz_rules.gd` covers charged, unidentified, capped-inflation, and zero-charge prices. `test_scenario_vm.gd` covers the complete ordinary shop lifecycle. The differential case is `economy.classic-shop-lifecycle`.
- Legacy quirk: none. A non-finite conversion is not a stable authored behavior.

## FD-ECONOMY-002 — Permit exact-maximum treasure load

- Affected rule: ordinary treasure assignment when the exact pending item would bring a recipient to, but not beyond, maximum load.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/booty.c`, `booty`, lines 1544–1583. Castle requires `current load + item base weight < maximum load`, then commits base plus charge weight separately.
- Observable source inconsistency: a recipient at load 90 with maximum 100 cannot receive an item weighing exactly 10, even though the resulting load would be legal. The same source check can admit a charged item whose complete weight later exceeds maximum. The synthetic source-observation fixture is `tests/fixtures/oracle/treasure-exact-load-correction.json`, SHA-256 `e163b32cd65223fcb89bb061d6c5263f54738cf315b4cd3ed087a0de6f96e2b8`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: an item is rejected at a legal capacity boundary, while another can be accepted into an overloaded state because the check and mutation use different weights.
- Chosen 2.0 behavior: evaluate the exact pending instance, including current charges, and allow assignment when resulting load is less than or equal to maximum. A result above maximum remains unavailable with a typed reason.
- Tests: `test_reward_workflow.gd` covers zero-capacity rejection, ordinary capacity, the exact-maximum correction, exact-instance assignment, and save/resume. The differential case is `rewards.ordinary-distribution`.
- Legacy quirk: none. No authored scenario dependency on rejecting a legal exact-maximum assignment is known.

## FD-ECONOMY-003 — Require complete denomination capacity during Share

- Affected rule: Classic Share when pooled jewelry is assigned to a character with fewer than fifteen load units free.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/share-movecost-dialog.c`, `share`, lines 5–40, and `src/realmz_orig/swap.c`, `swap`, lines 129–159. Share tests only `current load < maximum load` before adding fifteen for jewelry; Swap tests the complete added weight before the same transfer.
- Observable source inconsistency: a character at load 99 of 100 receives one jewelry through Share and becomes load 114, while the adjacent manual Swap path rejects that transfer. The synthetic source-observation fixture is `tests/fixtures/oracle/money-share-capacity-correction.json`, SHA-256 `b5cd34bb12db32b2b2213ecac35df289ee696b18b5f44758478b0a1c49559aeb`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: the one-click distribution command can create an overloaded character that the manual money command correctly identifies as unable to carry the same denomination.
- Chosen 2.0 behavior: Share retains Castle's jewelry, gems, then gold order and one-unit-per-character passes, but assigns a denomination only when its complete weight fits at or below maximum load. Unassignable wealth remains in the pool with a typed reason.
- Tests: `test_money_workflow.gd` records the Castle source result, verifies the corrected capacity result, covers all three denominations, source order, sounds, movement recalculation, typed intents, and save restoration. `test_classic_ui_system.gd` verifies detached disabled reasons. The differential case is `economy.pool-share`.
- Legacy quirk: none. Overloading through Share contradicts Swap and the ordinary maximum-load invariant.

## FD-INVENTORY-001 — Safe equipped-item trade

- Affected rule: moving an equipped carried item between party members in the ordinary two-character Trade workspace.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/items.c`, `items`, lines 950–979; `moveicon.c`, `moveicon`, lines 221–259, 353–440, and 615–655; and `removeitem.c`, `removeitem`, lines 5–102. Trade copies an equipped item to the recipient with its equipped flag cleared, but deletes the source record directly instead of invoking `removeitem`. The `canuse` failure changes cursor/sound without preventing the move.
- Observable source inconsistency: an equipped curse can bypass the ordinary curse-removal lock, and stored source-character equipment bonuses are not explicitly reversed even though the item record is gone. The synthetic source-observation fixture is `tests/fixtures/oracle/equipped-item-trade-correction.json`, SHA-256 `465fb2d73ae1d585a932a95a9ff0562719b3bfe90159c20eef85444f7bbf4d76`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: Trade can remove a supposedly locked curse and leave the source character benefiting from equipment no longer carried. Those outcomes contradict the ordinary Equip/Unequip workflow and create state that cannot be derived from current inventory.
- Chosen 2.0 behavior: allow an equipped ordinary item to transfer and force the recipient instance unequipped, matching Castle's record outcome. Derived values always follow the current equipped instances. Reject trading an equipped cursed item, so the curse cannot bypass its source-backed removal lock.
- Tests: `test_inventory_session.gd` verifies equipped ordinary transfer, recipient unequipped state, exact load movement, and equipped-curse rejection. The differential case is `inventory.carried-item-workflow`.
- Legacy quirk: none. Stale derived bonuses and removable equipped curses are contradictory state, not useful authored behavior.

## FD-INVENTORY-002 — Stable charged-item Split and Join

- Affected rules: splitting one finite charged-item record and joining every matching charged-item record in the ordinary Items workspace.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/items.c`, `items`, lines 483–557; `dropitem.c`, `dropitem`, lines 5–29; `misc.c`, `calcw`, lines 824–840; and `structs.h`, `struct item`, lines 77–81. Split keeps the selected record with `ceil(charges / 2)`, appends an identified-copy record with `floor(charges / 2)` and clears its equipped flag. Join visits all thirty slots, sums every matching record into a signed 16-bit accumulator, ORs identification/equipment, and keeps the first matching record.
- Observable source inconsistency: neither branch leaves `character.load` equal to `calcw`. Split does not add the second record's base weight. Join pre-adds each removed record's complete weight before `dropitem` subtracts it, deliberately leaving the prior total unchanged. Reopening Items or Character invokes `calcw` and changes the displayed load. A sufficiently large Join can also wrap the signed charge accumulator. The synthetic source-observation fixture is `tests/fixtures/oracle/inventory-stack-corrections.json`; this is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: the same inventory has two different carried loads depending on whether the player has reopened a screen, and a large Join can destroy a valid finite charge total by wrapping it negative. Both outcomes conflict with save validation and exact-instance ownership.
- Chosen Rebuilt behavior: preserve Castle's ceiling/floor split, copied identification, unequipped sibling, all-match Join, and OR-style identification/equipment. The selected stable instance survives Join. Recompute the exact record-derived load as part of each committed mutation. Reject negative/infinite-charge Join and totals above 32,767 transactionally. A lone stack exposes Join as unavailable rather than committing Castle's redraw-only no-op.
- Tests: `test_inventory_session.gd::_test_split_join` proves the public typed intents, exact identities, charge distribution, equipment/identification state, immediate load invariant, integrated sounds, save restoration, detached availability, and overflow rejection. The differential case is `inventory.split-join`.
- Legacy quirk: none. Stale derived load and signed overflow are contradictory bookkeeping defects, not useful authored behavior.

## FD-CHARACTER-002 — Human appearance-set zero alias

- Affected rule: the initial and recommended portrait/tactical icon for a Human character whose Data Race `defaulticonset` is zero.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/newcharacter.c`, `CharacterGen`; `src/realmz_orig/portrait-picklock.c`, `portrait`; `src/realmz_orig/iconpict.c`, `iconpicture`; and `src/realmz_orig/main.c`, the Portraits/Tacticals resource-fork opens. Initial creation computes portrait `251 + defaulticonset*6` and tactical `9000 - 257 + portrait`; the portrait picker applies the same zero-set offset. The browseable forks instead contain portraits 257–376 and tacticals 9000–9119. The imported Human record stores set zero, and decoded portrait 257 matches the first named Human portrait used by the functional Remake reference.
- Observable source inconsistency: the literal Human initial values are 251 and 8994, neither of which belongs to the browseable character catalogs, while the picker/catalog pairing begins at 257/9000. This conclusion combines complete pinned source flow with direct resource inventory; it is not presented as a Castle-runtime capture.
- Player-facing problem: preserving the literal formula would create a Human with unavailable art and would place no actual Human portraits in the recommended group.
- Chosen 2.0 behavior: treat stored set zero as an alias of the first browseable six-portrait set. A default Human receives portrait 257 and tactical icon 9000; explicit selection uses the corresponding offset. Set one remains a valid alias for the same first portrait set, and all positive set values otherwise retain Castle's formula.
- Tests: Providence validates the zero/set-one alias and emits exactly 120 role-labelled portraits plus 120 tactical icons. Package, session, UI, save/restore, and vault tests verify complete catalogs, stable IDs, role rejection, Human defaults, and immutable revision eligibility. The differential case is `character.appearance-catalog-and-human-default`.
- Legacy quirk: none. Missing resources are not useful authored behavior, and no compatibility profile is introduced.

## FD-CHARACTER-005 — Active appearance ownership boundary

- Affected workflow: changing an active party member's portrait or tactical icon from the Character menu.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/handlemenuchoice.c`, `HandleMenuChoice`; `modify-cancast.c`, `modify`; `portrait-picklock.c`, `portrait`; and `iconpict.c`, `iconpicture`. Castle exposes separate commands, recommends portraits by Data Race `defaulticonset`, recommends tactical icons by one-based character race, copies the selected identity into the active party slot when the picker closes, and then rewrites the standalone Character Files record.
- Observable source inconsistency: a campaign-local appearance edit implicitly overwrites reusable external character state, and the picker has no explicit staged rollback boundary. The synthetic source-observation fixture is `tests/fixtures/oracle/active-character-appearance-ownership-correction.json`, SHA-256 `93d8cb1d1691489b37c0da79da8e4c00027a633672a6b495cde9da2929b6df2b`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: merely browsing or closing an appearance picker can blur campaign state and reusable-character publication, making Cancel semantics and cross-campaign ownership unclear.
- Chosen 2.0 behavior: preserve separate portrait and tactical-icon catalogs and their distinct Castle recommendation formulas. Preview is presentation-owned, Apply commits exactly one stable-ID role to the session, Discard commits nothing, and vault publication remains a separately confirmed immutable revision.
- Tests: `test_character_appearance_workflow.gd` verifies exact independent mutations, event identity, RNG/time stability, wrong-role and unknown-character rejection, save restoration, corrupt-role rejection, explicit empty-media preservation without substitution, and transactional restore. `test_classic_ui_system.gd` verifies catalog preview, explicit Apply, and no-op Discard. The differential case is `character.active-appearance-change`.
- Legacy quirk: none. Implicit external-file overwrite conflicts with the central session and explicit vault-revision architecture and is not campaign-authored behavior.

## FD-CHARACTER-001 — Bounded trained-ability records

- Affected rule: initialization and level-up of the character's fifteen-slot trained-ability array.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/updatespec.c`, `updatespec`, lines 49–97, and `src/realmz_orig/structs.h`, lines 60, 94, and 314. `character.spec` has fifteen slots, but both race and caste `specialability` records have only fourteen. The initialization and level-up loops nevertheless run through slot fourteen, reading beyond both authored arrays; the neighboring twelve-slot `character.special` array is a separate racial combat-modifier field.
- Observable oracle behavior, determined from the complete source flow: the fifteenth iteration aliases adjacent struct storage and can conditionally add or roll a value that is not an authored trained ability. Its value and RNG effect depend on unrelated record fields rather than a defined file-format slot. The synthetic source-observation fixture is `tests/fixtures/oracle/character-ability-index-boundary-correction.json`, SHA-256 `31715ad5796826ed192f2eb8ecad905dc6ea07ad0d068dcbdc2cb35d9b6f118c`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: changing an unrelated race/caste field can alter a hidden ability or consume an extra gameplay draw during character creation and every level-up. Conflating `special` with `spec` would also make racial combat modifiers double as thief/application skills.
- Chosen 2.0 behavior: preserve fifteen trained-ability slots in character/save state, import and evaluate only the fourteen authored race/caste values, and hold slot fourteen at zero without a draw. Keep the twelve racial combat modifiers in their independent `specials` field. Strength/Dexterity modifiers and clamps retain Castle's authored fourteen-slot behavior.
- Tests: `_test_character_creation_and_leveling` verifies exact level-three values, draw count, the zero unauthored slot, the separate racial modifiers, victory threshold, condition threshold, and two-hand statistic. Package tests reject ability arrays of the wrong length. The differential case is `character.trained-ability-index-boundary`.
- Legacy quirk: none. Adjacent-struct reads are not authored scenario data and cannot be represented portably.

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

## FD-COMBAT-010 — Actor-owned monster projectile replacement

- Affected rule: replacing a monster's active projectile weapon before that monster performs an ordinary physical attack, including Guard and withdrawal reactions.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/attack.c`, `attack2`, lines 448–485, and `src/realmz_orig/checkforenemy.c`, `checkforenemy`, lines 93–118. `attack2` copies its actual `mon - 10` attacker into local `monst`, but the damage-type-nine replacement writes `monster[monsterup].weapon` and reads `monster[monsterup].items[0]`. A reaction calls `attack2(enemy[ttt], q[up], 0)` while `monsterup` can still identify the moving monster.
- Observable oracle behavior, determined from the complete source flow: when the reacting attacker and global active monster differ, Castle mutates the active mover and gives the reacting attacker's local copy the mover's native slot-zero item. The synthetic source-observation fixture is `tests/fixtures/oracle/monster-projectile-weapon-replacement-correction.json`, SHA-256 `4fa9d08301311d0164a58f9e6008050808857b743c07b8c64488373cb7e8e8d6`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: one monster can unexpectedly change another monster's equipment, while a reaction resolves with a weapon the attacker never carried. The result depends on unrelated active-turn state rather than authored equipment.
- Chosen 2.0 behavior: inspect and mutate only the actual attacking monster. If its active item links to a damage-type-nine projectile, replace it with that same monster's exact native slot-zero item; an empty slot continues unarmed. Ordinary attacks and reactions use the same actor-owned path. The surrounding source-conformant missile flow retains initial range power, lowers only unaffordable cost power, resolves at power one, and resumes the cast/movement decision when no target or affordable power remains.
- Tests: `_test_source_backed_projectile_fire` passes the actual attacker alongside a distinct untouched monster and proves replacement reads and mutates only the supplied attacker; source inspection verifies that ordinary and reaction resolution both call the shared helper. Package tests prove all six native slots retain their positions. The differential case is `combat.monster-projectile-weapon-replacement`.
- Legacy quirk: none. Cross-combatant mutation through stale global state is not a useful authored dependency.

## FD-COMBAT-011 — Per-cast monster spell-target retry scope

- Affected rule: the hundred-attempt guard used while a monster samples distinct targets for an ordinary repeated-target spell.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/combat.c`, `combat`, lines 9–12 and 209–370. Castle initializes local `pass` once when combat begins, increments it before every target sample, and resets it only after `pass > 100`; a successful selection or completed cast does not reset it.
- Observable oracle behavior, determined from the complete source flow: after one hundred cumulative samples across earlier casts, the next cast increments `pass` to 101 and reaches the cutoff before drawing its otherwise-valid target. The synthetic source-observation fixture is `tests/fixtures/oracle/monster-spell-target-retry-scope-correction.json`, SHA-256 `64bef13fb08493977b393b5efb11ae97ced24e6060a3e310f19904c88f4a4cc8`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: an unrelated history of successful earlier casts can suppress or truncate a later legal cast. The outcome depends on an invisible function-local lifetime accident, and serializing that counter would turn Castle's transient implementation detail into durable campaign state.
- Chosen 2.0 behavior: each monster spell cast receives its own zero-based attempt counter and may sample at most one hundred candidates. If one cast genuinely exhausts that budget after finding at least one distinct target, it retains Castle's partial-cast result and full chosen-power cost. The counter is temporary execution state and is not saved.
- Tests: `_test_character_and_monster_repeated_target_spells` proves that a first cast may succeed on its hundredth sample and that a second cast still receives its own first sample; it also preserves the within-cast partial-result/full-cost boundary. The differential case is `combat.repeated-target-spells`.
- Legacy quirk: none. Scenario data cannot read, write, or intentionally depend on the lifetime of Castle's local `pass` variable.

## FD-COMBAT-012 — Last-slot Delay advances the round

- Affected rule: initiative ordering when the final actor in a round chooses Delay.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/combat.c`, `combat`, lines 793–817, and `src/realmz_orig/getup.c`, `getup`, lines 1–210. Delay removes and appends the current queue entry, decrements the cursor, then calls `getup(TRUE)` even when the actor was already last.
- Observable oracle behavior, determined from complete source flow: at the final initiative entry, remove-and-append leaves the actor last and cursor rewind can select that same actor again. The source-observation fixture is `tests/fixtures/oracle/combat-delay-final-slot-correction.json`, SHA-256 `e4a41f2902f0d15966ba1bbd8109f5eceee493e903b01e52817d335fe16a804f`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: Delay can grant an immediate duplicate activation instead of delaying the actor or ending the round.
- Chosen 2.0 behavior: a fresh actor normally moves behind the remaining actors. If already last, Delay applies Castle's attack-allocation adjustment and advances to the next round, including ordinary round-boundary effects.
- Tests: combat-flow tests cover normal reorder, last-slot round advancement, attack allocation, rejection after committed action, and save restoration.
- Legacy quirk: none. Duplicate initiative caused by remove/reinsert cursor aliasing is not an authored scenario dependency.

## FD-COMBAT-013 — Bandage only an actual bleeding recipient

- Affected rule: the party selection accepted by manual Bandage.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/combat.c`, `combat`, lines 752–777, and `src/realmz_orig/combatinfo-combatchoice.c`, `combatchoice`, lines 208–228. The manual branch opens a broad dead-inclusive party picker and clears bleeding for every selected row; Auto instead scans party order for the first bleeding member.
- Observable oracle behavior, determined from complete source flow: a manual selection can contain a non-bleeding or dead character and still consume the activation, while multi-selection can clear several recipients. The source-observation fixture is `tests/fixtures/oracle/combat-bandage-recipient-correction.json`, SHA-256 `e0ad7afaf91c5fd7a8cee8e02bd9d1d819ae85e736c0d2a79dc5d3abb1a0ca11`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: the command can succeed without treating a wound, and a plural hidden effect conflicts with the singular choice presented to the player.
- Chosen 2.0 behavior: expose living, combat-owned bleeding recipients in party order, clear exactly one selected recipient, and reject invalid targets without mutation.
- Tests: combat-flow and persistence tests cover legal-recipient order, exact one-recipient mutation, invalid-target rejection, immediate persistent-Auto cleanup on defeat, party-ordered round bleeding, Castle's default party-warning RNG draw, death, and save restoration.
- Legacy quirk: none. A no-op or hidden multi-bandage selection is not needed by authored scenario data.

## FD-COMBAT-014 — Undo never overwrites an occupied combatant

- Affected rule: activation-start position restoration when another combatant now occupies that cell.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/getup.c`, `getup`, lines 220–225, and `src/realmz_orig/combat.c`, `combat`, lines 680–693. Castle records only `undox`/`undoy`, restores the current underlying cell, copies the destination field value into `charunder`, then writes the active actor into that field cell without an occupancy check.
- Observable oracle behavior, determined from complete source flow: an occupied activation-start cell is overwritten. The source-observation fixture is `tests/fixtures/oracle/combat-undo-occupied-cell-correction.json`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: the overwrite can make battlefield occupancy and actor positions disagree, corrupting movement, targeting, and save invariants.
- Chosen 2.0 behavior: the core availability probe disables Undo while another combatant occupies the recorded start cell. A submitted stale command fails without mutating state or RNG.
- Tests: the bounded Undo test covers the occupied-cell reason, mutation-free rejection, ordinary movement restoration, save/resume, source sound order, condition gates, and result invalidation.
- Legacy quirk: none. Authored scenarios cannot rely on one combatant replacing another in volatile battle state.

## FD-COMBAT-015 — Tangle Weed resolves its named condition

- Affected rule: stock application spell 2412, Tangle Weed, resolving unsigned special 253 in combat.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/structs.h`, `struct spell`, lines 259–267, and `src/realmz_orig/resolvespell.c`, `resolvespell`, lines 13–19 and 345–364. The spell record declares `special` as unsigned, converts it through `abs`, and treats every value above 99 as a condition-clear index at `special - 101`. The fixed application `Data S` at Castle commit `ef95fcff40d81f14ac668d5e13466da4a51de6f4`, SHA-256 `f47776aadc0f4ebf42320e0aaedd39dd7b5a2c76c125a44e99ea461d962860e7`, preserves Tangle Weed's target type 3, size 14, queue icon 4, power duration 1–2, and special 253.
- Observable oracle behavior, determined from complete source flow: special 253 addresses condition slot 152 outside both character and monster forty-slot condition arrays instead of applying any valid condition. The source-observation fixture is `tests/fixtures/oracle/tangle-weed-special-correction.json`, SHA-256 `017d6448ce51071ccb19e03e572525b9e40f31fd66dd8d63110853b7f711ede6`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: the named stock spell can corrupt adjacent battle state or crash rather than applying Tangle, and a deterministic runtime cannot expose the unsafe write as authored gameplay.
- Chosen 2.0 behavior: retain special 253 in package content and mechanical signatures, but normalize that otherwise impossible condition reference to special 3 at the combat-condition boundary. Learned spells, fixed-power scrolls, charged items, Party Auto, and monster AI then share the ordinary target-type-three area, queue, defense, duration, movement, and save contracts.
- Tests: `_test_public_tangle_weed_correction_matrix` loads the bundled application record, proves all four combat-source dispositions, resolves the exact Tangle condition and persistent field through every source, and restores the result and queue from public save data.
- Legacy quirk: none. An out-of-bounds condition write is not a portable authored dependency; any different intended effect would require contradictory application data or controlled runtime evidence.

## FD-REWARD-001 — Drain every level earned by one reward

- Affected rule: post-reward level progression when a recipient retains enough positive victory points for more than one level.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/booty.c`, `booty`, lines 1081–1100; `src/realmz_orig/misc.c`, `getexp`, lines 274–288; and `src/realmz_orig/levelup.c`, `levelup`, lines 5–18.
- Observable source behavior: the reward close calls `getexp` and `levelup` once per positive living recipient. One threshold is subtracted and one level is gained; a still-positive balance persists until another reward close. The source-observation fixture is `tests/fixtures/oracle/reward-earned-level-drain-correction.json`, SHA-256 `ceef3b2534f74bbe66cdcf3bff794dbaf16b8a7e38e5e42a36bc5d98ed35bdbf`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: a large reward visibly grants only one level, then a later one-point award can appear to grant another level even though that level was earned earlier.
- Chosen 2.0 behavior: retain the same divided award, threshold table, deterministic level transaction, and recipient order, but repeat the same recipient until its carried victory points are nonpositive. Each gained level remains a separate saveable result acknowledgement, and each eligible recipient receives at most one spell-selection pass after its complete level sequence. A nonpositive authored threshold publishes a correction event, normalizes the unusable positive balance, and grants no level rather than entering an unbounded or repeat-award loop.
- Tests: `_test_experience_level_and_spell_restore` proves four earned levels, save/restore after the first result, exact acknowledgement count, final negative balance, and one completed continuation. The differential case is `rewards.experience-level-up`.
- Legacy quirk: none. The timing of an already-earned level is not an authored scenario input, and retaining the Castle defect makes progression appear dependent on an unrelated later reward.

## FD-SYSTEM-001 — Immutable definition names with source-classified Reduced Sound

- Affected rule: Classic Preferences Reduced Sound and the adjacent Edit Spell Names and Edit Race/Caste Names commands.
- Castle evidence: commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/pref.c`, `preference`; `src/realmz_orig/editspellnames.c`, `editspellnames`, `editracecaste`, and `SetIndString`; plus the `reducesound` guards in Items, Cast Spell, and Swap.
- Observable source behavior: Reduced Sound is application preference state. It gates modal/opening ambience while button 141 and Swap transfer sounds remain outside the guard. The name editors rewrite application STR# resources directly and refuse to operate when the scenario names resource is active. The source-observation fixture is `tests/fixtures/oracle/classic-preferences-source-observation.json`, SHA-256 `8a9f70a96a458ff58ad65fc8ae98cd9629d19e6360f188f2d86c26e797398ff0`. This is `source-control-flow` evidence, not a Castle-runtime claim.
- Player-facing problem: globally filtering a sound ID can mute an ungated action that reuses it, while mutating compiled names would make immutable package facts depend on machine-local preference history and could diverge stable application/scenario identity across installations.
- Chosen 2.0 behavior: persist Reduced Sound in host settings and suppress only explicitly eligible presentation events before channel or media side effects. Keep compiled stock and scenario definition strings immutable; no preference rewrites package data or overlays those names.
- Tests: the public System workspace/settings proof covers schema-10 round-trip and migration plus eligible Items, Spells, and Swap openings, retained action sound 141, and restored default audio. The differential case is `system.classic-preferences`.
- Legacy quirk: application resource-file mutation is intentionally not supported. It is visual-only and cannot alter importability, navigation, targeting, rules, RNG, time, or gameplay saves.

Source-conformant implementations and ownership changes are not deviations. Phase 4's packed spell identities, spell power-roll ordering, equipment escrow, program replacement, and fumble mutations preserve observed Castle behavior while moving ownership into typed session state.

Each entry must include:

- stable deviation ID and affected rule;
- Castle commit, source file/function/range, and control-flow observation;
- observable Castle oracle behavior and fixture hash;
- player-facing problem;
- chosen 2.0 behavior;
- source-observation and chosen-result tests;
- proof that a narrowly named legacy quirk is required, if one is introduced.
