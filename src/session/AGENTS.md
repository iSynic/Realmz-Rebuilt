# Deterministic session orchestration contract

## Purpose

Own the pure transaction coordinator that joins core Realmz state and rules to the scenario VM without making either lower layer depend on the other.

## Ownership

- `GameSession` public operations, transaction checkpoints, exact-once commit, request identity, revision, and aggregate lifetime.
- `SessionSnapshot`, `SessionContinuation`, and the separate battle-return continuation that include core state, RNG, scenario VM/action state, and pending typed interactions.
- `SessionRestoreValidator` constructs and validates a detached typed restore candidate. `GameSession.restore` alone commits that candidate to the live aggregate, so every failed validation leaves the current session untouched.
- `SessionInteractionFactory` is the single owner of session-level request reconstruction shared by live orchestration and restore validation.
- Session workflow contexts and services for lifecycle, exploration, inventory/magic/services, combat/rewards, application hooks, and detached view projection.
- Internal exploration, scenario, and response coordinators that own continuation sequencing while leaving transaction commit and rollback in `GameSession`.
- The standalone character-creation session adapter.

## Local Contracts

- This layer may depend on `src/core` and `src/scenario`; neither lower layer may depend on `src/session`.
- All classes are pure `RefCounted` or value-like data. They never retain Nodes, repositories, presenters, or the owning application.
- Workflow services receive an explicit ephemeral `SessionWorkflowContext`; they never retain the owning `GameSession`.
- Session continuation coordinators receive one explicit operation-scoped `SessionCoordinatorContext`, retain neither the owning `GameSession` nor the context beyond that operation, and return a typed `SessionCoordinatorResult`. `GameSession` alone applies the context, advances revision, commits, rolls back, closes, and constructs the public `SessionStep`.
- Exploration state mutations such as Camp, Rest, Search, clock advancement, fatigue, and secret discovery belong to `ExplorationTimeWorkflow`. `GameSession` only chooses the continuation and commits the returned events/error as one transaction.
- `GameSession` alone owns rollback, request matching, revision changes, and exact-once commit.
- Boat boarding and third-attempt shore disembarkation are typed `YES_NO` interactions owned by a `boat-choice` continuation. Response coordination re-probes the same source/destination and boat state before mutation; accepted, declined, saved, and restored paths apply sound, time, overlay, movement, and post-time continuation exactly once.
- Restore validation must never mutate the live session. Candidate state, rules, RNG, VM, continuations, and interaction are replacement objects until the final `GameSession` assignment block.
- Scenario-mediated and direct player operations must converge on the same core rules and workflow implementations.
- Dictionaries are permitted only while crossing an explicit package/save/event codec. Live workflow state and continuations are typed.
- Every continuation body and nested scenario handoff must reject unknown fields and versions, detach mutable values, and round-trip through its strict wire codec before entering a snapshot.
- Detached views are cached by committed session revision. The projector may reuse immutable domain projections only for a strictly recognized ordinary movement/time event sequence; every unknown, interaction-changing, map-changing, or combat event invalidates the conservative fast path. Domain revisions let presenters update only affected visible regions without changing simulation state or save shape.

## Parent Contract

- See `../../AGENTS.md`.

## Child DOX Index

- `workflows/AGENTS.md` owns the domain workflow and detached projection contracts.
