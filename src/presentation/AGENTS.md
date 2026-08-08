# Godot presentation contract

## Purpose

Own scenes, controls, screen presenters, topology-derived rendering caches, animation, audio, and accessibility settings.

## Ownership

- Classic-wide 2D shell and optional topology-derived 3D dungeon presenter.
- Translation of user input to typed intents/responses.
- `InteractionPresenter` is the dedicated Classic interaction layer. It owns modal/request identity and delegates text/choice, selection, encounter, shop, temple, bank, and battle controls to typed components that emit only the selected payload.
- Consumption of `GameView`, domain events, and interaction requests.
- `ClassicMapPresenter` rendering of map, minimap, and debug facts from detached map/cell views.
- `DungeonGeometryProjection` and `DungeonMap3DPresenter` derive floor, wall, door, secret, stair, and column geometry from the same detached topology view as 2D.
- `ClassicAudioPresenter` owns package-media playback.
- `ClassicApplicationShell` is the sole scene-backed application composition. It owns the compact menu, map/picture stage boundary, right roster, bottom narrative/status well, and contextual command deck. `ClassicScreenRouter` owns scene-backed Classic workspaces; it may retain presentation selection/focus/filter state but it cannot mutate `GameSession`.
- `UiRouteCatalog` is the single route, label, shortcut, and workspace-scene registry. `ClassicCommandCatalog` is the single command/asset/action/context/availability/focus registry. `UiLayoutProfile` owns Compact, Standard, and Wide geometry after interface density is applied.
- `ClassicUiAssetCatalog` owns imported app-control lookup and keeps those controls separate from package media.
- The party-setup workspace is campaign-aware: Race is the left-hand driver, available classes are filtered from typed eligibility facts, and the five creator stages are visible as Identity, Race & Class, Appearance, Review, and Spells. Media choices remain explicit package data, never guessed filesystem paths.
- Cosmetic-only animation and randomness.

## Local Contracts

- Presentation never mutates gameplay state directly.
- Animation completion never advances simulation; only genuine interaction responses resume it.
- While an interaction is pending, exploration controls remain disabled and the presenter cannot bypass the session response path.
- Full-window structural Controls such as `ClassicApplicationShell` and `ClassicScreenRouter` use `MOUSE_FILTER_IGNORE`; only concrete controls and modal surfaces participate in pointer hit testing. Scene-tree order, not visual `z_index`, owns pointer priority: router modals follow the roster/textbox within the shell, and `InteractionPresenter` follows the shell at the application root.
- The campaign selector presents one row per campaign. Immutable package revisions are installation details, not separate campaigns; older files remain available for explicit opening and diagnostics.
- TileMap layers, collisions, AStar structures, meshes, minimap textures, and other caches are disposable derivatives of `GameView` facts produced from topology plus overlays.
- The 2D exploration viewport is clipped to its center panel and party-centered with edge clamping. Its camera rectangle never exceeds the detached 25×25 projection and remains centered within larger stages, so movement scrolls map contents inside a fixed viewport instead of moving that viewport across the shell. Land atlases render at their native 32×32 cell size from each detached cell's `tileset_id` and `render_tile`; a cell's optional Classic special-land image renders above that base tile. Dungeon composition uses the same detached feature and edge facts as the topology views.
- Normal play never paints topology grid lines, AP markers, random-rectangle bounds, or abstract land edges over Classic art. Those remain opt-in debug facts. Cardinal cues and click/hold movement report the session-provided topology probe and emit typed movement intent only.
- Switching between 2D and 3D changes only presentation settings. It cannot create collision, movement, LOS, discovery, or door state.
- Presentation and accessibility settings cannot change rules.
- Realmz 2 has one visual system. Verified base-game command bitmaps are app chrome and retain exact pixels at 1x/2x; scenario CICNs, portraits, pictures, sounds, and map art remain package content. Both use nearest-neighbor sampling where applicable and never share an ambiguous lookup. Slate backgrounds and frame centers use the manifest-backed seamless tile at native scale with repeat enabled; responsive containers crop or tile it and never stretch it.
- Interface density and text scale are independent. The window minimum is 800x600; larger settings stack, wrap, or scroll and do not fractionally scale Classic map/content art.
- Unidentified item views expose only player-knowable names and details. Presentation never reveals identified descriptions, values, curse relationships, or other hidden definition facts.
- Screen workspaces live inside clipped vertical scroll surfaces so long inventories, service actions, and accessibility-scaled text remain reachable. Interactions occupy the stage or bottom textbox region according to request kind; there is no floating desktop modal or persistent Chronicle column.
- Campaign selection and party setup use the already aligned root stone as one full-stage surface. They suppress the map frame, play textbox, and command deck until an active workspace returns, avoiding a second texture origin, structural seams, or overlapping play controls.
- A positive Classic message is rendered in the bottom textbox region with an explicit Continue response. A negative Classic message uses the same narrative surface without introducing an interaction and remains until the next committed step, matching Castle's no-click path. Textbox history excludes internal event names and sound/picture request diagnostics.
- Classic opcode 3 carries button labels, not a question prompt. Its yes/no presenter keeps the latest source-authored Classic textbox message visible as context, while an explicit typed request prompt remains authoritative.
- Classic sound playback rotates across four presentation-owned channels. Positive sound requests may overlap; a negative request waits for that channel's completion before the presenter drains later sound events, without introducing a simulation wait.
- Cosmetic RNG cannot enter saves, replays, oracle traces, or simulation decisions.

## Work Guidance

- Put tweakable visual values in scene/inspector properties.
- Use MCP to inspect scene trees, properties, errors, runtime state, interactions, and screenshots.

## Verification

- Playable slices follow: open/build scene, inspect editor errors, play scene, run input/test scenario, inspect runtime, capture screenshots, stop scene.
- Runtime MCP tools must never run before `play_scene`.

## Child DOX Index

- `assets/AGENTS.md` owns presentation-owned chrome assets and provenance.
- `interaction_components/AGENTS.md` owns typed request-kind control surfaces and exact payload emission.
- `screens/AGENTS.md` owns scene-backed workspace layout, scrolling, and focus containment.
