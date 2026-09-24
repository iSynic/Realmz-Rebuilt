# Keyboard shortcuts

Turn on **Classic keyboard shortcuts** under Settings → Controls to use the context-sensitive letters from the Realmz Castle codebase. It is off by default because A, S, D, and W conflict with WASD movement. With Classic shortcuts on, move with the arrow keys or numeric keypad instead. Mouse and controller controls remain available.

| Context | Keys |
| --- | --- |
| Exploration | I Items, M Money, S Spells, T Trade, A Area Search, C Camp, H Heal, R Rest, E Encounter, G Shop/Temple |
| Spell workspaces | L opens Scroll Case from exploration; K opens known-spell choice, then K invokes an available Make Scroll action; Space chooses targets/casts; A aborts |
| Combat | W changes weapon action, S Spells, L Scrolls, I Items, A Auto Turn, G Guard, D Delay, B Bandage, U Undo, E Escape, F Finish |
| Combat view | C centers the active character, M centers the battlefield under the pointer, N/P select next/previous combatant, R reveals friends |
| Items | J Join, D Drop, C Identify, U Use, T Trade, Enter/Space Equip or Unequip |
| Shop | I Items, M Money, P Pool, S Share, Enter Done |
| Targeting | T selects the hovered target or cycles candidates; Space confirms; Escape or right-click cancels |

Shortcuts respect the same availability, costs, confirmations, and target rules as their visible controls. Holding an action key does not repeat the action. Text entry and modal dialogs keep keyboard ownership. Area and multiple-target spells still require selection and confirmation, even with Immediate Single-Target Actions enabled.

Fast Spell slots retain their existing 1–0 bindings; Ctrl/Command invokes the binding. Alt exposes the combat Fast Spell dock. F12 opens retail Diagnostics. Escape remains the safety hatch for party Auto and returns manual control at the next activation boundary.

These are fixed contextual shortcuts, not a new keyboard remapping editor. Castle's separate item-information window is unnecessary because item facts are already shown; identification uses Rebuilt's existing contextual control rather than a second paid-identification command. W enters the dedicated weapon targeting action rather than reviving Castle's intermediate weapon workflow. Scroll creation is explicitly chosen from the spell workspace and retains ordinary camp, class, SP, and scroll-case requirements.

Implementation source references: the pinned Castle `checkkeypad.c`, `combat.c`, `items.c`, `choice.c`, and `getchoice.c`. This records source-backed mappings, not a new controlled Castle runtime comparison.
