# Deterministic Realmz core contract

## Purpose

Own the pure Realmz model, fixed Classic rules, topology, game clock, randomness, and complete session state.

## Ownership

- Direct Realmz definitions and mutable playthrough state, including characters, equipment, wealth, conditions, encounters, battles, shops, treasures, spells, monsters, races, and castes.
- `GameSession`, typed intents/events/interactions/views, and snapshot boundaries.
- `RealmzRules`, `RealmzClock`, `RealmzRng`, topology queries, and world overlays.

## Local Contracts

- All classes are pure `RefCounted` or value-like data. They never extend or retain Nodes.
- No scenes, autoloads, filesystem/resource APIs, audio, OS services, wall-clock time, or Godot randomness.
- JSON dictionaries stop at validating infrastructure factories. Domain state is typed and does not expose writable backing dictionaries.
- Every gameplay mutation is committed synchronously by `GameSession`.
- `GameSession` owns scenario execution state and is the only object allowed to connect VM operations to domain mutations.
- Session state owns encounter attempts/type flags, equipment escrow, mutable shop stock, combat, and scenario-program replacement. These are save data, never mutations of installed package definitions.
- Session state owns non-VM interaction continuations as well as VM continuations. Random-rectangle surprise choices serialize with their owning region and resume only through `GameSession.respond`.
- Monster death macros execute before battle resolution. Their combatant identity, VM interaction, and direct-session continuation belong to the save aggregate and resume only through `GameSession.respond`.
- A placed Action Point's Classic header is a post-action map/coordinate destination. `GameSession` applies it only after that AP completes, rechecks the destination cell once, and serializes the recheck depth so save/resume cannot repeat or skip it.
- Every gameplay random draw goes through the session-owned `RealmzRng` and is serializable.
- `RealmzRng` uses the documented QuickDraw 16807/mod-2147483647 state transition and Castle's inclusive scaling; raw scripted values are test-only branch controls.
- Snapshots and restores detach typed state so callers cannot mutate an active session through a prior envelope.
- `MapTopology` plus `WorldState` overlays is the only source for simulation map facts; movement, pathfinding, LOS, search, triggers, and views reuse its explicit cells, edges, and features.
- A topology cell retains immutable presentation metadata for its base tileset/tile and optional special-land overlay asset. These facts pass through detached views but never become an alternate movement, LOS, or trigger model.
- Random rectangles follow Castle's reverse region order, 1-in-10,000 chance scale, three ordered random-door draws, signed one-shot door state, surprise choice, and battle selection through the session RNG.
- `GameView` and its map/cell views are detached read models for presentation and never expose mutable simulation objects.
- `MapView` carries a bounded 25×25 party-local cell projection, the complete visited-coordinate set needed by the minimap, and cardinal movement availability computed through the same topology probe as movement. It does not duplicate the full 90×90 map for every presentation revision.
- Classic-visible Realmz behavior is the fixed ruleset. Fidelity corrections require a documented decision and source/oracle tests.
- Unsuspended held-over allies are consumed into the combat roster as non-traitors. After combat, surviving friendly monsters with nonzero `canSummon` eligibility return only through the typed Classic body-count selection; negative eligibility is mandatory. Monster targeting compares allegiance, so hostile monsters can attack party characters or friendly monsters and friendly monsters target hostiles.

## Work Guidance

- Prefer small domain modules behind a fixed `RealmzRules` facade; do not add registries or profile selectors.
- Keep character, condition/time, inventory/economy, combat, magic, and monster behavior in their owned rule modules. Opcode handlers adapt Classic records to these rules instead of duplicating formulas.
- Preserve 16-bit and 32-bit arithmetic semantics explicitly where Castle behavior depends on them.
- Keep serialized IDs stable strings and use `StringName` only as an internal lookup optimization.

## Verification

- `tools/verify_architecture.ps1` rejects forbidden host dependencies and direct randomness.
- Core behavior requires headless unit tests and, when source-backed, an evidence-labelled oracle fixture.

## Child DOX Index

- No child AGENTS.md files are currently required; subdirectories remain governed here.
