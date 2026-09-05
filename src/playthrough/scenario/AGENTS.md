# Playthrough scenario workflow contract

## Purpose

Own application-hook transactions and scenario handoff coordination above the scenario VM and runtime operations.

## Ownership

- `SessionScenarioCoordinator` coordinates application hooks, VM handoffs, party-defeat revival, and exact scenario return through the public session boundary.
- `ScenarioApplicationHookWorkflow` resolves authored hook programs, constructs execution context, and publishes completion events.
- `ScenarioContinuations` constructs the application-hook continuation.
- `ScenarioApplicationContinuationBody` carries hook, program, service, revival, and suspended scenario handoff facts.

## Local Contracts

- Scenario definitions, VM frames, runtime continuations, and opcode behavior remain under `src/scenarios`; this feature coordinates them with the active playthrough.
- Application-hook programs resolve from immutable scenario content and resume only through their typed execution context.
- Party-defeat handoff preserves the suspended VM, owning session continuation, typed VM handoff, event order, RNG order, and revival decision exactly once.
- Continuation kind, fields, version, and wire representation remain stable.
- `GameSession` alone commits, rolls back, changes revision, closes the adventure, and constructs steps.

## Work Guidance

- Begin with `SessionScenarioCoordinator` for a session/VM transition and `ScenarioApplicationHookWorkflow` for one authored application hook.
- Add opcode or Scenario Action behavior under `src/scenarios`, not this coordination layer.

## Verification

- `tests/scenario/test_scenario_vm.gd` owns VM handoff and continuation-wire behavior.
- `tests/integration/test_session_persistence.gd` owns application-hook and party-defeat restore.
- Combat, reward, exploration, and application suites cover the corresponding session return paths.

## Child DOX Index
