# Session transactions

`GameSession` is the public adventure boundary: start, restore, submit an intent, respond to an interaction, inspect a detached view, snapshot, and close. It owns rollback, revision changes, request identity, and exact-once commit. Workflows receive an operation-scoped context containing the active content, state, RNG, VM, continuations, and revision services.

`InteractionRequest` is the small registry and wire envelope for pending player decisions. Feature-owned payloads live under `src/game/session/requests`: each file names the decision it carries, validates its own detached data, and preserves the established serialized kind and fields. Add a new request by defining its payload beside that family, registering its kind and codec centrally, then handling it in the owning workflow and UI binder. Do not grow another nested protocol catalog inside `InteractionRequest`.

No UI, repository, Node, or wall-clock dependency enters this layer. New gameplay routes should add or reuse a typed intent and an owning feature workflow instead of exposing coordinator helpers. `test_game_session.gd` protects the API and `test_session_persistence.gd` protects the complete saveable aggregate.
