# Shell and routing

`game_shell.tscn` is the recognizable overworld HUD: menu, play stage, roster, narrative and status well, command decks, effects, and overlay hosts. Exploration and combat are modes of that shell. Workspaces replace the primary workspace region and return through `ScreenNavigator` history.

Routes are declared by typed route resources, not free-form dictionaries or one-node marker scenes. The navigator owns mounting and focus restoration; each scene controller owns binding and local presentation state. `test_classic_ui_shell.gd` protects shell composition and `test_classic_ui_system.gd` protects navigation and responsive behavior.
