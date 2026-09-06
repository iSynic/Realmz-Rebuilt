# Application platform contract

## Purpose

Own process lifecycle, presentation-only preferences, and debug-build host facilities.

## Ownership

- `ApplicationLifecycleHost` coordinates process Quit, End Adventure, Save and Quit, and deferred close interactions.
- `ApplicationLifecycle` is the pure option and decision policy for those host transitions.
- `ApplicationSettingsController` binds and persists presentation settings.
- `DebugToolsHost` exposes typed debug commands only in debug builds.
- `DevelopmentPreviewRequest` owns the strict developer-only request vocabulary shared with Providence; execution stays outside public release startup and never enters package or save data.

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
