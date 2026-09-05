# Application composition contract

## Purpose

Own the visible application root, explicit dependency construction, and alignment between the authored shell and algorithmic spatial presenters.

## Ownership

- `RealmzApplication` constructs the dependency graph and connects named collaborators.
- `ApplicationSpatialLayout` aligns map, battlefield, dungeon, and interaction regions to the scene-authored shell.
- `ApplicationStepStatusText` formats short application-owned status wording.

## Local Contracts

- Dependency construction stays visible and typed; there is no service locator or gameplay autoload.
- The composition root coordinates public owners without forwarding or duplicating their state.
- Spatial layout changes read detached geometry and mutate presentation only.
- Scene instantiation occurs at startup or route changes, never per movement step or rendered frame.

## Work Guidance

- Add a dependency or signal to the smallest named construction phase that owns it.
- Keep stable layout in scenes and retain frequently updated presenters and controls.

## Verification

- Run `tests/presentation/test_classic_ui_system.gd`, shell tests, and the runtime performance probe for composition-sensitive changes.
- Run `tools/verify_architecture.ps1` after dependency changes.

## Child DOX Index
