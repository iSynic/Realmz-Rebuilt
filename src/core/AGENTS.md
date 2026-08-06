# Deterministic Realmz core contract

## Purpose

Own the pure Realmz model, fixed Classic rules, topology, game clock, randomness, and complete session state.

## Ownership

- Direct Realmz definitions and mutable playthrough state.
- `GameSession`, typed intents/events/interactions/views, and snapshot boundaries.
- `RealmzRules`, `RealmzClock`, `RealmzRng`, topology queries, and world overlays.

## Local Contracts

- All classes are pure `RefCounted` or value-like data. They never extend or retain Nodes.
- No scenes, autoloads, filesystem/resource APIs, audio, OS services, wall-clock time, or Godot randomness.
- JSON dictionaries stop at validating infrastructure factories. Domain state is typed and does not expose writable backing dictionaries.
- Every gameplay mutation is committed synchronously by `GameSession`.
- Every gameplay random draw goes through the session-owned `RealmzRng` and is serializable.
- `RealmzRng` uses the documented QuickDraw 16807/mod-2147483647 state transition and Castle's inclusive scaling; raw scripted values are test-only branch controls.
- Snapshots and restores detach typed state so callers cannot mutate an active session through a prior envelope.
- `MapTopology` plus `WorldState` overlays is the only source for simulation map facts; movement, pathfinding, LOS, search, triggers, and views reuse its explicit cells, edges, and features.
- `GameView` and its map/cell views are detached read models for presentation and never expose mutable simulation objects.
- Classic-visible Realmz behavior is the fixed ruleset. Fidelity corrections require a documented decision and source/oracle tests.

## Work Guidance

- Prefer small domain modules behind a fixed `RealmzRules` facade; do not add registries or profile selectors.
- Preserve 16-bit and 32-bit arithmetic semantics explicitly where Castle behavior depends on them.
- Keep serialized IDs stable strings and use `StringName` only as an internal lookup optimization.

## Verification

- `tools/verify_architecture.ps1` rejects forbidden host dependencies and direct randomness.
- Core behavior requires headless unit tests and, when source-backed, an evidence-labelled oracle fixture.

## Child DOX Index

- No child AGENTS.md files are currently required; subdirectories remain governed here.
