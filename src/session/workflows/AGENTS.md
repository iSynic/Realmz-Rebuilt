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
- Registered Castle reads the Data SC aggregate maximum and then disables it before party selection. Rebuilt preserves that source field as package evidence but never enforces or presents it as a cap; only the independent Data RI per-character maximum may reject a character, with zero meaning uncapped.
- Domain mutations use core rules and state; callers own transaction rollback, request IDs, revisions, pending interactions, and exact-once commit.
- `InventoryMagicServicesWorkflow` owns carried-item Split and Join transactions; type-13 case transfer with all five ordered scroll records; Castle inventory Cast Identify selection, fixed cost, and all-carried-item mutation; exact Classic item-805 Torch discovery through the ordinary charged field-item path; exact field/combat door-item eligibility and Special-5 XAP lookup; plus field item, spell, and scroll eligibility, target normalization, typed target requests and continuations, deterministic mutations, continuation-state validation, and domain-event construction. Its character-target request includes one source-authored `SpellTargetContext` built from the same selected power and spell definition as the continuation, so restore can reconstruct the exact display contract without prompt parsing. Automatic field groups retain party order and append held-over allies only for Castle target types 3 and 9; the shared resolver publishes each target kind and never presents those groups as manual character selection. Field-invalid scroll use opens the source-backed typed Discard/Keep boundary and clears only the revalidated exact slot on acceptance. A strict field condition cure persists its typed target boundary, clears exactly the source condition after response, and publishes `clearedCondition`; restoring and answering either request may commit it only once. A successfully committed learned field spell increments the character's lifetime spell count exactly once; field items and scrolls do not. `GameSession` installs or resumes the returned transition and retains revision, age-update routing, and combat/death-macro orchestration.
- A workflow returns typed results or existing core result types. It does not construct `SessionStep` values or call another public session operation.
- Direct intents and scenario handlers must converge on the same core rule operation when they represent the same Realmz action.
- Detached spell projection probes every legal power through the owning combat, field, or scribing rule boundary. It retains the first exact rejection reason when no power is legal; presentation may display that reason but may not reduce it to a generic unsupported spell or infer capability from the absence of a tactical option.
- `ExplorationTimeWorkflow` owns movement mutation, source-ordered time advancement, Castle's persistent Search-mode toggle, separate held Area Search, Rest, and field Heal pulses, post-clock/post-move continuation construction, and placed-trigger selection shared by live continuation construction and restore validation; restore infrastructure must not become a live exploration dependency. A hidden unoriented land secret preserves terrain entry but suppresses its colocated placed trigger until the save-owned discovery overlay reveals it. Explicit Camp entry/exit request stock sounds 10001/141. The presentation-owned physical hold lifecycle requests the source's one start sound for Rest and Area Search; repeat pulses remain simulation events without replaying that start cue. Heal advances time before scanning party-order eligible casters and recipients, spends ten spell points per recovery, and uses one tagged Rand(8) draw per recipient. Area Search preserves Castle's first four field timeclicks and random scan, then resumes its outer one timeclick and second random scan through the typed `area-search-second` post-clock completion path so an intervening timed/random interaction cannot replay either phase. Post-clock, post-move, timed, contextual Encounter, restore, and detached map projection all query the same effective save-owned random-region membership: compiler-authored cell membership remains authoritative until opcode 92 overrides that region's inclusive bounds. `SessionExplorationCoordinator` owns the completion path plus contextual Encounter: it stays available outside camp, uses the faced cell on land and current cell in dungeons, reverse-scans negative random rectangles, performs ordered random-door draws, falls back to XAP 0, and retains a saveable XAP continuation.
- `ExplorationTimeWorkflow.turn_dungeon` validates a dungeon exploration boundary and one left/right quarter-turn, rotates the save-owned heading, and emits the committed heading without moving the party, advancing time, or consuming RNG.
- View projection is read-only and must not create gameplay truth or mutate state. It may retain a bounded revision-keyed cache of detached projections; cache identity includes the current map and party coordinate and is cleared across session replacement/close. Contextual services expose stable player-facing titles such as `Shop` without leaking Classic record indices. The detached map record carries the effective save-owned landlook, dungeon heading, authored LOS flag, exact seen coordinates, and current bounded topology visibility; Wizard's Eye bypasses occluders without bypassing the radius. Every detached land cell selects the effective landlook's stock tileset identity; absent a tile mutation it retains the authored tile and icon-backed overlay, while a save-owned signed Classic replacement projects its normalized ordinary tile or its positive or negative icon-backed overlay on the effective landlook base. A discovered secret remains an explicit feature, but a hidden unoriented land secret is only withheld from marker/trigger presentation and never changes the cell's detached movement availability; an authored path exposes `discovered_path` only after the save-owned visited overlay contains that cell. The party summary carries authoritative aboard state; none invent an uncompiled base-scale discriminator or movement rule. Historical location-note projection derives a bounded 15-by-13 crop from the same effective topology and save-owned overrides, centers it on the saved coordinate, and carries the saved zero-through-six darkness level without changing live party context. Acquired land-map projection uses the authored 320-pixel divisor, while an acquired dungeon map always projects Castle's bounded 20-by-20 cell window independently of its marker scale.
- Strict ordinary movement may reuse overlapping land-cell projections, source-owned fatigue updates whose payload matches committed state, and the exact nonblocking `classic-map-movement` sound request. Unknown events, LOS maps, interactions, transitions, triggered encounters, other sound requests, and mismatched fatigue facts force complete projection. While combat is active, unchanged hidden exploration/map projections may be retained until combat releases; the first post-combat projection rebuilds them from current state.
- `SessionDebugWorkflow` owns deterministic developer warp and party restoration. Warp accepts only an authored topology cell at an exploration boundary, changes no clock or RNG state, and marks the destination visited; restoration fills HP/SP and clears only positive temporary harmful conditions, never permanent negative records.

## Verification

- Focused public session and VM workflows cover each extracted owner; implementation-private coordinator tests are not admission evidence.

## Parent Contract

- See `../AGENTS.md`.

## Child DOX Index

- No child contracts are required.
