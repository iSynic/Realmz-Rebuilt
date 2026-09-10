# Combat presentation contract

## Purpose

Own the retained tactical battlefield, combat command deck, roster spellbook, Fast Spell dock, playback, and presentation-only targeting state.

## Ownership

- `ClassicBattlefieldPresenter` draws detached terrain, combatants, targets, fields, inspection aids, and playback frames.
- `BattlefieldPresentationGeometry` owns stateless viewport and coordinate calculations; `BattlefieldTextureCache` owns decoded tactical media reuse.
- `CombatPlaybackController` and `CombatPlaybackFrame` translate committed combat events into presentation timing and interpolation.
- `CombatTargetingRequest` and `CombatTargetingState` retain only the current presentation selection, hover, rotation, and inspection focus.
- `battle_interaction.tscn` owns the complete fixed command deck, initiative panel, secondary modes, targeting controls, and responsive Wide/Compact composition. `BattleInteraction` binds only request-supplied actions, targets, inspection facts, and typed responses.
- `BattlefieldInteractionController` translates tactical pointer and keyboard input through the exact rendered camera transform. `CombatInteractionController` coordinates the active battle request, command deck, targeting, roster spellbook, and Fast Spell dock without owning combat rules.
- `combat_roster_spellbook.tscn` owns the full-height memorized-spell chooser shown in the persistent party rail. `fast_spell_dock.tscn` owns the transient Alt-held shortcut surface. Both return the exact request-owned cast option through the normal command boundary.
- Battle initiative, spell-power, targeting, and Fast Spell collections instantiate only their exported row, button, or slot scenes.

## Local Contracts

- Combat legality, action cost, range, LOS, target relationships, movement paths, damage, and RNG remain in the deterministic game/playthrough boundaries.
- Targeting emits only identities, coordinates, order, or rotation supplied by the active typed request; the session validates the response before mutation.
- Battlefield textures, interpolation, camera focus, and overlays are disposable and never enter saves or combat truth.
- Retain battlefield nodes and media caches across updates; do not rebuild the tactical scene for each event or frame.
- Command availability, target sets, costs, masks, spell powers, Auto decisions, and inspection facts are supplied by the session. Presentation cannot infer or repair them.
- Secondary command, spell, item, inspection, and targeting modes preserve a visible Back or Cancel path and suppress spatial input until resolved.
- `CombatInteractionController.release()` is teardown-only: it releases the Fast Spell dock without emitting spellbook or layout changes. Ordinary `clear()` still restores the active application workspace.

## Work Guidance

- Keep rules-independent coordinate work in the geometry owner and exact media decoding in the cache.
- Begin layout work in `battle_interaction.tscn`, `combat_roster_spellbook.tscn`, or `fast_spell_dock.tscn`; scripts bind state and signals rather than constructing their hierarchy.

## Verification

- Run the combat-flow, presentation shell/system, and Realmz Builder preview suites after tactical presentation changes.
- Run `tools/combat_performance_probe.gd` after changing battlefield construction, targeting projection, or playback preparation.

## Child DOX Index
