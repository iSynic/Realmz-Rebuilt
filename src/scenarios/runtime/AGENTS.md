# Scenario runtime contract

## Purpose

Own the shared session-constructed boundary between `ScenarioVm`, Classic opcode implementations, Safe Scenario Actions, and playthrough state.

## Ownership

- `RealmzRuntimeApi`, runtime dispatch, and VM resume coordination.
- `ScenarioExecutionContext` plus its strict sparse codec.
- Typed operation results, directives, battle callers, runtime handoffs, and VM handoffs.
- The stable `ScenarioRuntimeContinuation` envelope and feature-owned suspended-operation bodies, factories, and codec under `continuations/`.
- Read-only combat request projection shared by scenario-owned and direct-session battles.

## Local Contracts

- `RealmzRuntimeApi` is the single VM-facing operation boundary. It coordinates typed waits and resumes but delegates Classic behavior to `../classic` and universal calculations to `src/game`.
- Runtime records and continuations remain pure, serializable, presentation-independent values. They never retain Nodes, presenters, repositories, or host services.
- `ScenarioExecutionContextCodec` is the only dictionary boundary for trigger, encounter, application, combat, and program-transfer provenance.
- `ScenarioRuntimeContinuationCodec` alone admits suspended-operation dictionaries and rejects unknown kinds, versions, fields, or mismatched payload families.
- The typed Party Death handoff also carries Classic health opcode 15/16 operands, stable target identities, and the next target cursor. Its strict existing-version codec permits pending-hook save/restore without changing the save schema; resume completes only after authored revival.
- Nested battle and death-macro VMs reference the owning runtime API weakly so the session graph has no `RefCounted` cycle.
- Unknown operations and malformed responses fail explicitly. There is no script-name dispatch or GDScript fallback.

## Work Guidance

- Begin with `realmz_runtime_api.gd` for VM-to-domain routing, `scenario_execution_context.gd` for provenance, and `scenario_runtime_continuation.gd` for a suspended operation.
- Put Castle opcode behavior under `../classic`; put VM scheduling and frame mutation under `../vm`.

## Verification

- `tests/scenario/test_scenario_vm.gd` owns dispatch, wait/resume, context, and continuation-wire behavior.
- `tests/scenario/test_reward_workflow.gd` and the matching integration suite own operation-specific return paths.

## Child DOX Index

- `continuations/AGENTS.md` owns typed suspended-operation payloads, feature factories, and their strict saved codec.
