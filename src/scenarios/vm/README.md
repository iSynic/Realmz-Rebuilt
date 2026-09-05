# Scenario VM

`ScenarioVm` schedules the immutable instruction stream and is the only owner of its frame stack. Each step dispatches a preserved Classic instruction or a typed Safe Scenario Action phase, applies any returned directive, and either advances, yields a serializable interaction, returns a frame, or halts.

Start with `scenario_vm.gd`, then inspect `scenario_frame.gd` for the live cursor and `scenario_vm_snapshot.gd` for persistence. Classic opcode meaning and frame-control policy live in `../classic`; Safe expression evaluation and action state live in `../actions`; gameplay operations and suspended-operation payloads live in `../runtime`.
