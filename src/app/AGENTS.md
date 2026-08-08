# Application composition contract

## Purpose

Own the Godot composition root and translate host input/output into the pure session boundary.

## Ownership

- `RealmzApplication` constructs the dependency graph explicitly.
- `GameSessionController` owns the replaceable `GameSession` instance and publishes committed steps.
- `GameSessionController` materializes one detached `GameView` per committed revision and shares it with host input checks and presenters; host code must not rebuild the same revision repeatedly.
- This boundary coordinates repositories and presenters but contains no Realmz rules.

## Local Contracts

- No gameplay autoloads, service locators, `GameGlobal`, `NodeAccess`, or string-based dispatch.
- The controller may call only the public `GameSession` operations.
- Interaction UI responses enter through `GameSession.respond`; presenters never resume the VM or mutate state themselves.
- Restore constructs and validates a replacement before swapping the active session.
- Named `InputMap` actions are the host input boundary. Back resolves blocking/passive modals, contextual drawers, and route history before returning to exploration; pending interactions suppress route and exploration input.
- The application applies window mode and presentation scales, but those settings never enter the session or save aggregate.

## Work Guidance

- Keep dependency construction visible in `RealmzApplication`.
- Convert Godot input into typed intents and interaction responses before entering `src/core`.

## Verification

- `tools/verify.ps1` validates scripts and runs the headless test suite.
- Playable slices require the MCP workflow documented in `docs/development.md`.

## Child DOX Index

- No child AGENTS.md files are currently required.
