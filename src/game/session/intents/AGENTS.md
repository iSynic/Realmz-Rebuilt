# Player intent contract

## Purpose

Own the feature-named commands and typed payloads accepted by `GameSession.submit_intent`.

## Ownership

- `PlayerIntentPayload` and the empty-payload marker.
- Exploration, inventory, magic, combat, party, and economy intent factories.
- Feature payload values and the central kind-to-payload registry.

## Local Contracts

- `PlayerIntent.Kind` is the stable command identity registry; never reorder or reuse a value.
- Each feature factory constructs only its own accepted payload type.
- Payloads are detached pure values. They retain no Nodes, repositories, live session context, or mutable collections supplied by a caller.
- `PlayerIntentRegistry` validates the kind/payload pairing and owns no gameplay legality.
- Add a command to the owning feature factory and payload family; do not grow forwarding factories or nested payload classes on `PlayerIntent`.

## Work Guidance

- Keep command names player- or workflow-facing and keep payload fields explicit.
- Characterize kind identity, normalization, and copied collections before changing a payload family.

## Verification

- `tests/core/test_game_session.gd` owns the complete intent-factory and registry contract.
- Run every gameplay, persistence, scenario, or presentation suite that consumes a changed family.
- Run `tools/verify.ps1` before committing a completed family migration.

## Child DOX Index
