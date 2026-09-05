# Playthrough combat workflow contract

## Purpose

Own the public session transactions that submit combat commands and the typed handoffs that resume an interrupted battle.

## Ownership

- `CombatCommandWorkflow` submits character actions, movement, retreat, and persistent Auto through the rules-owned combat surface.
- `CombatContinuations` constructs retreat, friendly-collision, death-macro, ally-selection, fumble-recovery, and reward continuations.
- `CombatContinuationBody` carries battle command and death-macro facts.
- `CombatRewardContinuationBody` carries a completed battle's reward workflow and scenario return point.
- `CombatIntents` and `CombatIntentPayloads` define typed battle actions, movement, targeting, and persistent Auto commands.

## Local Contracts

- Delegate battle legality and mutation to `CombatFlow` and its named combat collaborators; do not duplicate action rules here.
- Preserve persistent Auto rollback, event order, RNG order, actor identity, destination, source battle, and completion behavior.
- Continuation kinds, fields, versions, and wire representation remain stable across relocation.
- Scenario battle lifecycle and reward operations may create these continuations but retain ownership of their runtime mutation phases.
- `GameSession` alone commits, rolls back, changes revision, and constructs steps.

## Work Guidance

- Begin with `CombatCommandWorkflow` for a player battle intent and `CombatContinuations` for an interrupted battle transition.
- Add combat state and pure behavior under `src/game/combat` or the appropriate `src/game/rules` collaborator.

## Verification

- `tests/core/test_combat_flow.gd` owns combat command, Auto, reaction, and completion behavior.
- `tests/scenario/test_reward_workflow.gd` owns battle reward handoff behavior.
- `tests/integration/test_session_persistence.gd` and `tests/scenario/test_scenario_vm.gd` own continuation save/restore and scenario return.

## Child DOX Index
