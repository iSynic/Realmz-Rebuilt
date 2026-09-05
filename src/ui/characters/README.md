# Character interface

This folder is the Godot-facing home of the Character, Allies, Bestiary, and Character Files workspaces. Open the scene for the surface you want to change; its stable panels, headings, actions, empty states, and responsive containers are authored there rather than assembled by its script.

## Where to start

- `character_screen.tscn`: the party Character route and Party Order editor.
- `classic_character_sheet.tscn`: the shared eight-tab character record used by Character, Character Files, party inspection, and creation review.
- `creature_library_workspace.tscn`: the shared Allies and Bestiary list-and-detail body.
- `vault_screen.tscn`: the Character Files library, history, and immutable inspection surface.
- `character_screen_controller.gd`: route-local character and vault selection, binding, and typed commands.
- `creature_library_screen_controller.gd`: read-only Allies and Bestiary binding.

Repeated records live in the neighboring row and card scenes. Parent scenes export those `PackedScene` dependencies, so their appearance remains editable and their instances can be reused without rebuilding a route.

## Data flow

```text
GameSession -> detached character/creature/vault views
            -> route controller
            -> authored workspace and exported row scenes
            -> typed intent or host action
```

The controllers preserve presentation-only selection, tabs, filtering, Party Order drafts, and appearance drafts. They never receive a repository or mutate game state. Character rules live in `src/game/characters`; Character Files persistence lives in `src/storage/characters`.

## Invariants

- Stable hierarchy belongs in `.tscn` files; scripts bind values, signals, visibility, and variable collections.
- Portrait and tactical-icon identities remain independent and exact.
- Item, spell, condition, eligibility, and creature facts come from detached views. The interface does not infer hidden rules.
- Character Files revisions remain immutable; importing creates the campaign-owned copy through the host/session boundary.
- Wide and Compact profiles use the same authored regions, with explicit stacking or scrolling where required.

## Performance

Routes and the shared character sheet are retained while active. Controllers replace or rebind variable rows and signal handlers instead of rebuilding the whole tree during selection changes. Exact media is resolved through the shared presentation catalog and keeps nearest-neighbor sampling.

## Tests and preview

Realmz Builder registers all four major scenes with Wide, Compact, empty, long-content, unavailable, and error profiles. Focused behavior lives in the Character, Allies/Bestiary, Character Files, Classic UI system, and Builder preview presentation suites. The aggregate release gate is `tools/verify.ps1`.
