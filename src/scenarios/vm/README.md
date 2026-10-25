# Scenario VM

`ScenarioVm` is the sole execution runner. It schedules ordered Classic invocations, Safe calls and gameplay operations, applies explicit transitions, and suspends at the exact typed interaction owner.

Start with `scenario_vm.gd`, `scenario_execution_state.gd` and `scenario_vm_snapshot.gd`. Classic state, manual returns and compiled/native positions are separate records. `scenario_legacy_execution_codec.gd`, `scenario_legacy_call_codec.gd` and `scenario_legacy_macro_codec.gd` convert historical frames and nested snapshots before live assignment; they never create another runner. Classic opcode meaning lives in `../classic`, Safe evaluation in `../actions`, and gameplay operations in `../runtime`.
