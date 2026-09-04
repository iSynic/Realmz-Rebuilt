# Session continuation contract

## Purpose

Own the feature-named, typed payloads and strict codec that resume an interrupted playthrough transaction.

## Ownership

- `SessionContinuationBody` and the exploration, application, targeting, item-XAP, service, age, combat, reward, and boat payloads.
- `ExplorationContinuations`, `ApplicationContinuations`, `InventoryContinuations`, `MagicContinuations`, `ServiceContinuations`, and `CombatContinuations` as live construction entry points.
- `SessionContinuationCodec` as the only saved-envelope decoder and payload validator.

## Local Contracts

- `SessionContinuation` remains the stable versioned envelope. Feature factories fix its kind; callers never pair an arbitrary string with a payload.
- Preserve every existing continuation kind, field name, version, validation rule, and save representation exactly.
- Payloads contain detached values only. They never retain Nodes, repositories, presenters, or an owning session.
- Dictionaries exist only inside `wire_payload` and `SessionContinuationCodec`. Live workflows receive typed payloads.
- Add a continuation to its feature factory and the central codec. Do not add forwarding constructors or nested payload catalogs to the envelope.

## Work Guidance

- Name a payload for the transaction fact it carries, not for the coordinator currently consuming it.
- Keep decoding strict: unknown fields, mismatched payload families, invalid identities, and impossible resume combinations fail before restore assignment.

## Verification

- `tests/scenario/test_scenario_vm.gd::_test_session_continuation_contracts` owns the complete stable-kind and exact-wire denominator.
- `tests/integration/test_session_persistence.gd` owns full-session save and restore behavior.

## Child DOX Index

- No child DOX files are currently needed.
