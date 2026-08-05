# Application composition contract

## Purpose

Own the Godot composition root and translate host input/output into the pure session boundary.

## Ownership

- `RealmzApplication` constructs the dependency graph explicitly.
- `GameSessionController` owns the replaceable `GameSession` instance and publishes committed steps.
- This boundary coordinates repositories and presenters but contains no Realmz rules.

## Local Contracts

- No gameplay autoloads, service locators, `GameGlobal`, `NodeAccess`, or string-based dispatch.
- The controller may call only the public `GameSession` operations.
- Restore constructs and validates a replacement before swapping the active session.

## Work Guidance

- Keep dependency construction visible in `RealmzApplication`.
- Convert Godot input into typed intents and interaction responses before entering `src/core`.

## Verification

- `tools/verify.ps1` validates scripts and runs the headless test suite.
- Playable slices require the MCP workflow documented in `docs/development.md`.

## Child DOX Index

- No child AGENTS.md files are currently required.
