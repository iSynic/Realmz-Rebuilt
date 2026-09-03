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
- Realmz Builder recognizes each existing major scene and links its guide, controller, detached view, and tests. Registration remains distinct from production-bound preview completion, so the 24-surface preview debt is still reported honestly.
- Campaign selection and the retained party-assembly/character-creation workspace now have editor-authored scenes under `src/ui/setup`; their controllers bind stable nodes and create only variable campaign and Character File records. This lowers missing major scenes from eight to five and runtime-created Controls from 664 to 629.
- Level Up now has one recognizable two-mode scene: committed gains and spell learning share the scene-authored header, with their complete stable pane structures visible in Godot. Only the level-filtered spell buttons remain dynamic, lowering missing major scenes to four and runtime-created Controls to 611.
- Complex Encounter now exposes its six-command dock in `encounter_interaction.tscn` and keeps its editable Action, Items, Spells, and Speak structures in neighboring workspace scenes. Its script selects and binds those scenes and creates only authored action records, lowering missing major scenes to three and runtime-created Controls to 587.
- Shop now exposes its wide two-ledger and compact tabbed browsers, five category controls, transaction strip, shopper selectors, route controls, and detail wells in `shop_interaction.tscn`. Item and portrait records are reusable scenes, lowering missing major scenes to two and runtime-created Controls to 549; the controller also falls below both the file-size and class-method limits.
- Treasure now exposes its ordinary distribution workspace, legacy exact-item recovery adapter, completion confirmation, wealth transfers, loot cells, recipient rows, and lore controls through editable scenes. Its controller binds detached request values and creates only scene instances, lowering missing major scenes to one and runtime-created Controls to 483; it also lowers the outstanding file, function, and class limits to 26, 99, and 36 respectively.
- Combat now exposes the complete turn summary, initiative host, View/Action/Tactics deck, fixed command slots, attack/spell/scroll/item/bandage modes, inspection record, and reusable targeting controls in `battle_interaction.tscn` and `battle_targeting_controls.tscn`. The controller binds supplied legality and detached records without constructing Controls, lowering missing major scenes to zero and runtime-created Controls to 442.
- Allies and Bestiary now share the fully authored `creature_library_workspace.tscn`: list and detail panes, identity header, facts, empty state, and three state cards are visible in Godot, while `creature_library_row.tscn` supplies the only variable record. Their controller only binds detached creature data and exact media, lowering runtime-created Controls to 417.
- The Character route exposes its party-order summary, reorder editor, persistent shared sheet, empty state, identity, complete tab rail, and content frame through authored scenes. Character Files likewise exposes its complete library, empty state, history, eligibility, and inspection composition; exported `party_order_row.tscn`, `vault_character_card.tscn`, and `vault_history_row.tscn` provide the variable records.
- Overview, Conditions & Saves, Abilities, and Lifetime Record now expose their complete stable sheet regions through `character_sheet_stat_tabs.tscn`. Metric rows and lifetime cards instantiate exported component scenes, lowering runtime-created Controls to 361; Equipment, Spells, Appearance, and Race/Caste/Aging remain the explicitly incomplete sheet tabs.
- Equipment and Spells expose their fixed headings, split records, list hosts, empty states, and scroll-case regions through `character_sheet_inventory_magic_tabs.tscn`. Exact item and spell records use exported card scenes.
- Appearance and Race, Class & Aging now expose their complete preview, picker, action, definition, and age-band structures through `character_sheet_identity_tabs.tscn`. All eight character-sheet tabs are therefore recognizable and editable in Godot; their controller binds detached values and instantiates only the exported metric, record, item, and spell components. This completes the character-sheet scene migration and lowers runtime-created Controls to 324.
- Inventory now shares one editor-authored `inventory_workspace.tscn` between its route and Encounter selection. Its normal split, empty state, character record and selector, seven-action dock, confirmation stage, item inspector, two-ledger Trade workspace, portrait matrix, and fixed Money/Items/Done spine are visible in Godot; only exported party, item, fact, and portrait record scenes vary at runtime. The controller constructs no Controls, lowering runtime-created Controls to 274 and the outstanding file/function limits to 25 and 95.
- `ScreenNavigator` owns navigation and mounting. Named screen controllers bind detached views and populate genuinely variable collections.
- Large session, combat, application, interaction, and shell scripts were divided once, but 26 files still exceed the final 600-line limit, 99 functions exceed 60 lines, and 36 top-level scripts exceed the final method-count limits.
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
