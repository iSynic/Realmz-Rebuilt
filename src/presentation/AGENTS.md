# Godot presentation contract

## Purpose

Own scenes, controls, screen presenters, topology-derived rendering caches, animation, audio, and accessibility settings.

## Ownership

- Classic-wide 2D shell and optional topology-derived 3D dungeon presenter.
- Translation of user input to typed intents/responses.
- `InteractionPresenter` is the dedicated Classic interaction layer. It owns modal/request identity and delegates text/choice, selection, encounter, shop, temple, bank, battle, and one-item recovery controls to typed components that emit only the selected payload.
- Consumption of `GameView`, domain events, and interaction requests.
- `ClassicMapPresenter` rendering of map, minimap, and debug facts from detached map/cell views.
- `DungeonGeometryProjection` and `DungeonMap3DPresenter` derive floor, wall, door, secret, stair, and column geometry from the same detached topology view as 2D.
- `ClassicAudioPresenter` owns package-media playback.
- Picture and sound presenters resolve exact Classic resource type/ID pairs and expose developer-only resolution diagnostics with the package asset, hash, and decoder outcome. They never search by numeric ID alone.
- `ClassicApplicationShell` is the sole scene-backed application composition. It owns the compact menu, map/picture stage boundary, right roster, bottom narrative/status well, and contextual command deck. `ClassicScreenRouter` owns scene-backed Classic workspaces; it may retain presentation selection/focus/filter state but it cannot mutate `GameSession`.
- `UiRouteCatalog` is the single route, label, shortcut, and workspace-scene registry. `ClassicCommandCatalog` is the single command/asset/action/context/availability/focus registry. `UiLayoutProfile` owns Compact, Standard, and Wide geometry after interface density is applied.
- `ClassicUiAssetCatalog` owns imported app-control lookup and keeps those controls separate from package media.
- The party-setup workspace is campaign-aware: Race is the left-hand driver, available classes are filtered from typed eligibility facts, and exactly one of the five creator stages—Identity, Race & Class, Appearance, Review, or Spells—is mounted at a time. Review renders the core-generated provisional character; Spells renders only typed core options and costs. Media choices remain explicit package data, never guessed filesystem paths.
- Identity exposes level one and an exact disabled explanation for higher starting levels until the complete Classic level-up construction path exists. Presentation may not hide that missing workflow or synthesize advanced characters. Reroll and acceptance emit typed intents; the unspent-spell confirmation is a session-owned interaction, not a local dialog shortcut.
- Finalized and imported setup members render only from `GameView`; Add, Remove, and Begin emit typed intents. The presenter does not retain a parallel party array or infer that a committed setup edit has begun the adventure.
- Cosmetic-only animation and randomness.

## Local Contracts

- Presentation never mutates gameplay state directly.
- Animation completion never advances simulation; only genuine interaction responses resume it.
- While an interaction is pending, exploration controls remain disabled and the presenter cannot bypass the session response path.
- Full-window structural Controls such as `ClassicApplicationShell` and `ClassicScreenRouter` use `MOUSE_FILTER_IGNORE`; only concrete controls and modal surfaces participate in pointer hit testing. Scene-tree order, not visual `z_index`, owns pointer priority: router modals follow the roster/textbox within the shell, and `InteractionPresenter` follows the shell at the application root.
- The campaign selector presents one row per campaign. Immutable package revisions are installation details, not separate campaigns; older files remain available for explicit opening and diagnostics.
- TileMap layers, collisions, AStar structures, meshes, minimap textures, and other caches are disposable derivatives of `GameView` facts produced from topology plus overlays.
- The 2D exploration viewport is clipped to its center panel and party-centered with edge clamping. Its camera rectangle never exceeds the detached 25×25 projection and remains centered within larger stages, so movement scrolls map contents inside a fixed viewport instead of moving that viewport across the shell. Land atlases render at their native 32×32 cell size from each detached cell's `tileset_id` and `render_tile`; a cell's optional Classic special-land image renders above that base tile. Dungeon composition uses the same detached feature and edge facts as the topology views.
- Ordinary land travel draws exact built-in Classic CICN 186, the right-facing mounted party image, at its native 32×32 map-cell size without directional-arrow decoration. The abstract yellow ring is permitted only when that verified app-owned asset fails to load; opposite-facing, boat, camp, and base-scale tactical variants require their own proven assets before use.
- Normal play never paints topology grid lines, AP markers, random-rectangle bounds, or abstract land edges over Classic art. Those remain opt-in debug facts. Land click/hold movement uses Castle's independent horizontal/vertical pointer regions for eight directions; dungeon clicks remain cardinal. Both emit typed movement intent only.
- Switching between 2D and 3D changes only presentation settings. It cannot create collision, movement, LOS, discovery, or door state.
- Presentation and accessibility settings cannot change rules.
- Realmz 2 has one visual system. Verified base-game command bitmaps are app chrome and retain exact pixels at 1x/2x; scenario CICNs, portraits, pictures, sounds, and map art remain package content. Both use nearest-neighbor sampling where applicable and never share an ambiguous lookup. Slate backgrounds and frame centers use the manifest-backed seamless tile at native scale with repeat enabled; responsive containers crop or tile it and never stretch it.
- Interface density and text scale are independent. The window minimum is 800x600; larger settings stack, wrap, or scroll and do not fractionally scale Classic map/content art.
- Unidentified item views expose only player-knowable names and details. Presentation never reveals identified descriptions, values, curse relationships, or other hidden definition facts.
- Screen workspaces live inside clipped vertical scroll surfaces so long inventories, service actions, and accessibility-scaled text remain reachable. Interactions occupy the stage or bottom textbox region according to request kind; there is no floating desktop modal or persistent Chronicle column.
- Campaign selection and party setup use the already aligned root stone as one full-stage surface. They suppress the map frame, play textbox, and command deck until an active workspace returns, avoiding a second texture origin, structural seams, or overlapping play controls.
- Spatial map and dungeon presenters follow that same play-stage visibility boundary. They remain hidden beneath campaign selection and party setup even when Explore is still the active route.
- A positive Classic message replaces the complete bottom narrative region with an explicit Continue response. It uses the shell's exact bounds and open-right frame variation; inset layering may not expose the underlying textbox or command-deck corners. That surface has no redundant "Classic Textbox" heading or stage-modal minimum size. A negative Classic message uses the same narrative surface without introducing an interaction and remains until the next committed step, matching Castle's no-click path. Textbox history excludes internal event names and sound/picture request diagnostics.
- A live age-band change uses the inset `Age Update` component, not the Chronicle or Classic textbox. The component renders only typed character/race, resulting band/range, and fifteen-delta payload facts; each current request has one Continue response and independently presents sound 3002.
- Post-battle fumbled-item recovery uses a typed `treasure_distribution` stage component after body count. It displays exact remaining charges and rules-owned recipient availability, then emits assign or leave-behind without mutating inventory directly.
- The battle action component renders the session-owned melee/missile mode. It emits the no-cost typed switch response, never offers melee target buttons in missile mode, and labels each rules-owned legal projectile target as Fire. Unsupported or unavailable Fire remains visible with the request's exact reason.
- Scenario-picture overlays place a native-scale repeating stone backing under the complete raised bevel. Transparent frame pixels may never expose the map between the surface and bevel.
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
