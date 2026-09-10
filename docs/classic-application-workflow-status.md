# Classic Application Workflow Status

Generated deterministically from `tests/fixtures/oracle/classic-application-workflow-inventory.json`. Castle application completeness and modern host completeness are deliberately reported as separate denominators.

## Denominators

| Scope | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| classic | 69 | 0 | 3 | 53 | 13 |
| host | 8 | 0 | 1 | 5 | 2 |

Delivery state is derived. Missing means required content, simulation, or presentation is absent. Partial includes partial axes, shell-only presentation, unverified persistence, unresolved variants, oracle-required ambiguity, or blockers. Functional requires complete content/simulation, verified or inapplicable persistence, functional presentation, accounted variants, and no blocker. Certified additionally requires accepted presentation and ordinary-play or cross-platform evidence.

## Current parity-convergence batch

**Encounter prompts, stock rule geometry and reward continuation** (`ap-stock-rules-and-rewards`)

Repair the reproduced Necronomicon AP 3 zero-prompt failure, then prioritize the stock Race decoding defect exposed by its XP award over additional campaign variants. Castle reads 408-byte Race records, while the canonical application extractor currently advances 960 bytes and corrupts later Race fields. Reopen stock character creation, progression and reward acceptance; correct the canonical library, verify native fields, then replay those player workflows and the retained Treasure continuation. Prelude, AOGM and Bywater AP candidates remain queued until this shared defect is resolved. Existing inventories remain the denominators and full campaign certification stays separate.

AP batches use failure-first priorities: known failures, untested high-risk behavior, meaningful variants, and broader representatives. Verification mode records existing functional behavior without claiming full campaign certification; implementation, verification, and certification remain distinct modes.

| Workflow | Mode | Priority | Expected evidence | Owned gaps |
| --- | --- | --- | --- | --- |
| `classic.scenario.choose-response` | verification | known-failure | live-route |  |
| `classic.startup.create-character` | implementation | known-failure | - | GAP-RULES-001 |
| `classic.rewards.experience-level-up` | implementation | known-failure | - | GAP-RULES-002 |
| `classic.rewards.treasure-distribution` | implementation | known-failure | - | GAP-RULES-003 |

### Batch count delta

| Scope | State | Baseline | Current | Delta |
| --- | --- | ---: | ---: | ---: |
| classic | missing | 0 | 0 | 0 |
| classic | partial | 0 | 3 | +3 |
| classic | functional | 55 | 53 | -2 |
| classic | certified | 14 | 13 | -1 |
| host | missing | 0 | 0 | 0 |
| host | partial | 1 | 1 | 0 |
| host | functional | 5 | 5 | 0 |
| host | certified | 2 | 2 | 0 |

## Classic domain heatmap

| Domain | Total | Missing | Partial | Functional | Certified |
| --- | ---: | ---: | ---: | ---: | ---: |
| Startup and party | 8 | 0 | 1 | 6 | 1 |
| Exploration | 6 | 0 | 0 | 4 | 2 |
| Scenario interaction | 6 | 0 | 0 | 3 | 3 |
| Character management | 5 | 0 | 0 | 5 | 0 |
| Inventory and equipment | 9 | 0 | 0 | 9 | 0 |
| Spellcasting | 3 | 0 | 0 | 1 | 2 |
| Services and economy | 5 | 0 | 0 | 5 | 0 |
| Combat | 14 | 0 | 0 | 9 | 5 |
| Rewards and progression | 5 | 0 | 2 | 3 | 0 |
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
| partial | 3 |
| complete | 47 |

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

Blockers: **4**. Major gaps: **0**.

- **blocker** `classic.rewards.experience-level-up` - Stock progression consumes misaligned Race base attacks and movement from the current application catalog. Next: After canonical catalog repair, verify a real stock level-up and its saved continuation against source-decoded Race facts.
- **blocker** `classic.rewards.treasure-distribution` - Necronomicon AP 3 awards every starter the maximum-age reduced XP share because the current stock Race catalog is misaligned. Next: Repair canonical Race geometry, revalidate the application package, and replay the retained ordinary reward route plus save/resume with source-correct XP expectations.
- **blocker** `classic.startup.create-character` - Stock character creation consumes misaligned Race attributes, limits, base stats and eligibility from the current application catalog. Next: Verify all 30 native Race records against Castle geometry, regenerate the canonical library, and exercise ordinary stock character creation through its public workflow.
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

- `classic.rewards.experience-level-up` - Stock progression consumes misaligned Race base attacks and movement from the current application catalog.
- `classic.rewards.treasure-distribution` - Necronomicon AP 3 awards every starter the maximum-age reduced XP share because the current stock Race catalog is misaligned.
- `classic.startup.create-character` - Stock character creation consumes misaligned Race attributes, limits, base stats and eligibility from the current application catalog.
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
