# Classic functional differential

Classic-visible behavior is developed through a rolling differential gate. Current Remake identifies existing functionality, mappings, tests, and likely differences. Castle source controls the behavioral decision; a controlled Castle runtime fixture is used only when complete source flow is insufficient. Providence must preserve the authored inputs, and Realmz Remake 2.0 must own the result through typed runtime boundaries.

The machine-readable record is `tests/fixtures/oracle/classic-functional-differential.json`. It contains the detailed paths, symbols, commits, expected traces, tests, and decision state. This document summarizes only the current conclusions.

## Current cases

| Case | Current decision | Durable conclusion |
| --- | --- | --- |
| `movement.land-eight-direction` | Aligned | Land input, availability, and pathfinding use the same eight destination probes; diagonal corner exits follow compiled Layout neighbors. Dungeon movement remains cardinal and edge-based. |
| `action-point.placed-first-match` | Aligned | A placed AP selects the lowest native record at the coordinate. Disabled state or chance failure ends the placed-AP check without falling through; percent below one consumes no draw. |
| `media.classic-resource-key` | Aligned | Classic media identity is the exact four-character `(resourceType, resourceId)` pair. Scenario media wins over stock fallback; Providence rejects unresolved duplicate keys and runtime never performs numeric-ID-only lookup. |
| `interaction.classic-staged-presentation` | Aligned | The active textbox, picture, and response remain staged. Completed narrative may enter the Chronicle, but the Chronicle is not the interaction surface. |
| `campaign.party-setup-commit` | Aligned | Campaign startup begins with an empty session-owned party. Add, vault import, remove, save, and restore remain in setup across revisions; only explicit Begin enters exploration. |

## Rolling gate

For each functional slice:

1. Inventory the pinned Remake implementation, mappings, and tests.
2. Trace the complete Castle control flow and authored fields that determine the observable behavior.
3. Add a controlled synthetic Castle fixture only if source flow cannot settle the observation.
4. Verify Providence preserves the required data in the Realmz 2 package.
5. Add the failing 2.0 characterization, implement through the owning typed boundary, and verify save/resume and RNG where applicable.
6. Update the machine record and the owning domain evidence document before closing the slice.

An unresolved behavior remains disabled with an explicit reason. Remake host architecture, direct Godot mutation, service locators, compatibility profiles, and inferred Classic behavior are not accepted as implementations.
