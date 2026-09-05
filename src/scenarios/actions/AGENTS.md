# Safe Scenario Action contract

## Purpose

Own bounded Safe Scenario Action expression evaluation and mutable action-local state without introducing arbitrary script execution.

## Ownership

- `SafeExpressionEvaluator` for declared-value-type checks and ordered call or instruction argument evaluation.
- `ScenarioActionState` for versioned package-action state carried by the active playthrough.

## Local Contracts

- Safe bytecode is immutable Providence compiler output. Definitions remain under `src/game/scenario`; this folder owns execution support, not authoring state.
- Core operation names under `realmz.*` cannot be replaced. Campaign actions use their validated `scenario.<campaign>.*` namespace.
- Evaluation is deterministic, bounded by declared collection and depth limits, and may access only the explicit frame and runtime operation surface.
- Mutable action state is pure, typed, serializable, and copied transactionally with the session. Unknown schemas or malformed values fail without partial mutation.
- No evaluator or action state may access Nodes, files, wall-clock time, Godot randomness, or arbitrary GDScript.

## Work Guidance

- Begin with `safe_expression_evaluator.gd` for an expression or argument issue and `scenario_action_state.gd` for persisted action state.
- Frame scheduling and instruction-phase transitions remain in `../vm`; domain effects go through `../runtime/realmz_runtime_api.gd`.

## Verification

- `tests/scenario/test_scenario_vm.gd` owns Safe Action calls, expressions, loops, state, limits, save round trips, and explicit failures.
- `tests/integration/test_session_persistence.gd` owns whole-session action-state restoration.

## Child DOX Index
