# Classic Application Workflow Status

Generated deterministically from `tests/fixtures/oracle/classic-application-workflow-inventory.json`. Castle application completeness and modern host completeness are deliberately reported as separate denominators.

## Denominators

| Scope | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| classic | 60 | 2 | 16 | 42 | 0 |
| host | 8 | 1 | 1 | 6 | 0 |

Delivery state is derived. Missing means required content, simulation, or presentation is absent. Partial includes partial axes, shell-only presentation, unverified persistence, unresolved variants, oracle-required ambiguity, or blockers. Functional requires complete content/simulation, verified or inapplicable persistence, functional presentation, accounted variants, and no blocker. Certified additionally requires accepted presentation and ordinary-play or cross-platform evidence.

## Classic domain heatmap

| Domain | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| Startup and party | 8 | 0 | 0 | 8 | 0 |
| Exploration | 6 | 1 | 1 | 4 | 0 |
| Scenario interaction | 6 | 0 | 2 | 4 | 0 |
| Character management | 5 | 1 | 1 | 3 | 0 |
| Inventory and equipment | 7 | 0 | 3 | 4 | 0 |
| Spellcasting | 3 | 0 | 1 | 2 | 0 |
| Services and economy | 5 | 0 | 1 | 4 | 0 |
| Combat | 8 | 0 | 2 | 6 | 0 |
| Rewards and progression | 5 | 0 | 1 | 4 | 0 |
| Maps and journal | 3 | 0 | 2 | 1 | 0 |
| Save and system | 4 | 0 | 2 | 2 | 0 |

## Completion axes

### Classic

| Castle oracle | Count |
| --- | ---: |
| not-required | 10 |
| required | 10 |
| completed | 40 |

| Remake | Count |
| --- | ---: |
| absent | 5 |
| partial | 30 |
| implemented | 14 |
| divergent | 11 |
| not-applicable | 0 |

| providence | Count |
| --- | ---: |
| not-required | 13 |
| missing | 0 |
| partial | 3 |
| complete | 44 |

| simulation | Count |
| --- | ---: |
| not-applicable | 2 |
| absent | 1 |
| partial | 11 |
| complete | 46 |

| persistence | Count |
| --- | ---: |
| not-applicable | 6 |
| absent | 1 |
| partial | 1 |
| verified | 52 |

| presentation | Count |
| --- | ---: |
| absent | 2 |
| fixture-shell | 0 |
| functional | 58 |
| accepted | 0 |

### Host

| providence | Count |
| --- | ---: |
| not-required | 4 |
| missing | 0 |
| partial | 0 |
| complete | 4 |

| simulation | Count |
| --- | ---: |
| not-applicable | 7 |
| absent | 0 |
| partial | 0 |
| complete | 1 |

| persistence | Count |
| --- | ---: |
| not-applicable | 3 |
| absent | 0 |
| partial | 0 |
| verified | 5 |

| presentation | Count |
| --- | ---: |
| absent | 1 |
| fixture-shell | 0 |
| functional | 7 |
| accepted | 0 |

### Live evidence labels

| Label | Classic | Host |
| --- | ---: | ---: |
| synthetic | 58 | 7 |
| route-harness | 39 | 2 |
| aogm-ordinary | 22 | 3 |
| other-ordinary | 0 | 0 |
| cross-platform | 0 | 0 |

## Release blockers and major gaps

Blockers: **1**. Major gaps: **20**.

- **blocker** `host.release.platform-certification` — There is no cross-platform release certification and no accepted release candidate. Next: After Classic blockers close, produce clean exports and run the same Safe package on Windows, macOS, and Linux.
- **major** `classic.character.allies-bestiary` — The allies and bestiary workspaces are absent and the known-entry display contract is incomplete. Next: Trace discovery visibility, complete the immutable display model, and build read-only workspaces.
- **major** `classic.character.view-sheet` — Castle's lifetime combat record and prestige cannot yet be calculated accurately. Next: Add source-backed lifetime counters and update every owning combat and magic mutation path before enabling the visible Lifetime Record tab.
- **major** `classic.combat.resolve-outcome` — Ordinary victory and reward return work, but the terminal combat workflow is not yet accepted. Next: Obtain ordinary-play acceptance of the corrected command deck, then exercise ordinary defeat or retreat and a reward that produces a level-up.
- **major** `classic.combat.resolve-outcome` — Battle reward modes 5 and 10 and opcode 48 bonus treasure remain unresolved end to end. Next: Characterize the suspicious mode-5 incidental/RNG branches and mode-10 restart field with controlled Castle fixtures, then implement each distinct runtime continuation without changing schema v2 unless the fixture disproves positional preservation.
- **major** `classic.exploration.fast-spell` — Numeric fast-spell configuration and invocation are absent and their save ownership is not yet traced end to end. Next: Trace the preference/save fields and ordinary cast handoff, then decide whether the shortcut is Classic state or presentation state.
- **major** `classic.exploration.travel` — Ordinary positive-tile blocked land movement now advances the attempted tile time and runs current-cell random checks, while zero/negative tiles, boat/shore cancellation, special dungeon walls, and timed-location deltas remain unresolved. Next: Use controlled fixtures for zero/negative land tiles, boat/shore cancellation, special dungeon wall bits, and attempted-coordinate timed gates before broadening the topology result.
- **major** `classic.inventory.identify-item` — Shop identification works, but IDENTIFY_ITEM is dead and non-shop identification is unclassified. Next: Trace spell, item, and scenario identification paths and assign or remove the generic intent.
- **major** `classic.inventory.manage-equipment` — The declared split/join intents are dead and may not represent a real Classic player workflow. Next: Trace every items.c branch before deleting the intents or implementing a stack operation.
- **major** `classic.inventory.use-item` — Fixed-power charged items and field scroll scribing/use now preserve exact targets, charges/load, five-slot state, sound, save/resume, and transactional cancellation; combat scrolls, discard, case transfer, door/XAP items, random-power combat, spatial/repeated targets, and broader specials remain explicit. Next: Exercise an ordinary AOGM charged item and scroll route, then characterize combat scroll, discard, case-transfer, door/XAP, random-power combat, and target-abort behavior separately.
- **major** `classic.maps.location-notes` — Historical notes are readable in source order but do not yet recreate Castle's temporary map recentering and saved darkness view. Next: Add a mutation-free note browser derived from authoritative topology and the saved darkness value, then verify land and dungeon records through MCP.
- **major** `classic.maps.view-acquired` — Exact dungeon player-map composition is not yet proven against Castle. Next: Capture one synthetic Castle dungeon player map and compare wall, door, secret, and party-marker pixels before declaring exact presentation parity.
- **major** `classic.maps.view-acquired` — Acquisition and browsing have synthetic proof but no ordinary AOGM acceptance. Next: Acquire an AOGM player map, save and reload at the immediate display boundary, then browse it from Maps/Notes through the ordinary shell.
- **major** `classic.rewards.treasure-distribution` — Castle's two incidental random-item draws and battle-mode interaction are not yet reproduced. Next: Use controlled Castle RNG fixtures for ordinary, XP-only, and bonus-treasure battle rewards before implementing or correcting the random drops.
- **major** `classic.scenario.complex-interaction` — Thief encounter action availability and result routing are not fully traced or represented. Next: Build a synthetic thief encounter oracle fixture and reconcile Providence fields and typed responses.
- **major** `classic.scenario.random-timed-encounter` — Timed records dispatch through a save-owned scheduler, but location-changing and post-action-destination timed programs lack a dedicated end-to-end fixture. Next: Add a synthetic timed AP that changes map or coordinate, yields, applies any source-owned AP destination semantics, resumes the remaining scan, and performs the final random check at the resulting location.
- **major** `classic.services.shop` — The complete shop lifecycle has no ordinary campaign certification. Next: Exercise buy, sell, identify, buyback, leave, and reload in an ordinary shop.
- **major** `classic.services.temple` — The implemented temple subset has no ordinary campaign certification. Next: Exercise representative temple mutations and no-op payment in ordinary play.
- **major** `classic.spellcasting.combat-cast` — Combat spellcasting has extensive deterministic coverage but no ordinary campaign certification. Next: Cast representative single, group, and area spells in an ordinary AOGM battle and verify save/resume.
- **major** `classic.spellcasting.field-camp-cast` — Field casting, camp mode, five-slot scroll persistence, parchment-backed Make Scroll, and transactional no-SP field scroll use are implemented; combat scroll use, invalid-field discard, case transfer, allied targets, and map effects remain explicit. Next: Exercise the field scroll workflow in ordinary AOGM play, then implement combat/discard/case-transfer branches only from their bounded differential evidence.
- **major** `host.settings.accessibility` — Control customization and complete multi-scale layout acceptance remain unfinished. Next: Finish keyboard/mouse control help and run layout acceptance at every locked resolution and text scale.

## Oracle-required unknowns

- `classic.exploration.fast-spell` — Cast a numeric fast spell
- `classic.exploration.travel` — Travel on land and in dungeons
- `classic.inventory.identify-item` — Identify an item
- `classic.inventory.manage-equipment` — Equip and unequip carried items
- `classic.inventory.use-item` — Use an item
- `classic.maps.authored-journal` — Read the authored journal
- `classic.maps.location-notes` — Read and edit location notes
- `classic.scenario.complex-interaction` — Resolve a complex or thief encounter
- `classic.scenario.random-timed-encounter` — Enter a random or timed encounter
- `classic.system.preferences` — Change Classic application preferences

## Prioritized remaining-work queues

### aogm

- `classic.combat.resolve-outcome` — Ordinary victory and reward return work, but the terminal combat workflow is not yet accepted.
- `classic.exploration.travel` — Ordinary positive-tile blocked land movement now advances the attempted tile time and runs current-cell random checks, while zero/negative tiles, boat/shore cancellation, special dungeon walls, and timed-location deltas remain unresolved.
- `classic.inventory.use-item` — Fixed-power charged items and field scroll scribing/use now preserve exact targets, charges/load, five-slot state, sound, save/resume, and transactional cancellation; combat scrolls, discard, case transfer, door/XAP items, random-power combat, spatial/repeated targets, and broader specials remain explicit.
- `classic.maps.view-acquired` — Acquisition and browsing have synthetic proof but no ordinary AOGM acceptance.
- `classic.scenario.random-timed-encounter` — Timed records dispatch through a save-owned scheduler, but location-changing and post-action-destination timed programs lack a dedicated end-to-end fixture.
- `classic.services.shop` — The complete shop lifecycle has no ordinary campaign certification.
- `classic.services.temple` — The implemented temple subset has no ordinary campaign certification.
- `classic.spellcasting.combat-cast` — Combat spellcasting has extensive deterministic coverage but no ordinary campaign certification.
- `classic.spellcasting.field-camp-cast` — Field casting, camp mode, five-slot scroll persistence, parchment-backed Make Scroll, and transactional no-SP field scroll use are implemented; combat scroll use, invalid-field discard, case transfer, allied targets, and map effects remain explicit.
- `classic.combat.physical-attack` — The missile branch still lacks ordinary campaign evidence.
- `classic.exploration.contextual-service` — Contextual service entry is not yet demonstrated through ordinary AOGM play.
- `classic.inventory.trade-item` — Trade has no ordinary campaign observation.
- `classic.rewards.experience-level-up` — Experience award is observed in AOGM, but an actual level-up remains fixture-only.
- `classic.scenario.select-subject` — Picker variants are tested synthetically but not all observed in ordinary AOGM play.
- `classic.startup.create-character` — The five-step creator has deterministic and UI tests but no recorded ordinary AOGM completion in the audit evidence.
- `classic.startup.end-adventure` — End Adventure has synthetic interaction and teardown proof but no ordinary AOGM acceptance.

### other-campaign

- `classic.character.age-update` — Age updates have no ordinary-campaign observation because the trigger is rare.
- `classic.combat.retreat` — Retreat variants lack ordinary-campaign evidence.
- `classic.exploration.travel` — Dungeon and boat variants lack ordinary campaign certification.
- `classic.maps.authored-journal` — Authored journal discovery and browsing have synthetic proof only.
- `classic.maps.location-notes` — Location-note creation, editing, removal, and restoration have synthetic proof only.
- `classic.scenario.present-message-media` — Only AOGM's opening media sequence has ordinary-play evidence.
- `classic.services.bank` — The complete bank-backed Swap lifecycle has no ordinary campaign certification.
- `classic.startup.select-scenario` — Only AOGM has ordinary campaign-selection evidence in 2.0.
- `host.package.discover-install` — Only AOGM package installation has ordinary evidence.
- `host.vault.import-publish` — Cross-campaign reuse is tested but has no ordinary AOGM-to-War evidence.

### parity

- `classic.character.allies-bestiary` — The allies and bestiary workspaces are absent and the known-entry display contract is incomplete.
- `classic.character.view-sheet` — Castle's lifetime combat record and prestige cannot yet be calculated accurately.
- `classic.combat.resolve-outcome` — Battle reward modes 5 and 10 and opcode 48 bonus treasure remain unresolved end to end.
- `classic.exploration.fast-spell` — Numeric fast-spell configuration and invocation are absent and their save ownership is not yet traced end to end.
- `classic.inventory.identify-item` — Shop identification works, but IDENTIFY_ITEM is dead and non-shop identification is unclassified.
- `classic.inventory.manage-equipment` — The declared split/join intents are dead and may not represent a real Classic player workflow.
- `classic.maps.location-notes` — Historical notes are readable in source order but do not yet recreate Castle's temporary map recentering and saved darkness view.
- `classic.maps.view-acquired` — Exact dungeon player-map composition is not yet proven against Castle.
- `classic.rewards.treasure-distribution` — Castle's two incidental random-item draws and battle-mode interaction are not yet reproduced.
- `classic.scenario.complex-interaction` — Thief encounter action availability and result routing are not fully traced or represented.
- `classic.character.view-sheet` — Several nonzero Classic ability slots lack verified display names.
- `classic.combat.tactical-movement` — Realmz 2.0 requires an explicit switch from missile to melee before hostile collision, while Castle can perform that switch through its Auto Weapon Switch preference.
- `classic.maps.authored-journal` — Castle's Auto Note preference and unsafe journal cursor boundary remain outside the verified authored-journal subset.
- `classic.maps.location-notes` — Castle's two dialog exit labels and exact cancellation semantics are not established by source alone.
- `classic.maps.view-acquired` — Classic scrolling TEXT encoding and style resources remain only partially represented.
- `classic.maps.view-acquired` — Malformed crop starts and authored picture rectangles lack boundary observations.
- `classic.services.shop` — Normalized shop stock omits native empty-slot provenance.
- `classic.system.preferences` — Classic's editable stock spell/race/caste names are not represented and may conflict with immutable package content.

### polish

- `host.release.platform-certification` — There is no cross-platform release certification and no accepted release candidate.
- `host.settings.accessibility` — Control customization and complete multi-scale layout acceptance remain unfinished.
- `classic.spellcasting.choose-power-target` — SELECT_SPELL_POWER and SELECT_SPELL_TARGET are dead scaffolding beside the complete CAST_SPELL payload.
- `classic.startup.end-adventure` — Save-before-close ordering is characterized through the host transaction and repositories separately, but has no full composition-root failure-injection test.
- `classic.system.preferences` — Classic's reduced-sound preference is not represented.
- `classic.system.quit` — Typed Quit choices and host transaction ordering are characterized, but the real window-close notification and save-repository failure path lack composition-root proof.

## Coverage caveats

- Synthetic evidence proves a controlled fixture, not an ordinary campaign workflow.
- Route-harness evidence proves an automated route and may bypass ordinary navigation or presentation.
- AOGM and other ordinary-play labels certify only the listed workflow variants actually observed.
- Cross-platform certification requires the same Safe package and workflow to pass on every release platform.
- Differential cases provide behavioral depth. This inventory supplies the fixed application denominator.
