# Application shell contract

## Purpose

Own the persistent Godot composition that surrounds every Realmz playthrough and the navigation boundary that mounts application workspaces.

## Ownership

- `realmz_application.tscn` is the complete application composition mounted by `project.godot`.
- `game_shell.tscn` owns the stable map or battlefield stage, party roster, narrative/status well, command regions, menus, and overlay hosts.
- `GameShell` coordinates scene-owned shell collaborators; its layout, menu, availability, status, picture, effects, commands, and automatic-route policies remain separate named owners. `GameShellRoutePolicy` also identifies the active battlefield route at the first combat playback frame. Its nested `ControllerAccess` is the narrow presentation facade for prompts, text editing, radials, binding feedback, and controller roster selection.
- `ClassicCommandCatalog` owns the shell-wide command identity, media, action, context, availability, and focus registry. `classic_party_effect_slot.tscn` and `ClassicPartyEffects` own the reusable condition-effect presentation consumed by the retained shell.
- `screen_navigator.tscn` owns persistent workspace and overlay mount points. `ScreenNavigator` owns typed route history and scene mounting; `WorkspaceFocusController` owns semantic focus and nested-scroll restoration by route, operation, and stable record identity, falling forward then backward when a record disappears.
- `PresentationCoordinator` applies detached session results to the retained shell, acknowledges the exact revision only after it has drawn, activates Combat as soon as battle-start playback has a battlefield, and keeps route visibility and music on the currently presented combat state until playback settles. Its detached observation identifies the presented, drawn, deferred, and current playback-frame boundaries without exposing mutable presentation owners. Terminal combat departures remain deferred until the retained sequence finishes. `PresentationMediaController` supplies the composed application/scenario media context without exposing storage repositories to UI code.
- `ClassicPartyRoster` owns the persistent six-slot party rail and its reusable member and empty rows, including current-character, mandatory-selection, combat Auto, event-local playback health, and effect-presentation state.
- `SystemScreen` and `SystemWorkspace` own the editable Save & Load, Display, Audio, Pacing, Accessibility, Controls, and Diagnostics composition behind one visible category rail. Pacing owns the overall combat-speed slider and the separate default-off Hurry Spell Resolution toggle. Controls owns the controller draft editor, live input display, conflict/reachability status, tuning, binding capture requests, and docked persistent Restore Defaults and Apply actions. Display exposes the default-on custom fog tile preference; off means exact Castle black, not decorative surround art. `SystemScreenController` binds detached save previews and presentation settings and instantiates only variable save-slot and controller-binding rows.
- `MusicPlaylistDialog` and its reusable row scene own the twenty-slot Classic playlist editor. `DebugToolsDialog` owns the shared F12 Diagnostics surface and its debug-build-only command capability; `DebugActionConsole` owns debug-build-only readable committed-event history.
- `ScreenContentPresenter` composes route-local binders against the scene-owned workspace body and generic shared record scenes; it owns detached route state and route-specific presentation audio, not navigation history.
- `ControllerPromptStrip` is a non-layout three-second translucent hint shown only for Actions, Workspaces, Top Menu, System, and explicit inspection; its labels resolve the active bindings and controller family. `GameShellMenuController` owns controller traversal of the existing top-menu headings while `controller_top_menu_overlay.tscn` and its reusable authored row draw entries inside the main viewport; disabled entries remain selectable for their reason, and enabled entries invoke their existing route, command, or system owners exactly once. The shell mounts one shared `ControllerRadialOverlay`; interaction actions retain their active component owner, shell action entries come from `GameShellCommandController`, and the curated workspace pages exclude unrestricted internal combat or service routes.
- The shell also mounts one shared `ControllerQwertyEditor` above every route and interaction. Activating a focused `LineEdit` or `TextEdit` opens it with the existing text, caret, and line-edit length constraint; Done and Cancel return to the unchanged outer workflow.

## Local Contracts

- Shell scripts bind, route, resize, and retain scene-owned controls. They do not construct route-specific layouts or decide gameplay legality.
- Route-local controllers own workspace content. The navigator may mount them but must not call their private methods or absorb their rendering logic.
- Every route refresh invalidates queued focus restoration before mounting or emitting route changes, including Exploration and Combat shell modes with no workspace body.
- System preferences emit only host-owned presentation-setting changes and never alter Classic rules. Save and load actions remain typed application-host requests.
- Held Rest, Heal, and Area Search cadence consults `GameShellStatusController.is_field_time_playback_active()` so command repetition waits for the authoritative intermediate clock presentation without reaching into shell-private state. Confirming Rest or Heal from the action radial transfers the held-command owner to controller South until its release, using the same immediate pulse and timer as the footer control.
- Adjacent movement and combat playback update retained presenters and controls; scene instantiation occurs only at application or route transitions.
- A detached complete-refresh request always takes the full shell presentation path, even when restored domain revisions resemble an ordinary movement update; the roster must bind the restored view at that boundary.
- Party-effect presentation treats borrowed condition arrays as read-only across repeated, replacement and inactive refreshes.
- Roster effect tweens bind to their target row's lifetime, so a restore or roster replacement cancels callbacks before the old row is freed.
- All gameplay mutations continue through the typed application/session boundary.
- Controller focus uses stable route focus groups, captures before content rebinds and route departures, restores by semantic identity, reveals focused controls through their owning scroll container, and leaves a newer visible modal, popup, top menu, or radial in sole control until it closes.
- Repeated controller top-menu navigation resolves the currently selected authored row only after the replacement layout settles. Deferred scrolling must not retain a row instance that a subsequent menu render can replace.
- Escape opens System only from exposed, completed-party Exploration. Setup, inspection, and front-door Back remain owned by their current surface; returning from assembly goes to the front door without discarding the setup party. Exploration input and spatial rendering independently reject unfinished party setup.

## Work Guidance

- Open `game_shell.tscn` for stable HUD layout and `screen_navigator.tscn` for workspace/overlay placement.
- Open `music_playlist_dialog.tscn` for the player-facing playlist modal and `debug_tools_dialog.tscn` for the capability-shaped retail Diagnostics and developer-tools surface.
- Edit `classic_party_effect_slot.tscn` for the stable effect-cell composition; keep effect sequencing in `ClassicPartyEffects` and shell binding in `GameShellPartyEffectsPresenter`.
- Keep responsive calculations in the named layout policy and controller rather than embedding them in unrelated presenters.

## Verification

- Run `tests/presentation/test_classic_ui_shell.gd`, `tests/presentation/test_classic_ui_system.gd`, and `tests/presentation/test_realmz_builder_previews.gd` after shell or navigation changes.
- Run `tools/verify_architecture.ps1` after moving shell collaborators or changing route ownership.

## Child DOX Index

- `routes/AGENTS.md` owns typed shell-mode and workspace route definitions plus their catalog.
