# Playthrough

Begin with `GameSession`. It is the public transaction boundary used to start or restore a campaign, submit one player intent, answer one pending request, obtain a detached view, snapshot the playthrough, or close it.

`SessionContext` holds the current content, game state, deterministic random generator, Scenario VM, Scenario Action state, continuations, and revision. Short-lived coordinators translate a `GameSession` operation into feature workflows; workflows perform the actual exploration, inventory, magic, service, combat, reward, and lifecycle work. The game and scenario layers never depend back on this folder.

Restore is deliberately staged. `SessionRestoreValidator` checks package identity and reconstructs the candidate transaction, `SessionRestoreStateValidator` checks detached game truth, and `SessionScenarioRestoreValidator` checks pending VM workflows. Session-continuation checks stay with the entry validator because they join both sides. Only `GameSession.restore` assigns a fully accepted candidate to the live session.

For a common change, follow this path:

1. Find the typed intent or response at the `GameSession` boundary.
2. Follow its coordinator into the feature workflow under `workflows/`.
3. Keep rules and saved truth in `src/game`, and scenario instruction behavior in `src/scenarios`.
4. Add characterization to the matching core, scenario, or integration suite before changing transaction order.

Performance-sensitive paths are adjacent movement, detached view projection, combat turns, restore, and package-to-session startup. Preserve revision caching, incremental map projection, exact RNG order, and all-or-nothing rollback. Run `tools/run_tests.ps1` with the owning suite while iterating and `tools/verify.ps1` before committing.
