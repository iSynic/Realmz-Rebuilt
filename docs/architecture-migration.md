# Human-maintainability architecture record

The foundational reorganization is complete. Realmz Rebuilt now presents six human-facing source areas, scene-authored route layouts, responsibility-sized coordinators, enforceable readability budgets, and a newcomer guide that describes the running repository. The game remained importable and testable throughout the work; serialized IDs, package and save formats, deterministic behavior, and the stable `RealmzRemake2` user directory did not change.

This record preserves the acceptance boundary and the remaining cleanup ratchets. The current architectural guide is [The Realmz Rebuilt Builder's Manual](builders-manual.md).

## The six source areas

| Area | Owns | Must not own |
|---|---|---|
| `src/app` | Startup, dependency construction, host lifecycle, and input translation | Realmz rules or screen layout |
| `src/game` | Pure definitions, mutable state, fixed rules, topology, clock, RNG, and detached views | Nodes, files, audio, or platform services |
| `src/playthrough` | `GameSession`, transactions, continuations, restore coordination, and player workflows | Presentation or filesystem access |
| `src/scenarios` | Classic instruction execution, Safe Scenario Actions, and the scenario VM | Host UI or package I/O |
| `src/storage` | Package loading, saves, Character Files, settings, validation, and external adapters | Gameplay decisions or screen behavior |
| `src/ui` | Scenes, screens, dialogs, components, rendering, animation, audio, and themes | Mutable game truth or direct storage access |

Dependencies point toward the model and command boundary:

```text
game <- scenarios <- playthrough <- app
game/playthrough/scenarios <- storage <- app
game/playthrough <- ui <- app
```

The architecture verifier enforces these directions and the typed boundaries between them. A later move includes its scripts, paired `.uid` files, resource paths, tests, verification rules, and DOX ownership contract in one coherent change.

## What changed

- Internal source moved from framework-shaped `core`, `session`, `scenario`, `infrastructure`, and `presentation` folders into the six product-facing areas above.
- Stable routes gained named `*_screen.tscn` scenes. Inventory, Character, Allies, Bestiary, Maps/Notes, Money and services, Spells, System, and Character Files now expose their durable regions in the Godot editor.
- Exploration and Combat remain explicit route markers because their persistent visible structure is already authored once in `game_shell.tscn`; duplicating decorative controls in their route scenes would make the editor lie.
- `ScreenNavigator` owns navigation and mounting. Named screen controllers bind detached views and populate genuinely variable collections.
- Large session, combat, application, interaction, and shell scripts were divided by responsibility behind typed collaborators. No production GDScript file exceeds 800 substantive lines and no function exceeds 100.
- The obsolete `ClassicWorkspaceView` mounting-point scene was removed. Product files use screen, panel, dialog, row, card, canvas, renderer, definition, state, rules, repository, loader, decoder, result, and flow according to their actual role.
- Every internal rename was decisive. Stable wire identities—including `.realmz2`, `.r2save`, `.r2char`, package keys, opcode identities, save fields, and the user-data directory—were intentionally preserved.

## Scene and script agreement

Stable layout belongs in `.tscn`. Scripts bind data, respond to input, coordinate behavior, and build only variable collections. Repeated rows and cards should become small `PackedScene` components when their structure is stable enough to edit visually.

Custom map, battlefield, first-person dungeon, animation, and effect drawing remain valid script-owned exceptions because their structure is algorithmic. A route-marker scene is also valid when the route reuses an already-authored persistent shell region. Both exceptions are explicit in verification.

## Readability budgets

The repository now rejects:

- production scripts over 800 substantive lines;
- functions over 100 substantive lines;
- test suites over 1,200 substantive lines;
- a regression in the measured test-line ratchet or test-to-production ratio;
- growth in compressed statement lines, runtime-created ordinary controls, or production scripts lacking a purpose header;
- class/file-name mismatches and unapproved one-node route scenes.

The structural caps are complete and have no grandfather list. Three older local debts remain ratcheted rather than hidden: 276 compressed-statement lines, 825 runtime control constructions, and 362 scripts without purpose headers at this checkpoint. New work may reduce those numbers, never increase them. Runtime-created controls are not automatically defects—dynamic rows and algorithmic renderers are legitimate—but each accepted exception should become clearer as the ratchet approaches zero.

## Acceptance trail

A newcomer can now use names and the Builder's Manual to locate a character record, fatigue rule, inventory layout, opcode handler, package loader, and save serializer, then follow a command from host input through `GameSession` to a detached view and screen. Focused behavior suites, Godot import, architecture verification, the human-maintainability ratchet, and the hotspot/test budget protect that trail.

Further readability work is ordinary maintenance, not another repository-wide migration: choose one cohesive feature, replace nearby compressed syntax or unnecessary runtime layout while working there, lower the checked-in budget, and leave the owning scene and documentation more legible than before.
