# Shared game contracts

## Purpose

Own the small pure values that genuinely cross several game features or form a stable host-facing value boundary.

## Ownership

- `random/` owns deterministic `RealmzRng`, its saved state, and the scripted oracle source.
- `RealmzArithmetic` owns explicit signed and unsigned Classic integer conversion.
- `DomainEvent` carries detached committed-event data across the playthrough boundary.
- `GameState` is the thin save-owned aggregate that gathers feature state without re-owning feature behavior.
- `ConditionSet` is the reusable mutable condition value shared by characters and monsters.
- `ConditionRules` names the shared Classic condition slots and calculations interpreted by character, monster, combat, and magic features.
- `RealmzRules` is the narrow composition object that constructs and exposes the feature rule collaborators used by one session; behavior remains with those collaborators.
- `media/` owns immutable media descriptors and the read-only media-source port; adapters still own bytes and I/O.
- `presentation/` owns host presentation settings that never enter an adventure save.
- `view/` owns only the general detached `ActionAvailabilityView`, `DefinitionOptionView`, and `ViewChangeSet` atoms.
- `interactions/` owns the stable pure request/response envelopes, neutral bodies, and strict decoder registry consumed across runtime boundaries.

## Local Contracts

- Shared values are pure `RefCounted` or value-like records. They do not use Nodes, files, wall-clock time, or Godot randomness.
- Add a value here only when at least three features consume it or it defines one stable cross-boundary contract.
- Feature-specific state, rules, commands, request payloads, and continuation payloads remain in their named feature. Only the root `GameState` aggregate and genuinely cross-feature values belong here.
- RNG state and draw order are serializable and deterministic; diagnostic trace history is not save data.
- Media bytes remain adapter-owned. Presentation sees only `MediaAsset` and `MediaSource`.
- Presentation settings remain outside `GameSession` and `.r2save` data.
- Detached view atoms never expose mutable gameplay state.

## Work Guidance

- Prefer the owning feature whenever a concept has a natural home; do not use `shared` as a staging directory.
- Keep each contract small enough that its filename and class name explain its role without a facade or alias.

## Verification

- `tests/core/test_realmz_rng.gd` protects deterministic generator state and trace behavior.
- `tests/core/test_game_session.gd` and `tests/integration/test_session_persistence.gd` protect detached events, view changes, and saved RNG boundaries.
- `tests/infrastructure/test_package_repository.gd` protects the media-source boundary.
- `tests/presentation/test_classic_ui_system.gd` protects presentation-setting persistence and use.

## Child DOX Index

- `interactions/AGENTS.md` owns shared interaction envelopes, neutral bodies, and strict decoding.
