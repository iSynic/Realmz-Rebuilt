# Playthrough economy workflow contract

## Purpose

Own player money transactions and the resumable handoffs that keep services and pooled wealth inside one session transaction.

## Ownership

- `SessionMoneyWorkflow` owns Pool, Share, and denomination transfers plus their movement recalculation.
- `ServiceContinuations` constructs service-interaction and pooled-wealth-departure continuations.
- `ServiceContinuationBody` carries the exact service handoff or departure stage and direction.
- `EconomyIntents` and `EconomyIntentPayloads` define typed Pool, Share, denomination-transfer, and service commands.
- Economy transactions consume the detached Bank, service, Shop, Temple, and Treasure request bodies owned by `src/game/economy`.

## Local Contracts

- Use `EconomyRules` for denomination, affordability, capacity, Pool, Share, and Swap behavior; do not duplicate those calculations here.
- Service mutations remain with their scenario operation owners, while this feature retains only the session-level continuation facts.
- Money and service operations preserve exact event, sound, movement-recalculation, interaction, and save behavior.
- Continuation kinds, fields, versions, and wire representation remain stable across relocation.
- `GameSession` alone commits, rolls back, changes revision, and constructs steps.

## Work Guidance

- Begin with `SessionMoneyWorkflow` for Party Wealth commands and `ServiceContinuations` for an interrupted service or departure.
- Add immutable shop/treasure data, mutable service state, or calculations to `src/game/economy`, not this orchestration layer.

## Verification

- `tests/integration/test_money_workflow.gd` owns public Pool, Share, and Swap transactions.
- `tests/integration/test_session_persistence.gd` and `tests/scenario/test_scenario_vm.gd` own interrupted service and restore behavior.
- Presentation coverage verifies detached Party Wealth and service workspaces.

## Child DOX Index
