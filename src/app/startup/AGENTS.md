# Application startup contract

## Purpose

Own the first visible frame and prepare immutable application and campaign content without blocking or mutating an active session.

## Ownership

- `StartupFrontDoor` owns the launch card, retained intro media, background construction handoff, and input forwarding to the loaded application's temporarily hosted F12 Diagnostics surface.
- The scene-authored display compositor owns the persistent SubViewport around both front door and application; handoff mounts the application into that viewport without recreating the intro or adventure.
- The compositor remains `SceneTree.current_scene` during startup handoff. The front door relinquishes its prepared application before teardown; it frees that application only when ownership was never transferred.
- `PackageHostController` owns discovery, validation, preparation, cancellation, and prepared-package retention.
- `StartupRouteBridge` connects the lightweight front door to the loaded application routes.
- Campaign, package-operation, and prepared-package views are detached app values consumed by UI.

## Local Contracts

- The first rendered frame contains only the opaque launch card and its source-backed cue.
- Disable the hidden application's input callbacks after its ready notification; Godot automatically enables implemented callbacks during readiness. Only the visible front door consumes input until the deferred route handoff enables the application.
- Package work is cancellable and joined on shutdown; only a validated detached result may change application content.
- A failed, cancelled, or superseded preparation leaves the active session and media catalog unchanged.
- Synchronous and worker package installation both honor the host's configured installation root, including isolated fixture storage.
- Startup views may expose `MediaSource`, but never storage repository or archive objects.
- Discovery keeps the ready current revision for each of the 13 shipped campaign IDs authoritative over installed revisions with the same ID; unrelated campaign IDs retain the ordinary user-install override behavior.

## Work Guidance

- Preserve the existing first-frame and retained-video timing when changing dependencies.
- Keep package preparation off the interactive frame and apply results on the main thread.

## Verification

- Run `tests/presentation/test_classic_ui_system.gd` and `tools/startup_probe.gd` for startup-sensitive changes.
- Startup controller regression input must enter through the viewport with the hidden application mounted; direct handler calls bypass competing input owners.
- Run `tools/verify.ps1` before completing a workflow batch.

## Child DOX Index
