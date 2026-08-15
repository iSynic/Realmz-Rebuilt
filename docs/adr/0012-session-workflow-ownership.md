# ADR 0012: Make GameSession a transaction coordinator

## Status

Accepted; implementation in progress.

## Context

The pure session boundary is sound, but `GameSession` became the owner of lifecycle, exploration, inventory, magic, services, combat, scenario handoff, persistence validation, and view projection. This centralization obscures responsibility and encourages private-method tests.

## Decision

`GameSession` moves to a separate pure `src/session` orchestration layer and retains public dispatch, checkpoint/rollback, request identity, revision, exact-once commit, and aggregate ownership. This is required because the coordinator joins core state/rules to scenario VM execution while the lower layers remain independent: core depends on neither scenario nor session, scenario depends only on core, and session depends on both. Session-owned workflow services receive an explicit context containing immutable content, mutable state, rules, RNG, VM state, and an event sink. Separate services own lifecycle/party, exploration/time, inventory/magic/services, combat/rewards, scenario/application hooks, and detached view projection.

Classic opcode handlers use those same workflow/rule operations through one explicitly constructed registry. Neither workflows nor handlers retain Nodes, repositories, the owning session, or dynamic fallback dispatch.

## Consequences

Public workflow tests replace direct calls into coordinator internals. Transaction and VM semantics remain centralized while domain complexity can evolve independently.
