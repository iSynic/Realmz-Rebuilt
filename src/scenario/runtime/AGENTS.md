# Scenario runtime boundary

## Purpose

Own the single session-constructed VM runtime API and explicit Classic opcode handler registry.

## Ownership

- Runtime dispatch and VM resume coordination.
- Duplicate-safe Classic opcode registration.
- Domain handler groups for control flow, world/time, character, inventory/economy, encounters, combat/rewards, and presentation-producing operations.
- Typed battle-caller, runtime-continuation, runtime-handoff, and VM-handoff records used at every wait, nested macro, and party-defeat boundary.
- `ScenarioExecutionContext`, the closed typed provenance passed through VM frames, directives, opcode handlers, and saved frame serialization.

## Local Contracts

- Each Classic opcode has one owner. Registration rejects duplicate opcode IDs and VM-owned control-flow opcodes.
- `RealmzRuntimeApi` may coordinate typed waits and resumes but must delegate source-backed domain mutation to a handler or shared core workflow/rule operation.
- `ClassicServiceOperations` owns shop/temple/bank opcode execution, request projection, and continuation mutation. `ClassicBattleRewardOperations` is the opcode-facing facade over `ClassicBattleLifecycleOperations` and `ClassicRewardOperations`; the delegates respectively own battle startup/terminal handoff and reward/level continuation. Runtime API wrappers expose those operations to `GameSession` without duplicating their behavior.
- Shop projection preserves Castle's five fixed native stock bands by source slot: Weapons 0–199, Armor 200–399, limb armor 400–599, Magic 600–799, and Supplies 800–999. Buyback entries remain uncategorized rather than being guessed from item identity.
- Classic opcode 19 reads Extra Code slots zero and one as the inclusive low/high message IDs passed to Castle's `randrange`; the intervening authored messages are selectable and each result publishes ordinary narrative text.
- The world/time handler owns opcode 37's validated signed heading and dungeon-view policy at the same teleport transaction. The presentation handler owns opcodes 96/97 policy mutation and publishes only detached policy-change events; neither handler owns a current camera mode.
- The world/time handler owns opcode 68's source-exact fatigue modes, including Castle's third-slot integer percentage defect, and publishes the ordinary fatigue-change event from the committed party state.
- The world/time handler owns opcode 95's fixed or one-draw random dungeon-heading mutation because heading changes subsequent simulation movement, not merely camera presentation.
- The control-flow owner treats obsolete registration opcodes 84 and 98 as explicit open-source pass-through markers; package readiness never mistakes an active registration row for an unknown or silent no-op.
- The battle facade may project the current typed combat request for an active direct-session battle. This read-only projection shares command legality with scenario-owned combat but does not create a VM wait or continuation.
- The battle facade may accept a debug-completed victory only against the exact base Classic or Safe combat continuation whose battle is now terminal. It delegates immediately to ordinary ally selection and reward construction; no debug-only reward or VM-return path exists.
- `ClassicThiefEncounterOperations` owns the dedicated eight-action thief workspace, mutable encounter flags, trap ordering, timed Pick Lock handoff, signed click/non-click result text, authored result routing, and the matching typed continuations. It must not flatten those actions into Complex Encounter buttons or replace Castle's trained-ability 5-through-12 mapping with host-authored rolls.
- Simple, Complex, and Thief result programs retain the issuing encounter frame until the authored `maxTimes` selection count is exhausted. The current attempt is typed save state; eliminated Simple options survive each repeat, Back exits immediately, and a final Complex fallback result four becomes Castle's timeout result three when `maxTimes` exceeds one.
- Classic Choice mode zero finishes the current VM timeline and publishes a typed backout request for its session owner. Mode four finishes the timeline without inventing encounter-option mutation. The runtime never directly moves the party or finalizes the issuing AP.
- Terminal reward ownership lasts through every source-ordered reward workspace. Initial construction and each resumed reward operation checkpoint canonical game state and gameplay RNG; failures restore both, discard speculative events, and leave the owning continuation retryable. Persisted summoned actors are excluded before content validation and consume no reward draws. Ordinary and opcode-2 mode-5 victories otherwise share the exact money-then-incidental draw sequence; mode 5 suppresses authored monster wealth/items but not experience, recovered fumbles, or eligible Classic items 806/877. Treasure lore projection keeps Detect Magic and Identify Objects as stable sibling controls, disables an already completed method with an explicit reason, and independently recomputes the other method's eligible casters from authoritative remaining spell points. Opcode 48's optional fixed treasure is a separately persisted second stage; combat cleanup, the after-message, and VM return occur only after that stage completes.
- Nested battle and death-macro VMs call the owning runtime API through a weak reference so the session graph has no `RefCounted` ownership cycle.
- Classic control-flow results cross the runtime/VM boundary as `ScenarioVmDirective` variants. Raw directive dictionaries are codec data only and may not be inspected or constructed by handlers.
- Live execution context crosses the runtime/VM boundary only as `ScenarioExecutionContext`. Its sparse dictionary form exists solely inside its strict wire codec; unknown provenance fields fail restoration.
- Live continuation queues contain typed interaction bodies. Dictionary payloads may enter only from detached domain events and are decoded once before the continuation is constructed.
- Unknown opcodes fail explicitly. There is no script-name dispatch or GDScript fallback.
- Handlers are explicitly constructed, retain only session-owned pure dependencies, and never access Nodes or host services.

## Verification

- Scenario VM public workflows prove handler dispatch, waiting/resume behavior, unknown-opcode failure, and registry uniqueness.

## Parent Contract

- See `../AGENTS.md`.

## Child DOX Index

- `handlers/` and `operations/` are implementation groupings under this shared runtime contract and do not require separate contracts.
