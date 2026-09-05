# Scenario runtime continuations

This folder owns the saveable facts needed to resume a Classic or Safe scenario operation after player input. `ScenarioRuntimeContinuation` is the versioned envelope; `ScenarioRuntimeContinuationCodec` is the only dictionary decoder. Interaction, age, service, combat, and reward code construct payloads through their matching `Scenario*Continuations` factory.

The data flow is `RealmzRuntimeApi` or a runtime operation → feature factory → typed body → VM snapshot`. On restore, the codec validates the exact kind and fields before recreating that same typed body. Bodies contain detached values only and never own game state, rules, Nodes, repositories, or presentation.

When adding a continuation, add its stable kind to the envelope, place its payload and factory with the owning feature, admit it in the codec, and extend `_test_scenario_runtime_continuation_contracts`. Preserve existing wire strings and fields. The focused owners are `test_scenario_vm.gd`, `test_reward_workflow.gd`, `test_combat_flow.gd`, and `test_session_persistence.gd`; checkpoint cost is measured by `combat_performance_probe.gd`.
