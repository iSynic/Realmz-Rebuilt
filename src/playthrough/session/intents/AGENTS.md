# Player intent contract

## Purpose

Own the small central payload protocol and kind-to-payload registry accepted by `GameSession.submit_intent`.

## Ownership

- `PlayerIntentPayload` and the empty-payload marker.
- `PlayerIntentRegistry`, the central kind-to-payload registry.

Feature factories and payload values live beside their world, inventory, magic, combat, character, or economy workflow.

## Local Contracts

- `PlayerIntent.Kind` is the stable command identity registry; never reorder or reuse a value.
- Each sibling feature factory constructs only its own accepted payload type.
- Payloads are detached pure values. They retain no Nodes, repositories, live session context, or mutable collections supplied by a caller.
- `PlayerIntentRegistry` validates the kind/payload pairing and owns no gameplay legality.
- Add a command to the owning feature factory and payload family; do not grow forwarding factories or nested payload classes on `PlayerIntent`.

## Work Guidance

- Keep command names player- or workflow-facing and keep payload fields explicit.
- Characterize kind identity, normalization, and copied collections before changing a payload family.

## Verification

- `tests/core/test_game_session.gd` owns the complete intent-factory and registry contract.
- Run every gameplay, persistence, scenario, or presentation suite that consumes a changed family.
- Run the complete gate at the owning batch boundary.

## Child DOX Index
