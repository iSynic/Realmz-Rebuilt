# UI routes

Each `.tres` file defines one visible application destination. A route is either a persistent shell mode or a mounted workspace. Shell modes reuse the map, battlefield, roster, narrative, and command regions already authored in `game_shell.tscn`; workspaces name the scene mounted by `ScreenNavigator`.

Edit labels, shortcuts, descriptions, route kind, and workspace scene here. Keep route behavior in the destination controller and navigation history in `ScreenNavigator`.
