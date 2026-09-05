# Playthrough economy

Use `session_money_workflow.gd` for Party Wealth Pool, Share, and denomination-transfer commands. It delegates value, capacity, and custody calculations to `src/game/economy` and recalculates movement only after a successful transaction.

`service_continuations.gd` creates the saved handoffs for an active scenario service and for leaving a location while wealth remains pooled. `service_continuation_body.gd` carries only the service identity/runtime continuation or the exact warning/distribution departure stage and direction; the central continuation codec remains a wire boundary rather than an economy owner.

Player commands enter through `intents/economy_intents.gd`; its payload family carries only the selected denomination, source, target, quantity, and service operation.

The bodies under `src/game/economy/requests` describe Bank, Shop, Temple, service, and Treasure interactions. These workflows resume their selected actions; the bodies themselves contain already-projected records and availability, never live service or inventory state.

Begin verification with `tests/integration/test_money_workflow.gd`. Use the session-persistence and scenario-VM suites for interrupted services and pooled-wealth departure restoration; UI layout remains under `src/ui/services`.
