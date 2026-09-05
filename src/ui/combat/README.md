# Combat interface

This folder contains the complete Godot-facing combat presentation: the retained battlefield, command deck, initiative, targeting, roster spellbook, Fast Spell dock, and committed-event playback. Stable controls live in scenes; deterministic battle rules remain in `src/game/combat` and `src/playthrough/combat`.

## Where to start

- `battle_interaction.tscn`: the full-width command deck, initiative, inspection, spell/item modes, and targeting confirmation.
- `battle_interaction.gd`: request binding, presentation modes, and typed command responses.
- `classic_battlefield_presenter.gd`: algorithmic terrain, combatant, field, targeting, and playback drawing.
- `battlefield_interaction_controller.gd`: pointer/keyboard projection, inspection focus, Reveal Friends, and movement-cost aid.
- `combat_interaction_controller.gd`: coordination between the active request, deck, battlefield, roster spellbook, and Fast Spell dock.
- `combat_roster_spellbook.tscn`: memorized-spell selection in the persistent party rail.
- `fast_spell_dock.tscn`: transient Alt-held spell shortcuts.

Initiative records, power choices, targeting controls, and dock slots are neighboring editable scenes exported by their parent.

## Data flow

```text
GameSession -> detached CombatView + BattleInteraction request
            -> CombatInteractionController
            -> battlefield presenter + authored command scenes
            -> typed InteractionResponse
            -> committed combat events
            -> CombatPlaybackController
```

The interface owns hover, focus, camera framing, selection order, local rotation, and animation timing. The request/session owns legality, paths, range, LOS, targets, costs, effects, RNG, and mutation.

## Invariants

- Every command and target comes from the active typed request.
- Spatial input is projected through the same transform that rendered the battlefield.
- Target cancellation emits no gameplay response; confirmation preserves stable identities, coordinates, order, and rotation.
- The command deck and roster spellbook expose visible return paths in both Wide and Compact profiles.
- Battlefield nodes, media, and geometry are retained across ordinary updates and playback frames.

## Performance

Battlefield textures, geometry policy, and actor-centered camera state are cached. Playback updates retained nodes; it does not rebuild the board. Command scenes rebind the current request at activation boundaries and never instantiate per rendered frame.

## Tests and preview

Realmz Builder covers the combat command deck and supporting surfaces across all six preview profiles. Behavioral coverage lives in the combat-flow, battlefield-navigation, Classic UI system, and Builder preview suites. Use `tools/combat_performance_probe.gd` after changing battlefield construction or playback preparation; `tools/verify.ps1` is the aggregate gate.
