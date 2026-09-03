# Human-maintainability architecture record

The first boundary reorganization is complete, but the human-centered architecture overhaul is not. Realmz Rebuilt has six sound source areas and a verified behavioral baseline; many systems inside those areas still retain prototype-sized scripts, forwarding surfaces, and runtime-built UI. Beta 1 remains blocked until the stricter acceptance targets in [Human-centered architecture overhaul](human-centered-architecture.md) reach zero and the Godot scenes are independently recognizable.

This record describes the foundation inherited by the active migration. Current ownership is machine-checked in [the system manifest](system-manifest.json), and the newcomer tour remains [The Realmz Rebuilt Builder's Manual](builders-manual.md).

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

## Foundation already in place

- Internal source moved from framework-shaped `core`, `session`, `scenario`, `infrastructure`, and `presentation` folders into the six product-facing areas above.
- Major routes gained named `*_screen.tscn` scenes, but several expose only a frame or mounting regions. They are migration anchors, not evidence that the complete runtime composition is editor-authored.
- Reusable inventory regions, party-setup rows, Fast Spell controls, exchange controls, Debug Tools, the action console, music playlist, shared content and spell visuals, scrolling text, player maps, Pick Lock, Age Update, lifecycle and text choices, Bank, Temple, and Thief workspaces now have editable scenes. Request-sized item, spell, character, statistic, transfer, service, and tumbler records use reusable row scenes.
- Exploration and Combat are typed shell modes and no longer have placeholder scenes. Their persistent visible structure remains authored once in `game_shell.tscn`.
- `ScreenNavigator` owns navigation and mounting. Named screen controllers bind detached views and populate genuinely variable collections.
- Large session, combat, application, interaction, and shell scripts were divided once, but 28 files still exceed the final 600-line limit, 103 functions exceed 60 lines, and 38 top-level scripts exceed the final method-count limits.
- The obsolete `ClassicWorkspaceView` mounting-point scene was removed. Product files use screen, panel, dialog, row, card, canvas, renderer, definition, state, rules, repository, loader, decoder, result, and flow according to their actual role.
- Every internal rename was decisive. Stable wire identities—including `.realmz2`, `.r2save`, `.r2char`, package keys, opcode identities, save fields, and the user-data directory—were intentionally preserved.

## Scene and script agreement

Stable layout belongs in `.tscn`. Scripts bind data, respond to input, coordinate behavior, and build only variable collections. Repeated rows and cards should become small `PackedScene` components when their structure is stable enough to edit visually.

Custom map, battlefield, first-person dungeon, animation, and effect drawing remain valid script-owned exceptions because their structure is algorithmic. Their viewport, cameras, layers, materials, masks, and surrounding controls still belong in scenes. Shell modes are typed resources rather than duplicate or placeholder scenes.

## Readability budgets

The repository rejects growth from the verified baseline and is converging on stricter final limits:

- final production scripts over 600 substantive lines;
- final functions over 60 substantive lines;
- final classes over 40 total or 20 public methods;
- test suites over 1,200 substantive lines;
- a regression in the measured test-line ratchet or test-to-production ratio;
- any compressed statement line or production script without a purpose header;
- any runtime-created ordinary control outside an exact reviewed function classification, any stale classification, or any per-owner count change that has not been reviewed;
- class/file-name mismatches and unapproved one-node route scenes.

The former 800/100 caps and 664-call construction inventory remain useful no-growth guards during migration, but they are not final acceptance. `verify_architecture_overhaul.ps1` separately ratchets the 600/60/method limits, cross-object private calls, generic preload aliases, missing major scenes, missing preview registrations, and one-node shell-mode markers toward zero. A converted UI collection instantiates an exported row scene; only named algorithmic renderers retain code-created rendering nodes.

## Acceptance trail

The final acceptance exercise requires a newcomer to locate and explain fatigue movement, character state, portable item resolution, one scenario opcode, Inventory layout, and combat Auto flow without private guidance. That exercise has not yet passed. Each migration batch must lower its checked-in ceilings and leave source, scene, guide, tests, and system-manifest ownership in agreement.
