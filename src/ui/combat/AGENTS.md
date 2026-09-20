# Combat presentation contract

## Purpose

Own the retained tactical battlefield, combat command deck, roster spellbook, Fast Spell dock, playback, and presentation-only targeting state.

## Ownership

- `ClassicBattlefieldPresenter` draws detached terrain, combatants, targets, fields, inspection aids, and playback frames.
- `BattlefieldPresentationGeometry` owns stateless viewport and coordinate calculations; `BattlefieldTextureCache` owns decoded tactical media reuse.
- `CombatPlaybackController` and `CombatPlaybackFrame` translate committed combat events into presentation timing and interpolation.
- `CombatTargetingRequest` and `CombatTargetingState` retain only the current presentation selection, hover, rotation, and inspection focus.
- `battle_interaction.tscn` owns the complete fixed command deck, initiative panel, secondary modes, targeting controls, and responsive Wide/Compact composition. `BattleInteraction` binds only request-supplied actions, targets, inspection facts, and typed responses; `BattleControllerCommandCatalog` projects those existing controls and Fast Spells into ordered radial entries.
- `BattlefieldInteractionController` translates tactical pointer, keyboard, and normalized controller input through the exact rendered camera transform. Its nested controller access owns movement-preview and inspection queries without widening the ordinary pointer interface. Controller movement stages one request-owned destination and cost before explicit confirmation; controller targeting keeps preview focus separate from ordered selected combatants or coordinates. `CombatInteractionController` coordinates the active battle request, command deck, targeting, roster spellbook, and Fast Spell dock without owning combat rules.
- `combat_roster_spellbook.tscn` owns the full-height memorized-spell chooser shown in the persistent party rail. `fast_spell_dock.tscn` owns the transient Alt-held shortcut surface. Both return the exact request-owned cast option through the normal command boundary.
- Battle initiative, spell-power, targeting, and Fast Spell collections instantiate only their exported row, button, or slot scenes.

## Local Contracts

- Combat legality, action cost, range, LOS, target relationships, movement paths, damage, and RNG remain in the deterministic game/playthrough boundaries.
- Targeting emits only identities, coordinates, order, or rotation supplied by the active typed request; the session validates the response before mutation.
- Battlefield textures, interpolation, camera focus, and overlays are disposable and never enter saves or combat truth.
- World-canvas zoom scales the retained battlefield presenter as one surface; visible-cell camera tracking, targeting, movement previews, and pointer hits continue to use its local 32-pixel coordinates.
- The battlefield's testing observation reports each detached monster's requested facing resource, exact resolved owner/hash, Castle's detached `lr` state (`-1` left, `0` neutral/vertical, `1` right), and legitimate base fallback without changing media selection or simulation. Movement and melee playback update that state at their causal boundaries; it is never serialized.
- Retain battlefield nodes and media caches across updates; do not rebuild the tactical scene for each event or frame.
- Command availability, target sets, costs, masks, spell powers, Auto decisions, and inspection facts are supplied by the session. Presentation cannot infer or repair them.
- Secondary command, spell, item, inspection, and targeting modes preserve a visible Back or Cancel path and suppress spatial input until resolved.
- A request-provided `prepare_projectile` action binds Fire directly to the typed Roll Power response. Presentation does not open an empty target picker or compute projectile power; the rerendered request supplies the targets derived from the saved roll.
- The action radial enumerates the active battle component's existing command owners and Fast Spell bindings. It invokes their typed presentation operations; it does not synthesize pointer input or infer availability.
- `CombatInteractionController.release()` is teardown-only: it releases the Fast Spell dock without emitting spellbook or layout changes. Ordinary `clear()` still restores the active application workspace.
- Playback frames carry event-local combatant positions, health, persistent fields, and lifecycle masks. A committed friendly swap changes both actor anchors in one frame before later attacks are located. Damage or healing appears on its result frame, a defeated target remains visible through that result and is removed on the following defeat boundary, and persistent fields appear or expire at their committed causal event rather than only in the final view.
- Default-off Hurry Spell Resolution coalesces only the shared effect frames of contiguous results from the same eligible area or group cast. Per-target results and deaths remain ordered, while intervening sounds, reactions, collisions, field changes, or lifecycle events end the group.

## Work Guidance

- Keep rules-independent coordinate work in the geometry owner and exact media decoding in the cache.
- Begin layout work in `battle_interaction.tscn`, `combat_roster_spellbook.tscn`, or `fast_spell_dock.tscn`; scripts bind state and signals rather than constructing their hierarchy.

## Verification

- Run the combat-flow, presentation shell/system, and Realmz Builder preview suites after tactical presentation changes.
- Run `tools/combat_performance_probe.gd` after changing battlefield construction, targeting projection, or playback preparation.

## Child DOX Index
