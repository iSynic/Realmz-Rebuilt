# Safe Scenario Actions

Safe Scenario Actions are reusable Providence-compiled programs that run inside the same serializable scenario VM as Classic instructions. `safe_expression_evaluator.gd` evaluates typed expressions and ordered arguments against one explicit VM frame and the narrow runtime operation surface. It does not own frames, continuations, or mutations.

`scenario_action_state.gd` stores the optional mutable state declared by package actions. The playthrough copies and restores it transactionally with the VM and gameplay RNG. Immutable action definitions live in `src/game/scenario`; instruction scheduling lives in `../vm`; gameplay effects cross `../runtime/realmz_runtime_api.gd`.
