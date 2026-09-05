# Application shell contract

## Purpose

Own the persistent Godot composition that surrounds every Realmz playthrough and the navigation boundary that mounts application workspaces.

## Ownership

- `realmz_application.tscn` is the complete application composition mounted by `project.godot`.
- `game_shell.tscn` owns the stable map or battlefield stage, party roster, narrative/status well, command regions, menus, and overlay hosts.
- `GameShell` coordinates scene-owned shell collaborators; its layout, menu, availability, status, picture, effects, commands, and automatic-route policies remain separate named owners.
- `screen_navigator.tscn` owns persistent workspace and overlay mount points. `ScreenNavigator` owns typed route history and scene mounting; `WorkspaceFocusController` owns focus and scroll restoration.
- `PresentationCoordinator` applies detached session results to the retained shell. `PresentationMediaController` supplies the composed application/scenario media context without exposing storage repositories to UI code.

## Local Contracts

- Shell scripts bind, route, resize, and retain scene-owned controls. They do not construct route-specific layouts or decide gameplay legality.
- Route-local controllers own workspace content. The navigator may mount them but must not call their private methods or absorb their rendering logic.
- Adjacent movement and combat playback update retained presenters and controls; scene instantiation occurs only at application or route transitions.
- All gameplay mutations continue through the typed application/session boundary.

## Work Guidance

- Open `game_shell.tscn` for stable HUD layout and `screen_navigator.tscn` for workspace/overlay placement.
- Keep responsive calculations in the named layout policy and controller rather than embedding them in unrelated presenters.

## Verification

- Run `tests/presentation/test_classic_ui_shell.gd`, `tests/presentation/test_classic_ui_system.gd`, and `tests/presentation/test_realmz_builder_previews.gd` after shell or navigation changes.
- Run `tools/verify_architecture.ps1` after moving shell collaborators or changing route ownership.

## Child DOX Index
