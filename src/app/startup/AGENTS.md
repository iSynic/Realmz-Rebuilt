# Application startup contract

## Purpose

Own the first visible frame and prepare immutable application and campaign content without blocking or mutating an active session.

## Ownership

- `StartupFrontDoor` owns the launch card, retained intro media, and background construction handoff.
- `PackageHostController` owns discovery, validation, preparation, cancellation, and prepared-package retention.
- `StartupRouteBridge` connects the lightweight front door to the loaded application routes.
- Campaign, package-operation, and prepared-package views are detached app values consumed by UI.

## Local Contracts

- The first rendered frame contains only the opaque launch card and its source-backed cue.
- Package work is cancellable and joined on shutdown; only a validated detached result may change application content.
- A failed, cancelled, or superseded preparation leaves the active session and media catalog unchanged.
- Synchronous and worker package installation both honor the host's configured installation root, including isolated fixture storage.
- Startup views may expose `MediaSource`, but never storage repository or archive objects.

## Work Guidance

- Preserve the existing first-frame and retained-video timing when changing dependencies.
- Keep package preparation off the interactive frame and apply results on the main thread.

## Verification

- Run `tests/presentation/test_classic_ui_system.gd` and `tools/startup_probe.gd` for startup-sensitive changes.
- Run `tools/verify.ps1` before completing a workflow batch.

## Child DOX Index
