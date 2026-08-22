# Classic Application Workflow Status

Generated deterministically from `tests/fixtures/oracle/classic-application-workflow-inventory.json`. Castle application completeness and modern host completeness are deliberately reported as separate denominators.

## Denominators

| Scope | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| classic | 69 | 0 | 15 | 53 | 1 |
| host | 8 | 1 | 1 | 6 | 0 |

Delivery state is derived. Missing means required content, simulation, or presentation is absent. Partial includes partial axes, shell-only presentation, unverified persistence, unresolved variants, oracle-required ambiguity, or blockers. Functional requires complete content/simulation, verified or inapplicable persistence, functional presentation, accounted variants, and no blocker. Certified additionally requires accepted presentation and ordinary-play or cross-platform evidence.

## Current parity-convergence batch

**Classic context music and playlists** (`classic-context-music`)

At the baseline, the application had no Realmz music playback or source-visible Music menu despite the pinned Castle data model preserving twenty context slots and three per-slot modes. This batch adds a deterministic OpenMPT-backed stock music bank, context-aware playback, a complete Classic playlist workspace, and separately persisted host audio controls without changing simulation or campaign saves.

Planning target: **60%** ordinary-play acceptance and presentation, **25%** missing or partial workflow implementation, and **15%** discrepancy-triggered archaeology. These percentages guide batch selection; they are not inferred from commits or test counts.

| Workflow | Mode | Priority | Expected evidence | Owned gaps |
| --- | --- | --- | --- | --- |
| `classic.system.music-playlists` | implementation | classic-missing | - | GAP-SYS-004 |
| `classic.system.preferences` | implementation | aogm-major-partial | - |  |
| `host.settings.accessibility` | implementation | aogm-major-partial | - | GAP-HOST-004 |
| `classic.exploration.travel` | certification | aogm-certification | aogm-ordinary |  |

### Batch count delta

| Scope | State | Baseline | Current | Delta |
| --- | --- | ---: | ---: | ---: |
| classic | missing | 1 | 0 | -1 |
| classic | partial | 14 | 15 | +1 |
| classic | functional | 53 | 53 | 0 |
| classic | certified | 1 | 1 | 0 |
| host | missing | 1 | 1 | 0 |
| host | partial | 1 | 1 | 0 |
| host | functional | 6 | 6 | 0 |
| host | certified | 0 | 0 | 0 |

## Classic domain heatmap

| Domain | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| Startup and party | 8 | 0 | 0 | 8 | 0 |
| Exploration | 6 | 0 | 0 | 6 | 0 |
| Scenario interaction | 6 | 0 | 1 | 5 | 0 |
| Character management | 5 | 0 | 2 | 3 | 0 |
| Inventory and equipment | 9 | 0 | 2 | 7 | 0 |
| Spellcasting | 3 | 0 | 1 | 2 | 0 |
| Services and economy | 5 | 0 | 1 | 4 | 0 |
| Combat | 14 | 0 | 2 | 11 | 1 |
| Rewards and progression | 5 | 0 | 1 | 4 | 0 |
| Maps and journal | 3 | 0 | 2 | 1 | 0 |
| Save and system | 5 | 0 | 3 | 2 | 0 |

## Completion axes

### Classic

| Castle oracle | Count |
| --- | ---: |
| not-required | 9 |
| required | 8 |
| completed | 52 |

| Remake | Count |
| --- | ---: |
| absent | 7 |
| partial | 35 |
| implemented | 14 |
| divergent | 13 |
| not-applicable | 0 |

| providence | Count |
| --- | ---: |
| not-required | 19 |
| missing | 0 |
| partial | 3 |
| complete | 47 |

| simulation | Count |
| --- | ---: |
| not-applicable | 3 |
| absent | 0 |
| partial | 8 |
| complete | 58 |

| persistence | Count |
| --- | ---: |
| not-applicable | 6 |
| absent | 0 |
| partial | 1 |
| verified | 62 |

| presentation | Count |
| --- | ---: |
| absent | 0 |
| fixture-shell | 1 |
| functional | 67 |
| accepted | 1 |

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
| synthetic | 69 | 7 |
| route-harness | 40 | 2 |
| aogm-ordinary | 41 | 3 |
| other-ordinary | 0 | 0 |
| cross-platform | 0 | 0 |

## Release blockers and major gaps

Blockers: **1**. Major gaps: **13**.

- **blocker** `host.release.platform-certification` - There is no cross-platform release certification and no accepted release candidate. Next: After Classic blockers close, produce clean exports and run the same Safe package on Windows, macOS, and Linux.
- **major** `classic.character.allies-bestiary` - Current held-over allies now have a functional read-only workspace, but the Bestiary cannot be reconstructed from the package because menu visibility and normalized descriptions are not preserved per monster. Next: Correct Providence schema v3 and Rebuilt decoding to preserve every menu-visible monster, its description, and not-on-menu flag, then add the Bestiary route without inventing discovery state.
- **major** `classic.character.view-sheet` - Castle's lifetime combat record and prestige cannot yet be calculated accurately. Next: Add source-backed lifetime counters and update every owning combat and magic mutation path before enabling the visible Lifetime Record tab.
- **major** `classic.combat.resolve-outcome` - Ordinary victory and reward return work, but the terminal combat workflow is not yet accepted. Next: Obtain ordinary-play acceptance of the corrected command deck, then exercise ordinary defeat or retreat and a reward that produces a level-up.
- **major** `classic.combat.resolve-outcome` - Battle reward modes 5 and 10 remain unresolved end to end. Next: Characterize the suspicious mode-5 incidental/RNG branches and mode-10 restart field with controlled Castle fixtures, then implement each distinct runtime continuation without changing schema v2 unless the fixture disproves positional preservation.
- **major** `classic.combat.undo` - Movement-only Undo, result invalidation, condition gates, occupied-cell safety, presentation, and save restoration are implemented; repeated Undo and initiative-edge re-entry remain runtime-unobserved. Next: Run the synthetic Castle fixtures for repeated Undo and first/last-slot or round-boundary re-entry before expanding the bounded implementation.
- **major** `classic.inventory.use-item` - Ordinary AOGM play proves a fixed-power party-state Torch and a saveable field scroll target/consumption path; discard, case transfer, door/XAP items, random-power combat, and broader specials remain explicit. Next: Characterize discard, case-transfer, door/XAP, random-power combat, battlefield-area/repeated targeting, and broader special behavior only when parity or a reachable campaign requires each branch.
- **major** `classic.maps.location-notes` - Historical notes are readable in source order but do not yet recreate Castle's temporary map recentering and saved darkness view. Next: Add a mutation-free note browser derived from authoritative topology and the saved darkness value, then verify land and dungeon records through MCP.
- **major** `classic.maps.view-acquired` - Exact dungeon player-map composition is not yet proven against Castle. Next: Capture one synthetic Castle dungeon player map and compare wall, door, secret, and party-marker pixels before declaring exact presentation parity.
- **major** `classic.rewards.treasure-distribution` - Castle's two incidental random-item draws and battle-mode interaction are not yet reproduced. Next: Use controlled Castle RNG fixtures for ordinary, XP-only, and bonus-treasure battle rewards before implementing or correcting the random drops.
- **major** `classic.scenario.complex-interaction` - The dedicated thief menu and timed Pick Lock flow are source-shaped; trap spell resolution and controlled Castle/UI acceptance remain incomplete. Next: Route the trap spell through the source-backed application spell effect, then run a controlled Castle comparison and ordinary campaign UI acceptance.
- **major** `classic.spellcasting.field-camp-cast` - Ordinary AOGM camp play proves power-selected scribing, five-slot persistence, saveable party targeting, no-SP scroll use, and exact-slot consumption; invalid-field discard, case transfer, allied targets, and map effects remain explicit. Next: Implement discard, case-transfer, allied-target, and map-effect branches only from bounded differential evidence when parity or a reachable campaign requires them.
- **major** `classic.system.music-playlists` - Indoor automatic selection and scenario Custom 1–3 music remain unresolved. Next: Add an explicit Providence base-scale field and normalized scenario music resources, then certify Indoor and Custom 1–3 through ordinary packages without inferring either from landlook.
- **major** `host.settings.accessibility` - Control customization and complete multi-scale layout acceptance remain unfinished. Next: Finish keyboard/mouse control help and run layout acceptance at every locked resolution and text scale.

## Oracle-required unknowns

- `classic.combat.undo` - Undo the active combat activation
- `classic.inventory.manage-equipment` - Equip and unequip carried items
- `classic.inventory.use-item` - Use an item
- `classic.maps.authored-journal` - Read the authored journal
- `classic.maps.location-notes` - Read and edit location notes
- `classic.scenario.complex-interaction` - Resolve a complex or thief encounter
- `classic.system.music-playlists` - Configure and hear context music
- `classic.system.preferences` - Change Classic application preferences

## Prioritized remaining-work queues

### aogm

- `classic.combat.resolve-outcome` - Ordinary victory and reward return work, but the terminal combat workflow is not yet accepted.

### other-campaign

- `classic.system.music-playlists` - Indoor automatic selection and scenario Custom 1–3 music remain unresolved.
- `classic.character.age-update` - Age updates have no ordinary-campaign observation because the trigger is rare.
- `classic.exploration.travel` - Dungeon and boat variants lack ordinary campaign certification.
- `classic.maps.authored-journal` - Authored journal discovery and browsing have synthetic proof only.
- `classic.maps.location-notes` - Location-note creation, editing, removal, and restoration have synthetic proof only.
- `classic.scenario.present-message-media` - Only AOGM's opening media sequence has ordinary-play evidence.
- `classic.services.bank` - The complete bank-backed Swap lifecycle has no ordinary campaign certification.
- `classic.startup.select-scenario` - Only AOGM has ordinary campaign-selection evidence in 2.0.
- `host.package.discover-install` - Only AOGM package installation has ordinary evidence.
- `host.vault.import-publish` - Cross-campaign reuse is tested but has no ordinary AOGM-to-War evidence.

### parity

- `classic.character.allies-bestiary` - Current held-over allies now have a functional read-only workspace, but the Bestiary cannot be reconstructed from the package because menu visibility and normalized descriptions are not preserved per monster.
- `classic.character.view-sheet` - Castle's lifetime combat record and prestige cannot yet be calculated accurately.
- `classic.combat.resolve-outcome` - Battle reward modes 5 and 10 remain unresolved end to end.
- `classic.combat.undo` - Movement-only Undo, result invalidation, condition gates, occupied-cell safety, presentation, and save restoration are implemented; repeated Undo and initiative-edge re-entry remain runtime-unobserved.
- `classic.inventory.use-item` - Ordinary AOGM play proves a fixed-power party-state Torch and a saveable field scroll target/consumption path; discard, case transfer, door/XAP items, random-power combat, and broader specials remain explicit.
- `classic.maps.location-notes` - Historical notes are readable in source order but do not yet recreate Castle's temporary map recentering and saved darkness view.
- `classic.maps.view-acquired` - Exact dungeon player-map composition is not yet proven against Castle.
- `classic.rewards.treasure-distribution` - Castle's two incidental random-item draws and battle-mode interaction are not yet reproduced.
- `classic.scenario.complex-interaction` - The dedicated thief menu and timed Pick Lock flow are source-shaped; trap spell resolution and controlled Castle/UI acceptance remain incomplete.
- `classic.spellcasting.field-camp-cast` - Ordinary AOGM camp play proves power-selected scribing, five-slot persistence, saveable party targeting, no-SP scroll use, and exact-slot consumption; invalid-field discard, case transfer, allied targets, and map effects remain explicit.
- `classic.character.view-sheet` - Several nonzero Classic ability slots lack verified display names.
- `classic.maps.authored-journal` - Castle's PRFN default and the authored-journal rendering boundary remain outside the verified subset.
- `classic.maps.location-notes` - Castle's two dialog exit labels and exact cancellation semantics are not established by source alone.
- `classic.maps.view-acquired` - Classic scrolling TEXT encoding and style resources remain only partially represented.
- `classic.maps.view-acquired` - Malformed crop starts and authored picture rectangles lack boundary observations.
- `classic.services.shop` - Normalized shop stock omits native empty-slot provenance.
- `classic.system.preferences` - Classic's editable stock spell/race/caste names are not represented and may conflict with immutable package content.

### polish

- `host.release.platform-certification` - There is no cross-platform release certification and no accepted release candidate.
- `host.settings.accessibility` - Control customization and complete multi-scale layout acceptance remain unfinished.
- `classic.exploration.travel` - Ordinary AOGM dungeon presentation shows two solid green rectangular cells that do not visually match the surrounding Classic dungeon composition.
- `classic.maps.view-acquired` - Ordinary AOGM acquisition, interaction-boundary restore, reward completion, persistence, and Maps/Notes browsing are proven, but the acquired-map presentation has not been user-accepted.
- `classic.startup.end-adventure` - Save-before-close ordering is characterized through the host transaction and repositories separately, but has no full composition-root failure-injection test.
- `classic.system.preferences` - Classic's reduced-sound preference is not represented.
- `classic.system.quit` - Typed Quit choices and host transaction ordering are characterized, but the real window-close notification and save-repository failure path lack composition-root proof.

## Coverage caveats

- Synthetic evidence proves a controlled fixture, not an ordinary campaign workflow.
- Route-harness evidence proves an automated route and may bypass ordinary navigation or presentation.
- AOGM and other ordinary-play labels certify only the listed workflow variants actually observed.
- Cross-platform certification requires the same Safe package and workflow to pass on every release platform.
- Differential cases provide behavioral depth. This inventory supplies the fixed application denominator.
- Gaps not selected by the current batch remain explicitly deferred; their presence alone does not authorize archaeology.
