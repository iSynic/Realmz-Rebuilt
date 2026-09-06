# Playthrough world workflow contract

## Purpose

Own exploration transactions and the detached map read model that joins immutable topology to save-owned world state.

## Ownership

- `ExplorationMovementWorkflow` owns travel, dungeon heading, fatigue admission, camp departure, and boats.
- `ExplorationSearchWorkflow` owns Search mode, Area Search, and secret discovery.
- `ExplorationTimeWorkflow` owns Camp, Rest, and field Heal.
- `ExplorationContinuationWorkflow` and `SessionExplorationCoordinator` own saveable post-clock, post-move, AP, random-region, timed, and contextual-Encounter resumption, plus isolated stable-ID Action Point preview entry that rejoins ordinary trigger completion.
- `SessionActionPointCoordinator` owns execution of a selected Action Point and the isolated preview preparation that deliberately bypasses placement chance before rejoining that same completion path.
- `LocationNoteWorkflow` owns player-authored location notes.
- `SessionMapViewBuilder` owns topology-derived cells, movement options, player-map records, location-note crops, and bounded map-window caching.
- Exploration and boat continuation payloads/factories own the typed values needed to resume those operations.
- `ExplorationIntents` and `ExplorationIntentPayloads` define typed travel, Search, time, contextual-service, and player-note commands.

## Local Contracts

- Workflows receive an ephemeral `SessionWorkflowContext`; `GameSession` alone commits, rolls back, changes revision, and constructs steps.
- Movement uses one authoritative `MapTopology`, preserves exact RNG/event/time order, and applies fatigue admission before any side effect.
- Search and time workflows never hide extra movement, time, RNG, or AP processing outside their documented continuation.
- Continuation payloads preserve existing kinds, fields, versions, and strict save representation.
- Map projection is read-only. Its caches are nonserialized, bounded, revision-keyed, and disposable across restore, replacement, or close.
- The 2D and 3D presenters consume the same detached topology facts and never create their own collision, LOS, heading, discovery, or secret rules.

## Work Guidance

- Begin with the named command workflow, then follow `SessionExplorationCoordinator` only when the operation yields.
- Keep world truth and pure calculations in `src/game/world`; this feature coordinates transactions and detached views.
- Preserve incremental map projection and copy-on-write typed chunks on movement-sensitive changes.
- Keep the ordinary adjacent-movement projection path allocation-light. It may coordinate visibility, bounds, cache lookup, movement options, and final view construction in one bounded method; extract cold full-window construction and copy-on-write patching only where the hot path remains measurably neutral.

## Verification

- `tests/core/test_map_topology.gd` owns topology rules.
- `tests/integration/test_exploration_session.gd` owns public exploration transactions and continuations.
- `tests/integration/test_session_persistence.gd` owns save/restore of interrupted exploration.
- Use the movement and dungeon-transition probes when projection or spatial behavior changes.

## Child DOX Index
