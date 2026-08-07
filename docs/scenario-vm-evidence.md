# Scenario VM evidence

This document separates the Classic control-flow observations used to design the 2.0 VM from the behavior proven in the new runtime. It does not claim a Castle runtime fixture where only source has been inspected.

## Castle source/control-flow

Pinned oracle: Realmz Castle commit `491816ad60037394f92c428e99c004494d3c28b3`.

- `src/realmz_orig/main.c:46-48` declares a 20-entry stack counter, its index, and the GOSUB flag. This is the source basis for the Classic frame limit; it is not reused as global state.
- `src/realmz_orig/newland.c:97-120` treats negative codes other than -14 and -23 as their positive operation with GOSUB intent. CODE 111 restores the saved action record and resumes at the following slot; CODE 112 drops a stack entry without returning through it.
- `src/realmz_orig/stack.c:3-20` stores the complete door/action record with its slot and restores both on pop. The 2.0 VM therefore serializes the caller program and cursor, not only a target ID.
- `src/realmz_orig/newland.c:1573-1632` loads a Simple Encounter, receives one of four responses, copies that response's eight code/ID pairs into the active action record, and restarts execution. The 2.0 compiler linearizes each result as a normal referenced program while retaining the same response-to-result routing.
- `src/realmz_orig/newland.c:2747-2752` implements opcode 39 by loading the referenced extended door record, resetting the slot, and restarting. The 2.0 instruction replaces the current Classic program with the referenced XAP program; a prior negative call frame remains available for CODE 111.
- `src/realmz_orig/flashrange-loaddoor.c:43-59` loads XAP actions while copying the current AP's level, coordinate, chance, and identity fields back onto the temporary record. The 2.0 VM therefore carries origin context across opcode 39 and directive-based XAP transfers instead of replacing the frame with contextless code.
- `src/realmz_orig/newland.c:1736-1815` implements opcode 7 by copying a referenced XAP program over a Simple/Complex result or AP slot, while lines 1817-1823 implement opcode 8 by replacing the active AP record and restarting at slot zero. The 2.0 runtime preserves immutable package programs and stores an equivalent source-to-target program mapping or explicit active-frame redirect in `GameState`.
- `src/realmz_orig/killbody.c:87-127` saves the current action/E-code context, runs or queues a monster's `todoondeath` macro with that combatant's identity, restores the caller context, and removes the monster from the hostile side. The 2.0 equivalent uses a nested serializable VM frame and does not let combat finalize first.
- `src/realmz_orig/getup.c:71-82` invokes a negative battle macro after a completed round. The runtime keeps battle-round macros separate from monster-death macros, but both use the same typed interaction ABI and whole-session persistence.
- `src/realmz_orig/newland.c:1530-1535` passes Classic opcode 3's two Extra Code option IDs to `question2`. `src/realmz_orig/question.c:100-134` keeps the standard Yes/No dialog when the first ID is zero; otherwise it reads 25-byte labels from Data OD, falling back to ordinary Data SD2 messages only when Data OD is unavailable. The 2.0 runtime therefore keeps option labels as their own typed content table and never interprets message zero (`Do Not Use`) as a button label.
- `src/realmz_orig/newland.c:1826-1828` forwards opcode 9's signed operand to `sound`. `src/realmz_orig/misc.c:1875-1907` rotates through the configured sound channels, looks up the absolute `snd ` ID, plays a positive ID asynchronously, and a negative ID synchronously. The 2.0 runtime preserves the absolute resource ID and sign metadata while the presentation host owns four rotating channels; simulation does not wait on audio.

These observations establish structure and control flow. They do not by themselves prove every edge case of the Castle executable.

## Borrowed interpreter concepts

Current Remake checkpoint `cdaa0d8dcc5ab81c195aa960c860bf74e7d4f40b` demonstrates useful serializable interpreter concepts in `src/scripts/scenario_runtime/scenario_interpreter.gd:840-875`: trigger/cursor identity, call stack, encounter origin, pending command, trace, and restore validation. Its call/return handling at lines 938-975 also preserves a caller cursor.

2.0 borrows those concepts, not that host architecture. The new VM has one session-owned runtime API, no Godot service ports or dynamic fallback, distinct Classic and Safe frames, immutable compiled package input, typed interaction responses, and whole-session persistence.

## 2.0 proof

- `runtime-unit`: VM tests cover Classic and Safe calls/returns, CODE 39/111/112, inherited AP origin through XAP transfer, Extra Code battle identity, opcode 7 replacement, opcode 8 redirect, serializable battle-round/death macros, recursion and execution limits, typed Safe state, unknown behavior, interaction validation, Data OD versus default Yes/No choice labels, signed sound playback metadata, and snapshot restore.
- `runtime-integration`: the synthetic Providence package executes AP -> Simple Encounter -> result -> Scenario Action -> XAP -> CODE 111. Saving at the pending encounter and restoring reproduces the same request ID, selected continuation, trace, action state, and final world state.
- `runtime-integration`: an automatic monster death macro receives its defeated combatant ID, can revive it through opcode 119, and resolves the battle only after macro completion. A direct-session variant yields opcode 14, saves, restores, resumes through `GameSession.respond`, and preserves combat, VM, action, and RNG ownership.
- `live-route`: Godot MCP Pro drove the same synthetic interaction through the actual composition root and `InteractionPresenter`, saved/restored at the pending request, and observed the final resumed state. This proves host wiring for the synthetic route, not Castle executable parity or campaign certification.

The remaining parity lane is an isolated synthetic Castle oracle harness with scripted input/RNG. Until that exists for a behavior, tests must retain the labels above rather than upgrading the claim to `castle-runtime`.

The local Assault on Giant Mountain completion route additionally proves that the 2.0 host carries Baron briefing context through its macro and resolves the goblin battle through Extra Code. That is campaign `live-route` evidence for the recorded deterministic spine, not a Castle executable differential fixture.

The local War in the Sword Lands completion spine adds direct ED3 macro checkpoints, ally add/remove behavior, round/death macro instructions, Castle body-count resumption, and four observed battles. Naryl's post-Battle-473 selection is an ordinary typed VM interaction, and the later opcode 87 branch confirms that the selected survivor returned to party state. Those checkpoints execute compiled programs through the ordinary VM but do not claim that an unplaced ED3 record was reached through map topology.
