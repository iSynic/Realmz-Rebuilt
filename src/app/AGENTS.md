# Application composition contract

## Purpose

Own the Godot composition root and translate host input/output into the pure session boundary.

## Ownership

- `RealmzApplication` constructs the dependency graph explicitly.
- `GameSessionController` owns the replaceable `GameSession` instance and publishes committed steps.
- `GameSessionController` materializes one detached `GameView` per committed revision and shares it with host input checks and presenters; host code must not rebuild the same revision repeatedly.
- Detached campaign, vault, and host view models live under `src/app/view`; `CharacterVaultRevisionView` is app-owned while remaining `class_name`-compatible. Prepared package views expose the core `MediaSource` abstraction and never leak an infrastructure package catalog into presentation.
- This boundary coordinates repositories and presenters but contains no Realmz rules.

## Local Contracts

- No gameplay autoloads, service locators, `GameGlobal`, `NodeAccess`, or string-based dispatch.
- The controller may call only the public `GameSession` operations.
- Interaction UI responses enter through `GameSession.respond`; presenters never resume the VM or mutate state themselves.
- A committed `character_publication_requested` event is the only creator-to-vault write boundary. `RealmzApplication` snapshots the already-finalized session character and asks `CharacterVaultRepository` to publish an immutable revision; rejected/declined interactions and ordinary campaign mutations perform no vault write.
- `RealmzApplication` owns the no-scenario Character Files workshop. It loads the pinned Providence-built stock catalog, runs the same typed creator transaction through `CharacterCreationSession`, and publishes the completed detached character directly to the vault. Selecting a scenario continues to use that scenario's `GameSession`, so package-specific Race/Caste definitions and restrictions never leak into the application-wide stock creator.
- Vault listing converts each validated immutable revision into a detached `CharacterVaultRevisionView` against the selected campaign content so setup can inspect eligible and ineligible records without importing or mutating them. Its public fields and `from_record` factory behavior remain unchanged; presentation consumes the view without defining, duplicating, or compatibility-wrapping it.
- Restore constructs and validates a replacement before swapping the active session.
- End Adventure is a host-owned typed confirmation over the public `GameSession.close` boundary. The host prompt never enters `.r2save`; after confirmation, the session runs End Adventure and then Party Death package hooks, exposes any typed hook interactions, and closes only after both return without revival. Save-and-end starts that chain only after transactional save success, active combat never offers a save, and noncombat gameplay interactions remain modal. Campaign-library browsing alone does not close gameplay.
- Process Quit is a separate host-owned typed confirmation. Menu and window-manager requests share one path after disabling Godot's automatic quit acceptance; an active noncombat session may save first, battle cannot save, and cancellation or save failure must leave the process and session untouched. A pending host lifecycle confirmation owns response routing before standalone Character Files creation or session interactions so no subordinate workflow can consume it or leave Quit permanently pending. Quit never runs the scenario Global quit hook.
- Campaign discovery is a responsive manifest-only library operation. Choosing Play starts one cancellable infrastructure worker for full integrity validation and immutable installation; the composition root polls detached progress, joins the worker at its terminal state, and mutates neither media nor session until the validated result is available. Session-start failure leaves the previous media catalog untouched.
- Infrastructure progress and repository records are converted to app-owned detached view models before presentation. Presentation code may not consume infrastructure DTOs directly.
- Named `InputMap` actions are the host input boundary. Land movement binds the complete keypad compass, including 7/9/1/3 diagonals; the host suppresses those diagonals on dungeon maps before creating a typed intent. Camp, Rest, and Heal are separate typed commands; held Rest, Heal, and Area Search cadence is presentation-owned and emits one intent per pulse. The application catches physical mouse release so rerendering the pressed footer button cannot strand a held command. Back resolves blocking/passive modals, contextual drawers, and route history before returning to exploration; pending interactions suppress route and exploration input.
- The composition root owns one `HeldMovementController` shared by keyboard and mouse exploration. It submits one immediate typed single-step movement, requires a 300-millisecond hold before repetition begins, then uses the persisted 25–400 percent cadence without entering `.r2save` or simulation state. It stops the scheduler at every host/session boundary. The same host settings boundary applies the optional traveled-area preview, default-on Auto Note behavior, and Classic/readable typography choice to presentation only.
- While combat playback is active, the composition root rejects gameplay, route, and interaction input before it can reach the session. Space skips only the presentation transaction. Roster persistent-Auto toggles and the Escape full-Auto abort are the only gameplay exceptions: the host queues each stable character ID and desired boolean; turning one off settles current playback immediately, commits the queued change, and applies it before deciding whether to run the next one-activation Auto transaction. Escape queues Auto-off for every enabled party character and resumes manual control at the next activation boundary. Battlefield target clicks and Back/cancel remain host translations into the presentation-owned target state; only a completed target payload crosses the existing `GameSession.respond` boundary.
- A terminal session step reached during combat playback does not navigate to setup or campaign selection until `PresentationCoordinator` settles the retained battlefield and publishes that exact committed step. Host teardown and navigation therefore happen once, after presentation releases the prior view.
- The application applies window mode and presentation scales, but those settings never enter the session or save aggregate.
- The application injects Auto Switch to Melee only into a manual typed combat-move response. The core owns eligibility, source ordering, mutation, and any pending one-move continuation; no application preference object crosses into `GameState`.
- Direct-session battles expose a detached combat request while remaining intent-driven. The composition root translates that request's typed response body into the corresponding combat intent; scenario-owned combat continues through `GameSession.respond`. Both paths preserve the same presentation component and core legality contract.

## Work Guidance

- Keep dependency construction visible in `RealmzApplication`.
- Convert Godot input into typed intents and interaction responses before entering `src/core`.
- Keep process Quit, campaign-library navigation, and End Adventure as distinct host operations. Do not turn session close into a free-standing gameplay intent.

## Verification

- `tools/verify.ps1` validates scripts and runs the headless test suite.
- Playable slices require the MCP workflow documented in `docs/development.md`.

## Child DOX Index

- `controllers/AGENTS.md` owns host package, save, vault, and creator controller boundaries.
