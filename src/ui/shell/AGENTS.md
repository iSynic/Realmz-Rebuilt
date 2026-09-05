# Application shell contract

## Purpose

Own the persistent Godot composition that surrounds every Realmz playthrough and the navigation boundary that mounts application workspaces.

## Ownership

- `realmz_application.tscn` is the complete application composition mounted by `project.godot`.
- `game_shell.tscn` owns the stable map or battlefield stage, party roster, narrative/status well, command regions, menus, and overlay hosts.
- `GameShell` coordinates scene-owned shell collaborators; its layout, menu, availability, status, picture, effects, commands, and automatic-route policies remain separate named owners.
- `ClassicCommandCatalog` owns the shell-wide command identity, media, action, context, availability, and focus registry. `classic_party_effect_slot.tscn` and `ClassicPartyEffects` own the reusable condition-effect presentation consumed by the retained shell.
- `screen_navigator.tscn` owns persistent workspace and overlay mount points. `ScreenNavigator` owns typed route history and scene mounting; `WorkspaceFocusController` owns focus and scroll restoration.
- `PresentationCoordinator` applies detached session results to the retained shell. `PresentationMediaController` supplies the composed application/scenario media context without exposing storage repositories to UI code.
- `ClassicPartyRoster` owns the persistent six-slot party rail and its reusable member and empty rows, including current-character, mandatory-selection, combat Auto, and effect-presentation state.
- `SystemScreen` and `SystemWorkspace` own the editable Save & Load, Display, Audio, Pacing, Accessibility, Controls, and Diagnostics composition. `SystemScreenController` binds detached save previews and presentation settings and instantiates only the exported save-slot row.
- `MusicPlaylistDialog` and its reusable row scene own the twenty-slot Classic playlist editor. `DebugToolsDialog` and `DebugActionConsole` own the developer-only typed command surface and readable committed-event history.
- `ScreenContentPresenter` composes route-local binders against the scene-owned workspace body and generic shared record scenes; it owns detached route state and route-specific presentation audio, not navigation history.

## Local Contracts

- Shell scripts bind, route, resize, and retain scene-owned controls. They do not construct route-specific layouts or decide gameplay legality.
- Route-local controllers own workspace content. The navigator may mount them but must not call their private methods or absorb their rendering logic.
- System preferences emit only host-owned presentation-setting changes and never alter Classic rules. Save and load actions remain typed application-host requests.
- Held Rest and Area Search cadence consults `GameShellStatusController.is_field_time_playback_active()` so command repetition waits for the authoritative intermediate clock presentation without reaching into shell-private state.
- Adjacent movement and combat playback update retained presenters and controls; scene instantiation occurs only at application or route transitions.
- All gameplay mutations continue through the typed application/session boundary.

## Work Guidance

- Open `game_shell.tscn` for stable HUD layout and `screen_navigator.tscn` for workspace/overlay placement.
- Open `music_playlist_dialog.tscn` for the player-facing playlist modal and `debug_tools_dialog.tscn` for the developer-only diagnostic surface.
- Edit `classic_party_effect_slot.tscn` for the stable effect-cell composition; keep effect sequencing in `ClassicPartyEffects` and shell binding in `GameShellPartyEffectsPresenter`.
- Keep responsive calculations in the named layout policy and controller rather than embedding them in unrelated presenters.

## Verification

- Run `tests/presentation/test_classic_ui_shell.gd`, `tests/presentation/test_classic_ui_system.gd`, and `tests/presentation/test_realmz_builder_previews.gd` after shell or navigation changes.
- Run `tools/verify_architecture.ps1` after moving shell collaborators or changing route ownership.

## Child DOX Index

- `routes/AGENTS.md` owns typed shell-mode and workspace route definitions plus their catalog.
