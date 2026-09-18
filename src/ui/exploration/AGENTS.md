# Exploration presentation contract

## Purpose

Own the retained 2D map and optional first-person dungeon presentation for detached world topology and exploration views.

## Ownership

- `ClassicMapPresenter` draws the 2D world and dungeon map, overlays, party marker, darkness, LOS, discovery, and developer-only map diagnostics.
- `ClassicRetainedMapSurface`, `MapPresentationGeometry`, and `MapTextureCache` own incremental retained layers, stateless projection geometry, and decoded media reuse respectively.
- `HeldMovementController` translates held pointer or key cadence into independent typed movement submissions; `ClassicFieldTimePlayback` presents committed time changes.
- `ClassicSearchCommandButton` and `ClassicTorchCommandButton` own the source-backed visual state of the retained exploration controls; the shell command controller owns their typed command binding and held cadence.
- `dungeon/` owns `DungeonGeometryProjection`, `DungeonSceneMeshBuilder`, and `DungeonMap3DPresenter`, which derive first-person geometry from the same detached topology as the 2D map.

## Local Contracts

- Presentation never decides traversability, visibility, discovery, secrets, facing, triggers, or movement cost.
- Every projected cell withheld by exploration visibility uses the default-on byte-exact project-owner fog tile or, when that host preference is off, exact opaque Castle black: never-seen cells on authored LOS maps and non-LOS cells outside both the current Classic window and remembered discovery. Seen or revealed terrain draws at normal fidelity, and leaving a cell's current LOS never conceals it again. Decorative stage surround art remains only outside projected map cells and is never the fog-off replacement.
- Ordinary movement updates retained layers and entering geometry incrementally. Map, topology, LOS, restore, and projection-boundary changes may rebuild from detached authority.
- The 2D and 3D views consume one save-owned heading and one topology; no renderer-owned collision or discovery state is allowed.
- Hidden dungeon secrets remain solid or withheld until world discovery commits them; discovered secret edges project as open archways in 3D and the source-backed red `S` marker in 2D. Unmapped cells do not leak authored doors, columns, or stale fog patterns before their bounded discovery window is revealed.
- Godot nodes, textures, meshes, shaders, and camera state remain disposable presentation caches and never enter saves or deterministic simulation.

## Work Guidance

- Keep map math in `MapPresentationGeometry`, media retention in `MapTextureCache`, drawing/input in `ClassicMapPresenter`, and first-person mesh construction under `dungeon/`.
- Edit the Search and Torch control scripts here when changing their source-backed animation or bitmap composition; keep command admission and gameplay effects outside presentation.
- Preserve native Classic pixels and the existing retained-update performance boundary when changing composition.

## Verification

- Run `tests/presentation/test_dungeon_geometry_projection.gd`, the presentation shell/system suites, and `tools/dungeon_transition_performance_probe.gd` after first-person changes.
- Run the rendered movement probe after changing retained map updates, camera movement, or texture/layer ownership.

## Child DOX Index
