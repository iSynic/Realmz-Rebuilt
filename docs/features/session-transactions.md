# Session transactions

`GameSession` is the public adventure boundary: start, restore, submit an intent, respond to an interaction, inspect a detached view, snapshot, and close. It owns rollback, revision changes, request identity, and exact-once commit. Workflows receive an operation-scoped context containing the active content, state, RNG, VM, continuations, and revision services.

No UI, repository, Node, or wall-clock dependency enters this layer. New gameplay routes should add or reuse a typed intent and an owning feature workflow instead of exposing coordinator helpers. `test_game_session.gd` protects the API and `test_session_persistence.gd` protects the complete saveable aggregate.
