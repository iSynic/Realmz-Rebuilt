# Godot presentation contract

## Purpose

Own scenes, controls, screen presenters, topology-derived rendering caches, animation, audio, and accessibility settings.

## Ownership

- Classic-first 2D shell and optional topology-derived 3D dungeon presenter.
- Translation of user input to typed intents/responses.
- `InteractionPresenter` renders serializable requests and emits only a typed response carrying the matching request ID.
- Consumption of `GameView`, domain events, and interaction requests.
- `ClassicMapPresenter` rendering of map, minimap, and debug facts from detached map/cell views.
- `DungeonGeometryProjection` and `DungeonMap3DPresenter` derive floor, wall, door, secret, stair, and column geometry from the same detached topology view as 2D.
- `ClassicShellPresenter` campaign/party/character/inventory/spell/settings/save surfaces and `ClassicAudioPresenter` package-media playback.
- `ClassicApplicationShell` is the scene-backed composition for the application. `ClassicScreenRouter` owns navigable Classic-shaped workspaces and a typed-fixture gallery; it may retain presentation selection state but it cannot mutate `GameSession`.
- The party-setup workspace is campaign-aware: Race is the left-hand driver, available classes are filtered from typed eligibility facts, and the five creator stages are visible as Identity, Race & Class, Appearance, Review, and Spells. Media choices remain explicit package data, never guessed filesystem paths.
- Cosmetic-only animation and randomness.

## Local Contracts

- Presentation never mutates gameplay state directly.
- Animation completion never advances simulation; only genuine interaction responses resume it.
- While an interaction is pending, exploration controls remain disabled and the presenter cannot bypass the session response path.
- The campaign selector presents one row per campaign. Immutable package revisions are installation details, not separate campaigns; older files remain available for explicit opening and diagnostics.
- TileMap layers, collisions, AStar structures, meshes, minimap textures, and other caches are disposable derivatives of `GameView` facts produced from topology plus overlays.
- The 2D exploration viewport is clipped to its center panel and party-centered with edge clamping. Land atlases render at their native 32×32 cell size from each detached cell's `tileset_id` and `render_tile`; a cell's optional Classic special-land image renders above that base tile. Dungeon composition uses the same detached feature and edge facts as the topology views.
- Normal play never paints topology grid lines, AP markers, random-rectangle bounds, or abstract land edges over Classic art. Those remain opt-in debug facts. Cardinal cues and click/hold movement report the session-provided topology probe and emit typed movement intent only.
- Switching between 2D and 3D changes only presentation settings. It cannot create collision, movement, LOS, discovery, or door state.
- Presentation and accessibility settings cannot change rules.
- A positive Classic message is rendered by `InteractionPresenter` as a dedicated textbox with an explicit Continue response. A negative Classic message uses the same textbox without introducing an interaction and remains until the next committed step, matching Castle's no-click path. Chronicle may retain player-facing message history, but it excludes internal event names and sound/picture request diagnostics.
- Classic sound playback rotates across four presentation-owned channels. Positive sound requests may overlap; a negative request waits for that channel's completion before the presenter drains later sound events, without introducing a simulation wait.
- Cosmetic RNG cannot enter saves, replays, oracle traces, or simulation decisions.

## Work Guidance

- Put tweakable visual values in scene/inspector properties.
- Use MCP to inspect scene trees, properties, errors, runtime state, interactions, and screenshots.

## Verification

- Playable slices follow: open/build scene, inspect editor errors, play scene, run input/test scenario, inspect runtime, capture screenshots, stop scene.
- Runtime MCP tools must never run before `play_scene`.

## Child DOX Index

- No child AGENTS.md files are currently required.
