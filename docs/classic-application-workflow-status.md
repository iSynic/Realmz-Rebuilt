# Classic Application Workflow Status

Generated deterministically from `tests/fixtures/oracle/classic-application-workflow-inventory.json`. Castle application completeness and modern host completeness are deliberately reported as separate denominators.

## Denominators

| Scope | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| classic | 60 | 12 | 15 | 33 | 0 |
| host | 8 | 1 | 3 | 4 | 0 |

Delivery state is derived. Missing means required content, simulation, or presentation is absent. Partial includes partial axes, shell-only presentation, unverified persistence, unresolved variants, oracle-required ambiguity, or blockers. Functional requires complete content/simulation, verified or inapplicable persistence, functional presentation, accounted variants, and no blocker. Certified additionally requires accepted presentation and ordinary-play or cross-platform evidence.

## Classic domain heatmap

| Domain | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| Startup and party | 8 | 1 | 1 | 6 | 0 |
| Exploration | 6 | 1 | 1 | 4 | 0 |
| Scenario interaction | 6 | 0 | 1 | 5 | 0 |
| Character management | 5 | 3 | 1 | 1 | 0 |
| Inventory and equipment | 7 | 1 | 3 | 3 | 0 |
| Spellcasting | 3 | 0 | 1 | 2 | 0 |
| Services and economy | 5 | 2 | 1 | 2 | 0 |
| Combat | 8 | 0 | 2 | 6 | 0 |
| Rewards and progression | 5 | 3 | 0 | 2 | 0 |
| Maps and journal | 3 | 1 | 2 | 0 | 0 |
| Save and system | 4 | 0 | 2 | 2 | 0 |

## Completion axes

### Classic

| Castle oracle | Count |
| --- | ---: |
| not-required | 19 |
| required | 13 |
| completed | 28 |

| Remake | Count |
| --- | ---: |
| absent | 4 |
| partial | 32 |
| implemented | 19 |
| divergent | 5 |
| not-applicable | 0 |

| providence | Count |
| --- | ---: |
| not-required | 14 |
| missing | 0 |
| partial | 7 |
| complete | 39 |

| simulation | Count |
| --- | ---: |
| not-applicable | 2 |
| absent | 9 |
| partial | 12 |
| complete | 37 |

| persistence | Count |
| --- | ---: |
| not-applicable | 8 |
| absent | 8 |
| partial | 4 |
| verified | 40 |

| presentation | Count |
| --- | ---: |
| absent | 11 |
| fixture-shell | 8 |
| functional | 41 |
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
| fixture-shell | 2 |
| functional | 5 |
| accepted | 0 |

### Live evidence labels

| Label | Classic | Host |
| --- | ---: | ---: |
| synthetic | 51 | 7 |
| route-harness | 37 | 2 |
| aogm-ordinary | 14 | 2 |
| other-ordinary | 0 | 0 |
| cross-platform | 0 | 0 |

## Release blockers and major gaps

Blockers: **9**. Major gaps: **26**.

- **blocker** `classic.combat.enter-battle` — Battle entry and placement are not certified through ordinary AOGM play. Next: Reach an AOGM battle through ordinary UI and compare setup, placement, save, and first actor.
- **blocker** `classic.combat.resolve-outcome` — The complete victory/defeat/reward/return chain is not implemented through ordinary UI. Next: Implement and certify terminal battle outcomes together with treasure and level-up workflows.
- **blocker** `classic.inventory.use-item` — USE_ITEM returns an explicit unimplemented result and targeted item use is not dispatched. Next: Inventory item-effect families and implement typed target and continuation handling.
- **blocker** `classic.rewards.experience-level-up` — Experience can be granted, but the ordinary level-up workflow and declared LEVEL_UP intent are absent. Next: Trace Castle levelup as an application workflow and implement a serializable multi-character continuation.
- **blocker** `classic.rewards.treasure-distribution` — Ordinary treasure bypasses distribution and assigns each item to the first character with capacity. Next: Implement the ordinary Castle booty continuation and reuse the interaction kind beyond fumble recovery.
- **blocker** `classic.services.pool-share` — Classic Pool and Share are absent despite session wealth fields. Next: Implement source-backed denomination conservation, save tests, and controls.
- **blocker** `classic.services.swap` — MONEY_ACTION is declared but undispatched, so Classic Swap is absent. Next: Trace Swap denominations and implement a typed money-transfer workflow.
- **blocker** `classic.spellcasting.field-camp-cast` — The ordinary field/camp spell catalog and scroll workflows are not complete end to end. Next: Inventory Castle field/camp spell families and scroll state, then wire them through CAST_SPELL.
- **blocker** `host.release.platform-certification` — There is no cross-platform release certification and no accepted release candidate. Next: After Classic blockers close, produce clean exports and run the same Safe package on Windows, macOS, and Linux.
- **major** `classic.character.allies-bestiary` — The allies and bestiary workspaces are absent and the known-entry display contract is incomplete. Next: Trace discovery visibility, complete the immutable display model, and build read-only workspaces.
- **major** `classic.character.change-appearance` — Creation catalogs exist, but active-character portrait and icon changes have no typed intent or workspace. Next: Add typed appearance-change intents and a package-catalog picker.
- **major** `classic.character.reorder-party` — Party order cannot be changed through a typed workflow. Next: Add a reorder intent, deterministic mutation, save test, and workspace controls.
- **major** `classic.character.view-sheet` — The character route is not yet the complete Classic inspection workspace. Next: Complete the detached character read model and build the full sheet tabs.
- **major** `classic.combat.physical-attack` — Physical combat is deeply source-tested but not certified in ordinary campaign play. Next: Complete and save/reload a representative melee and missile exchange in AOGM.
- **major** `classic.combat.tactical-movement` — COMBAT_MOVE is dispatched but the global availability table still describes it as unimplemented. Next: After the audit, make availability derive from the active battle view and validate ordinary movement controls.
- **major** `classic.combat.turn-control` — The battle interaction is functional but not yet an accepted Classic tactical workspace. Next: Run the ordinary AOGM battle loop and close presentation gaps found there.
- **major** `classic.exploration.camp-rest` — Camp toggling exists, but Classic rest duration, recovery, and interruption are not implemented as a complete workflow. Next: Trace Castle rest branches and add a typed rest request plus clock/recovery continuation.
- **major** `classic.exploration.fast-spell` — Numeric fast-spell configuration and invocation are absent and their save ownership is not yet traced end to end. Next: Trace the preference/save fields and ordinary cast handoff, then decide whether the shortcut is Classic state or presentation state.
- **major** `classic.inventory.identify-item` — Shop identification works, but IDENTIFY_ITEM is dead and non-shop identification is unclassified. Next: Trace spell, item, and scenario identification paths and assign or remove the generic intent.
- **major** `classic.inventory.inspect-item` — Item details do not yet expose the complete Classic record and disabled-action reasons. Next: Complete the detached item view and item-detail panel.
- **major** `classic.inventory.manage-equipment` — The declared split/join intents are dead and may not represent a real Classic player workflow. Next: Trace every items.c branch before deleting the intents or implementing a stack operation.
- **major** `classic.maps.authored-journal` — The complete authored journal entry contract and discovery state are not represented end to end. Next: Trace Castle journal records, add deterministic package fields, and wire a read-only journal view.
- **major** `classic.maps.location-notes` — Player location notes are entirely absent and their exact save ownership is not yet traced. Next: Trace the Castle note editor and save fields before defining typed note state.
- **major** `classic.maps.view-acquired` — Map IDs can be acquired, but the journal route explicitly lacks map viewing. Next: Finish package map display data and build a presentation-owned acquired-map viewer.
- **major** `classic.rewards.detect-identify-loot` — Treasure detection and identification are not represented in the 2.0 reward flow. Next: Trace chances, costs, and persistent knowledge before extending treasure distribution.
- **major** `classic.scenario.complex-interaction` — Thief encounter action availability and result routing are not fully traced or represented. Next: Build a synthetic thief encounter oracle fixture and reconcile Providence fields and typed responses.
- **major** `classic.services.bank` — Banking transfers only gold although session state stores more Classic wealth denominations. Next: Trace the bank path and add an oracle fixture before expanding or limiting denominations.
- **major** `classic.services.shop` — The complete shop lifecycle has no ordinary campaign certification. Next: Exercise buy, sell, identify, buyback, leave, and reload in an ordinary shop.
- **major** `classic.services.temple` — The temple lifecycle has no ordinary campaign certification. Next: Exercise representative temple mutations and no-op payment in ordinary play.
- **major** `classic.spellcasting.combat-cast` — Combat spellcasting has extensive deterministic coverage but no ordinary campaign certification. Next: Cast representative single, group, and area spells in an ordinary AOGM battle and verify save/resume.
- **major** `classic.startup.end-adventure` — There is no typed end-adventure boundary distinct from process quit or campaign replacement. Next: Add a committed session-close intent and confirmation workflow.
- **major** `classic.startup.inspect-character` — Party setup cannot open a complete Classic character inspection workspace. Next: Wire the detached character view into party setup without mutating the session.
- **major** `host.package.validation-progress` — Package loading remains perceptibly slow and lacks a real asynchronous progress workflow. Next: Move host validation orchestration off the interactive frame while keeping session construction atomic.
- **major** `host.settings.accessibility` — Control customization and complete multi-scale layout acceptance remain unfinished. Next: Finish keyboard/mouse control help and run layout acceptance at every locked resolution and text scale.
- **major** `host.system.save-previews` — Save/load works, but the required slot preview and mismatch/corruption library is still a shell. Next: Build the read-only save index and preview view before changing repository semantics.

## Oracle-required unknowns

- `classic.exploration.fast-spell` — Cast a numeric fast spell
- `classic.inventory.identify-item` — Identify an item
- `classic.inventory.manage-equipment` — Equip and unequip carried items
- `classic.inventory.use-item` — Use an item
- `classic.maps.location-notes` — Read and edit location notes
- `classic.rewards.detect-identify-loot` — Detect and identify treasure
- `classic.rewards.experience-level-up` — Award experience and level up
- `classic.scenario.complex-interaction` — Resolve a complex or thief encounter
- `classic.services.bank` — Use the bank
- `classic.services.pool-share` — Pool and share party money
- `classic.services.swap` — Swap money between characters
- `classic.spellcasting.field-camp-cast` — Cast field and camp spells
- `classic.system.preferences` — Change Classic application preferences

## Prioritized remaining-work queues

### aogm

- `classic.combat.enter-battle` — Battle entry and placement are not certified through ordinary AOGM play.
- `classic.combat.resolve-outcome` — The complete victory/defeat/reward/return chain is not implemented through ordinary UI.
- `classic.inventory.use-item` — USE_ITEM returns an explicit unimplemented result and targeted item use is not dispatched.
- `classic.rewards.experience-level-up` — Experience can be granted, but the ordinary level-up workflow and declared LEVEL_UP intent are absent.
- `classic.rewards.treasure-distribution` — Ordinary treasure bypasses distribution and assigns each item to the first character with capacity.
- `classic.services.pool-share` — Classic Pool and Share are absent despite session wealth fields.
- `classic.services.swap` — MONEY_ACTION is declared but undispatched, so Classic Swap is absent.
- `classic.spellcasting.field-camp-cast` — The ordinary field/camp spell catalog and scroll workflows are not complete end to end.
- `classic.character.reorder-party` — Party order cannot be changed through a typed workflow.
- `classic.character.view-sheet` — The character route is not yet the complete Classic inspection workspace.
- `classic.combat.physical-attack` — Physical combat is deeply source-tested but not certified in ordinary campaign play.
- `classic.combat.tactical-movement` — COMBAT_MOVE is dispatched but the global availability table still describes it as unimplemented.
- `classic.combat.turn-control` — The battle interaction is functional but not yet an accepted Classic tactical workspace.
- `classic.exploration.camp-rest` — Camp toggling exists, but Classic rest duration, recovery, and interruption are not implemented as a complete workflow.
- `classic.inventory.inspect-item` — Item details do not yet expose the complete Classic record and disabled-action reasons.
- `classic.maps.view-acquired` — Map IDs can be acquired, but the journal route explicitly lacks map viewing.
- `classic.services.shop` — The complete shop lifecycle has no ordinary campaign certification.
- `classic.services.temple` — The temple lifecycle has no ordinary campaign certification.
- `classic.spellcasting.combat-cast` — Combat spellcasting has extensive deterministic coverage but no ordinary campaign certification.
- `classic.startup.inspect-character` — Party setup cannot open a complete Classic character inspection workspace.
- `host.system.save-previews` — Save/load works, but the required slot preview and mismatch/corruption library is still a shell.
- `classic.exploration.contextual-service` — Contextual service entry is not yet demonstrated through ordinary AOGM play.
- `classic.inventory.trade-item` — Trade has no ordinary campaign observation.
- `classic.scenario.select-subject` — Picker variants are tested synthetically but not all observed in ordinary AOGM play.
- `classic.startup.create-character` — The five-step creator has deterministic and UI tests but no recorded ordinary AOGM completion in the audit evidence.

### other-campaign

- `classic.character.age-update` — Age updates have no ordinary-campaign observation because the trigger is rare.
- `classic.combat.retreat` — Retreat variants lack ordinary-campaign evidence.
- `classic.exploration.travel` — Dungeon and boat variants lack ordinary campaign certification.
- `classic.scenario.present-message-media` — Only AOGM's opening media sequence has ordinary-play evidence.
- `classic.startup.select-scenario` — Only AOGM has ordinary campaign-selection evidence in 2.0.
- `host.package.discover-install` — Only AOGM package installation has ordinary evidence.
- `host.vault.import-publish` — Cross-campaign reuse is tested but has no ordinary AOGM-to-War evidence.

### parity

- `classic.character.allies-bestiary` — The allies and bestiary workspaces are absent and the known-entry display contract is incomplete.
- `classic.character.change-appearance` — Creation catalogs exist, but active-character portrait and icon changes have no typed intent or workspace.
- `classic.exploration.fast-spell` — Numeric fast-spell configuration and invocation are absent and their save ownership is not yet traced end to end.
- `classic.inventory.identify-item` — Shop identification works, but IDENTIFY_ITEM is dead and non-shop identification is unclassified.
- `classic.inventory.manage-equipment` — The declared split/join intents are dead and may not represent a real Classic player workflow.
- `classic.maps.authored-journal` — The complete authored journal entry contract and discovery state are not represented end to end.
- `classic.maps.location-notes` — Player location notes are entirely absent and their exact save ownership is not yet traced.
- `classic.rewards.detect-identify-loot` — Treasure detection and identification are not represented in the 2.0 reward flow.
- `classic.scenario.complex-interaction` — Thief encounter action availability and result routing are not fully traced or represented.
- `classic.services.bank` — Banking transfers only gold although session state stores more Classic wealth denominations.
- `classic.startup.end-adventure` — There is no typed end-adventure boundary distinct from process quit or campaign replacement.
- `classic.system.preferences` — Classic's editable stock spell/race/caste names are not represented and may conflict with immutable package content.

### polish

- `host.release.platform-certification` — There is no cross-platform release certification and no accepted release candidate.
- `host.package.validation-progress` — Package loading remains perceptibly slow and lacks a real asynchronous progress workflow.
- `host.settings.accessibility` — Control customization and complete multi-scale layout acceptance remain unfinished.
- `classic.spellcasting.choose-power-target` — SELECT_SPELL_POWER and SELECT_SPELL_TARGET are dead scaffolding beside the complete CAST_SPELL payload.
- `classic.system.quit` — Unsaved-state quit confirmation is not an evidenced ordinary workflow.

## Coverage caveats

- Synthetic evidence proves a controlled fixture, not an ordinary campaign workflow.
- Route-harness evidence proves an automated route and may bypass ordinary navigation or presentation.
- AOGM and other ordinary-play labels certify only the listed workflow variants actually observed.
- Cross-platform certification requires the same Safe package and workflow to pass on every release platform.
- Differential cases provide behavioral depth. This inventory supplies the fixed application denominator.
