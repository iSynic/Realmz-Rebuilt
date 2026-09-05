# Application shell UI

Open `game_shell.tscn` to edit the persistent Realmz HUD: map or battlefield stage, six-character roster, narrative and status well, command decks, menus, effects, and interaction hosts. Open `screen_navigator.tscn` to edit the retained workspace and overlay mount points. Exploration and Combat are modes of this shell rather than placeholder workspace scenes.

`GameShell` coordinates focused collaborators for layout, status, menus, command binding, party effects, pictures, media, and automatic routing. `ScreenNavigator` mounts the typed route definitions under `routes/`; route controllers own their own content and selection state. `ClassicCommandCatalog` is the single shell-wide command registry, while the party-effect scene and animator own the reusable condition slots. The neighboring music-playlist scenes own the player-facing twenty-slot editor; the debug-tools and action-console scenes own developer-only diagnostics.

Detached playthrough views flow into the retained shell, and user actions leave as typed intents or interaction responses. Shell code does not decide gameplay legality or mutate saved state. Movement and combat updates reuse existing presenters and controls instead of rebuilding the scene tree.

Use Realmz Builder for Wide, Compact, empty, long-content, unavailable, and error profiles. Run the shell, System, and Builder preview suites after changing this feature; use the runtime movement probe when changing retained per-step presentation.
