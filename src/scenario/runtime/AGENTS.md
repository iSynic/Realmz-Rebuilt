# Scenario runtime boundary

## Purpose

Own the single session-constructed VM runtime API and explicit Classic opcode handler registry.

## Ownership

- Runtime dispatch and VM resume coordination.
- Duplicate-safe Classic opcode registration.
- Domain handler groups for control flow, world/time, character, inventory/economy, encounters, combat/rewards, and presentation-producing operations.

## Local Contracts

- Each Classic opcode has one owner. Registration rejects duplicate opcode IDs and VM-owned control-flow opcodes.
- `RealmzRuntimeApi` may coordinate typed waits and resumes but must delegate source-backed domain mutation to a handler or shared core workflow/rule operation.
- Classic control-flow results cross the runtime/VM boundary as `ScenarioVmDirective` variants. Raw directive dictionaries are codec data only and may not be inspected or constructed by handlers.
- Unknown opcodes fail explicitly. There is no script-name dispatch or GDScript fallback.
- Handlers are explicitly constructed, retain only session-owned pure dependencies, and never access Nodes or host services.

## Verification

- Scenario VM public workflows prove handler dispatch, waiting/resume behavior, unknown-opcode failure, and registry uniqueness.

## Parent Contract

- See `../AGENTS.md`.

## Child DOX Index

- `handlers/` and `operations/` are implementation groupings under this shared runtime contract and do not require separate contracts.
