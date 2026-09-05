# Combat presentation contract

## Purpose

Own the retained tactical battlefield, combat playback, and presentation-only targeting state.

## Ownership

- `ClassicBattlefieldPresenter` draws detached terrain, combatants, targets, fields, inspection aids, and playback frames.
- `BattlefieldPresentationGeometry` owns stateless viewport and coordinate calculations; `BattlefieldTextureCache` owns decoded tactical media reuse.
- `CombatPlaybackController` and `CombatPlaybackFrame` translate committed combat events into presentation timing and interpolation.
- `CombatTargetingRequest` and `CombatTargetingState` retain only the current presentation selection, hover, rotation, and inspection focus.

## Local Contracts

- Combat legality, action cost, range, LOS, target relationships, movement paths, damage, and RNG remain in the deterministic game/playthrough boundaries.
- Targeting emits only identities, coordinates, order, or rotation supplied by the active typed request; the session validates the response before mutation.
- Battlefield textures, interpolation, camera focus, and overlays are disposable and never enter saves or combat truth.
- Retain battlefield nodes and media caches across updates; do not rebuild the tactical scene for each event or frame.

## Work Guidance

- Keep rules-independent coordinate work in the geometry owner and exact media decoding in the cache.
- Place stable combat controls in their owning scenes outside this renderer group; this folder owns the tactical visual surface and playback only.

## Verification

- Run the combat-flow, presentation shell/system, and Realmz Builder preview suites after tactical presentation changes.
- Run `tools/combat_performance_probe.gd` after changing battlefield construction, targeting projection, or playback preparation.

## Child DOX Index
