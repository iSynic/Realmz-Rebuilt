# Human-maintainability architecture record

The architecture migration has reached its structural target. Realmz Rebuilt now has six product-facing source boundaries, feature-owned files, scene-authored stable UI, narrow public interfaces, local feature guides, and machine-checked size and ownership limits. The remaining Beta 1 work is acceptance of that structure by an unfamiliar maintainer plus ordinary-play, performance, native-platform, and hosted-release evidence.

Current ownership is indexed in [the system manifest](system-manifest.json). New contributors should begin with [The Realmz Rebuilt Builder's Manual](builders-manual.md) and the nearest feature `README.md`.

## Source boundaries

| Boundary | Owns | Does not own |
|---|---|---|
| `src/app` | Startup, navigation, session hosting, platform lifecycle, dependency composition | Realmz rules or screen layout |
| `src/game` | Immutable definitions, mutable state, fixed rules, topology, RNG, detached views | Nodes, files, audio, or host services |
| `src/playthrough` | `GameSession`, transactions, workflows, continuations, restore coordination | Presentation or filesystem access |
| `src/scenarios` | Classic instruction execution, Safe Scenario Actions, runtime operations, VM scheduling | Host UI or package I/O |
| `src/storage` | Packages, saves, Character Files, settings, validation, external bytes | Gameplay decisions or screen behavior |
| `src/ui` | Scenes, controllers, renderers, animation, audio, themes, editor previews | Mutable gameplay truth or direct persistence |

Dependencies point toward the model:

```text
game <- scenarios <- playthrough <- app
game/playthrough/scenarios <- storage <- app
game/playthrough <- ui <- app
```

The architecture verifier rejects dependency reversals, cross-object private calls, storage objects in presentation, gameplay state in Nodes, and alternate command or interaction buses.

## Feature layout

- `game`: `characters`, `inventory`, `magic`, `economy`, `world`, `combat`, `scenario`, `shared`
- `playthrough`: the matching feature workflows plus `session`
- `ui`: `shell`, `exploration`, `combat`, `characters`, `inventory`, `magic`, `services`, `journal`, `setup`, `shared`
- `storage`: `packages`, `saves`, `characters`, `settings`
- `scenarios`: `classic`, `actions`, `runtime`, `vm`
- `app`: `startup`, `navigation`, `session`, `platform`, `composition`

Every directory above exists, contains a public `README.md`, and is declared in `system-manifest.json`. Production files do not sit loose at a boundary root. A move or rename includes its paired Godot UID, resource references, tests, guides, and manifest entry in one change; no compatibility aliases remain.

## Naming and ownership

Names describe roles rather than implementation history:

- `Definition`: immutable authored content
- `State`: mutable playthrough truth
- `View`: detached presentation data
- `Rules`: pure calculation
- `Workflow`: resumable playthrough operation
- `Controller`: one scene's signal and data binding
- `Presenter`: algorithmic or custom rendering
- `Repository`: persistence or external I/O
- `Codec` or `Decoder`: strict wire conversion
- `Catalog`: indexed immutable records

`Classic` is reserved for source-backed Castle behavior, media, or evidence. Product shells, screens, navigation, and components use ordinary product names. Serialized package, save, Character Files, resource, opcode, and user-directory identities remain stable even when internal source names move.

## Runtime interfaces

`GameSession` is the public transaction boundary: start, restore, submit intent, respond, view, snapshot, and close. One `SessionContext` owns content, mutable state, deterministic RNG, rules, VM/action state, continuations, pending interaction, and revision. Feature workflows receive that context by reference and report named results; they do not copy coordinator state or call another object's private methods.

Player intents live beside their feature workflows. Character, combat, economy, and scenario request bodies live beside their game models. The common `PlayerIntent`, `InteractionRequest`, `InteractionResponse`, and `SessionContinuation` envelopes retain stable kind/version/data wire shapes; small registries and strict feature decoders reject unknown or mismatched payloads before mutation or restore.

Combat shares one explicit `CombatContext`. Round, action, reaction, magic, field, summoning, navigation, automation, and event collaborators own cohesive public operations rather than forwarding through a giant facade. Deterministic simulation remains in pure objects; Nodes own lifecycle, signals, timers, input, and presentation only.

## Godot authoring model

`src/ui/shell/game_shell.tscn` is the recognizable persistent Realmz HUD. It contains the stage, roster, narrative/status well, command regions, effects, and interaction hosts. Exploration and Combat are typed shell modes, not placeholder workspace scenes.

Major workspaces author their stable panels, splits, tabs, headings, buttons, details, empty/error states, and command regions in `.tscn` files. A controller binds detached values, toggles modes, connects signals, and instantiates only exported variable row/card scenes. Routes and frequently updated surfaces are retained; movement, projection, battlefield, animation, and media caches are not rebuilt per frame.

Algorithmic map, battlefield, and first-person dungeon geometry remains code-owned. Their viewport, camera, layers, materials, masks, and surrounding controls remain scene-owned. The only reviewed runtime `Control` allocations are two named render-target operations; no route, screen, interaction, or controller constructs stable layout.

Realmz Builder is an export-excluded editor plugin. It binds production scenes and controllers to representative Wide, Compact, Empty, Long Content, Unavailable, and Error data without saving preview children. Its registry links each major scene to its guide, controller, detached view, and tests.

## Enforced limits

The architecture-overhaul gate currently reports zero for every target:

- production files over 600 substantive lines;
- functions over 60 substantive lines;
- classes over 40 total methods or 20 public methods;
- cross-object private calls;
- generic `Type` or `Script` preload aliases;
- major UI surfaces without scenes or production-bound previews;
- one-node shell-mode marker scenes;
- missing or undeclared feature directories;
- production files loose at a source-boundary root.

The companion maintainability gate rejects compressed statement lines, missing production purpose headers, unclassified stable `Control.new()` construction, stale classifications, class/file naming mismatches, and obsolete route scenes. Test source remains capped at 20 percent of production source, and individual test suites remain capped at 1,200 substantive lines.

## Verified baseline

- Godot 4.7.1 import and main-scene smoke pass.
- All 4,030 assertions across 28 suites pass.
- Realmz Builder passes 313 production-bound preview assertions.
- The 148-frame Wide/Compact gallery has passed the current visual audit.
- Package, save, export, media, schema, provenance, bundled-scenario, differential, workflow-inventory, and gameplay-parity validators pass.
- A tracked-files-only clean checkout passes first import, startup, the complete suite, and all previews.
- A local sanitized one-root Git/LFS repository and separate clone pass; a Windows export has been inspected and smoke-launched.
- Path-only ownership moves preserved runtime behavior and added no per-frame, simulation, RNG, save, or package-loading work.

## Remaining acceptance

Structural completion does not certify the release. Before Beta 1:

1. An unfamiliar contributor must complete the six hint-free journeys in `maintainer-acceptance.md`; every folklore dependency is repaired.
2. Ordinary release-candidate play must cover Assault on Giant Mountain, War in the Sword Lands, and City of Bywater across the required exploration, dungeon, combat, workspace, save, and restore paths.
3. Final warmed performance probes must remain within both relative and absolute budgets.
4. The exact candidate must build and launch on Windows, Linux, and real macOS runners.
5. The actual GitHub Git/LFS clone and Download ZIP must materialize valid packages.
6. The owner must review and manually publish the draft prerelease.

These are evidence gates, not opportunities to weaken the architecture. Any failure returns to the owning feature, scene, guide, or workflow and is repaired before release.
