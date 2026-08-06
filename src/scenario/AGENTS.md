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
- Battle-round and monster-death macros run as serializable nested VM frames. A death macro receives the defeated combatant ID and must complete before allegiance and battle outcome are finalized.
- Completed battles may yield a typed `ally_selection` from the issuing combat continuation. That response rebuilds the held-over ally party under Castle body-count limits before the scenario frame continues.
- Executable-opcode readiness is declared by `ClassicOpcodeCatalog` and checked against bounded, provenance-labelled content inventories. A declared opcode must have an explicit handler and may never fall through to dynamic dispatch or a silent no-op.

## Work Guidance

- Preserve raw and normalized Classic opcode identity plus source provenance.
- Represent player input as an `InteractionRequest` and resume the exact issuing frame.
- Keep Safe Action source and visual outline as two views of the same validated program.

## Verification

- VM tests cover calls, returns, limits, yields, save/resume, unknown behavior, Castle traces, inherited AP context, Extra Code battle identity, serializable battle/death/body-count flows, program replacement/redirect, domain dispatch, and bounded campaign-inventory readiness.

## Child DOX Index

- No child AGENTS.md files are currently required.
