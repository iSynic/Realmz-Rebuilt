# Scenario runtime continuation contract

## Purpose

Own typed payloads, feature factories, and strict decoding for scenario operations suspended at player input.

## Ownership

- `ScenarioRuntimeContinuationBody` and the text, choice, character, thief, age, service, combat, opcode-death, and reward payloads.
- `ScenarioInteractionContinuations`, `ScenarioAgeContinuations`, `ScenarioServiceContinuations`, `ScenarioCombatContinuations`, and `ScenarioRewardContinuations` as live construction entry points.
- `ScenarioRuntimeContinuationCodec` as the only saved-envelope decoder and payload validator.

## Local Contracts

- `ScenarioRuntimeContinuation` remains the stable versioned envelope and sole owner of wire kind constants.
- Preserve every existing kind, field name, version, validation rule, VM snapshot representation, and RNG boundary.
- Simple Encounter choices may carry optional boolean `reopenResult` for opcode 35's immediate result replacement. Omission retains ordinary encounter repetition. The flag cannot accompany Complex Encounter or GOSUB continuation payloads; its existing iteration and authored option-index mapping survive save/restore unchanged.
- Payloads contain detached values only and never retain state, rules, Nodes, repositories, or presentation.
- Live callers use feature factories; dictionaries exist only in `wire_payload` and the strict codec.
- Add new kinds to their owning factory and the complete denominator test. Do not restore envelope factories, nested payload catalogs, or compatibility aliases.

## Work Guidance

- Name payloads for the facts they carry and factories for the runtime feature that owns the suspended operation.
- Reject unknown fields, wrong payload families, invalid source/caller pairs, and impossible resume combinations before restore assignment.

## Verification

- `tests/scenario/test_scenario_vm.gd::_test_scenario_runtime_continuation_contracts` owns every stable kind and exact wire round trip.
- Reward, combat, and persistence suites own the resumed gameplay behavior.

## Child DOX Index

- No child DOX files are currently needed.
