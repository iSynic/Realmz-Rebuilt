# Playthrough session

This is the doorway into a running adventure. `game_session.gd` exposes the small public transaction surface; `session_context.gd` holds the one owned aggregate; intent and response coordinators route a validated operation to its feature; and `session_coordinator_result.gd` returns the result to `GameSession` for the only commit or rollback.

Restore is deliberately staged. `session_restore_validator.gd` coordinates state, scenario, continuation, and request checks against a detached candidate. Only a fully accepted candidate replaces the live context. `session_continuation.gd` and its codec preserve interrupted operations in saves, while the view projectors build read-only `GameView` records and reuse them only for recognized committed revisions.

To trace a command, begin with `GameSession.submit`, continue through `SessionIntentCoordinator`, and then enter the named sibling feature workflow. To trace a response, begin with `GameSession.respond` and `SessionResponsesCoordinator`. The primary checks are `tests/core/test_game_session.gd`, `tests/integration/test_session_persistence.gd`, and `tests/scenario/test_scenario_vm.gd`; movement and projection changes also require the runtime performance probe.
