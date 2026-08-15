# Deterministic session orchestration contract

## Purpose

Own the pure transaction coordinator that joins core Realmz state and rules to the scenario VM without making either lower layer depend on the other.

## Ownership

- `GameSession` public operations, transaction checkpoints, exact-once commit, request identity, revision, and aggregate lifetime.
- `SessionSnapshot`, `SessionContinuation`, and the separate battle-return continuation that include core state, RNG, scenario VM/action state, and pending typed interactions.
- Session workflow contexts and services for lifecycle, exploration, inventory/magic/services, combat/rewards, application hooks, and detached view projection.
- The standalone character-creation session adapter.

## Local Contracts

- This layer may depend on `src/core` and `src/scenario`; neither lower layer may depend on `src/session`.
- All classes are pure `RefCounted` or value-like data. They never retain Nodes, repositories, presenters, or the owning application.
- Workflow services receive an explicit ephemeral `SessionWorkflowContext`; they never retain the owning `GameSession`.
- `GameSession` alone owns rollback, request matching, revision changes, and exact-once commit.
- Scenario-mediated and direct player operations must converge on the same core rules and workflow implementations.
- Dictionaries are permitted only while crossing an explicit package/save/event codec. Live workflow state and continuations are typed.
- Every continuation body and nested scenario handoff must reject unknown fields and versions, detach mutable values, and round-trip through its strict wire codec before entering a snapshot.

## Parent Contract

- See `../../AGENTS.md`.

## Child DOX Index

- `workflows/AGENTS.md` owns the domain workflow and detached projection contracts.
