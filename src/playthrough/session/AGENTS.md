# Playthrough session transaction contract

## Purpose

Own the public, deterministic, all-or-nothing transaction boundary around one active playthrough.

## Ownership

- `GameSession` owns start, restore, intent submission, response, view, snapshot, close, revision, rollback, and exact-once commit.
- `SessionContext` owns the current content, game state, RNG, VM, Scenario Action state, continuations, pending interaction, and disposable projection caches.
- Intent, response, and debug coordinators dispatch validated operations and return `SessionCoordinatorResult`; they never commit independently.
- Developer preview commands enter exact Simple/Complex Encounter, Battle, Treasure, and Shop definitions through their ordinary scenario, combat, reward, and service interactions. Direct Shop preview uses unrestricted acceptance ranges because contextual ranges remain caller-owned; all resumable preview operations suppress snapshots until their final interaction closes.
- `intents/` owns only the common payload protocol, empty payload, and stable kind-to-payload registry; feature factories and payloads live beside their workflows.
- Restore validators build and verify one detached candidate before `GameSession` assigns it.
- `SessionContinuation`, its body protocol, and codec own the stable saved continuation envelope.
- View projectors own read-only detached `GameView` assembly and conservative revision reuse.
- `SaveSlotPreview` is the neutral detached browse contract constructed by storage and consumed by the host and UI.
- `PlayerIntent` is the stable public command envelope. Session transactions consume the lower-level `InteractionRequest` and `InteractionResponse` contracts from `src/game/shared/interactions` without owning their wire codec.
- `GameView`, `ViewDomainRevisions`, and `SessionStep` are the detached read model and transaction result returned to callers.

## Local Contracts

- This feature may depend on `src/game`, `src/scenarios`, and sibling playthrough features; none may depend back on the app, UI, or storage layers.
- Every operation receives the one owned context by reference. Coordinators never copy or mirror session state.
- Rejected input is distinct from committed failure; only `GameSession` advances revision or constructs `SessionStep`.
- Restore validation and transaction rollback leave the live aggregate untouched on every failure.
- Continuation kinds, fields, versions, RNG order, event order, save shape, and stable identities remain unchanged.
- Detached projections are read-only, cached only by committed revision, and disposable across replacement or close.

## Work Guidance

- Begin at `GameSession`, then follow the intent or response coordinator to the feature workflow that owns the operation.
- Add behavior to the owning feature instead of widening the session facade or adding a proxy method.
- Preserve incremental projection and exact RNG/event order on hot transaction paths.

## Verification

- `tests/core/test_game_session.gd` owns the public transaction surface.
- `tests/integration/test_session_persistence.gd` owns complete snapshot and restore behavior.
- `tests/scenario/test_scenario_vm.gd` owns continuation wire compatibility.
- Run the affected feature workflow suite and `tools/verify.ps1` before completing a batch.

## Child DOX Index

- `intents/AGENTS.md` owns the common player-intent payload protocol and registry.
