# Combat feature

## Purpose

Own the explicit collaboration boundary shared by deterministic battle rules.

## Ownership

- `CombatContext` holds the rule services and named combat collaborators used during one command transaction.
- `CombatActionEvents` builds committed physical-action feedback and owns fumble and death-macro event transitions.
- `README.md` is the public maintainer entry point for combat rules.

Combat state remains under `src/game/state`: `CombatState` aggregates the battle, its roster/turn/status/dropped-item/spell-runtime owners hold cohesive mutable facts, and `CombatStateCodec` preserves the stable flat save shape. Detached views remain under `src/game/view`, and the established rule collaborators remain under `src/game/rules` until a complete feature migration moves each file, test, UID, and reference atomically.

## Local Contracts

- Collaborators receive one `CombatContext` by reference and never retain or call a `CombatFlow` root object.
- Cross-collaborator calls use named public operations. Do not call another object's private method or add forwarding query methods to `CombatFlow`.
- `CombatFlow` owns mutation commands. Read-only probes belong to the collaborator that calculates them.
- Context and event objects are pure `RefCounted` values. They may not own Nodes, filesystem access, wall-clock time, or independent randomness.

## Work Guidance

- Keep serialized combat state, event identities, RNG order, and Castle-visible outcomes unchanged during structural work.
- Split cohesive action/event policy before expanding a collaborator beyond the architecture limits.
- Move remaining combat files here only in coherent batches that preserve Godot UIDs and update tests, docs, and the system manifest together.

## Verification

- Run `tools/run_tests.ps1 -Suite @('test_combat_flow.gd') -TimeoutSeconds 180` for combat command changes.
- Run `tools/verify_architecture_overhaul.ps1` to reject private-call and size-budget regressions.

## Child DOX Index

- No child AGENTS.md files are currently required.
