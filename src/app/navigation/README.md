# Application navigation

Begin with `application_input_router.gd` when tracing a key, pointer action, route shortcut, held command, or dungeon-control mapping. `ui_input_actions.gd` names the host actions; the router applies ownership priority and translates accepted input into typed session commands, interaction responses, or presentation-only operations.

This folder contains no Realmz rules and no saved state. Pending interactions, combat playback, route workspaces, and exploration each have explicit precedence so a physical input has one owner. Input-sensitive checks live primarily in `tests/presentation/test_classic_ui_system.gd`, `tests/presentation/test_classic_ui_shell.gd`, and the affected exploration/combat workflow suite.
