# Exploration UI

Start with `classic_map_presenter.gd` for the retained two-dimensional land and dungeon surface. First-person dungeon projection lives under `dungeon/`. Both presenters consume the same detached topology, discovery, visibility, secret, position, and heading facts; presentation owns no second map or facing state.

`ClassicRetainedMapSurface`, `MapPresentationGeometry`, and `MapTextureCache` divide retained layers, projection math, and decoded media reuse. `HeldMovementController` translates physical holds into typed movement submissions, while `ClassicFieldTimePlayback` presents committed clock steps. The Search and Torch command scripts own only their source-backed visual composition; the shell binds their commands.

Keep topology, traversability, LOS, secret discovery, triggers, time, and fatigue in the game and playthrough layers. Keep the viewport, textures, meshes, cameras, animation, and incremental drawing here. Ordinary movement updates entering strips and overlays rather than reconstructing the complete map.

Run the presentation shell/system suites after control or map changes. Run the dungeon projection and transition probes for first-person work, and the rendered movement probe whenever retained map or per-step presentation changes.
