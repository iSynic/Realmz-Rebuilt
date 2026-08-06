# Godot presentation contract

## Purpose

Own scenes, controls, screen presenters, topology-derived rendering caches, animation, audio, and accessibility settings.

## Ownership

- Classic-first 2D shell and optional later 3D dungeon presenter.
- Translation of user input to typed intents/responses.
- `InteractionPresenter` renders serializable requests and emits only a typed response carrying the matching request ID.
- Consumption of `GameView`, domain events, and interaction requests.
- `ClassicMapPresenter` rendering of map, minimap, and debug facts from detached map/cell views.
- Cosmetic-only animation and randomness.

## Local Contracts

- Presentation never mutates gameplay state directly.
- Animation completion never advances simulation; only genuine interaction responses resume it.
- While an interaction is pending, exploration controls remain disabled and the presenter cannot bypass the session response path.
- TileMap layers, collisions, AStar structures, meshes, minimap textures, and other caches are disposable derivatives of `GameView` facts produced from topology plus overlays.
- Presentation and accessibility settings cannot change rules.
- Cosmetic RNG cannot enter saves, replays, oracle traces, or simulation decisions.

## Work Guidance

- Put tweakable visual values in scene/inspector properties.
- Use MCP to inspect scene trees, properties, errors, runtime state, interactions, and screenshots.

## Verification

- Playable slices follow: open/build scene, inspect editor errors, play scene, run input/test scenario, inspect runtime, capture screenshots, stop scene.
- Runtime MCP tools must never run before `play_scene`.

## Child DOX Index

- No child AGENTS.md files are currently required.
