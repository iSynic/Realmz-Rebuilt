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
- `CombatView`, `BattlefieldView`, actor/catalog views, action-option views, and persistent-field views carry the detached battle read model.
- `CombatRequestBody` carries the detached active-actor command surface through the shared interaction envelope.
- Battlefield construction, physical attack policy and resolution, initiative, command/retreat probes, monster rules, and their typed results live beside the state they interpret.
- `CombatFlow` and its action, reaction, phase, lifecycle, magic, field, summoning, and rollback collaborators own command mutation. `CombatBattleSetup` owns validated construction and opening turns.
- `CombatAiScoring`, party and monster planners, party and monster automation, target facts, monster actions, and occupancy rules own deterministic automatic decisions and battlefield cleanup.
- `README.md` is the public maintainer entry point for combat rules.

`RealmzContent.combat` owns immutable definition lookup. Every combat state, definition, view, rule collaborator, typed result, and request body now lives in this feature root; playthrough command submission and UI rendering remain in their respective boundaries.

## Local Contracts

- Collaborators receive one `CombatContext` by reference and never retain or call a `CombatFlow` root object.
- Cross-collaborator calls use named public operations. Do not call another object's private method or add forwarding query methods to `CombatFlow`.
- `CombatFlow` owns mutation commands. Read-only probes belong to the collaborator that calculates them.
- `CombatMacroSpells`, reached through `CombatFlowMagic`, resolves non-damaging area and side-group condition spells around a retained macro source without action costs, activation advancement, or death-macro completion. Dead sources are anchors, never targets; complete living footprints are deduplicated in party-then-monster order. Macro source context, continuation, and completion remain scenario/playthrough-owned.
- Context and event objects are pure `RefCounted` values. They may not own Nodes, filesystem access, wall-clock time, or independent randomness.
- The combat request body reports calculated choices and targets but never decides legality or mutates battle state.

## Work Guidance

- Keep serialized combat state, event identities, RNG order, and Castle-visible outcomes unchanged during structural work.
- Monster automation must consume an exhausted cast-fallback chain within the current activation: the advance/contact probe is the ordinary physical fallback, and only explicit reaction waiting or death-macro results may leave a resumable active actor.
- Random monster target preference consumes one choice draw. An empty, friendly, unavailable, or obscured sampled slot falls through immediately to the stable visible-target scan; it must not consume repeated draws while a legal opposed target already exists.
- Address `battlefield.terrain` or `battlefield.actors` directly; do not restore aggregate forwarding methods. Use `BattlefieldGrid` for fixed dimensions and footprint geometry.
- Split cohesive action/event policy before expanding a collaborator beyond the architecture limits.
- Keep combat rules, views, request bodies, tests, docs, and the system manifest synchronized when a collaborator moves or changes ownership.

## Verification

- Run `tools/run_tests.ps1 -Suite @('test_combat_flow.gd') -TimeoutSeconds 180` for combat command changes.
- Run `tools/verify_architecture_overhaul.ps1` to reject private-call and size-budget regressions.

## Child DOX Index

- No child AGENTS.md files are currently required.
