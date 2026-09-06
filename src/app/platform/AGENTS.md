# Application platform contract

## Purpose

Own process lifecycle, presentation-only preferences, and debug-build host facilities.

## Ownership

- `ApplicationLifecycleHost` coordinates process Quit, End Adventure, Save and Quit, and deferred close interactions.
- `ApplicationLifecycle` is the pure option and decision policy for those host transitions.
- `ApplicationSettingsController` binds and persists presentation settings.
- `DebugToolsHost` exposes typed debug commands only in debug builds.
- `DevelopmentPreviewRequest` owns the strict developer-only request vocabulary shared with Providence. `DevelopmentPreviewSession` validates the temporary package through the ordinary application-plus-scenario boundary, creates the deterministic in-memory party, and enters an Action Point, Simple, Complex, or owner-bound Thief Encounter, map location, exact scenario-owned scrolling `TEXT`, or exact Classic Battle, Treasure, or Shop target. Complex, Thief, Battle, Treasure, and Shop readiness requires the ordinary typed interaction surface; a Thief target enters through the exact owning Complex Encounter's authored action, and direct Shop preview is unrestricted because caller-owned acceptance ranges are not part of `Data SD`. `DevelopmentPreviewResultWriter` owns the strict result envelope. Export-excluded tools provide the headless and interactive hosts; public release startup never selects them.

## Local Contracts

- Process Quit and End Adventure are distinct operations.
- Settings may affect presentation, input cadence, renderer choice, sound, and accessibility; they never alter deterministic game truth.
- Debug commands enter through the typed public debug boundary and never appear in release UI or saves.
- Cancelled or failed lifecycle operations leave both process and session active.

## Work Guidance

- Keep operating-system notifications at this boundary and game lifecycle decisions in public session operations.
- Keep setting defaults and persistence synchronized with `src/storage/settings`.

## Verification

- Run `tests/presentation/test_classic_ui_system.gd` and the settings repository suite for affected work.
- Run native smoke verification for process-lifecycle changes.

## Child DOX Index
