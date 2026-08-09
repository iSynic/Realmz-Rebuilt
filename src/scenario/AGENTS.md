# Scenario execution contract

## Purpose

Own the serializable Scenario VM, Classic instructions, Safe Scenario Actions, capabilities, and the single Realmz runtime API presented by a session.

## Ownership

- VM instruction/frame/trace/limit models and execution.
- Classic AP, XAP, encounter, GOSUB, return, and result semantics.
- Scenario Action definitions, validated Safe programs, private helpers, state schemas, and migrations.
- Capability declarations and readiness checks.

## Local Contracts

- The VM is presentation-independent and serializable at every interaction yield.
- Domain mutations execute through one session-owned `RealmzRuntimeApi`; there are no Godot ports or dynamic GDScript fallbacks.
- `RealmzRuntimeApi` is the single VM boundary and delegates source-backed work to typed domain executors under `runtime/operations`; those executors cannot bypass `GameState`, `RealmzRules`, or the session RNG.
- Classic GOSUB depth is 20. Safe Action call depth is 32, program size 4,096 nodes, arrays 256 entries, and execution 65,536 steps.
- Unknown instructions, IDs, capabilities, actions, and response shapes fail explicitly.
- Packages cannot override `realmz.*`; campaign actions use `scenario.<campaign>.*`.
- A Scenario Action call is an ordinary AP/Encounter timeline entry. Authoring gaps and behavior anchors are not runtime concepts.
- Runtime instruction forms are preserved `ClassicAction` records and typed `CallScenarioAction` records. Safe bytecode is compiler output, never Providence editor state.
- The session owns the active VM, action state, runtime API, and post-move continuation. VM snapshots include Classic and Safe frames, origin, trace, and any pending typed interaction.
- A saved Classic program replacement is resolved once when a frame starts. Redirecting the active AP changes that frame explicitly; neither behavior rewrites immutable package programs.
- Classic XAP transfers inherit the issuing frame's AP origin/context. Loading macro code cannot erase the trigger identity required by source-backed operations such as opcode 25.
- Battle opcodes resolve the Classic battle ID from Extra Code slot zero when a row is present; the action operand is only the direct-ID form when no Extra Code row exists.
- Battle-round and monster-death macros run as serializable nested VM frames. A death macro receives the defeated combatant ID and must complete before occupancy, allegiance, and battle outcome are finalized; `FD-COMBAT-007` retains the pending subject's footprint so CODE 119 revival remains positioned and saveable. Spell-triggered death macros drain from the combat state's save-owned queue before the issuing caster advances. The host may not clear allegiance merely because a queued macro completed; an authored operation such as opcode 119 owns that mutation.
- Typed combat-action requests expose every adjacent living combatant hostile to the active loyal actor, including a party character whose battle-scoped Charm allegiance has changed. They also expose the eight session-probed player movement destinations and exact disabled reasons. The runtime API does not infer targets, positions, or movement legality from presentation state.
- Typed combat-action requests expose the battle-owned character weapon mode, exact legal mode switch, and source-owned ordinary projectile targets. Missile mode omits melee attacks; Fire carries the actor and selected stable target ID and remains disabled with an exact reason for unsupported projectile classes or failed range/LOS/resource gates.
- Typed combat-action requests expose source-admitted spell options. Automatic groups carry no fabricated target ID; spatial types 3 and 4 carry a rules-owned Data AD shape, ordered offsets, and default battlefield coordinate, and the response returns only the chosen coordinate and rotation. The runtime API never rebuilds area masks, range, LOS, or affected actors from presentation state.
- Classic opcode 1 preserves the message operand sign as control flow. A positive message yields a typed, saveable `acknowledge` request for the dedicated Classic textbox; a negative message publishes its presentation event and continues without a click boundary.
- A Classic or Safe time operation and Classic opcode 17/18 spell that changes an age band yields a typed `age_update`; its runtime continuation owns the ordered remaining updates and resumes the exact issuing VM frame only after every response.
- Classic opcode 3 treats zero option IDs as the standard Yes/No pair. Nonzero IDs resolve through the package's Data OD option-label table, with ordinary message lookup used only for old-format packages that have no option-label table.
- Classic opcode 9 publishes the absolute `snd ` resource ID while preserving the operand sign as presentation playback metadata: positive is asynchronous and negative waits within the Classic sound queue. It never blocks or advances simulation.
- Classic opcode 24 ends the current timeline and reports Keep Codes for the issuing placed Action Point. Without that exception, the session disables the AP after successful completion; opcode 25 remains the explicit in-program removal operation.
- Completed battles may yield a typed `ally_selection` from the issuing combat continuation. That response rebuilds the held-over ally party under Castle body-count limits before the scenario frame continues.
- A completed battle drains its exact fumbled-item queue after `ally_selection` through one typed `treasure_distribution` response per item. Assignment or discard must finish before the battle after-message and issuing frame continue; the request and VM continuation are save-owned.
- Classic opcode 122 delegates to the core fumble operation only after Castle's outer party-active and committed-physical-action guards. A failed outer guard suppresses authored Extra Code media. The unreachable nested monster branch is not implemented; natural monster fumbles belong to `attack2`, not this opcode. The live `inspell` guard remains explicit until spell activation owns a source-equivalent lifecycle fact.
- Scenario-launched battles that trigger Classic monster aging wrap the issuing Classic or Safe combat continuation in a serializable typed age-update queue. Acknowledgement resumes remaining monster turns, Guard/withdrawal cursor, battle/death macros, completion, or the next player actor without restarting the issuing scenario instruction. A Guard that kills a death-macro monster retains that cursor and footprint; CODE 119 revival continues with the next queued reaction rather than replaying or discarding the interrupted sequence.
- Scenario-launched Escape yields a `yes_no` request owned by the issuing Classic or Safe combat continuation. Decline returns to the unchanged active turn; acceptance commits the core's per-character Escape and then resumes battle, body count, fumble recovery, and the issuing VM frame in their ordinary order. The nested confirmation must survive VM/save restoration without replaying the combat action.
- Scenario-launched combat responses preserve repeated-spell `targetIds` as an ordered array of stable actor IDs. The runtime validates the complete response shape and passes it to the same core probe used by direct-session casting; it never sorts, deduplicates, or resolves targets in the host.
- Executable-opcode readiness is declared by `ClassicOpcodeCatalog` and checked against bounded, provenance-labelled content inventories. A declared opcode must have an explicit handler and may never fall through to dynamic dispatch or a silent no-op.

## Work Guidance

- Preserve raw and normalized Classic opcode identity plus source provenance.
- Represent player input as an `InteractionRequest` and resume the exact issuing frame.
- Keep Safe Action source and visual outline as two views of the same validated program.

## Verification

- VM tests cover calls, returns, limits, signed Classic textbox and age-update pacing, yields, save/resume, unknown behavior, Castle traces, inherited AP context, Extra Code battle identity, serializable battle/death/body-count flows, program replacement/redirect, domain dispatch, and bounded campaign-inventory readiness.

## Child DOX Index

- No child AGENTS.md files are currently required.
