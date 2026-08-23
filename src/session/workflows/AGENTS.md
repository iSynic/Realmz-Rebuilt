# Session workflow contract

## Purpose

Own domain-oriented, presentation-independent operations invoked by the session transaction coordinator.

## Ownership

- Lifecycle and party setup.
- Exploration and time.
- Inventory, magic, and services.
- Combat and rewards.
- Scenario application-hook protocol preparation.
- Detached `GameView` projection.

## Local Contracts

- Operations receive an ephemeral `SessionWorkflowContext` and never retain the session or context.
- Domain mutations use core rules and state; callers own transaction rollback, request IDs, revisions, pending interactions, and exact-once commit.
- `InventoryMagicServicesWorkflow` owns carried-item Split and Join transactions; type-13 case transfer with all five ordered scroll records; Castle inventory Cast Identify selection, fixed cost, and all-carried-item mutation; exact Classic item-805 Torch discovery through the ordinary charged field-item path; plus field item, spell, and scroll eligibility, target normalization, typed target requests and continuations, deterministic mutations, continuation-state validation, and domain-event construction. Its character-target request includes one source-authored `SpellTargetContext` built from the same selected power and spell definition as the continuation, so restore can reconstruct the exact display contract without prompt parsing. Field-invalid scroll use opens the source-backed typed Discard/Keep boundary and clears only the revalidated exact slot on acceptance. A strict field condition cure persists its typed target boundary, clears exactly the source condition after response, and publishes `clearedCondition`; restoring and answering either request may commit it only once. `GameSession` installs or resumes the returned transition and retains revision, age-update routing, and combat/death-macro orchestration.
- A workflow returns typed results or existing core result types. It does not construct `SessionStep` values or call another public session operation.
- Direct intents and scenario handlers must converge on the same core rule operation when they represent the same Realmz action.
- Detached spell projection probes every legal power through the owning combat, field, or scribing rule boundary. It retains the first exact rejection reason when no power is legal; presentation may display that reason but may not reduce it to a generic unsupported spell or infer capability from the absence of a tactical option.
- `ExplorationTimeWorkflow` owns movement mutation, source-ordered time advancement, Castle's persistent Search-mode toggle, separate held Area Search, Rest, and field Heal pulses, post-clock/post-move continuation construction, and placed-trigger selection shared by live continuation construction and restore validation; restore infrastructure must not become a live exploration dependency. Explicit Camp entry/exit request stock sounds 10001/141. The presentation-owned physical hold lifecycle requests the source's one start sound for Rest and Area Search; repeat pulses remain simulation events without replaying that start cue. Heal advances time before scanning party-order eligible casters and recipients, spends ten spell points per recovery, and uses one tagged Rand(8) draw per recipient. Area Search preserves Castle's first four field timeclicks and random scan, then resumes its outer one timeclick and second random scan through the typed `area-search-second` post-clock completion path so an intervening timed/random interaction cannot replay either phase. `SessionExplorationCoordinator` owns that completion path plus contextual Encounter: it stays available outside camp, uses the faced cell on land and current cell in dungeons, reverse-scans negative random rectangles, performs ordered random-door draws, falls back to XAP 0, and retains a saveable XAP continuation.
- View projection is read-only and must not create gameplay truth or mutate state. It may retain a bounded revision-keyed cache of detached projections; cache identity includes the current map and party coordinate and is cleared across session replacement/close. The detached map record carries the authored landlook for presentation but never invents an uncompiled base-scale discriminator.
- Strict ordinary movement may reuse overlapping land-cell projections and source-owned fatigue updates whose payload matches committed state. Unknown events, LOS maps, interactions, transitions, triggered encounters, and mismatched fatigue facts force complete projection. While combat is active, unchanged hidden exploration/map projections may be retained until combat releases; the first post-combat projection rebuilds them from current state.

## Verification

- Focused public session and VM workflows cover each extracted owner; implementation-private coordinator tests are not admission evidence.

## Parent Contract

- See `../AGENTS.md`.

## Child DOX Index

- No child contracts are required.
