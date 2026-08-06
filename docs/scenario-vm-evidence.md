# Scenario VM evidence

This document separates the Classic control-flow observations used to design the 2.0 VM from the behavior proven in the new runtime. It does not claim a Castle runtime fixture where only source has been inspected.

## Castle source/control-flow

Pinned oracle: Realmz Castle commit `491816ad60037394f92c428e99c004494d3c28b3`.

- `src/realmz_orig/main.c:46-48` declares a 20-entry stack counter, its index, and the GOSUB flag. This is the source basis for the Classic frame limit; it is not reused as global state.
- `src/realmz_orig/newland.c:97-120` treats negative codes other than -14 and -23 as their positive operation with GOSUB intent. CODE 111 restores the saved action record and resumes at the following slot; CODE 112 drops a stack entry without returning through it.
- `src/realmz_orig/stack.c:3-20` stores the complete door/action record with its slot and restores both on pop. The 2.0 VM therefore serializes the caller program and cursor, not only a target ID.
- `src/realmz_orig/newland.c:1573-1632` loads a Simple Encounter, receives one of four responses, copies that response's eight code/ID pairs into the active action record, and restarts execution. The 2.0 compiler linearizes each result as a normal referenced program while retaining the same response-to-result routing.
- `src/realmz_orig/newland.c:2747-2752` implements opcode 39 by loading the referenced extended door record, resetting the slot, and restarting. The 2.0 instruction replaces the current Classic program with the referenced XAP program; a prior negative call frame remains available for CODE 111.
- `src/realmz_orig/newland.c:1736-1815` implements opcode 7 by copying a referenced XAP program over a Simple/Complex result or AP slot, while lines 1817-1823 implement opcode 8 by replacing the active AP record and restarting at slot zero. The 2.0 runtime preserves immutable package programs and stores an equivalent source-to-target program mapping or explicit active-frame redirect in `GameState`.

These observations establish structure and control flow. They do not by themselves prove every edge case of the Castle executable.

## Borrowed interpreter concepts

Current Remake checkpoint `cdaa0d8dcc5ab81c195aa960c860bf74e7d4f40b` demonstrates useful serializable interpreter concepts in `src/scripts/scenario_runtime/scenario_interpreter.gd:840-875`: trigger/cursor identity, call stack, encounter origin, pending command, trace, and restore validation. Its call/return handling at lines 938-975 also preserves a caller cursor.

2.0 borrows those concepts, not that host architecture. The new VM has one session-owned runtime API, no Godot service ports or dynamic fallback, distinct Classic and Safe frames, immutable compiled package input, typed interaction responses, and whole-session persistence.

## 2.0 proof

- `runtime-unit`: VM tests cover Classic and Safe calls/returns, CODE 39/111/112, opcode 7 replacement, opcode 8 redirect, recursion and execution limits, typed Safe state, unknown behavior, interaction validation, and snapshot restore.
- `runtime-integration`: the synthetic Providence package executes AP -> Simple Encounter -> result -> Scenario Action -> XAP -> CODE 111. Saving at the pending encounter and restoring reproduces the same request ID, selected continuation, trace, action state, and final world state.
- `live-route`: Godot MCP Pro drove the same synthetic interaction through the actual composition root and `InteractionPresenter`, saved/restored at the pending request, and observed the final resumed state. This proves host wiring for the synthetic route, not Castle executable parity or campaign certification.

The remaining parity lane is an isolated synthetic Castle oracle harness with scripted input/RNG. Until that exists for a behavior, tests must retain the labels above rather than upgrading the claim to `castle-runtime`.
