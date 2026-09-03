# Shell and routing

`game_shell.tscn` is the recognizable overworld HUD: menu, play stage, roster, narrative and status well, command decks, effects, and overlay hosts. Exploration and combat are modes of that shell. Workspaces replace the primary workspace region and return through `ScreenNavigator` history.

Routes are declared by typed route resources, not free-form dictionaries or one-node marker scenes. The navigator owns mounting and focus restoration; each scene controller owns binding and local presentation state. `test_classic_ui_shell.gd` protects shell composition and `test_classic_ui_system.gd` protects navigation and responsive behavior.

The shell's persistent Party rail begins at `src/ui/screens/classic_party_roster.tscn`. Its member record, empty position, selection number, current-character marker, combat Auto toggle, and pointer-following selection count are editor-authored. `ClassicPartyRoster` binds detached `CharacterView` records, preserves matching rows during incremental exploration updates, and performs only source-backed portrait compositing. Its exported member and empty-row scenes are the only variable roster records.
