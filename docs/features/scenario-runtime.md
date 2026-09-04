# Scenario runtime

Compiled scenario definitions are immutable game content. `ScenarioVm` executes their instruction timelines, while `RealmzRuntimeApi` adapts Classic instructions and safe scenario operations to public rules and playthrough collaborators. Scenario Actions are reusable callable programs; call sites do not contain executable gap behavior.

Keep dictionaries at package and save codecs. Runtime frames, requests, responses, and continuations are typed and deterministic. Begin with `tests/scenario/test_scenario_vm.gd`; reward and battle-return behavior is owned by `test_reward_workflow.gd`. Castle evidence explains behavior but does not become a second host architecture.

Service opcodes enter through `ClassicServiceOperations`. Shop and Temple remain there; Bank request projection and wealth transfers belong to `ClassicBankingOperations`. Both use `ClassicMoneyTransferSupport` for package-backed movement validation and recalculation, so changing denomination movement or load behavior has one explicit owner. `test_money_workflow.gd` is the focused Bank and pooled-wealth characterization suite.

Battle opcodes enter through `ClassicBattleLifecycleOperations`, which owns start, resume, retreat, battle/death macros, age acknowledgements, and terminal handoff. The neighboring `CombatInteractionRequestBuilder` performs the separate read-only task of turning current combat state and rule legality into the typed `combat_action` request used by both scenario-owned and direct-session battles. Change combat mutation in the lifecycle or game combat owners; change detached command facts in the builder. Characterization begins in `test_scenario_vm.gd`, `test_reward_workflow.gd`, `test_combat_flow.gd`, and `test_session_persistence.gd`.
