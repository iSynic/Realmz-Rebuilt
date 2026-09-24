# Combat, navigation, and controls acceptance

## Delivered behavior

- Combat keeps dedicated Attack, Fire Weapon, and contextual Use Weapon actions, a shared targeting record, and preview/confirm by default. Immediate Single-Target Actions is optional; areas, sequences, keyboard, and controller still confirm explicitly. Ctrl/Command-hover inspection exposes safe Attacks, Items, and Conditions; clicking pins it.
- Auto evaluates legal action categories independently of the displayed weapon mode, reuses selected spell plans, pursues useful firing positions around obstacles, and yields to the host after each party activation. Blocked actors Guard. Escape disables party Auto; two complete unchanged automated rounds pause it. These are deliberate improvements over the Realmz Castle codebase, not fidelity corrections.
- Right-click on a two-dimensional map starts a legal route immediately. Adventure > Move To saves the preference for left-click route selection; Shift also exposes route previews. Combat displays affordable cells. Ordinary acknowledged movement owns every step, including interruptions and reactions; routes never become saved gameplay state.
- Game, Adventure, Party, Settings, and Help share one menu catalog. Pointer switching and 150 ms leave-region dismissal preserve keyboard/controller ownership. Preferences use five grouped categories, with Save & Load separate. Controller bindings remain an explicit draft; ordinary preferences save immediately.
- The redesigned quick-access panel preserves eight directional choices, paging, unavailable reasons, and explicit confirm/cancel. Controller auditing repaired Trade row focus and Music modal containment. Classic context hotkeys are opt-in because A/S/D/W conflict with WASD; see [Keyboard shortcuts](keyboard-shortcuts.md).

## Weapon audit

The effective Bywater/application catalog contains 17 melee-weapon records with a positive secondary special field. Twelve reference combat spell effects, one references a field-only effect, and four contain non-spell values below the spell-ID boundary. Eligibility remains determined by the existing item-use probe, not by a name match or the presence of that integer alone.

Bull Whip +1/+4 reference effects 4709/4710, both class 8. Their supplied descriptions are consistent with activated distance attacks. Use Weapon exposes that effect while ordinary melee remains adjacent. No item reclassification or Castle-data deviation was needed. The controller fixture exercised the equipped whip and throwing weapon separately and verified once-only resource handling; it does not certify every catalog effect in ordinary play.

## Verification

Evidence from the local implementation checkpoint:

| Mode | Evidence |
| --- | --- |
| Automated | Aggregate test run: 4,887 assertions across 30 suites. Package, media, schema, provenance, workflow, gameplay inventory, export-contract, and architecture checks passed. The aggregate sequence resumed after correcting one method-count violation; it was not a second full test run. Final layout changes passed 1,098 focused assertions. Test-source usage remains 10,497 of the approved 10,500 lines. |
| Auto correctness/performance | 417 focused combat assertions, 25 host scheduling/stall assertions, three safety probes, 867 pursuit-equivalence queries, and 23,760 LOS-equivalence queries. Controlled dense/spell-heavy timings and their limits are recorded in [Runtime performance](runtime-performance.md). |
| Actual controls | Isolated pointer, keyboard, and injected-pad journeys cover all 11 workspace routes, wheel paging, menus, controller drafts, Music containment, inspection, combat Items/Spells, Fire Weapon/Use Weapon preview-confirm, exact charges, immediate targeting, right-click travel, and saved Move To. These use the normal application input and transaction owners. |
| Visual | Pen designs and native Godot captures reviewed at 1280×720 and 800×600. Preferences, Save & Load, and the quick-access panel additionally checked at 150-percent text. Long preference toggle/description text wraps. Display now omits the non-rendering stage placeholder and stacks its control cards in compact mode. |
| Retail | Fresh local Windows release export, package/asset inventory validation, and a 600-frame headless startup smoke. Export construction and startup are not retail combat or campaign-play certification. |

Only presentation settings advance to schema 19. Missing new options retain Preview/Confirm, ordinary mouse movement, and WASD defaults. Gameplay saves, Character Files, and campaign package formats are unchanged.

The dropdown follow-up reproduced an exclusive embedded-window input lock through the production display compositor. Dropdowns now remain nonexclusive, with outside-click dismissal explicitly consumed by the menu owner. An isolated Bywater fixture exercised real item selection, outside-click dismissal with unchanged session snapshots, Escape, heading switching, and leave-region dismissal through outer-window input at 1280×720 and 800×600. Direct shell event injection alone had missed this boundary. Display's non-rendering placeholder was removed; Window & Scale and Image Effects use the recovered space and stack in compact mode.

## Evidence boundaries

No physical gamepad or ordinary player adventure was automated. Hardware prompt detection, device comfort, disconnect/reconnect behavior on each operating system, and full campaign certification remain separate acceptance tracks in [Controller acceptance](controller-acceptance.md).

Navigation rules cover revealed terrain, boat state, occupancy, footprints, and movement costs. Runtime route checks complement those rules but do not establish every authored encounter/reaction path. Healing-recipient pursuit beyond current spell range and a complete spell planner for charmed party members are not claimed. Performance measurements compare deterministic diagnostic workloads, not rendered input latency or exhaustive final-save equivalence.

The route-lifecycle fixture additionally proves that Escape and workspace entry discard pending steps through actual input. Its focus-loss notification and stale-revision injection test the corresponding guards directly; those two cases are not operating-system input observations.

This checkpoint is local only; no public push, tag, or release is included.
