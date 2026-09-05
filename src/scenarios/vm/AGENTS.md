# Scenario VM contract

## Purpose

Own deterministic scheduling of Classic and Safe Scenario Action frames, including suspension, resume, snapshots, and bounded traces.

## Ownership

- `ScenarioVm`, instruction dispatch phases, frame stack, step limits, and trace publication.
- `ScenarioFrame`, pending continuation, operation result, snapshot, directive transition, and VM handoff records.

## Local Contracts

- The VM is pure and serializable at every supported interaction yield. It never reaches presentation, storage, Nodes, files, wall-clock time, or Godot randomness.
- `ScenarioVm` alone mutates the active frame stack and applies typed directive transitions. Classic control flow under `../classic` cannot run a second VM.
- Safe evaluation under `../actions` returns typed values; it does not own frame or continuation mutation.
- Every unknown instruction, invalid frame, exceeded depth or step bound, and malformed resume fails explicitly.
- Snapshots preserve exact frame order, instruction cursor, execution context, pending request, nested handoff, and trace state without changing stable save representation.

## Work Guidance

- Begin with `scenario_vm.gd` for scheduling, `scenario_frame.gd` for one active frame, and `scenario_vm_snapshot.gd` for persistence.
- Put Castle opcode semantics under `../classic`, Safe expression/state behavior under `../actions`, and domain-operation behavior under `../runtime`.

## Verification

- `tests/scenario/test_scenario_vm.gd` owns frame scheduling, directives, limits, waits, resumes, and snapshot round trips.
- `tests/integration/test_session_persistence.gd` owns whole-session VM restore.

## Child DOX Index
