# Combat feature

## Purpose

Own the explicit collaboration boundary shared by deterministic battle rules.

## Ownership

- `CombatContext` holds the rule services and named combat collaborators used during one command transaction.
- `CombatActionEvents` builds committed physical-action feedback and owns fumble and death-macro event transitions.
- `BattleDefinition`, `BattleMonsterSlotDefinition`, `MonsterDefinition`, and `MonsterAttackDefinition` are the immutable authored battle records.
- `CombatCatalog` indexes immutable monster sets and battles for the active campaign.
- `BattlefieldState` aggregates battle-map identity, terrain, and actor placement. `BattlefieldTerrainState`, `BattlefieldActorState`, and `BattlefieldGrid` own their named mutable facts and geometry; `BattlefieldStateCodec` owns the stable flat save boundary.
- `CombatState` and its roster, turn, status, reaction, dropped-item, spell-runtime, field, monster, and undo collaborators own all mutable battle truth. `CombatStateCodec` preserves their stable flat save boundary.
- `README.md` is the public maintainer entry point for combat rules.

`RealmzContent.combat` owns immutable definition lookup. Detached views remain under `src/game/view`, and the established rule collaborators remain under `src/game/rules` until a complete feature migration moves each file, test, UID, and reference atomically.

## Local Contracts

- Collaborators receive one `CombatContext` by reference and never retain or call a `CombatFlow` root object.
- Cross-collaborator calls use named public operations. Do not call another object's private method or add forwarding query methods to `CombatFlow`.
- `CombatFlow` owns mutation commands. Read-only probes belong to the collaborator that calculates them.
- Context and event objects are pure `RefCounted` values. They may not own Nodes, filesystem access, wall-clock time, or independent randomness.

## Work Guidance

- Keep serialized combat state, event identities, RNG order, and Castle-visible outcomes unchanged during structural work.
- Address `battlefield.terrain` or `battlefield.actors` directly; do not restore aggregate forwarding methods. Use `BattlefieldGrid` for fixed dimensions and footprint geometry.
- Split cohesive action/event policy before expanding a collaborator beyond the architecture limits.
- Move remaining combat rules and views here only in coherent batches that preserve Godot UIDs and update tests, docs, and the system manifest together.

## Verification

- Run `tools/run_tests.ps1 -Suite @('test_combat_flow.gd') -TimeoutSeconds 180` for combat command changes.
- Run `tools/verify_architecture_overhaul.ps1` to reject private-call and size-budget regressions.

## Child DOX Index

- No child AGENTS.md files are currently required.
