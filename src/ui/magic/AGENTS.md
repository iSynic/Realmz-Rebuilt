# Magic UI contract

## Purpose

- Own the editable field-spellbook route, its reusable workspace, and presentation-only spell formatting.

## Ownership

- `spells_screen.tscn` owns the route sidebar, footer, context actions, and persistent Back control.
- `spells_workspace.tscn` owns the reusable ordinary and Encounter spellbook hierarchy.
- `fast_spell_row.tscn`, `spell_scroll_slot_row.tscn`, and `spell_action_dock.tscn` own stable repeated or contextual records.
- `SpellsScreenController` binds detached spell views and emits typed spell intents.
- `SpellDetailFormatter` owns pure display text for supplied spell facts.
- `ClassicSpellSelectionChrome` owns the reusable level rail, filtered list, and spell-selection binding shared with creation and Level Up.
- The neighboring Classic level, heading, selection-button, target-badge, and effect-preview scenes own the stable reusable spell-selection visuals consumed by Magic, setup, combat, and shared request surfaces.

## Local Contracts

- The field Spells route remains a persistent right sidebar: 420 pixels in the canonical composition and 288 pixels in the optional Classic composition.
- Cast, Make Scroll, and Back remain in the fixed route action strip, outside scrolling content.
- Encounter spell selection reuses `spells_workspace.tscn`; it must not maintain a second layout hierarchy.
- `Fast Spells (1-0)` exposes ten character-owned bindings with separate Clear actions. Scroll Case remains a separate record and action surface.
- The controller may format supplied scaling, target, resistance, save, cost, and availability facts. It never infers legal powers, targets, effects, costs, or resource identities.
- Stable hierarchy belongs in `.tscn` scenes. Variable records instantiate only exported row or action scenes.

## Work Guidance

- Keep presentation selection and filtering local to the retained workspace.
- Keep rule calculations, spell legality, target validation, and resource consumption in game and playthrough code.

## Verification

- Exercise the ordinary route, Encounter selection, Fast Spell assignment, Scroll Case actions, field casting, and Wide/Compact Realmz Builder previews.
- Run `tools/verify.ps1` before committing a workflow.

## Child DOX Index
