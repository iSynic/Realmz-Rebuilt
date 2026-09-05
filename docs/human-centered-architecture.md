# Human-centered architecture overhaul

Realmz Rebuilt is behaviorally mature, but its source still exposes too much of its construction history to a new maintainer. Beta 1 is blocked while the repository is reorganized into an editor-readable, feature-oriented form. The working game remains the behavioral reference during this migration.

## Starting point

The migration branch begins at commit `55292533` with Godot 4.7.1. The complete local verification gate passed at that commit with 3,532 assertions across 27 suites, 101 differential cases, all 13 bundled scenarios, and every package, schema, export, media, and workflow check.

The initial structural audit found:

- 64,250 substantive production lines and 8,596 substantive test lines.
- 664 `Control.new()` calls, all admitted by the former reviewed-classification budget.
- 28 production files above the new 600-line limit and 103 functions above the new 60-line limit.
- 38 top-level scripts above the new method-count limits.
- 203 production calls into another object's underscore-prefixed method.
- 133 generic `Type` or `Script` preload aliases.
- Two one-node shell-mode marker scenes and no registered editor-preview profiles.

These numbers are migration debt, not the desired architecture. The overhaul gate prevents any category from growing and requires each ceiling to move downward as its owning workflow is converted. The final ceilings are zero except for the ordinary numeric size limits and explicitly named algorithmic renderers.

## Performance baseline

Three warmed samples were taken on the same Windows machine before structural work. Medians are used for comparison.

| Probe | Baseline median |
|---|---:|
| Application ready | 6,734.890 ms |
| First frame | 153.658 ms |
| Movement transaction plus projection p95 | 1.781 ms |
| Movement transaction p95 | 0.787 ms |
| Movement projection p95 | 1.034 ms |
| 3D dungeon unique-step p95 | 4.573 ms |
| 3D dungeon turn p95 | 0.023 ms |
| 3D dungeon backtrack p95 | 0.035 ms |
| Battle setup | 93.719 ms |
| Combat view | 1.532 ms |
| Auto activation | 30.311 ms |
| Warm monster phase | 9.798 ms |

The performance probes now load scenario packages through the pinned application catalog before measuring them. This is required by the separated application-catalog and scenario-overlay contract.

## Working rules

- Unrelated feature work remains paused. Defects, fidelity blockers, and migration-required polish may proceed.
- Each batch starts with characterization evidence and ends with focused tests, the architecture gates, and three comparable performance samples when it touches a sensitive path.
- Stable layout moves into scenes. Scripts bind data, coordinate behavior, and instantiate exported scenes for genuinely variable records.
- Simulation remains pure and deterministic. The migration does not move rules or saved truth into Nodes.
- Renames are decisive. Serialized identifiers, packages, saves, Character Files, and the existing user-data directory do not change.
- A system is finished only when its source, scene, guide, tests, and manifest entry agree.

Current ownership and navigation are recorded in `system-manifest.json`. That manifest changes atomically with every move, rename, new public interface, scene conversion, or test transfer.

## Current certification status

The size, interface, and scene-ownership migration is complete: those architecture-overhaul ceilings are zero, the complete automated suite is green, and the 148-frame graphical Mobile/Vulkan gallery runs through every registered route and interaction family without a script error. The gallery waits for the public application library and follows the live scene-owned Encounter dock, so it exercises the retained production composition rather than an obsolete test hierarchy. The field-Spells footer is now an in-flow scene-authored region, and the regenerated 1280x720 and 800x600 frames keep the level rail, spell records, contextual actions, and persistent Back legible and reachable. Inventory now retains its horizontal browser and command rail at 800x600, fits the four-column action deck and horizontal item record inside the initial viewport, and keeps its integrated Done visible. Party Wealth scrolls only its exchange body, keeps its task-owned Done fixed in both profiles, and no longer duplicates the generic route Back action. Compact combat now retains its tactical board through live resizes, fits the complete two-row View/Action/Tactics deck without an outer scrollbar, and preserves the board through spellbook targeting at both supported profiles. A complete gallery-wide visual audit then found one retained Encounter Items workspace preserving wide minimums after a compact resize; the corrected production-bound fixture now shows its populated ledger, bound character, inspector, command rail, and Back action without clipping in both profiles. The final regenerated gallery completed cleanly and the affected Encounter and ordinary Inventory frames passed manual comparison.

A subsequent physical-layout audit found that the earlier gate did not enforce the plan's feature-folder topology. The manifest now names the exact final directories under all six source boundaries, and the verifier exposes three additional ratchets. The corrective batches have moved persistent shell/navigation composition into `src/ui/shell`, the generic request host and reusable typed request surfaces into `src/ui/shared/interactions`, the complete retained battlefield/command deck/targeting/playback stack into `src/ui/combat`, retained exploration maps and dungeons into `src/ui/exploration`, Character/Allies/Bestiary/Character Files/Age Update/Level Up into `src/ui/characters`, Places/acquired Maps/Journal/scrolling text into `src/ui/journal`, Party Wealth/Shop/Temple/Bank/Treasure into `src/ui/services`, campaign selection/party assembly/character creation into `src/ui/setup`, and cross-feature exchange records into `src/ui/shared/exchange`. The persistent roster, System workspace, route-content coordinator, reusable screen records, and typed route resources now live with their shell or shared owners, eliminating the generic `screens`, `controllers`, root-level `routes`, and `interaction_components` buckets. The repository still has 16 missing target feature directories, 19 undeclared legacy or generic directories, and 70 production files loose at a boundary root. These are active migration debt with final targets of zero; Beta 1 cannot treat the earlier zero size/interface counters as complete architecture certification.

Clean-clone onboarding is also proven at commit `aa4f5dc5`. A temporary fresh checkout containing only tracked files and no prior Godot import state completed first editor import, main-scene smoke launch, all 4,030 assertions, all 313 production-bound Realmz Builder preview assertions, architecture checks, package checks, and scenario validation. The checkout remained clean and was removed after verification. This proves repository-local onboarding; the later sanitized Git LFS clone remains a separate public-release gate.

Local Windows release preparation is proven at commit `6f31513f`. The release preset produced `Realmz Rebuilt.exe` (109,071,360 bytes; SHA-256 `001d1cc9ff639529548151f628a27ee1084edce04162110f6ff40bd62d661827`) and its adjacent PCK (152,974,600 bytes; SHA-256 `48ff6a8ac3e68a613d8edd5f740f64a3a74873141862b9aadc30963c8bfe9c65`). Artifact verification found the exact application library, starter catalog, licenses, and thirteen bundled scenarios with no development resources; the exported executable then completed the CI-equivalent hidden headless smoke with exit code zero and no error record. Final release acceptance still rebuilds and launches the exact tag on all three native runners.

Sanitized-source rehearsal is proven at internal commit `bf986c15`. The manifest-built public repository has root commit `d408512ffd77e21608e87b2cc62aeb5fb2b3f1de`, exactly one reachable commit, a clean tree, and sixteen Git LFS package objects. Public-source verification, Git connectivity, Git LFS integrity, and the complete project gate passed in that repository. A separate `git clone --no-local` checkout then materialized all sixteen `.realmz2` files as valid ZIP archives, completed first Godot import in 22,864 ms, launched the main scene in 6,969 ms, and passed all 4,030 assertions, all 313 production-bound preview assertions, architecture checks, package checks, scenario validation, and parity inventories. This proves the local sanitized Git/LFS acquisition path; the actual GitHub clone and Download ZIP paths remain release gates because they depend on the public host and its archive setting.

Automated size/interface acceptance, gallery-wide visual sign-off, repository-local clean-clone onboarding, local sanitized Git/LFS clone acceptance, and local Windows native pre-certification are complete. Physical feature-folder migration, the independent maintainer exercise, ordinary-play campaign walkthroughs, final Linux/macOS native certification, and hosted GitHub acquisition checks remain open.
