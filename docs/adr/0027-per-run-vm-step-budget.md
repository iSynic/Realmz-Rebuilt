# ADR 0027: Per-run Scenario VM step budget

Status: accepted for VM schema 4 / save v7; its per-run policy is retained, while ADR 0029 supersedes the nested-VM budget mechanism for VM schema 5.

## Problem

`ScenarioVm` stops runaway scripts after 65,536 steps (`EXECUTION_STEP_LIMIT`). This is a Rebuilt safeguard; Castle has no equivalent, so the number has no source basis. Today the count is a per-program lifetime total:

- `_step_count` resets only in `start_program` and `start_debug_instruction`. It keeps growing across every `resume()` and `resume_handoff()`, and it is saved in the VM snapshot (`stepCount`). A long, legitimate interactive loop, such as an authored encounter the player repeats many times, can eventually fail with `scenario_step_limit` even though no single run was runaway.
- Nested timer and battle/death-macro VMs are separate `ScenarioVm` instances that each start at zero. So the budget is reset at exactly the boundaries where it should be shared, and shared where it should reset.
- `_step_count == 0` doubles as the "native invocation has not begun" marker that triggers `native_action_points.begin()` on the first `run()`.

## Decision

1. The budget covers one uninterrupted run: the work between an external entry and the next yield, completion, failure or host handoff. External entries are `start_program`, `start_debug_instruction`, `resume` (a player response) and `resume_handoff` (a host return). Each resets the counter.
2. Internal calls, GOSUB, program transfers, nested timer VMs, battle and death-macro VMs, and automatic handoffs inside one run share that budget. A nested VM is configured with the parent's remaining steps and reports its consumed steps back. It never starts a fresh allowance.
3. The limit stays 65,536 steps per run and remains documented as a Rebuilt safeguard, not Castle behavior. A runaway loop with no interaction still fails deterministically with `scenario_step_limit`; repeated player-driven loops no longer exhaust a lifetime allowance.
4. The "native invocation begun" fact becomes an explicit boolean in VM snapshot schema 4, replacing the overloaded counter. The per-run counter is not persisted, because every restore resumes through an external entry that resets it.
5. Schema 2/3 snapshots decode `stepCount` only to derive that boolean (`stepCount > 0`), then discard it.

## Consequences

- The failure point for genuinely runaway scripts can move, since nested work now draws on the parent's budget. Results stay deterministic from serialized state; RNG, events and traces are unchanged for every script that stays under the limit.
- A script that previously failed only after many interactions now completes. That is a behavior change from current Rebuilt builds, but not a fidelity change, because Castle never imposed a limit.
- Ships in the same VM schema 4 / save v7 as ADR 0026.

## Verification

- A public VM workflow repeats an interactive encounter loop well past 65,536 cumulative steps across many responses without failing, and a non-interactive infinite loop still fails within one run.
- A nested timer or death macro that would exceed the parent's remaining budget fails at the same deterministic step whether or not the session was saved and restored mid-run.
- Wire tests prove schema 4 carries the native-begun flag, and schema 2/3 snapshots restore with an unchanged first-run header decision.

## Limit

The owner accepted one engine-wide limit of 65,536 steps per run; packages cannot configure it.
