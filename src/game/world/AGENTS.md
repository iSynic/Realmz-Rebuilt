# World game model

## Purpose

Own immutable world topology definitions, the authoritative game clock, and pure rules that interpret world movement and elapsed time.

## Ownership

- Map, cell, edge, feature, transition, land-tile, battle-terrain, random-region, and player-map definitions.
- `MapTopology` as the one immutable topology queried by movement, pathfinding, LOS, search, triggers, and detached views.
- `ClassicLandTileRules` for signed Castle land-tile identities and effective presentation profiles.
- `RealmzClock` for the save-owned minute count and deterministic day, hour, and minute projection.
- `ClockRules` for fatigue, condition ticks, spell recovery, aging, ration use, and half-day health recovery.
- `WorldState` gathers mutable world truth while `WorldTopologyState`, `WorldTriggerState`, and `WorldExplorationState` own altered topology, trigger state, and discovery history.
- `RandomRegionState` and `LocationNoteState` retain mutable random-region and player-note facts.
- `MapView` and its cell, window, presentation-delta, player-map, location-note, and journal-entry records form the detached world read model.

## Local Contracts

- Topology definitions are immutable after package construction; playthrough changes belong to the world state collaborators.
- `MapTopology` remains the only source of collision, edge, secret, and line-of-sight facts.
- Revealing an unoriented land secret changes entry/marker eligibility but preserves the underlying terrain's LOS, as Castle `cansee2` strips every marker band before reading mapstats. Directional dungeon discovery remains edge-owned.
- Clock changes are synchronous deterministic gameplay mutations. They use no wall-clock time, Godot timers, or presentation state.
- `ClockRules` preserves individual Classic timeclick order and emits detached events only after each mutation commits.
- World definitions, clock state, and rules are pure objects with no Node, filesystem, package, or UI dependency.
- Detached map views may share immutable projection chunks, but never retain or mutate authoritative topology or world state.

## Work Guidance

- Add immutable spatial facts beside the existing map definition that owns their meaning.
- Put mutable terrain, trigger, and discovery overlays in their named world state collaborators rather than mutating package definitions.
- Change clock or fatigue behavior through `ClockRules`; workflows decide when a source action advances time.

## Verification

- `tests/core/test_map_topology.gd` protects topology, pathfinding, LOS, and discovery facts.
- `tests/core/test_realmz_rules.gd` protects clock, fatigue, condition, and recovery rules.
- `tests/integration/test_exploration_session.gd` and `tests/integration/test_scroll_camp_workflow.gd` protect public movement and camp-time transactions.
- `tests/integration/test_session_persistence.gd` protects saved clock and world state.

## Child DOX Index
