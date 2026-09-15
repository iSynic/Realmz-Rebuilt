# Classic compatibility gap register

Realmz Rebuilt aims to load and play ordinary Castle Realmz scenarios through Providence packages without silently changing authored behavior. This register tracks known gaps below the coarse application-workflow denominator. A workflow can be generally functional while a specific item, spell, opcode branch, combat condition, or presentation sequence remains incomplete.

## Status and evidence

- **Confirmed blocker** means a current production path explicitly rejects, skips, or misrepresents a Castle-valid operation.
- **Coverage gap** means the runtime has an owner, but the relevant authored variants or ordinary routes have not been demonstrated.
- **Reported defect** means ordinary play exposed a symptom that still needs a retained reproduction or causal proof.
- **Implemented, awaiting ordinary replay** means production behavior and focused public-boundary coverage exist, but the original player route has not yet been repeated successfully on the repaired build.
- Corpus counts below describe stored definitions or instructions. They do not establish ordinary-route reachability.
- Package validation, controlled execution, ordinary play, and Castle comparison are separate evidence levels.

## Confirmed runtime and presentation gaps

| ID | Area | Current gap | Known exposure | Player consequence | Closure evidence |
| --- | --- | --- | --- | --- | --- |
| `CCG-005` | Monster turns | Closed in controlled public combat: Speedy doubles movement and repeats attack row zero twice after the authored rows; signed permanent Tangle is subtracted exactly as Castle does and survives save restoration. | 19 Speedy and 27 permanently Tangled stored definitions across bundled catalogs; ordinary-route battle placement remains unmeasured. | The explicit activation stops are removed. | Recheck open and obstructed ordinary campaign battles with named Speedy/permanent-Tangle actors before upgrading route reachability. |
| `CCG-006` | Monster spells | General friendly-target monster spells are rejected unless they belong to the currently recognized healing, cure, condition, spell-point, destroy-magic, or charm families. | Fresh normalized probes report zero unsupported-pending monster spell-slot references across all 13 bundled packages. They separately identify 21 not-applicable references to party-only or field-only records in Destroy the Necronomicon, Grilochs Revenge, and Half Truth. Third-party exposure remains unaudited. | A third-party monster can decline a legal authored spell and fall back or finish its turn. | Audit converted third-party packages, then characterize any demonstrated target ownership before broadening ally-safe deterministic selection and resource/RNG/action accounting. |
| `CCG-007` | Combat spells | Area spells fail when an affected character or monster reflects spells because Classic area/group reflection targeting remains unresolved. | State-dependent across every reflecting combatant and eligible area spell. | A legal cast can fail instead of resolving its reflection behavior. | Characterize reflected recipient and ordering for area and group shapes; verify mixed reflectors, resistance, death macros, resources, and restore. |
| `CCG-008` | Combat spells | Non-summoning target-type-0 spells with nonzero size require ordered open-space selection that is not implemented. | No such scenario-owned definition was found in the current 13-package audit. The stock nonzero-size target-type-0 records are recognized summons and use the separate implemented summon path. | A third-party custom spell using this valid shape will be disabled. | Add a Providence-produced synthetic signature and implement ordered, saveable space selection without treating it as an actor target. |
| `CCG-009` | Projectiles | Character missile-item random power and the demonstrated zero-cost monster spell-slot signature are repaired. Projectile spells with nonzero specials remain explicitly unsupported. | The monster signature has 90 stored references across Castle in the Clouds, Grilochs Revenge, and Prelude to Pestilence; all three package probes report it executable. Random-power character Fire has controlled public command, cancel/RNG, save-state, and target-commit proof; authored item exposure and ordinary-route reachability remain unaudited. | The two generic pre-picker power gaps are closed, but special missile or thrown-item attacks can still be unavailable. | Replay referenced character and monster projectiles through ordinary combat, inventory item/spell pairs, and adjudicate each remaining nonzero-special family. |
| `CCG-010` | Monster macros | Battle/death macro spellcasting currently supports only non-damaging area and side-group condition spells. | Macro-call signature and reachability audit required. | A scenario-authored monster macro can fail instead of applying damage, healing, summoning, or another spell family. | Enumerate macro spell calls, implement them through existing spell owners, and prove death-source retention, target ordering, RNG, and continuation. |
| `CCG-012` | Combat movement presentation | Closed in controlled playback: `combatants_swapped` changes both cached anchors in one causal frame, so later attacks originate from the committed square. | Directly observed in Half Truth with Brom and Durin; controlled presentation regression added. | The stale-square cause of apparent two-space melee is removed. | Inspect an ordinary Half Truth Auto swap plus skip and reduced-motion convergence before upgrading live-route evidence. |
| `CCG-013` | Combat movement | Castle's pre-direction movement substate is not represented by the one-step intent. Guard cannot fire on a direction that is subsequently cancelled or blocked in the same way Castle permits. | State-dependent; ordinary reachability not inventoried. | Guard/reaction chronology can differ on cancelled or blocked movement attempts. | Use a controlled Castle fixture to settle the substate, then add a serializable typed interaction only if observable behavior requires it. |

## Implemented repairs awaiting ordinary replay

| ID | Area | Current evidence | Remaining acceptance |
| --- | --- | --- | --- |
| `CCG-001` | Equipment | Castle wear/remove ordering is implemented through `EquipmentRules`, including strength, movement, magic resistance, spell points, attack bonus, conditions, trained abilities, special abilities, party conditions, and forced removal. The exact stock Robe of Speed (206) now equips for a Brownie Minstrel named David through the public Inventory session, applies permanent Speedy, restores through save v5, and removes cleanly. | Repeat David's original Inventory screen route on the repaired build and inspect its visible enabled state and effect in ordinary play. Broaden package representatives for overlapping and lossy party-condition effects. |
| `CCG-003` | Equipment | `CharacterState` now owns exact equipped-instance order. Controlled public tests distinguish reversed armor-floor and damage-cap results, and save v5/Character Files v2 reject missing or inconsistent order. | Exercise a naturally obtained order-sensitive combination through actual Inventory, combat, removal, and save/load controls. |
| `CCG-015` | Inventory presentation | Detached item actions already carry the rules-owned reason and the Inventory controller binds it for focus/hover. The Robe case is now enabled because its negative permanent-condition duration is legal, not because the UI invented an exception. | Repeat the reported screen with controller focus and verify both enabled actions and a representative disabled reason visibly. |
| `CCG-004` | Combat outcome | Castle source and application STR# 3 settle opcode 56 loss target `-1`. The revived handoff now preserves both stock warnings and sound 26260, subtracts `2,000 × level` experience in party order, reverses the last land step, finishes the issuing timeline, and round-trips the completed state. Invalid backup state rejects before mutation or RNG consumption. | Exercise a reachable authored opcode-56 defeat through its ordinary application hook, acknowledgement queue, and post-move owner; the controlled public-runtime proof does not establish campaign reachability. |
| `CCG-011` | Monster retreat | A routed monster with a stale target now reacquires through the deterministic visible-target owner before moving. At the edge, an ordinary monster leaves battle; a scenario-mandatory ally remains living and positioned and publishes an explicit blocked-retreat reason. The latter deliberately stops movement instead of reproducing Castle's unsafe repeated offscreen walk. Both retained states serialize. | Exercise ordinary and required allied monsters through routed movement, Guard/withdrawal reactions, large footprints, and restored battles before upgrading route evidence. |

## Corrected baseline claims

- `CCG-002` was invalid as recorded. Pinned Castle `wear.c` accepts normalized item type 1 through its default slot path, Rebuilt now does the same, and the current stock-plus-13-package content contains no type-1 item definition. The earlier claim of two Griloch definitions came from an incorrect field/count interpretation. Type 1 remains a synthetic controlled coverage case, not an exposed campaign gap.
- `CCG-014` overstated a production defect. Compiled compact maps already route replacement terrain through `MapTopology.effective_cell_at` for movement, LOS, rendering, and restoration. The remaining question is a coverage gap for the noncompact/no-compact-map identity path and alternate callers; ordinary reachability is not established.
- `CCG-023` was invalid as a runtime defect. Destroy the Necronomicon contains six monster spell-slot references to target-type-8 special 56, but Castle `resolvespell.c:192-233` implements Phase entirely through the active party slot (`charup`, `c[charup]`, `attacks`, `beenattacked`, and `canundo`) even when the generic monster cast path reaches it. Rebuilt correctly classifies this context as not applicable rather than teleporting or killing a stale party character. Fresh probes of all 13 bundled packages now separate these six records plus nine fatigue, three Identify, and three Torch field-only references from genuine unsupported-pending monster spells; the latter count is zero for this corpus.

## Coverage and compatibility gaps

| ID | Boundary | Missing proof | Why it matters |
| --- | --- | --- | --- |
| `CCG-016` | Third-party package intake | The feature-report analyzer can compare normalized opcode and spell signatures, but there is no maintained compatibility run over a representative legal third-party scenario set. | The 13 bundled packages cannot establish compatibility with the wider authoring ecosystem. |
| `CCG-017` | Opcode variants | All 119 behavior-bearing opcode identities have handlers, but handler ownership does not prove every Extra Code mode, sign, selector, branch target, caller, or malformed-but-tolerated Castle value. | A package can pass opcode identity readiness and still fail only when a rarer authored branch executes. |
| `CCG-018` | Scenario reachability | All 13 bundled archives pass strict loading, but most stored definitions and instructions are not tied to demonstrated ordinary routes. | Static presence overstates practical playability and cannot prioritize progression blockers accurately. |
| `CCG-019` | Scenario-owned spells | Custom spell signatures are intentionally kept in local feature-report sidecars; application spell saturation does not prove them. | Third-party scenarios can introduce legal combinations absent from the stock application library. |
| `CCG-020` | Scenario media | Package validation proves indexed assets, not that every contextual orientation, animation stage, crop, text encoding, and same-key override is displayed correctly during play. | A scenario may run while showing stock fallback, stale orientation, malformed crops, or unreadable text. |
| `CCG-021` | Failure presentation | Fatal unsupported package/content failures do not yet share one retained typed recovery view. | Third-party incompatibilities can be technically rejected without giving the player or author a durable, actionable explanation. |
| `CCG-022` | Platform proof | Windows and Linux have native evidence; macOS remains unexecuted on an Apple runner. | Cross-platform compatibility remains incomplete even when simulation is identical. |

## Reported defects awaiting closure or renewed reproduction

- Intermittent persistent Party Auto stalls, including more than one report involving David.
- Combat beginning and advancing on Auto before the battlefield becomes visible.
- Battlefield, health, defeat, persistent-field, feedback, and music playback appearing out of causal order in ordinary battles.
- Scenario-specific monster CICN orientation falling back to a stock application image in some battles.
- Spells displaying zero damage while producing a lethal result.

Some of these areas have received repairs. They stay listed until the repaired build reproduces the original route successfully and the retained trace proves committed and presented state agree.

## Prioritization

1. **Progression and deterministic-state blockers:** `CCG-004`, reported Auto stalls, and any package compiler loss.
2. **Common authored mechanics:** `CCG-005`, `CCG-006`, `CCG-007`, and `CCG-010`, followed by ordinary replay of `CCG-001` and `CCG-003`.
3. **Misleading or inaccessible presentation:** `CCG-012`, ordinary replay of `CCG-015`, combat chronology, controller reachability, and media orientation.
4. **Rare signatures and fidelity edges:** `CCG-008`, `CCG-009`, `CCG-011`, `CCG-013`, and the noncompact topology coverage remaining from `CCG-014`.
5. **Certification breadth:** `CCG-016` through `CCG-022` after the blocking mechanics have executable representatives.

## Closure workflow

For each gap:

1. Record a normalized definition or instruction signature without copying third-party scenario content.
2. Separate Providence preservation, Rebuilt package readiness, controlled runtime execution, ordinary-route reachability, presentation, save/restore, and Castle comparison.
3. Reproduce the smallest representative through a public gameplay owner. Do not close a gap from private-handler coverage alone.
4. Implement through the existing typed operation; do not introduce a compatibility mode or a second gameplay path.
5. Add the missing variant and owned gap to `classic-application-workflow-inventory.json`, regenerate the workflow status, and close the register entry only when its required evidence exists.
6. Rank the next scenario by new executable feature coverage after reported progression failures are addressed.
