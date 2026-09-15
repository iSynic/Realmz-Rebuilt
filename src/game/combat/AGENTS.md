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
- `CombatCatalog.definitions()` exposes the deterministic complete effective monster catalog for bounded capability and corpus analysis; player-facing bestiary filtering remains a separate view.
- Routed monster movement replaces a stale retained target through the existing deterministic visible-target selection before stepping away. A `canSummon == -1` scenario-mandatory ally may reach the retreat band but remains a living positioned combatant; the activation ends with a typed blocked-retreat reason instead of deleting the ally or following Castle's unsafe offscreen walk.
- `CombatFlow` and its action, reaction, phase, lifecycle, magic, field, summoning, and rollback collaborators own command mutation. `CombatBattleSetup` owns validated construction and opening turns.
- `CombatAiScoring`, party and monster planners, party and monster automation, target facts, monster actions, and occupancy rules own deterministic automatic decisions and battlefield cleanup.
- `README.md` is the public maintainer entry point for combat rules.

`RealmzContent.combat` owns immutable definition lookup. Every combat state, definition, view, rule collaborator, typed result, and request body now lives in this feature root; playthrough command submission and UI rendering remain in their respective boundaries.

## Local Contracts

- Collaborators receive one `CombatContext` by reference and never retain or call a `CombatFlow` root object.
- Cross-collaborator calls use named public operations. Do not call another object's private method or add forwarding query methods to `CombatFlow`.
- `CombatFlow` owns mutation commands. Read-only probes belong to the collaborator that calculates them.
- `CombatMacroSpells`, reached through `CombatFlowMagic`, resolves immediate area and side-group spells around a retained macro source without action costs, activation advancement, or death-macro completion. It shares ordinary spell effects and lifecycle cleanup, including nested defeated-monster macro queuing; queued fields and open-space/summoning remain separate paths. Dead sources are anchors, never targets; complete living footprints are deduplicated in party-then-monster order. Macro source context, continuation, and completion remain scenario/playthrough-owned.
- Context and event objects are pure `RefCounted` values. They may not own Nodes, filesystem access, wall-clock time, or independent randomness.
- The combat request body reports calculated choices and targets but never decides legality or mutates battle state.

## Work Guidance

- Keep serialized combat state, event identities, RNG order, and Castle-visible outcomes unchanged during structural work.
- Monster automation must consume an exhausted cast-fallback chain within the current activation: the advance/contact probe is the ordinary physical fallback, and only explicit reaction waiting or death-macro results may leave a resumable active actor.
- Monster activation setup follows Castle's signed condition arithmetic: Tangle is subtracted even when permanent and negative, then Slow halves and Speedy doubles movement; Speedy also appends two uses of attack row zero after the authored attack sequence.
- Monster advance routing never revisits a settled anchor during one uninterrupted activation. If both the deterministic route and the source-style fallback would loop through an earlier anchor, it reports the unavailable route and ends movement instead of consuming the remaining allowance in place.
- Character movement starts its serializable Guard reaction after validating an adjacent direction but before terrain, movement cost, contact, or friendly-collision outcome. A blocked attempt keeps the anchor and turn resources and emits its reason after Guard; a same-side collision pauses for the save-owned Swap/Attack choice only after Guard settles.
- Random monster target preference consumes one choice draw. An empty, friendly, unavailable, or obscured sampled slot falls through immediately to the stable visible-target scan; it must not consume repeated draws while a legal opposed target already exists.
- The corpus-backed zero-cost class-nine monster spell-slot projectile consumes Castle's range-power draw before targeting, resolves at forced power one, and spends no spell points. Physical projectile-item specials 7 and 49 retain the ordinary shield/dodge gate: 7 halves current character movement on a successful monster-fired hit, while 49 replaces damage with current health plus ten. Other variable-cost, variable-range, or special projectile signatures remain separate capabilities.
- Character and monster shaped spell areas use the shared resolver's reflection mode. Target collection consumes one draw per reflecting occupant before shared spell rolls, redirects successes to the active caster, and deduplicates the effective target; automatic target types 9, 10, and 12 retain their source bypass.
- An equipped character projectile whose authored item power is eight exposes `prepare_projectile` before target selection. That command draws and saves one power for the activation; profile range and Fire use the retained value, invalid targets do not reroll it, and a successful shot clears staging. Party Auto uses the same staged command rather than an alternate projectile path.
- Address `battlefield.terrain` or `battlefield.actors` directly; do not restore aggregate forwarding methods. Use `BattlefieldGrid` for fixed dimensions and footprint geometry.
- Split cohesive action/event policy before expanding a collaborator beyond the architecture limits.
- Keep combat rules, views, request bodies, tests, docs, and the system manifest synchronized when a collaborator moves or changes ownership.

## Verification

- Run `tools/run_tests.ps1 -Suite @('test_combat_flow.gd') -TimeoutSeconds 180` for combat command changes.
- Run `tools/verify_architecture_overhaul.ps1` to reject private-call and size-budget regressions.

## Child DOX Index

- No child AGENTS.md files are currently required.
