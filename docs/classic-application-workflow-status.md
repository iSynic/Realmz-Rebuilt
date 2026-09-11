# Classic Application Workflow Status

Generated deterministically from `tests/fixtures/oracle/classic-application-workflow-inventory.json`. Castle application completeness and modern host completeness are deliberately reported as separate denominators.

## Denominators

| Scope | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| classic | 69 | 0 | 0 | 55 | 14 |
| host | 8 | 0 | 1 | 5 | 2 |

Delivery state is derived. Missing means required content, simulation, or presentation is absent. Partial includes partial axes, shell-only presentation, unverified persistence, unresolved variants, oracle-required ambiguity, or blockers. Functional requires complete content/simulation, verified or inapplicable persistence, functional presentation, accounted variants, and no blocker. Certified additionally requires accepted presentation and ordinary-play or cross-platform evidence.

## Current parity-convergence batch

**AOGM contextual encounters and Wrath owner-bound chest outcomes** (`ap-contextual-and-owner-bound-encounters`)

Batch complete: AOGM's zero-slot contextual RNG defect is repaired, with entry, wrong-set repetition and exact reward/region-disable/default reentry verified. Wrath AP 44 has equal detection/disarm, armed-trap failure, unarmed lock failure and eight-item lock-reward repeats. Detected-trap and trap-warning restores reproduce exact final game/RNG state; pending Treasure reproduces every suffix state. Done alone sets chance zero and prevents duplicate rewards. The recipes retain 49 passes and two historical failures across all thirteen bundled scenarios under their recorded package/library identities, without certification upgrades. Clean-reference Tier 2 passes 91 focused assertions. The full aggregate passes 4212 assertions across 28 suites plus package, media, architecture, export, schema and inventory gates in an isolated copy with hash-matched product content and committed project settings. Development autoloads remain untouched in the working checkout. The forced five-frame startup smoke retains its known one-object teardown warning; strict tests and the closed gameplay fixture have no teardown errors. Protocol build and 37 tests pass, with two opt-in engine tests skipped. Wrath preparation/source/replay work took approximately 29 minutes before batch gates; full lock replays took 19.22/18.86 seconds and the saved suffix 9.51 seconds, with no new tooling implementation. Next coverage favors the retained pending-tumbler save boundary, then War pooled-payment edges using existing baselines. Native performance, complete combat replay, full campaign certification and broader bridge capabilities remain separate; reported failures take priority.

AP batches use failure-first priorities: known failures, untested high-risk behavior, meaningful variants, and broader representatives. Verification mode records existing functional behavior without claiming full campaign certification; implementation, verification, and certification remain distinct modes.

| Workflow | Mode | Priority | Expected evidence | Owned gaps |
| --- | --- | --- | --- | --- |
| `classic.scenario.choose-response` | verification | known-failure | live-route |  |
| `classic.system.save-game` | verification | meaningful-variant | live-route |  |
| `classic.scenario.trigger-action-point` | verification | known-failure | runtime-integration |  |

### Batch count delta

| Scope | State | Baseline | Current | Delta |
| --- | --- | ---: | ---: | ---: |
| classic | missing | 0 | 0 | 0 |
| classic | partial | 0 | 0 | 0 |
| classic | functional | 55 | 55 | 0 |
| classic | certified | 14 | 14 | 0 |
| host | missing | 0 | 0 | 0 |
| host | partial | 1 | 1 | 0 |
| host | functional | 5 | 5 | 0 |
| host | certified | 2 | 2 | 0 |

## Classic domain heatmap

| Domain | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| Startup and party | 8 | 0 | 0 | 7 | 1 |
| Exploration | 6 | 0 | 0 | 4 | 2 |
| Scenario interaction | 6 | 0 | 0 | 3 | 3 |
| Character management | 5 | 0 | 0 | 5 | 0 |
| Inventory and equipment | 9 | 0 | 0 | 9 | 0 |
| Spellcasting | 3 | 0 | 0 | 1 | 2 |
| Services and economy | 5 | 0 | 0 | 5 | 0 |
| Combat | 14 | 0 | 0 | 9 | 5 |
| Rewards and progression | 5 | 0 | 0 | 4 | 1 |
| Maps and journal | 3 | 0 | 0 | 3 | 0 |
| Save and system | 5 | 0 | 0 | 5 | 0 |

## Completion axes

### Classic

| Castle oracle | Count |
| --- | ---: |
| not-required | 9 |
| required | 0 |
| completed | 60 |

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
| partial | 0 |
| complete | 50 |

| simulation | Count |
| --- | ---: |
| not-applicable | 3 |
| absent | 0 |
| partial | 0 |
| complete | 66 |

| persistence | Count |
| --- | ---: |
| not-applicable | 5 |
| absent | 0 |
| partial | 0 |
| verified | 64 |

| presentation | Count |
| --- | ---: |
| absent | 0 |
| fixture-shell | 0 |
| functional | 55 |
| accepted | 14 |

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
| absent | 0 |
| fixture-shell | 0 |
| functional | 6 |
| accepted | 2 |

### Live evidence labels

| Label | Classic | Host |
| --- | ---: | ---: |
| synthetic | 69 | 8 |
| route-harness | 40 | 2 |
| aogm-ordinary | 44 | 3 |
| other-ordinary | 12 | 3 |
| cross-platform | 0 | 0 |

## Release blockers and major gaps

Blockers: **1**. Major gaps: **0**.

- **blocker** `host.release.platform-certification` - Windows and Linux have native release evidence, but macOS remains unexecuted on an Apple runner. Next: Run the current commit's macOS verify/export job on an actual Apple runner, launch the exported application, and retain its release manifest and clean native log.

## Oracle-required unknowns

- None.

## Prioritized remaining-work queues

### aogm

- None.

### other-campaign

- `classic.character.age-update` - Age updates have no ordinary-campaign observation because the trigger is rare.
- `classic.services.bank` - The complete bank-backed Swap lifecycle has no ordinary campaign certification.

### parity

- `classic.character.view-sheet` - Several nonzero Classic ability slots lack verified display names.
- `classic.maps.view-acquired` - Classic scrolling TEXT encoding and style resources remain only partially represented.
- `classic.maps.view-acquired` - Malformed crop starts and authored picture rectangles lack boundary observations.

### polish

- `host.release.platform-certification` - Windows and Linux have native release evidence, but macOS remains unexecuted on an Apple runner.
- `classic.exploration.travel` - Ordinary AOGM dungeon presentation shows two solid green rectangular cells that do not visually match the surrounding Classic dungeon composition.
- `classic.maps.location-notes` - Castle's two dialog exit labels are not available in the pinned source, although both native exits are now proven to commit the current record.
- `classic.maps.view-acquired` - Ordinary AOGM acquisition, interaction-boundary restore, reward completion, persistence, and Maps/Notes browsing are proven, but the acquired-map presentation has not been user-accepted.
- `classic.startup.end-adventure` - Save-before-close ordering is characterized through the host transaction and repositories separately, but has no full composition-root failure-injection test.

## Coverage caveats

- Synthetic evidence proves a controlled fixture, not an ordinary campaign workflow.
- Route-harness evidence proves an automated route and may bypass ordinary navigation or presentation.
- AOGM and other ordinary-play labels certify only the listed workflow variants actually observed.
- Cross-platform certification requires the same Safe package and workflow to pass on every release platform.
- Differential cases provide behavioral depth. This inventory supplies the fixed application denominator.
- Gaps not selected by the current batch remain explicitly deferred; their presence alone does not authorize archaeology.
