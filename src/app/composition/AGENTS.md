# Application composition contract

## Purpose

Own the visible application root, explicit dependency construction, and alignment between the authored shell and algorithmic spatial presenters.

## Ownership

- `RealmzApplication` constructs the dependency graph and connects named collaborators.
- The root routes the scene-authored Save & Load Update Save request to the application storage host without altering the active session.
- `ApplicationSpatialLayout` aligns map, battlefield, dungeon, and interaction regions to the scene-authored shell.
- The spatial layout applies optional 1x–4x world-only integer zoom to retained 2D map and battlefield presenters; the 3D dungeon remains integer-fit inside its own stage.
- `ApplicationStepStatusText` formats short application-owned status wording.

## Local Contracts

- Dependency construction stays visible and typed; there is no service locator or gameplay autoload.
- The composition root coordinates public owners without forwarding or duplicating their state.
- Spatial layout changes read detached geometry and mutate presentation only.
- Map projection size, camera bounds, and pointer hit testing consume the zoomed presenters' local geometry; game/session state retains no scale.
- Scene instantiation occurs at startup or route changes, never per movement step or rendered frame.
- Package and session-start failures publish a detached terminal package-operation view. Idle worker polling leaves that failure visible; a new attempt replaces it and successful completion clears it.
- A developer preview arrives only as a pre-tree request meta value from the export-excluded host. `RealmzApplication` selects scratch persistence collaborators and the preview session before ordinary startup work; it does not copy preview package/session logic into the composition root.
- The opt-in runtime testing host receives the active session controller, content identity accessor, and host readiness accessor explicitly after composition. Its readiness record separates committed, presented, presentation-drawn, deferred, and playback-frame identities from the transport's own draw revision. Disabled and release starts create no listener; testing cannot discover private collaborators through a service locator.
- An export-excluded fixture host supplies a strict pre-tree launch request. Composition selects scratch save/settings/vault/install repositories before any startup work and delegates fixture preparation to the platform owner. Public `submit_movement` and `submit_response` are shared by existing input routing and fixture commands; testing applies the ordinary input/playback/modal gates before calling them.

## Work Guidance

- Add a dependency or signal to the smallest named construction phase that owns it.
- Keep stable layout in scenes and retain frequently updated presenters and controls.

## Verification

- Run `tests/presentation/test_classic_ui_system.gd`, shell tests, and the runtime performance probe for composition-sensitive changes.
- Run `tools/verify_architecture.ps1` after dependency changes.

## Child DOX Index
