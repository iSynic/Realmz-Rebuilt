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
- A committed `character_publication_requested` event is the only creator-to-vault write boundary. `RealmzApplication` snapshots the already-finalized session character and asks `CharacterVaultRepository` to publish an immutable revision; rejected/declined interactions and ordinary campaign mutations perform no vault write.
- Vault listing converts each validated immutable revision into a detached character view against the selected campaign content so setup can inspect eligible and ineligible records without importing or mutating them.
- Restore constructs and validates a replacement before swapping the active session.
- End Adventure is a host-owned typed confirmation over the public `GameSession.close` boundary. The host prompt never enters `.r2save`; save-and-end closes only after transactional save success, active combat never offers a save, and noncombat gameplay interactions remain modal. Campaign-library browsing alone does not close gameplay.
- Process Quit is a separate host-owned typed confirmation. Menu and window-manager requests share one path after disabling Godot's automatic quit acceptance; an active noncombat session may save first, battle cannot save, and cancellation or save failure must leave the process and session untouched. Quit never runs the scenario Global quit hook.
- Campaign discovery is a responsive manifest-only library operation. Choosing Play starts one cancellable infrastructure worker for full integrity validation and immutable installation; the composition root polls detached progress, joins the worker at its terminal state, and mutates neither media nor session until the validated result is available. Session-start failure leaves the previous media catalog untouched.
- Named `InputMap` actions are the host input boundary. Land movement binds the complete keypad compass, including 7/9/1/3 diagonals; the host suppresses those diagonals on dungeon maps before creating a typed intent. Camp and Rest are separate typed commands; held Rest repeat cadence is presentation-owned and emits one Rest intent per pulse. Back resolves blocking/passive modals, contextual drawers, and route history before returning to exploration; pending interactions suppress route and exploration input.
- The application applies window mode and presentation scales, but those settings never enter the session or save aggregate.

## Work Guidance

- Keep dependency construction visible in `RealmzApplication`.
- Convert Godot input into typed intents and interaction responses before entering `src/core`.
- Keep process Quit, campaign-library navigation, and End Adventure as distinct host operations. Do not turn session close into a free-standing gameplay intent.

## Verification

- `tools/verify.ps1` validates scripts and runs the headless test suite.
- Playable slices require the MCP workflow documented in `docs/development.md`.

## Child DOX Index

- No child AGENTS.md files are currently required.
