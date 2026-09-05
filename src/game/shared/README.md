# Shared game contracts

This folder is deliberately small. It contains the pure values that several Realmz systems need but no one feature can honestly own.

Start with `RealmzRng` when following a random decision. A `GameSession` owns one generator, saves only its generator state and draw count, and supplies it to workflows through `SessionContext`. `ScriptedRng` is the deterministic test and oracle source; production code never uses Godot randomness.

`RealmzArithmetic` makes Castle's signed 16-bit and 32-bit behavior explicit. `DomainEvent` is the detached record emitted after a gameplay mutation commits. `GameState` is the thin save-owned root that gathers the character party, world, combat, scenario, service, and wealth feature states without taking their behavior away from those features. `ConditionSet` is shared because the same mutable condition representation belongs to both characters and monsters, while `ConditionRules` names and interprets those shared slots. `RealmzRules` constructs the feature rule collaborators used by a session without re-owning their behavior. `ViewChangeSet` tells presentation which detached read-model domains changed without exposing mutable state. `ActionAvailabilityView` and `DefinitionOptionView` are the small general records reused by several screens.

The `media` folder defines `MediaAsset` and `MediaSource`, not archive or filesystem access. Storage adapters supply the bytes. The `presentation` folder contains host preferences such as scaling, typography, sound, and the last successfully started campaign identity; those settings never become adventure state. The `interactions` folder contains the stable request/response envelopes and strict wire decoders shared by scenario execution, playthrough, saves, and UI; feature-specific bodies remain with their game feature.

```text
feature rules and workflows
          |
          v
small shared value contract
          |
          v
playthrough, storage, or presentation adapter
```

Do not put a type here merely because two files use it. A feature-specific value belongs beside the feature that defines its meaning, and `GameState` must remain an aggregate rather than a second implementation of those features. The owning checks are `test_realmz_rng.gd`, `test_game_session.gd`, `test_session_persistence.gd`, `test_package_repository.gd`, and `test_classic_ui_system.gd`.
